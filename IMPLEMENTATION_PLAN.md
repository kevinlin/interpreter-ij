# Implementation Plan — Self-Hosted Interpreter 10x Perf

Status: **Phase 0 complete, Phase 1 complete, Phase 2 in progress**

## Phase 0 — Baseline Capture ✅

- [x] Task 0.1: Capture verify.sh golden + bench baseline — commit `d04bdf9`
- [x] Task 0.2: Add eval-heavy secondary benchmark (`src/bench_eval.s`) + extend `bench.sh`

Baseline measurements (macOS/arm64):
- selfhosted_interpreter.sh sample.s: ~1m16s real
- selfhosted_interpreter.sh bench_eval.s: ~1m25s real (fib(22) + bubbleSort(30))

## Phase 1 — Tagged-Union Value ✅

Replace `Value` interface with `Value` tagged-union struct in emitted Go runtime.
Edits: `src/interpreter.s` runtime emit block (~5159-6402) + all `*ToGo` codegen functions.

### Completed

**Type definitions:**
- [x] `Value2` tagged-union struct with tag constants (`t2Null` through `t2Invalid`)
- [x] `Value2` struct fields fixed (`arr *ArrayValue2`, `m *MapValue2`, `cmd Command2`)
- [x] Full method set on `Value2`: `IsTruthy`, `IsInvalid`, `Length`, `IntValue`, `String`, `ValueString`, `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`, `Type`, `Append`
- [x] Helper constructors: `v2Null`, `v2Bool`, `v2Int`, `v2Double`, `v2String`, `v2Array`, `v2Map`, `v2Func`, `v2Invalid`
- [x] Parallel types: `ArrayValue2`, `MapValue2`, `KeyValuePair2`, `Context2`, `Command2`, `FunctionCommand2`
- [x] `NewStaticFunctionCommand2` added

**Runtime wiring:**
- [x] `registerLibraryFunctions2` added with all 33 library functions using Value2 types
- [x] `main()` creates both `ctx` (old `*Context`) and `ctx2` (`*Context2`) for incremental migration

**Codegen switched to Value2:**
- [x] `numberLiteralToGo`, `stringLiteralToGo`, `booleanLiteralToGo`, `nullLiteralToGo`
- [x] `arrayLiteralToGo` uses `NewArrayValue2`
- [x] `mapLiteralToGo` uses `NewMapValue2` + `KeyValuePair2`
- [x] `variableDeclarationToGo`
- [x] `functionDeclarationToGo` uses `v2Func` wrapping + Value2 types
- [x] `emitQueuedImpls` uses Value2 types
- [x] `identifierToGo` uses `ctx2.Get`
- [x] `assignmentStatementToGo` uses `ctx2.Update`
- [x] `blockStatementToGo` uses `NewContext2`
- [x] `CallExpression_toGo` uses `ctx2` + `NewArrayValue2`
- [x] Package-level var declarations use Value2 type

**Verification:**
- [x] verify.sh checks 1-4 pass (parse error in checks 1-2 was fixed)
- [x] `refreshToGoPointers` added to `makeInterpreter` — refreshes pointer-based codegen hooks after self-transpile so evaluator emits current codegen functions
- [x] Bool helpers in `goLibPrefix` updated to use `Value2` tag checks (source ~line 7244-7269)
- [x] `mapLiteralToGo` and `arrayLiteralToGo` updated to wrap results in `Value2` (lines 4509, 73)

### Remaining

(None — Phase 1 complete)

### Design note

Self-bootstrap constraint forced parallel type hierarchies during transition. Clean bootstrapped binary used to break chicken-and-egg. Post-transition, single `Value` tagged-union struct replaces both old `Value` interface and `Value2` struct. `fix_app_go.py` bridges legacy binary output by removing old types + renaming Value2→Value.

### Bridge binary approach (via compile-local.sh)

