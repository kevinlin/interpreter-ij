#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
(echo "//multiline" && cat $1 && echo "//<EOF>" && cat) | "$SCRIPT_DIR/interpreter.sh" "$SCRIPT_DIR/src/interpreter.s"
