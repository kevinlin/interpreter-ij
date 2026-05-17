# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline ~70s. Need ≥10× cumulative.

**Spec:** `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md` (revised 2026-05-18 with status update + new Phase 2.5)
**Phased plan:** `docs/superpowers/plans/2026-05-16-self-hosted-perf-10x.md` (revised 2026-05-18 with Phase 2.5 task block)
**Research / current-state map:** `docs/research/2026-05-18-interpreter-perf-research.md` (authoritative line-by-line audit of `src/interpreter.s` at HEAD `c42261c`)

---

## Current State (verified 2026-05-17, against bench.log + git HEAD)

| Label | Real time | Speedup vs phase0 | Status |
|---|---|---|---|
| phase0-baseline | 1m11.153s | 1.00× | ✅ captured |
| phase0-baseline-eval | 1m16.438s | 0.93× | ✅ captured (sample.s line) |
| `run` (unlabeled, 02:13Z) | 0m49.274s | 1.43× | non-reproducible — see P1 forensics below |
| phase2-typed-ast (03:46Z) | 1m25.086s | 0.83× | Phase 2 cutover |
| phase2-runtime (08:31Z) | 1m25.193s | 0.83× | Phase 2 runtime tweak |
| phase2-current (14:44Z) | 1m29.188s | 0.80× | HEAD pre-cleanup floor |
| p1-dead-code-cleanup (15:32Z) | 1m21.306s | 0.88× (1.10× vs phase2-current) | ✅ dead D2-prep walks removed |
| **p2-no-refresh (16:32Z)** | **1m20.478s** | **0.88× (1.01× vs p1)** | ✅ refreshToGoPointers excised; stage2 emits valid main() |

**Headline:** committed HEAD binary passes verify.sh 5/5. Phase-2 self-host bench is 0.88× vs phase0 — still off the 10× target, but the path forward no longer requires a phase revert. The 02:13Z 49s outlier was forensically reproduced and shown to be a dual-runtime artifact (see "P1 forensics" below). The new floor is **p2-no-refresh = 1m20.478s**.

**Next-loop target = P2.5 (NEW, added 2026-05-18):** activate the resolver annotations that Phase 2 wired structurally but never reads. Research doc §3.2 confirms every `*ToGo` emitter ignores `resolvedKind`/`resolvedOrigin`/`resolvedName`/`resolvedAtRoot`/`resolvedScope`/`resolvedLocals`/`resolvedIsStatic`; six `Node` fields are dead weight; `evalIdent` is `ctx.Get(string)` chain-walk per identifier; `evalBlock` always allocates Context even for blocks with zero `let`. P2.5 ships as ≥1.3× over `p2-no-refresh` per the per-phase drop rule. Detailed spec in `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md` §"Phase 2.5"; detailed task block in `docs/superpowers/plans/2026-05-16-self-hosted-perf-10x.md` §Phase 2.5 (Tasks 2.5.1–2.5.8).

Phase 0 ✅ • Phase 1 ✅ committed • Phase 2 ✅ wired structurally; semantically incomplete (resolver annotations dead) • **Phase 2.5 ⬜ NEXT** • Phase 3 ⬜ (demoted: smaller lever than P2.5) • Phase 4 ⬜

**P2 status (current — pre-P2.5):** Phase-2 emit pipeline is reproducible at the source level (stage2≡stage3 byte-identical). Replacing the committed bridge bootstrap with a clean Phase-2 self-build is BLOCKED on a separate stage2 IJ-tree-walker bug ("scalar-VarDecl regression" — see P2 section below). **This blocker DOES NOT prevent P2.5 source work** — `compile-local.sh src/interpreter.s` builds against the existing bootstrap and the P2.5 emitter changes are exercised by the resulting binary. Only the committed-binary-replace step at the end of P2.5 is gated on the regression fix.

### P0 completed (2026-05-17 ~14:44Z)

