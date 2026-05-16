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
  echo "-- interpreter.sh test.s --"
  { time (echo "hi" | "$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  echo "-- native_interpreter.sh src/test.s --"
  { time (echo "hi" | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/sample.s" >/dev/null); } 2>&1
  echo "-- selfhosted_interpreter.sh bench_eval.s --"
  { time (echo | "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/bench_eval.s" >/dev/null); } 2>&1
  echo "-- native_interpreter.sh bench_eval.s --"
  { time (echo | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/bench_eval.s" >/dev/null); } 2>&1
  echo
} | tee -a "$LOG"
