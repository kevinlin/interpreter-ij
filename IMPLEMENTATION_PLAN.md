# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline `phase0 = 71.153s`. Need ≥10× cumulative.

> Single source of truth for status, blockers, next-run roadmap. Design recipe lives under `docs/specs/`. Research/current-state map: `docs/research/2026-05-18-interpreter-perf-research.md`.
> **Verified:** 2026-05-29 (audit workflow against `src/interpreter.s` HEAD `1848c9c` + `bench.log`).

---

## 0. TWO REALITY CHECKS — read before picking up any task

A 4-agent audit (2026-05-29) verified the codegen state, the runtime alloc ceiling, the bench methodology, and doc consistency. Two findings change the priority order.

### 🔴 Reality check A — the measurement is broken (FIX FIRST)

The selfhost bench **measures the committed binary**, which is frozen at commit `ac2e6f3` (pre-cleanup OLD bridge: direct-Go impl bodies + interface `Value`). It has **never been replaced**. So every source change since (P1, P2, P2.5, P2.6 Runs N..N+6) is **invisible to `bench.sh`**. We have optimised blind for ~10 loops.

Worse, the bench is single-run on a loaded laptop. The **same committed binary** measured across `bench.log` spans **70.45s … 109.18s = 1.55× noise band**. The drop-rule threshold is **1.3×**. **Noise > drop-rule ⇒ every "1.04× within noise" verdict in this plan is statistically meaningless.** No perf decision made so far is trustworthy.

**Consequence:** until the bench can measure a *fresh* build with *repeat/min* statistics, do not chase 1.3× wins — they cannot be detected. This is now **P-A (top priority)** and it is cheap (shell-script changes). Spec: `specs/bench-methodology.md`.

> **STATUS 2026-05-29:** the P-A harness has **shipped** — `bench.sh --fresh` (true fixed-point stage2 build) + `--repeat N` (min/median/max under `GOMAXPROCS=1`), via `IJ_BINARY` overrides in `native_interpreter.sh` and `compile-local.sh`. Source work is now visible to the bench. Remaining open item: pick the noise-robust drop-rule threshold once the first `--fresh --repeat 3` band is in hand.

### 🔴 Reality check B — the planned phases almost certainly cannot reach 10×

The committed bridge (~71–104s) is already a *direct-Go-bodies* build. Fully landing D1-reborn only brings the new emit back to that **emit shape (≈ parity, ~1×)**. The remaining planned levers stack against Amdahl's law:

| Lever | Realistic gain over committed bridge | Why bounded |
|---|---|---|
| tagged-union `Value` (shipped P1) | ~1.0–1.3× | 88-byte by-value copy may be net-negative vs 24-byte interface; needs measurement |
| D1-reborn complete (Runs N..N+7) | →parity, then ~1.1–1.3× | matches bridge emit; small net win from tagged-union + fewer allocs |
| P3 interning + singletons | ~1.1–1.3× | saves a string-header alloc per literal; does **not** cut eval()/dispatch cost |
| P4 slot-indexed contexts | ~1.3–1.6× | cuts `ctx.Get` chain walks; eval() dispatch + Value copy remain |
| **Stacked plausible ceiling** | **~2–4× over phase0 (≈18–36s)** | per-node tree-walk eval() cost + ~33% GC are irreducible in a tree-walker |

pprof (stage2, fib25): `eval`+`Execute`+`evalBlock`+`evalCall` ≈ 34% cum, `evalFuncDecl.func1` 33.6%, GC (kevent+gcBgMark) ≈ 33%. The planned phases attack **allocation rate**, not **operation count** or **per-node dispatch cost**. **≤7s (10×) realistically requires a structural lever the current plan treats as out-of-scope:** a bytecode VM (eliminates per-node `eval()` dispatch + Value copy; est. 5–8×), a smaller `Value` (tagged-pointer / NaN-box; ~1.3–1.5×), or caching the parsed `interpreter.s` AST across the two selfhost reparses (~1.2–1.5×). Spec: `specs/10x-feasibility-and-structural-levers.md`.

**This is NOT a reason to stop.** Nobody has measured a fresh fully-landed new emit (deadlock above). The honest path is **measurement-first, then an evidence-based decision gate** — do not pre-abandon the incremental path, but do not pretend 10× is one loop away.