- ✅ Goldens captured at HEAD `f84bee9` via `./scripts/verify.sh --capture` — `/tmp/ij-golden/{test,sample,mcp-interp,mcp-native}.out` exist.
- ✅ Full `./scripts/verify.sh` run: **5/5 PASS**, binaries bit-identical (check 5). HEAD is provably green; any future regression can be diff'd against these goldens.
- ✅ `scripts/bench.sh` labels fixed (lines 20+22 said `test.s` while running `sample.s`). Commented-out `bench_eval.s` block removed and replaced with a one-line note explaining why (Phase 2 codegen makes it >5min — re-enable only after primary bench hits 10×).
- ✅ `src/interpreter_debug.s` deleted. It was a 21:19 snapshot of `interpreter.s` taken just before commit `d69d42a` added the `NewArrayValue` nil-guard — i.e. stale by exactly the fix that resolved the Binary B crash, plus three `dbgF` puts wrapped around the codegen `toGo` call. No remaining diagnostic value.
- ✅ HEAD re-baselined: `phase2-current = 1m29.188s` written to `bench.log`. This is the new drop-rule floor for P1 triage.

---

## Priority-ordered TODO

### P0 — Ground truth + measurement hygiene (do first, no perf change)

All P0 items completed 2026-05-17 ~14:44Z. See *P0 completed* note above for evidence. Floor at the time = `phase2-current = 1m29.188s`. Floor now (after p1-cleanup + p2-no-refresh) = `p2-no-refresh = 1m20.478s`. **Next loop starts at P2.5** (P0/P1 resolved; P2 carried as a non-blocking-for-P2.5 backlog item).

### P1 — ✅ RESOLVED: Phase 2 regression triage

**Verdict: drop-rule does not fire.** Triage forensics below; the "Phase 2 regression vs 49s baseline" narrative was based on a non-reproducible data point. Real Phase 1 → Phase 2 perf delta is < 5%. Cleanup of dead D2-prep work alone recovers 1.10× over phase2-current. **Next-loop direction: P2.5 (activate dead resolver annotations)** — research doc §3.2 confirms this is the highest-leverage available change at HEAD.

**P1 forensics (worktree benches, 2026-05-17 ~23:00Z):**

| Worktree | Source @ | Binary @ | Real time | Notes |
|---|---|---|---|---|
| W-a | fb2b299 source | fb2b299 committed binary (3.6 MB, built from c5da0ac) | 51.97s | "02:13Z 49s" reproduced |
| W-b | fb2b299 source | fresh self-build of fb2b299 (4.5 MB) | 1m33s | self-build of post-cleanup source |
| W-c | c5da0ac source | c5da0ac committed binary (3.6 MB) | 1m02s | pre-cleanup baseline |
| W-d | ac2e6f3 source | fresh self-build of ac2e6f3 (4.5 MB) | 1m27s | first post-cleanup self-build, fixed-point ✅ |
| HEAD | 38431c9 source | 38431c9 committed binary (4.5 MB) | 1m29s | current production |

**Smoking gun:** the only sub-60s data point (W-a / 02:13Z 49s) uses a binary built from `c5da0ac` source — a transitional dual-runtime commit that registers BOTH the old `Value`-interface and new `Value2` tagged-union library functions, plus emits D1 (`ctx.Get` → direct Go-var inlining), D2 (`ij_<name>_impl` fixed-arity), D3 (raw-bool helpers) fast paths. That source **cannot self-build** (`compile-local.sh` errors on `Value` vs `Value2` type incompatibility — verified). The 49s is therefore an irreproducible artifact, not a perf baseline.

The Phase 1 cleanup at `fb2b299` (delete old interface + dual-runtime, rename `Value2→Value`) is the actual regression entry point: it eliminated D1/D2/D3 emit paths along with the dead code. The subsequent Phase 2 wiring (`768e308..d69d42a`) didn't measurably change the floor (1m27s @ ac2e6f3 → 1m29s @ HEAD). Reverting Phase 2 would not recover speed.

**D1/D2/D3 audit (against HEAD `interpreter.s`):**

