# Implementation Plan — Self-Hosted Interpreter 10x Perf

Status: **Phase 0 complete, Phase 1 complete, Phase 2 partial (Node tree codegen active; verify.sh 1-5 pass via fb2b299 transpiler; push() + NewArrayValue fixed; Binary B crash root-caused to deep eval recursion in goLibPrefix eval functions; full self-hosted transpile blocked on eval depth)**

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

## Phase 2 — Typed AST Struct Nodes 🔄

Status: **Partial. Node tree codegen active. *ToGo emitters rewritten to emit `&Node{...}`. goLibPrefix emits Node types + eval runtime. refreshToGoPointers iterative. verify.sh 1-5 pass via fb2b299 transpiler. Full self-hosted transpile truncated.**

### Completed

- [x] Node struct + nk/op constants in goLibPrefix
- [x] eval() dispatch + per-kind eval functions in goLibPrefix
- [x] `opCodeFor` helper in interpreter.s
- [x] `refreshToGoPointers` converted to iterative (fixes stack overflow)
- [x] fb2b299 binary used as transpiler bridge (committed binary at dba0ddc has stack overflow, pre-cleanup binary at fb2b299 works)
- [x] Push function bug fixed: `return ele` → `return arr` in goLibPrefix

### Completed: Node tree *ToGo codegen

All 21 `*ToGo` emitters rewritten to emit `&Node{...}` struct literals:
- `numberLiteralToGo`, `stringLiteralToGo`, `booleanLiteralToGo`, `nullLiteralToGo`
- `arrayLiteralToGo`, `mapLiteralToGo`
- `variableDeclarationToGo`, `functionDeclarationToGo`
- `identifierToGo`, `assignmentStatementToGo`
- `blockStatementToGo`, `programToGoPhase2`
- `PrefixExpression_toGo`, `InfixExpression_toGo`, `CallExpression_toGo`, `IndexExpression_toGo`
- `IfExpression_toGo`, `WhileExpression_toGo`
- `ReturnStatement_toGo`, `PrintStatement_toGo`, `ExpressionStatement_toGo`

**Wiring:**
- [x] `goLibPrefix`: main() emission removed (Phase 2 style)
- [x] `programToGoPhase2`: new top-level def emitting main() with Node tree + eval()
- [x] `useNodeTree` flag = true; `makeProgram` conditionally uses `programToGoPhase2`
- [x] `goLibSuffix` and `emitQueuedImpls`: no-ops (D2 dropped)
- [x] Package-level var declarations removed

**Fixes:**
- [x] `opCodeFor` fixed: added "!" → opNot mapping
- [x] `PrefixExpression_toGo` fixed: uses correct op codes for prefix operators (`-` → opNeg, `!` → opNot)

**Verification:**
- [x] test.sh: all pass
- [x] verify.sh: checks 1-5 all pass (using fb2b299 as transpiler)
- [x] Simple programs compile and run correctly with Phase 2 codegen

**Known issues and findings:**

Push() fix:
- [x] Push function in goLibPrefix returned `ele` instead of `arr`. Fixed in source: `return ele` → `return arr` at goLibPrefix emission.
- [x] Confirmed: with push fix, `refreshToGoPointers` correctly rebinds toGo methods to Phase 2 Node tree emitters.

NewArrayValue fix:
- [x] Zero-arg function calls (e.g. `makeInterpreter()`) created `ArrayValue` with nil `values` slice, causing downstream panics.
- [x] Fixed in source: `if elements == nil { return &ArrayValue{values: []Value{}} }` added to `NewArrayValue` in goLibPrefix (`interpreter.s` ~line 5076).
- [x] Same fix patched into `fix_app_go.py` Step 7c so legacy binary output gets the nil-guard.

Binary B crash root-caused:
- [x] Binary B's eval of the 772KB compiled-in Node tree for `interpreter.s` panics with "index out of range [0] with length 0" in a library function during deep eval recursion.
- [ ] Binary A works because Binary 0 emits old-style code (`ij_puts.Execute` calls) alongside a near-empty `programNode`, providing a working transpilation path that doesn't rely on `eval(programNode)`.
- [x] The committed binary (pre-cleanup, `ac2e6f3`) uses its **compiled-in goLibPrefix** (old code), not the source code's goLibPrefix. Source changes to goLibPrefix don't propagate until the committed binary is rebuilt. The `fix_app_go.py` bridge is the mechanism to patch emitted Go code.
- [x] Phase 2 eval functions work correctly for small programs (`test.s`, `sample.s`) but the eval recursion for `interpreter.s`'s 772KB Node tree is too deep. The crash is a bounds-check failure in a string indexing operation within a library function, triggered by deeply nested `evalIf`/`evalBlock` recursion.
- [ ] Binary B crash requires either depth reduction (e.g. iterative eval) or Binary 0 route (old-style codegen) to unblock full self-hosted transpile.

### fix_app_go.py updates

Updated to handle fb2b299 binary's mixed (old + Value2) output — fb2b299 emits both old and new type systems; fix_app_go.py strips old and renames Value2→Value:

- **Step 1** (remove `registerLibraryFunctions`): Conditional — only removes old block when counter vars (`i`, `j`, `k`, `n`) appear after it. fb2b299 emits both old `registerLibraryFunctions` and new `registerLibraryFunctions2`; old removal can incorrectly match the new block if not conditional.
- **Step 5** (bool helpers / `AsValue` wrappers): Conditional — only injects if not already present.
- **Step 6** (rename `Value2`→`Value`): Uses string-literal-safe replacement with Execute call protection (`ctx2.Execute`, `FunctionCommand2.Execute`) to avoid renaming in call expressions.

### Design notes (for when codegen resumes)

Node struct, kind/op constants, and eval runtime are emitted in goLibPrefix and working:

```go
// Node struct: kind, op, pos, sIdx, iVal, dVal, bVal,
// left, right, list, body, params, name, resolvedKind/Slot/Name, isStatic
```

- `eval()` returns `(Value, bool)` — `bool==true` means "return value, propagate."
- `functionDeclarationToGo` emits Go closures with Node tree bodies. Params bound via `params.Get`; body evaluated as `eval(bodyNode, ctx)`.
- Static resolution dropped — all variable access goes through `ctx.Get/Update/Create`.
- D2 impl function bodies become Node trees; call sites emit direct `ij_name_impl(ctx, eval(n, ctx), ...)`.

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
