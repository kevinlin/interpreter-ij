#!/bin/bash
# P-VM differential harness: every program must produce IDENTICAL output with
# and without IJ_VM=1. Uses the committed binary both as the runtime under
# test and as the compile bridge -- valid because verify.sh check 5 enforces
# committed == true fixed point, so its emitted prelude contains the same VM.
#
# NOTE (stage gotcha, AGENTS.md): after editing src/interpreter.s you must
# rebuild the fixed point and replace the committed binary (or pass
# IJ_BINARY=<stage2>) before this harness exercises NEW runtime behaviour --
# a stage1 build is parity-blind for runtime features.
#
# Usage: scripts/vm_difftest.sh   (exits non-zero on any divergence)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1) Compiled VM test programs (function chunks + abort paths).
for t in tests/vm/vmtest*.s; do
    name=$(basename "$t" .s)
    bin="$tmp/${name}_bin"
    if ! ./src/compile-local.sh "$t" "$bin" >/dev/null 2>&1; then
        echo "FAIL: compile $t"; fail=1; continue
    fi
    echo | "$bin" > "$tmp/${name}_default.out" 2>&1 || true
    echo | IJ_VM=1 "$bin" > "$tmp/${name}_vm.out" 2>&1 || true
    if diff -q "$tmp/${name}_default.out" "$tmp/${name}_vm.out" >/dev/null; then
        echo "PASS: $name (IJ_VM == default)"
    else
        echo "FAIL: $name diverges under IJ_VM=1"
        diff "$tmp/${name}_default.out" "$tmp/${name}_vm.out" | head -10
        fail=1
    fi
done

# 2) The interpreter itself under the VM (1-layer: binary runs interpreter.s
#    programNode through vmRunProgram, which interprets the test suite).
echo | ./scripts/native_interpreter.sh src/test.s > "$tmp/test_default.out" 2>&1
echo | IJ_VM=1 ./scripts/native_interpreter.sh src/test.s > "$tmp/test_vm.out" 2>&1
if diff -q "$tmp/test_default.out" "$tmp/test_vm.out" >/dev/null; then
    echo "PASS: test.s (IJ_VM == default)"
else
    echo "FAIL: test.s diverges under IJ_VM=1"; fail=1
fi
echo hi | ./scripts/native_interpreter.sh src/sample.s > "$tmp/sample_default.out" 2>&1
echo hi | IJ_VM=1 ./scripts/native_interpreter.sh src/sample.s > "$tmp/sample_vm.out" 2>&1
if diff -q "$tmp/sample_default.out" "$tmp/sample_vm.out" >/dev/null; then
    echo "PASS: sample.s (IJ_VM == default)"
else
    echo "FAIL: sample.s diverges under IJ_VM=1"; fail=1
fi

# 3) Confirm the VM actually engaged (guards against a silently-dead gate).
stats=$(echo | IJ_VM=1 IJ_VM_DEBUG=1 ./scripts/native_interpreter.sh src/test.s 2>&1 >/dev/null | grep "program stmts" || true)
if [ -n "$stats" ]; then
    echo "PASS: VM engaged ($stats)"
else
    echo "FAIL: no [vm] debug stats -- IJ_VM gate dead or stage1 binary"; fail=1
fi

exit $fail
