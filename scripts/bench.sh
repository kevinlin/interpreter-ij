#!/bin/bash
# Benchmark the self-hosted interpreter and the native interpreter test run.
#
# Usage:
#   ./bench.sh [label]                  # default: committed binary, single run
#   ./bench.sh --fresh [label]          # build src/interpreter.s -> /tmp/ij-fresh, bench THAT
#   ./bench.sh --repeat N [label]       # run selfhost block N times, report min/median/max
#   ./bench.sh --fresh --repeat 3 label # combine
#
# WHY: the committed binary is frozen (ac2e6f3); without --fresh the bench
# measures it, not your source changes (the gating-deadlock described in
# IMPLEMENTATION_PLAN.md P-A / specs/bench-methodology.md). Single-run wall time
# also has a ~1.55x noise band > the 1.3x drop-rule, so use --repeat for any
# perf decision; min-of-N under GOMAXPROCS=1 is the headline (noise is one-sided).
#
# Appends timings to bench.log.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

FRESH=0
REPEAT=1
LABEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)      FRESH=1; shift ;;
    --repeat)     REPEAT="$2"; shift 2 ;;
    --repeat=*)   REPEAT="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)            LABEL="$1"; shift ;;
  esac
done
LABEL="${LABEL:-run}"
LOG="$ROOT_DIR/bench.log"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! [[ "$REPEAT" =~ ^[0-9]+$ && "$REPEAT" -ge 1 ]]; then
  echo "bench.sh: --repeat needs a positive integer (got '$REPEAT')" >&2
  exit 2
fi

# --fresh: build the TRUE FIXED POINT of the current source and point the whole
# nested self-host stack at it via IJ_BINARY (honoured by native_interpreter.sh).
#
# Why two stages, not one: a single `compile-local src/interpreter.s` uses the
# committed (frozen, pre-Run-N+6) bridge, whose functionDeclarationToGo emits no
# `staticImpl` field — so stage1 is parity-blind to the closure-body-hoist work
# (IMPLEMENTATION_PLAN.md §1). Only stage2 (built BY stage1, whose emitter does
# add staticImpl) exercises the current source's codegen. Benching stage1 would
# report ~parity and hide exactly the source work --fresh exists to reveal.
#
# compile-local.sh is the non-Docker path that exits non-zero on failure (the
# Docker path silently skips the build and masks regressions). The IJ_BINARY
# bridge override builds the fixed point without ever touching the committed
# binary.
if [[ $FRESH -eq 1 ]]; then
  echo "bench.sh --fresh: stage1 (committed bridge) -> /tmp/ij-fresh-s1 ..." >&2
  ( unset IJ_BINARY; "$ROOT_DIR/src/compile-local.sh" "$ROOT_DIR/src/interpreter.s" /tmp/ij-fresh-s1 ) >&2
  echo "bench.sh --fresh: stage2 (stage1 bridge, fixed point) -> /tmp/ij-fresh ..." >&2
  IJ_BINARY=/tmp/ij-fresh-s1 "$ROOT_DIR/src/compile-local.sh" "$ROOT_DIR/src/interpreter.s" /tmp/ij-fresh >&2
  export IJ_BINARY=/tmp/ij-fresh
  echo "bench.sh --fresh: benching fixed-point stage2 IJ_BINARY=$IJ_BINARY" >&2
fi

# One GOMAXPROCS=1 selfhost run; prints "<real> <user>" seconds.
# GC background + sysmon threads are ~33% of stage2 wall and the dominant
# variance source, so pin to one P for cross-run comparability.
run_selfhost_pinned() {
  local tf; tf="$(mktemp)"
  { TIMEFORMAT='%R %U'; time ( echo "hi" | GOMAXPROCS=1 "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null ); } 2> "$tf"
  tr '\n' ' ' < "$tf"; echo
  rm -f "$tf"
}

aggregate() {
  # stdin: lines of "<real> <user>"; emit min/median/max for each.
  python3 -c '
import sys, statistics
real, user = [], []
for ln in sys.stdin:
    p = ln.split()
    if len(p) >= 2:
        real.append(float(p[0])); user.append(float(p[1]))
def fmt(xs):
    return "min=%.2fs median=%.2fs max=%.2fs" % (min(xs), statistics.median(xs), max(xs))
print("  real: %s" % fmt(real))
print("  user: %s" % fmt(user))
print("  headline (min real, GOMAXPROCS=1): %.2fs over %d run(s)" % (min(real), len(real)))
'
}

{
  echo "=== $STAMP label=$LABEL fresh=$FRESH repeat=$REPEAT${IJ_BINARY:+ binary=$IJ_BINARY} ==="

  if [[ $REPEAT -gt 1 ]]; then
    echo "-- selfhosted_interpreter.sh sample.s (stdin=hi, GOMAXPROCS=1, repeat=$REPEAT) --"
    samples=()
    for ((i=1; i<=REPEAT; i++)); do
      line="$(run_selfhost_pinned)"
      echo "  run $i: real=${line%% *}s user=$(echo "$line" | awk '{print $2}')s"
      samples+=("$line")
    done
    printf '%s\n' "${samples[@]}" | aggregate
  else
    # Default single-run path (committed binary unless --fresh). Quick smoke
    # check only — unreliable for perf decisions; use --repeat for those.
    echo "-- selfhosted_interpreter.sh sample.s (stdin=hi) --"
    { time (echo "hi" | "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  fi

  echo "-- interpreter.sh sample.s --"
  { time (echo "hi" | "$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  echo "-- native_interpreter.sh sample.s --"
  { time (echo "hi" | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  # bench_eval.s (the eval-heavy secondary benchmark from spec §Phase 0) is intentionally
  # NOT timed here: Phase 2 codegen makes selfhosted run >5min, which drowns the primary
  # signal. Revisit only after the primary sample.s bench hits the 10x target.
  echo
} | tee -a "$LOG"
