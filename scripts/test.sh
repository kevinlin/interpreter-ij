#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
echo|"$SCRIPT_DIR/interpreter.sh" "$ROOT_DIR/src/test.s"
