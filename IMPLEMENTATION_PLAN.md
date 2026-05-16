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

- [x] `Value2` tagged-union struct with tag constants (`t2Null` through `t2Invalid`)
- [x] Full method set on `Value2`: `IsTruthy`, `IsInvalid`, `Length`, `IntValue`, `String`, `ValueString`, `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`, `Type`, `Append`
- [x] Helper constructors: `v2Null`, `v2Bool`, `v2Int`, `v2Double`, `v2String`, `v2Array`, `v2Map`, `v2Func`, `v2Invalid`
- [x] Parallel types added alongside old types: `ArrayValue2`, `MapValue2`, `KeyValuePair2`, `Context2`, `Command2`, `FunctionCommand2`
- [x] Codegen switched: `numberLiteralToGo`, `stringLiteralToGo`, `toGoBooleanLiteral`, `nullLiteralToGo`, `arrayLiteralToGo`, `PrefixExpression_toGo`, `CallExpression_toGo`, `makeMapLiteral.toGo`, `variableDeclarationToGo`
- [x] Tests pass; verify.sh checks 1-4 pass

### Remaining (critical path)

1. [ ] Update `functionDeclarationToGo` to emit `Context2`/`ArrayValue2`/`Value2` (currently emits old `ctx.Context`/`ArrayValue`/`Value`)
2. [ ] Update `emitQueuedImpls` similarly
3. [ ] Add `ctx2 := NewContext2(nil)` and `registerLibraryFunctions2(ctx2)` in emitted `main()`
4. [ ] Add `Value2`-based library functions: `puts`, `gets`, `push`, `pop`, `len`, `chr`, `ord`, `char`, `substr`, `int`, `string`, `random`, `typeof`, `isArray`, `isMap`, `isNumber`, `isString`, `assert`, `double`, `echo`, `print`, `delete`, `startsWith`, `endsWith`, `trim`, `match`, `findAll`, `replace`, `split`
5. [ ] Change all codegen `ctx.` references to `ctx2.`: `assignmentStatementToGo`, `blockStatementToGo`, `functionDeclarationToGo`, `identifierToGo`, `variableDeclarationToGo`
6. [ ] After all codegen switched: remove old `Value` interface + per-type structs, rename `Value2`→`Value`, `ArrayValue2`→`ArrayValue`, `Context2`→`Context`, `MapValue2`→`MapValue`, `KeyValuePair2`→`KeyValuePair`, `FunctionCommand2`→`FunctionCommand`
7. [ ] Re-baseline verify.sh check 5 (bit-identical fixed-point)

### Design note

Self-bootstrap constraint forces parallel type hierarchies during transition. Old binary emits old-style Go code referencing old types; new binary emits new-style Go code referencing new types. Both must coexist in emitted runtime until old codegen path is fully replaced.

### Known state

- verify.sh check 5 fails (expected mid-phase: old + new runtime coexist)

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
