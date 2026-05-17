# Self-Hosted Interpreter Perf — ≥10× Design

Date: 2026-05-16
Status: Approved; **revised 2026-05-18 after research review** (see "Status Update" below).

## Status Update — 2026-05-18

After implementing Phase 1 (tagged-union `Value`) and Phase 2 (typed AST `Node`), bench reality vs the original projection:

| Label | Real time | Speedup vs phase0 | Spec target |
|---|---|---|---|
| `phase0-baseline` | 1m11.153s | 1.00× | — |
| `phase2-typed-ast` (post P1+P2 cutover) | 1m25.086s | 0.83× | 4–16× cumulative |
| `p2-no-refresh` (HEAD, post-cleanup) | 1m20.478s | 0.88× | — |

**The 10× goal is unmet, and the phases as shipped REGRESSED vs phase0.** Root cause is documented in `docs/superpowers/research/2026-05-18-interpreter-perf-research.md` (the research doc is the authoritative current-state map; this section is the design-level summary).

### What actually shipped vs what was spec'd

- **Phase 1 (tagged-union `Value`) — shipped semantically.** `Value` is the 88-byte struct, dispatch is tag-switch, no interface boxing. ✅
- **Phase 1 cleanup — accidentally REMOVED D1/D2/D3 fast paths.** The pre-Phase-1 codegen had three optimizations layered on top of the old `Value` interface: D1 emitted `<gomanglename>` (Go variable) instead of `ctx.Get("name")` for params/locals/lib-globals; D2 emitted `ij_<name>_impl(ctx, a, b)` fixed-arity static dispatch; D3 emitted `EqualsBool(...)` raw-`bool` helpers for `if`/`while` conditions. The Phase 1 cleanup commit (`fb2b299`) removed these along with the dual runtime. They were never lifted onto the new `Value` shape.
- **Phase 2 (typed AST `Node`) — shipped STRUCTURALLY ONLY.** The `Node` struct, `eval` switch, and per-kind `evalXxx` functions are emitted and used. ✅ But:
  - The resolver runs and writes `resolvedKind` / `resolvedOrigin` / `resolvedName` / `resolvedAtRoot` / `resolvedScope` / `resolvedLocals` / `resolvedParamLocals` / `resolvedIsStatic` to every AST node — and **NO `*ToGo` emitter reads any of them.** `mangle(name)` runs and the result is discarded. `analyzeIsStatic` walks every function body and the result is dropped.
  - The `Node` struct emits 16 fields. **6 are pure dead weight** (`pos`, `sIdx`, `resolvedKind`, `resolvedSlot`, `resolvedName`, `isStatic`) — never written by emitters, never read by runtime.
  - `evalIdent` at `src/interpreter.s:5221-5223` is `return ctx.Get(n.name), false` — full chain walk + map probe per identifier reference.
  - `evalBlock` at `5275-5285` unconditionally calls `NewContext(ctx)` — a fresh `*Context` per block, even for blocks with no `let`.
  - `evalCall` allocates ~5 heap objects per call (`*ArrayValue` + `*Context` × 2, one of which is wasted by `FunctionCommand.Execute`, + lazy map alloc on first `Create`).
- **`fix_app_go.py` injects `EqualsBool`/`LessThanBool` helpers into every `app.go`** — but emitted Go has zero callers. Pure dead weight from the D3 era.

### Implication for the phase ordering

The original spec ordered phases by expected lever: P1 (boxing) → P2 (AST shape) → P3 (interning) → P4 (slot ctx). After the cleanup-induced regression, the **dominant remaining cost is the dead resolver infrastructure**: every `evalIdent`/`evalAssign` does a parent-chain map walk despite the resolver already knowing the answer at codegen time. Wiring the existing-but-dead annotations into Node + reading them in `eval*` is the single highest-leverage change available.

**Phase ordering revised:**

1. **Phase 2.5 — Activate Resolver Annotations (NEW; was D1/D2 in pre-Phase-1 era).** Project `resolvedKind` / `resolvedName` / `resolvedOrigin` from the IJ-side AST into the `Node` struct at emit time; switch `evalIdent` / `evalAssign` / `evalVarDecl` / `evalFuncDecl` to use them. Reintroduces D1 (static-identifier dispatch). Expected 2–3× because `evalIdent` is on every recursive call.
2. **Phase 3 (string interning + singletons) — DEMOTED.** Original 1.3–1.8× target stands but the lever is smaller than P2.5; without P2.5, interning saves only the string-header alloc per literal and adds no help to `ctx.Get` chain walks (the dominant cost).
3. **Phase 4 (slot-indexed contexts) — partially overlaps with P2.5.** The slot index is the natural extension of the resolver annotation projection; if P2.5 hits the cumulative 10× target, P4 may not be needed. If not, P4 finishes the job by replacing the `Context.variables` map probe with `ctx.slots[N]`.

