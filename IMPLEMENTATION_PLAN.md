# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline ~70s. Need ≥10× cumulative.

> **This file is the running-state doc / single source of truth for status, blockers, and the next-run roadmap.** The plan and spec under `docs/superpowers/` are the design recipe (architecture + recipes for future phases). When a phase ships, status is updated here, not there.

**Spec (design recipe):** `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md` (revised 2026-05-18 with status update + new Phase 2.5)
**Phased plan (recipe for future phases):** `docs/superpowers/plans/2026-05-16-self-hosted-perf-10x.md` — shipped phases (0/1/2/2.5/2.6) are stubbed to "see IMPLEMENTATION_PLAN.md"; Phase 3/4/Cleanup still carry full step-by-step.
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
| p2-no-refresh (16:32Z) | 1m20.478s | 0.88× (1.01× vs p1) | ✅ refreshToGoPointers excised; stage2 emits valid main() |
| p2_5-final (18:40Z) | 1m17.982s | 0.91× (1.03× vs p2-no-refresh) | ✅ P2.5 wired (gain blocked behind committed-binary replace) |
| p2-stage2-regression-fix (20:06Z) | 1m17.810s | 0.91× (1.00× vs p2_5-final) | ✅ stage2 IJ tree-walker compat fixed; bridge stays |
| d2-reborn-source-only (2026-05-18 02:11Z) | 1m33.841s | 0.76× (0.83× vs p2-stage2-regression-fix; within noise band on loaded laptop) | ✅ D2-reborn IJ source landed; committed bridge stays (s3 regresses 5×) |
| p2.6-diagnosis + alloc-reduction (2026-05-18) | n/a (bench runs committed bridge; source-only changes invisible until binary replace) | n/a | ✅ stage2 perf regression root-caused (see P2.6 forensics); pprof defer-order bug fixed; evalCall + evalFuncDecl alloc-reduction patches landed in source |
| **p2.6-d1r-run-N (2026-05-18 this loop)** | **n/a (source-only)** | **n/a** | ✅ D1-reborn MVP scaffold landed: 7 `*ToGoDirect` emitters + dispatcher + allowlist + impl-emit branch in `programToGoPhase2`; 1 def (`nullLiteralEvaluate`) flipped; verify.sh 5/5 ✅ |

**Headline:** committed HEAD binary passes verify.sh 5/5. Phase-2 self-host bench is 0.91× vs phase0 — still off the 10× target. D1-reborn MVP scaffolding shipped this loop (source-only; one leaf def flipped to direct emit as proof of concept). The new floor is **p2-stage2-regression-fix = 1m17.810s**.

**🎯 Next-loop start here:** `P2.6 → D1-reborn → Run N+1` (expression-level direct emitters) below. Every other P2.5/P2.6 source-level win is invisible to `bench.sh` until the committed bridge is replaced, and the bridge can't be replaced until D1-reborn closes the 5× stage2 perf regression (multi-run roadmap: N → N+3). P3/P4/P5 stay queued behind that gate.

**D2-reborn shipped (this loop, source-only):** P2.6's "D2 fast-path emit" is wired in `src/interpreter.s`. Pre-pass `collectStaticDefs` runs from `programToGoPhase2` and promotes 205 top-level FunctionDeclaration nodes (resolvedAtRoot && single binding); each promoted def gets a sibling `ij_<name>_impl(ctx, args []Value) Value` Go fn emitted at package scope plus a `var ij_<name>_body *Node` ref initialised once in main(). `functionDeclarationToGo` emits `body: ij_<name>_body` for promoted defs (saves doubling the emit; nkFuncDecl still runs at programNode-eval time so the Value{tag:tFunc} binding is registered for indirect callers). `CallExpression_toGo` emits `nkStaticCall` (new AST kind) with `staticImpl` func-pointer field baked into the Node literal whenever the callee is `nkIdent` with `resolvedKind="global", resolvedOrigin="def"` and the name is in `staticDefByName`. Runtime: new `evalStaticCall` reads args, jumps directly into `n.staticImpl(ctx, args)` — bypasses evalIdent + ctx.Get + FunctionCommand.Execute + ArrayValue alloc. 89 nkStaticCall sites in the new emit (rest stay nkCall because callee is `node["fn"](node, ctx)`-style map-dispatched or library names).

**Predicate scoped narrower than research§3.3 suggested:** dropped the `resolvedIsStatic` check. D1's predicate (no global writes, no dynamic lookups) was too conservative for D2; the D2 path goes through `eval(body, local)` so global writes via ctx.Update walk to rootCtx and resolve correctly, and dynamic lookups via ctx.Get work unchanged. Promoting non-static defs (parser helpers like `nextToken` that mutate top-level `currentToken`/`peekToken`/`currentPosition`) is observationally identical to the closure path while skipping FunctionCommand.Execute indirection — confirmed by `verify.sh 5/5` and `test.sh ✅` on the new emit.

