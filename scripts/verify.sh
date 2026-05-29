#!/bin/bash
# 5-check regression harness for the C/D performance phases.
# Assumes golden outputs exist at /tmp/ij-golden/ (run `./verify.sh --capture` once to create).
#
# Usage:
#   ./verify.sh           -> run all 5 checks against current binaries
#   ./verify.sh --capture -> capture golden outputs from current binaries
#
# Exits non-zero on any regression.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GOLDEN=/tmp/ij-golden
MCP_INPUT='{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"x","version":"1"}},"jsonrpc":"2.0","id":0}
{"method":"tools/call","params":{"name":"execute_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":1}
{"method":"tools/call","params":{"name":"parse_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":2}'

if [[ "${1:-}" == "--capture" ]]; then
    mkdir -p "$GOLDEN"
    echo | "$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/test.s" > "$GOLDEN/test.out" 2>&1
    echo hi | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/sample.s" > "$GOLDEN/sample.out" 2>&1
    echo "$MCP_INPUT" | "$SCRIPT_DIR/mcp.sh" 2>/dev/null > "$GOLDEN/mcp-interp.out"
    echo "$MCP_INPUT" | "$SCRIPT_DIR/native_mcp.sh" 2>/dev/null > "$GOLDEN/mcp-native.out"
    echo "captured goldens:"
    wc -l "$GOLDEN"/*.out
    exit 0
fi

fail=0
pass=0
note() { echo "[verify] $*"; }
ok()   { echo "  PASS: $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $*"; fail=$((fail+1)); }

# 1. test.s interpreted -> all tests pass, byte-identical to golden.
note "1/5 test.s (interpreted)"
tmp=$(mktemp)
echo | "$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/test.s" > "$tmp" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then bad "interpreter.sh test.s exit=$rc"
elif grep -E -iq 'fail|panic|error' "$tmp"; then bad "test.s output contains fail/panic/error"; grep -E -i 'fail|panic|error' "$tmp" | head -3
elif ! diff -q "$GOLDEN/test.out" "$tmp" >/dev/null; then bad "test.s output diverges from golden"; diff "$GOLDEN/test.out" "$tmp" | head -20
else ok "test.s matches golden"; fi
rm -f "$tmp"

# 2. test.s self-hosted -> same output.
note "2/5 test.s (self-hosted)"
tmp=$(mktemp)
echo | "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/test.s" > "$tmp" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then bad "selfhosted_interpreter.sh test.s exit=$rc"
elif ! diff -q "$GOLDEN/test.out" "$tmp" >/dev/null; then bad "self-hosted test.s diverges"; diff "$GOLDEN/test.out" "$tmp" | head -20
else ok "self-hosted test.s matches golden"; fi
rm -f "$tmp"

# 3. sample.s self-hosted (the real perf target).
note "3/5 sample.s (self-hosted)"
tmp=$(mktemp)
echo hi | "$SCRIPT_DIR/selfhosted_interpreter.sh" "$ROOT_DIR/src/sample.s" > "$tmp" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then bad "selfhosted sample.s exit=$rc"; head -5 "$tmp"
elif ! diff -q "$GOLDEN/sample.out" "$tmp" >/dev/null; then bad "self-hosted sample.s diverges"; diff "$GOLDEN/sample.out" "$tmp" | head -20
else ok "self-hosted sample.s matches golden"; fi
rm -f "$tmp"

# 4. MCP native vs golden (both interpreted and native should still match).
note "4/5 MCP native"
tmp=$(mktemp)
echo "$MCP_INPUT" | "$SCRIPT_DIR/native_mcp.sh" 2>/dev/null > "$tmp"
if ! diff -q "$GOLDEN/mcp-native.out" "$tmp" >/dev/null; then bad "native MCP diverges from golden"; diff "$GOLDEN/mcp-native.out" "$tmp" | head -10
else ok "native MCP matches golden"; fi
rm -f "$tmp"

# 5. TRUE self-transpile fixed point. Two layers of guarantee:
#    (a) determinism  : interpreter.s -> Xa, interpreter.s -> Xb, Xa == Xb.
#    (b) fixed point   : committed binary == Xa (the committed bridge, used to
#        transpile interpreter.s, reproduces ITSELF byte-for-byte).
#    Until 2026-05-29 this only checked (a). Determinism is necessary but NOT
#    sufficient — the frozen pre-replace bridge was deterministic yet emitted an
#    OLD shape no current source could reproduce (a one-way bridge). Now that the
#    committed binary IS the true fixed point (stage2, replaced 2026-05-29), (b)
#    is enforceable and catches a stale committed bridge immediately.
note "5/5 true self-transpile fixed-point"
case "$(uname -s)" in Linux) OS_NAME=linux ;; Darwin) OS_NAME=mac ;; *) OS_NAME=unknown ;; esac
case "$(uname -m)" in x86_64) ARCH_NAME=amd64 ;; arm64|aarch64) ARCH_NAME=arm64 ;; *) ARCH_NAME=unknown ;; esac
COMMITTED="$ROOT_DIR/interpreter_${OS_NAME}_${ARCH_NAME}"
if "$ROOT_DIR/src/compile-local.sh" "$ROOT_DIR/src/interpreter.s" /tmp/ij-golden/_roundtrip_a >/tmp/rt1.log 2>&1 \
   && "$ROOT_DIR/src/compile-local.sh" "$ROOT_DIR/src/interpreter.s" /tmp/ij-golden/_roundtrip_b >/tmp/rt2.log 2>&1; then
    if ! diff -q /tmp/ij-golden/_roundtrip_a /tmp/ij-golden/_roundtrip_b >/dev/null; then
        bad "non-deterministic: transpile output differs $(wc -c </tmp/ij-golden/_roundtrip_a) vs $(wc -c </tmp/ij-golden/_roundtrip_b)"
    elif [[ ! -x "$COMMITTED" ]]; then
        bad "committed binary $COMMITTED missing — cannot check fixed point"
    elif ! diff -q "$COMMITTED" /tmp/ij-golden/_roundtrip_a >/dev/null; then
        bad "NOT a fixed point: committed binary != self-transpile output ($(wc -c <"$COMMITTED") vs $(wc -c </tmp/ij-golden/_roundtrip_a)) — committed bridge is stale, rebuild+replace it"
    else
        ok "true fixed point: committed binary == self-transpile output (bit-identical)"
    fi
else
    bad "compile-local.sh failed"
    tail -5 /tmp/rt2.log 2>/dev/null
fi

echo "[verify] $pass pass, $fail fail"
exit $fail
