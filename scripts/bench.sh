#!/bin/bash
# Benchmark the self-hosted interpreter and the native interpreter test run.
# Usage: ./bench.sh [label]
# Appends timings to bench.log.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LABEL="${1:-run}"
LOG="$ROOT_DIR/bench.log"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "=== $STAMP label=$LABEL ==="
  echo "-- selfhosted_interpreter.sh sample.s (stdin=hi) --"
  { time (echo "hi" | "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  echo "-- interpreter.sh sample.s --"
  { time (echo "hi" | "$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  echo "-- native_interpreter.sh sample.s --"
  { time (echo "hi" | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  # bench_eval.s (the eval-heavy secondary benchmark from spec §Phase 0) is intentionally
  # NOT timed here: Phase 2 codegen makes selfhosted run >5min, which drowns the primary
  # signal. Revisit only after the primary sample.s bench hits the 10x target.
  echo
} | tee -a "$LOG"