---

## 1. Current state (verified 2026-05-29)

| Artifact | Selfhost sample.s | Emit shape | Note |
|---|---|---|---|
| **committed bridge** (`interpreter_mac_arm64`, frozen `ac2e6f3`) | ~71–104s (noisy) | OLD: 188 `ij_*_impl` direct-Go bodies, interface `Value`, 0 `nkStaticCall` | what `bench.sh` actually runs |
| **stage1** (committed → new src) | ~1m45s (parity) | NEW emit, but produced by OLD bridge whose `functionDeclarationToGo` predates Run N+6 → FuncDecls carry no `staticImpl`, so the IF-branch never fires | parity with committed |
| **stage2** (stage1 → new src, true fixed-point ≡ stage3) | **75.61s** pinned min-of-3 (Run N+7) | NEW: 226 `ij_*_impl`, **214 direct-Go bodies** + 12 `eval(body)` holdouts; FuncDecls carry `staticImpl` so the closure-hoist IF-branch fires; `ctxGet` no longer scans on the hot path | **2.84× faster than N+6; now ≤ committed → bridge-replace gate appears OPEN (confirm head-to-head)** |

**Trajectory of stage2 selfhost** (fresh self-build, the number that actually reflects source work): Run N+2 `4m32s` → N+3 `4m1s` → N+5 `4m15s` → **N+6 `2m26.2s`** (closure-body hoist, 1.74×) → **N+7 `75.61s` pinned** (`ctxGet`/`mapHasKey` hot-path reorder, **2.84×** over the N+6 pinned baseline `214.42s`). Single biggest lever in the whole arc — `mapHasKey`'s `keys()` array-alloc + linear scan was both the hottest leaf (10.12% flat) AND a top GC driver (GC ~33% of wall); removing it from the common lookup path cut scan + allocation together. Bench: `--fresh --repeat 3`, `GOMAXPROCS=1`, band 75.61/75.63/76.68s (1.01×).

Phase status: P0 ✅ • P1 ✅ (tagged-union shipped; cleanup dropped D1/D2/D3) • P2 ✅ (typed AST) • P2.5 ✅ (resolver wired, source-only) • P2.6 D2-reborn ✅ + D1-reborn Runs N..N+6 ✅ • P-C Run N+7 ✅ (`ctxGet`/`mapHasKey` reorder, 2.84×, stage2 now `75.61s` ≤ committed → **bridge-replace gate appears open**) • P3 ⬜ • P4 ⬜.

---

## 2. Architecture facts (load-bearing — do not lose)

**The selfhost bench is three nested IJ-interpretation layers.** `selfhosted_interpreter.sh src/sample.s` →
`native binary` (compiled `interpreter.s`) tree-walks → **interpreter.s instance A** tree-walks → **interpreter.s instance B** tree-walks → **sample.s**.
Wall time is dominated by A tree-walking B's full run (B = interpreter.s parsing its own ~250KB source + defining ~200 fns + running sample.s). So the hot quantity is *(native per-node eval cost) × (IJ operations B performs)*.

**Why stage2 was slower than the committed bridge (root cause, Run N..N+6 closes it):** the committed bridge emits each interpreter.s function as a **direct Go statement body** (`func ij_nextToken_impl(...) { ...direct Go... }`). The naïve NEW emit wrapped each body as `result,_ := eval(ij_<n>_body, local)` — a Node-tree tree-walk at runtime, allocating per node visit. D1-reborn re-emits promoted-static-def bodies as direct Go (`nodeToGoDirect`, `src/interpreter.s:6464-6519`). 214/226 promoted defs now direct-Go; only 12 holdouts still `eval(body)` (`:6536-6547`).

**The remaining stage2 gap is dispatch machinery, not body-eval.** Every IJ-level `node["evaluate"](node, ctx)` (e.g. `:6767`, `:366`, `:1186`) compiles to: `evalCall` (`:5577`) → `callee.cmd.Execute` → `FunctionCommand` closure (`:5546`) → `ij_<n>_impl_wrapper` (`:6522`, unpacks `[]Value`→positional) → `ij_<n>_impl` (direct Go). Several hops + an `[]Value` built-then-unpacked per node visit. **Run N+7 targets this.**

