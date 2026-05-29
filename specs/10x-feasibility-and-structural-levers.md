# Spec — 10× Feasibility Reassessment + Structural Levers

Date: 2026-05-29
Status: Decision gate (authored during a plan-only loop; drives IMPLEMENTATION_PLAN.md P-B).

## Purpose

The original design (`docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md`) projected the five planned phases multiplying to "~12–87×, realistic 10–15×". After P1/P2/P2.5/P2.6 shipped and ~10 loops of D1-reborn, the **measured trajectory contradicts that projection**. This spec records the reassessment and the structural options, so the team makes an evidence-based decision instead of grinding an approach with a ceiling below the goal.

## The goal restated

`selfhosted_interpreter.sh src/sample.s` (stdin=`hi`), `phase0 = 71.153s`. Target **≤7s = 10×**.

## Why the planned phases plausibly cannot reach 10×

### What the benchmark actually stresses

Three nested IJ-interpretation layers: `native (compiled interpreter.s)` → `interpreter.s A` → `interpreter.s B` → `sample.s`. Wall time ≈ *(native per-node `eval()` cost) × (number of IJ operations B performs)*, where B = interpreter.s parsing its own ~250KB source, defining ~200 functions, then running the tiny `sample.s`. The cost is **per-node tree-walk dispatch**, repeated for the millions of node visits B performs.

### The committed bridge is already the "fast" shape

The frozen committed binary (`ac2e6f3`) emits each interpreter.s function as a **direct Go body** and runs at ~71–104s. Fully landing D1-reborn re-creates that emit shape in the new source — i.e. its ceiling against the bridge is **≈ parity (1×)**, plus whatever tagged-union `Value` and reduced allocations net out (small, possibly negative given the 88-byte by-value copy).

### Amdahl on the remaining levers

pprof (stage2, fib25): `eval`+`Execute`+`evalBlock`+`evalCall` ≈ 34% cum, `evalFuncDecl.func1` 33.6%, GC ≈ 33%. The planned phases attack **allocation rate** (P3 interning, P4 slot-contexts), not **operation count** or **per-node dispatch cost**:

| Lever | Plausible gain | Bounded because |
|---|---|---|
| tagged-union `Value` (shipped) | ~1.0–1.3× | 88B copy may offset the boxing it removed |
| D1-reborn complete + Run N+7 dispatch specialisation | →parity, then ~1.1–1.3× | matches bridge emit; nets tagged-union + fewer allocs + cheaper dispatch |
| P3 interning + singletons | ~1.1–1.3× | removes a string-header alloc per literal; eval()/dispatch untouched |
| P4 slot-indexed contexts | ~1.3–1.6× | removes `ctx.Get` chain walks; per-node `eval()` + Value copy remain |
| **Stacked, optimistic** | **~2–4× over phase0 (≈18–36s)** | tree-walk dispatch cost + ~33% GC are structural |

**Conclusion:** the incremental tree-walker path realistically reaches ~2–4×, i.e. ~18–36s — **well short of ≤7s.** Reaching 10× almost certainly requires removing the per-node `eval()` dispatch itself.

> Confidence: the *direction* (incremental caps well below 10×) is high-confidence — it follows from the bridge already being direct-Go + Amdahl. The exact ceiling (2–4×) is an estimate pending the first honest `--fresh` measurement (P-A). Do **not** abandon the incremental path before that measurement; do **not** assume 10× is one loop away.

## The decision gate (P-B)

1. Land **P-A** (`bench.sh --fresh` + repeat/min). 
2. Land **P-C** (Run N+7 + bridge replace) so a fully-landed new emit is measurable.
3. Measure cumulative gain vs `phase0=71.153s` with min-of-3 + `GOMAXPROCS=1`.
4. **If < ~3× (> ~24s):** the incremental path cannot reach ≤7s. Pivot to a structural lever below and author its implementation spec.
5. **Update the design spec's projection** to match reality (the "~12–87×" claim is inconsistent with the measured trajectory — Ralph instruction #14).

## Structural levers (increasing effort), if the gate says pivot

### Lever 1 — Cache the parsed `interpreter.s` AST across the two selfhost reparses
- **Idea:** the selfhost parses ~250KB of `interpreter.s` twice (instance A's program, then instance B's program). Serialise the parsed/resolved AST once and deserialise at the second site.
- **Est:** ~1.2–1.5×. **Effort:** small. **Risk:** changes only parse-time, not eval — and parse is a minority of wall, so this alone is far from 10×. Also borderline "benchmark-specific" since it exploits the duplicate-source structure of the self-host harness rather than speeding general interpretation.

### Lever 2 — Shrink `Value` (tagged-pointer / NaN-box)
- **Idea:** replace the 88-byte by-value `Value` struct with a single word (tagged pointer or NaN-boxed float64). Cuts the copy cost on every `eval()` return + argument pass + the GC pressure from boxed payloads.
- **Est:** ~1.3–1.5×. **Effort:** medium (touches every `*ToGo` leaf emit + the whole runtime). **Risk:** the design doc lists this as out-of-scope; pointer-tagging in Go fights the GC (unsafe, precise-GC concerns). NaN-boxing is safer but still a large diff. Stacks with the incremental phases but does not reach 10× alone.

### Lever 3 — Bytecode VM (the only single lever that plausibly reaches 10×)
- **Idea:** add a compile-from-AST-to-bytecode pass and a flat dispatch loop (`for { op := code[pc]; switch op {...} }`) in place of recursive `eval(*Node)`. Eliminates per-node function-call dispatch, the `(Value,bool)` sentinel branch, and most per-visit allocation. Operands live in a value stack / registers, not heap Contexts.
- **Est:** ~5–8× over the new tree-walker (removes the dominant `eval`+`Execute`+closure cost) and composes with slot-contexts/interning. **Effort:** large (new IR, compiler pass, VM loop, must preserve self-bootstrap fixed-point + MCP override pattern + verify.sh check 5). **Risk:** highest, but the only path with headroom for ≤7s.
- **De-risk:** prototype an arithmetic + function-call subset, transpile only `bench_eval.s`'s `fib`/`bubbleSort`, and measure the VM-loop speedup before committing to lowering all ~19 node kinds.

## Recommendation

Sequence: **P-A (measure) → P-C (Run N+7 + bridge replace, get the first honest cumulative number) → P-B gate.** If the honest number is < ~3×, prototype **Lever 3 (bytecode VM)** on the `bench_eval.s` subset before any further P3/P4 investment — P3/P4 would add ~1.5× to a path that caps at ~4×, which does not justify the loops if a VM is the real answer. If the honest number is surprisingly ≥ ~4× (the fresh tagged-union + D1-reborn build beats the interface-Value bridge by more than expected), continue incremental through P3/P4 and re-evaluate.

The one thing not to do: keep grinding 1.x× tree-walker tweaks against a 1.55× noise band toward a 10× target the approach cannot reach.
