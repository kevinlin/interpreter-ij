# D1-reborn Emit Template Reference

Captured 2026-05-18 from `/tmp/d1r_app_raw.go` — the pre-`fix_app_go.py` `app.go` produced by `compile-local.sh src/interpreter.s`. The 188 `func ij_<name>_impl(...)` definitions at lines 4153–11541 were emitted by the **committed bridge's** OLD D1/D2 path. This file is the structural reference for porting per-statement direct emitters into the new `interpreter.s` (`*ToGoDirect`).

> Why preserve this: the OLD bridge is a frozen artifact built from a transitional commit (`c5da0ac`) whose IJ source can no longer self-build. Once the bridge is replaced (D1-reborn Run N+3), this output is gone. The patterns below are the only durable record of the OLD emit shape.

## Impl prologue / epilogue (every promoted def)

```go
func ij_<name>_impl(ctx *Context, ij_<p1> Value, ij_<p2> Value) (result Value) {
_ = ctx
_ = ij_<p1>
_ = ij_<p2>
result=vNull()
{ ... body ... }
return result
}
```

- Signature: `ctx *Context` first, then each IJ parameter as `ij_<name> Value`.
- Named return: `(result Value)`; pre-initialised to `vNull()`.
- Body wrapped in an outer `{ ... }` block (the IJ-level `BlockStatement`).
- Trailing `return result` ensures any path that falls through still returns `vNull()`.

## Per–node-kind mapping

### NullLiteral
```go
vNull()
```

### BooleanLiteral
```go
vBool(true)
vBool(false)
```
(Helper from `goLibPrefix`: `func vBool(b bool) Value { return Value{tag: tBool, b: b} }`.)

### NumberLiteral (int)
```go
Value{tag: tInt, i: 42}
```

### NumberLiteral (double)
```go
Value{tag: tDouble, d: 3.14}
```

### StringLiteral
```go
Value{tag: tString, s: "hello"}
```
(Double quotes inside the literal are escaped with `\\`; see `escapeGoStringLiteral` in IJ source.)

### Identifier (param / local / library)
```go
ij_<name>
```
- IJ parameters become Go params with the `ij_` prefix.
- IJ `let` bindings inside the body become Go locals with the same prefix (see VariableDeclaration).
- Library names (e.g. `puts`, `ord`, `len`) are captured at the top of `main()` as `ij_<name> = ctx.Get("<name>")` and reused as bare Go vars.

### VariableDeclaration (`let x = expr;`)
```go
var ij_<name> Value = <expr-direct>
_ = ij_<name>

```
(Blank line follows; `_ =` keeps the Go compiler happy if the binding is only assigned for closure capture.)

