# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline `phase0 = 71.153s`. Need ≥10× cumulative.

> Single source of truth for status, blockers, next-run roadmap. Design recipe lives under `docs/specs/`. Research/current-state map: `docs/research/2026-06-11-perf-benchmark-bottlenecks-and-optimization-ledger.md` (supersedes the archived 2026-05-18 research docs).
> **🟢 P-VM.4 SHIPPED 2026-06-12 (this loop): the IJ-side `evaluate` evaluator now has its own bytecode VM — selfhost 123.99s → 34.94s = 3.55× same-session pinned min-of-3.** A second, IJ-written VM (`ijvm*` defs in `src/interpreter.s`, ~7430-8400) compiles the inner program's AST (MapValue nodes) to flat int-opcode chunks and executes them on a shared slot stack — this is the layer the Go-side VM could never touch (interpreter.s-as-data tree-walking interpreter.s-as-data). Gates: `IJ_VM=0` kills every VM at every nesting depth (the new `getenv` builtin chains down through each layer); `IJ_VM_IJ=0` kills only the IJ-side VM (differential isolation); `IJ_VM_DEBUG=1` prints `[ijvm]` compile stats per layer. On interpreter.s: 363 top-level stmts → 251 escaped (parse/def-time, not hot), **274 func chunks, only 12 bails**. Parity proven at 1-/2-/3-layer + difftest 11/11 + MCP; fixed point re-established (s2==s3) and committed binary replaced; `mcp_mac_arm64` rebuilt; verify.sh 5/5. **Gap to ≤7s goal: 34.94s = 5× remaining → P-VM.5 (lean Value, ~2.4× measured headroom) + close the 12 chunk bails + retire the dead walker.** See P-VM.4 section.
> **🟢 P-VM.3 SHIPPED 2026-06-12 (prior loop): the bytecode VM is the DEFAULT engine.** `main()`'s env-gate inverted — `IJ_VM=0` opts back into the tree-walk eval (escape hatch until P-VM.4 retires the dead walker); `IJ_VM_DEBUG=1` works on the default path. `vm_difftest.sh` re-pointed at default-VM-vs-`IJ_VM=0` (11/11 incl. the new MCP differential + an opt-out check); fixed point re-established (s2==s3) and committed binary replaced (`70d51330…`); `mcp_mac_arm64` rebuilt under the flipped default (`a796eea1…`); verify.sh 5/5 with the VM running every check (incl. the check-5 transpile itself). Bench `phase-vm3`: see P-VM.3 section. **Next implementation loop: P-VM.4 (mirror the VM into the IJ-side `evaluate` evaluator — the selfhost-dominant layer and the actual ≥8× lever).**
> **🟢 RESOLVER CLOBBER BUG FIXED 2026-06-12 (this loop, found by the P-VM.3 MCP pre-flight):** `resolveVariableDeclaration` stamped each VarDecl with the *enclosing-scope resolution* of its name (sequential block resolution → lookup runs before the local declare), so a function-local `let result` in a tree-walked body resolved to a same-named TOP-LEVEL let → `rkGlobalLet` → emitted `evalVarDecl` ran `setTopLetGoVar`, **clobbering the package-level Go var of the genuine global**. Latent since Run N+3; invisible to verify because check 4 tested the frozen May-16 MCP binary — the first fresh MCP transpile since then returned `invalid: type mismatch in Add` for every `execute_script` (eval.s's global `result` zeroed by inner-interpreter locals; same masked clobber exists via `makeInterpreter`'s `let interpreter = {}`). Fix: VarDecl nodes are now stamped with the binding they *create* (root → `rkGlobalLet`, else `rkLocal`); Identifier/Assignment stamping unchanged (assignment semantics genuinely write the resolved binding). Consumers audited: emitted `evalVarDecl`, VM `compileVarDecl` (slot-by-name; top-level flag preserved), `variableDeclarationToGoDirect` (always Go-local var — was never affected), `analyzeIsStatic`/`canDirectEmit` (don't read VarDecl kind). Fixed point rebuilt + committed binary replaced; **`mcp_mac_arm64` rebuilt from current source for the first time since 2026-05-16**; `vm_difftest.sh` gained a fresh-build MCP differential (check 3) so the overlay workload can never silently rot again. verify.sh 5/5, difftest 10/10.
> **🟢 P-VM.2 SHIPPED 2026-06-11 (prior loop):** full node-kind coverage under `IJ_VM=1` — `vmOpArray`/`vmOpMap`/`vmOpIndex`/`vmOpIndexStore`/`vmOpStaticCall`/`vmOpMakeStaticFn` + block-scoped `let`s in func chunks (compile-time shadow records). interpreter.s escape count **269 → 14** (12 nested-def holdouts + 2 other), funcChunks 0 → 2 (`getTokenLiteral` ×2). Differential green at all 3 nesting layers on stage2 + 3 new abort/coverage test programs (`tests/vm/vmtest{4,5,6}.s`); fixed point re-established and committed binary replaced (`4c42e04b…`); verify.sh 5/5. Remaining bails (deliberate, see P-VM.2 section): nested defs, upvalues, unannotated writes inside funcs, top-level hasLocals blocks. **Next implementation loop: P-VM.3 (flip default), but see the P-VM.3 pre-flight notes first.**
> **🟢 P-VM.1 SHIPPED 2026-06-11 (this loop):** Go-side bytecode VM landed behind `IJ_VM=1`, default path untouched. `goVMPrefix()` (new def after `goLibPrefix` in `src/interpreter.s`) emits ~26 opcodes + `vmCompileProgram`/`vmCompileFunc`/`vmExec`/`vmCallChunk` as constant prelude text; `main()` env-gates `vmRunProgram(programNode, ctx)` vs `eval(...)`. Differential-tested at all 3 nesting layers + 3 dedicated VM test programs; fixed point re-established and committed binary replaced (verify.sh 5/5). See P-VM.1 section for the load-bearing semantics learnings (poison values, unbound params, stage1-vs-stage2 testing gotcha).
> **🟢 DEADLOCK BROKEN 2026-05-29:** committed bridge **replaced** with the true fixed-point stage2 (`fa1fe55…`, was frozen `ac2e6f3`/`282e1126…`). First honest same-session pinned head-to-head: **committed-old 88.74s vs stage2 71.08s = 1.25× cumulative** for the entire source arc since `ac2e6f3` (P1+P2+P2.5+P2.6 N..N+7). The default `bench.sh` now measures current source — the gating deadlock that hid ~10 loops is gone. **P-B verdict: 1.25× ≪ the 3× pivot threshold → the incremental tree-walker path cannot reach ≤7s; pivot to a structural lever (bytecode VM).** See §0 + P-B.
> **🟢 PIVOT DE-RISKED 2026-05-30 (this loop):** the bytecode-VM lever is **measured, not guessed**. A faithful tree-walker-vs-VM prototype (`experiments/bytecode-vm-prototype/`, same 88-byte `Value`) gives **vm 7.96× / vmLean 19.19×** on fib(32) with **per-call allocs 35.2M → ~0**. Lever 3 = GO. Implementation spec authored: **`docs/specs/bytecode-vm-implementation.md`**. Next loop starts P-VM.1 (Go-side VM behind `IJ_VM` flag). See §0-B + P-VM.

---

## 0. TWO REALITY CHECKS — read before picking up any task

A 4-agent audit (2026-05-29) verified the codegen state, the runtime alloc ceiling, the bench methodology, and doc consistency. Two findings change the priority order.

### 🟢 Reality check A — RESOLVED 2026-05-29 (measurement fixed + bridge replaced)

**Was:** the selfhost bench measured the committed binary, frozen at `ac2e6f3` (pre-cleanup OLD bridge: direct-Go impl bodies + interface `Value`), never replaced. Every source change since (P1, P2, P2.5, P2.6 Runs N..N+7) was invisible to `bench.sh`. And the single-run bench spanned **70.45s … 109.18s = 1.55× noise band** > the 1.3× drop-rule, so every "within noise" verdict was meaningless.

**Now (both halves fixed):**
1. **P-A harness shipped** — `bench.sh --fresh` (true fixed-point stage2 build) + `--repeat N` (min/median/max under `GOMAXPROCS=1`), via `IJ_BINARY` overrides. **Pinned min-of-3 collapses the noise band from 1.55× to 1.01×** (both stage2 and committed measured this loop at band 1.01×) — far below the 1.3× drop-rule, so **the 1.3× drop-rule is now usable as written.**
2. **Committed bridge REPLACED** (this loop) with the true fixed-point stage2 (`fa1fe55…`). The default `bench.sh` (no `--fresh`) now measures current source. The gating deadlock is gone.

**First honest same-session pinned head-to-head** (`GOMAXPROCS=1`, `--repeat 3`, back-to-back, 2026-05-29):

| Binary | real min / median / max | band |
|---|---|---|
| committed-OLD bridge (`ac2e6f3`/`282e1126…`) | 88.74 / 89.47 / 89.62s | 1.01× |
| stage2 fixed point (`fa1fe55…`, now committed) | 71.08 / 71.58 / 72.03s | 1.01× |

→ **1.25× cumulative** for the whole source arc since `ac2e6f3`. (Note: the OLD committed bridge measured **88.74s pinned**, not the ~105–150s the plan previously guessed — the win is 1.25×, not ~1.4–2×. Earlier "stage2 vs guessed-committed" comparisons overstated the gain; this same-session number is the trustworthy one.)

### 🔴 Reality check B — CONFIRMED by measurement: the planned phases cannot reach 10×

> **2026-05-29 update:** the first honest cumulative number (§Reality-check-A) is **1.25×** over the frozen bridge. That is *below* even the optimistic 2–4× ceiling estimated below — the incremental tree-walker path is closer to exhausted than the table hoped. **The P-B gate (< 3× ⇒ pivot) is met. Pivot to a structural lever.** The text below remains the rationale.


The committed bridge (~71–104s) is already a *direct-Go-bodies* build. Fully landing D1-reborn only brings the new emit back to that **emit shape (≈ parity, ~1×)**. The remaining planned levers stack against Amdahl's law:

| Lever | Realistic gain over committed bridge | Why bounded |
|---|---|---|
| tagged-union `Value` (shipped P1) | ~1.0–1.3× | 88-byte by-value copy may be net-negative vs 24-byte interface; needs measurement |
| D1-reborn complete (Runs N..N+7) | →parity, then ~1.1–1.3× | matches bridge emit; small net win from tagged-union + fewer allocs |
| P3 interning + singletons | ~1.1–1.3× | saves a string-header alloc per literal; does **not** cut eval()/dispatch cost |
| P4 slot-indexed contexts | ~1.3–1.6× | cuts `ctx.Get` chain walks; eval() dispatch + Value copy remain |
| **Stacked plausible ceiling** | **~2–4× over phase0 (≈18–36s)** | per-node tree-walk eval() cost + ~33% GC are irreducible in a tree-walker |

pprof (stage2, fib25): `eval`+`Execute`+`evalBlock`+`evalCall` ≈ 34% cum, `evalFuncDecl.func1` 33.6%, GC (kevent+gcBgMark) ≈ 33%. The planned phases attack **allocation rate**, not **operation count** or **per-node dispatch cost**. **≤7s (10×) realistically requires a structural lever the current plan treats as out-of-scope:** a bytecode VM (eliminates per-node `eval()` dispatch + Value copy), a smaller `Value` (tagged-pointer / NaN-box; ~1.3–1.5×), or caching the parsed `interpreter.s` AST across the two selfhost reparses (~1.2–1.5×). Spec: `specs/10x-feasibility-and-structural-levers.md`.

**🟢 The bytecode-VM lever is now MEASURED (2026-05-30).** `experiments/bytecode-vm-prototype/` benches a byte-for-byte-faithful clone of the emitted runtime (88-byte `Value`, `Context{parent,map}` chain lookups, `eval(*Node)(Value,bool)`, `FunctionCommand` closure, per-call `*Context`+map+`*ArrayValue`) against a slot-based bytecode VM with the **same** `Value`:

| engine (same 88-byte Value) | fib(32) min wall | allocs/call | speedup |
|---|---|---|---|
| treeWalk (faithful emit clone) | 2.588 s | 35,245,806 | 1.00× |
| **vm — Lever 3 only** | **0.325 s** | **~40** (one-time arena) | **7.96×** |
| vmLean — Lever 3 + lean Value | 0.135 s | ~38 | 19.19× |

→ Lever 3 lands at the **top of the 5–8× estimate** with no Value-shrink inflation, and removes **all** per-call heap traffic (the ~33% GC cost). It models the *lighter* Go-side tree-walk, so the selfhost-dominant IJ-side `MapValue` walk gain is **≥ 8×**. **GO.** Implementation spec: `docs/specs/bytecode-vm-implementation.md`.

**This is NOT a reason to stop.** Nobody has measured a fresh fully-landed new emit (deadlock above). The honest path is **measurement-first, then an evidence-based decision gate** — do not pre-abandon the incremental path, but do not pretend 10× is one loop away.

---

## 1. Current state (verified 2026-05-29)

| Artifact | Selfhost sample.s | Emit shape | Note |
|---|---|---|---|
| **committed binary** (`interpreter_mac_arm64`, now `d17ae10f…` after P-VM.4; `70d51330…` was the P-VM.3 flip, `4c42e04b…` P-VM.2, `255e274e…` P-VM.1, `fa1fe55…` the 2026-05-29 original) | **34.94s pinned min-of-3 (2026-06-12, P-VM.4)** vs same-session P-VM.3 control 123.99s = 3.55× | NEW emit + Go-side VM (top layer) + IJ-side VM (interpreted layers), both default-on (`IJ_VM=0` opt-out, `IJ_VM_IJ=0` IJ-side only) | **IS the true fixed point of current source at every commit since 2026-05-29 (verify.sh check 5); re-replaced each loop that touches the prelude** |
| OLD frozen bridge (`ac2e6f3`/`282e1126…`, no longer committed) | 88.74s pinned min-of-3 | OLD: 188 `ij_*_impl` direct-Go bodies, interface `Value`, 0 `nkStaticCall` | superseded; recover via `git show 062e95c:interpreter_mac_arm64` if ever needed |
| stage1 (any fresh build via the NEW committed bridge) | == stage2 (fixed point) | NEW emit | the NEW committed bridge already emits `staticImpl`, so stage1 == stage2 == stage3 now (no more parity-blind stage1) |

**Trajectory of stage2 selfhost** (fresh self-build, the number that actually reflects source work): Run N+2 `4m32s` → N+3 `4m1s` → N+5 `4m15s` → **N+6 `2m26.2s`** (closure-body hoist, 1.74×) → **N+7 `75.61s` pinned** (`ctxGet`/`mapHasKey` hot-path reorder, **2.84×** over the N+6 pinned baseline `214.42s`) → P-VM.1/2/3 ~parity (VM dormant in selfhost-dominant layers; cross-session absolutes incomparable) → **P-VM.4 `34.94s` pinned (2026-06-12, 3.55× over the same-session P-VM.3 control `123.99s`)**. Single biggest lever in the whole arc — `mapHasKey`'s `keys()` array-alloc + linear scan was both the hottest leaf (10.12% flat) AND a top GC driver (GC ~33% of wall); removing it from the common lookup path cut scan + allocation together. Bench: `--fresh --repeat 3`, `GOMAXPROCS=1`, band 75.61/75.63/76.68s (1.01×). **2026-05-29 head-to-head (less-loaded box, same session for both):** stage2 `71.08s` vs OLD committed bridge `88.74s` = **1.25×**; bridge then **replaced** (`fa1fe55…`). 1.25× is the honest cumulative for the whole arc since `ac2e6f3` — confirms the incremental ceiling is near-exhausted (§0-B).

Phase status:
 • P0 ✅
 • P1 ✅ (tagged-union shipped; cleanup dropped D1/D2/D3)
 • P2 ✅ (typed AST)
 • P2.5 ✅ (resolver wired, source-only)
 • P2.6 D2-reborn ✅ + D1-reborn Runs N..N+6 ✅
 • P-C Run N+7 ✅
 • P-C bridge-replace ✅ (2026-05-29: committed binary IS the fixed point; 1.25× cumulative head-to-head)
 • P-A ✅ (harness + pinned bands; drop-rule now usable)
 • P-B ✅ gate resolved → PIVOT to structural lever
 • P-VM.0 ✅ (2026-05-30: lever de-risked — vm 7.96×/vmLean 19.19× measured; spec authored)
 • P-VM.1 ✅ (2026-06-11: Go-side VM behind `IJ_VM=1`; subset + escapes; verify 5/5; fixed point replaced)
 • P-VM.2 ✅ (2026-06-11: full node-kind coverage; escapes 269→14; verify 5/5; fixed point replaced again)
 • P-VM.3 ✅ (2026-06-12: VM is the default engine, `IJ_VM=0` opt-out; MCP differential added; resolver clobber bug fixed en route; fixed point replaced `70d51330…`)
 • P-VM.4 ✅ (2026-06-12: IJ-side VM in the `evaluate` evaluator; selfhost 123.99s → 34.94s = 3.55×; fixed point replaced)
 • P-VM.5 ⬜ NEXT (lean Value ~2.4× headroom + close the 12 IJ-side chunk bails — the remaining 5× to ≤7s)
 • ~~P3~~ deprioritised
 • ~~P4~~ **subsumed by P-VM** (resolver `resolvedSlot` feeds the VM's slot frames directly).

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

### P-A — Fix measurement + break the gating deadlock (✅ COMPLETE 2026-05-29)

Spec: **`specs/bench-methodology.md`** (corrected this loop — see fixed-point note below). The drop-rule was unenforceable until this landed. **All items closed:** harness shipped, both pinned bands captured, drop-rule confirmed usable (1.01× band), committed bridge replaced so the default bench now sees source work.

- [x] **`IJ_BINARY` override** in `scripts/native_interpreter.sh` (`:27-32`) — env var propagates through the whole nested self-host stack for free. Verified: explicit override + committed binary prints "Hello hi"; bogus path errors (proves the var is read).
- [x] **`IJ_BINARY` bridge override** in `src/compile-local.sh` (`:27-31`) — lets a fixed point be built (committed→s1, then `IJ_BINARY=s1`→s2) **without ever overwriting/restoring the committed binary**. Obsoletes the unsafe `cp /tmp/s1 interpreter_mac_arm64` dance.
- [x] **`bench.sh --fresh`**: now builds the **TRUE FIXED POINT (stage2)**, not stage1. 🔴 **Key finding / spec correction:** the original spec's single `compile-local src/interpreter.s` produces **stage1**, which uses the frozen pre-Run-N+6 committed bridge → FuncDecls carry **no `staticImpl`** → IF-branch never fires → parity-blind to the closure-body-hoist work (§1). A single-stage `--fresh` would report ~committed parity and **hide the exact source work P-A exists to reveal.** `bench.sh --fresh` therefore does the 2-stage build (stage1 committed-bridge → stage2 stage1-bridge) and benches stage2. Both builds verified to succeed end-to-end.
- [x] **`bench.sh --repeat N`** (default 1; use 3 for decisions): runs the selfhost block N times under `GOMAXPROCS=1`, reports **min/median/max** of `real` + `user` via a python aggregator; headline = **min real**. Default no-flag path is preserved (three `time` blocks, committed binary).
- [x] **Noise controls:** `GOMAXPROCS=1` on the repeat selfhost runs (GC threads ~33% of wall dominate variance); `user` time reported alongside `real`. Outlier filter (>1.1× median) deferred — not needed until the band is measured.
- [x] **Decide the drop-rule under noise:** DONE 2026-05-29. Both bands captured this loop under the identical pinned harness (`--repeat 3`, `GOMAXPROCS=1`, back-to-back): stage2 **71.08/71.58/72.03s (band 1.01×)**, OLD committed bridge **88.74/89.47/89.62s (band 1.01×)**. The pinned min-of-3 band is **1.01× ≪ the 1.3× drop-rule ≪ the 1.55× single-run band** → the **1.3× drop-rule is usable as written**; no deterministic-proxy (`ijCount*`) fallback needed. `--repeat` default stays 1 (quick smoke); decisions use `--repeat 3` (documented in `bench.sh` header + AGENTS.md) — not worth changing the no-flag default-behaviour contract. NB the OLD bridge is **88.74s pinned**, well under the ~105–150s the plan had guessed.
- [x] **Sanity-gate `--fresh`:** `compile-local.sh src/interpreter.s` twice byte-identical is verify.sh check 5 (unchanged; still the reproducibility prerequisite).

### P-B — 10× feasibility decision gate (✅ RESOLVED 2026-05-29 → PIVOT)

Spec: **`specs/10x-feasibility-and-structural-levers.md`** (authored this loop).

- [x] **Measured the real cumulative gain** (this loop, bridge now replaceable+replaced via P-C): same-session pinned head-to-head **stage2 71.08s vs OLD committed bridge 88.74s = 1.25×** — the first honest cumulative number in the whole effort. (vs the unpinned single-run `phase0=71.153s`: not directly comparable across pinning regimes; the same-session pinned 1.25× is the trustworthy figure.)
- [x] **Updated the design spec's projection** — `docs/specs/2026-05-16-self-hosted-perf-10x-design.md` had "~12–87× / realistic 10–15×". Corrected 2026-05-29 to the measured ~1.25× incremental result + the structural-lever requirement (Ralph instruction #14).
- [x] **Gate decision: PIVOT.** 1.25× ≪ the 3× threshold (and below even the optimistic 2–4× estimate) ⇒ the incremental tree-walker path cannot reach ≤7s. Chosen lever: **(3) bytecode VM** — the only lever that plausibly reaches 10× alone. (Lever 1 AST-cache ~1.2–1.5× benchmark-specific; Lever 2 lean `Value` ~1.3–1.5× — kept as the optional P-VM.5 stacking step.)
- [x] **De-risked the chosen lever** (2026-05-30, this loop): `experiments/bytecode-vm-prototype/` measures **vm 7.96× / vmLean 19.19×** on fib(32) vs a faithful emit clone, per-call allocs 35.2M → ~0. Confirms the 5–8× estimate (top of band) is real, not optimistic.
- [x] **Authored the implementation spec first** (Ralph #12/#5): `docs/specs/bytecode-vm-implementation.md` (IR, opcodes, calling convention, fixed-point/MCP invariants, phased P-VM.1…5 landing).

### P-VM — Bytecode VM (the structural lever; ✅ de-risked, ⬜ landing)

Spec: **`docs/specs/bytecode-vm-implementation.md`**. Replaces recursive AST evaluation with compile-to-bytecode + a flat dispatch loop. Subsumes P4 (the VM's slot frames ARE slot-indexed contexts; `compileChunk` numbers slots itself — see P-VM.1 note).

- [x] **P-VM.0 — de-risk prototype + spec** (2026-05-30). 7.96× measured (lower bound; models the lighter Go-side walk). GO.
- [x] **P-VM.1 — Go-side VM behind `IJ_VM=1` (SHIPPED 2026-06-11).** `goVMPrefix()` def (constant prelude text — fixed point unaffected by construction) + `main()` env-gate. Runtime compile at binary startup (spec §6.1 route): `vmCompileProgram(programNode)` compiles top-level statements **per-statement with rollback** — unsupported statements become `vmOpEvalNode` escapes into `eval(stmt, ctx)`; top-level FuncDecls *without* `staticImpl` get all-or-nothing `vmCompileFunc` body chunks with slot-indexed frame locals (own name→slot numbering, per the 2026-06-10 resolvedSlot correction — resolver untouched). Promoted defs (staticImpl) stay on the evalFuncDecl fast branch via escape — direct Go bodies are already faster than the VM. Subset: literals/ident/infix(+`&&`/`||` jumps)/prefix/call/assign/var-decl/block/if/while/return/funcDecl. Func-chunk bail rules (correctness-first): nested defs, upvalues, lets in nested blocks (block-scoped shadowing), unannotated global writes, array/map/index/staticCall (→ P-VM.2). On interpreter.s itself: 338 top-level stmts, 69 VM-compiled, 269 escaped, 0 func chunks (all promoted/holdouts — expected); func chunks proven via redefined-def test programs (redefinition defeats the `counts==1` promotion gate). **Verified:** differential `IJ_VM=1` vs default at 1-layer (test.s+sample.s vs golden), 2-layer (`interpreter.sh`), 3-layer (`selfhosted_interpreter.sh` vs golden), + 3 dedicated VM test programs (committed at `tests/vm/vmtest{1,2,3}.s`, harness `scripts/vm_difftest.sh` — func chunks incl. recursion/short-circuit-side-effects/arity-over+underflow/override-pattern/bail-fallback, non-function-call abort, undefined-var abort). Fixed point rebuilt (s2==s3) + committed binary replaced (`255e274e…`); verify.sh 5/5. `IJ_VM_DEBUG=1` prints compile stats to stderr.
  - 🔴 **Load-bearing semantics learnings (carry into P-VM.2/4):**
    1. **Invalid values are POISON VALUES, not exceptions.** `evalInfix` returns the invalid operand as the expression result (l-invalid skips right entirely; r-invalid discards l), `evalCall` does NOT check args (invalids flow into callees; `puts(invalid)` PRINTS it), assignments BIND invalid before the statement check aborts. Only per-statement checks (`vmOpStep`) abort frames. First VM draft treated invalid as frame-abort → diverged + stack-misaligned (SIGSEGV). Now: `vmOpJumpIfInvKeep` (keep top, jump to expr end) after infix-left/prefix/callee/if-cond; `vmOpJumpIfInvDrop` (drop the value beneath) after infix-right and while-cond.
    2. **Missing params are UNBOUND, not vNull.** The evalFuncDecl closure binds only provided args; reads of missing params chain-walk to defCtx at read time (usually → vInvalid). AGENTS.md's "missings vNull-pad" describes only the positional-impl wrapper path. Slots cannot model unbound → `vmCallChunk` falls back to the exact closure path (`eval(bodyNode, local)`) on arity underflow; overflow (extras dropped) stays on slots.
    3. **Stage1 is parity-blind for runtime features.** A committed-bridge build (s1) carries the NEW emitters as program DATA but the OLD runtime prelude — `IJ_VM=1` is a silent no-op on s1 (differential passes vacuously). Always differential-test on **stage2** (s1-bridge build). Confirm the VM actually engaged with `IJ_VM_DEBUG=1` (stderr stats), not just by matching output.
  - **Bench `phase-vm1` (2026-06-11, pinned `--repeat 3`, GOMAXPROCS=1): 120.12s min-of-3 (band 1.002×).** Looks like a 1.6× regression vs N+7's 75.61s — it is NOT. Same-session controls: OLD committed binary (`fa1fe55…`) + current source = **120.26s** (→ new binary parity; the dormant VM costs ~0); OLD binary + OLD source both inner layers = **113.7s** (→ **+5.7% honest cost: the interpreted layer A parses the +553-line goVMPrefix text in B**); remaining 75.61→113.7 delta = box state drift vs the 2026-05-29 session (the cross-session hazard §0-A warned about — only same-session comparisons are valid). Same-session new-vs-old = 1.056×, within the 1.3× drop-rule. Expect another small parse-cost bump when P-VM.4 grows the source; the ≥8× VM win dwarfs it.
- [x] **P-VM.2 — full node-kind coverage (SHIPPED 2026-06-11).** interpreter.s escapes **269 → 14**, funcChunks 0 → 2 (`getTokenLiteral` ×2 — the only redefined def). All differential gates green on stage2 (1-/2-/3-layer + `vm_difftest.sh` incl. 3 new test programs); fixed point rebuilt (s2==s3) and committed binary replaced (`4c42e04b…`); verify.sh 5/5. What landed (all in `goVMPrefix`, constant prelude text — fixed point safe by construction):
  - `vmOpArray`/`vmOpMap` (count operand, build from stack). **NO per-element invalid checks** — `evalArrayLit`/`evalMapLit` have none (invalids are appended/Put verbatim). Odd trailing map expr never evaluated (`i+1 < len` guard mirrored).
  - `vmOpIndex` + `vmOpIndexStore` (`nkIndexAssign` in `compileStmt`): invalid **collection** short-circuits keeping the invalid as the result (idx/rhs never evaluated); idx/rhs themselves are NOT invalid-checked (`coll.Get(invalid)` runs). Statement result of an index-assign = rhs. NB the surface parser only accepts single-level `name[idx] = v` — nested stores go through a reference temp, so `compileIndexAssign`'s `n.left` is in practice an ident, but it compiles any expr.
  - `vmOpStaticCall` (node-idx operand → baked `staticImpl` pointer): **per-arg invalid checks** (unlike `nkCall`, where invalids flow into the callee — both behaviors differential-tested in `vmtest4`/`vmtest5`). Args COPIED to a fresh `[]Value` — the impl may re-enter the VM (`vmCallChunk` bases at current `vmSP`) and would clobber an in-stack window. New `vmOpJumpIfInvDropN` (b = values to drop beneath the kept invalid) generalizes and replaced `vmOpJumpIfInvDrop` (infix-r/while-cond now emit b=1).
  - `vmOpMakeStaticFn`: promoted-def declarations (staticImpl != nil) compile to an exact mirror of the `evalFuncDecl` staticImpl fast branch instead of escaping — this is what cleared ~226 of the 269 escapes. Bodies stay direct Go (faster than the VM); only the declaration is VM-compiled.
  - **Block-scoped `let`s in func chunks**: compile-time shadow records (`vmShadowRec{name, oldSlot, had}` + per-block scope marks). A block `let` gets a FRESH slot; block end restores the symtab mapping → reads after the block see the outer binding which kept its value. Re-let in the SAME block reuses its slot (UpdateLocal overwrite). Statement-order compilation exactly models fresh-ctx-per-block-entry (incl. while bodies: the let re-stores each iteration). Differential-tested: param shadowing, re-let, while-body lets, read-after-block (`vmtest4`).
  - `vmCompileProgram` now rolls back `ch.nodes` too (static-call/static-fn node refs share the registry with escapes) and counts escapes explicitly for the debug line.
  - **Remaining bails (deliberate, correctness-first):** nested `FuncDecl` in chunks (a chunked nested def running under rootCtx can't model recursion via self-name nor function-local `ctx.Create` binding), upvalue idents (only reachable via nested defs anyway — belt-and-braces), unannotated writes inside funcs (dynamic Exists/Update/Create may target a function-local ctx slots can't model), top-level `hasLocals` blocks. The 14 residual escapes = the 12 nested-def holdouts (AST factories; parse-time only, not hot) + 2 unidentified top-level stmts. Closing these is NOT needed for P-VM.3 — escapes are semantics-preserving by construction.
  - New differential tests: `tests/vm/vmtest4.s` (arrays/maps/index chains/index-store/static calls top-level + in-chunk/block-let shadowing/invalid-flows-into-puts-and-continues), `vmtest5.s` (static-call invalid-ARG abort at statement boundary — note `puts(twice(missing))` does NOT abort, the `let` binding makes it statement-level), `vmtest6.s` (index-assign invalid-collection abort; side-effect args never evaluated).
  - **Bench `phase-vm2` (2026-06-11, pinned `--repeat 3`, GOMAXPROCS=1): new committed 130.29s min-of-3 (band 1.02×) vs same-session old-P-VM.1-binary control 153.03s (band 1.10× — box got noisy during the control). No regression; 1.3× drop-rule passes.** The apparent 1.17× "speedup" is box drift, not real — both binaries run identical default paths (VM dormant); treat as parity. Cross-session absolute numbers (P-VM.1's 120.12s) remain incomparable per §0-A.
  - 🔴 **Ops lesson (cost a bench rerun):** never edit a script while a backgrounded run of it is still executing — bash reads script files incrementally, so the edit shifted the file offset mid-run and the old-binary control aborted with a garbage command. Re-ran the control after the edit settled.
- [x] **P-VM.3 — flip default to VM + re-establish the true fixed point (SHIPPED 2026-06-12).** Gate decision: **kept `IJ_VM=0` as the opt-out** during P-VM.4 (deleting it would orphan the differential harness; remove with the dead tree-walker in P-VM.4/5). What landed:
  - The MCP pre-flight differential **caught a real bug before the flip** — not a VM bug: the first fresh MCP transpile since 2026-05-16 was broken on BOTH engines by the resolver VarDecl-stamp clobber (see the 2026-06-12 header bullet). Fixed + committed separately (`8084ff8`, tag 0.0.28) with its own fixed-point replace; `mcp_mac_arm64` is now current source (`a796eea1…`) and `vm_difftest.sh` check 3 rebuilds + differentials the MCP overlay fresh from source every run (func chunks for the overridden `gets`/`puts` engage: `program stmts: 350 escaped: 14 funcChunks: 6`).
  - Flip itself: `main()` emit now `if os.Getenv("IJ_VM") == "0" { eval } else { vmRunProgram }` (`src/interpreter.s:~7390`). `vm_difftest.sh` re-pointed at default-vs-`IJ_VM=0` + an explicit opt-out check (gate-inversion guard). Fixed point committed→s1→s2→s3, `cmp s2 s3` identical; committed binary = s2 (`70d51330…`); verify.sh 5/5 — note check 5's transpile now itself runs through the VM, so the fixed point doubles as a VM-on-transpile-workload proof.
  - Stage discipline reminder: s1 (committed-bridge build) still carries the OLD opt-in gate — the flip only manifests at s2. All runtime checks were done on s2 (`IJ_BINARY=/tmp/flip_s2`) before the replace, incl. the 3-layer selfhost vs golden.
  - **Bench `phase-vm3` (2026-06-12, pinned `--repeat 3`, GOMAXPROCS=1): committed-new (VM default) 143.33/150.80/151.06s vs same-session pre-flip control (`fix_s2`, eval default) 130.34/135.17/148.30s — min-of-3 ratio 1.10×, inside the 1.3× drop-rule.** The box was loaded (control band alone 1.14×, vs the usual 1.01×); user-time mins differ only 3% (124.67 vs 120.94s), so most of the wall gap is noise, with a small real VM-dispatch overhead plausible. Expected shape either way: the Go-side VM only runs top-level statements + 2 func chunks — the selfhost-dominant work lives in promoted direct-Go bodies + the IJ-side `evaluate` walk, untouched until P-VM.4. Cross-session absolutes (vs P-VM.2's 130.29s) remain meaningless per §0-A.
- [x] **P-VM.4 — mirror the VM into the IJ-side `evaluate` evaluator (SHIPPED 2026-06-12).** A second VM, written in IJ (`ijvm*` defs, `src/interpreter.s` between `mapToJsonString` and `makeInterpreter`), compiles the *inner* program's MapValue-AST to chunks of parallel int arrays (`ops`/`a`/`b` + `consts`/`names`/`poss`/`nodes` pools) and executes them on a shared growable slot stack (`ijvmStack`/`ijvmSP`, frame = `[base, base+numSlots+maxDepth)`). **Selfhost bench: 123.99s → 34.94s = 3.55× (same-session pinned `--repeat 3`, control = HEAD worktree at P-VM.3).** Key design points:
  - **18 numeric opcodes** (no name lookups in dispatch), two-level `op < 7` / `op < 13` if-chain ordered by frequency. All `ijvm*` defs pass `canDirectEmit` → they run as **direct Go** in the native layer (global `let` writes like `ijvmSP` are fine — `setTopLetGoVar` dual-write).
  - **Gate plumbing:** new `getenv`/`eputs` builtins in the Go prelude (`goLibPrefix`), re-registered by `StdIOLibraryFunctionsInitializer` at every interpreted layer via `oneWrapper(getenv)` — so `IJ_VM=0` reaches ALL nesting depths through one `os.Getenv` chain. `IJ_VM_IJ=0` disables only the IJ-side VM. Gate lives in `makeInterpreter.evaluate` (tree-walk vs `ijvmRunProgram`); per-function fast path in `evaluateFunctionDeclaration` (closure checks `node["ijvmChunk"]`, set by `ijvmAttachChunks` at chunk-compile time, calls `ijvmCallChunk`).
  - **Tree-walk semantics mirrored exactly** (differential-proven): `&&`/`||` do NOT short-circuit (both sides eval, then `applyInfixOperator`); missing args **null-pad** slots (IJ closures, unlike the Go-side unbound-param rule); every block = fresh scope via compile-time shadow records; chunk compile bails (12 on interpreter.s) on nested `def`, `let` shadowing hazards it can't model, etc. — bailed functions fall back to the tree-walk closure, mixing freely.
  - **Errors:** `ctxGet`/`throwRuntimeError`/`raiseRuntimeError` are called with the same positions as the tree-walk, so overridden error handlers (eval.s/MCP collect-and-continue) behave identically — MCP differential green.
  - **Verified:** brace-balance + parse (a missing `}` in `ijvmExec` initially swallowed the bootstrap suffix — symptom: empty `ij_ijvmExec_body =` in app.go + program node truncated at `ijvmExec`); stage2 difftest 11/11; 2-layer + 3-layer default-vs-`IJ_VM=0` parity; `[ijvm]` engagement at both inner layers (`IJ_VM_DEBUG=1`); fixed point s2==s3; committed binary + `mcp_mac_arm64` replaced; verify.sh 5/5; test.sh green.
  - **Not done (deliberate):** the dead tree-walker is NOT yet dropped — `IJ_VM=0`/`IJ_VM_IJ=0` escape hatches and the 12 bailing functions still need it, and `ast.sh`/resolver share the AST shape. Retire in P-VM.5+ after the bails are closed.
- [ ] **P-VM.5 — stack Lever 2** (NaN-box/tagged-pointer `Value`; `vmLean` measured ~2.4× headroom) **+ close the 12 IJ-side chunk bails + retire the dead tree-walker.** Remaining gap to goal: 34.94s → ≤7s = 5×. Lean Value (~2.4×) alone is not enough — also profile where the remaining selfhost time lives (likely: the 12 bailed functions' tree-walk, `ctxGet` global lookups from chunks (`loadName`), and the L1-interprets-L2's-ijvmExec tower).

### P-C — Run N+7 + committed-binary replace (✅ critical path done; bridge replaced 2026-05-29)

> Bridge replacement landed this loop — the gating deadlock is broken. The remaining open items below (`node["evaluate"]` dispatch specialisation, 12 holdouts) are **incremental tree-walker perf**, now **deprioritised by the P-B pivot verdict** (1.25× cumulative ⇒ structural lever, not more tree-walker tweaks). Keep them only as context if the pivot prototype falls through.

- [x] **Capture a fresh stage2 pprof at HEAD first** (load-bearing for path selection): saved `docs/research/2026-05-29-stage2-cpu.pprof` (+ `-top.txt`). 🔴 **Surprise top frame:** it is **NOT** the `node["evaluate"]` dispatch — it is **`ij_mapHasKey_impl` = 11.17s flat (10.12%), the single hottest leaf** (next leaf `eval` is 2.32s), with **33.70% cum**, ~all of it reached **through `ij_ctxGet_impl`** (2.91s flat / **44.72% cum**). So scope-chain variable resolution, not closure dispatch, is the dominant cost — and `mapHasKey`'s `keys()`-array-alloc + linear-scan is the leaf to kill.
- [x] **Run N+7-mapHasKey — reorder `ctxGet` to skip the present-null scan on the hot path** (`src/interpreter.s` `ctxGet`, 2026-05-29). Root cause: the old `ctxGet` did `values[name]` → (if null) `mapHasKey(values)` → `functions[name]` → `mapHasKey(functions)`. Looking up a **builtin or top-level def** (the overwhelmingly common case: every `puts`/`len`/operator-helper call in the inner layer) found `values[name]==null` and so ran `mapHasKey(values_global)` — a `keys()` alloc + linear scan over the hundreds-deep global values map — **before** ever probing `functions`. Fix: **probe `functions[name]` BEFORE the values present-null scan**, and **drop the `mapHasKey(functions)` scan entirely** (functions are never registered null). Now the hot builtin/global-fn path is two O(1) map reads, zero scans; `mapHasKey(values)` runs only on a genuine miss or an explicit null binding (rare). No sentinel, no new builtin → no bootstrap hazard. **Behaviour change (documented, accepted):** an explicit null binding that shadows a same-scope function name (e.g. `let len = null; len`) now resolves to the function instead of null. Pathological; `test.s` + sample + MCP all pass 1- and 2-layer; the MCP override idiom (`let oldX=X; def X`) involves no nulls and is unaffected. **Selfhost delta: `214.42s → 75.61s` pinned min-of-3 (`--fresh --repeat 3`, `GOMAXPROCS=1`), 2.84× — bench label `n7-maphaskey-reorder`, band 1.01×.** verify.sh 5/5 (incl. fixed-point check 5).
- [ ] **Run N+7 — specialise the `node["evaluate"](self, ctx)` indirect dispatch.** Two routes (NOT interchangeable; pick by pprof):
  - **Path 2 (preferred — lower risk, runtime-only):** cache the impl pointer on the Node. In the `make*` factories, alongside `node["evaluate"] = SomeDef`, set `node["evaluateImpl"]` to the promoted def's wrapper when the def is in `staticDefByName`. At tree-walker call sites (`:6767`, `:366`, `:368`, `:1186`) check `evaluateImpl` before the `MapValue.Get("evaluate")` + `Execute` hops. No codegen pattern-matching.
  - **Path 1 (codegen-level):** when the emitter sees `<expr>["evaluate"](<expr>,<ctx>)`, emit a tagged dispatch straight to `_impl_wrapper`. More fragile (pattern recognition in the `*ToGoDirect` emitters).
  - Cheap adjacent win regardless of path: the indirect path builds an `*ArrayValue`/`[]Value` then `impl_wrapper` immediately unpacks it positionally — collapse the double-wrap for `staticImpl` closures.
- [ ] **Close the 12 holdouts only if pprof says they matter** (they are parse-time AST factories, not selfhost-hot — likely skip). Closing needs nested-`FunctionDeclaration` support in `canDirectEmit`/`nodeToGoDirect`.
- [x] **Replaced the committed binary** (2026-05-29). Gate confirmed OPEN by the same-session pinned head-to-head (stage2 71.08s vs OLD committed 88.74s = 1.25×). Procedure executed: built true fixed point (committed→stage1→stage2, `cmp stage2 stage3` byte-identical = `fa1fe55…`), functional-checked `/tmp/ij-fresh` against sample+test goldens, `cp /tmp/ij-fresh interpreter_mac_arm64`, **tightened verify.sh check 5 from determinism to true fixed point** (`committed == self-transpile output`, `scripts/verify.sh:76-99`), re-ran `verify.sh` 5/5. **🟠 Only `interpreter_mac_arm64` was replaced; `interpreter_linux_amd64` is still the OLD frozen bridge** (cross-compile needs Docker via `compile-linux.sh`; out of scope for this Docker-less loop) — rebuild it on a linux/Docker host next. Recover the OLD mac bridge if ever needed: `git show 062e95c:interpreter_mac_arm64`.

### P3 — String interning + singletons (DEPRIORITISED — fold into P-VM, not standalone)

Per design §Phase 3. Singletons (`vNull/vTrue/vFalse/vEmpty/smallInt[256]/strPool`) + `vIntFast`; the VM's `OpNull/OpTrue/OpFalse` opcodes (spec §3.2) are the natural home for the singleton routing. **Lever is small standalone** (~1.1–1.3×, per-literal alloc only) — not worth a separate loop; land the singletons as part of P-VM.1's constant pool.

### P4 — Slot-indexed contexts (✅ SUBSUMED by P-VM)

The VM's frame-local slots (spec §3.3) *are* slot-indexed contexts — slot numbering happens inside `compileChunk` (per-chunk symbol table; the resolver's `resolvedSlot` field is dead scaffold, never assigned — verified 2026-06-10), with zero per-call map/`Context` alloc and no parent-chain walk. **Do not land P4 separately;** it is strictly weaker than and redundant with the VM frame design.

### P5 — Cleanup once 10× hit (or once a structural pivot supersedes the tree-walker)

- [ ] README perf section: append phase rows + the D1/D2/D3-reborn arc + the 10×-ceiling lesson.
- [x] **Doc drift:** `scripts/bench.sh` header un-staled (fixed 2026-06-11 P-VM.2 loop — was still describing the frozen ac2e6f3 bridge).
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

Research doc `docs/research/archive/2026-05-18-interpreter-perf-research.md` (archived; superseded by `docs/research/2026-06-11-perf-benchmark-bottlenecks-and-optimization-ledger.md`) audited HEAD `c42261c`; several findings are now resolved by P2.5/P2.6.

| Research § | Finding | Status |
|---|---|---|
| §2.2 | `Context.Get` chain-walks per `evalIdent` | ✅ P2.5 (rkLib fast path); rkParam/rkLocal deferred → P4 |
| §2.3 | ~5 heap allocs per `evalCall` | ✅ partial P2.5 (block+caller ctx) + N+6 alloc-reduction |
| §2.4 | `evalBlock` always allocs Context | ✅ P2.5 (`hasLocals` gate, `:5459`) |
| §3.2 | All resolver annotations dead | ✅ P2.5 (`resolvedKind` now read by `evalIdent`) — **research doc now stale here** |
| §3.10 | `FunctionCommand.Execute` wastes a Context alloc | ✅ P2.5 (`executeFunc(nil,…)`) |
| §2.8 | String literals emit per occurrence | ⬜ P3 |
| §3.1 | Six dead Node fields | 🔄 partially live post-P2.5 (`resolvedKind` live; `sIdx`→P3, `resolvedSlot` confirmed dead 2026-06-10 — VM numbers own slots, drop field at P5, `isStatic`/`pos` still dead) → P5 |
| §3.3 | `analyzeIsStatic` walks bodies | ✅ activated (D1-reborn `useDirectEmit` predicate) |
| §3.4/§3.6/§3.7 | `useNodeTree`/`ijCount*`/`opCodeFor("!")` dead | ⬜ P5 |
| §3.9 | Phase-3 singleton scaffolding present, not emitted | ⬜ P3 |
| §4.5 | Committed binary is one-way bridge; check 5 = determinism | 🔄 P-C (bridge replace) |
| §4.7 | `registerLibraryFunctions.func12` (`assert`) length-0 panic | ⬜ retest under stage2 |
| §4.11 | `bench_eval.s` dropped (>5min) | ⬜ re-enable after 10× |

---

## 6. Open questions / risks

- **🚫 DEAD-END — in-band null sentinel (do not retry).** Replacing `mapHasKey` by storing null bindings as a distinctive string sentinel (`"__IJ_NULL_SENTINEL_b7e3c1__"`) in `ctx["values"]` to make absent-vs-present-null an O(1) read **is fundamentally broken under self-hosting** and was reverted 2026-05-29. Empirically: in 2-layer (`interpreter.sh`) a program doing `let m={}; m["k"]=<sentinel>; m["k"]` reads back **null**, not the string (`type:null`, `is_null:true`). The outer interpreter layer's own `ctxGet`/value pipeline re-interprets any value equal to its sentinel as null, so the inner layer's sentinel is "re-sentinelised" and corrupted. **Any** in-band marker reachable through a name lookup hits this — confirmed with both the map-roundtrip and `let x=null` minimal repros. The only sentinel-free O(1) options are a native presence builtin (blocked by the frozen-committed-bridge bootstrap — checks 2/3 would see an undefined `hasKey`) or the call-ordering fix actually shipped (see P-C Run N+7-mapHasKey).
- **10× IS infeasible via tree-walking** (§0-B) — CONFIRMED 2026-05-29: 1.25× honest cumulative. Design spec projection corrected. P-B gate says pivot to a structural lever. **The structural lever (bytecode VM) is de-risked 2026-05-30: 7.96× measured (lower bound) — `experiments/bytecode-vm-prototype/` + `docs/specs/bytecode-vm-implementation.md`. 10× is reachable via P-VM.**
- **Drop-rule vs noise** (§0-A): RESOLVED — pinned min-of-3 collapses the band to 1.01×, so the 1.3× drop-rule is enforceable.
- **Committed binary** is **no longer a one-way bridge** — it IS the true fixed point of current source (since 2026-05-29; `70d51330…` after the P-VM.3 flip), reproducible from source (`compile-local.sh` fixed point). A fresh recompile now equals the committed binary (verify.sh check 5 enforces it). Recover the OLD frozen bridge only if forensics need it: `git show 062e95c:interpreter_mac_arm64`. **`interpreter_linux_amd64` is still the OLD frozen bridge** — rebuild on a linux/Docker host (and `mcp_linux_amd64` likewise — the mac MCP binary was rebuilt 2026-06-12, the linux one is still 2026-05-16).
- **Go toolchain pin:** check-5 byte-identity embeds the Go version — builds MUST use **go1.26.4** (the version in the committed binaries). The host lost its `go` install before this loop; reinstalled at `~/sdk/go1.26.4` (official tarball). A different Go version will fail check 5 with a byte-diff even on identical source.
- **MCP override pattern** (`let oldX=X; def X`) is the verify.sh check-4 invariant. Any `functionDeclarationToGo`/`collectStaticDefs` edit re-runs verify.sh in full. `counts==1` gate preserves it.
- **Resolver mis-classification:** every emitter switching on `resolvedKind` keeps a chain-walk fallback for unannotated (`rkGlobal=0`) nodes. A `vInvalid("variable not found")` regression ⇒ fall back to fallback, don't ship.
- **`hasLocals` shadowing:** inner-block `let` shadowing must keep per-block ctx. If `test.s` regresses, force `hasLocals:true` for blocks containing `If`/`While`.

## 7. Build & verification reminders

- `./src/compile-local.sh` (Docker-less). `compile-mac.sh`/`build.sh` silently swallow Docker failures and mask regressions.
- Two consecutive `compile-local.sh src/interpreter.s` must be byte-identical (verify.sh check 5).
- For phase-boundary perf decisions use **`bench.sh --fresh`** (once P-A lands) — committed-bridge numbers are the production gate only, they cannot see source work.
- Scripts live in `scripts/` (driver) + `src/` (compile). `echo |` for scripts that don't call `gets()`.
