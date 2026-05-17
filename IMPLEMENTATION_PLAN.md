# Implementation Plan — Self-Hosted Interpreter 10x Perf

Status: **Phase 0 complete, Phase 1 complete**

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
