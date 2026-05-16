#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Transpile twice for real self-transpilation
"$ROOT_DIR/src/compile-mac.sh" "$ROOT_DIR/src/interpreter.s" "$ROOT_DIR/interpreter_mac_arm64"
"$ROOT_DIR/src/compile-linux.sh" "$ROOT_DIR/src/interpreter.s" "$ROOT_DIR/interpreter_linux_amd64"
"$ROOT_DIR/src/compile-mac.sh" "$ROOT_DIR/src/interpreter.s" "$ROOT_DIR/interpreter_mac_arm64"
"$ROOT_DIR/src/compile-linux.sh" "$ROOT_DIR/src/interpreter.s" "$ROOT_DIR/interpreter_linux_amd64"

echo|"$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/test.s"

echo '{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-ai","version":"0.1.0"}},"jsonrpc":"2.0","id":0}'|"$SCRIPT_DIR/mcp.sh"

"$ROOT_DIR/src/compile-mac.sh" "$ROOT_DIR/mcp_eval.s" "$ROOT_DIR/mcp_mac_arm64"
"$ROOT_DIR/src/compile-linux.sh" "$ROOT_DIR/mcp_eval.s" "$ROOT_DIR/mcp_linux_amd64"

echo '{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-ai","version":"0.1.0"}},"jsonrpc":"2.0","id":0}'|"$SCRIPT_DIR/native_mcp.sh"
echo '{"method":"tools/call","params":{"name":"execute_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":7}'|"$SCRIPT_DIR/native_mcp.sh"
echo '{"method":"tools/call","params":{"name":"parse_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":7}'|"$SCRIPT_DIR/native_mcp.sh"