### Assignment (`x = expr;`)
```go
ij_<name>=<expr-direct>
```
(No `var` for re-assignments. Mirrors IJ's evalAssign semantics.)

### BlockStatement (`{ s1; s2; ... }`)
```go
{
_ = ctx
<s1-direct>
<s2-direct>
}
```

### ReturnStatement (`return expr;`)
```go
return <expr-direct>
```
(With no value: `return vNull()`.)

### IfStatement (`if (cond) { ... } else { ... }`)
```go
if <cond-direct>.IsTruthy() {
_ = ctx
<then-direct>
} else {
_ = ctx
<else-direct>
}
```
- The `.IsTruthy()` call is OLD bridge style; D3 fast-path uses `EqualsBool` / `LessThanBool` etc. directly when the condition is an infix comparison (skip the `Value` round-trip).

### Equality used as condition (D3 fast-path)
```go
if EqualsBool(<a-direct>, <b-direct>) {
if NotEqualsBool(<a-direct>, <b-direct>) {
if LessThanBool(<a-direct>, <b-direct>) {
if LessThanEqualBool(<a-direct>, <b-direct>) {
if BiggerThanBool(<a-direct>, <b-direct>) {
if BiggerThanEqualBool(<a-direct>, <b-direct>) {
```
(Helpers are re-injected by `fix_app_go.py`; safe to call from D1-reborn direct emit even when the IJ runtime helpers are missing.)

### WhileStatement
```go
for <cond-direct>.IsTruthy() {
_ = ctx
<body-direct>
}
```

### InfixExpression (general — produces a `Value`)
| IJ op | Direct emit                       |
|-------|-----------------------------------|
| `+`   | `<a>.Add(<b>)`                    |
| `-`   | `<a>.Subtract(<b>)`               |
| `*`   | `<a>.Multiply(<b>)`               |
| `/`   | `<a>.Divide(<b>)`                 |
| `%`   | `<a>.Modulo(<b>)`                 |
| `==`  | `<a>.Equals(<b>)`                 |
| `!=`  | `<a>.Equals(<b>).Not()`           |
| `<`   | `<a>.LessThan(<b>)`               |
| `<=`  | `<a>.LessThanEqual(<b>)`          |
| `>`   | `<a>.BiggerThan(<b>)`             |
| `>=`  | `<a>.BiggerThanEqual(<b>)`        |
| `&&`  | `<a>.And(<b>)`                    |
| <code>&#124;&#124;</code>  | `<a>.Or(<b>)`                     |

### PrefixExpression
| IJ op | Direct emit |
|-------|-------------|
| `!`   | `<a>.Not()` |
| `-`   | `vInt(0).Subtract(<a>)` *(no negate helper; subtract from zero)* |

### CallExpression — library or indirect callee
```go
ij_<callee>.Execute(ctx, NewArrayValue(<arg1-direct>, <arg2-direct>))
```

### CallExpression — known-at-emit-time static def (D2 fast-path)
```go
ij_<callee>_impl(ctx, <arg1-direct>, <arg2-direct>)
```
(Note: D2-reborn currently dispatches via `nkStaticCall` + `staticImpl func(*Context, []Value) Value`, NOT positional args. The OLD bridge's positional-arg signature is what D1-reborn restores.)

### IndexExpression (`coll[idx]`)
```go
<coll-direct>.Get(<idx-direct>)
```

### IndexAssignment (`coll[idx] = val;`)
```go
<coll-direct>.Put(<idx-direct>,<val-direct>)
```

### ArrayLiteral
```go
NewArrayValue(<e1-direct>,<e2-direct>,...)
```
(`fix_app_go.py` wraps these as `NewArrayValueAsValue(...)` outside of `.Execute(ctx, NewArrayValue(...))` call sites, so the direct emit can stay `NewArrayValue(...)` and let the post-processor handle the wrapper.)

### MapLiteral (`{"k": v, ...}`)
```go
NewMapValue(KeyValuePair{Key: <k-direct>, Value: <v-direct>}, ...)
```
(Same `NewMapValueAsValue` wrapping by `fix_app_go.py`.)

### FunctionDeclaration (inside a body — nested def)
Skip; D1-reborn does NOT promote defs with nested defs. The `resolvedIsStatic` predicate already excludes them, but the migrated allowlist must additionally exclude them.

## Where this matters in `interpreter.s`

| New emitter (`*ToGoDirect`) | Mirrors existing emitter (`*ToGo`) |
|---|---|
| `nullLiteralToGoDirect` | `nullLiteralToGo` |
| `toGoBooleanLiteralDirect` | `toGoBooleanLiteral` |
| `numberLiteralToGoDirect` | `numberLiteralToGo` |
| `stringLiteralToGoDirect` | `stringLiteralToGo` |
| `identifierToGoDirect` | `identifierToGo` |
| `blockStatementToGoDirect` | `blockStatementToGo` |
| `ReturnStatement_toGoDirect` | `ReturnStatement_toGo` |
| `nodeToGoDirect` (dispatcher) | (no equivalent — Node-tree path goes through `node["toGo"](node)` instead) |

Subsequent runs add the remaining ~12 emitters per the run roadmap in `IMPLEMENTATION_PLAN.md` (P2.6 → Run N+1, N+2).

## Why a dispatcher instead of `node["toGoDirect"](node)`

The IJ tree-walker uses callable map entries (`node["toGo"]`, `node["evaluate"]`, etc.) for double-dispatch on AST node kind. Setting a `node["toGoDirect"]` slot would require every `make<Kind>` constructor to attach one, and inherits the same per-call indirection cost the tree-walker pays for `toGo`. A central `nodeToGoDirect` dispatcher that switches on `node["type"]` is cheaper and lets unsupported kinds emit a sentinel that fails the Go build loudly (which is the desired behaviour for a feature-flagged opt-in path).
