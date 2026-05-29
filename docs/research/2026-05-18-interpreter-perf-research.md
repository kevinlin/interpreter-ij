---
date: 2026-05-18T00:40:00+0800
researcher: Claude
git_commit: c42261c081c2ae25e93797d17fe1aa8dc5a98210
branch: main
repository: kevinlin/interpreter-ij
topic: "IJ interpreter performance — expression flow, bottlenecks, shortcuts, and failed paths"
tags: [research, interpreter, performance, transpiler, self-hosted, codegen, eval]
status: complete
last_updated: 2026-05-18
last_updated_by: Claude
---

# Research: IJ Interpreter Performance — Expression Flow, Bottlenecks, Shortcuts, and Failed Paths

**Date**: 2026-05-18T00:40:00+0800
**Researcher**: Claude
**Git Commit**: `c42261c` (`perf/p2: excise refreshToGoPointers, demonstrate stage2 emit fixed-point`)
**Branch**: `main`
**Repository**: `kevinlin/interpreter-ij`

## Research Question

Two parts:

1. Document the core IJ interpreter (`src/interpreter.s`) with a focus on performance:
   - Expression interpretation flow.
   - Performance bottlenecks.
   - Potential shortcuts that could improve interpreter performance.

2. Cross-reference the previous performance work (`docs/specs/2026-05-16-self-hosted-perf-10x-design.md`, `docs/plans/2026-05-16-self-hosted-perf-10x.md`, `IMPLEMENTATION_PLAN.md`) against the current state of `src/interpreter.s` and note the paths that did not work.

> **Documentation only.** This document describes the current state of the code as of `c42261c`. It does not propose changes, evaluate trade-offs, or recommend next steps. Where the existing planning documents already note a future direction, that future direction is cited as historical context, not as a recommendation.

---

## Summary

`src/interpreter.s` is a self-hosted IJ→Go transpiler that can also tree-walk-evaluate IJ source directly. The transpile output is a single Go file (`app.go`) consumed by `go build`. The committed native binary at the repo root (`interpreter_mac_arm64`, ~4.5 MB) is the Go-built output of `src/interpreter.s` transpiling itself.

The hot path for `selfhosted_interpreter.sh sample.s` is:

```
IJ source → IJ-side lexer/parser → MapValue AST → resolver → IJ-side *ToGo emitters
   → Go file (app.go) → go build → native binary → ctx + Node tree → eval(programNode, ctx)
   → switch n.kind → evalIdent/evalInfix/evalCall/... → recurse over Node tree.
```

The current shipped runtime (`goLibPrefix` at `src/interpreter.s:4351-5384` plus `programToGoPhase2` at `5390`) is a **pure tree-walker over a typed `*Node` AST, with no static identifier resolution or singleton interning**. The structural Phase 2 work (typed-AST struct nodes) shipped successfully and is what runs today. The semantic Phase 2 work (using resolver annotations to skip `ctx.Get` map probes, fixed-arity static dispatch, singleton literals, slot-indexed contexts) did not ship — `identifierToGo` emits a bare `&Node{kind: nkIdent, name: "<s>"}`, `evalIdent` unconditionally calls `ctx.Get(n.name)`, and every resolver annotation on the AST is computed and then never read by any codegen emitter.

Bench reality at HEAD (`c42261c`, per `bench.log` and `IMPLEMENTATION_PLAN.md`):

| Label | Real time | Speedup vs phase0 |
|---|---|---|
| `phase0-baseline` | 1m11.153s | 1.00× |
| `phase2-typed-ast` (2026-05-17 03:46Z) | 1m25.086s | 0.83× |
| `phase2-current` (2026-05-17 14:44Z) | 1m29.188s | 0.80× |
| `p1-dead-code-cleanup` (2026-05-17 15:32Z) | 1m21.306s | 0.88× |

The 10× goal is unmet. Phase 2 in its current shape is a measurable regression vs. the unannotated phase0 baseline. The "running 49s" outlier (`run-baseline`, 02:13Z) was a transitional dual-runtime artifact built from commit `c5da0ac`, which cannot self-build and no longer exists in source form.

---

## Detailed Findings

### 1. Expression Interpretation Flow

The interpreter has two interpretation paths and one compile path. All three share the IJ-side lexer/parser.

#### 1.1 Path A — IJ-side tree-walker (`scripts/interpreter.sh`)

Used by the IJ-implemented driver. Each AST node is a `MapValue` with an `"evaluate"` callable attached at construction time (see `makeAssignmentStatement` at `src/interpreter.s:699`, `makeInfixExpression` at `819`, `makeNumberLiteral` at `1721`, `makeIdentifier` at `1891`, etc.). Evaluation reads `node["evaluate"]` and calls it with `(self, context)`. The context (`makeEvaluationContext` at `3786`, `ctxGet` at `3813`, `ctxAssign` at `3848`, `ctxExtend` at `3876`) is a chain of MapValues; `ctxGet` walks parents until it finds the name or reports a runtime error. This is the slowest of the three paths and is used by `scripts/interpreter.sh` and by self-hosted runs (`scripts/selfhosted_interpreter.sh`) — the latter runs the IJ-side tree-walker inside an already-tree-walking native interpreter.

#### 1.2 Path B — Native interpreter via Path A (committed binary)

`./interpreter_mac_arm64` is `src/interpreter.s` transpiled to Go and compiled. When it runs `src/sample.s`, it goes through Path A (lex/parse/resolve/walk) but the walker itself runs as compiled Go. Used by `scripts/native_interpreter.sh`. Runs sample.s in ~30 ms.

#### 1.3 Path C — Transpile to Go (`//<GO2>` mode)

`readSources()` at `src/interpreter.s:5762` reads stdin and selects a mode based on sentinels (`//<EOF>`, `//<AST>`, `//<GO>`, `//<GO2>`). For `//<GO2>`, after parse + resolve, the program walks the AST and calls each node's `toGo` method, which emits Go source via `puts(...)` and `print(...)`. The emit consists of three sections:

1. **`goLibPrefix()`** at `src/interpreter.s:4351-5384` — emits the entire Go runtime (Value, ArrayValue, MapValue, Context, Command, FunctionCommand, Node, eval, evalIdent, evalInfix, …, evalProgram, plus all built-in library functions inside `registerLibraryFunctions`).
2. **The user program body** — `programToGoPhase2(self)` at `5390-5431` emits `func main()`, sets up `ctx := NewContext(nil); registerLibraryFunctions(ctx)`, then emits `programNode := &Node{kind: nkProgram, list: []*Node{...stmts...}}` followed by `eval(programNode, ctx)`. The `...stmts...` part comes from each statement's `toGo` emitter (e.g. `assignmentStatementToGo` at `735`, `infixExpressionToGo` at `894`, `CallExpression_toGo` at `3002`, `ifStatementToGo` at `3159`, `functionDeclarationToGo` at `1693`).
3. **Post-processing** by `scripts/fix_app_go.py` — see §5 below.

The resulting `app.go` is fed to `go build app.go`, producing the binary.

#### 1.4 The Go-side eval dispatcher (the actual hot loop)

`puts("func eval(n *Node, ctx *Context) (Value, bool) {")` at `src/interpreter.s:5194-5220` emits this switch:

