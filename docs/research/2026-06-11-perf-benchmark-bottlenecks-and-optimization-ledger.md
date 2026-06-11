---
date: 2026-06-11T10:08:00+0800
researcher: Claude
git_commit: 121cc08e53f5b7e188a68294e5fe4b0728f6b820
branch: main
repository: kevinlin/interpreter-ij
topic: "IJ interpreter performance — how the benchmark measures, where the bottlenecks root from, and the full tried/verified/failed optimization ledger"
tags: [research, interpreter, performance, benchmark, transpiler, self-hosted, bytecode-vm, codegen]
status: complete
last_updated: 2026-06-11
last_updated_by: Claude
supersedes:
  - docs/research/archive/2026-05-18-interpreter-perf-research.md
  - docs/research/archive/2026-05-18-d1-reborn-emit-template.md
---

# Research: IJ Interpreter Performance — Benchmark Methodology, Bottleneck Roots, and the Optimization Ledger

**Date**: 2026-06-11T10:08+0800
**Git Commit**: `121cc08` (`perf/p-vm.1: Go-side bytecode VM behind IJ_VM=1 flag`)
**Branch**: `main`

> **This document is the source-of-truth perf research.** It supersedes
> `2026-05-18-interpreter-perf-research.md` and `2026-05-18-d1-reborn-emit-template.md`
> (both archived under `docs/research/archive/`). Those documents audited commit
> `c42261c`; most of their "dead infrastructure" findings have since been resolved by
> P2.5/P2.6/P-C work, and their line numbers no longer match the source. Everything
> still load-bearing from them is folded in here against HEAD `121cc08`
> (`src/interpreter.s` = 7,719 lines).

## Research Question

1. How is the performance benchmark measured in `scripts/bench.sh`?
2. Where do the performance bottlenecks root from?
3. What methods have been tried/verified — which worked, which failed, and why the
   failed paths failed?

---

## Summary

- **The benchmark** is wall-clock `time` of `selfhosted_interpreter.sh src/sample.s`
  (stdin=`hi`) — a **three-layer nested interpretation**: the native binary
  tree-walks `interpreter.s` (instance A), which tree-walks `interpreter.s` again
  (instance B), which runs the 7-line `sample.s`. `bench.sh` had two historical
  measurement defects (frozen-binary blindness and a 1.55× noise band) that
  invalidated ~10 loops of perf verdicts; both were fixed 2026-05-29 by `--fresh`
  (true fixed-point stage2 build) and `--repeat N` + `GOMAXPROCS=1` + min-of-N
  (noise band collapsed to 1.01×).
- **The bottleneck** is not any single function — it is the *structure*:
  per-node tree-walk dispatch cost × the millions of IJ operations instance B
  performs (parsing its own ~250 KB source + defining ~200 functions). pprof of
  the stage2 binary shows the cost concentrated in scope-chain variable resolution
  (`ctxGet` 44.7% cum, with `mapHasKey` formerly the hottest leaf at 10.1% flat —
  since fixed), function-call dispatch machinery (`FunctionCommand.Execute` →
  closure → `_impl_wrapper` → impl, ~5 hops with an `[]Value` built-then-unpacked
  per call), and ~33% of wall in GC from per-call heap allocation.
- **The ledger**: the incremental tree-walker path delivered a measured honest
  cumulative of **1.25×** (committed-old 88.74s vs stage2 71.08s, same-session
  pinned) — far below the 10× goal (≤7s). Two paths regressed and were
  reverted/abandoned with documented root causes (D4 arithmetic helpers; the
  in-band null sentinel). One path was the wrong shape (D2-reborn `nkStaticCall`).
  The single biggest win was a two-line lookup reorder (`ctxGet`, 2.84×). The
  project pivoted 2026-05-29/30 to a **bytecode VM** (P-VM), de-risked by a
  prototype measuring **7.96×** on dispatch alone, and P-VM.1 (Go-side VM behind
  `IJ_VM=1`) shipped 2026-06-11 at HEAD.

---

## 1. How the Benchmark Is Measured (`scripts/bench.sh`)

### 1.1 What is timed

`scripts/bench.sh` (123 lines) appends to `bench.log` and times three blocks:

| Block | Command | What it exercises | Typical time |
|---|---|---|---|
| **selfhost** (headline) | `echo hi \| selfhosted_interpreter.sh src/sample.s` | 3-layer nested interpretation (see §1.2) | 71–120 s |
| interpreted | `echo hi \| interpreter.sh src/sample.s` | 2-layer: native binary tree-walks interpreter.s which runs sample.s | ~0.5–1 s |
| native | `echo hi \| native_interpreter.sh src/sample.s` | 1-layer: native binary runs sample.s directly | ~0.01–0.06 s |

