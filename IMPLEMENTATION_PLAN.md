# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline ~70s. Need ≥10× cumulative.

**Spec:** `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md`
**Phased plan:** `docs/superpowers/plans/2026-05-16-self-hosted-perf-10x.md`

---

## Current State (verified 2026-05-17, against bench.log + git HEAD)

| Label | Real time | Speedup vs phase0 | Status |
|---|---|---|---|
| phase0-baseline | 1m11.153s | 1.00× | ✅ captured |
| phase0-baseline-eval | 1m16.438s | 0.93× | ✅ captured (sample.s line) |
| `run` (unlabeled, 02:13Z) | **0m49.274s** | **1.43×** | best ever — pre-Phase-2 state, identity unknown |
| phase2-typed-ast (03:46Z) | 1m25.086s | **0.83× — REGRESSION** | Phase 2 cutover |
| phase2-runtime (08:31Z) | 1m25.193s | 0.83× | Phase 2 runtime tweak, no improvement |
| phase2-current (14:44Z) | **1m29.188s** | **0.80× — REGRESSION** | HEAD re-baseline post-P0, new floor |

**Headline:** Phase 2 HEAD is a 25% regression vs phase0 (0.80×) and a 1.81× slowdown vs the unlabeled 02:13Z best. Drop-rule breached. 10× target (≤7s) requires ~12.7× improvement from current HEAD.

Phase 0 ✅ • Phase 1 ✅ committed • Phase 2 🔴 wired but regressing • Phase 3 ⬜ • Phase 4 ⬜

### P0 completed (2026-05-17 ~14:44Z)

- ✅ Goldens captured at HEAD `f84bee9` via `./scripts/verify.sh --capture` — `/tmp/ij-golden/{test,sample,mcp-interp,mcp-native}.out` exist.
- ✅ Full `./scripts/verify.sh` run: **5/5 PASS**, binaries bit-identical (check 5). HEAD is provably green; any future regression can be diff'd against these goldens.
- ✅ `scripts/bench.sh` labels fixed (lines 20+22 said `test.s` while running `sample.s`). Commented-out `bench_eval.s` block removed and replaced with a one-line note explaining why (Phase 2 codegen makes it >5min — re-enable only after primary bench hits 10×).
- ✅ `src/interpreter_debug.s` deleted. It was a 21:19 snapshot of `interpreter.s` taken just before commit `d69d42a` added the `NewArrayValue` nil-guard — i.e. stale by exactly the fix that resolved the Binary B crash, plus three `dbgF` puts wrapped around the codegen `toGo` call. No remaining diagnostic value.
- ✅ HEAD re-baselined: `phase2-current = 1m29.188s` written to `bench.log`. This is the new drop-rule floor for P1 triage.

---

## Priority-ordered TODO

### P0 — Ground truth + measurement hygiene (do first, no perf change)

All P0 items completed 2026-05-17 ~14:44Z. See *P0 completed* note above for evidence. Floor = `phase2-current = 1m29.188s`. Next loop starts at P1.

### P1 — 🔴 BLOCKER: Phase 2 regression triage (must resolve before P3)

The single biggest 10× obstacle is that Phase 2 made the bench slower, not faster. Drop-rule says revert; before reverting, audit which Phase 2 change broke perf, since the structural Node-tree change is sound (and required for P3+ pool indices on `Node.sIdx`).

- [ ] **Bisect the 02:13Z → 03:46Z regression window.** The unlabeled `run` at 02:13Z hit **49.27s (1.43×)**, then `phase2-typed-ast` at 03:46Z dropped to 85s (0.83×). That ~90-minute window is exactly the Phase 2 cutover. Use `git log --since='2026-05-17T02:13Z' --until='2026-05-17T03:46Z'` and `git bisect` (or manual `compile-local.sh` + `bench.sh` per commit) to identify the offending commit.
- [ ] **Audit D2 static-impl drop.** Per current `interpreter.s`: `emitQueuedImpls()` and `goLibSuffix()` are documented no-ops; comment says "D2 dropped for Phase 2 Node tree". D2 (`ij_<name>_impl(ctx, args...)` fixed-arity direct call, bypassing `FunctionCommand.Execute`) is the biggest pre-Phase-2 fast path per README. Removing it almost certainly explains a large chunk of the regression. Decide:
  - Option A: **Restore D2 alongside Node tree.** Function decls emit both a `ij_<name>_impl` fixed-arity Go func (body = direct Go translation of statement list) AND a `&Node{kind: nkFuncDecl, body: ...}` (used for capture / dynamic dispatch). Direct call sites resolve to `ij_<name>_impl(...)`; indirect (via `Value{tag: tFunc}`) goes through `eval(body, ...)`. This was the legacy approach — the override pattern (`let oldX = X; def X(...)`) needs the Func wrapper anyway.
  - Option B: **Audit D3 raw-bool helpers** (`EqualsBool`, `LessThanBool`, …). Confirm `conditionToGoBool` still routes if/while conditions through these. If Phase 2 eval routes conditions through `Value.Equals/LessThan` returning a boxed `Value`, that's a per-loop-iteration alloc regression on tight `while` loops.
  - Option C: **Audit D1 static resolution.** Resolver writes `resolvedKind`/`resolvedName` on IJ AST nodes but the Node-struct emit zeroes those fields (subagent audit confirmed `resolvedSlot` has zero writes). Currently every `nkIdent` eval goes through `ctx.Get(n.name)` → map-lookup-by-string. Pre-Phase-2 D1 short-circuited locals/params. Project resolved info into `Node.resolvedKind/Name` and switch `evalIdent` to use it.