```go
func eval(n *Node, ctx *Context) (Value, bool) {
    switch n.kind {
    case nkIntLit:    return Value{tag: tInt, i: n.iVal}, false
    case nkDoubleLit: return Value{tag: tDouble, d: n.dVal}, false
    case nkStringLit: return Value{tag: tString, s: n.name}, false
    case nkBoolLit:   return Value{tag: tBool, b: n.bVal}, false
    case nkNullLit:   return vNull(), false
    case nkIdent:     return evalIdent(n, ctx)
    case nkInfix:     return evalInfix(n, ctx)
    case nkPrefix:    return evalPrefix(n, ctx)
    case nkAssign:    return evalAssign(n, ctx)
    case nkIndexAssign: return evalIndexAssign(n, ctx)
    case nkExprStmt:  return eval(n.left, ctx)
    case nkBlock:     return evalBlock(n, ctx)
    case nkVarDecl:   return evalVarDecl(n, ctx)
    case nkFuncDecl:  return evalFuncDecl(n, ctx)
    case nkIfStmt:    return evalIf(n, ctx)
    case nkWhileStmt: return evalWhile(n, ctx)
    case nkReturn:    return evalReturn(n, ctx)
    case nkArrayLit:  return evalArrayLit(n, ctx)
    case nkMapLit:    return evalMapLit(n, ctx)
    case nkIndex:     return evalIndex(n, ctx)
    case nkCall:      return evalCall(n, ctx)
    case nkProgram:   return evalProgram(n, ctx)
    }
    return vInvalid("unknown node kind"), false
}
```

The `(Value, bool)` return shape is the in-band return sentinel (the `bool` is `true` when a `return` statement is unwinding the call stack). Every caller of `eval` checks `if ret { return v, true }` — for evalBlock at `5275-5285`, evalWhile at `5309-5321`, evalIf at `5295-5308`, evalInfix at `5224-5247`, evalPrefix at `5248-5257`, evalAssign at `5258-5263`, evalIndexAssign at `5264-5274`, evalVarDecl at `5286-5294`, evalIndex at `5364-5371`, evalArrayLit at `5350-5354`, evalMapLit at `5355-5363`, evalCall at `5340-5349`, evalProgram at `5372-5381`. (The `(Value, bool)` shape is the project's resolution of the spec's "Task 2.7 return-sentinel decision" — see §6.4 below.)

#### 1.5 Per-node evaluators (Go-side)

Each `evalXxx` function is emitted as a string in `goLibPrefix`. Key shapes:

- **`evalIdent`** (`src/interpreter.s:5221-5223`): `return ctx.Get(n.name), false` — no resolved-kind switching, no slot lookup; one Go map probe + chain walk per identifier resolution.
- **`evalInfix`** (`5224-5247`): evaluates `n.left`, short-circuits on `opAnd`/`opOr`, evaluates `n.right`, then dispatches on `n.op` to `l.Add(r)` / `l.Subtract(r)` / etc. Each operator returns a `Value` (88-byte struct, see §2.1).
- **`evalCall`** (`5340-5349`): evaluates the callee, then `NewArrayValue()` and appends each evaluated argument, then `callee.cmd.Execute(ctx, args)`. The caller `ctx` is passed but, as §2.3 shows, it is then discarded by `FunctionCommand.Execute`.
- **`evalFuncDecl`** (`5327-5339`): constructs a Go closure that captures `pNames`, `bodyN`, `defCtx`; wraps it in a `FunctionCommand`; calls `ctx.Create(n.name, vFunc(fn))`. The closure body always allocates a fresh `NewContext(defCtx)` per call, populates parameters via `local.Create(p, args.values[i])`, then `eval(bodyN, local)`.
- **`evalBlock`** (`5275-5285`): `blockCtx := NewContext(ctx)` — allocates a new context **even if the block declares no variables**, then iterates `n.list` running `eval(s, blockCtx)`.
- **`evalIf`** (`5295-5308`) / **`evalWhile`** (`5309-5321`): evaluate condition, call `c.IsTruthy()` (which switches on `c.tag` to return a Go `bool`), then recurse on `n.body` (and `n.right` for the else branch / loop body).
- **`evalAssign`** (`5258-5263`): `if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }`. `Exists` walks the parent chain to find the name; `Update` walks again to write it; `Create` allocates the map lazily and writes to the local-only ctx.
- **`evalReturn`** (`5322-5326`): returns `(v, true)` — the second value is the return-sentinel that lets callers unwind.

#### 1.6 Top-level program emit

`programToGoPhase2(self)` at `src/interpreter.s:5390-5431` emits:

```go
func main() {
    if pf := os.Getenv("IJ_CPUPROFILE"); pf != "" { /* pprof.StartCPUProfile */ }
    ctx := NewContext(nil)
    registerLibraryFunctions(ctx)
    defer func() { /* dump ijCount* counters if IJ_COUNTERS != "" */ }()
    programNode := &Node{kind: nkProgram, list: []*Node{ <stmts via toGo>, ... }}
    eval(programNode, ctx)
}
```

Two observability hooks bake in: `IJ_CPUPROFILE=path` writes a Go pprof CPU profile, and `IJ_COUNTERS=1` dumps the `ijCountNewContext / Create / Get / Update / MapGet / MapPut / FuncExec / NewMap / NewArr / Promote` counters declared at `4381-4390`. The counter increments themselves do not appear in the emit at this commit — only the declarations + the dump. (They were dead-code-cleaned in `b040672` "drop 121 LOC dead D2/D3 code".)

#### 1.7 Resolver pass

Between parse and emit, `resolveScopes(ast)` at `src/interpreter.s:1616` walks the MapValue AST and annotates nodes with `resolvedKind` ∈ {`"global"`, `"local"`, `"captured"`}, `resolvedOrigin` ∈ {`"param"`, `"let"`, `"def"`, `"lib"`, null}, `resolvedName` (a mangled, Go-safe identifier produced by `mangle` at `1243`), `resolvedAtRoot` (true iff scope parent is null), `resolvedScope` (a back-pointer), `resolvedLocals` / `resolvedParamLocals` (declaration lists), and `resolvedIsStatic` (output of `analyzeIsStatic` at `1429` — true iff the function body emits no `ctx.Get`/`Update`/`Create`).

**Critical finding (§3.2):** none of these annotations is read by any `*ToGo` emitter at this commit. `analyzeIsStatic` recursively walks every function body and the result is then dropped on the floor.

---

### 2. Performance Bottlenecks

All paths and line numbers in this section refer to `src/interpreter.s`.

#### 2.1 `Value` is 88 bytes and is passed by value everywhere

The `Value` struct (`puts("type Value struct {")` at `4703-4713`) has these fields:

```
tag uint8         //  1 byte
b   bool          //  1 byte
                  //  6 bytes padding for next int64
i   int64         //  8 bytes
d   float64       //  8 bytes
s   string        // 16 bytes (header: pointer + len)
arr *ArrayValue   //  8 bytes
m   *MapValue     //  8 bytes
cmd Command       // 16 bytes (interface: type + data)
inv string        // 16 bytes (invalid reason)
                  // total: 88 bytes
```

`eval` returns `(Value, bool)` — a 96-byte tuple — on every node visit. Every method on `Value` (Add, Subtract, Multiply, Equals, LessThan, …, IsTruthy, IsInvalid, Length, IntValue, String, Type, Get, Put, Keys, Values, Execute) takes `Value` by value and returns `Value` by value (`4760-4979`). For a tight `fib(25)`-style recursion this is ~88 bytes per recursive call frame × tree depth.

The tagged-union design (Phase 1 spec, design §Phase 1) intentionally removed the interface-boxing alloc of the old `IntValue{val: 3}` Go-interface shape, trading interface boxing (24 bytes + GC pressure per scalar value) for inline 88-byte struct copies. Per the spec the trade should net positive; per `bench.log` it has not — see §6.1 for the historical sequence.

#### 2.2 `Context.Get` walks the parent chain and probes a Go map at every level

`Context` (`5078-5106`):