- **D1 (static identifier resolution → direct Go var).** GONE. `identifierToGo` (line 1942) emits `&Node{kind: nkIdent, name: "<s>"}` unconditionally; the `resolvedKind`/`resolvedOrigin`/`resolvedName` annotations the resolver writes are never consulted at emit. Every `nkIdent` eval = `ctx.Get(string)` map lookup. Phase 4 owns reintroducing this via `Node.resolvedSlot`.
- **D2 (static def → fixed-arity `ij_<name>_impl` direct call).** GONE. `emitQueuedImpls()` and `goLibSuffix()` were documented no-ops; `transpilerImplQueue` was never appended; `transpilerStaticImpls` was populated but had ZERO readers in the entire codebase. **Cleaned up this loop** (see P1 increment below); call sites all dispatch via `Value{tag: tFunc}` → `FunctionCommand.Execute`.
- **D3 (condition slot → raw-`bool` helper, no `BoolValue` heap alloc).** GONE. `conditionToGoBool` routes if/while conditions back to `condNode["toGo"]` (Node-tree emit). `EqualsBool`/`NotEqualsBool`/`LessThanBool`/`LessThanEqualBool`/`BiggerThanBool`/`BiggerThanEqualBool` were emitted in `goLibPrefix` but had ZERO callers in emitted Go. **Cleaned up this loop**; `fix_app_go.py` already re-injects them via its `if "func EqualsBool" not in content[:main()]` guard, so emitted Go is byte-identical post-cleanup.

**P1 increment shipped this loop:**

- Removed `transpilerImplQueue`, `transpilerStaticImpls` (declarations + the 3-loop populate block in `programToGo`, lines 4288–4346 pre-edit).
- Removed `emitQueuedImpls` def + its call from `transpileGo` block.
- Removed `goLibSuffix` def + its call (no-op).
- Removed 6 unused bool helpers from `goLibPrefix` (re-injected by `fix_app_go.py` so codegen output unchanged).
- 121 net LOC deleted from `src/interpreter.s`. `verify.sh` 5/5 ✅, `test.s` ✅, bench **1m21.3s (1.10× over phase2-current)**.

**Honest follow-up risks (carried forward, NOT blocking):**

- ~~Fresh self-build of HEAD is functionally broken — stage2 lacks `func main()`.~~ **RESOLVED this loop.** Stage2 emit now produces a complete program; root cause was `refreshToGoPointers`, not `evalAssign`. `Context.Update`/`Exists` already walk parents. See P2 increment below.
- Stage2 binary's *runtime* still has a separate bug — IJ tree-walker aborts after a `let X = scalar` statement. Means we cannot yet replace the committed bridge bootstrap with a self-built one. Tracked as the new P2 blocker.
- The "index out of range [0] with length 0" in `registerLibraryFunctions.func12` (per stack trace, the `assert` lib fn) — may share root cause with the scalar-VarDecl regression. P2 retest item.

### P2 — Make verify.sh check 5 honest (true fixed-point, not just determinism)

Phase 2 IS kept. P2 is now the bridge to a clean self-build so the committed binary can be regenerated reproducibly.

**P2 increment shipped this loop (root cause = refreshToGoPointers, NOT evalAssign):**