- [ ] **Run drop-rule decision.** After D1/D2/D3 audit:
  - If we can recover ≥1.3× over phase1, keep Phase 2 and continue.
  - Else: revert Phase 2 commits (`f7783ed..d69d42a`) per drop-rule. Restart from Phase 1 (49s `run` state) and pursue Phase 3 directly on top of P1.

### P2 — Fix Binary B crash (unblocks end-to-end Phase 2 self-transpile)

Required only if Phase 2 is kept after P1 triage.

- [ ] **Confirm crash signature.** IMPLEMENTATION_PLAN claims "deep eval recursion → index out of range [0] with length 0 in lib fn". Reproduce w/ the cleaned `dba0ddc` binary transpiling `interpreter.s`; capture full panic + goroutine stack. The "index out of range with length 0" is a slice/string bounds-check, not a stack overflow — likely a library function (e.g. push/append/get) receiving an empty collection from a Phase 2 eval path that the test programs don't exercise.
- [ ] **Add diagnostic logging in the emitted lib functions** that take string/array args. Goal: identify which lib fn, on which Node, with which empty input. Once located, fix the underlying empty-collection handling (mirrors the `NewArrayValue` nil-guard already added in commit `d69d42a`).
- [ ] **Only if true stack overflow:** convert recursive `eval()` dispatch to iterative trampoline in `goLibPrefix`. ~200 LOC change, but mechanical. Alternative: emit `debug.SetMaxStack(1 << 30)` in `main()`.
- [ ] **Replace committed `interpreter_mac_arm64`** with the cleaned Phase 2 binary (currently the committed binary is the pre-cleanup `ac2e6f3`-era hybrid that sidesteps the crash via old-style `ij_puts.Execute` paths). This change makes verify.sh check 5 honest.

### P3 — Phase 3: String interning + singletons (expected 1.3–1.8×)

Per design §Phase 3. Only start once P1 + P2 are settled.

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

- [ ] **README perf section update.** Append phase1–phaseN rows to the speedup table; one-paragraph description per phase; D1/D2/D3 lessons captured if D1/D2 ended up reborn under Phase 2.
- [ ] **Remove `cleanup_phase1.py`** if no longer referenced (verify with `rg cleanup_phase1`).
- [ ] **Remove `scripts/fix_app_go.py`** once the committed binary is fully Phase-2-clean and the legacy hybrid bridge isn't needed for any pipeline step (currently it's the load-bearing post-processor for `compile-local.sh`; removing prematurely breaks the build).
- [ ] **Garbage-collect tree-walker `evaluate` path** in `interpreter.s`. Phase 2 codegen produces `&Node{...}` literals consumed by emitted `eval()` in Go — the IJ-side `node["evaluate"]` callable entries are still used by `scripts/interpreter.sh` (tree-walker) and by AST-emit JSON. Audit which `evaluate*` functions are reachable from `scripts/interpreter.sh src/sample.s` and `scripts/ast.sh`; everything else is dead. Don't strip without dead-code audit — `scripts/interpreter.sh` and the resolver pass both still depend on the IJ-side AST shape.

---

## Open Questions / Risks

- **What was the 02:13Z `run` (49s)?** It's the only number above baseline. Worth a `git show <commit-around-02:13Z>` to confirm whether it was a real Phase-1-only state or a transient experiment. If real, it's the actual P1 result and the bench labels in the log are wrong.
- **fix_app_go.py mtime is 21:41 today** — same minute as the binary build. Active edits in this session. Read its current state before any P1 triage; the bridge logic may already encode an attempted regression fix.
- **D4 lesson (README):** "looks faster, is slower." Every phase commit must be measured, not assumed. Phase 2's current 0.83× is exactly this scenario at a phase boundary.
- **MCP regression risk.** verify.sh check 4 currently can't run (no goldens). The override pattern (`let oldX = X; def X(...)`) is the MCP-relevant invariant. Re-capture goldens (P0) before any codegen edit touching `functionDeclarationToGo`.

## Build & verification reminders

- Use `./src/compile-local.sh` (Docker-less). `compile-mac.sh` / `build.sh` silently swallow Docker failures and mask regressions.
- Two consecutive `compile-local.sh src/interpreter.s` must produce byte-identical binaries (verify.sh check 5).
- Drop-rule on every phase boundary: `<1.3×` over predecessor ⇒ revert.
- Scripts moved root → `scripts/` per AGENTS.md: `scripts/bench.sh`, `scripts/verify.sh`, etc.
