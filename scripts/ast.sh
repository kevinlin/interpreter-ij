#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
(echo "//multiline" && cat $1 && echo "//<AST>") | "$SCRIPT_DIR/native_interpreter.sh" "$ROOT_DIR/src/interpreter.s"