**Key mechanisms:**
- `collectStaticDefs` (3 passes, `:~5700`): promote `resolvedAtRoot && counts[name]==1` defs (the `counts==1` gate excludes the `let oldX=X; def X` override idiom). Opt into `useDirectEmit` if `resolvedIsStatic && (allowlisted || canDirectEmit(body))`.
- `canDirectEmit` (`:5758-5920`): rejects bodies containing nested `FunctionDeclaration` → the 12 holdouts (`makeProgram`, `makeMapLiteral`, `makeReturnValue`, `makeInterpreter`, `makeIndexExpression`, `makeWhileStatement`, `buildToJson`, `evaluateFunctionDeclaration`, `zero/one/two/threeWrapper`) are AST-construction factories + arity wrappers — **not hot path** (called once per node during parse).
- `functionDeclarationToGo` (`:1799-1801`): appends `, staticImpl: ij_<n>_impl_wrapper` when `useDirectEmit`.
- `evalFuncDecl` (`:5544-5551`): IF-branch dispatches the closure body through `staticImpl` (passing `defCtx`=`rootCtx`, NOT `callerCtx`, because `Execute` discards callerCtx).
- `CallExpression_toGo` (`:3126`) emits `nkStaticCall` with the wrapper for direct-by-name calls; `CallExpression_toGoDirect` (`:6145-6190`) emits positional `ij_<n>_impl(ctx,a,b)` when caller/callee arity match, else `_impl_wrapper(ctx,[]Value{...})`.

**Invariants that must hold every commit:** verify.sh check 5 (two `compile-local.sh interpreter.s` runs byte-identical) + check 4 (MCP override-pattern). `staticDefNames` is in source order (no map-iteration nondeterminism).

---

## 3. Priority-ordered TODO

### P-A — Fix measurement + break the gating deadlock (LANDED 2026-05-29; harness shipped)

Spec: **`specs/bench-methodology.md`** (corrected this loop — see fixed-point note below). The drop-rule was unenforceable until this landed.

- [x] **`IJ_BINARY` override** in `scripts/native_interpreter.sh` (`:27-32`) — env var propagates through the whole nested self-host stack for free. Verified: explicit override + committed binary prints "Hello hi"; bogus path errors (proves the var is read).
- [x] **`IJ_BINARY` bridge override** in `src/compile-local.sh` (`:27-31`) — lets a fixed point be built (committed→s1, then `IJ_BINARY=s1`→s2) **without ever overwriting/restoring the committed binary**. Obsoletes the unsafe `cp /tmp/s1 interpreter_mac_arm64` dance.
- [x] **`bench.sh --fresh`**: now builds the **TRUE FIXED POINT (stage2)**, not stage1. 🔴 **Key finding / spec correction:** the original spec's single `compile-local src/interpreter.s` produces **stage1**, which uses the frozen pre-Run-N+6 committed bridge → FuncDecls carry **no `staticImpl`** → IF-branch never fires → parity-blind to the closure-body-hoist work (§1). A single-stage `--fresh` would report ~committed parity and **hide the exact source work P-A exists to reveal.** `bench.sh --fresh` therefore does the 2-stage build (stage1 committed-bridge → stage2 stage1-bridge) and benches stage2. Both builds verified to succeed end-to-end.
- [x] **`bench.sh --repeat N`** (default 1; use 3 for decisions): runs the selfhost block N times under `GOMAXPROCS=1`, reports **min/median/max** of `real` + `user` via a python aggregator; headline = **min real**. Default no-flag path is preserved (three `time` blocks, committed binary).
- [x] **Noise controls:** `GOMAXPROCS=1` on the repeat selfhost runs (GC threads ~33% of wall dominate variance); `user` time reported alongside `real`. Outlier filter (>1.1× median) deferred — not needed until the band is measured.
- [ ] **Decide the drop-rule under noise:** PARTIAL. First fixed-point band captured (`label=n6-fresh-fixedpoint`, `--fresh --repeat 2`, `GOMAXPROCS=1`): **real min/median/max = 214.42 / 221.25 / 228.08s** (band 1.06×), **user = 188.25 / 190.79 / 193.33s** (band 1.03×). The pinned repeat band (1.03–1.06×) is **far tighter than the 1.55× single-run committed band** → 1.3× wins are now detectable; the 1.3× drop-rule looks usable as written. **Still TODO:** capture the committed binary's band the same way (`--repeat 3`, no `--fresh`) for the side-by-side, and bump `--repeat` default to 3 for decisions. Deterministic-proxy fallback (`ijCount*`) not needed unless a later band widens. NB pinned stage2 (214s) vs unpinned hand-rolled (146s) differ only by `GOMAXPROCS=1`; the pinned number is the gate.
- [x] **Sanity-gate `--fresh`:** `compile-local.sh src/interpreter.s` twice byte-identical is verify.sh check 5 (unchanged; still the reproducibility prerequisite).