```go
type Context struct {
    parent    *Context
    variables map[string]Value
}
func (c *Context) Get(name string) Value {
    for ctx := c; ctx != nil; ctx = ctx.parent {
        if v, ok := ctx.variables[name]; ok { return v }
    }
    return vInvalid("variable not found: " + name)
}
func (c *Context) Exists(name string) bool { /* same walk */ }
func (c *Context) Create(name string, value Value) Value {
    if c.variables == nil { c.variables = make(map[string]Value) }
    c.variables[name] = value
    return value
}
func (c *Context) Update(name string, value Value) Value {
    for ctx := c; ctx != nil; ctx = ctx.parent {
        if _, ok := ctx.variables[name]; ok { ctx.variables[name] = value; return value }
    }
    return c.Create(name, value)
}
```

Every `evalIdent` (called for every identifier reference at runtime — once per `n`, once per `i`, once per `fib`, once per `puts`, once per `gets` in a recursive call) executes one `Get` = one chain walk + one Go map probe per level. A nested `fib(n-1)` inside a body whose ctx is `fib_local → fib_local → fib_local → … → root` will probe each level until it finds the name; library globals like `puts` always walk to root.

`evalAssign` (`5258-5263`) calls `Exists` (chain-walk) THEN `Update` (chain-walk again) — i.e. two walks per assignment unless the variable doesn't exist (in which case one walk + one `Create`).

The `ctxCount*` counters at `4381-4390` were originally added to instrument this; the increments were removed in `b040672`.

#### 2.3 Per function-call: at least four heap allocations

Each `evalCall` at `5340-5349` does:

1. `args := NewArrayValue()` — 1 alloc for `*ArrayValue`, then `args.values = append(args.values, v)` per argument (slice growth allocs as needed).
2. `callee.cmd.Execute(ctx, args)` → `FunctionCommand.Execute` at `5119-5121`: `return c.executeFunc(NewContext(c.definitionCtx), params)`. That `NewContext` produces a `*Context` — **and is then ignored** by the closure body emitted by `evalFuncDecl` at `5331-5336`. The closure signature is `func(callerCtx *Context, args *ArrayValue) Value` but the first line is `local := NewContext(defCtx)` (the captured definition ctx), discarding `callerCtx`. So that's 2 `*Context` allocs per call, one of which is immediately garbage.
3. If the function body is `nkBlock` (the universal case for `def f(...) { ... }`), `evalBlock` at `5275` does `blockCtx := NewContext(ctx)` — a 3rd `*Context` alloc per call.
4. `ctx.Create(p, args.values[i])` (line `5333`) does `c.variables == nil` check + `make(map[string]Value)` on first `Create` — 1 map alloc per fresh context.

Net per call: ~5 heap allocations on the function-call hot path, none of which involve any actual user computation.

#### 2.4 `evalBlock` always creates a fresh `Context` — even for blocks with no `let`

`evalBlock` at `5275-5285` unconditionally calls `blockCtx := NewContext(ctx)`. The condition body of an `if`/`while`, the alternative branch of an `if`, the body of a `while` loop iteration — each is a `BlockStatement` and each runs allocates a fresh `*Context` per iteration even when the block contains only statements like `puts("Hello " + name)`. For a `while (name != null) { puts("Hello " + name); name = gets(); }` loop (the sample.s shape), this is one extra `*Context` per loop iteration.

#### 2.5 `MapValue` uses a Go hash map indirectly via `key.String()`

`MapValue` (`5026-5076`) stores `pairs []KeyValuePair` for ordered iteration AND `keyIndex map[string]int` for O(1) lookup. Every `Get` / `Put` calls `key.String()` — for `Value{tag: tString}` this just returns `v.s` (cheap), for `tInt` it allocates via `strconv.FormatInt`, for `tBool` it returns a literal string, for arrays/maps it builds a debug string. Index-heavy code paths that use non-string keys pay an allocation per access.

The ordered-pairs slice exists because `Keys()` / `Values()` (`5059-5068`) need deterministic iteration order.

#### 2.6 Every node visit performs in-band return-sentinel propagation

The `(Value, bool)` return convention requires every intermediate caller (evalInfix, evalIf, evalWhile, evalBlock, evalCall, evalProgram, evalIndex, evalIndexAssign, evalArrayLit, evalMapLit, evalAssign, evalVarDecl, …) to check `if ret { return v, true }` after every recursive `eval` call. For an expression like `puts("Hello " + name)`, that is at least 5 `if ret` checks per execution. The plan's Task 2.7 explicitly discussed the alternatives (`tReturn` tag + `subTag` field, vs. panic/recover) and the project picked the `(Value, bool)` shape — the tag-based approach was never wired (the `tReturn` constant doesn't appear in the current emit; see `4691-4702`).

#### 2.7 The fix_app_go.py-injected bool helpers are dead code

`scripts/fix_app_go.py:117-151` injects `EqualsBool`, `NotEqualsBool`, `LessThanBool`, `LessThanEqualBool`, `BiggerThanBool`, `BiggerThanEqualBool` into `app.go` before `func main()`. These take `(a, b Value) bool` and return a raw Go bool, avoiding the `Value{tag: tBool, b: true}` heap-touching boxing.

Nothing in the emitted Go calls them. `evalInfix` uses `l.Equals(r)` → returns `Value`. `evalIf` / `evalWhile` evaluate the condition into a `Value` and then call `.IsTruthy()` on it. The bool helpers exist in `app.go` but are reachable only via `go build` not stripping unused package-level functions when emitted-but-unused.

The injection is a historical defensive measure from the D3 era (pre-`fb2b299`) when the legacy binary emitted `if EqualsBool(x, y) {` directly. That codegen path no longer exists in `src/interpreter.s` (see §3.2 below).

#### 2.8 String literals are emitted as inline `Value{tag: tString, s: "..."}` per occurrence

`stringLiteralToGo` at `1818-1820` emits `&Node{kind: nkStringLit, name: "<escaped>"}`. The `eval` case at `5198` then constructs `Value{tag: tString, s: n.name}` on each evaluation — a fresh `Value` struct (88 bytes), but the underlying string header (16 bytes, pointer + len) is shared because `n.name` is a Go string constant from `app.go`. The string body itself is in the binary's read-only data, not re-allocated. The Phase 3 design proposes routing through a `strPool[idx uint32]` table with `Value` singletons; that has not been implemented (§6.3).

#### 2.9 `evalIdent` always misses on `Context` for library functions

`evalIdent` does `ctx.Get(n.name)`. For library functions (`puts`, `gets`, `len`, `chr`, …), the name is registered into `ctx` (the root context) by `registerLibraryFunctions(ctx)` at startup. A call from a deeply nested function does the full chain walk to root every time. The IJ-side resolver does identify these (`resolveIdentifier` at `1551` will tag them `resolvedKind="global"`, `resolvedOrigin="lib"` because the resolver pre-seeds the root scope with `libraryFunctionNames()` at `1289-1297` via `resolveScopes`), but as documented in §3.2 those annotations are never projected into the emitted Node.

#### 2.10 sample.s — the benchmark target

`src/sample.s` is 7 lines: a `puts`, a `let name = gets()`, a `while (name != null) { puts("Hello " + name); name = gets(); }`. The self-hosted run sources this script through the IJ-implemented interpreter running on top of the native interpreter, with stdin = `hi` (a 2-line input). The hot loop is therefore the IJ-side lexer (`createLexer` at `3182`, `tokenize` at `3543`, `scnnnerNextToken` at `3360`) + IJ-side parser (`parseProgram` at `2132`) + IJ-side resolver + IJ-side tree-walker, where each of those runs as compiled Go (i.e. via Path A executed by Path B). Because the IJ-side tree-walker uses `*MapValue` AST with map-string lookup of `"evaluate"` and `ctxGet` parent-chain walks on `MapValue` contexts, the cost dominates the trivial sample.s workload.