**Stage1 (built by committed bridge) is at PARITY; stage2 (true fixed-point) REGRESSES — committed-binary-replace STILL blocked.** Measurements this loop:

| Bridge | Emit produced | Binary size | Selfhost sample.s | Note |
|---|---|---|---|---|
| committed (pre-D2-reborn) | OLD-style: 188 ij_*_impl + 0 nkStaticCall | 4.6 MB | 1m17–1m33s (noise on loaded laptop) | bench gate ✅ vs phase0 baseline |
| d2r_s1 (stage1 = committed-bridge built from new src) | NEW-style: 205 ij_*_impl + 89 nkStaticCall | 4.6 MB | 1m20–1m26s | bench gate ✅ — D2-reborn dispatch works |
| d2r_s2 (stage2 = d2r_s1 built itself = true fixed-point) | NEW-style: 205 + 89 (same emit, byte-identical fixed-point) | 4.0 MB | **7m25s** | **bench gate ❌ — 5× regression** |

s2 and s3 emit byte-identical app.go (cmp confirmed) and `go build -trimpath -buildid= -w -s` is deterministic — yet the resulting binaries differ in both size (4.6 MB vs 4.0 MB) and runtime perf (1m26s vs 7m25s). Stage1's compiled-in programNode comes from the committed bridge's OLD-style emit (smaller, inline bodies, 0 nkStaticCall sites in programNode). Stage2's compiled-in programNode comes from the NEW-style emit (bigger, body-ref'd via globals, 89 nkStaticCall sites in programNode). At runtime both rely on the NEW source's runtime closures to override ctx and dispatch via tree-walk for map-indexed callees — so the structural programNode shape is the only meaningful axis of difference, and it points at iCache pressure / Go inliner divergence between the two literal initializer forms. **Investigating this regression is the gating task for committed-binary replacement** — see P2.6 carry-forward.

Phase 0 ✅ • Phase 1 ✅ committed • Phase 2 ✅ wired structurally; semantically incomplete (resolver annotations dead until P2.5) • Phase 2.5 ✅ shipped (source only; visible gain blocked on bridge replace) • **Phase 2.6 D2-reborn ✅ source landed; bridge replace blocked behind stage2 perf-regression diagnosis** • Phase 3 ⬜ • Phase 4 ⬜

**P2 status (post D2-reborn source):** Phase-2 emit pipeline is reproducible at the source level (stage1→stage2→stage3 byte-identical, verified this loop). The IJ tree-walker on stage1 correctly handles user scripts with multi-statement bodies, scalar `let`s, scalar return values, etc. (P2 stage2-runtime regression from previous loop stays fixed via the `isReturnValue` isMap guard at `src/interpreter.s:1210`). Stage1 selfhost matches committed-bridge selfhost — D2-reborn's calling-convention optimisation works. The remaining gating constraint on committed-binary-replace is the stage1→stage2 perf regression (s1=4.6 MB fast, s2=4.0 MB slow). See P2.6 below.

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

**P2 stage2-regression — RESOLVED 2026-05-18 (this loop):**

- [x] **Fix stage2's IJ tree-walker scalar-VarDecl regression.** Root cause: NOT in `evalVarDecl` or scalar/map dispatch — the actual culprit was `def isReturnValue(result)` in `interpreter.s:1205` doing `result[returnValueIndicatorMagicValue] == true` without first type-checking `result`. Under Phase-2 emit, `scalar[key]` returns `tInvalid` from `Value.Get`. `evalInfix(opEq)` then bails on `l.tag == tInvalid` and propagates `tInvalid` up. The IJ-level `evaluateProgram` calls `isReturnValue(result)` after each statement; if a statement returned a non-map (scalar, array, function, …), `isReturnValue`'s output became `tInvalid` rather than `false`. The outer Phase-2 `evalIf`/`evalBlock`/`evalProgram` then short-circuited on tInvalid, terminating the IJ-level evaluate loop after the first non-map statement. Not visible in the OLD bridge because that binary emits `ij_*_impl` D2-style direct Go functions for all IJ defs — those bypass the Phase-2 `eval()` machinery and tInvalid never propagates through evalInfix bail.

  **Fix shipped:** `isReturnValue` now type-checks via `if (!isMap(result)) { return false; }` before the `result[magic]` lookup. Single-line semantic fix in IJ source — no Go-side eval changes required (those were tried and reverted: removing eval-bail-on-tInvalid blanket fixed the regression but introduced 15-20× perf regression on `interpreter.sh test.s` because evalInfix/evalBlock did pointless work on tInvalid sentinels in deep IJ-evaluator call stacks).

  **Verification (this loop):** stage1→stage2→stage3 byte-identical fixed-point ✅, `printf '//multiline\nputs(1);let x=10;puts(x);\n//<EOF>' | stage2` → `1\n10` ✅, `(echo //multiline; cat src/interpreter.s; echo //<EOF>; (echo //multiline; cat src/test.s; echo //<EOF>)) | stage2` → "All tests completed successfully!" ✅, selfhosted sample.s under stage2-as-bridge prints expected output ✅.