- ✅ **Excised `refreshToGoPointers`.** Phase 2 emit captures top-level `*toGo*` defs into AST nodes at parse time; those captures already point at the live global Value, so the Phase-1 helper that re-walks the AST to "rebind" them is dead. Worse, when stage2 runs `interpreter.s` on itself, the helper's tree walk aborts mid-stream (vInvalid result somewhere in the per-node `node["toGo"] = X` assignments) — and because evalBlock bails on `tInvalid`, control never reaches `programToGoPhase2`, leaving stage2 emit truncated at `evalProgram` with no `func main()`. Removing the call (and the 90 LOC `def`) makes stage1→stage2 emit a complete, runnable program. (Forensics: instrumented `def toGo`/`def refreshToGoPointers` with sentinel `puts("// DBG_*")`, observed iteration `// DBG_REFRESH_ITER sp=15` was the last marker before the silent abort; vNull/vInvalid mismatch in MapValue.Get on a missing field is the most likely trigger but wasn't worth deep-diving once the helper proved dead.) `verify.sh` 5/5 ✅, bench `p2-no-refresh = 1m20.478s` (1.01× vs p1, within noise — perf win wasn't the goal here, correctness was).
- ✅ **Demonstrated true fixed-point at the SOURCE level.** With the helper removed: stage1 (built from `ac2e6f3` bootstrap) → stage2 → stage3 produces stage2 ≡ stage3 byte-identical (verified via `cmp /tmp/p2/s2 /tmp/p2/s3`). The Phase-2 emit pipeline is reproducible; the only reason `verify.sh` check 5 still uses determinism (same bootstrap → same output twice) instead of stage1→stage2→diff is that the committed bootstrap can't yet be replaced — see next item.

**P2 carried forward (BLOCKER for replacing the committed bridge):**

- [ ] **Fix stage2's IJ tree-walker scalar-VarDecl regression.** A clean Phase-2 self-build (`/tmp/p2/s2`) emits correctly when used as a transpiler (`stage2_bin src/sample.s //<GO2>` produces a working app.go), but its **runtime** breaks the IJ tree-walker path used by `scripts/interpreter.sh src/test.s`. Repro: `printf '//multiline\nputs(1);\nlet x=10;\nputs(2);\n//<EOF>\n' | s2` → prints `1` then aborts (no `2`, EC=0). `let m={}; puts(m);` works (prints `{}`); `let m=[]; puts(m);` aborts; `let s="hi"; puts(s);` aborts; `def f(){puts("called");} f(); puts("after");` prints `called` then aborts. Pattern: any top-level statement *whose tree-walker `evaluate` returns a non-map IJ value* ends program execution. Hypothesis: Phase-2's `evalBlock` aborts on `v.tag == tInvalid`, and one of the call paths inside `evaluateVariableDeclaration → ctxDefine` returns vInvalid for scalar/array values but not for maps. Most likely culprit: how `return self["value"]` in `numberLiteralEvaluate` flows through `evalCall`/`evalReturn` semantics when the wrapped Go func's bool is dropped. Until this is fixed, replacing the committed bootstrap with s2 makes `verify.sh` checks 1/2/3 fail (confirmed: check 1 prints empty stdout vs golden's "All tests completed successfully!"). **DO NOT replace the committed binary** until this lands.
- [ ] **Repro the `registerLibraryFunctions.func12` panic.** Listed in the previous loop; not retriggered in this loop's test surface. May or may not be the same root cause as the scalar-VarDecl regression above. Re-test once the regression fix lands.
- [ ] **Patch `fix_app_go.py` to harden all lib-fn `params.Get(Value{tag: tInt, i: N})` call sites** with bounds checks. Mechanical sed; ~30 lib fns. Defensive depth even if not strictly needed.
- [ ] **Replace committed `interpreter_mac_arm64` + tighten `verify.sh` check 5.** Only after the regression above lands. The replacement is what makes `verify.sh` check 5 a TRUE fixed-point check (stage1 install → stage2 build → diff) instead of mere determinism.

### P2.5 — Activate resolver annotations (NEW, added 2026-05-18; expected 2–3× over p2-no-refresh)

Per design §"Phase 2.5 — Activate Resolver Annotations" (revised 2026-05-18). Research evidence: `docs/superpowers/research/2026-05-18-interpreter-perf-research.md` §3.2 (all resolver annotations dead) + §3.1 (six dead Node fields) + §2.2 (`Context.Get` chain-walk cost) + §2.4 (`evalBlock` always allocs) + §3.10 (wasted `FunctionCommand.Execute` ctx alloc).

**Why this is next, not P3:** the resolver pass already runs and writes per-node annotations (`resolvedKind`, `resolvedOrigin`, `resolvedName`, `resolvedAtRoot`, `resolvedLocals`, `resolvedIsStatic`). Every cost is paid; zero benefit harvested. Wiring the projection + read sites is the highest-leverage available change because `evalIdent` is on every recursive eval frame. P3 (string interning) is a smaller lever — it saves a string-header alloc per literal but does NOT reduce `ctx.Get` chain walks (the dominant cost).

**Pre-flight for P2.5:** the P2 stage2-runtime regression does NOT block P2.5 source work. P2.5 edits `interpreter.s` only; `compile-local.sh src/interpreter.s` builds against the existing committed bootstrap and exercises every P2.5 emitter change. The committed-binary replace step (Task 2.5.8 Step 2) IS gated on the P2 regression fix, but the bench number from Step 3 is honest before that.

- [ ] **Task 2.5.1: Scaffold `rk*` constants + `hasLocals` field + `Context.GetLocal`/`UpdateLocal` + `var rootCtx`.** Add to runtime emit (`goLibPrefix`). No behavior change. Build + test green. Ref: design §Phase 2.5 "New shape (emitted Go)".
- [ ] **Task 2.5.2: Add `resolverKindCode(kind, origin)` IJ-side helper** that maps the resolver's string-tagged annotation to the numeric `rk*` constant.
- [ ] **Task 2.5.3: Project `resolvedKind`/`resolvedOrigin` from `identifierToGo`** (`src/interpreter.s:1922`). Annotations now ride on every emitted `&Node{kind: nkIdent, ...}`; `evalIdent` still uses chain-walk fallback at this commit. Verify check 5 determinism.
- [ ] **Task 2.5.4: Switch `evalIdent` to dispatch on `resolvedKind`** (`src/interpreter.s:5221-5223`). `rkParam`/`rkLocal` → `ctx.GetLocal`; `rkLib` → `rootCtx.GetLocal`; `rkUpvalue` → single-hop walk; fallback → `ctx.Get`. Capture `rootCtx` in `programToGoPhase2`. **First measurable win — bench should show ≥1.3× over p2-no-refresh after this task alone.**
- [ ] **Task 2.5.5: Project + dispatch `evalAssign` / `evalVarDecl` on `resolvedKind`.** `assignmentStatementToGo` (`735`) + `variableDeclarationToGo` (`4336`) emit `resolvedKind`; runtime `evalAssign` (`5258`) + `evalVarDecl` (`5286`) short-circuit on it. Eliminates the `Exists`+`Update` two-walks-per-write cost.
- [ ] **Task 2.5.6: Gate `evalBlock` Context allocation on `hasLocals`.** `blockStatementToGo` (`1100`) projects `hasLocals: true` only when `resolvedLocals` non-empty; `evalBlock` (`5275`) skips `NewContext(ctx)` when `hasLocals == false`. Eliminates per-iteration Context alloc inside `while` loops with no `let` (the `sample.s` shape).
- [ ] **Task 2.5.7: Drop the wasted `FunctionCommand.Execute` Context alloc.** Pass `nil` instead of `NewContext(c.definitionCtx)` — closure body discards `callerCtx` anyway (research §3.10). One fewer `*Context` per function call.
- [ ] **Task 2.5.8: Re-baseline check 5 (source-level fixed-point), bench `phase2_5-resolver-wired`, drop-rule check.** Drop-rule: ≥1.3× over `p2-no-refresh = 1m20.478s`. Cumulative: if ≥10× over `phase0-baseline = 1m11.153s`, **stop and ship — skip P3 + P4**. Replace committed binary IF the P2 stage2-regression item is closed.

**Out of P2.5 scope (deferred):**
- D2 reborn: emitting `ij_<name>_impl(ctx, a, b)` fixed-arity Go functions + direct call-site dispatch. (Lift `resolvedIsStatic` into emit to enable this in a follow-up phase.)
- D3 reborn: routing if/while conditions through raw-`bool` helpers (`EqualsBool`, `LessThanBool`). The `fix_app_go.py`-injected helpers already exist and are dead — wiring them is a separate small task.
- Slot-indexed contexts (Phase 4 territory).
- String interning (Phase 3 territory).

### P3 — Phase 3: String interning + singletons (expected 1.3–1.8×)

Per design §Phase 3. **Only start once P2.5 is settled and cumulative speedup is < 10×.**

- [ ] **Singletons in `goLibPrefix`.** Emit `vNull`, `vTrue`, `vFalse`, `vEmpty`, `smallInt[256]` ([-128..127]), `strPool []Value` package-level vars + `init()` populating `smallInt`. Helper `vIntFast(i int64) Value` (cache hit for small, else fresh `Value`).
- [ ] **Route eval literal dispatch through singletons.** Update `eval()` cases in goLibPrefix:
  - `nkNullLit → return vNull`
  - `nkBoolLit → if n.bVal { return vTrue }; return vFalse`
  - `nkIntLit → return vIntFast(n.iVal)`
- [ ] **String pool in IJ-side codegen.** Add `strPoolList = []`, `strPoolIndex = {}`, `strPoolIntern(s)` helpers in `interpreter.s` near the codegen entrypoint. Pool order = first-appearance during the deterministic `toGo` walk (required for verify.sh check 5 bit-identical fixed-point).
- [ ] **`stringLiteralToGo` rewrite.** Emit `&Node{kind: nkStringLit, sIdx: <N>}` instead of `&Node{kind: nkStringLit, name: "..."}`. Update `eval` case `nkStringLit → return strPool[n.sIdx]`.
- [ ] **Identifier names → pool.** `nkIdent.name` is also a string-header allocation each emit. Optional but free: route `n.name` through the same pool (store index, lookup via `strPool[idx].s` at eval time). Defer if not on hot path.
- [ ] **Emit `initStrPool()`** as part of `goLibPrefix` or `programToGoPhase2` — populates `strPool` from `strPoolList` in deterministic order; called from `init()`.
- [ ] **Determinism gate.** After P3 code lands, `compile-local.sh interpreter.s` twice; `diff` must be byte-identical. If not, the pool ordering is non-deterministic (likely an `iteritems`-style map walk somewhere) — fix before bench.
- [ ] **Bench: `./scripts/bench.sh phase3-intern`.** Drop-rule ≥1.2× over phase2 floor.

### P4 — Phase 4 (stretch): Slot-indexed contexts (expected 1.5–2×)

Only if cumulative speedup after P3 < 10×. Per design §Phase 4.

- [ ] **Resolver slot assignment.** Add `nextSlot` to `makeResolverScope`; `resolverScopeDeclare` writes `scope["slots"][name] = scope["nextSlot"]++`. `resolverScopeLookup` returns slot + depth.
- [ ] **Project slot + depth into Node.** `identifierToGo`, `variableDeclarationToGo`, `assignmentStatementToGo`, `functionDeclarationToGo` emit `resolvedSlot: N, resolvedKind: K` (fields already exist on `Node` struct in goLibPrefix; currently zero-valued).
- [ ] **Add `slotCount int32` to Node struct emit** for function decls — sized from resolver count.
- [ ] **Context.slots in goLibPrefix.** `type Context struct { parent *Context; variables map[string]Value; slots []Value; ... }`. Add `GetSlot(depth, slot)` + `SetSlot(depth, slot, v)` methods.
- [ ] **eval rewrites.** `evalIdent` switches on `n.resolvedKind`: 1/2 (param/local) → `ctx.slots[n.resolvedSlot]`; 3 (upvalue) → walk parent; 0 (global) → map fallback. `evalAssign`, `evalVarDecl`, `evalFuncDecl` similarly.
- [ ] **Top-level globals stay map-based** for override pattern + MCP. Only function/block scopes go slot-indexed.
- [ ] **Bench: `./scripts/bench.sh phase4-slots`.** Drop-rule ≥1.3× over phase3.

### P5 — Cleanup once 10× hit

- [ ] **README perf section update.** Append phase1–phaseN rows to the speedup table; one-paragraph description per phase; D1/D2/D3 lessons captured if D1/D2 ended up reborn under Phase 2.5 (or a follow-up).
- [ ] **Remove `cleanup_phase1.py`** if no longer referenced (verify with `rg cleanup_phase1`).
- [ ] **Remove `scripts/fix_app_go.py`** once the committed binary is fully Phase-2-clean and the legacy hybrid bridge isn't needed for any pipeline step (currently it's the load-bearing post-processor for `compile-local.sh`; removing prematurely breaks the build). Note: per research §3.5 the post-processor's `EqualsBool`-family helper injection is dead code that piggybacks on the rename bridge — both go away together.
- [ ] **Garbage-collect tree-walker `evaluate` path** in `interpreter.s`. Phase 2 codegen produces `&Node{...}` literals consumed by emitted `eval()` in Go — the IJ-side `node["evaluate"]` callable entries are still used by `scripts/interpreter.sh` (tree-walker) and by AST-emit JSON. Audit which `evaluate*` functions are reachable from `scripts/interpreter.sh src/sample.s` and `scripts/ast.sh`; everything else is dead. Don't strip without dead-code audit — `scripts/interpreter.sh` and the resolver pass both still depend on the IJ-side AST shape.
- [ ] **Drop the dead Node fields** that P2.5 / future phases do not adopt. After P2.5 ships, audit which of `pos uint32` / `sIdx uint32` / `resolvedSlot int32` / `isStatic bool` are still unused. `resolvedKind` is now live (P2.5); `resolvedName` activates only with D2 reborn; `resolvedSlot` activates only with P4. Anything still unused after P3+P4 land (or after P2.5 hits 10×) is removable for ~10 bytes/Node savings (research §3.1).
- [ ] **Drop the dead `ijCount*` counters** (`src/interpreter.s:4381-4390`). Declared + dumped on exit but never incremented since `b040672`. Either re-instrument the surviving allocation hot paths (`evalCall`, `evalBlock` allocs, `Context.Get`/`Update` chain walks) or delete the declarations + the `IJ_COUNTERS` env-var dump emit in `programToGoPhase2`.
- [ ] **Drop the dead `useNodeTree` switch** (`src/interpreter.s:5388`). Phase 2's `programToGoPhase2` is the only path; the `let useNodeTree = true` gate guards a removed Phase-1 emit branch. Trivial cleanup.
- [ ] **Drop dead `opCodeFor("!")` branch** (`src/interpreter.s:835-851`). `"!"` is prefix-only; `infixExpressionToGo` never asks for it. Trivial.

