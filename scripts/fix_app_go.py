#!/usr/bin/env python3
"""Bridge post-processor: fix old-type references in app.go emitted by the legacy
pre-cleanup native binary. Rewrites old type system + Value2 -> clean Value.

The legacy binary emits its compiled-in goLibPrefix which has BOTH:
  - Old Value interface + per-type structs (NullValue, IntValue, ...)
  - Value2 tagged-union struct + helpers
  - Old registerLibraryFunctions (uses *Context, *ArrayValue, Value interface)
  - registerLibraryFunctions2 (uses *Context2, *ArrayValue2, Value2)

This script removes the old type system and renames Value2->Value everywhere.

Usage: python3 scripts/fix_app_go.py app.go [--in-place]
"""

import re
import sys


def _replace_outside_strings(line: str, old: str, new: str) -> str:
    """Replace `old` with `new` only when NOT inside a Go string literal ("...")."""
    result = []
    i = 0
    in_string = False
    while i < len(line):
        if not in_string and line[i:i+len(old)] == old:
            result.append(new)
            i += len(old)
        else:
            if line[i] == '"' and (i == 0 or line[i-1] != '\\'):
                in_string = not in_string
            result.append(line[i])
            i += 1
    return ''.join(result)


def fix_app_go(content: str) -> str:
    # === STEP 1: Remove old registerLibraryFunctions ===
    # The legacy binary emits counter vars AFTER old registerLibraryFunctions.
    # In the cleaned fb2b299+ binary, counter vars come BEFORE the single
    # registerLibraryFunctions. Only do the removal when counter vars follow
    # registerLibraryFunctions (old layout); otherwise skip.
    old_rlf_start = content.find("\nfunc registerLibraryFunctions(ctx *Context) {")
    old_rlf_end_marker = "\nvar ijCountNewContext uint64\n"
    old_rlf_end = content.find(old_rlf_end_marker)
    if old_rlf_start != -1 and old_rlf_end != -1 and old_rlf_end > old_rlf_start:
        content = content[:old_rlf_start] + content[old_rlf_end:]
        print("  Removed old registerLibraryFunctions")

    # === STEP 2: Remove old type system ===
    # Remove everything from "type Value interface {" to just before "func main() {"
    old_types_start = content.find("\ntype Value interface {")
    # The counter vars, old Context type, old Command/FunctionCommand, old Value interface,
    # old per-type structs, old bool helpers, old NullValue — all sit between the
    # end of Value2 helpers and main().
    # We remove from the FIRST old-type marker after Value2 section to just before main().
    # The old Context/Command/FunctionCommand sits just after counter vars and before
    # the new registerLibraryFunctions2.

    # First, remove old Context/Command/FunctionCommand block (between counter vars
    # and registerLibraryFunctions2). The old Context has "inlineLen" field.
    old_ctx_start = content.find("\ntype Context struct {\nparent    *Context\nvariables map[string]Value\ninlineLen int")
    if old_ctx_start != -1:
        # Find the next occurrence of "func registerLibraryFunctions2"
        rlf2_marker = "\nfunc registerLibraryFunctions2(ctx2 *Context2) {"
        rlf2_idx = content.find(rlf2_marker, old_ctx_start)
        if rlf2_idx != -1:
            content = content[:old_ctx_start] + content[rlf2_idx:]
            print("  Removed old Context/Command/FunctionCommand block")

    # Now remove old Value interface through NullValue
    old_types_start = content.find("\ntype Value interface {")
    main_marker = "\nfunc main() {"
    main_idx = content.find(main_marker)
    if old_types_start != -1 and main_idx != -1 and old_types_start < main_idx:
        content = content[:old_types_start] + content[main_idx:]
        print("  Removed old Value interface + per-type structs")

    # === STEP 3: Rename Value2 -> Value everywhere ===
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
        content = content.replace(old, new)

    print("  Renamed Value2->Value and related types")

    # === STEP 4: Add bool helpers before main() (unconditional — old ones removed) ===
    bool_helpers = (
        "// --- bool helpers (Value tagged-union) ---\n"
        "func EqualsBool(a, b Value) bool {\n"
        "if a.tag != b.tag { return false }\n"
        "switch a.tag {\n"
        "case tInt: return a.i == b.i\n"
        "case tDouble: return a.d == b.d\n"
        "case tString: return a.s == b.s\n"
        "case tBool: return a.b == b.b\n"
        "case tNull: return true\n"
        "}\n"
        "return false\n"
        "}\n"
        "func NotEqualsBool(a, b Value) bool { return !EqualsBool(a, b) }\n"
        "func LessThanBool(a, b Value) bool {\n"
        "if a.tag == tInt && b.tag == tInt { return a.i < b.i }\n"
        "if a.tag == tDouble && b.tag == tDouble { return a.d < b.d }\n"
        "return a.LessThan(b).b\n"
        "}\n"
        "func LessThanEqualBool(a, b Value) bool {\n"
        "if a.tag == tInt && b.tag == tInt { return a.i <= b.i }\n"
        "if a.tag == tDouble && b.tag == tDouble { return a.d <= b.d }\n"
        "return a.LessThanEqual(b).b\n"
        "}\n"
        "func BiggerThanBool(a, b Value) bool {\n"
        "if a.tag == tInt && b.tag == tInt { return a.i > b.i }\n"
        "if a.tag == tDouble && b.tag == tDouble { return a.d > b.d }\n"
        "return a.BiggerThan(b).b\n"
        "}\n"
        "func BiggerThanEqualBool(a, b Value) bool {\n"
        "if a.tag == tInt && b.tag == tInt { return a.i >= b.i }\n"
        "if a.tag == tDouble && b.tag == tDouble { return a.d >= b.d }\n"
        "return a.BiggerThanEqual(b).b\n"
        "}\n\n"
    )

    # === STEP 5: Add AsValue wrappers + bool helpers before main() ===
    # Only add if not already present (new binary already has them).
    wrappers = (
        "func NewMapValueAsValue(pairs ...KeyValuePair) Value {\n"
        "\treturn Value{tag: tMap, m: NewMapValue(pairs...)}\n"
        "}\n"
        "func NewArrayValueAsValue(elements ...Value) Value {\n"
        "\treturn Value{tag: tArray, arr: NewArrayValue(elements...)}\n"
        "}\n\n"
    )
    # Only inject bool helpers if not already in the preamble
    if "func EqualsBool(a, b Value) bool" not in content[:content.find("\nfunc main() {")]:
        content = content.replace(
            "\nfunc main() {", "\n" + bool_helpers + "func main() {"
        )
    # Only inject AsValue wrappers if not already present
    if "func NewArrayValueAsValue" not in content[:content.find("\nfunc main() {")]:
        content = content.replace(
            "\nfunc main() {", "\n" + wrappers + "func main() {"
        )

    # === STEP 6: Split at main() — rewrite body only ===
    idx = content.find("\nfunc main() {")
    if idx == -1:
        return content
    preamble = content[:idx]
    body = content[idx:]

    # Protect .Execute(ctx, NewArrayValue/NewMapValue) — these need *ArrayValue/*MapValue.
    body = body.replace(".Execute(ctx, NewArrayValue(", ".Execute(ctx, __TMP_NEWARR__")
    body = body.replace(".Execute(ctx, NewMapValue(", ".Execute(ctx, __TMP_NEWMAP__")

    # In body: NewMapValue -> NewMapValueAsValue.
    # Process line-by-line, skipping occurrences inside Go string literals.
    body_lines = body.split("\n")
    for i, line in enumerate(body_lines):
        body_lines[i] = _replace_outside_strings(line, "NewMapValue(", "NewMapValueAsValue(")
    body = "\n".join(body_lines)

    # NewArrayValue -> NewArrayValueAsValue.
    body_lines = body.split("\n")
    for i, line in enumerate(body_lines):
        body_lines[i] = _replace_outside_strings(line, "NewArrayValue(", "NewArrayValueAsValue(")
    body = "\n".join(body_lines)

    # Restore protected Execute calls.
    body = body.replace(".Execute(ctx, __TMP_NEWARR__", ".Execute(ctx, NewArrayValue(")
    body = body.replace(".Execute(ctx, __TMP_NEWMAP__", ".Execute(ctx, NewMapValue(")

    # Fix result=NewNullValue() -> result=vNull()
    body = body.replace("result=NewNullValue()", "result=vNull()")

    # Fix remaining var X Value = declarations
    body = re.sub(r"\bvar (\w+) Value =", r"var \1 Value =", body)

    content = preamble + body

    # === STEP 7: Fix specific issues ===
    # 7a. ValueToOld stub returns nil — Value is now a struct
    content = content.replace(
        'func ValueToOld(v Value) Value { return nil }',
        'func ValueToOld(v Value) Value { return Value{} }'
    )
    # 7c. Fix NewArrayValue nil values: when called with no args (new binary
    #     evalCall creates args for zero-arg calls), the values slice is nil
    #     and library functions panic on params.Get(...). Ensure non-nil.
    content = content.replace(
        'func NewArrayValue(elements ...Value) *ArrayValue {\nreturn &ArrayValue{values: elements}\n}',
        'func NewArrayValue(elements ...Value) *ArrayValue {\nif elements == nil { return &ArrayValue{values: []Value{}} }\nreturn &ArrayValue{values: elements}\n}'
    )

    # 7b. Fix main(): remove old context setup, avoid duplicate ctx declarations
    # The old binary's main() has both ctx (old) and ctx2 (new) setups.
    # After step 3 renames, ctx2 -> ctx, so we have duplicate ctx := NewContext(nil).
    # Replace the duplicate block with a single setup.
    content = content.replace(
        'ctx := NewContext(nil)\n\tregisterLibraryFunctions(ctx)\n\tctx := NewContext(nil)\n\tregisterLibraryFunctions(ctx)',
        'ctx := NewContext(nil)\n\tregisterLibraryFunctions(ctx)'
    )
    # Also handle the non-indented version (if tabs are spaces)
    content = content.replace(
        'ctx := NewContext(nil)\nregisterLibraryFunctions(ctx)\nctx := NewContext(nil)\nregisterLibraryFunctions(ctx)',
        'ctx := NewContext(nil)\nregisterLibraryFunctions(ctx)'
    )

    # Remove duplicate blank lines that may result
    while '\n\n\n' in content:
        content = content.replace('\n\n\n', '\n\n')

    return content


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--in-place"]
    in_place = "--in-place" in sys.argv
    if len(args) != 1:
        sys.stderr.write("Usage: fix_app_go.py app.go [--in-place]\n")
        sys.exit(2)

    filepath = args[0]
    with open(filepath, "r") as f:
        original = f.read()

    fixed = fix_app_go(original)

    if in_place:
        with open(filepath, "w") as f:
            f.write(fixed)
    else:
        sys.stdout.write(fixed)


if __name__ == "__main__":
    main()