---

### 3. Potential Shortcuts (Found in the Code but Not Activated)

This section catalogues optimization infrastructure that exists in `src/interpreter.s` but has no live consumer in the current emit.

#### 3.1 Six dead fields on the emitted `Node` struct

`Node` is emitted with 16 fields at `5174-5192`. The codebase-analyzer subagent confirmed (verbatim: "6 fields are pure dead weight"): **`pos`, `sIdx`, `resolvedKind`, `resolvedSlot`, `resolvedName`, `isStatic`** are never written by any `*ToGo` emitter and never read by any `eval*` runtime function. Each field is sized:

- `pos uint32` — 4 bytes
- `sIdx uint32` — 4 bytes (Phase 3 strPool index — scaffolded, never populated)
- `resolvedKind uint8` — 1 byte
- `resolvedSlot int32` — 4 bytes (Phase 4 slot — scaffolded, never populated)
- `resolvedName string` — 16 bytes (header)
- `isStatic bool` — 1 byte

The struct also has `params []string` (24 bytes — slice header) which is used only by `evalFuncDecl`. Per-node these are paid for every `&Node{...}` allocation regardless of whether the kind has params.

The `pos uint32` was designed in spec §Phase 2 (lines 158-198 of the design doc) as a packed line/col replacement for the IJ-side `Position` MapValue, to enable line/col error messages. It is never set in the current `*ToGo` emitters and the `vInvalid("...")` runtime errors do not include source position.

#### 3.2 All resolver annotations are dead

The resolver (`resolveScopes` at `1616`, `resolveBlockStatement` at `1346`, `resolveFunctionDeclaration` at `1380`, `resolveIdentifier` at `1551`, `resolveAssignmentStatement` at `1539`, `resolveVariableDeclaration` at `1524`, `analyzeIsStatic` at `1429`) annotates AST MapValue nodes with these keys:

| Annotation | Written by | Read by codegen? |
|---|---|---|
| `resolvedKind` | resolveIdentifier, resolveAssignmentStatement, resolveVariableDeclaration, resolveFunctionDeclaration | NO — only by `analyzeIsStatic` |
| `resolvedOrigin` | same as above | NO — only by `analyzeIsStatic` |
| `resolvedName` (via `mangle` at 1243) | same as above | NO |
| `resolvedAtRoot` | resolveFunctionDeclaration, resolveVariableDeclaration | NO |
| `resolvedScope` / `resolvedLocals` / `resolvedParamLocals` | resolveBlockStatement, resolveFunctionDeclaration | NO |
| `resolvedIsStatic` | resolveFunctionDeclaration (via `analyzeIsStatic`) | NO |

The codebase-analyzer subagent verified this against every `*ToGo` function: `identifierToGo` (1922), `assignmentStatementToGo` (735), `variableDeclarationToGo` (4336), `functionDeclarationToGo` (1693), `infixExpressionToGo` (894), `nullLiteralToGo` (939), `numberLiteralToGo` (1756), `stringLiteralToGo` (1818), `toGoBooleanLiteral` (1880), `blockStatementToGo` (1100), `toGoJsonExpressionStatement` (801), `ifStatementToGo` (3159) + `conditionToGoBool` (3150), `arrayLiteralToGo` (70), `mapLiteralToGo` (under `makeMapLiteral` at 4020), `indexAssignmentStatement_toGo` (3991), `ReturnStatement_toGo` (591), `PrefixExpression_toGo` (3606), `CallExpression_toGo` (3002), `programToGoPhase2` (5390). None reads any `resolved*` key. `mangle(name)` runs on every named node and its output is then discarded.

The design's Task 2.8 explicitly described `identifierToGo` projecting `resolvedName`, `resolvedKind` into the emitted Node (plan lines 1406-1417). The implementation lands the struct fields, runs the resolver, but never wires the projection.

#### 3.3 `analyzeIsStatic` recursively walks every function body for nothing

`analyzeIsStatic` at `src/interpreter.s:1429-1522` walks the full body of every `FunctionDeclaration`, recursing through scalar children (`condition, consequence, alternative, body, left, right, collection, index, value, callee, expression, initializer`), array children (`statements, elements, arguments`), and map-literal pairs. The result lands on `node["resolvedIsStatic"]`. Per §3.2 that key is then never read. The analysis is paid per IJ→Go transpile but has no effect.

The intent (per design §Phase 2 "Static-impl path (D1/D2) lift-over" lines 238-241 and IMPLEMENTATION_PLAN.md P1 forensics) was for `functionDeclarationToGo` to emit a fixed-arity `ij_<name>_impl(ctx *Context, a, b Value) Value` Go function alongside the Node literal, and for call-sites to detect static targets and emit a direct call. Neither half exists in the current emit.

#### 3.4 The `useNodeTree` switch permanently disables the Phase 1 path

`let useNodeTree = true;` at `src/interpreter.s:5388` is the gate that selects Phase 2's `programToGoPhase2` over the (now removed) Phase 1 emitter. The variable is read at the program-level emit dispatch but no path resets it. The Phase 1 emit branch is dead — kept only for reference. Files like `cleanup_phase1.py` (referenced as removable in IMPLEMENTATION_PLAN.md P5) are consistent with this — Phase 1 is unreachable.

#### 3.5 fix_app_go.py-injected bool helpers + AsValue wrappers wait for a caller

Per §2.7 above, `EqualsBool`/`NotEqualsBool`/`LessThanBool`/`LessThanEqualBool`/`BiggerThanBool`/`BiggerThanEqualBool` (`scripts/fix_app_go.py:117-151`) are injected into `app.go` but no emitted code calls them. `NewMapValueAsValue` / `NewArrayValueAsValue` (`fix_app_go.py:156-163`) wrap the constructors to return `Value` instead of `*MapValue`/`*ArrayValue` — they ARE used (Step 6 rewrites `NewMapValue(` → `NewMapValueAsValue(` and `NewArrayValue(` → `NewArrayValueAsValue(` in the body, outside of `.Execute(ctx, NewArrayValue(` call-sites which it protects via `__TMP_NEWARR__` sentinel).