### P-B — 10× feasibility decision gate (after P-A; evidence-based)

Spec: **`specs/10x-feasibility-and-structural-levers.md`** (authored this loop).

- [ ] **Measure the real cumulative gain once the bridge is replaceable** (P-C). With `--fresh`, capture: new-emit-fully-landed selfhost vs `phase0=71.153s`. This is the first honest cumulative number in the whole effort.
- [ ] **Update the design spec's projection.** `docs/specs/...-design.md` claims "~12–87× / realistic 10–15×" multiplicative. That is inconsistent with the measured trajectory and Amdahl reality (§0-B). Revise to the realistic ~2–4× incremental ceiling + the structural-lever requirement. (Per Ralph instruction #14, this spec is inconsistent with reality and must be corrected.)
- [ ] **Gate decision:** if fully-landed incremental new emit + P3 + P4 measures < ~3× over phase0 (i.e. > ~24s), the incremental path cannot reach ≤7s — **pivot to a structural lever** and author its spec. Candidates, in increasing effort: (1) cache parsed `interpreter.s` AST across the two selfhost reparses (~1.2–1.5×, smallest); (2) shrink `Value` to a tagged-pointer/NaN-box (~1.3–1.5×); (3) **bytecode VM** — transpile the IJ AST to bytecode and run a flat dispatch loop instead of recursive `eval()` over `*Node` (est. 5–8×; the only lever that plausibly reaches 10× alone). Prototype the bytecode arithmetic+call subset before committing.

### P-C — Run N+7 + committed-binary replace (the gating critical path, now measurable via P-A)

- [x] **Capture a fresh stage2 pprof at HEAD first** (load-bearing for path selection): saved `docs/research/2026-05-29-stage2-cpu.pprof` (+ `-top.txt`). 🔴 **Surprise top frame:** it is **NOT** the `node["evaluate"]` dispatch — it is **`ij_mapHasKey_impl` = 11.17s flat (10.12%), the single hottest leaf** (next leaf `eval` is 2.32s), with **33.70% cum**, ~all of it reached **through `ij_ctxGet_impl`** (2.91s flat / **44.72% cum**). So scope-chain variable resolution, not closure dispatch, is the dominant cost — and `mapHasKey`'s `keys()`-array-alloc + linear-scan is the leaf to kill.
- [x] **Run N+7-mapHasKey — reorder `ctxGet` to skip the present-null scan on the hot path** (`src/interpreter.s` `ctxGet`, 2026-05-29). Root cause: the old `ctxGet` did `values[name]` → (if null) `mapHasKey(values)` → `functions[name]` → `mapHasKey(functions)`. Looking up a **builtin or top-level def** (the overwhelmingly common case: every `puts`/`len`/operator-helper call in the inner layer) found `values[name]==null` and so ran `mapHasKey(values_global)` — a `keys()` alloc + linear scan over the hundreds-deep global values map — **before** ever probing `functions`. Fix: **probe `functions[name]` BEFORE the values present-null scan**, and **drop the `mapHasKey(functions)` scan entirely** (functions are never registered null). Now the hot builtin/global-fn path is two O(1) map reads, zero scans; `mapHasKey(values)` runs only on a genuine miss or an explicit null binding (rare). No sentinel, no new builtin → no bootstrap hazard. **Behaviour change (documented, accepted):** an explicit null binding that shadows a same-scope function name (e.g. `let len = null; len`) now resolves to the function instead of null. Pathological; `test.s` + sample + MCP all pass 1- and 2-layer; the MCP override idiom (`let oldX=X; def X`) involves no nulls and is unaffected. **Selfhost delta: `214.42s → 75.61s` pinned min-of-3 (`--fresh --repeat 3`, `GOMAXPROCS=1`), 2.84× — bench label `n7-maphaskey-reorder`, band 1.01×.** verify.sh 5/5 (incl. fixed-point check 5).
- [ ] **Run N+7 — specialise the `node["evaluate"](self, ctx)` indirect dispatch.** Two routes (NOT interchangeable; pick by pprof):
  - **Path 2 (preferred — lower risk, runtime-only):** cache the impl pointer on the Node. In the `make*` factories, alongside `node["evaluate"] = SomeDef`, set `node["evaluateImpl"]` to the promoted def's wrapper when the def is in `staticDefByName`. At tree-walker call sites (`:6767`, `:366`, `:368`, `:1186`) check `evaluateImpl` before the `MapValue.Get("evaluate")` + `Execute` hops. No codegen pattern-matching.
  - **Path 1 (codegen-level):** when the emitter sees `<expr>["evaluate"](<expr>,<ctx>)`, emit a tagged dispatch straight to `_impl_wrapper`. More fragile (pattern recognition in the `*ToGoDirect` emitters).
  - Cheap adjacent win regardless of path: the indirect path builds an `*ArrayValue`/`[]Value` then `impl_wrapper` immediately unpacks it positionally — collapse the double-wrap for `staticImpl` closures.