The headline metric is the selfhost block. `src/sample.s` is a 7-line greeting
loop (`puts` + `gets` + `while`); the workload is **not** sample.s itself — it is
instance B (interpreter.s) being interpreted by instance A.

A fourth block (`src/bench_eval.s` — `fib` + `bubbleSort`, eval-heavy) was
designed in the spec but is **intentionally not timed**: under Phase-2 codegen the
selfhosted run exceeded 5 minutes and drowned the primary signal
(`scripts/bench.sh:119-121`; commit `a93d814`). The file still exists at
`src/bench_eval.s` for future re-enablement after 10× is hit.

### 1.2 The three-layer stack

```
bench.sh
  └─ selfhosted_interpreter.sh sample.s        (scripts/selfhosted_interpreter.sh:5)
       └─ interpreter.sh interpreter.s          ← wraps the user file in //multiline … //<EOF>
            └─ native_interpreter.sh interpreter.s   (scripts/interpreter.sh:5)
                 └─ $BINARY  (committed interpreter_mac_arm64, or $IJ_BINARY override)
```

Each wrapper prepends `//multiline`, the script, then `//<EOF>` + remaining stdin
(the `gets()` input). So the native binary tree-walks **interpreter.s (A)**, whose
stdin is **interpreter.s (B)** + sample.s + `hi`. Wall time ≈
*(native per-node eval cost) × (IJ operations B performs)*, where B's operations
are dominated by parsing its own ~250 KB source and defining ~200 functions before
sample.s even starts.

### 1.3 Flags and statistics (P-A harness, shipped 2026-05-29)

- **`--fresh`** (`scripts/bench.sh:60-67`): builds the **true fixed point** of the
  current source and benches that instead of the committed binary. Two stages are
  load-bearing: `compile-local.sh` with the committed bridge → stage1, then
  `IJ_BINARY=stage1 compile-local.sh` → stage2. Benching stage1 would be
  **parity-blind**: stage1 carries the new emitters only as program *data* but
  runs the bridge's old runtime prelude, so runtime-feature work (e.g. the
  `staticImpl` closure hoist, `IJ_VM`) is invisible on stage1
  (`scripts/bench.sh:49-54`, AGENTS.md "STAGE GOTCHA").
- **`--repeat N`** (`scripts/bench.sh:99-107`): runs the selfhost block N times
  under `GOMAXPROCS=1`, reports min/median/max of `real` and `user`; **headline =
  min real** (noise is one-sided — other processes only slow you down).
- **`GOMAXPROCS=1`** (`scripts/bench.sh:69-77`): GC background + sysmon threads
  are ~33% of stage2 wall and the dominant variance source; pinning makes runs
  comparable.
- **`IJ_BINARY`** env var: honoured by `scripts/native_interpreter.sh:31` (runtime
  binary for the whole nested stack) and `src/compile-local.sh:31` (the transpile
  *bridge*), so a fixed point can be built and benched without ever touching the
  committed binary.