---

## Research-doc backlog (audit findings, 2026-05-18)

The research doc `docs/superpowers/research/2026-05-18-interpreter-perf-research.md` enumerates dead-code / unused-infrastructure sites in `src/interpreter.s` at HEAD `c42261c`. Most of these are addressed by P2.5 / P3 / P4 / P5 above; this section is the running checklist of what the research found vs what each priority covers.

| Research § | Finding | Addressed by |
|---|---|---|
| §2.1 | `Value` struct is 88 bytes, passed by value everywhere | structural, not a cleanup target — measure under P2.5 first |
| §2.2 | `Context.Get` chain-walks per `evalIdent` | **P2.5 Task 2.5.4** |
| §2.3 | ~5 heap allocs per `evalCall` | **P2.5 Tasks 2.5.6 + 2.5.7** (block ctx + caller-ctx) |
| §2.4 | `evalBlock` always allocs Context | **P2.5 Task 2.5.6** |
| §2.5 | `MapValue.String()` alloc per non-string key | not on hot path for sample.s — defer |
| §2.6 | `(Value, bool)` return-sentinel branch per node visit | structural; rolling back to `tReturn` is not on the table per research §4.12 |
| §2.7 | `fix_app_go.py`-injected `EqualsBool`-family helpers are dead | **P5 (`fix_app_go.py` removal)** |
| §2.8 | String literals emit per occurrence | **P3 (string interning)** |
| §2.9 | `evalIdent` always misses on Context for library funcs | **P2.5 Task 2.5.4** (`rkLib` direct root lookup) |
| §3.1 | Six dead `Node` fields | **P5 cleanup** (after P2.5/P3/P4 settle which fields are live) |
| §3.2 | All resolver annotations dead | **P2.5** (Tasks 2.5.3–2.5.6) |
| §3.3 | `analyzeIsStatic` walks bodies for nothing | activated by **P2.5 Task 2.5.7** (NewStaticFunctionCommand path) + future D2-reborn task |
| §3.4 | `useNodeTree` switch permanently true | **P5 cleanup** |
| §3.5 | Bool helpers + AsValue wrappers wait for caller | **P5 (`fix_app_go.py` removal)** |
| §3.6 | `ijCount*` counters declared but never incremented | **P5 cleanup** |
| §3.7 | `opCodeFor("!")` has no caller | **P5 cleanup** |
| §3.8 | CPU profile hook (`IJ_CPUPROFILE`) | live; use under P2.5 / P3 / P4 measurement |
| §3.9 | Phase 3 singleton scaffolding present but not emitted | **P3** |
| §3.10 | `FunctionCommand.Execute` wastes a Context alloc | **P2.5 Task 2.5.7** |
| §4.5 | Committed binary is one-way bridge; check 5 = determinism | **P2** (carried; blocks committed-binary replace) |
| §4.7 | `registerLibraryFunctions.func12` (`assert`) length-0 panic | **P2** (carried) |
| §4.11 | `bench_eval.s` dropped (>5min under Phase 2 codegen) | re-enable after primary bench hits 10× |

