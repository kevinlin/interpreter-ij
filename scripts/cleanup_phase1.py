#!/usr/bin/env python3
"""Phase 1 Cleanup: Remove old Value types, rename Value2->Value in interpreter.s.

Idempotent. Run from project root:
  python3 scripts/cleanup_phase1.py
"""

import sys
import os


def _bool_helpers_puts():
    """Return puts() calls for Value-tagged-union bool helpers (post-rename names)."""
    lines = [
        'puts("// --- bool helpers (Value tagged-union) ---");',
        'puts("func EqualsBool(a, b Value) bool {");',
        'puts("if a.tag != b.tag { return false }");',
        'puts("switch a.tag {");',
        'puts("case tInt: return a.i == b.i");',
        'puts("case tDouble: return a.d == b.d");',
        'puts("case tString: return a.s == b.s");',
        'puts("case tBool: return a.b == b.b");',
        'puts("case tNull: return true");',
        'puts("}");',
        'puts("return false");',
        'puts("}");',
        'puts("func NotEqualsBool(a, b Value) bool { return !EqualsBool(a, b) }");',
        'puts("func LessThanBool(a, b Value) bool {");',
        'puts("if a.tag == tInt && b.tag == tInt { return a.i < b.i }");',
        'puts("if a.tag == tDouble && b.tag == tDouble { return a.d < b.d }");',
        'puts("return a.LessThan(b).b");',
        'puts("}");',
        'puts("func LessThanEqualBool(a, b Value) bool {");',
        'puts("if a.tag == tInt && b.tag == tInt { return a.i <= b.i }");',
        'puts("if a.tag == tDouble && b.tag == tDouble { return a.d <= b.d }");',
        'puts("return a.LessThanEqual(b).b");',
        'puts("}");',
        'puts("func BiggerThanBool(a, b Value) bool {");',
        'puts("if a.tag == tInt && b.tag == tInt { return a.i > b.i }");',
        'puts("if a.tag == tDouble && b.tag == tDouble { return a.d > b.d }");',
        'puts("return a.BiggerThan(b).b");',
        'puts("}");',
        'puts("func BiggerThanEqualBool(a, b Value) bool {");',
        'puts("if a.tag == tInt && b.tag == tInt { return a.i >= b.i }");',
        'puts("if a.tag == tDouble && b.tag == tDouble { return a.d >= b.d }");',
        'puts("return a.BiggerThanEqual(b).b");',
        'puts("}");',
        'puts("");',
    ]
    return "\n".join(lines)


