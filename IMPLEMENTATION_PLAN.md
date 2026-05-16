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

- [x] Added `Value2` tagged-union struct with tag constants (`t2Null` through `t2Invalid`)
- [x] Added `Value2` methods: `IsTruthy`, `IsInvalid`, `Length`, `IntValue`, `String`, `ValueString`, `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`, `Type`, `Append`
- [x] Added helper constructors: `v2Null`, `v2Bool`, `v2Int`, `v2Double`, `v2String`, `v2Array`, `v2Map`, `v2Func`, `v2Invalid`
- [x] Added parallel types: `ArrayValue2`, `MapValue2`, `KeyValuePair2`, `Context2`, `Command2`, `FunctionCommand2`
- [x] Updated codegen functions: `numberLiteralToGo`, `stringLiteralToGo`, `toGoBooleanLiteral`, `nullLiteralToGo`, `arrayLiteralToGo`, `PrefixExpression_toGo`, `CallExpression_toGo`, `makeMapLiteral.toGo`, `variableDeclarationToGo`
- [x] Tests pass; verify.sh checks 1-4 pass

### Remaining

- [ ] Update `functionDeclarationToGo` to emit `Context2`/`ArrayValue2`/`Value2`
- [ ] Update `emitQueuedImpls` to emit `Context2`/`ArrayValue2`/`Value2`
- [ ] Add `Context2`-based `main()` and `registerLibraryFunctions2()` in runtime emit
- [ ] Remove old `Value` interface + per-type structs
- [ ] Rename `Value2` → `Value`, `ArrayValue2` → `ArrayValue`, etc.
- [ ] Re-baseline check 5 (bit-identical fixed-point)

### Known state

- verify.sh check 5 fails (expected mid-phase: old + new runtime coexist)
- Scripts live at repo root, not `scripts/`

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