1. The legacy native binary transpiles `interpreter.s` to `app.go` (emits compiled-in old + Value2 types).
2. `scripts/fix_app_go.py` post-processes `app.go`: removes old type system, renames Value2→Value, injects bool helpers + AsValue wrappers.
3. `go build` produces the binary.
4. `compile-local.sh` runs this same pipeline for both passes, producing bit-identical binaries (verify.sh check 5 passes).

### Known state

- verify.sh checks 1–5 pass, bit-identical double self-transpile confirmed
- All types renamed: `Value` (tagged-union struct), `ArrayValue`, `MapValue`, `Context`, `Command`, `FunctionCommand`, `KeyValuePair`
- Old `Value` interface + per-type structs removed from goLibPrefix
- `fix_app_go.py` rewritten to remove old types + rename Value2→Value in legacy binary output
- Committed binary at repo root kept as pre-cleanup version (required for transpilation pipeline)
- New cleaned binary has stack overflow in `refreshToGoPointers` (FunctionCommand2→FunctionCommand lacks skipCtx), needs investigation in Phase 2

## Phase 2 — Typed AST Struct Nodes

### Context

Replace MapValue-backed AST emission with typed Go `Node` struct literals in transpiled output. IJ-side parser still builds MapValues. Only transpile output changes.

Each `*ToGo` function currently emits direct Go code (if/while/expr). After Phase 2, each emits `&Node{kind: nkXxx, ...}` struct literals. New `eval()` runtime walks the Node tree. Eliminates map lookups, string comparisons, callable-entry indirection per evaluation step.

### Key Design Decisions

1. **Return sentinel: `(Value, bool)` not tReturn tag** — `eval()` returns `(Value, bool)` where `bool==true` = "return value, propagate." Cleaner than modifying Value struct with subTag field.

2. **Compact Node struct** — reuse `left`/`right`/`body`/`list`/`name` fields across kinds. Fewer fields = better cache.

3. **Static resolution dropped** — C3/C4 direct Go var access (`ij_x`) can't work with tree-walking eval(). All variable access goes through `ctx.Get/Update/Create`.

4. **D2 preserved with adaptation** — impl function bodies become Node trees. Call site still emits direct `ij_name_impl(ctx, eval(n, ctx), ...)` bypassing ArrayValue alloc.

5. **functionDeclarationToGo emits Go closures** — functions stay as Go closures (for Go interop). Only body becomes Node tree.

### Node Struct Fields

```go
type Node struct {
    kind         uint8
    op           uint8
    pos          uint32   // line<<16 | col
    sIdx         uint32   // string-pool index (Phase 3)
    iVal         int64
    dVal         float64
    bVal         bool
    left         *Node    // first child (generic)
    right        *Node    // second child (generic)
    list         []*Node  // child list (blocks, args, elements, pairs)
    body         *Node    // function/if/while body
    params       []string // function parameter names
    name         string   // identifier/function/variable name
    resolvedKind uint8    // resolver annotation
    resolvedSlot int32    // P4 slot
    resolvedName string   // resolver annotation
    isStatic     bool     // D1 annotation
}
```

### Node Kind Constants

nkInfix=0, nkPrefix=1, nkAssign=2, nkIndexAssign=3, nkExprStmt=4, nkBlock=5, nkVarDecl=6, nkFuncDecl=7, nkIfStmt=8, nkWhileStmt=9, nkReturn=10, nkIdent=11, nkIntLit=12, nkDoubleLit=13, nkStringLit=14, nkBoolLit=15, nkNullLit=16, nkArrayLit=17, nkMapLit=18, nkIndex=19, nkCall=20, nkProgram=21

### Operator Constants

opAdd=0, opSub=1, opMul=2, opDiv=3, opMod=4, opEq=5, opNeq=6, opLt=7, opLte=8, opGt=9, opGte=10, opAnd=11, opOr=12, opNot=13, opNeg=14

### Implementation Steps

