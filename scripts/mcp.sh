#!/bin/bash

# Claude Desktop Config
#{
#  "mcpServers": {
#    "ijscript": {
#      "command": "/.../mcp.sh",
#      "args": [],
#      "transport": {
#        "type": "stdio"
#      }
#    }
#  }
#}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
cat src/interpreter.s|src/until.rb "interpreter is ready" > interpreter_base.s
cat interpreter_base.s src/eval.s src/mcp.s > mcp_eval.s
"$SCRIPT_DIR/native_interpreter.sh" mcp_eval.s
