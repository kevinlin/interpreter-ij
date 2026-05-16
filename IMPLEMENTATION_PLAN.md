# Implementation Plan — Self-Hosted Interpreter 10x Perf

Status: **Phase 0 complete, Phase 1 in progress**

## Phase 0 — Baseline Capture ✅

- [x] Task 0.1: Capture verify.sh golden + bench baseline — commit `d04bdf9`
- [x] Task 0.2: Add eval-heavy secondary benchmark (`src/bench_eval.s`) + extend `bench.sh`

Baseline measurements (macOS/arm64):
- selfhosted_interpreter.sh sample.s: ~1m16s real
- selfhosted_interpreter.sh bench_eval.s: ~1m25s real (fib(22) + bubbleSort(30))

## Phase 1 — Tagged-Union Value 🔄

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

1. **[ ] verify.sh check 5 — double self-transpile fixed-point**
   - Legacy binary (built from commit `80f3358`) has old `goLibPrefix` that emits old types; even though `interpreter.s` source now emits Value2 codegen, the legacy binary's runtime emits old-type references in the raw `app.go` it produces.
   - Bridge binary approach: `scripts/fix_app_go.py` post-processes the legacy binary's `app.go` to produce a self-consistent Value2 build.
   - fix_app_go.py currently handles: `NewNullValue→v2Null`, `var Value→var Value2`, bool helpers. Map/array wrapping (`NewMapValue2AsValue`/`NewArrayValue2AsValue`) needs surgical per-line fixes (~12 remaining errors) due to context sensitivity.
   - Next step: finalize bridge binary build by fixing the ~12 map/array errors in app.go.

2. **[ ] Cleanup: after check 5 passes**
   - Remove old `Value` interface + per-type structs
   - Rename `Value2`→`Value`, `ArrayValue2`→`ArrayValue`, `Context2`→`Context`, `MapValue2`→`MapValue`, `KeyValuePair2`→`KeyValuePair`, `FunctionCommand2`→`FunctionCommand`
   - Re-baseline verify.sh check 5

### Design note

Self-bootstrap constraint forces parallel type hierarchies during transition. Clean bootstrapped binary (built from pre-Value2 source) used to break chicken-and-egg: Value2 types added to `goLibPrefix`, codegen switched to emit Value2 code. The old binary emits old-style Go referencing old types; new binary emits Value2-style Go. Both coexist in emitted runtime until old codegen path fully replaced.

### Bridge binary approach

1. The legacy (pre-Value2) native binary transpiles the updated `interpreter.s` to `app.go`.
2. `scripts/fix_app_go.py` post-processes `app.go` to fix old-type references emitted by the legacy binary's runtime:
   - `result=NewNullValue()` → `result=v2Null()`
   - `var ij_XXX Value =` → `var ij_XXX Value2 =`
   - 6 old bool helpers (`EqualsBool` etc.) → Value2 tag-check versions
   - `NewMapValue2(` / `NewArrayValue2(` → wrapped with `NewMapValue2AsValue(` / `NewArrayValue2AsValue(` (in progress — ~12 remaining context-sensitive sites)
3. The fixed `app.go` compiles via `go build` to a bridge binary.
4. The bridge binary transpiles `interpreter.s` again — this time emitting fully Value2-clean code with no old-type references, producing the final binary.

### Known state

- verify.sh checks 1-4 pass
- verify.sh check 5 failing — bridge binary incomplete (~12 map/array wrapping errors in app.go)
- After bridge binary works, cleanup pass renames `*2` types and re-baselines check 5

## Phase 2 — Typed AST Struct Nodes ⬜

Replace MapValue-backed AST nodes with typed Go `Node` struct in transpiled output.

Status: Not started.

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