- [ ] **Close the 12 holdouts only if pprof says they matter** (they are parse-time AST factories, not selfhost-hot — likely skip). Closing needs nested-`FunctionDeclaration` support in `canDirectEmit`/`nodeToGoDirect`.
- [ ] **Replace the committed binary** — **gate now appears OPEN after N+7** (stage2 `75.61s` pinned min-of-3 vs the committed bridge's ~71–104s *unpinned*, which is ~105–150s pinned; stage2 is well under). **Before replacing, capture the committed binary's pinned min-of-3 head-to-head** (`bench.sh --repeat 3`, no `--fresh`) to confirm stage2 ≤ committed on the same harness. Then `cp /tmp/ij-fresh interpreter_mac_arm64` (or rebuild), re-run `verify.sh` 5/5, and tighten check 5 from determinism to true fixed-point. Per AGENTS.md: keep a `git restore interpreter_mac_arm64` escape until the replace is committed. (Deferred from the N+7 commit — bridge replacement is a deliberate, separately-verified step.)

### P3 — String interning + singletons (queued; only after P-C, and only if cumulative < 10×)

Per design §Phase 3. Singletons (`vNull/vTrue/vFalse/vEmpty/smallInt[256]/strPool`) + `vIntFast` in `goLibPrefix`; route `eval` literal cases through them; IJ-side `strPoolIntern` (first-appearance order for determinism); `stringLiteralToGo` emits `sIdx`. Determinism gate + `bench.sh --fresh phase3-intern`. **Lever is small** (per-literal alloc only) — expect ~1.1–1.3×.

### P4 — Slot-indexed contexts (stretch; only if cumulative after P3 < 10×)

Per design §Phase 4. Resolver assigns `nextSlot` per scope; project `resolvedSlot`+depth into Node (fields already exist, zero-valued); `Context.slots []Value` + `GetSlot/SetSlot`; `evalIdent/evalAssign/evalVarDecl` switch on `resolvedKind` to slot access; top-level globals stay map-based (override pattern + MCP). `bench.sh --fresh phase4-slots`.

### P5 — Cleanup once 10× hit (or once a structural pivot supersedes the tree-walker)

- [ ] README perf section: append phase rows + the D1/D2/D3-reborn arc + the 10×-ceiling lesson.
- [ ] Drop dead infra confirmed by the audit: `ijCount*` counters (`:~4508`, declared+dumped, never incremented — unless re-instrumented for P-A proxy), `useNodeTree` switch (`:~5388`, permanently true), `opCodeFor("!")` branch (`:858`, no caller), dead Node fields after P3/P4 settle which are live (`pos`, `sIdx` until P3, `resolvedSlot` until P4, `isStatic`), `fix_app_go.py` + its dead `EqualsBool`-family injection (only once the committed binary is fully Phase-2-clean — it is the load-bearing post-processor today), `cleanup_phase1.py` if unreferenced.
- [ ] Dead-code-audit the IJ-side `evaluate*` tree-walker before stripping — `scripts/interpreter.sh` + `scripts/ast.sh` + the resolver still depend on the IJ-side AST shape.

---

## 4. Shipped-phase changelog (compressed — forensics in git history + §2)

- **P0** (2026-05-17): goldens captured; `bench.sh` labels fixed; `bench_eval.s` dropped from bench (>5min under Phase 2 codegen — re-add after primary hits 10×); `interpreter_debug.s` deleted. Floor `phase0=71.153s`.
- **P1** (tagged-union `Value`, then cleanup `b040672`): 88-byte `Value{tag,b,i,d,s,arr,m,cmd,inv}` by value, tag-switch dispatch. **Cleanup accidentally dropped the D1/D2/D3 fast paths** — the root cause of the whole regression saga. The "49s outlier" (`c5da0ac`) is irreproducible (transitional dual-runtime that no longer compiles) — NOT a floor.
- **P2** (typed AST `Node`): `&Node{kind:nkXxx,...}` + per-kind `evalXxx` switch; `(Value,bool)` return-sentinel (chose over `tReturn`); `refreshToGoPointers` excised (`c42261c`); stage2 scalar-VarDecl regression fixed via `isReturnValue` isMap guard (`:1210`, `fdf23ec`).
- **P2.5** (resolver wiring, `6ca08e9..5bf147a`): `rk*` consts, `resolverKindCode`, `identifierToGo`/`assignmentStatementToGo`/`variableDeclarationToGo` project `resolvedKind`; `evalIdent`/`evalAssign` fast paths (`rkLib`→`rootCtx.GetLocal`); `evalBlock` gates `NewContext` on `hasLocals`; `FunctionCommand.Execute` drops a Context alloc. All source-only — **invisible to bench** (committed bridge predates it). `evalIdent` rkParam/rkLocal fast path left unlifted (per-block ctx still shadows).
- **P2.6 D2-reborn** (`6c4d429`): `nkStaticCall` + `staticImpl` func-pointer for direct-by-name calls. **Was the wrong-shape fix** — collapses direct calls but not the dominant closure path.
- **P2.6 D1-reborn** (Runs N..N+6): direct-Go-statement emit for promoted defs.
  - N: scaffold + `nodeToGoDirect` dispatcher + 1 def.
  - N+1: expression-level emitters (infix/prefix/call/index) + 8 leaf defs.
  - N+2: statement-level emitters + library-globals plumbing + `canDirectEmit` predicate → 142/226 defs. Stage2 7m25s→4m32s.
  - N+3: `rkGlobalLet` plumbing (`setTopLetGoVar` dual-write) for top-level user `let`s → 214/226. Stage2 4m32s→4m1s.
  - N+4a: implicit-return tail-expression fix (`result = <expr>` at tail, 54 sites).
  - N+5: positional-arg calling convention + arity-fallback wrapper. Confirmed nkStaticCall is NOT the bottleneck.
  - **N+6: closure-body hoist via FuncDecl `staticImpl`** → stage2 4m15s→**2m26.2s** (1.74×). The `node["evaluate"]` closure now dispatches into the direct-Go wrapper instead of `eval(body)`.

---

## 5. Research-doc backlog (status as of 2026-05-29)

Research doc `docs/research/2026-05-18-interpreter-perf-research.md` audited HEAD `c42261c`; several findings are now resolved by P2.5/P2.6.

| Research § | Finding | Status |
|---|---|---|
| §2.2 | `Context.Get` chain-walks per `evalIdent` | ✅ P2.5 (rkLib fast path); rkParam/rkLocal deferred → P4 |
| §2.3 | ~5 heap allocs per `evalCall` | ✅ partial P2.5 (block+caller ctx) + N+6 alloc-reduction |
| §2.4 | `evalBlock` always allocs Context | ✅ P2.5 (`hasLocals` gate, `:5459`) |
| §3.2 | All resolver annotations dead | ✅ P2.5 (`resolvedKind` now read by `evalIdent`) — **research doc now stale here** |
| §3.10 | `FunctionCommand.Execute` wastes a Context alloc | ✅ P2.5 (`executeFunc(nil,…)`) |
| §2.8 | String literals emit per occurrence | ⬜ P3 |
| §3.1 | Six dead Node fields | 🔄 partially live post-P2.5 (`resolvedKind` live; `sIdx`→P3, `resolvedSlot`→P4, `isStatic`/`pos` still dead) → P5 |
| §3.3 | `analyzeIsStatic` walks bodies | ✅ activated (D1-reborn `useDirectEmit` predicate) |
| §3.4/§3.6/§3.7 | `useNodeTree`/`ijCount*`/`opCodeFor("!")` dead | ⬜ P5 |
| §3.9 | Phase-3 singleton scaffolding present, not emitted | ⬜ P3 |
| §4.5 | Committed binary is one-way bridge; check 5 = determinism | 🔄 P-C (bridge replace) |
| §4.7 | `registerLibraryFunctions.func12` (`assert`) length-0 panic | ⬜ retest under stage2 |
| §4.11 | `bench_eval.s` dropped (>5min) | ⬜ re-enable after 10× |

---

## 6. Open questions / risks

- **🚫 DEAD-END — in-band null sentinel (do not retry).** Replacing `mapHasKey` by storing null bindings as a distinctive string sentinel (`"__IJ_NULL_SENTINEL_b7e3c1__"`) in `ctx["values"]` to make absent-vs-present-null an O(1) read **is fundamentally broken under self-hosting** and was reverted 2026-05-29. Empirically: in 2-layer (`interpreter.sh`) a program doing `let m={}; m["k"]=<sentinel>; m["k"]` reads back **null**, not the string (`type:null`, `is_null:true`). The outer interpreter layer's own `ctxGet`/value pipeline re-interprets any value equal to its sentinel as null, so the inner layer's sentinel is "re-sentinelised" and corrupted. **Any** in-band marker reachable through a name lookup hits this — confirmed with both the map-roundtrip and `let x=null` minimal repros. The only sentinel-free O(1) options are a native presence builtin (blocked by the frozen-committed-bridge bootstrap — checks 2/3 would see an undefined `hasKey`) or the call-ordering fix actually shipped (see P-C Run N+7-mapHasKey).
- **10× may be infeasible via tree-walking** (§0-B). The design spec's projection is over-optimistic. Resolve via P-B gate after the first honest fresh measurement.
- **Drop-rule vs noise** (§0-A): unenforceable at 1.3× under 1.55× noise. P-A fixes the measurement before any phase-boundary decision is trusted.
- **Committed binary is a one-way bridge** (`ac2e6f3`, OLD emit no current source reproduces). Don't lose it: `git restore interpreter_mac_arm64` after any accidental recompile until P-C replace lands.
- **MCP override pattern** (`let oldX=X; def X`) is the verify.sh check-4 invariant. Any `functionDeclarationToGo`/`collectStaticDefs` edit re-runs verify.sh in full. `counts==1` gate preserves it.
- **Resolver mis-classification:** every emitter switching on `resolvedKind` keeps a chain-walk fallback for unannotated (`rkGlobal=0`) nodes. A `vInvalid("variable not found")` regression ⇒ fall back to fallback, don't ship.
- **`hasLocals` shadowing:** inner-block `let` shadowing must keep per-block ctx. If `test.s` regresses, force `hasLocals:true` for blocks containing `If`/`While`.

## 7. Build & verification reminders

- `./src/compile-local.sh` (Docker-less). `compile-mac.sh`/`build.sh` silently swallow Docker failures and mask regressions.
- Two consecutive `compile-local.sh src/interpreter.s` must be byte-identical (verify.sh check 5).
- For phase-boundary perf decisions use **`bench.sh --fresh`** (once P-A lands) — committed-bridge numbers are the production gate only, they cannot see source work.
- Scripts live in `scripts/` (driver) + `src/` (compile). `echo |` for scripts that don't call `gets()`.