The bool-helper injection logic is gated: `if "func EqualsBool(a, b Value) bool" not in content[:content.find("\nfunc main() {")]`. So the helpers appear only when the current `goLibPrefix` did not already emit them (which it doesn't at this commit) — meaning every transpile produces an `app.go` with dead bool helpers.

#### 3.6 IJ counters declared and dumped but never incremented

`puts("var ijCountNewContext uint64")` and 9 sibling counters at `4381-4390` are declared in the emit. `programToGoPhase2` at `5404-5408` emits a `defer` that prints them on exit (`fmt.Fprintf(os.Stderr, "[IJ counters] NewContext=%d ...")`). No emitted code increments them. Setting `IJ_COUNTERS=1` and running any program produces an all-zeros line on stderr. They were incremented in the pre-`b040672` D2/D3 fast-path emit; the cleanup removed the call sites but left the declarations + dump.

#### 3.7 `opCodeFor("!")` has no caller

`opCodeFor` at `src/interpreter.s:835-851` maps operator strings to op-constant names. Its `"!"` entry returns `"opNot"`. The only caller is `infixExpressionToGo` (894), where `"!"` cannot appear (it's a prefix-only operator). `PrefixExpression_toGo` at `3606` does not call `opCodeFor`; it hardcodes `"opNeg"`/`"opNot"` directly. So the `"!"` branch of `opCodeFor` is dead.

#### 3.8 CPU profiling hook

`programToGoPhase2` at `5393-5401` emits:

```go
if pf := os.Getenv("IJ_CPUPROFILE"); pf != "" {
    f, err := os.Create(pf)
    if err == nil {
        if err := pprof.StartCPUProfile(f); err == nil {
            defer pprof.StopCPUProfile()
            defer f.Close()
        }
    }
}
```

Running `IJ_CPUPROFILE=/tmp/p.out ./interpreter_mac_arm64 < src/sample.s` produces a pprof CPU profile suitable for `go tool pprof`. This is a built-in shortcut for any future profiling work.

#### 3.9 Singleton scaffolding present in spec but not emitted

Design §Phase 3 (lines 260-307) and Plan §Task 3.1 (lines 1514-1546) describe `vNull`, `vTrue`, `vFalse`, `vEmpty`, `smallInt [256]Value`, `vIntFast(i int64) Value`, `strPool []Value`, `vStrPool(idx uint32) Value`, `init()` populating `smallInt`. None of these is emitted by the current `goLibPrefix`. `vNull()` etc. exist as helper *functions* (`4981-4989`) — they construct a new `Value` per call, not cached singletons. Per `eval` at `5196-5200`, every `nkNullLit` calls `vNull()` (returns `Value{tag: tNull}` — small but still a Value-by-value return), every `nkBoolLit` returns `Value{tag: tBool, b: n.bVal}` (no `vTrue`/`vFalse` lookup), every `nkIntLit` returns `Value{tag: tInt, i: n.iVal}` (no `smallInt[i+128]` cache).

The `sIdx uint32` field on `Node` (§3.1) is the half of the strPool wiring that landed. `eval` reads `n.name`, not `n.sIdx`.

#### 3.10 The dead `caller-ctx` allocation in `FunctionCommand.Execute`

`FunctionCommand.Execute` (`5119-5121`):

```go
func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {
    return c.executeFunc(NewContext(c.definitionCtx), params)
}
```

The `callerCtx` parameter is named but the body ignores it; instead it constructs a fresh `NewContext(c.definitionCtx)`. The closure body at `5331-5336` then names its first parameter `callerCtx` and again ignores it, calling `local := NewContext(defCtx)`. The first `NewContext(c.definitionCtx)` is unreachable garbage from the GC's perspective the moment the closure body returns. Per call this is one wasted `*Context` allocation + one wasted map header allocation if `Create` is called on it (it isn't, in the current closure).

`NewStaticFunctionCommand` (`5128-5130`) is identical to `NewFunctionCommand` — the "static" variant exists in name only; there is no behavioural difference.

---

### 4. Plan Paths That Did Not Work (Reading the Specs Against the Code)

This section maps each significant claim/assumption/path from the three planning documents to its current state in `src/interpreter.s`.

#### 4.1 D1 — Static identifier resolution → direct Go-var access — **REMOVED**

**Spec position:** Implicit; D1 was the historical optimization (pre-this work) that `identifierToGo` would consult `resolvedKind`/`resolvedOrigin` and emit `<gomanglename>` (a Go variable) instead of `ctx.Get("name")`, for params/locals/captured/lib-globals.

**Current state:** GONE. `identifierToGo` at `1922-1925` emits `&Node{kind: nkIdent, name: "<s>"}` unconditionally. Per IMPLEMENTATION_PLAN.md P1 forensics: "GONE. `identifierToGo` (line 1942) emits `&Node{kind: nkIdent, name: "<s>"}` unconditionally; the `resolvedKind`/`resolvedOrigin`/`resolvedName` annotations the resolver writes are never consulted at emit. Every `nkIdent` eval = `ctx.Get(string)` map lookup."

The committed `interpreter_mac_arm64` bridge binary was built from `ac2e6f3`-era source and still has D1-style direct Go var assignments compiled in. The current `src/interpreter.s` cannot reproduce that binary — see §4.5.

#### 4.2 D2 — Static def → fixed-arity `ij_<name>_impl` direct call — **REMOVED**

**Spec position:** Plan §Task 1.6 (lines 612-637) updates fixed-arity static-impl signatures to `Value2`. Design §Phase 2 "Static-impl path (D1/D2) lift-over" (lines 238-241) intends to preserve `ij_<name>_impl`.

**Current state:** GONE. Per IMPLEMENTATION_PLAN.md P1 forensics: `emitQueuedImpls()` and `goLibSuffix()` were documented no-ops; `transpilerImplQueue` was never appended; `transpilerStaticImpls` was populated but had ZERO readers. Cleaned up in commit `b040672` ("perf/p1: root-cause Phase-2 regression, drop 121 LOC dead D2/D3 code"). All call-sites dispatch via `Value{tag: tFunc}.cmd.Execute(...)` → `FunctionCommand.Execute` (`5119`).

#### 4.3 D3 — Condition slot → raw-`bool` helper (no `BoolValue` heap alloc) — **REMOVED**

**Spec position:** Design §Phase 1 (line 126): "D3 helpers (`EqualsBool`, `LessThanBool`, …) keep their signatures shifted to `(a, b Value) bool` with inline tag check."

**Current state:** GONE from `goLibPrefix`. Per IMPLEMENTATION_PLAN.md P1 forensics: "`conditionToGoBool` routes if/while conditions back to `condNode["toGo"]` (Node-tree emit)." Helpers are re-injected by `fix_app_go.py:117-151` (see §3.5 above) but no caller in emitted Go exists. `evalIf` at `5295-5308` and `evalWhile` at `5309-5321` call `.IsTruthy()` on the condition's `Value` result.

#### 4.4 The `run-baseline` 49s outlier — **IRREPRODUCIBLE ARTIFACT**

**Plan position:** `bench.log` line 52: `=== 2026-05-17T02:13:13Z label=run === selfhosted_interpreter.sh sample.s (stdin=hi) real 0m49.274s`. Recorded as `phase1-tagged-value`-era win.

**Current state:** Non-reproducible. Per IMPLEMENTATION_PLAN.md P1 forensics (W-a vs W-b table, lines 48-55):

- W-a binary (built from commit `c5da0ac` source, the transitional dual-runtime that registered BOTH old `Value`-interface AND new `Value2` tagged-union library functions PLUS D1/D2/D3 emit paths) ran sample.s in **51.97s**.
- W-b binary (fresh self-build of `fb2b299` source — the Phase 1 cleanup that removed the dual runtime) ran sample.s in **1m33s**.
- W-c binary (built from `c5da0ac`'s committed 3.6 MB binary) ran in **1m02s**.
- W-d binary (fresh self-build of `ac2e6f3` — first post-cleanup) ran in **1m27s**.
- HEAD binary (`38431c9` committed, 4.5 MB) ran in **1m29s**.

The 49s wasn't a phase win; it was the cost-amortized output of a binary whose source no longer exists in compilable form (the `c5da0ac` source cannot self-build — `compile-local.sh` errors on `Value` vs `Value2` type incompatibility).

#### 4.5 The committed `interpreter_mac_arm64` is a one-way bridge artifact — **NO TRUE FIXED-POINT**

**Plan position:** Cross-Phase Conventions (plan lines 19-32) assume the committed binary at the repo root is replaced once per phase and `verify.sh` check 5 confirms `compile-local.sh src/interpreter.s` produces a bit-identical binary in two consecutive runs.

**Current state:** Per IMPLEMENTATION_PLAN.md "Honest follow-up risks" (lines 74-79): "Fresh self-build of HEAD is functionally broken — `compile-local.sh` succeeds and produces a stage1 binary, but using that stage1 as the bootstrap and re-running `compile-local.sh` yields a binary that lacks `func main()`." The committed binary is from `ac2e6f3`-era pre-cleanup source and emits D1-style direct Go var assignments that no current source can reproduce.

`verify.sh` check 5 (per IMPLEMENTATION_PLAN.md "Open Questions" lines 129) runs `compile-local.sh src/interpreter.s _roundtrip_{a,b}` twice with the SAME committed bootstrap and diffs — this catches map-iteration non-determinism but NOT the "stage1 ≠ stage2 because stage1's compiled-in eval is buggy" regression class. P2 in IMPLEMENTATION_PLAN.md is the bridge to make this check honest.

**The root-cause Phase 2 bug:** `evalAssign` (`src/interpreter.s:5258-5263` emit) does `if ctx.Exists(n.name) { ctx.Update(...) } else { ctx.Create(...) }`. `Exists` walks parents but `Create` writes only to the current `ctx`. Top-level code that mutates a global from inside a function (e.g. `readSources()` at `5762` setting `transpileGo = true`) creates a shadow binding in the function's local ctx instead of updating the global. The transpile path therefore never sees `transpileGo = true` at the top level, and the program-emit branch in the stage1 binary never fires, so stage2 has no `func main()`.

#### 4.6 Phase 2 measurement reality: 0.83×–0.88× vs phase0, not the predicted 2–4×

**Spec position:** Design §Phase 2 line 255: "`./scripts/bench.sh phase2-typed-ast` ≥1.5× over phase1."

**Current state:** `bench.log` records `phase2-typed-ast` at 1m25.086s, `phase2-runtime` at 1m25.193s, `phase2-current` at 1m29.188s — all WORSE than `phase0-baseline` at 1m11.153s. The 1.10× recovery in `p1-dead-code-cleanup` (1m21.306s) came from removing dead instrumentation (counters + their increment-site overhead) per `b040672`, not from the typed-AST work itself.

The drop-rule (plan lines 28-29: "phase that does not exceed predecessor by ≥1.3× is reverted") was not enforced because (a) the 49s outlier (§4.4) made the "predecessor" floor ambiguous, and (b) revert would have dragged back the dual-runtime/cleanup chain. IMPLEMENTATION_PLAN.md P1 explicitly declines to fire the drop-rule.

#### 4.7 `registerLibraryFunctions.func12` (assert) length-0 panic — **PARTIALLY MITIGATED**

**Spec position:** Not anticipated in design or plan.

**Current state:** IMPLEMENTATION_PLAN.md P2 entry (lines 86-87): "Reproduced this loop with `printf 'let x=false\ndef setIt(){x=true;}\nsetIt()\nputs(x)\n' | stage2_redo`: panics in `assert` lib fn (func12) at `app.go:148 +0x1d8`, called from a recursive eval chain ~100 frames deep. The crash is `params.Get(Value{tag: tInt, i: 0})` or `params.Get(Value{tag: tInt, i: 1})` on a length-0 ArrayValue."

The `NewArrayValue` nil-guard at `fix_app_go.py:220-223` (Step 7c) is partial mitigation:

```python
'func NewArrayValue(elements ...Value) *ArrayValue {\nif elements == nil { return &ArrayValue{values: []Value{}} }\nreturn &ArrayValue{values: elements}\n}'
```

Bookkeeping bounds checks on every library function's `params.Get(Value{tag: tInt, i: N})` call site (the proposed Step 4 of P2) have not been added.

#### 4.8 `Value2 → Value` rename is mostly done; `fix_app_go.py` still bridges legacy types

**Spec position:** Plan §Task 1.7 (line 670 onward) — "Rename `Value2 → Value` … run: `grep -c "Value2" src/interpreter.s` Expected: `0`."

**Current state:** `src/interpreter.s` itself uses `Value` throughout (`Value2` appears only in `interpreter.s:4990` as a string literal in a stub `ValueToOld(v Value) Value { return nil } // stub — unused during transition`). But the committed `interpreter_mac_arm64` is the pre-rename `ac2e6f3`-era binary, which emits `Value2 → Value` rename targets in its compiled-in `goLibPrefix`. `scripts/fix_app_go.py` (the "Bridge post-processor: fix old-type references in app.go emitted by the legacy pre-cleanup native binary") handles the renames (Step 3 at `fix_app_go.py:80-115`), removes old register-library-functions and old Value interface (Steps 1+2 at `38-77`), splices in bool helpers + AsValue wrappers (Steps 4+5 at `117-173`), and rewrites the body so `NewArrayValue(...)` calls outside of `.Execute(ctx, ...)` use the AsValue wrappers (Step 6 at `175-209`). It also dedupes a `ctx := NewContext(nil); ... ctx := NewContext(nil)` block left by the legacy main() emit (Step 7b at `225-237`).

So the rename happened in source but the build pipeline still depends on the post-processor because the bootstrap binary is pre-rename. Removing `fix_app_go.py` (proposed in IMPLEMENTATION_PLAN.md P5) requires fixing the §4.5 stage1→stage2 bug first.

#### 4.9 Phase 3 (interning + singletons) and Phase 4 (slot-indexed contexts) — **NOT STARTED**

**Plan position:** Plan §Phase 3 (Tasks 3.1-3.3 at lines 1510-1676) and §Phase 4 (Tasks 4.1-4.3 at lines 1680-1825). IMPLEMENTATION_PLAN.md priorities P3 and P4.

**Current state:** Neither phase has shipped. The `sIdx uint32` field on Node (§3.1) and the `resolvedSlot int32` field on Node (§3.1) are the only scaffolding artefacts; the runtime tables (`strPool`, `smallInt`, `vTrue`, `vFalse`, `vEmpty`, `vIntFast`, `vStrPool`) and the resolver slot-numbering (`makeResolverScope` does not allocate `nextSlot` / `slots`) are absent.

#### 4.10 `refreshToGoPointers` — **EXCISED**

**Spec position:** Not in spec; introduced during Phase 2 attempts at `c42261c`'s parent `b040672`.

**Current state:** Commit `c42261c` ("perf/p2: excise refreshToGoPointers, demonstrate stage2 emit fixed-point") removed it. Per the commit subject this was part of the bridge to a clean Phase 2 self-build — the iterative `refreshToGoPointers` pass that was added in `ac2e6f3` and `768e308` to re-walk the AST and rebind toGo pointers between resolver and emit is gone.

#### 4.11 `bench_eval.s` secondary benchmark — **DROPPED**

**Spec position:** Design §Verification §Benchmarks (lines 388-422): "Secondary (new file `src/bench_eval.s`)" with `fib(25)` + `bubbleSort` 50-element.

**Current state:** `bench.log:51` shows the line `-- selfhosted_interpreter.sh bench_eval.s --` for `phase0-baseline-eval` but no timing follows (the run hung past 5 minutes). Commit `a93d814` "Commment out eval benchmark for now since it's too slow" + IMPLEMENTATION_PLAN.md P0 note ("Commented-out `bench_eval.s` block removed and replaced with a one-line note explaining why (Phase 2 codegen makes it >5min — re-enable only after primary bench hits 10×)"). `bench.sh` (28 lines per `Read` of `scripts/bench.sh`) does not currently exercise `bench_eval.s`.

#### 4.12 The `tReturn` sentinel approach — **REJECTED, in-band `(Value, bool)` shipped instead**

**Spec position:** Plan §Task 2.7 (lines 1152-1228) — "Pick (a) Magic-tag approach: add a new tag value `tReturn` that wraps the real value … widen the Value struct to carry an optional sub-tag for tReturn wrapping. Add `subTag uint8` field."

**Current state:** `tReturn` does NOT appear in the emitted `const ( tNull ... )` block (`src/interpreter.s:4691-4702`). `Value` has no `subTag` field. Every `eval*` function instead returns `(Value, bool)` where the bool is the return-sentinel (§1.4, §1.5, §2.6 above). The choice was made implicitly during implementation — Plan Task 2.7 explicitly flagged the trade-off as measurement-conditional.

---

### 5. Code References

Primary source: `src/interpreter.s` (5960 lines).

**Emitted Go runtime (lives inside `puts(...)` strings in `goLibPrefix`):**

- `src/interpreter.s:4351-5384` — `goLibPrefix()` — emits the entire Go runtime preamble.
- `src/interpreter.s:4691-4702` — `const ( tNull ... tInvalid )` value-tag constants emit.
- `src/interpreter.s:4703-4713` — `type Value struct { tag, b, i, d, s, arr, m, cmd, inv }` emit.
- `src/interpreter.s:4714-4979` — `Value` methods (`IsTruthy`, `Length`, `IntValue`, `String`, `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`, `Type`, `Append`).
- `src/interpreter.s:4981-4989` — `vNull / vBool / vInt / vDouble / vString / vArray / vMap / vFunc / vInvalid` constructor functions.
- `src/interpreter.s:4992-5024` — `ArrayValue` type + methods.
- `src/interpreter.s:5026-5076` — `MapValue` (uses `keyIndex map[string]int` keyed on `key.String()`).
- `src/interpreter.s:5078-5106` — `Context` type + `Get / Exists / Create / Update`.
- `src/interpreter.s:5109-5130` — `Command` interface + `FunctionCommand`.
- `src/interpreter.s:5133-5156` — `const ( nkInfix ... nkProgram )` Node-kind constants.
- `src/interpreter.s:5157-5173` — `const ( opAdd ... opNeg )` operator-code constants.
- `src/interpreter.s:5174-5192` — `type Node struct { ... 16 fields ... }`.
- `src/interpreter.s:5194-5220` — `func eval(n *Node, ctx *Context) (Value, bool)` switch dispatch.
- `src/interpreter.s:5221-5223` — `evalIdent` — `return ctx.Get(n.name), false`.
- `src/interpreter.s:5224-5247` — `evalInfix` — short-circuits opAnd/opOr, dispatches arithmetic to Value methods.
- `src/interpreter.s:5248-5257` — `evalPrefix`.
- `src/interpreter.s:5258-5263` — `evalAssign` (chain-walk on Exists + Update).
- `src/interpreter.s:5264-5274` — `evalIndexAssign`.
- `src/interpreter.s:5275-5285` — `evalBlock` (always allocs `NewContext`).
- `src/interpreter.s:5286-5294` — `evalVarDecl`.
- `src/interpreter.s:5295-5308` — `evalIf`.
- `src/interpreter.s:5309-5321` — `evalWhile`.
- `src/interpreter.s:5322-5326` — `evalReturn` (returns `(v, true)` sentinel).
- `src/interpreter.s:5327-5339` — `evalFuncDecl` (closure ignores `callerCtx`, allocates own ctx).
- `src/interpreter.s:5340-5349` — `evalCall` (allocs `NewArrayValue` + arg-by-arg append).
- `src/interpreter.s:5350-5354` — `evalArrayLit`.
- `src/interpreter.s:5355-5363` — `evalMapLit`.
- `src/interpreter.s:5364-5371` — `evalIndex`.
- `src/interpreter.s:5372-5381` — `evalProgram`.
- `src/interpreter.s:4381-4390` — `ijCount*` counter declarations (never incremented, dumped on exit).

**Top-level program emit:**

- `src/interpreter.s:5388` — `let useNodeTree = true;` — Phase 2 gate.
- `src/interpreter.s:5390-5431` — `programToGoPhase2` — emits `func main()` + `IJ_CPUPROFILE` hook + ctx setup + `programNode := &Node{kind: nkProgram, list: []*Node{...}}` + `eval(programNode, ctx)`.

**IJ-side codegen emitters (`*ToGo` functions):**

- `src/interpreter.s:70-91` — `arrayLiteralToGo`.
- `src/interpreter.s:591-690` — `ReturnStatement_toGo`.
- `src/interpreter.s:735-742` — `assignmentStatementToGo` — `&Node{kind: nkAssign, name: <raw>, right: ...}`.
- `src/interpreter.s:801-813` — `toGoJsonExpressionStatement`.
- `src/interpreter.s:835-851` — `opCodeFor` (the `"!"` entry is dead).
- `src/interpreter.s:894-905` — `infixExpressionToGo`.
- `src/interpreter.s:939-944` — `nullLiteralToGo`.
- `src/interpreter.s:1100-1126` — `blockStatementToGo`.
- `src/interpreter.s:1693-1718` — `functionDeclarationToGo` (does not read `resolvedIsStatic`).
- `src/interpreter.s:1756-1771` — `numberLiteralToGo`.
- `src/interpreter.s:1818-1820` — `stringLiteralToGo` — `&Node{kind: nkStringLit, name: "<escaped>"}`.
- `src/interpreter.s:1880-1887` — `toGoBooleanLiteral`.
- `src/interpreter.s:1922-1925` — `identifierToGo` — `&Node{kind: nkIdent, name: "<s>"}` (no resolver annotations projected).
- `src/interpreter.s:3002-3025` — `CallExpression_toGo`.
- `src/interpreter.s:3150-3157` — `conditionToGoBool` (passes through to child `toGo`).
- `src/interpreter.s:3159-3174` — `ifStatementToGo`.
- `src/interpreter.s:3606-3621` — `PrefixExpression_toGo`.
- `src/interpreter.s:3991-4019` — `indexAssignmentStatement_toGo`.
- `src/interpreter.s:4336-4350` — `variableDeclarationToGo`.

**Resolver pass (all annotations dead):**

- `src/interpreter.s:1243-1268` — `mangle(name)` — produces a Go-safe identifier name; output is then ignored.
- `src/interpreter.s:1269-1297` — resolver scope helpers + `libraryFunctionNames()`.
- `src/interpreter.s:1299-1328` — `resolverScopeLookup`.
- `src/interpreter.s:1330-1344` — `resolveNode`.
- `src/interpreter.s:1346-1378` — `resolveBlockStatement`.
- `src/interpreter.s:1380-1420` — `resolveFunctionDeclaration` (computes `resolvedIsStatic`).
- `src/interpreter.s:1429-1522` — `analyzeIsStatic` (walks full body, result never read).
- `src/interpreter.s:1524-1557` — `resolveVariableDeclaration` / `resolveAssignmentStatement` / `resolveIdentifier`.
- `src/interpreter.s:1559-1613` — `resolveGeneric`.
- `src/interpreter.s:1616-…` — `resolveScopes(ast)` entry point.

**Post-processor:**

- `scripts/fix_app_go.py:37-243` — `fix_app_go(content)` — 7 transformation steps bridging the pre-rename committed bootstrap binary's output to clean `Value`. Injects unused `EqualsBool`-family helpers at `117-151`.

**Build pipeline / scripts referenced in this doc:**

- `scripts/bench.sh` — primary benchmark driver. Currently runs only `selfhosted_interpreter.sh sample.s` + `interpreter.sh sample.s` + `native_interpreter.sh sample.s`. `bench_eval.s` block removed per §4.11.
- `scripts/verify.sh` — 5-check regression harness. Check 5 currently validates determinism, not true fixed-point (§4.5).
- `src/compile-local.sh` — the Docker-less compile path, mandatory for honest verification (Docker path silently swallows failures per AGENTS.md).
- `scripts/selfhosted_interpreter.sh src/sample.s` — primary headline benchmark (stdin=`hi`).

**Source examples:**

- `src/sample.s` — 7-line greeting-loop benchmark target.

---

### 6. Architecture Documentation

#### 6.1 Three-binary history

The repository carries the scars of three eras:

1. **Pre-Phase-1 (pre-`c5da0ac`)** — `Value` was a Go interface; `IntValue{val: 3}` etc. were struct types implementing it. D1/D2/D3 fast paths emitted by the codegen used resolver annotations heavily. Bench label `phase0-baseline` at 1m11s.
2. **Phase 1 transitional (`c5da0ac → fb2b299`)** — `Value2` (tagged-union struct) added alongside the old `Value` interface, with parallel `registerLibraryFunctions2` / `Context2` / etc. The `c5da0ac` "dual-runtime" commit registers BOTH and emits D1/D2/D3 inline — this is the 49s outlier source (§4.4). `fb2b299` cleaned up the dual runtime: deleted the old interface, renamed `Value2 → Value`. Cleanup also (incidentally) dropped D1/D2/D3 emit paths.
3. **Phase 2 (`768e308 → c42261c`)** — Typed `Node` AST shipped. `eval(n *Node, ctx *Context) (Value, bool)` switch dispatch shipped. Resolver annotation projection into Node did NOT ship. `refreshToGoPointers` pass added in `ac2e6f3`, removed in `c42261c`. P1 dead-code cleanup at `b040672` dropped 121 LOC of vestigial D2 prep.

The committed `interpreter_mac_arm64` is from era 2 (`ac2e6f3` snapshot) — see §4.5.

#### 6.2 Stdin sentinel-mode protocol

Per CLAUDE.md and `readSources()` at `src/interpreter.s:5762`:

| Marker (trailing line) | Mode |
|---|---|
| `//<EOF>` | Evaluate (default) — rest of stdin is `gets()` input. |
| `//<AST>` | Emit AST as JSON, do not evaluate. |
| `//<GO>` | Emit Go source for the program body, do not evaluate. |
| `//<GO2>` | Emit a `bash` script that writes `app.go` (prelude + body + suffix + `go build app.go`). |

`//multiline` is the leading marker that switches the reader into multi-line collect mode. Compile scripts feed `//multiline … //<GO2>` and pipe the resulting shell script through `bash`.

#### 6.3 IJ → Go transpile pipeline (compile-local.sh shape)

```
src/interpreter.s + stdin (mode markers)
   ↓  ./interpreter_mac_arm64 (committed bootstrap binary)
app.go.script (a bash script that emits app.go)
   ↓  bash app.go.script
app.go
   ↓  scripts/fix_app_go.py app.go --in-place
clean app.go
   ↓  go build app.go
new binary
```

#### 6.4 The `(Value, bool)` return-sentinel convention

Picked over the design's Task 2.7 `tReturn`/`subTag` option (§4.12). Every `eval*` returns `(Value, bool)` where the bool is `true` iff a `return` statement in user code is unwinding the call stack. Callers must check the bool after every recursive `eval` and propagate it. The hot loop pays one Go boolean compare per node visit per recursion level.

#### 6.5 The two-AST design

The IJ-side AST is `*MapValue` with `"evaluate"` / `"toGo"` / `"toJson"` callable entries (e.g. `makeIdentifier` at `1891-1902` attaches three callables per node). The Go-side runtime AST is `*Node` struct (`5174-5192`). No runtime cross-talk: IJ-side reads project into Node only at emit time. The IJ-side AST is still used by `scripts/interpreter.sh`, `scripts/ast.sh`, the resolver, and the `toGo` emitters themselves.

---

## Historical Context (from existing planning docs)

### From `docs/specs/2026-05-16-self-hosted-perf-10x-design.md`

The spec sets a 10× target for `selfhosted_interpreter.sh sample.s` (1m11s → 7s) via four phases: P1 tagged-union Value (2-4× expected), P2 typed AST struct nodes (2-4×), P3 string interning + singletons (1.3-1.8×), P4 slot-indexed contexts (1.5-2×). Multiplicative range: ~6-58×. Realistic 10-15×. Per-phase exit criterion: ≥1.5× over predecessor (Phase 1, 2), ≥1.2× (Phase 3), ≥1.3× (Phase 4). Drop-rule: <1.3× over predecessor ⇒ revert.

### From `docs/plans/2026-05-16-self-hosted-perf-10x.md`

Detailed task breakdown. P1 shipped. P2 shipped structurally (Node AST landed) but missed every optimization it was supposed to enable (resolver projection, static-impl emit, slot allocation). P3 and P4 not started.

### From `IMPLEMENTATION_PLAN.md`

Current ground truth at HEAD `c42261c`. Verifies P0 complete; P1 dead-code cleanup shipped (`b040672`, +1.10× over phase2-current floor); P2 has two open bugs (`evalAssign` closure-scope bug breaking stage1→stage2 fixed-point; `assert` lib-fn length-0 panic); P3 + P4 not started. Drop-rule was NOT enforced for the Phase 2 regression because the "predecessor" floor was contaminated by the `c5da0ac` 49s outlier (§4.4). Real Phase 1 → Phase 2 delta is <5%.

---

## Related Research

This is the first research document under `docs/research/`. Related planning artefacts:

- `docs/specs/2026-05-16-self-hosted-perf-10x-design.md` — spec (Phases 1-4 design).
- `docs/plans/2026-05-16-self-hosted-perf-10x.md` — task-by-task plan.
- `IMPLEMENTATION_PLAN.md` — current state, P0-P5 priorities, P1 forensics, honest follow-up risks.

---

## Open Questions

These are descriptive only — they record uncertainties this research did not resolve, not proposed work:

1. **Stage1 self-build crash exact reproducer.** IMPLEMENTATION_PLAN.md P2 includes a reproducer for the `assert` panic but does not include a stack trace for the "stage2 binary lacks `func main()`" path. Where in the emit does the missing `func main()` originate? (Hypothesis from IMPLEMENTATION_PLAN.md: `readSources()` setting `transpileGo = true` is invisible to its enclosing scope because of the `evalAssign` closure-scope bug. Confirmed by inspection of `evalAssign` emit at `5258-5263` — `ctx.Exists(n.name)` walks the parent chain to find `transpileGo` but `ctx.Create(n.name, v)` writes only to the local ctx of `readSources`. Not actually reproduced in a debugger during this research.)

2. **MapValue.String() allocation cost in practice.** The `key.String()` call per `Get`/`Put` (§2.5) allocates for non-string keys. How often are non-string keys used at runtime? The IJ MapValue idiom is overwhelmingly string-keyed (AST nodes themselves are `MapValue` with string keys); but user-program map literals can use any key type.

3. **CPU profile of `selfhosted_interpreter.sh src/sample.s`.** `IJ_CPUPROFILE` hook exists (§3.8). A profile would empirically rank the bottlenecks in §2 by sample share. This research did not run a profile.

4. **`bench_eval.s`'s actual runtime under Phase 2 codegen.** Recorded as >5 min in IMPLEMENTATION_PLAN.md P0. The exact ratio vs. `bench_eval.s` under the `interpreter_mac_arm64` committed binary running its compiled-in Phase 1 codegen would quantify how much slower Phase 2 is on eval-heavy workloads vs. sample.s's I/O-heavy workload.

5. **Whether `fix_app_go.py` would still be needed after a clean Phase 2 self-build.** Per IMPLEMENTATION_PLAN.md P5 it should not be — but P5 is gated on P2 (clean self-build). At HEAD, the post-processor is load-bearing for `compile-local.sh`.

6. **The exact ordering constraint for strPool determinism.** Phase 3 design (lines 296-300) requires "first-appearance during a documented traversal order" for `strPool` indices to be bit-identical across runs. The current `*ToGo` emitters traverse in source order; this is the natural deterministic order, but the spec does not enumerate which emitters would need to call `strPoolIntern` to cover every literal site (identifier names, type tags, map keys, etc.).