#### Step 1: Add opCodeFor helpers to interpreter.s (~line 855 area)
- `infixOpCodeFor(op)` — maps "+","-","*","/","%","==","!=","<","<=",">",">=","&&","||" → "opAdd"..."opOr"
- `prefixOpCodeFor(op)` — maps "-","!" → "opNeg","opNot"

#### Step 2: Add Node types + eval runtime to goLibPrefix
Insert before Value tagged-union comment (~line 5146). Emit via puts():
- 22 nk constants block
- 15 op constants block
- Node struct
- eval() dispatch: switches on n.kind, returns (Value, bool)
- 16 eval functions: evalInfix, evalPrefix, evalCall, evalIndex, evalArrayLit, evalMapLit, evalExprStmt, evalBlock, evalIf, evalWhile, evalReturn, evalVarDecl, evalFuncDecl, evalAssign, evalIndexAssign, evalIdent
- All eval functions return (Value, bool)

Build test: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_s2 && echo OK`

#### Step 3: Atomic rewrite of ALL 21 *ToGo emitters
All must change in ONE commit (parent consumes child output).

**Leaf literals (5):**
- nullLiteralToGo → `&Node{kind: nkNullLit}`
- numberLiteralToGo → `&Node{kind: nkIntLit, iVal: N}` or `nkDoubleLit, dVal: N.N`
- stringLiteralToGo → `&Node{kind: nkStringLit, name: "escaped"}`
- toGoBooleanLiteral → `&Node{kind: nkBoolLit, bVal: true/false}`
- identifierToGo → `&Node{kind: nkIdent, name: "x"}` (no more static resolution)

**Expressions (6):**
- infixExpressionToGo → `&Node{kind: nkInfix, op: <infixOpCodeFor(op)>, left: <L>, right: <R>}`
- PrefixExpression_toGo → `&Node{kind: nkPrefix, op: <prefixOpCodeFor(op)>, right: <R>}`
- CallExpression_toGo → D2: `ij_name_impl(ctx, eval(<a1>,ctx),...)`; non-D2: `&Node{kind: nkCall, left: <callee>, list: []*Node{<args>}}`
- IndexExpression toGo → `&Node{kind: nkIndex, left: <coll>, right: <idx>}`
- arrayLiteralToGo → `&Node{kind: nkArrayLit, list: []*Node{<elems>}}`
- MapLiteral toGo → `&Node{kind: nkMapLit, list: []*Node{<k0>,<v0>,<k1>,<v1>}}` (interleaved)

**Statements (8):**
- toGoJsonExpressionStatement → `&Node{kind: nkExprStmt, left: <expr>}`
- blockStatementToGo → `&Node{kind: nkBlock, list: []*Node{<stmts>}}` (remove hasLocal/result logic)
- ifStatementToGo → `&Node{kind: nkIfStmt, left: <cond>, body: <then>, right: <else or nil>}`
- WhileStatement toGo → `&Node{kind: nkWhileStmt, left: <cond>, body: <body>}`
- ReturnStatement_toGo → `&Node{kind: nkReturn, right: <value or nil>}`
- variableDeclarationToGo → `&Node{kind: nkVarDecl, name: "x", right: <init or nil>}`
- assignmentStatementToGo → `&Node{kind: nkAssign, name: "x", right: <value>}`
- indexAssignmentStatement_toGo → `&Node{kind: nkIndexAssign, left: <coll>, right: <idx>, body: <value>}`

**Function declaration:**
- functionDeclarationToGo → emits Go closure with Node tree body. D2 path preserved. Params still bound via `params.Get`. Body emitted as `eval(<bodyNode>, ctx)` returning `(Value, bool)`.

**Program entry:**
- program["toGo"] → `result, _ = eval(&Node{kind: nkProgram, list: []*Node{<stmts>}}, ctx)`

#### Step 4: Update emitQueuedImpls
D2 impl bodies: `result, _ = eval(<bodyNode>, ctx)`

#### Step 5: Remove dead code
- conditionToGoBool (lines 3463-3503) — no longer called
- isGoVarAssign block in blockStatementToGo (lines 1220-1244) — no longer needed
- Static resolution dispatching in identifierToGo, assignmentStatementToGo — simplify to just emit name field

#### Step 6: Update fix_app_go.py
Add Phase 2 sanity check: verify `nkProgram` present in output. Old type removal + Value2 rename steps should not affect Node types.

#### Step 7: Verify
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_stage1  # build
./scripts/test.sh                                            # functional
echo hi | ./scripts/selfhosted_interpreter.sh src/sample.s   # sanity
./scripts/verify.sh                                          # 5 checks
./scripts/bench.sh phase2-typed-ast                          # benchmark
```

