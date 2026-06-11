# Implementation Plan — Self-Hosted Interpreter 10× Perf

**Goal:** `./scripts/bench.sh` self-hosted (`selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) ≤ 7s wall on macOS/arm64. Baseline `phase0 = 71.153s`. Need ≥10× cumulative.

> Single source of truth for status, blockers, next-run roadmap. Design recipe lives under `docs/specs/`. Research/current-state map: `docs/research/2026-06-11-perf-benchmark-bottlenecks-and-optimization-ledger.md` (supersedes the archived 2026-05-18 research docs).
> **Plan re-verified 2026-06-11 (plan-only loop, HEAD `237c7de`):** P-VM.1 state live-confirmed — `IJ_VM=1 IJ_VM_DEBUG=1` on the committed binary prints `program stmts: 338 escaped: 269 funcChunks: 0` (matches the shipped claim); `test.s` green. P-VM.2 bail inventory verified at exact source lines (see P-VM.2 sub-bullets). **Next implementation loop: P-VM.2.**
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
| **committed binary** (`interpreter_mac_arm64`, now `fa1fe55…`) | **71.08s** pinned min-of-3 | **NEW** (== stage2): 226 `ij_*_impl`, 214 direct-Go bodies + 12 `eval(body)` holdouts, `staticImpl` closure-hoist + `ctxGet` reorder | **REPLACED 2026-05-29 — IS the true fixed point now; `bench.sh` default finally measures current source** |
| OLD frozen bridge (`ac2e6f3`/`282e1126…`, no longer committed) | 88.74s pinned min-of-3 | OLD: 188 `ij_*_impl` direct-Go bodies, interface `Value`, 0 `nkStaticCall` | superseded; recover via `git show 062e95c:interpreter_mac_arm64` if ever needed |
| stage1 (any fresh build via the NEW committed bridge) | == stage2 (fixed point) | NEW emit | the NEW committed bridge already emits `staticImpl`, so stage1 == stage2 == stage3 now (no more parity-blind stage1) |

**Trajectory of stage2 selfhost** (fresh self-build, the number that actually reflects source work): Run N+2 `4m32s` → N+3 `4m1s` → N+5 `4m15s` → **N+6 `2m26.2s`** (closure-body hoist, 1.74×) → **N+7 `75.61s` pinned** (`ctxGet`/`mapHasKey` hot-path reorder, **2.84×** over the N+6 pinned baseline `214.42s`). Single biggest lever in the whole arc — `mapHasKey`'s `keys()` array-alloc + linear scan was both the hottest leaf (10.12% flat) AND a top GC driver (GC ~33% of wall); removing it from the common lookup path cut scan + allocation together. Bench: `--fresh --repeat 3`, `GOMAXPROCS=1`, band 75.61/75.63/76.68s (1.01×). **2026-05-29 head-to-head (less-loaded box, same session for both):** stage2 `71.08s` vs OLD committed bridge `88.74s` = **1.25×**; bridge then **replaced** (`fa1fe55…`). 1.25× is the honest cumulative for the whole arc since `ac2e6f3` — confirms the incremental ceiling is near-exhausted (§0-B).

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
 • P-VM.2 ⬜ NEXT (full node-kind coverage under the flag)
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
- [ ] **P-VM.2 — full node-kind coverage** (NEXT). Goal: drive interpreter.s's own escape count 269→~0 and compile func chunks for the holdout-style bodies, so P-VM.3 (default flip) is meaningful. **Verified bail inventory at HEAD `237c7de` (2026-06-11, exact lines):**
  - [ ] `compileExpr` default-bails on `nkArrayLit` / `nkMapLit` / `nkIndex` / `nkStaticCall` (`src/interpreter.s:5836-5837`) → add `vmOpArray`/`vmOpMap` (count operand, build from stack), `vmOpIndex`, and a static-call op that reuses the Node's baked `staticImpl` pointer (mirror `evalStaticCall` `:5599-5611` semantics incl. invalid-arg flow).
  - [ ] `compileStmt` has no `nkIndexAssign` case — falls to the expr default and bails (`:5963-5964`) → add `vmOpIndexStore` (mirror `evalIndexAssign` `:5362`).
  - [ ] Func-chunk bails to close: upvalue idents (`compileIdent` rkUpvalue `:5762`), nested `FuncDecl` (`compileFuncDecl` `!c.topLevel` `:5934`), nested-block `let`s (`compileVarDecl` `blockDepth>0` `:5843` — needs sub-scope slot numbering that preserves block-scoped shadowing), unannotated writes inside funcs (`compileAssign` non-topLevel default `:5871-5872`).
  - [ ] Upvalue representation decision (spec §8): flat captured-slot array vs boxed cells — inspect interpreter.s's actual closure usage first (it relies on `self`-passed map methods, not lexical capture; a narrow bail-keep may be cheaper than full `OpMakeClosure`).
  - [ ] Carry the P-VM.1 semantics invariants (below): poison-value propagation points, UNBOUND missing params (closure-path fallback on arity underflow), per-statement `vmOpStep` aborts, source-order const/name interning (check 5).
  - [ ] Gate: `scripts/vm_difftest.sh` green **on stage2** + `verify.sh` 5/5 with `IJ_VM=1`; confirm engagement via `IJ_VM_DEBUG=1` escape-count drop (not just output match — stage1 is parity-blind).
- [ ] **P-VM.3 — flip default to VM + re-establish the true fixed point** (committed→s1→s2, `cmp s2 s3`; mirror the P-C bridge-replace procedure). The delicate step — never flip before 5/5 under the flag.
- [ ] **P-VM.4 — mirror the VM into the IJ-side `evaluate` evaluator** (the selfhost-dominant `MapValue` walk); bench the real ≥8× selfhost win; then drop the dead tree-walker once `scripts/interpreter.sh`+`ast.sh`+resolver are migrated.
- [ ] **P-VM.5 (optional) — stack Lever 2** (NaN-box/tagged-pointer `Value`) only if ≤7s still unmet; `vmLean` shows ~2.4× more headroom.

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
- [ ] **Doc drift (cheap, any loop):** `scripts/bench.sh:9-11` header still says "the committed binary is frozen (ac2e6f3)" — stale since the 2026-05-29 bridge replace; default bench DOES measure current source now. Fix the comment.
- [ ] **Working-tree housekeeping (found 2026-06-11):** the `docs/research/2026-05-29-stage2-cpu*.{txt,pprof}` → `docs/research/archive/` moves are uncommitted (git shows D + ??); commit alongside the next change.
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
- **Committed binary** is **no longer a one-way bridge** — it IS the true fixed point (`fa1fe55…`) as of 2026-05-29, reproducible from source (`compile-local.sh` fixed point). A fresh recompile now equals the committed binary (verify.sh check 5 enforces it). Recover the OLD frozen bridge only if forensics need it: `git show 062e95c:interpreter_mac_arm64`. **`interpreter_linux_amd64` is still the OLD frozen bridge** — rebuild on a linux/Docker host.
- **MCP override pattern** (`let oldX=X; def X`) is the verify.sh check-4 invariant. Any `functionDeclarationToGo`/`collectStaticDefs` edit re-runs verify.sh in full. `counts==1` gate preserves it.
- **Resolver mis-classification:** every emitter switching on `resolvedKind` keeps a chain-walk fallback for unannotated (`rkGlobal=0`) nodes. A `vInvalid("variable not found")` regression ⇒ fall back to fallback, don't ship.
- **`hasLocals` shadowing:** inner-block `let` shadowing must keep per-block ctx. If `test.s` regresses, force `hasLocals:true` for blocks containing `If`/`While`.

## 7. Build & verification reminders

- `./src/compile-local.sh` (Docker-less). `compile-mac.sh`/`build.sh` silently swallow Docker failures and mask regressions.
- Two consecutive `compile-local.sh src/interpreter.s` must be byte-identical (verify.sh check 5).
- For phase-boundary perf decisions use **`bench.sh --fresh`** (once P-A lands) — committed-bridge numbers are the production gate only, they cannot see source work.
- Scripts live in `scripts/` (driver) + `src/` (compile). `echo |` for scripts that don't call `gets()`.