- [x] **Demonstrated true fixed-point at the BINARY level.** With the new src + stage1 install, `compile-local.sh src/interpreter.s /tmp/s2; cp /tmp/s2 interpreter_mac_arm64; compile-local.sh src/interpreter.s /tmp/s3; cmp s2 s3` → byte-identical (3.88 MB each).

**P2 carried forward (P2.6 status moved into the P2.6 task block below; the only remaining P2-level item is the bench-regression diagnosis):**

- [x] **D2-reborn source landed** (this loop). 205 promoted defs, 89 nkStaticCall sites. Stage1 at parity, stage2 at 5× regression. See P2.6 for details.
- [ ] **Diagnose stage2 perf regression.** Gating task for committed-binary replace. See P2.6 last item.

### P2.5 — Activate resolver annotations (NEW, added 2026-05-18; expected 2–3× over p2-no-refresh)

Per design §"Phase 2.5 — Activate Resolver Annotations" (revised 2026-05-18). Research evidence: `docs/superpowers/research/2026-05-18-interpreter-perf-research.md` §3.2 (all resolver annotations dead) + §3.1 (six dead Node fields) + §2.2 (`Context.Get` chain-walk cost) + §2.4 (`evalBlock` always allocs) + §3.10 (wasted `FunctionCommand.Execute` ctx alloc).

**Why this is next, not P3:** the resolver pass already runs and writes per-node annotations (`resolvedKind`, `resolvedOrigin`, `resolvedName`, `resolvedAtRoot`, `resolvedLocals`, `resolvedIsStatic`). Every cost is paid; zero benefit harvested. Wiring the projection + read sites is the highest-leverage available change because `evalIdent` is on every recursive eval frame. P3 (string interning) is a smaller lever — it saves a string-header alloc per literal but does NOT reduce `ctx.Get` chain walks (the dominant cost).

**Pre-flight for P2.5:** the P2 stage2-runtime regression does NOT block P2.5 source work. P2.5 edits `interpreter.s` only; `compile-local.sh src/interpreter.s` builds against the existing committed bootstrap and exercises every P2.5 emitter change. The committed-binary replace step (Task 2.5.8 Step 2) IS gated on the P2 regression fix, but the bench number from Step 3 is honest before that.

