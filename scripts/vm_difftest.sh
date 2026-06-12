#!/bin/bash
# P-VM differential harness: every program must produce IDENTICAL output on
# the default engine (the bytecode VM since P-VM.3) and under IJ_VM=0 (the
# tree-walking eval escape hatch). Uses the committed binary both as the
# runtime under test and as the compile bridge -- valid because verify.sh
# check 5 enforces committed == true fixed point, so its emitted prelude
# contains the same VM.
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
    echo | "$bin" > "$tmp/${name}_vm.out" 2>&1 || true
    echo | IJ_VM=0 "$bin" > "$tmp/${name}_eval.out" 2>&1 || true
    if diff -q "$tmp/${name}_vm.out" "$tmp/${name}_eval.out" >/dev/null; then
        echo "PASS: $name (default VM == IJ_VM=0 eval)"
    else
        echo "FAIL: $name diverges between VM and IJ_VM=0 eval"
        diff "$tmp/${name}_vm.out" "$tmp/${name}_eval.out" | head -10
        fail=1
    fi
done

# 2) The interpreter itself (1-layer: binary runs interpreter.s programNode
#    through vmRunProgram by default, which interprets the test suite).
echo | ./scripts/native_interpreter.sh src/test.s > "$tmp/test_vm.out" 2>&1
echo | IJ_VM=0 ./scripts/native_interpreter.sh src/test.s > "$tmp/test_eval.out" 2>&1
if diff -q "$tmp/test_vm.out" "$tmp/test_eval.out" >/dev/null; then
    echo "PASS: test.s (default VM == IJ_VM=0 eval)"
else
    echo "FAIL: test.s diverges between VM and IJ_VM=0 eval"; fail=1
fi
echo hi | ./scripts/native_interpreter.sh src/sample.s > "$tmp/sample_vm.out" 2>&1
echo hi | IJ_VM=0 ./scripts/native_interpreter.sh src/sample.s > "$tmp/sample_eval.out" 2>&1
if diff -q "$tmp/sample_vm.out" "$tmp/sample_eval.out" >/dev/null; then
    echo "PASS: sample.s (default VM == IJ_VM=0 eval)"
else
    echo "FAIL: sample.s diverges between VM and IJ_VM=0 eval"; fail=1
fi

# 3) MCP overlay differential (added at P-VM.3 pre-flight): the concatenated
#    interpreter_base.s + eval.s + mcp.s source redefines gets/puts via the
#    override idiom, so its program chunk compiles func chunks for them --
#    a workload shape nothing in tests/vm covers. Built fresh from source
#    (honours IJ_BINARY) because the committed mcp binary can lag source.
#    This also guards the 2026-06-12 resolver regression (function-local
#    `let result` clobbering the top-level global via setTopLetGoVar).
MCP_INPUT='{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"x","version":"1"}},"jsonrpc":"2.0","id":0}
{"method":"tools/call","params":{"name":"execute_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":1}
{"method":"tools/call","params":{"name":"parse_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":2}'
cat src/interpreter.s | src/until.rb "interpreter is ready" > "$tmp/interpreter_base.s"
cat "$tmp/interpreter_base.s" src/eval.s src/mcp.s > "$tmp/mcp_eval.s"
if ./src/compile-local.sh "$tmp/mcp_eval.s" "$tmp/mcp_bin" >/dev/null 2>&1; then
    echo "$MCP_INPUT" | "$tmp/mcp_bin" 2>/dev/null > "$tmp/mcp_vm.out" || true
    echo "$MCP_INPUT" | IJ_VM=0 "$tmp/mcp_bin" 2>/dev/null > "$tmp/mcp_eval.out" || true
    if diff -q "$tmp/mcp_vm.out" "$tmp/mcp_eval.out" >/dev/null; then
        echo "PASS: mcp_eval (default VM == IJ_VM=0 eval)"
    else
        echo "FAIL: mcp_eval diverges between VM and IJ_VM=0 eval"
        diff "$tmp/mcp_vm.out" "$tmp/mcp_eval.out" | head -10
        fail=1
    fi
    if [ -f /tmp/ij-golden/mcp-native.out ] && ! diff -q "$tmp/mcp_vm.out" /tmp/ij-golden/mcp-native.out >/dev/null; then
        echo "FAIL: fresh mcp_eval default output diverges from golden"
        diff "$tmp/mcp_vm.out" /tmp/ij-golden/mcp-native.out | head -10
        fail=1
    fi
else
    echo "FAIL: compile mcp_eval.s"; fail=1
fi

# 4) Confirm the VM actually engages BY DEFAULT (guards a silently-dead or
#    inverted gate), and that IJ_VM=0 really opts out.
stats=$(echo | IJ_VM_DEBUG=1 ./scripts/native_interpreter.sh src/test.s 2>&1 >/dev/null | grep "program stmts" || true)
if [ -n "$stats" ]; then
    echo "PASS: VM engaged by default ($stats)"
else
    echo "FAIL: no [vm] debug stats on the default path -- gate dead or stage1 binary"; fail=1
fi
optout=$(echo | IJ_VM=0 IJ_VM_DEBUG=1 ./scripts/native_interpreter.sh src/test.s 2>&1 >/dev/null | grep "program stmts" || true)
if [ -z "$optout" ]; then
    echo "PASS: IJ_VM=0 opts out (no VM stats)"
else
    echo "FAIL: IJ_VM=0 still ran the VM ($optout)"; fail=1
fi

exit $fail