### Other research findings folded into this design

- **`bench_eval.s` (eval-heavy secondary benchmark) was dropped** — current Phase 2 codegen makes it >5min. Re-enable only after primary bench hits 10×.
- **The 49s outlier** (`bench.log:52`, `run-baseline` at 02:13Z) was an irreproducible artifact from a transitional dual-runtime commit (`c5da0ac`) whose source no longer compiles. It is not a "phase win"; it is not the perf floor. Drop-rule should reference `phase0-baseline = 1m11.153s` as the floor, not the 49s.
- **The committed `interpreter_mac_arm64` is a one-way bridge** built from `ac2e6f3`-era source that emitted D1/D2/D3 fast paths the current source can no longer reproduce. `verify.sh` check 5 currently validates determinism (same bootstrap → same output twice), NOT true fixed-point. Replacing the committed binary with a clean Phase-2 self-build is BLOCKED on a stage2-runtime IJ-tree-walker bug ("scalar-VarDecl regression"). See `IMPLEMENTATION_PLAN.md` P2.
- **`(Value, bool)` was chosen over `tReturn` magic-tag** for the return-sentinel (Plan §Task 2.7 had it as measurement-conditional). Adds one `if ret { return v, true }` branch per recursive `eval` call. Plan §Task 2.7 should record this as the implemented choice; rolling back to `tReturn` is not on the table at this point.
- **CPU profile hook is built in:** `IJ_CPUPROFILE=path ./interpreter_mac_arm64 < src/sample.s` writes a Go pprof CPU profile. Use this when measuring P2.5/P3/P4.

The remainder of this document keeps the original phase definitions (P1 / P2 / P3 / P4) for reference; **P2.5 is the new section authored 2026-05-18** and lives between P2 and P3 below.

## Goal