Decision protocol (AGENTS.md): default no-flag run = quick smoke only;
**`--repeat 3` for any perf decision**; `--fresh --repeat 3` for source work. The
pinned min-of-3 noise band measured 1.01× on both binaries, making the historical
**1.3× drop-rule** (revert any phase that doesn't beat its predecessor by ≥1.3×)
enforceable as written.

### 1.4 The two measurement defects that invalidated early verdicts

These are the most important historical facts about this benchmark
(`docs/specs/bench-methodology.md`):

1. **Frozen-binary blindness (the "gating deadlock").** Until 2026-05-29 the
   committed binary was a one-way bridge frozen at `ac2e6f3`; `bench.sh` (no
   flags) measured *it*, not source changes. Every source-level win from P1
   through D1-reborn Run N+6 (~10 loops) was invisible to the bench. Broken by
   the `IJ_BINARY` override + `--fresh` + replacing the committed bridge with the
   true fixed-point stage2 (`fa1fe55…`, since replaced again at P-VM.1 with
   `255e274e…`). `verify.sh` check 5 was simultaneously tightened from
   determinism-only to **true fixed point** (committed binary must byte-equal the
   self-transpile output, `scripts/verify.sh:76-103`), so the bench can no longer
   silently de-sync from source.
2. **Noise above the signal.** Single-run wall time on a loaded laptop spanned
   70.45–109.18 s (1.55×) for the *same binary* — wider than the 1.3× drop-rule,
   so "within noise" verdicts carried no information. Fixed by §1.3's pinned
   min-of-N.

**Corollary that still applies:** cross-session comparisons are invalid. The
`phase-vm1` bench (120.12 s, 2026-06-11) looks like a 1.6× regression vs N+7's
75.61 s but same-session controls attribute it to box-state drift plus a
legitimate +5.7% source-parse cost (the +553-line `goVMPrefix` text that layer A
must parse in B); the dormant VM itself costs ~0 (IMPLEMENTATION_PLAN.md P-VM.1
bench note). Only same-session head-to-heads are trustworthy.

### 1.5 Relationship to verify.sh

`scripts/verify.sh` is correctness, not perf: checks 1–4 (interpreted test.s,
selfhosted test.s, selfhosted sample.s, native MCP) diff against goldens in
`/tmp/ij-golden`; check 5 enforces determinism **and** the true fixed point.
`scripts/vm_difftest.sh` adds the P-VM differential harness (`IJ_VM=1` output must
equal default at all nesting layers, plus an engagement check via `IJ_VM_DEBUG=1`
so a silently-dead gate can't pass vacuously).

---

## 2. Where the Bottlenecks Root From

### 2.1 The structural frame

The selfhost bench multiplies two factors:

- **Per-node cost** of the native (Go) tree-walker, paid on every AST node visit.
- **Operation count**: instance B re-lexes/re-parses ~250 KB of IJ source and
  defines ~200 functions *as interpreted IJ data structures*, every run.

All shipped optimizations attack the first factor (per-node cost / allocation
rate). Nothing shipped attacks the operation count or removes a dispatch layer —
which is why the measured ceiling of the incremental path is low (§3.4) and the
project pivoted to a VM.

### 2.2 Layer 1 — the IJ-side MapValue tree-walker (the dominant cost under selfhost)

The deepest interpretation layer is interpreter.s's own `evaluate` machinery, and
under selfhost it runs *as interpreted code* (instance B interpreted by A). Every
construct costs multiples of what native code would:

- **Callable-entry dispatch.** Every AST node is a `MapValue`; evaluation is
  `node["evaluate"](node, context)` — a string-keyed map lookup plus an indirect
  call, at every visit (`src/interpreter.s:33,366,565,758,865,1054,1186`).
- **Scope-chain lookup — `ctxGet`** (`src/interpreter.s:3934-3971`). Contexts are
  MapValues chained via `ctx["parent"]`. A lookup probes `values[name]`, then
  `functions[name]`, then (only on a genuine miss or explicit-null binding) runs
  `mapHasKey` — an O(n) `keys()`-allocating scan (`src/interpreter.s:3892-3904`)
  — then recurses to the parent. Before the 2026-05-29 reorder, the common
  builtin/global-def lookup hit `mapHasKey(values_global)` (hundreds-deep map,
  alloc + linear scan) on **every** call — making `ij_mapHasKey_impl` the single
  hottest leaf in the profile (§2.4).
- **Per-call context allocation.** Each IJ function call allocates a fresh child
  context (`ctxExtend`, `src/interpreter.s:4002-4017`) — three maps plus five
  method-pointer entries — then binds params one by one
  (`evaluateFunctionDeclaration`, `src/interpreter.s:1164-1201`).
- **Return-value unwrapping.** Every statement result is checked by
  `isReturnValue` (`src/interpreter.s:1210-1218`), an isMap + magic-key probe.

### 2.3 Layer 2 — the emitted Go runtime (the native walker that runs layers A and B)

The Go prelude is emitted as strings by `goLibPrefix()`
(`src/interpreter.s:4483-5648`). Hot-path shapes at HEAD:

- **`eval(n *Node, ctx *Context) (Value, bool)`** (`src/interpreter.s:5351-5378`):
  a kind-switch over 21 node kinds. The `(Value, bool)` tuple is the in-band
  return sentinel — every recursive caller pays an `if returned` branch per child
  visit. (Chosen over a `tReturn` magic-tag during P2; never revisited.)
- **88-byte `Value` passed by value everywhere.** `Value{tag,b,i,d,s,arr,m,cmd,inv}`
  (`src/interpreter.s:~4830`); every method (`Add`, `Equals`, `Get`, …) takes and
  returns it by value, so each node visit copies ~96 bytes (Value+bool). This was
  P1's deliberate trade (kill interface boxing, accept copy cost); measurement
  says the trade nets ~1.0–1.3× at best.
- **Identifier resolution.** `evalIdent` (`src/interpreter.s:5379-5389`) fast-paths
  only `rkLib` (`rootCtx.GetLocal`); everything else does `ctx.Get(name)` — a
  parent-chain walk with a Go map probe per level. rkParam/rkLocal fast paths are
  deliberately NOT wired: per-block child contexts mean `GetLocal` would miss
  function-scope bindings read from nested blocks (comment at
  `src/interpreter.s:5380-5386`).
- **Call machinery — the remaining dispatch gap.** An indirect IJ-level call
  compiles to: `evalCall` (`:5582`, allocates an exact-sized `*ArrayValue`) →
  `Value.cmd.Execute` → `FunctionCommand` closure → for promoted defs
  `ij_<name>_impl_wrapper` (unpacks `[]Value` → positional args) → `ij_<name>_impl`
  (direct Go body). Five hops and a built-then-unpacked argument array per
  visit. For non-promoted defs, the closure allocates a `*Context` + sized
  params map per call and tree-walks the body via `eval(bodyN, local)`
  (`src/interpreter.s:5566-5578`).
- **Mitigations already in place** (all verified live at HEAD):
  - `staticImpl` closure hoist (Run N+6): promoted top-level defs dispatch the
    closure body straight into the direct-Go wrapper (`src/interpreter.s:5549-5556`).
  - 214/226 defs direct-Go-emitted; 12 holdouts (AST-factory functions with
    nested `def`s) still `eval(body)` — parse-time only, not hot
    (`collectStaticDefs` `src/interpreter.s:6223-6306`, `canDirectEmit` `:6324`).
  - `nkStaticCall` direct-by-name dispatch (`evalStaticCall`, `:5599-5611`).
  - `hasLocals` gate: `evalBlock` skips the per-block `*Context` when the block
    declares nothing (`src/interpreter.s:5463-5483`).
  - `rkGlobalLet` dual-write keeps package-scope Go vars in sync with ctx writes
    (`src/interpreter.s:5439-5447`).

### 2.4 The empirical ranking (pprof, stage2, 2026-05-29)

`docs/research/2026-05-29-stage2-cpu-top.txt` (126.71 s run, 110.35 s samples):

| Symbol | flat | cum | Meaning |
|---|---|---|---|
| `FunctionCommand.Execute` / `Value.Execute` / `evalFuncDecl.func1` | ~3% | **~84%** | everything funnels through call dispatch |
| `eval` | 2.10% | 74% | per-node switch dispatch |
| `ij_ctxGet_impl` (+wrapper) | 2.64% | **44.7%** | IJ-side scope-chain resolution |
| `ij_mapHasKey_impl` | **10.12% (hottest leaf)** | 33.7% | the `keys()`-alloc linear scan — **fixed by Run N+7** |
| GC (kevent + gcBgMark, off-table) | — | **~33% of wall** | per-call allocation pressure |

Reading: **scope-chain variable resolution, not closure dispatch, was the
dominant leaf cost** — the surprise that redirected Run N+7 from dispatch
specialisation to the `ctxGet` reorder. Post-reorder, the remaining cost is split
between the dispatch hop chain (§2.3), the per-node eval switch + sentinel
branch + Value copy, and GC.

### 2.5 What is structurally irreducible in a tree-walker

Per the Amdahl analysis in `docs/specs/10x-feasibility-and-structural-levers.md`
(confirmed by the 1.25× measured cumulative): allocation-rate levers (interning,
slot contexts) do not cut **operation count** or **per-node dispatch cost**. The
per-node `eval()` call + `(Value,bool)` sentinel + 88-byte copy + per-call frame
allocations cap the incremental path at ~2–4× optimistic over phase0 — hence the
bytecode-VM pivot (flat dispatch loop, slot frames, reused value stack: measured
7.96× on dispatch alone with zero per-call allocs,
`experiments/bytecode-vm-prototype/`).

---

## 3. The Tried / Verified / Failed Ledger

Chronological. ✅ = shipped & live at HEAD; 🟡 = shipped but superseded/neutral;
❌ = failed/reverted/dead-end.

### 3.1 Pre-history (README "Self-Hosted Performance", pre-2026-05-16; baseline 154 s)

| Method | Result | Status |
|---|---|---|
| **C1–C7 static variable resolution** — resolver annotates identifiers; emitter emits direct Go var reads/writes instead of `ctx.Get/Update` | 154→65 s (2.36×), biggest single win of the era | ✅ then lost in P1 cleanup; re-landed as P2.5/D1-reborn |
| **D1 context elimination** — `resolvedIsStatic` bodies skip per-call `NewContext` | 65→55 s | ✅ then lost; re-landed |
| **D2 fixed-arity direct calls** — `ij_<name>_impl(ctx, a, b)` + direct call sites; `lastDefIndex` pre-pass protects the override idiom | 55→52 s | ✅ then lost; re-landed |
| **D3 raw-bool condition helpers** — `EqualsBool/LessThanBool/…` in `if`/`while` slots avoid boxing a `BoolValue` | ~53 s, kept | ✅ then lost; **not** re-landed (current `evalIf/evalWhile` use `.IsTruthy()` on a Value) |
| **D4 arithmetic helpers** — same trick for `Add/Sub/Mul/Mod` | **regressed ~10%** | ❌ **REVERTED.** Why: the helper added a call frame the Go mid-stack inliner didn't collapse; unlike D3 there was no boxing to save, so the indirection was pure cost. Lesson: "replace `a.Op(b)` with `OpHelper(a,b)`" only pays when it skips a return-value boxing. |

### 3.2 The 10×-design era (P1/P2, 2026-05-16..17; phase0 = 71.153 s)

| Method | Result | Status |
|---|---|---|
| **P1 tagged-union `Value`** (88-byte struct, tag-switch dispatch, no interface boxing) | shipped semantically; bench-neutral to slightly negative | 🟡 The by-value copy of 88 bytes largely offsets the boxing it removed (estimated ~1.0–1.3×). |
| **P1 cleanup (`fb2b299`/`b040672`)** | **accidentally deleted the C/D fast paths** (D1/D2/D3 emit) along with the dual runtime | ❌ Root cause of the entire regression saga: phase2 measured 0.83× vs phase0. The committed binary still carried the old fast emit, masking the loss (gating deadlock, §1.4). |
| **The "49 s outlier"** (`run-baseline` 2026-05-17) | looked like a win | ❌ Irreproducible artifact of transitional dual-runtime commit `c5da0ac` whose source cannot self-build. Never a valid floor. |
| **P2 typed AST `Node` + `eval` switch** | shipped structurally; 1m25 s (0.83× — a regression) | 🟡 The struct AST landed but every resolver annotation was computed and dropped; `evalIdent` stayed `ctx.Get(name)`. The semantic half (annotation projection) only landed later as P2.5. |
| **`(Value, bool)` return sentinel** (over `tReturn` magic tag) | implemented choice | 🟡 one extra branch per recursive eval call; never revisited; the VM's `OpReturn` (stack unwind) is the eventual replacement. |
| **`refreshToGoPointers` iterative re-bind pass** | added in `ac2e6f3`, excised in `c42261c` | ❌ Dead complexity; removal demonstrated the stage2 emit fixed point. |
| **stage1→stage2 missing `func main()`** | `evalAssign` create-vs-update closure-scope bug: a function-body write to an undeclared-on-chain name shadowed instead of updating the global (`transpileGo` flag never visible at top level) | ❌ bug, fixed during P2 remediation (`fdf23ec` era + `evalAssign` resolvedKind dispatch). |

### 3.3 Resolver re-activation and D-reborn (P2.5/P2.6, 2026-05-17..28)

| Method | Result | Status |
|---|---|---|
| **P2.5 resolver wiring** — project `resolvedKind` onto Node; `evalIdent` rkLib fast path; `evalAssign`/`evalVarDecl` short-circuits; `evalBlock` `hasLocals` gate; `FunctionCommand.Execute` drops a Context alloc | correct, but **invisible to bench** at the time (frozen bridge) | ✅ live at HEAD. rkParam/rkLocal fast path deliberately unlifted (per-block ctx shadowing — `src/interpreter.s:5380-5386`). |
| **P2.6 D2-reborn** — `nkStaticCall` + `staticImpl` func pointer for direct-by-name calls | no measurable win | 🟡 **Wrong-shape fix**: it collapses *direct named calls*, but the dominant path is the *indirect closure* dispatch (`node["evaluate"]`-driven). Kept (harmless, occasionally hit). |
| **P2.6 D1-reborn Runs N..N+5** — re-emit promoted-static-def bodies as direct Go statements (`nodeToGoDirect`); positional-arg convention with arity-fallback wrapper | stage2 7m25s → 4m1s..4m15s | ✅ Necessary recovery of the lost OLD-bridge emit shape, but note stage2 was still *slower* than the committed bridge until N+6. The naive new emit had wrapped bodies as `eval(ij_<n>_body, local)` tree-walks — the root cause of stage2's 4-minute era. |
| **Run N+6 closure-body hoist** — FuncDecl Node carries `staticImpl`; `evalFuncDecl` dispatches the closure body into the direct-Go wrapper | stage2 4m15s → **2m26s (1.74×)** | ✅ `src/interpreter.s:5549-5556`. |
| **Run N+7 `ctxGet`/`mapHasKey` reorder** — probe `functions[name]` before the values present-null scan; drop `mapHasKey(functions)` entirely | stage2 214.42s → **75.61s pinned (2.84×)** — the single biggest lever in the whole arc | ✅ `src/interpreter.s:3934-3971`. Documented, accepted behaviour change: an explicit null binding shadowing a same-scope function name now resolves to the function (pathological; no test or MCP impact). |
| **In-band null sentinel** — store null bindings as a magic string so absent-vs-present-null is O(1), eliminating `mapHasKey` | diverged under self-hosting | ❌ **DEAD-END, do not retry** (IMPLEMENTATION_PLAN.md §6). Why: under 2-layer interpretation the *outer* interpreter's own `ctxGet`/value pipeline re-interprets any value equal to its sentinel as null — the inner layer's sentinel gets "re-sentinelised" and corrupted (`let m={}; m["k"]=<sentinel>; m["k"]` reads back null). *Any* in-band marker reachable through a name lookup hits this. A native presence builtin was also blocked: the frozen bridge's runtime wouldn't know it (bootstrap hazard). The call-ordering fix (N+7) was the only sentinel-free O(1) option. |

### 3.4 Measurement repair and the feasibility gate (P-A/P-B/P-C, 2026-05-29)

| Method | Result | Status |
|---|---|---|
| **P-A bench harness** — `IJ_BINARY` overrides, `--fresh` two-stage fixed-point build, `--repeat` min-of-N, `GOMAXPROCS=1` | noise band 1.55× → **1.01×**; drop-rule enforceable; deadlock broken | ✅ §1.3–1.4. The spec's own first draft (single-stage `--fresh`) was caught and corrected — it would have benched the parity-blind stage1. |
| **P-C bridge replace** — committed binary replaced with true fixed-point stage2; verify.sh check 5 tightened to fixed-point | default bench finally measures current source | ✅ (`interpreter_linux_amd64` is still the OLD frozen bridge — needs a Docker/linux host rebuild.) |
| **P-B 10× feasibility gate** — first honest same-session pinned head-to-head | **committed-old 88.74s vs stage2 71.08s = 1.25× cumulative** for the entire source arc since `ac2e6f3` | ✅ measured. 1.25× ≪ the 3× pivot threshold ⇒ **the incremental tree-walker path cannot reach ≤7s**. The design spec's "~12–87×, realistic 10–15×" multiplicative projection was retracted: levers were not independent (the bridge was already direct-Go-bodies, so D1-reborn only bought back parity) and Amdahl caps allocation-rate levers while dispatch + GC remain. |
| **P3 string interning + singletons** | never landed standalone | 🟡 deprioritised (~1.1–1.3× ceiling — saves per-literal allocs only); folded into the VM's constant pool. |
| **P4 slot-indexed contexts** | never landed | 🟡 **subsumed by P-VM**: VM frame slots *are* slot-indexed contexts, with zero per-call alloc. Note `resolvedSlot` on Node is dead scaffold — the resolver assigns no slots (verified 2026-06-10); the VM's `compileChunk` numbers its own slots. |

### 3.5 The structural pivot (P-VM, 2026-05-30..2026-06-11)

| Method | Result | Status |
|---|---|---|
| **P-VM.0 de-risk prototype** (`experiments/bytecode-vm-prototype/`) — faithful clone of the emitted runtime vs slot-based bytecode VM, same 88-byte Value | fib(32): treeWalk 2.588s, **vm 0.325s (7.96×)**, vmLean 0.135s (19.19×); allocs/call 35.2M → ~40 (one-time) | ✅ measured GO decision; models the *lighter* Go-side walk, so the selfhost-dominant IJ-side gain is a lower bound ≥8×. |
| **P-VM.1 Go-side VM behind `IJ_VM=1`** — `goVMPrefix()` (`src/interpreter.s:5671-6221`, ~26 opcodes, `vmCompileProgram`/`vmCompileFunc`/`vmExec`/`vmCallChunk`); `main()` env-gate (`:7185-7189`); per-statement compile with `vmOpEvalNode` escape rollback; slot-indexed function frames | shipped 2026-06-11 (HEAD); differential-tested at all 3 nesting layers; fixed point re-established; verify 5/5 | ✅ Default path untouched. On interpreter.s itself: 338 top-level stmts, 69 VM-compiled, 269 escaped, 0 func chunks (all defs are promoted/holdouts — expected; chunks proven via `tests/vm/vmtest{1,2,3}.s`). |
| Load-bearing semantics found during P-VM.1 | (a) invalid values are **poison values, not exceptions** — they flow through infix/call/assignment and only per-statement checks abort (first VM draft treated them as frame-aborts → SIGSEGV); (b) missing params are **UNBOUND, not vNull** — reads chain-walk to defCtx at read time, so `vmCallChunk` falls back to the closure path on arity underflow; (c) **stage1 is parity-blind for runtime features** — always differential-test on stage2 and confirm engagement with `IJ_VM_DEBUG=1` | carried into P-VM.2/4 (IMPLEMENTATION_PLAN.md P-VM.1 notes) |
| `phase-vm1` bench 120.12s | NOT a regression: same-session controls show new-binary parity (dormant VM ≈ 0 cost), +5.7% honest source-parse cost from the +553-line prelude, remainder = cross-session box drift | 🟡 §1.4 corollary in action. |

**Next:** P-VM.2 (full node-kind coverage; drive the 269 escapes → ~0), P-VM.3
(flip default + re-fix the fixed point), P-VM.4 (mirror the VM into the IJ-side
evaluator — the selfhost-dominant layer, where the real ≥8× lives), P-VM.5
(optional lean Value).

### 3.6 Why the failed paths failed — the pattern

1. **Measurement blindness** (frozen bridge + noise) let regressions ship and wins
   go unnoticed for ~10 loops. Fix measurement before optimizing.
2. **Indirection is not free** (D4): a helper call only pays if it removes an
   allocation/boxing; the Go inliner won't save you.
3. **Self-hosting poisons in-band markers** (null sentinel): any sentinel value
   reachable through a name lookup gets re-interpreted by the outer layer.
4. **Optimizing the wrong dispatch shape** (D2-reborn): profile first — the
   dominant call path was the indirect closure, not direct named calls.
5. **Multiplicative lever projections fail under Amdahl** (the 12–87× claim):
   levers attacking the same allocation budget don't multiply, and per-node
   dispatch cost is untouched by allocation levers.
6. **Two-stage bootstrap semantics hide work** (stage1 parity-blindness): both
   bench (`--fresh`) and runtime-feature testing must use stage2.

---

## 4. Code References (HEAD `121cc08`)

**Benchmark & harness**
- `scripts/bench.sh:60-67` — `--fresh` two-stage fixed-point build
- `scripts/bench.sh:69-77` — pinned `GOMAXPROCS=1` selfhost runner
- `scripts/bench.sh:96-123` — log blocks; bench_eval.s exclusion note at `:119-121`
- `scripts/selfhosted_interpreter.sh:5`, `scripts/interpreter.sh:5` — layer nesting
- `scripts/native_interpreter.sh:31` — `IJ_BINARY` runtime override
- `src/compile-local.sh:31`, `:52`, `:65-73` — bridge override; `//<GO2>` transpile; `fix_app_go.py`; `go build`
- `scripts/verify.sh:76-103` — check 5 (determinism + true fixed point)
- `scripts/vm_difftest.sh` — `IJ_VM=1` differential harness + engagement check
- `src/sample.s` — the 7-line benchmark target; `src/bench_eval.s` — dormant secondary

**IJ-side tree-walker (selfhost-dominant layer)**
- `src/interpreter.s:3892-3904` — `mapHasKey` (the formerly-hottest leaf)
- `src/interpreter.s:3934-3971` — `ctxGet` with the N+7 reorder + rationale comment
- `src/interpreter.s:4002-4017` — `ctxExtend` per-call context alloc
- `src/interpreter.s:1164-1201` — `evaluateFunctionDeclaration` closure + param binding
- `src/interpreter.s:1210-1218` — `isReturnValue` (isMap guard, P2 regression fix)
- `src/interpreter.s:33,366,565,758,865,1054,1186` — `node["evaluate"]` dispatch sites

**Emitted Go runtime (`goLibPrefix`)**
- `src/interpreter.s:4483` — `goLibPrefix()` start
- `src/interpreter.s:5351-5378` — `eval` kind-switch; `(Value,bool)` sentinel
- `src/interpreter.s:5379-5389` — `evalIdent` (rkLib fast path only; comment explains why)
- `src/interpreter.s:5424-5451` — `evalAssign` resolvedKind dispatch + rkGlobalLet dual-write
- `src/interpreter.s:5463-5483` — `evalBlock` hasLocals gate
- `src/interpreter.s:5532-5581` — `evalFuncDecl`: staticImpl hoist branch + closure path
- `src/interpreter.s:5582-5598` — `evalCall` (exact-sized ArrayValue)
- `src/interpreter.s:5599-5611` — `evalStaticCall` (D2-reborn)

**Transpiler / promotion machinery**
- `src/interpreter.s:6223-6306` — `collectStaticDefs` (3 passes; `counts==1` override-idiom gate)
- `src/interpreter.s:6324-…` — `canDirectEmit` (the 12 holdouts: nested-def AST factories)
- `src/interpreter.s:6908` — `nodeToGoDirect` dispatcher; `:6671` `CallExpression_toGoDirect` (arity fallback)
- `src/interpreter.s:1756-1801` — `functionDeclarationToGo` (`staticImpl:` emission at `:1800`)
- `src/interpreter.s:2008-2021` — `identifierToGo` (resolvedKind projection)
- `src/interpreter.s:6934` — `programToGoPhase2`; `main()` emit at `:7107-7190` (IJ_CPUPROFILE, lib-globals cache, IJ_VM gate)
- `src/interpreter.s:7522` — `readSources` (stdin sentinel protocol)

**Bytecode VM (P-VM.1)**
- `src/interpreter.s:5650-5670` — design comment (escapes, bail rules, invalid/arity semantics)
- `src/interpreter.s:5671-6221` — `goVMPrefix()`: opcodes, `VMChunk`, `vmCompileProgram` (`:5985`), `vmExec` (`:6008`), `vmRunProgram` (`:6187`)
- `experiments/bytecode-vm-prototype/` — de-risk prototype + README with measurements
- `tests/vm/vmtest{1,2,3}.s` — VM function-chunk test programs

**Evidence artifacts**
- `bench.log` — full timing history (phase0 71.153s … phase-vm1 120.12s)
- `docs/research/2026-05-29-stage2-cpu-top.txt` / `…-stage2-cpu.pprof` — the load-bearing profile

---

## 5. Architecture Notes That Keep Biting

- **Stdin sentinel protocol**: `//multiline` leading marker; trailing `//<EOF>`
  (evaluate), `//<AST>`, `//<GO>`, `//<GO2>` (emit bash script that writes
  `app.go`). All wrappers inject these (`readSources`, `src/interpreter.s:7522`).
- **Build pipeline**: source + markers → bridge binary → `gen.sh` → `app.go` →
  `scripts/fix_app_go.py` (still load-bearing post-processor) → `go build`.
- **Fixed-point discipline**: any emit-ordering nondeterminism (map iteration)
  breaks verify check 5; `staticDefNames` and the VM constant pool intern in
  source order.
- **Override idiom** `let oldX = X; def X(...) { oldX(...) }` is the MCP
  load-bearing pattern; the `counts==1` promotion gate exists to protect it
  (verify check 4).
- **Arity gotcha**: IJ tolerates caller-arity ≠ callee-arity. Missing params are
  **UNBOUND** (chain-walk to defCtx at read time, usually vInvalid) on the
  closure path; the positional `_impl` wrapper path vNull-pads. Two different
  semantics — `CallExpression_toGoDirect` falls back to the wrapper on mismatch,
  and `vmCallChunk` falls back to the closure path on underflow.
- **Invalid values are poison, not exceptions** — they propagate as expression
  results; only per-statement checks abort. Any new evaluator must replicate
  this exactly (P-VM.1 learned it via SIGSEGV).

---

## 6. Historical Context (superseded / related documents)

- `docs/research/archive/2026-05-18-interpreter-perf-research.md` — the c42261c
  audit (88-byte Value anatomy, dead-annotation forensics, plan-vs-code diff).
  Superseded by this doc; its §2/§3 findings are resolved or restated in §2/§3
  here. Line numbers there are stale.
- `docs/research/archive/2026-05-18-d1-reborn-emit-template.md` — the OLD-bridge
  emit-shape reference captured before the bridge was replaced. Its purpose
  (porting per-statement direct emitters) completed with D1-reborn Runs N..N+6;
  the patterns now live in the `*ToGoDirect` emitters in source.
- `docs/specs/2026-05-16-self-hosted-perf-10x-design.md` — original 4-phase
  design; projection retracted 2026-05-29 (see its header).
- `docs/specs/bench-methodology.md` — the P-A harness spec (defect analysis).
- `docs/specs/10x-feasibility-and-structural-levers.md` — the P-B gate + lever
  analysis.
- `docs/specs/bytecode-vm-implementation.md` — the P-VM implementation spec
  (IR, opcodes, calling convention, landing phases).
- `docs/plans/2026-05-16-self-hosted-perf-10x.md` — task-level plan of the
  original phases (historical).
- `IMPLEMENTATION_PLAN.md` — living status (P-VM.1 shipped; P-VM.2 next).
- `README.md` §Self-Hosted Performance — the pre-2026-05 C/D era ledger.

## Open Questions

1. **The real selfhost VM win is unmeasured.** P-VM.1 gates the Go-side walker
   only; the selfhost-dominant IJ-side `MapValue` walk (instance B) is untouched
   until P-VM.4. The ≥8× claim for the full lever remains a (well-grounded)
   extrapolation from the prototype + pprof shares.
2. **`interpreter_linux_amd64` is still the OLD frozen bridge** — verify check 5
   on a Linux host would fail the fixed-point comparison until it is rebuilt.
3. **The 12 direct-emit holdouts** (nested-def AST factories) remain on
   `eval(body)`. pprof says they are parse-time, not hot; closing them needs
   nested-`FunctionDeclaration` support in `canDirectEmit`/`nodeToGoDirect` and
   is probably moot once P-VM.4 replaces the walker.
4. **D3 raw-bool condition helpers were never re-landed** post-P1-cleanup
   (`evalIf`/`evalWhile` box a Value then call `.IsTruthy()`). Likely subsumed by
   the VM's `vmOpJumpIfFalse`, but no measurement isolates the residual cost.
5. **The `assert` lib-fn length-0 panic** (P2-era finding) was partially
   mitigated by the `NewArrayValue` nil-guard in `fix_app_go.py`; never re-tested
   under the current stage2.
