#!/bin/bash

# Transpile twice for real self-transpilation
src/compile-mac.sh src/interpreter.s interpreter_mac_arm64
src/compile-linux.sh src/interpreter.s interpreter_linux_amd64
src/compile-mac.sh src/interpreter.s interpreter_mac_arm64
src/compile-linux.sh src/interpreter.s interpreter_linux_amd64

echo|./interpreter.sh src/test.s

echo '{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-ai","version":"0.1.0"}},"jsonrpc":"2.0","id":0}'|mcp.sh

src/compile-mac.sh mcp_eval.s mcp_mac_arm64
src/compile-linux.sh mcp_eval.s mcp_linux_amd64

echo '{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-ai","version":"0.1.0"}},"jsonrpc":"2.0","id":0}'|native_mcp.sh
echo '{"method":"tools/call","params":{"name":"execute_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":7}'|native_mcp.sh
echo '{"method":"tools/call","params":{"name":"parse_script","arguments":{"script":"puts(1+22/7.0)"}},"jsonrpc":"2.0","id":7}'|native_mcp.sh
