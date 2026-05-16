#!/usr/bin/env python3
"""Bridge post-processor: fix old-type references in app.go emitted by the legacy
pre-Value2 native binary.  The script is idempotent — running it twice is safe.

Usage: python3 scripts/fix_app_go.py app.go [--in-place]
"""

import re
import sys


def fix_app_go(content: str) -> str:
    # 1. result=NewNullValue() -> result=v2Null()
    content = content.replace("result=NewNullValue()", "result=v2Null()")

    # 2. var ij_XXX Value = -> var ij_XXX Value2 =
    content = re.sub(r"var (ij_\w+) Value =", r"var \1 Value2 =", content)

    # 3. Replace old bool helpers (Value interface) with Value2 versions.
    # The raw goLibPrefix output uses NO indentation (just newlines).
    bool_subs = [
        (
            "func EqualsBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val == bi.val } }\n"
            "if as, ok := a.(StringValue); ok { if bs, ok := b.(StringValue); ok { return as.val == bs.val } }\n"
            "return a.Equals(b).(BoolValue).val\n"
            "}",
            "func EqualsBool(a, b Value2) bool {\n"
            "if a.tag != b.tag { return false }\n"
            "switch a.tag {\n"
            "case t2Int: return a.i == b.i\n"
            "case t2Double: return a.d == b.d\n"
            "case t2String: return a.s == b.s\n"
            "case t2Bool: return a.b == b.b\n"
            "case t2Null: return true\n"
            "}\n"
            "return false\n"
            "}",
        ),
        (
            "func NotEqualsBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val != bi.val } }\n"
            "if as, ok := a.(StringValue); ok { if bs, ok := b.(StringValue); ok { return as.val != bs.val } }\n"
            "return !a.Equals(b).(BoolValue).val\n"
            "}",
            "func NotEqualsBool(a, b Value2) bool { return !EqualsBool(a, b) }",
        ),
        (
            "func LessThanBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val < bi.val } }\n"
            "return a.LessThan(b).(BoolValue).val\n"
            "}",
            "func LessThanBool(a, b Value2) bool {\n"
            "if a.tag == t2Int && b.tag == t2Int { return a.i < b.i }\n"
            "if a.tag == t2Double && b.tag == t2Double { return a.d < b.d }\n"
            "return a.LessThan(b).b\n"
            "}",
        ),
        (
            "func LessThanEqualBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val <= bi.val } }\n"
            "return a.LessThanEqual(b).(BoolValue).val\n"
            "}",
            "func LessThanEqualBool(a, b Value2) bool {\n"
            "if a.tag == t2Int && b.tag == t2Int { return a.i <= b.i }\n"
            "if a.tag == t2Double && b.tag == t2Double { return a.d <= b.d }\n"
            "return a.LessThanEqual(b).b\n"
            "}",
        ),
        (
            "func BiggerThanBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val > bi.val } }\n"
            "return a.BiggerThan(b).(BoolValue).val\n"
            "}",
            "func BiggerThanBool(a, b Value2) bool {\n"
            "if a.tag == t2Int && b.tag == t2Int { return a.i > b.i }\n"
            "if a.tag == t2Double && b.tag == t2Double { return a.d > b.d }\n"
            "return a.BiggerThan(b).b\n"
            "}",
        ),
        (
            "func BiggerThanEqualBool(a, b Value) bool {\n"
            "if ai, ok := a.(IntValue); ok { if bi, ok := b.(IntValue); ok { return ai.val >= bi.val } }\n"
            "return a.BiggerThanEqual(b).(BoolValue).val\n"
            "}",
            "func BiggerThanEqualBool(a, b Value2) bool {\n"
            "if a.tag == t2Int && b.tag == t2Int { return a.i >= b.i }\n"
            "if a.tag == t2Double && b.tag == t2Double { return a.d >= b.d }\n"
            "return a.BiggerThanEqual(b).b\n"
            "}",
        ),
    ]
    for old, new in bool_subs:
        if old in content:
            content = content.replace(old, new)

    # 4. Add wrapper functions before func main()
    wrappers = (
        "func NewMapValue2AsValue(pairs ...KeyValuePair2) Value2 {\n"
        "\treturn Value2{tag: t2Map, m: NewMapValue2(pairs...)}\n"
        "}\n"
        "func NewArrayValue2AsValue(elements ...Value2) Value2 {\n"
        "\treturn Value2{tag: t2Array, arr: NewArrayValue2(elements...)}\n"
        "}\n\n"
    )
    content = content.replace(
        "\nfunc main() {", "\n" + wrappers + "func main() {"
    )

    # 5-6. Replace map/array constructors in Value2-typed variable assignments
    content = re.sub(
        r"(var ij_\w+ Value2 = )NewMapValue2\(",
        r"\1NewMapValue2AsValue(",
        content,
    )
    content = re.sub(
        r"(var ij_\w+ Value2 = )NewArrayValue2\(",
        r"\1NewArrayValue2AsValue(",
        content,
    )

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