- [x] **Task 2.5.1: Scaffold `rk*` constants + `hasLocals` field + `Context.GetLocal`/`UpdateLocal` + `var rootCtx`.** Shipped 2026-05-17. No behavior change at this step.
- [x] **Task 2.5.2: Add `resolverKindCode(kind, origin)` IJ-side helper.** Shipped 2026-05-17. Maps `"global"`+`"lib"` → `rkLib`, `"local"`+`"param"` → `rkParam`, etc.
- [x] **Task 2.5.3: Project `resolvedKind`/`resolvedOrigin` from `identifierToGo`.** Shipped 2026-05-17.
- [x] **Task 2.5.4: Switch `evalIdent` to dispatch on `resolvedKind`.** Shipped 2026-05-17 (commit `26f8761`). Capture `rootCtx` in `programToGoPhase2`. Bench `phase2_5-task-2.5.4-peek = 1m19.591s` — within noise vs `p2-no-refresh`. **Bench gain is blocked behind the committed-binary-replace step:** the selfhosted bench runs the *committed* binary as the IJ interpreter, and the committed binary is the pre-P2.5 bridge whose tree-walker does not honour the new annotations. Real-world fast-path payoff only fires after `verify.sh` check 5 promotes from determinism to true fixed-point (P2 carry).
- [x] **Task 2.5.5: Project + dispatch `evalAssign` / `evalVarDecl` on `resolvedKind`.** Shipped 2026-05-17.
  - `assignmentStatementToGo` (`src/interpreter.s:735`) + `identifierToGo` (`1945`) + `variableDeclarationToGo` (`4365`) now project `resolvedKind` via the new `resolverKindCode` helper.
  - Runtime `evalAssign` switches on `resolvedKind`: `rkParam`/`rkLocal` → `ctx.Update` (skip the `ctx.Exists` walk, fall through `Update`'s parent walk to find the binding), `rkLib` → `rootCtx.UpdateLocal` (direct root write), default → original `Exists`+`Update`/`Create`. `rkGlobal` is deliberately *not* in the switch because it is the Go-zero default for unannotated bootstrap-era nodes — those must keep the chain-walk semantics or the IJ "assignment-implicitly-creates" idiom breaks.
  - Runtime `evalVarDecl` unconditionally uses `ctx.UpdateLocal` (functionally identical to the previous `ctx.Create`; both write to the current ctx's variables map).
  - `evalIdent` keeps **only** the `rkLib` fast path (`rootCtx.GetLocal`); `rkParam`/`rkLocal` were attempted to GetLocal at first but reverted to `ctx.Get` because `evalBlock` still creates per-block `*Context` children, so a function-scope `let` lives one ctx level up from a nested-block ident reference — `GetLocal` would miss it. The `rkParam`/`rkLocal` GetLocal fast path lifts only after P2.5.6 collapses the per-block ctx (see Task 2.5.6).
  - `verify.sh` 5/5 ✅. `test.sh` ✅. Bench `p2_5-resolver-wired = 1m17.250s` (1.04× over `p2-no-refresh = 1m20.478s` — within noise, drop-rule technically not satisfied at this incremental step). The real lever from P2.5 only fires after the committed-binary replace lands or after P2.5.6+ ships; 2.5.5 alone is wiring + a safe `rkLib` win that the committed bridge cannot observe.
- [x] **Task 2.5.6: Gate `evalBlock` Context allocation on `hasLocals`.** Shipped 2026-05-17. `blockStatementToGo` projects `hasLocals: true` when `resolvedLocals` non-empty; `evalBlock` runtime reuses caller ctx unless block introduces bindings. Stage1 passes test.sh + verify.sh 5/5 incl. shadowing test (`{ let x = 2; ... } puts(x)` still prints outer). The `rkParam`/`rkLocal` GetLocal fast-path in `evalIdent` is STILL not lifted — collapsing block ctxs is safe at runtime but the inner-block-emits-let case still introduces a new ctx, so GetLocal would miss outer-function locals from inside an inner shadowing block. Left as a P5 follow-up once a measurement justifies it.
- [x] **Task 2.5.7: Drop the wasted `FunctionCommand.Execute` Context alloc.** Shipped 2026-05-17 (commit `5bf147a`, combined with 2.5.6). `c.executeFunc(nil, params)` — closure body in `evalFuncDecl` discards `callerCtx` anyway. Only two `Execute` callers (`Value.Execute` + `evalCall`); both already-safe.
- [x] **Task 2.5.8: Bench + drop-rule check.** Bench `p2_5-final = 1m17.982s` (1.03× vs `p2-no-refresh = 1m20.478s`). Drop-rule technically not satisfied at this incremental step. **Visible gain blocked behind committed-binary-replace step** — selfhosted bench runs the COMMITTED binary which is the pre-P2.5 bridge; its tree-walker does not honour the new annotations + does not skip block ctx alloc + still allocates caller-ctx. The new emit sites + runtime code are correct (`test.sh` + `verify.sh` 5/5 ✅ across all 2.5.* commits), they just can't be observed until P2 stage2-regression unblocks committed-binary replacement. Committed binary NOT replaced per AGENTS.md guidance — bridge stays.

**Out of P2.5 scope (deferred):**
- D2 reborn: emitting `ij_<name>_impl(ctx, a, b)` fixed-arity Go functions + direct call-site dispatch. (Lift `resolvedIsStatic` into emit to enable this in a follow-up phase.)
- D3 reborn: routing if/while conditions through raw-`bool` helpers (`EqualsBool`, `LessThanBool`). The `fix_app_go.py`-injected helpers already exist and are dead — wiring them is a separate small task.
- Slot-indexed contexts (Phase 4 territory).
- String interning (Phase 3 territory).

### P2.6 — D2-reborn (source landed 2026-05-18; committed-binary-replace STILL blocked behind stage2 perf regression)

Per the P2-stage2-regression-fix forensics, the visible P2.5 gain is doubly blocked: (a) the committed bridge can't be replaced without (b) the new emit reaching tree-walker perf parity with the bridge. (b) requires re-emitting IJ-level static functions as direct Go functions instead of routing every call through `evalCall → FunctionCommand.Execute → executeFunc → eval(body)`.

**Why this is the actual next priority:** without D2-reborn, every loop's P2.5/P3/P4 perf wins remain invisible to `bench.sh` (the committed bridge is what runs the bench). With D2-reborn shipped, replacing the committed binary becomes a straight win and the entire P2.5 fast-path lights up.

- [x] **Lift `resolvedIsStatic` into emit — done, then loosened.** Initial wiring used `resolvedIsStatic` per the spec; it promoted only 187 defs and missed parser hot-paths (`nextToken`, `parseStatement`, `initParser`) because analyzeIsStatic excludes any AssignmentStatement that writes a global. That predicate is D1's (no inlined Go vars, must preserve ctx-write-through semantics) — D2 doesn't care because the `eval(body, local)` path goes through ctx.Update which walks parents naturally. Dropped the resolvedIsStatic check; final predicate is `resolvedAtRoot && counts[name]==1` (single binding excludes the `let oldX = X; def X(...)` override idiom). 205 promoted defs, +18 vs the strict predicate. Comment in `collectStaticDefs` records the reasoning. (`src/interpreter.s:5506-5582`.)
- [x] **Direct call-site dispatch in `CallExpression_toGo`.** When the callee is `nkIdent` with `resolvedKind == "global"` and `resolvedOrigin == "def"` and the name is in `staticDefByName`, emit `&Node{kind: nkStaticCall, staticImpl: ij_<n>_impl, list: [...args...]}`. The kind+origin gate distinguishes a real top-level def from a let/param/upvalue shadowing the name (resolver's sequential lookup would return `kind="local"` or `origin="let"` for those). 89 nkStaticCall sites in the new emit (the rest are map-indexed callees like `node["fn"](node, ctx)` and library names, neither of which can take this fast path with the current predicate). (`src/interpreter.s:3056-3115`.)
- [x] **Runtime support in `goLibPrefix`.** Added `nkStaticCall` const, `staticImpl func(*Context, []Value) Value` field on `Node`, eval-switch case, and `func evalStaticCall(n, ctx)` body. evalStaticCall mirrors the closure path's invariant — propagates a returned-bool out of arg evaluation, swallows return-bool from the impl (function call boundary), bails on tInvalid args. (`src/interpreter.s:5202-5306`.)
- [x] **Body emit dedupe.** functionDeclarationToGo emits `body: ij_<n>_body` (a global Go var reference) for promoted defs, with the body literal initialised once at the top of main() via `ij_<n>_body = &Node{...}`. Avoids doubling emit size (205 promoted defs × ~1KB body = ~200 KB savings). nkFuncDecl still runs at programNode-eval time to register `ctx[<n>] = Value{tag:tFunc, cmd: closure-over-ij_<n>_body}` — required for indirect callers (`let g = foo; g(42)` and map-stored function values).
- [x] **Override-pattern compatibility verified.** The `let oldX = X; def X(...) { oldX(...) }` idiom keeps working: `counts["X"] == 1` (only the FuncDecl, not the VarDecl named "oldX") → X is promoted; calls to `oldX(...)` inside X's body have `resolvedOrigin == "let"` → no promotion → nkCall path → ctx.Get → captured library X. MCP path tested via `verify.sh` check 4 (5/5 ✅).
- [x] **Determinism gate.** Two consecutive `compile-local.sh src/interpreter.s` runs produce byte-identical binaries (verified with d2r_s2 and d2r_s4 = identical SHA on stage1; d2r_s3 and d2r_s5 = identical SHA on stage2). staticDefNames is an in-source-order list (no map-iteration ordering risk).
- [x] **Source-level true fixed-point.** Stage1 → stage2 → stage3 are byte-identical (cmp confirmed). The Phase-2 emit pipeline is reproducible at the source level *across* the bridge transition (committed-bridge-emit → d2r_s1 → d2r_s2 → d2r_s3, with d2r_s2 ≡ d2r_s3 byte-identical).
- [x] **Stage1 bench parity.** `selfhosted_interpreter.sh sample.s` under d2r_s1 (4.6 MB; 188 OLD impls compiled in but irrelevant — runtime overrides via ctx) = 1m20–1m26s vs committed bridge's 1m17–1m33s on the same loaded laptop today. D2-reborn dispatch works in practice when the bridge has the OLD emit's structural shape baked in.
- [x] **Stage2 bench REGRESSION — ROOT-CAUSED 2026-05-18 (this loop).** The previous loop's "iCache pressure / Go inliner divergence / global var pattern" hypothesis was WRONG. The actual root cause is **architectural**: the committed bridge emits a fundamentally different shape of `app.go` than the new src.

  **Diagnosis evidence (this loop, fib25 micro-bench: stage1 4.0s vs stage2 17.85s = 4.5× regression):**

  | Metric | Stage1 (committed-bridge → new-src) | Stage2 (stage1 → new-src, true fixed-point) |
  |---|---|---|
  | Wall time | 4.04s | 17.85s |
  | Total allocations | 54.1M | 112.7M |
  | Total bytes allocated | 4.8 GB | 24.7 GB |
  | GC cycles | 1605 | 5982 |
  | GC pause total | 62 ms | 223 ms |
  | Avg alloc size | 89 B | 220 B |
  | Heap live | ~0 MB (transient) | ~4 MB sustained (interpreter.s Node tree globals) |

  **The shapes diverge structurally:** stage1's `app.go` (from committed bridge) has 187 `ij_<name>_impl` Go functions where **each `_impl` body is direct Go code** transpiled statement-by-statement from the IJ source (e.g. `func ij_mangle_impl(ctx, ij_name) { return Value{...}.Add(ij_name) }`). The user program body in `main()` is emitted as a series of inline `ij_xxx.Execute(...)` calls — NO Node tree, NO `eval()` recursion. Stage2's `app.go` (from stage1, NEW emit) has 205 `ij_<name>_impl` Go functions where **each body is `result, _ := eval(ij_<name>_body, local)`** — wraps a Node-tree tree-walker. Plus a 1 MB `programNode := &Node{kind: nkProgram, list: []*Node{...}}` literal in `main()`.

  When stage2 runs interpreter.s evaluating fib25.s, EVERY IJ-level operation (lexer token, parser step, evaluator dispatch, MapValue lookup, …) goes through the Go-side `eval()` switch with allocation per node visit. When stage1 runs the same workload, those IJ-level operations are direct Go function calls with no `eval()` indirection.

  **Pprof CPU breakdown (stage2, fib25, 19.12s sample):**

  | Function | flat | cum | cum % |
  |---|---|---|---|
  | runtime.systemstack | 0.02s | 12.11s | 43.23% |
  | main.(*FunctionCommand).Execute | 0.08s | 9.59s | 34.24% |
  | main.eval | 1.64s | 9.59s | 34.24% |
  | main.evalBlock | 0.29s | 9.59s | 34.24% |
  | main.evalCall | 0.14s | 9.59s | 34.24% |
  | main.evalFuncDecl.func1 | 0.04s | 9.41s | 33.60% |
  | runtime.kevent (GC sysmon) | 4.69s | 4.69s | 16.74% |
  | runtime.gcBgMarkWorker.func2 | 0 | 4.66s | 16.64% |

  **D2-reborn was the wrong shape of fix.** It collapses `evalIdent + ctx.Get + FunctionCommand.Execute + ArrayValue alloc` for direct-by-name calls, but the hot path under selfhost+fib25 is **the closure body** in `evalFuncDecl.func1` (33.6% cum), reached via `FunctionCommand.Execute` (34.24% cum). User-level `fib(n)` and IJ-side `MapValue["evaluate"]` calls go through that closure path, NOT through nkStaticCall (because the callee is a value, not a known-at-emit-time identifier). So D2-reborn saves IJ-internal direct-by-name calls in interpreter.s but doesn't touch the dominant cost.

  **The structural fix: "D1-reborn" — emit promoted-static-def bodies as direct Go statements, NOT as `eval(body, local)` wrappers.** This brings the new src to parity with the committed bridge's emit shape. Each `*ToGo` function in interpreter.s currently emits Node literals; we'd need a parallel set of "direct-Go-statement" emitters that mirror what the OLD bridge did (e.g. `assignmentStatementToGoDirect`, `infixExpressionToGoDirect`, `callExpressionToGoDirect`, etc.). The OLD bridge's emit shape is preserved in the committed binary's compiled-in `app.go`; reading `/tmp/p2_6/app_s1.go` lines 5724-5800 shows the template (one Go function per IJ def with direct-statement body). This is multi-loop work but it is the only path to closing the regression AND replacing the committed binary.

- [x] **Pprof defer-order bug — FIXED (this loop).** `programToGoPhase2` emitted `defer pprof.StopCPUProfile()` BEFORE `defer f.Close()`. Go defers run LIFO → `f.Close()` ran first, then `pprof.StopCPUProfile()` tried to flush profile data to a closed fd → every `IJ_CPUPROFILE=...` invocation produced a 0-byte file (silently). Fix: swap the two `puts(...)` lines so `f.Close()` is deferred first and runs LAST. Verified via `(echo //multiline; cat fib25.s; echo //<EOF>) | IJ_CPUPROFILE=/tmp/cpu.out stage2_patched` → 40 KB profile parseable by `go tool pprof`. This unblocks all future profiling work. NOTE: the committed bridge has the OLD defer order baked into its own `main()`; only stage1+stage2 builds get the fix. Bench/verify pipelines aren't affected because they don't use IJ_CPUPROFILE.

- [x] **Alloc-reduction in goLibPrefix (this loop).** Two source-side patches in `evalCall` + `evalFuncDecl` emit:
  - `evalCall`: replace `args := NewArrayValue(); for ... append(args.values, v)` with `av := &ArrayValue{values: make([]Value, nargs)}; for i ... av.values[i] = v`. Drops the empty-slice + per-append slice-growth allocations to a single preallocated backing slice. (`src/interpreter.s:5494-5510`)
  - `evalFuncDecl` closure body: replace `NewContext(defCtx) + local.Create(p, v)` (which lazily allocates the `variables` map on first Create) with a single `&Context{parent: defCtx, variables: make(map[string]Value, npar)}` literal. Special-case `npar == 0` to skip the map alloc entirely (zero-param IJ defs are common — `getErrors`, `parseMapPairs`, etc.). (`src/interpreter.s:5481-5500`)
  - **Expected ~5% per-call cost reduction** on stage2 (measured via `stage2_v5` hand-patch ≈ 17.0s vs original 17.85s = 4.8% recovery on fib25). Invisible to `bench.sh` today (committed-bridge binary is what runs the bench) but lands in source for next loop's committed-binary replacement.

**🎯 D1-reborn — the critical path. Multi-loop work; scope per loop below.**

D1-reborn = emit promoted-static-def bodies as direct Go statements instead of `eval(body, local)` wrappers. Per the diagnosis above this is the structural fix that closes the 5× stage2 regression and unblocks the committed-binary replace. The OLD bridge's emit template lives in `/tmp/p2_6/app_s1.go` lines 5724-5800 (regenerate via `compile-local.sh` + save before `fix_app_go.py` runs if it's gone). Per-statement direct emitters needed (~15): `literalsToGoDirect` (int/double/string/bool/null), `identifierToGoDirect`, `infixExpressionToGoDirect`, `prefixExpressionToGoDirect`, `callExpressionToGoDirect`, `indexExpressionToGoDirect`, `assignmentStatementToGoDirect`, `variableDeclarationToGoDirect`, `ifStatementToGoDirect`, `whileStatementToGoDirect`, `blockStatementToGoDirect`, `returnStatementToGoDirect`, `indexAssignmentToGoDirect`, `arrayLiteralToGoDirect`, `mapLiteralToGoDirect`. Each emits Go in the OLD-bridge style (e.g. `var ij_x Value = ij_y.Add(ij_z)`) instead of `&Node{kind: nkVarDecl, ...}`. `programToGoPhase2` switches promoted defs to use the direct emitter for their body (instead of `body: ij_<n>_body` + `eval(ij_<n>_body, local)` indirection). Non-promoted defs (nested defs, dynamic lookups, etc.) stay on the Node-tree+eval path — graceful migration: direct-emit lights up per-def as soon as every node kind in its body has a direct emitter.

- [x] **Run N (this loop): Scaffold D1-reborn + minimum-viable-product. ✅ SHIPPED.**
  - ✅ Template captured to `docs/research/2026-05-18-d1-reborn-emit-template.md` — per-statement mapping (prologue/epilogue, all literals, identifier, var/assign, block, return, if/while, infix, prefix, call, index, array/map literal). Source: the pre-`fix_app_go.py` `app.go` produced by running the committed bridge on `src/interpreter.s` (188 OLD-style `func ij_<n>_impl(ctx, ij_<p1>, ij_<p2>)` defs at lines 4153–11541 of that capture).
  - ✅ Direct emitters added in `src/interpreter.s` (between `collectStaticDefs` and `programToGoPhase2`, around line 5642): `nullLiteralToGoDirect`, `toGoBooleanLiteralDirect`, `numberLiteralToGoDirect`, `stringLiteralToGoDirect`, `identifierToGoDirect`, `blockStatementToGoDirect`, `ReturnStatement_toGoDirect`, + central dispatcher `nodeToGoDirect(node)`. Unsupported node kinds emit a sentinel that fails the Go build loudly (`D1R_UNSUPPORTED_NODE_KIND_<type>`).
  - ✅ Feature flag wired: `directEmitAllowlist` map + `s["useDirectEmit"] = true` projection inside `collectStaticDefs`. The flag is set ONLY if (a) the def is in the allowlist AND (b) `resolvedIsStatic == true`. The `resolvedIsStatic` gate is critical for direct emit (param/local become Go vars; any ctx-fallthrough semantics must be observationally identical to direct Go) — even though D2-reborn dropped it. MVP allowlist contains a single name: `nullLiteralEvaluate` (body = `return null;`).
  - ✅ Impl-emit branch in `programToGoPhase2` (the `while sdi < len(staticDefNames)` loop): when `sdef["useDirectEmit"] == true`, emit the impl as direct Go statements (alias `ctx := callerCtx`, materialise each param as `var ij_<p> Value` populated from `args[i]`, declare `result Value = vNull()`, then `nodeToGoDirect(body)` for the function body, finally `return result`). The Node-tree body still goes into `ij_<name>_body` for indirect callers (`Value{tag:tFunc}` stored in a map). Signature stays `(callerCtx *Context, args []Value) Value` so `nkStaticCall.staticImpl` call sites need no change.
  - ✅ Verified: stage1 (committed-bridge → new src) emits `ij_nullLiteralEvaluate_impl` in direct-Go form; every other promoted def stays on the eval-wrapped path. `test.sh` ✅ via committed bridge, stage1, stage2. `verify.sh` 5/5 ✅. Stage1 selfhost-runtime-on `sample.s` works. Fib25 direct (NOT selfhost) timings: stage1 = 4.4s, stage2 = 19.3s — consistent with the documented stage1/stage2 ratio (no improvement from a single-def MVP flip, but also no regression).
  - Commit gate met: `verify.sh` 5/5 ✅, `test.sh` ✅. Source-only change — committed bridge untouched.

- [ ] **Run N+1: Expression-level direct emitters.**
  - Add `infixExpressionToGoDirect`, `prefixExpressionToGoDirect`, `callExpressionToGoDirect`, `indexExpressionToGoDirect`. After this, simple expression-only static defs (e.g. accessor helpers, math utilities) can flip to direct emit. Calls inside direct-emit bodies need a dispatch decision: known-at-emit-time static def → direct Go call (`ij_other_impl(...)`); else → fall back to value-call via `Value{tag:tFunc}.Execute`. Reuses the existing `staticDefByName` predicate from D2-reborn.
  - Expand the opt-in to ~5-10 more defs.
  - Commit gate: `verify.sh` 5/5 ✅, `test.sh` ✅, stage2 fib25 micro-bench drops further.

- [ ] **Run N+2: Statement-level direct emitters + flip predicate.**
  - Add `assignmentStatementToGoDirect`, `variableDeclarationToGoDirect`, `ifStatementToGoDirect`, `whileStatementToGoDirect`, `blockStatementToGoDirect`, `returnStatementToGoDirect`, `indexAssignmentToGoDirect`, `arrayLiteralToGoDirect`, `mapLiteralToGoDirect`. After this most parser helpers should be direct-emittable.
  - Flip the promoted-def predicate to a coverage check: walk the body, if every node kind has a direct emitter, opt in; else stay on Node-tree+eval. Defs migrate automatically as coverage grows.
  - Commit gate: `verify.sh` 5/5 ✅, `test.sh` ✅, stage2 selfhost `sample.s` approaches stage1 parity (target: ≤ 1m30s vs current 7m25s).

- [ ] **Run N+3: Close the regression + replace the committed bridge.**
  - Verify stage1 ≡ stage2 ≡ stage3 byte-identical (true fixed-point at the binary level).
  - `cp /tmp/d1r/stage2 interpreter_mac_arm64`; rebuild MCP via `./scripts/build.sh`. Verify `verify.sh` 5/5 ✅ with the new bridge.
  - Tighten `verify.sh` check 5 from determinism (same bootstrap → same output twice) to true fixed-point (stage1 install → stage2 build → diff).
  - Run `./scripts/bench.sh d1-reborn-bridge-replace`. **At this point all P2.5 + P2.6 source-level wins become observable.** Per the alloc-reduction math (~5%) + the per-call cost reductions in evalCall/evalFuncDecl, expect bench to drop substantially from the current 1m17s floor.
  - Drop-rule: if new bench is NOT ≥1.3× over `p2-no-refresh = 1m20.478s`, investigate before declaring the phase shipped (the wins should be real once the bridge is replaced — failure to materialise means a hidden runtime cost dominates and needs profiling).

**Other P2.6 backlog (non-blocking; can fit alongside D1-reborn runs):**

- [ ] **Capture stage2 pprof at HEAD on a quiet machine.** The defer-order bug is fixed (this loop), so `IJ_CPUPROFILE=/tmp/stage2.cpu` + `go tool pprof` now works. Save the profile to `docs/research/2026-05-18-stage2-cpu.pprof` (or similar) so future agents can read it without re-running. Quick, parallelisable with Run N scaffolding.
- [ ] **Patch `fix_app_go.py` to harden all lib-fn `params.Get(Value{tag: tInt, i: N})` call sites** with bounds checks. Mechanical sed; ~30 lib fns. Defensive depth even if not strictly needed. Low-risk, parallelisable.
- [ ] **NewStaticFunctionCommand wrapping for storage paths.** Currently when a static def is referenced by name as a value (e.g. assigned into a map), nkFuncDecl creates `Value{tag:tFunc, cmd:NewFunctionCommand(...)}`, NOT NewStaticFunctionCommand. Both paths produce identical results today but NewStaticFunctionCommand was the OLD-bridge sentinel for "this is a static impl we can fast-path." Switch to NewStaticFunctionCommand once it has meaningful behaviour (currently it's a passthrough — `src/interpreter.s:5202`). Deferred until D1-reborn opens an actual perf lever here.

**P2.6 experiments that DID NOT pan out (this loop):**

- ❌ **Stage2 args-slice elimination in ij_*_impl** (`patch_static.py`): rewrote `ij_<n>_impl(callerCtx, args []Value)` → `ij_<n>_impl(n *Node, ctx *Context)` with inline arg eval. Saved the `[]Value` slice alloc per static call site. Result: **0.3% wall improvement on fib25** (17.57s vs 17.85s). Negligible because user-level fib goes through closure path, not nkStaticCall path. Reverted.
- ❌ **Combined NewContext + map literal in ij_*_impl** (`patch_allocs.py`): single struct literal instead of `NewContext` + `Create`. Saved 1 alloc per impl call. Result: **1.6% wall improvement**. Reverted (negligible).
- ❌ **`sync.Pool` of `*Context` for closure body** (`patch_pool.py`): `getCtx(parent)` / `putCtx(c)` with map-clear-on-Put. Result: **fib25 → 0.5s wall but EMPTY output** — broke any IJ-level closure that captured a body-local context (`makeXxx(...)` MapValue patterns where node["evaluate"] = closure over enclosing scope). Pool is correct only when the closure body provably has no inner defs capturing local; that's the `resolvedIsStatic` predicate, which is currently dead. Reverted.
- ✅ **`sync.Pool` of `*ArrayValue` for evalCall args** (`patch_avpool.py`): `avPool.Get`/`Put` in evalCall, `args.values = args.values[:0]` for reuse. Result: **fib25 17.0s vs 17.85s = 4.8% wall improvement**. SAFE only if no library function retains the ArrayValue past Execute return. Audit of library fns shows most read args via `.Get(int)` and don't retain; the risky ones are array-returning fns like `keys()`/`values()` which return NEW arrays. **Not shipped this loop** because the risk audit needs verify.sh check 4 (MCP) pass — deferred to follow-up. The single-literal alloc-reduction patch DID ship (gives most of the same gain without the pool risk).

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
