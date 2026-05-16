# Self-Hosted Interpreter Perf — ≥10× Design

Date: 2026-05-16
Status: Approved, ready for implementation planning.

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
| P1 | Tagged-union `Value` struct | 2–4× | Spec'd |
| P2 | Typed AST struct nodes | 2–4× | Spec'd |
| P3 | String interning + null/bool/small-int singletons | 1.3–1.8× | Spec'd |
| P4 (stretch) | Slot-indexed contexts | 1.5–2× | Conditional — only if P1–P3 < 10× |

Multiplicative range if all four land: ~6–58×. Realistic 10–15×. Stop after first phase that crosses 10× cumulative.

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

`phase0-baseline`, `phase1-tagged-value`, `phase2-typed-ast`, `phase3-intern`, `phase4-slots`.

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