Make `./scripts/bench.sh` self-hosted run (`./scripts/selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) at least 10× faster.

- Current measured: real `1m10s`, user `3m4s` on macOS/arm64 (label `run-baseline` in `bench.log`).
- Historical baseline (per README): 154s pre-C1 phase.
- Target: ≤ 7s wall on the same machine.
- Approach: stay tree-walking; refactor the emitted-Go runtime + the codegen in `interpreter.s` that produces it.

## Constraints

- Self-hosted architecture preserved. Interpreter still written in IJ. No new IJ syntax.
- `./scripts/verify.sh` checks 1–4 (functional, golden, MCP, JSON-RPC) green at **every commit**.
- `./scripts/verify.sh` check 5 (bit-identical double self-transpile fixed-point) **green at end of each phase before merge**. May break mid-phase.
- Use `compile-local.sh` (non-Docker) for verification — `scripts/build.sh` / Docker path silently swallows failures.
- `./scripts/test.sh` green at every commit.
- `bench.log` appended per phase with labels of the form `phaseN-<name>`.
- Drop-rule: phase that does not exceed predecessor by ≥1.3× is reverted (D4 lesson).

## Two-Layer Edit Surface

Every phase changes two layers in tandem:

1. **Emitted Go runtime** — strings inside `interpreter.s` at lines ~5159–6342 (`puts("type Value interface { ... }")` block + per-type methods). Produces `app.go`.
2. **Codegen `*ToGo` functions** in `interpreter.s` — every `print('IntValue{val: ' + ...)` site that emits Go must match the new runtime shape.

Unchanged: IJ syntax/lexer/parser logic, driver scripts, MCP protocol, `test.s`, `sample.s`.

## Phases

| Phase | Lever | Expected | Status |
|---|---|---|---|
| P1 | Tagged-union `Value` struct | 2–4× | ✅ Shipped, but cleanup dropped D1/D2/D3 fast paths |
| P2 | Typed AST struct nodes | 2–4× | ✅ Shipped structurally; resolver annotations LANDED but DEAD (no emitter reads them) |
| **P2.5** | **Activate resolver annotations (D1 reborn) + skip dead Context allocs** | **2–3×** | **NEW (added 2026-05-18) — next priority after P2-fixed-point unblock** |
| P3 | String interning + null/bool/small-int singletons | 1.3–1.8× | Demoted: smaller lever than P2.5 |
| P4 (stretch) | Slot-indexed contexts | 1.5–2× | Conditional — only if P1–P3 < 10× |

Multiplicative range if all five land: ~12–87×. Realistic 10–15× cumulative vs phase0. **HEAD measurement is 0.88× of phase0 — the bookkeeping target for P2.5 is to crawl back to ≥1.3× of phase0 first, then continue.** Stop after first phase that crosses 10× cumulative.

---

## Phase 1 — Tagged-Union `Value`

### Problem

Emitted Go runtime today:

```go
type Value interface {
    Execute(ctx *Context, params *ArrayValue) Value
    String() string
    // ...
}
type IntValue struct { val int64 }
type StringValue struct { val string }
type BoolValue struct { val bool }
type DoubleValue struct { val float64 }
```

Every `IntValue{val: 3}` assigned to a `Value`-typed slot forces heap allocation (interface boxing). Hits every arithmetic op, every literal, every comparison return.

### New shape (emitted Go)

```go
const (
    tNull uint8 = iota
    tInt
    tDouble
    tString
    tBool
    tArray
    tMap
    tFunc      // FunctionCommand / Command
    tNamed
    tInvalid
)

type Value struct {
    tag uint8
    b   bool
    i   int64
    d   float64
    s   string
    arr *ArrayValue
    m   *MapValue
    cmd Command
}
```

`Value` is passed/returned **by value**. No interface, no per-op heap alloc for scalars.

Method dispatch becomes switches on `tag`:

```go
func (v Value) Add(o Value) Value {
    switch v.tag {
    case tInt:
        if o.tag == tInt    { return Value{tag: tInt, i: v.i + o.i} }
        if o.tag == tDouble { return Value{tag: tDouble, d: float64(v.i) + o.d} }
    case tString:
        // concat
    }
    panic("type error")
}
```

`Command` interface kept. Function values still dispatch via interface (rare on hot path).

### Codegen rewrites (`*ToGo`)

| Old emit | New emit |
|---|---|
| `IntValue{val: 3}` | `Value{tag: tInt, i: 3}` |
| `StringValue{val: "x"}` | `Value{tag: tString, s: "x"}` (P3 will replace with interned ref) |
| `BoolValue{val: true}` | `vTrue` (singleton, set up in P3) — for P1, `Value{tag: tBool, b: true}` |
| `NewArrayValue(...)` | `Value{tag: tArray, arr: NewArrayValue(...)}` |
| `NewMapValue(...)` | `Value{tag: tMap, m: NewMapValue(...)}` |
| `IntValue{val: -1}.Multiply(...)` | `Value{tag: tInt, i: -1}.Mul(...)` |
| `params.Get(IntValue{val: 0})` | `params.GetI(0)` (new fixed-int accessor on `ArrayValue`) |

D3 helpers (`EqualsBool`, `LessThanBool`, …) keep their signatures shifted to `(a, b Value) bool` with inline tag check.

### Edit sites (interpreter.s)

71 (NewArrayValue print), 2028 (IntValue emit), 2079 (StringValue emit), 3287/3295/3325 (.Execute / NewArrayValue dispatch), 3970 (unary minus), 4366 (Put), 4512–4514 (NewMapValue), 1885–1913 (function params unpack), 4843+ (StdIO prelude), plus the runtime-type definition block at ~5159–6342.

### Risks

- IJ string literal `\"` quirk: every new emit string with `"` uses `chr(34)`.
- Override pattern `let oldX = X; def X(...) { oldX(...) }` must work — preserved via `Command` interface still backing `tFunc`.
- MCP overrides (`eval.s` / `mcp.s`) cast through `Value` — new shape must let those plug in via `cmd Command`.
- Golden checks 1–4 compare program output, not types — should stay green. Check 5 re-baselined post-phase.

### Exit criteria

- No `IntValue{...}` / `BoolValue{...}` / `DoubleValue{...}` / `StringValue{...}` strings remain in interpreter.s codegen output paths.
- `./scripts/test.sh` passes.
- `./scripts/bench.sh phase1-tagged-value` ≥1.5× over `phase0-baseline` (target 2–4×).
- `./scripts/verify.sh` checks 1–4 green; check 5 re-baselined and green.

---

## Phase 2 — Typed AST Struct Nodes

### Problem

Every AST node is `*MapValue` with string keys + callable entries. Each evaluation = map-string-lookup for `"evaluate"` + interface call + `ArrayValue` alloc for params + tag-check inside callee.

Node-construction sites in interpreter.s (each returns a `MapValue`): `makeInfixExpression` (~855), `makeAssignmentStatement` (708), `makeExpressionStatement` (801), `makeBlockStatement` (1092), `makeFunctionDeclaration` (1266), `makeIndexExpression` (358), `makeNullLiteral` (1002), `makeReturnValue` (1035), `makeArrayLiteral` (5), `makePosition` (517), `ReturnStatement_create` (546), plus ~15 more.

### New shape (emitted Go)

```go
const (
    nkInfix uint8 = iota
    nkAssign
    nkExprStmt
    nkBlock
    nkFuncDecl
    nkIfStmt
    nkWhileStmt
    nkReturn
    nkIdent
    nkIntLit
    nkDoubleLit
    nkStringLit
    nkBoolLit
    nkNullLit
    nkArrayLit
    nkMapLit
    nkIndex
    nkCall
    nkPrefix
)

type Node struct {
    kind  uint8
    pos   uint32          // line<<16 | col, replaces Position MapValue
    sIdx  uint32          // string-pool index (P3)
    iVal  int64
    dVal  float64
    op    uint8           // operator code
    left  *Node
    right *Node
    list  []*Node
    body  *Node           // function body
    params []string
    resolvedKind uint8    // 0=global,1=param,2=local,3=upvalue,4=static
    resolvedSlot int32    // P4 slot, -1 until then
    resolvedName string
    isStatic bool         // D1 annotation
}
```

Evaluation:

```go
func eval(n *Node, ctx *Context) Value {
    switch n.kind {
    case nkInfix:    return evalInfix(n, ctx)
    case nkAssign:   return evalAssign(n, ctx)
    case nkBlock:    return evalBlock(n, ctx)
    case nkIntLit:   return Value{tag: tInt, i: n.iVal}
    case nkStringLit:return strPool[n.sIdx]   // P3
    case nkIdent:    return lookupIdent(n, ctx)
    }
    panic("unknown node kind")
}
```

No map lookups. No callable-entry indirection. No `ArrayValue` param alloc per call.

### IJ-side rewrite

1. `make*` constructors stay in IJ source — IJ interpreter parsing the source still needs introspectable MapValues.
2. `*ToGo` codegen emits `&Node{kind: nkInfix, op: opAdd, left: ..., right: ...}` instead of `NewMapValue(...)` for AST nodes.
3. At runtime in transpiled Go, no MapValue AST nodes — only `*Node`. Eval switches on `n.kind`. The IJ-side map-of-callables `node["evaluate"]` path no longer exists at runtime.

The AST representation differs between IJ parser (still maps) and transpiled-Go program (typed Nodes). Already kind of the case; P2 widens the gap.

### Operator opcodes

Infix/prefix operators map to `op uint8` codes (`opAdd`, `opSub`, `opEq`, `opLt`, `opAnd`, `opOr`, …). `evalInfix` switches on `n.op`. Replaces today's runtime string compare on `node["operator"]`.

### Eval functions location

`evalXxx(n *Node, ctx *Context) Value` for each kind, emitted as part of the standard prelude in the Go-type-definition block (~5000–6300). Hand-written Go equivalents of today's IJ `evaluateXxx` logic. Emitted once, not per program.

### Resolver bridge

Resolver currently annotates MapValue AST with `"resolvedName"`, `"resolvedKind"`, `"resolvedIsStatic"`. Project these into `Node` fields at emit time. Mechanical mapping inside `*ToGo` functions.

### Static-impl path (D1/D2) lift-over

`ij_<name>_impl` fixed-arity Go functions now take `Value` (by value) args. Body emitted by `blockStatementToGo` over the `Node` body — same shape as today's body emission, only leaf-level emissions differ (P1 already covers the leaves).

### Risks

- Largest single diff in project history. Land over several commits within the phase branch.
- Position info: `MapValue` → packed `uint32`. Error messages decode line/col on print.
- IJ-side AST (MapValues during parse) and Go-side AST (`*Node`) diverge. No runtime cross-talk — IJ-side reads project into Node only at emit time.
- MCP integration: `eval.s` / `mcp.s` hook in via Command values, not AST nodes. Untouched. Verify check 4 catches breakage.
- Override pattern preserved — P2 doesn't touch FunctionCommand.

### Exit criteria

- Every `make*ToGo` function emits `&Node{...}`; no `NewMapValue` calls in the AST-node emit path (user-level `MapLiteral` map values are unrelated and stay).
- `evalXxx` Go functions emitted for every node kind, covering today's `evaluateXxx` semantics.
- `./scripts/test.sh` passes; verify.sh checks 1–4 green.
- `./scripts/bench.sh phase2-typed-ast` ≥1.5× over phase1.
- Check 5 re-baselined and bit-identical at phase end.

---

## Phase 2.5 — Activate Resolver Annotations (added 2026-05-18)

### Problem

After P2 shipped structurally, the resolver pass (`resolveScopes` at `src/interpreter.s:1616`, plus `resolveBlockStatement` / `resolveFunctionDeclaration` / `resolveIdentifier` / `analyzeIsStatic`) annotates every AST MapValue node with:

- `resolvedKind` ∈ {`"global"`, `"local"`, `"captured"`}
- `resolvedOrigin` ∈ {`"param"`, `"let"`, `"def"`, `"lib"`, `null`}
- `resolvedName` (mangled, Go-safe identifier from `mangle` at `src/interpreter.s:1243`)
- `resolvedAtRoot` (true iff scope's parent is null)
- `resolvedScope` / `resolvedLocals` / `resolvedParamLocals` (per-scope declaration metadata)
- `resolvedIsStatic` (true iff the function body emits no `ctx.Get`/`Update`/`Create`)

**No `*ToGo` emitter reads any of these.** Every `&Node{...}` literal is emitted with the raw user-source name, and `evalIdent` does `ctx.Get(n.name)` — chain-walk + Go-map probe — at runtime. For library globals like `puts`, `gets`, `len`, the walk goes all the way to root every time.

The optimization infrastructure is present and paid for; only the projection + read sites are missing.

### New shape (emitted Go)

#### Resolver-projected fields on `Node`

These already exist on the emitted `Node` struct (`src/interpreter.s:5174-5192`) — `resolvedKind uint8`, `resolvedSlot int32`, `resolvedName string`, `isStatic bool`. They are zero-valued today. P2.5 starts writing them.

```go
const (
    rkGlobal  uint8 = 0  // top-level let / def / library
    rkParam   uint8 = 1  // function parameter
    rkLocal   uint8 = 2  // function-local let
    rkUpvalue uint8 = 3  // captured from enclosing scope
    rkLib     uint8 = 4  // root-context library function (puts/gets/...)
)
```

`resolvedSlot int32` stays zero-valued at this phase (P4 populates it). `resolvedName` carries the Go-safe mangled name when the identifier is a function-decl reference targeted at a static-impl Go function (P2.5b — D2 reborn). `isStatic` (currently dead) repurposed as `Node.skipCtxLookup`: when the resolver proved the binding can be reached without a `ctx.Get` map probe, set `true`.

#### Codegen: `identifierToGo` projects resolver annotations

```ij
def identifierToGo(self) {
    print('&Node{kind: nkIdent, name: "' + self["name"] + '"');
    if (self["resolvedKind"] != null) {
        print(', resolvedKind: ' + resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
    }
    print('}');
}
```

`resolverKindCode(kind, origin)` is a new emitter helper that maps the IJ-side string-tagged annotation (`"global"`+`"lib"` ⇒ `rkLib`; `"local"`+`"param"` ⇒ `rkParam`; etc.) to the numeric `rk*` constant emitted at runtime.

#### Runtime: `evalIdent` switches on `resolvedKind`

```go
func evalIdent(n *Node, ctx *Context) (Value, bool) {
    switch n.resolvedKind {
    case rkParam, rkLocal:
        return ctx.GetLocal(n.name), false   // skip parent walk
    case rkLib:
        return rootCtx.GetLocal(n.name), false  // direct root lookup
    case rkUpvalue:
        return ctx.parent.GetLocal(n.name), false  // single-hop walk (depth=1)
    }
    return ctx.Get(n.name), false  // fallback: rkGlobal or unannotated
}
```

`Context.GetLocal(name)` is a new method that probes only `c.variables[name]` without walking parents. `rootCtx` is a top-level `*Context` reference captured at program start; `programToGoPhase2` already creates `ctx := NewContext(nil)` once at `func main()` entry, so capturing it as a package-level `var rootCtx *Context` is a one-line emit change.

#### `evalAssign` short-circuits on annotation

```go
func evalAssign(n *Node, ctx *Context) (Value, bool) {
    v, ret := eval(n.right, ctx); if ret { return v, true }
    switch n.resolvedKind {
    case rkLocal, rkParam:
        ctx.UpdateLocal(n.name, v)  // no Exists chain walk
        return v, false
    case rkGlobal:
        rootCtx.UpdateLocal(n.name, v)
        return v, false
    }
    if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }
    return v, false
}
```

(One `if ctx.Exists` chain walk + one `ctx.Update` chain walk replaced with one direct map probe. Catches the `evalAssign` "two-walks-per-write" cost from the research §2.2.)

#### `evalBlock` skips Context allocation when no `let`

The resolver already computes `resolvedLocals` per block scope. Project that as `Node.list` is unchanged but **add `Node.hasLocals bool`** (one new field) — set by `blockStatementToGo` only when the resolver tagged the block as introducing at least one binding.

```go
func evalBlock(n *Node, ctx *Context) (Value, bool) {
    blockCtx := ctx
    if n.hasLocals {
        blockCtx = NewContext(ctx)
    }
    var last Value
    for _, s := range n.list {
        v, ret := eval(s, blockCtx)
        if ret { return v, true }
        last = v
    }
    return last, false
}
```

This eliminates the per-iteration Context alloc inside `while` loops whose body has no `let` (the `sample.s` shape).

#### `evalCall` skips the wasted `FunctionCommand.Execute` ctx alloc

`FunctionCommand.Execute` (`src/interpreter.s:5119-5121`) creates a `NewContext(c.definitionCtx)` that the closure body then immediately ignores. Drop that alloc:

```go
func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {
    return c.executeFunc(nil, params)  // closure body allocates its own
}
```

The closure body still does `local := NewContext(defCtx)` — which is fine; that is the function's actual local scope. Net: 1 fewer `*Context` alloc per function call.

#### `NewStaticFunctionCommand` becomes the path for `resolvedIsStatic == true` defs

Today `NewStaticFunctionCommand` is a name-only alias for `NewFunctionCommand` (`src/interpreter.s:5128-5130`). Wire `functionDeclarationToGo` to emit `NewStaticFunctionCommand(...)` when `node["resolvedIsStatic"] == true`, and inside `NewStaticFunctionCommand` skip the per-call `NewContext` alloc by re-using a fenced reusable context (the static-impl path: function body emits no `ctx.Get`/`Update`/`Create`, so a re-used ctx is safe). This is the half-step toward D2 — a static def gets called with zero `*Context` allocations on the function-call hot path.

(D2 full reborn — emitting `ij_<name>_impl(ctx, a, b)` fixed-arity Go functions and direct call-site dispatch — is the natural follow-up but is NOT in P2.5 scope. P2.5 ships only the resolver wiring + the cheap static-ctx win. D2 reborn is a separate post-P2.5 task if measurement still falls short.)

### Codegen edit sites

| Emitter | Edit |
|---|---|
| `identifierToGo` (`src/interpreter.s:1922`) | project `resolvedKind` / `resolvedOrigin` into `&Node{kind: nkIdent, ...}` |
| `assignmentStatementToGo` (`735`) | project `resolvedKind` of the LHS |
| `variableDeclarationToGo` (`4336`) | project `resolvedKind` of the binding |
| `functionDeclarationToGo` (`1693`) | emit `NewStaticFunctionCommand` when `resolvedIsStatic == true`; project `resolvedAtRoot` so `evalFuncDecl` can register at root |
| `blockStatementToGo` (`1100`) | emit `hasLocals: true` only when `resolvedLocals` non-empty |

### Runtime emit edits

| Block | Edit |
|---|---|
| `Node` struct (`5174-5192`) | add `hasLocals bool`; keep `resolvedKind`/`resolvedSlot`/`resolvedName`/`isStatic` (currently dead) |
| `eval` dispatch (`5194-5220`) | unchanged — switch on `n.kind` still |
| `evalIdent` (`5221-5223`) | switch on `n.resolvedKind` |
| `evalAssign` (`5258-5263`) | switch on `n.resolvedKind` |
| `evalBlock` (`5275-5285`) | gate `NewContext` on `n.hasLocals` |
| `evalFuncDecl` (`5327-5339`) | add `rootCtx` capture path for top-level decls |
| `Context` (`5078-5106`) | add `GetLocal` / `UpdateLocal` (single-level) methods |
| `FunctionCommand.Execute` (`5119-5121`) | drop the `NewContext(c.definitionCtx)` alloc |
| `goLibPrefix` preamble | add `var rootCtx *Context` declaration; `programToGoPhase2` assigns it after `ctx := NewContext(nil)` |

### Risks

- **Deletes `evalAssign` "shadowing" semantics.** Today's `evalAssign` (`5258-5263`) creates a local binding on assignment if the name doesn't exist anywhere on the chain — IJ's idiom for "assignment-also-declares". The resolver knows whether the LHS was previously declared at any scope; for unannotated nodes we keep the old fallback. Any node where the resolver did NOT annotate must continue to fall through to the chain-walk fallback. Verify with `test.s`.
- **Override pattern preservation.** `let oldX = X; def X(...) { oldX(...) }` works today because `ctx.Update` walks parents. P2.5 keeps that path on the unannotated fallback; the resolver will mark the rebound `X` with `resolvedKind=rkGlobal` and route through `rootCtx.UpdateLocal`. Verify `verify.sh` check 4 (MCP, which depends on the override pattern) at every P2.5 commit.
- **`rootCtx` global is mutable from any goroutine.** The interpreter is single-threaded; not a real concern but warrants a comment in the emit.
- **`hasLocals` determinism.** `blockStatementToGo` reads `node["resolvedLocals"]`, written deterministically by the resolver in source order. Should be deterministic; verify with `verify.sh` check 5.
- **`NewStaticFunctionCommand` re-used ctx aliasing.** The static-impl invariant is "no `ctx.Create` / `ctx.Update`" inside the body — but the body STILL has params, which are bound at call time. Re-using a single ctx across nested calls breaks recursion. Two options: (a) keep `NewContext` per call but skip the inner block's redundant ctx (cheap; covered by `hasLocals`); (b) defer the static-ctx pooling to a follow-up. **Pick (a) for P2.5.** The dead `NewStaticFunctionCommand` alias is renamed but stays semantically identical; the actual win is the `evalBlock` `hasLocals` gate.

### Exit criteria

- Resolver annotations are projected into Node by `identifierToGo`, `assignmentStatementToGo`, `variableDeclarationToGo`, `functionDeclarationToGo`, `blockStatementToGo`.
- `evalIdent`, `evalAssign`, `evalBlock` switch on annotations and skip chain walks / context allocs in the fast path.
- `./scripts/test.sh` passes.
- `./scripts/verify.sh` checks 1–4 green; check 5 re-baselined and bit-identical at phase end.
- `./scripts/bench.sh phase2_5-resolver-wired` ≥ 1.5× over `p2-no-refresh = 1m20.478s` (target 2–3× given the per-eval frequency of `evalIdent`/`evalBlock`).
- Cumulative speedup vs `phase0-baseline = 1m11.153s` ≥ 1.3×. (Today's HEAD is 0.88× — the cleanup-induced regression is forgiven only by net post-cleanup gain; P2.5 must crawl back over 1.3× cumulative or it's not a phase, just churn.)

### Out of scope for P2.5

- D2 full reborn (emitting `ij_<name>_impl` fixed-arity Go functions + direct call-site dispatch).
- D3 reborn (raw-bool `EqualsBool`/`LessThanBool` helpers wired into `evalIf`/`evalWhile`).
- Slot-indexed contexts (Phase 4 territory).
- String interning (Phase 3 territory).

If P2.5 hits ≥10× cumulative, **stop and ship.** Otherwise continue to P3 (interning) → P4 (slot-indexed contexts) per original ordering.

---

## Phase 3 — String Interning + Constant Singletons

### Problem

After P1, scalar `Value` no longer boxes, but `Value{tag: tString, s: "..."}` for operator literals, type tags, etc. still creates string headers. `null` / `true` / `false` / small ints reconstructed everywhere.

### Fix (emitted Go runtime)

```go
var (
    vNull    = Value{tag: tNull}
    vTrue    = Value{tag: tBool, b: true}
    vFalse   = Value{tag: tBool, b: false}
    vEmpty   = Value{tag: tString, s: ""}
    smallInt [256]Value     // indexed -128..127
    strPool  []Value        // populated at init from codegen-collected literals
)

func init() {
    for i := range smallInt { smallInt[i] = Value{tag: tInt, i: int64(i - 128)} }
}

func vInt(i int64) Value {
    if i >= -128 && i < 128 { return smallInt[i+128] }
    return Value{tag: tInt, i: i}
}

func vStr(idx uint32) Value { return strPool[idx] }
```

### Codegen

During IJ→Go transpile, emitter collects every string literal into a global pool, deduping by content. Each literal emits `strPool[N]`. P2's AST nodes already carry `sIdx uint32` indexing the same pool. Two consumers, one table.

`null` / `true` / `false` literals emit `vNull` / `vTrue` / `vFalse`. Boolean returns from D3 helpers route through these.

### Risks

- String-pool ordering must be deterministic across two consecutive transpiles (check 5). Order pool by first-appearance in a documented traversal order. Same order = same indices = bit-identical Go.
- `strPool` indices must survive resolver → emit. Store on IJ-side MapValue AST as `node["sIdx"]`, project into Go `Node` at codegen.
- Pool memory cheap; init cost paid once.

### Exit criteria

- No `Value{tag: tString, s: "..."}` inline literals in emitted Go — all via `strPool`.
- `null`/`true`/`false` go via singletons.
- `./scripts/bench.sh phase3-intern` ≥1.2× over phase2 (target 1.3–1.8×).
- All verify.sh checks green.

---

## Phase 4 (Stretch) — Slot-Indexed Contexts

Only run if cumulative speedup after P1–P3 still < 10×.

### Problem

`Context` today is roughly:

```go
type Context struct {
    parent *Context
    vars   map[string]Value
}
```

`ctx.Get("x")` = map lookup + hash + chain. After D1 `skipCtx` + C-series static resolution, non-static paths still walk the chain.

### Fix

Resolver assigns numeric `slot int32` per scope. Replace map with `[]Value`:

```go
type Context struct {
    parent *Context
    slots  []Value
    names  []string         // debug only
}

func (c *Context) GetSlot(depth, slot int) Value {
    cur := c
    for i := 0; i < depth; i++ { cur = cur.parent }
    return cur.slots[slot]
}
func (c *Context) SetSlot(depth, slot int, v Value) {
    cur := c
    for i := 0; i < depth; i++ { cur = cur.parent }
    cur.slots[slot] = v
}
```

Most loads have `depth == 0` (local) or `depth` statically known — codegen unrolls the parent walk into chained `.parent.parent.slots[N]`.

Global scope keeps name-indexed lookup (needed for dynamic `def` overrides + MCP). Per-function and per-block scopes go slot-indexed.

### Codegen

Resolver pass already assigns `resolvedKind`. Add slot assignment: per scope, give every `let`/param a numeric index in declaration order. Emit `ctx.slots[N]` instead of `ctx.Get("x")` for local/param reads.

### Risks

- Slot assignment must be deterministic (check 5). Index in declaration order; resolver already walks deterministically.
- Override pattern at top level still needs name-based dispatch — top-level globals stay map-based.
- Block scopes with conditional `let`: pre-walk the block to count slots, allocate upfront.

### Exit criteria

- `./scripts/bench.sh phase4-slots` ≥1.3× over phase3.
- All verify.sh checks green.
- If still < 10× after P4: document shortfall in `bench.log`; propose tagged-pointer `Value` or bytecode VM as out-of-scope follow-up.

---

## Verification

### Per-phase gate (run before merge)

1. `./scripts/test.sh` — golden test suite passes.
2. `./scripts/verify.sh` — checks 1–4 green (functional, golden, MCP, JSON-RPC).
3. `./scripts/verify.sh` — check 5 bit-identical fixed-point. Capture new baseline at phase start (`--capture`), confirm bit-identical at phase end.
4. `./scripts/bench.sh phaseN-<name>` — speedup ≥ phase's exit-criteria threshold. Drop-rule: revert if regress vs predecessor.

### Benchmarks

Primary: `scripts/selfhosted_interpreter.sh sample.s` (existing, documented headline metric).

Secondary (new file `src/bench_eval.s`):

```ij
def fib(n) {
  if (n < 2) { return n; }
  return fib(n-1) + fib(n-2);
}
puts(fib(25));

def bubbleSort(arr) {
  let n = len(arr);
  let i = 0;
  while (i < n) {
    let j = 0;
    while (j < n - i - 1) {
      if (arr[j] > arr[j + 1]) {
        let temp = arr[j];
        arr[j] = arr[j + 1];
        let jPlusOne = j + 1;
        arr[jPlusOne] = temp;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return arr;
}
// 50-element reverse-sorted input
let xs = [];
let k = 50;
while (k > 0) { xs = push(xs, k); k = k - 1; }
bubbleSort(xs);
puts(xs[0]);
puts(xs[49]);
```

Wired into `scripts/bench.sh` as a fourth timed block. Catches eval-path regressions sample.s under-represents.

Native check (`scripts/native_interpreter.sh src/sample.s`) tracked as regression detector — should stay flat.

### Bench labels

`phase0-baseline`, `phase1-tagged-value`, `phase2-typed-ast`, `phase2_5-resolver-wired`, `phase3-intern`, `phase4-slots`.

(`p1-dead-code-cleanup`, `p2-no-refresh` are intra-phase remediation labels written 2026-05-17. Treat `p2-no-refresh = 1m20.478s` as the P2.5 entry floor.)

---

## Risks (Cross-Cutting)

| Risk | Mitigation |
|---|---|
| Fixed-point check 5 breaks unrecoverably | Use `compile-local.sh` (not Docker). Re-baseline at every commit during phase to catch divergences early. |
| MCP silently broken | verify.sh check 4 mandatory pre-merge. `mcp_eval.s` rebuilt and tested against golden JSON-RPC every phase. |
| Override pattern broken by codegen change | Preserve `lastDefIndex` pre-pass across all phases. Test fixture exercising override-pattern semantics in test.s. |
| IJ string `\"` quirk reintroduced | Code review: every new `puts(...)` of Go syntax that needs `"` uses `chr(34)`. |
| D4-style "looks faster, is slower" regression | Drop-rule: ≥1.3× over predecessor or revert. No exceptions. |
| Self-bootstrap divergence (binary not from latest source) | Always `compile-local.sh`. Never Docker path during measurement. |

## Rollout

1. Branch off `main`. Capture verify.sh baseline + `scripts/bench.sh phase0-baseline`.
2. Land P1 — tagged-union Value — series of commits. Final commit re-baselines check 5, logs `phase1-tagged-value`. Merge.
3. Land P2 — typed AST nodes. Largest phase. Same protocol. Log `phase2-typed-ast`. Merge.
4. Land P3 — interning + singletons. Log `phase3-intern`. Merge.
5. Measure cumulative. If ≥10×, **stop, ship**. Update README perf section.
6. Else: P4 — slot-indexed contexts. Log `phase4-slots`. Re-measure. Update README.

### Stop conditions

- ≥10× hit at any phase → stop, ship, update README.
- All four phases shipped, still <10× → write `bench.log` summary, propose tagged-pointer `Value` (single uintptr w/ low-bit tag) or bytecode VM as out-of-scope follow-up.

### Out of scope

- New language features.
- Lexer/parser optimization (parser cost amortized; AST shape changes are P2's job).
- GC tuning (no GOGC fiddling).
- Bytecode VM, JIT, tagged-pointer Value.

## Open Questions

None at design-approval time. Implementation plan (writing-plans skill) will surface task-level questions.