def cleanup(content: str) -> str:
    # === STEP 1: Remove old registerLibraryFunctions (uses *Context, *ArrayValue, Value) ===
    old_rlf_start = content.find('puts("func registerLibraryFunctions(ctx *Context) {");')
    # Marker: counter vars right after registerLibraryFunctions closes
    old_rlf_end_marker = 'puts("var ijCountNewContext uint64");'
    old_rlf_end = content.find(old_rlf_end_marker)
    if old_rlf_start != -1 and old_rlf_end != -1:
        # Also eat the preceding blank puts("") line
        blank_marker = '\nputs("");\nputs("func registerLibraryFunctions(ctx *Context) {")'
        blank_idx = content.find(blank_marker)
        if blank_idx != -1:
            old_rlf_start = blank_idx + len('\nputs("");\n')
        content = content[:old_rlf_start] + content[old_rlf_end:]
        print("  Removed old registerLibraryFunctions block")
    else:
        print("  WARNING: old registerLibraryFunctions markers not found")

    # === STEP 1.5: Remove old Context/Command/FunctionCommand block ===
    # The old Context has "inlineLen" field (unique marker). This block sits between
    # the counter variables and the new registerLibraryFunctions2.
    old_ctx_marker = 'puts("type Context struct {");\nputs("parent    *Context");\nputs("variables map[string]Value");\nputs("inlineLen int");'
    old_ctx_idx = content.find(old_ctx_marker)
    new_rlf_marker = 'puts("func registerLibraryFunctions2(ctx2 *Context2) {");'
    new_rlf_idx = content.find(new_rlf_marker)
    if old_ctx_idx != -1 and new_rlf_idx != -1 and old_ctx_idx < new_rlf_idx:
        # Eat preceding blank puts("") line
        before = content[:old_ctx_idx]
        if before.endswith('puts("");\n'):
            old_ctx_idx -= len('puts("");\n')
        content = content[:old_ctx_idx] + content[new_rlf_idx:]
        print("  Removed old Context/Command/FunctionCommand block")
    else:
        print("  WARNING: old Context/Command/FunctionCommand markers not found")

    # === STEP 2: Remove old type system (Value interface through NullValue methods) ===
    old_types_start = content.find('puts("type Value interface {");')
    old_types_end_marker = 'puts("func main() {");'
    old_types_end = content.find(old_types_end_marker)
    if old_types_start != -1 and old_types_end != -1:
        # Eat preceding blank puts("") line
        before = content[:old_types_start]
        if before.endswith('puts("");\n'):
            old_types_start -= len('puts("");\n')
        content = content[:old_types_start] + content[old_types_end:]
        print("  Removed old type system block")
    else:
        print("  WARNING: old type system markers not found")

    # === STEP 3: Update main() (pre-rename names) ===
    content = content.replace(
        'puts("ctx := NewContext(nil)");\nputs("registerLibraryFunctions(ctx)");\n',
        ''
    )
    content = content.replace(
        'puts("ctx2 := NewContext2(nil)");',
        'puts("ctx := NewContext(nil)");'
    )
    content = content.replace(
        'puts("registerLibraryFunctions2(ctx2)");',
        'puts("registerLibraryFunctions(ctx)");'
    )
    content = content.replace(
        'puts("_ = ctx");\nputs("_ = ctx2");\n',
        'puts("_ = ctx");\n'
    )
    content = content.replace(
        'puts("var result Value2 = v2Null()");',
        'puts("var result Value = vNull()");'
    )
    print("  Updated main() function")

    # === STEP 4: Apply renames (longest names first to avoid partial matches) ===
    renames = [
        ("NewStaticFunctionCommand2", "NewStaticFunctionCommand"),
        ("FunctionCommand2", "FunctionCommand"),
        ("KeyValuePair2", "KeyValuePair"),
        ("ArrayValue2", "ArrayValue"),
        ("MapValue2", "MapValue"),
        ("Context2", "Context"),
        ("Command2", "Command"),
        ("Value2", "Value"),
        ("registerLibraryFunctions2", "registerLibraryFunctions"),
        ("NewContext2", "NewContext"),
        ("v2Null", "vNull"),
        ("v2Bool", "vBool"),
        ("v2Int", "vInt"),
        ("v2Double", "vDouble"),
        ("v2String", "vString"),
        ("v2Array", "vArray"),
        ("v2Map", "vMap"),
        ("v2Func", "vFunc"),
        ("v2Invalid", "vInvalid"),
        ("t2Null", "tNull"),
        ("t2Int", "tInt"),
        ("t2Double", "tDouble"),
        ("t2String", "tString"),
        ("t2Bool", "tBool"),
        ("t2Array", "tArray"),
        ("t2Map", "tMap"),
        ("t2Func", "tFunc"),
        ("t2Named", "tNamed"),
        ("t2Invalid", "tInvalid"),
        ("ctx2", "ctx"),
    ]

    for old, new in renames:
        count = content.count(old)
        if count > 0:
            content = content.replace(old, new)
            print(f"  Renamed: {old} -> {new} ({count} occurrences)")

    # === STEP 5: Insert bool helpers before main() ===
    bool_helpers_block = _bool_helpers_puts()
    main_marker = 'puts("func main() {");'
    main_idx = content.find(main_marker)
    if main_idx != -1:
        content = content[:main_idx] + bool_helpers_block + "\n" + content[main_idx:]
        print("  Inserted Value bool helpers before main()")
    else:
        print("  WARNING: main() marker not found for bool helper insertion")

    return content


def main():
    filepath = "src/interpreter.s"
    if not os.path.exists(filepath):
        print(f"ERROR: {filepath} not found. Run from project root.")
        sys.exit(1)

    # Backup
    with open(filepath, "r") as f:
        original = f.read()
    bak_path = filepath + ".pre_cleanup_bak"
    with open(bak_path, "w") as f:
        f.write(original)
    print(f"Backed up to {bak_path}")

    result = cleanup(original)

    with open(filepath, "w") as f:
        f.write(result)
    print(f"Wrote cleaned {filepath}")


if __name__ == "__main__":
    main()