---

## Open Questions / Risks

- **`verify.sh` check 5 = determinism, not fixed-point.** The script runs `compile-local.sh src/interpreter.s _roundtrip_{a,b}` twice with the SAME committed bootstrap binary, then diffs `_roundtrip_a` vs `_roundtrip_b`. This catches non-deterministic transpile output (e.g. map iteration) but NOT the "stage1 ≠ stage2 because stage1's compiled-in eval is buggy" class of regression. P2 promotes this to true fixed-point.
- **The committed `interpreter_mac_arm64` is a bridge.** It was built from `ac2e6f3`-era source that still emitted D1/D2/D3 fast paths, then the source was rewritten in `f7783ed` to remove them. The committed binary therefore has fast-path runtime semantics that NO current `src/interpreter.s` can reproduce. Until P2 ships, treat the committed binary as a one-way artifact — do not lose it (`git restore interpreter_mac_arm64` after any accidental recompile). **Update (this loop):** stage2 emit is now reproducible (s2≡s3) but stage2 RUNTIME still regresses on IJ tree-walker scalar-VarDecl flows; bridge stays in place.
- **D4 lesson (README):** "looks faster, is slower." Every phase commit must be measured. Counter-lesson from this loop: also "looks slower, is irreproducible" — the 49s 02:13Z bench was real but irreproducible because it depended on a transitional dual-runtime that no longer exists in source form.
- **MCP regression risk.** verify.sh check 4 PASSES at HEAD. The override pattern (`let oldX = X; def X(...)`) is the MCP-relevant invariant. Any codegen edit touching `functionDeclarationToGo` must re-run verify.sh in full.
- **P2.5 resolver-classification risk.** The resolver may mis-classify some identifiers (e.g. binding introduced by `let` inside an `if` branch where the if-block scope and the parent scope disagree). Each P2.5 task that switches an emitter on `resolvedKind` keeps an explicit fallback path (`return ctx.Get(n.name)` / `if ctx.Exists(...) { ... }`) for unannotated nodes. If a `vInvalid("variable not found: ...")` regression surfaces, the immediate fix is to leave that emit site annotation-free (`resolvedKind == 0` ⇒ rkGlobal fallback path) until the resolver's mis-classification is found and fixed. Do NOT push P2.5 to land while functional regressions are present — fall back to fallback.
- **P2.5 `hasLocals` semantics.** The Phase-2 `evalBlock` allocs unconditionally and IJ semantics may rely on the per-block-iteration ctx for `var x = ...; ... { var x = ...; }` shadowing inside `if`/`while` bodies. The resolver's `resolvedLocals` should already classify a shadowing inner `let` as introducing a local, but the `hasLocals` projection must respect that. If `test.s` regressions surface, audit which test relies on per-iteration scoping; the conservative fix is `hasLocals: true` for any block that contains an `IfStatement`/`WhileStatement` even when its top-level `resolvedLocals` is empty.

## Build & verification reminders

- Use `./src/compile-local.sh` (Docker-less). `compile-mac.sh` / `build.sh` silently swallow Docker failures and mask regressions.
- Two consecutive `compile-local.sh src/interpreter.s` must produce byte-identical binaries (verify.sh check 5).
- Drop-rule on every phase boundary: `<1.3×` over predecessor ⇒ revert.
- Scripts moved root → `scripts/` per AGENTS.md: `scripts/bench.sh`, `scripts/verify.sh`, etc.