### Risk Mitigation

1. **IJ string escaping**: No `\"` support. Use `chr(34)` for embedded quotes in Go string literals emitted via puts().
2. **Closure-based toGo**: WhileStatement, MapLiteral, IndexExpression use closures. Only emission inside closure changes.
3. **refreshToGoPointers**: No changes needed — rebinds by type string, names unchanged.
4. **Self-bootstrap fixed point**: Map iteration order is main nondeterminism source. Watch for this in Stage 1 vs Stage 2 diff.
5. **evalFuncDecl scope**: Must capture definition context in closure, create local scope as child of definition context (not calling context). This preserves lexical scoping.

### Files Modified
- `src/interpreter.s` — all changes
- `scripts/fix_app_go.py` — Phase 2 sanity check only
- `interpreter_mac_arm64` — regenerated at phase end

## Phase 2 — Typed AST Struct Nodes 🔄

Status: **Partial — runtime emitted, codegen partially switched, check 5 failing**

### Completed

- [x] Node struct + nk/op constants in goLibPrefix (line 5455-5516)
- [x] eval() dispatch + per-kind eval functions in goLibPrefix (line 5516-5696)
- [x] `opCodeFor` helper (line 846)
- [x] `refreshToGoPointers` converted to iterative (fixes stack overflow)
- [x] `IndexExpression.toGo` fixed — children emitted inside struct literal (not outside)
- [x] `indexAssignmentStatement_toGo` fixed — same pattern
- [x] All `*ToGo` leaf/expression/statement emitters → `&Node{...}` literals

### Remaining

- [ ] **check 5 failing**: puts()/print() mixing in `blockStatementToGo` — nested FunctionDeclarations emit via puts() (package-level Go) inside blocks that use print() for Node trees. Resulting Go code has struct literals concatenated with Go statements without separators.
- [ ] Need fb2b299 binary as transpiler bridge (committed binary broken)
- [ ] `programToGo` needs to separate FunctionDeclarations from Node tree elements
- [ ] `blockStatementToGo` needs to coordinate puts() and print() output correctly
- [ ] `whileStatementToGo` and `ifStatementToGo` wrapper adaptation for Node trees

### Approach for fix

Option A: Revert *ToGo emitters to old style (Value literals, not Node trees). Keep goLibPrefix additions + iterative refreshToGoPointers. This makes check 5 pass immediately.

Option B: Fix blockStatementToGo's emission to properly separate FunctionDeclarations (puts) from Node tree statements (print). More complex but preserves Phase 2 codegen.

### Known issues

- Committed binary at dba0ddc is broken (stack overflow). Use fb2b299 binary instead.
- `NewStaticFunctionCommand` and `NewFunctionCommand` are identical (no skipCtx field) — static dispatch doesn't actually skip context creation.

## Phase 3 — String Interning + Singletons ⬜

Global string pool, null/bool/small-int singletons.

Status: Not started (conditional on P1+P2 < 10x).

## Phase 4 — Slot-Indexed Contexts ⬜

Slot-indexed local/param access. Conditional stretch goal.

Status: Not started (conditional on P1+P2+P3 < 10x).

## Notes

- Use `compile-local.sh` not Docker for verification
- check 5 (bit-identical fixed-point) may break mid-phase, re-baseline at phase end
- Drop-rule: phase < 1.3x over predecessor → revert
