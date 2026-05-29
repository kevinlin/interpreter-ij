# Spec — Benchmark Methodology (`bench.sh --fresh` + repeat/min + noise controls)

Date: 2026-05-29
Status: Proposed (authored during a plan-only loop; implement under IMPLEMENTATION_PLAN.md P-A).

## Why this exists (the problem)

The self-hosted perf effort has two measurement defects that, together, make every perf verdict in `bench.log` untrustworthy.

1. **The bench measures the wrong binary.** `scripts/bench.sh` runs `selfhosted_interpreter.sh src/sample.s`, which (via `interpreter.sh` → `native_interpreter.sh`) hardcodes the **committed** `interpreter_${OS}_${ARCH}` binary (`scripts/native_interpreter.sh:27-35`). That binary is **frozen at commit `ac2e6f3`** and has never been replaced. So all source-level perf work since (P1, P2, P2.5, P2.6 Runs N..N+6) is **invisible to the bench**. The team has optimised blind for ~10 loops, hand-rolling one-off "stage2" timings outside `bench.sh`.

2. **The signal is below the noise floor.** The bench is a single `time` invocation on a loaded laptop. The **same committed binary** spans **70.45s … 109.18s = 1.55× ratio** across `bench.log`. The drop-rule gate is **1.3×**. A 1.3× win cannot be distinguished from machine noise, so "1.04× within noise" verdicts (the dominant outcome in the plan) carry no information.

These combine into a **gating deadlock**: source wins are invisible until the committed binary is replaced, but the binary is only replaced once a fresh build beats it — and you cannot see that it beats it, because the bench measures the frozen binary.

## Goal

Make `bench.sh` able to (a) measure a *freshly built* interpreter, decoupled from the committed-binary-replace decision, and (b) report statistics robust to laptop noise — so the drop-rule becomes enforceable and source progress becomes visible immediately.

## Design

### 1. `BINARY` override in `scripts/native_interpreter.sh`

Today the binary path is computed and hardcoded. Add a one-line override so any driver can point the self-host stack at an arbitrary build:

```bash
BINARY="${IJ_BINARY:-$ROOT_DIR/interpreter_${OS_NAME}_${ARCH_NAME}}"
```

Default behaviour is unchanged (committed binary). Setting `IJ_BINARY=/tmp/ij-fresh` swaps in a fresh build for the whole nested self-host stack (all three interpretation layers use the same binary, which is correct — instance A and B are the same interpreter).

**Why an env var, not a flag:** `native_interpreter.sh` is called transitively (`bench.sh` → `selfhosted_interpreter.sh` → `interpreter.sh` → `native_interpreter.sh`); threading a flag through every layer is noisy, an env var propagates for free.

### 2. `bench.sh --fresh`

```
./scripts/bench.sh --fresh [label]
```

- Builds the **true fixed point** (stage2) of the current source via two
  non-Docker `compile-local.sh` runs, then benches it:
  1. `compile-local.sh src/interpreter.s /tmp/ij-fresh-s1` (committed bridge → stage1).
  2. `IJ_BINARY=/tmp/ij-fresh-s1 compile-local.sh src/interpreter.s /tmp/ij-fresh` (stage1 bridge → stage2).
- Exports `IJ_BINARY=/tmp/ij-fresh` for the selfhost block only.
- Everything else identical to a normal run.

**Why two stages, not one (correction, 2026-05-29 implementation):** an earlier
draft of this spec proposed a single `compile-local src/interpreter.s` and claimed
it surfaces Run N+6's `2m26s` stage2. That is wrong. A single compile uses the
**committed (frozen, pre-Run-N+6) bridge**, whose `functionDeclarationToGo` emits
no `staticImpl` field — so stage1 is **parity-blind** to the closure-body-hoist
work (IMPLEMENTATION_PLAN.md §1: "stage1 … IF-branch never fires there"). Benching
stage1 reports ~committed parity and **hides exactly the source work `--fresh`
exists to reveal.** Only stage2 — built BY stage1, whose emitter does add
`staticImpl` — exercises the current codegen. The `IJ_BINARY` bridge override on
`compile-local.sh` (added this loop) lets the fixed point be built without ever
overwriting/restoring the committed binary (it also obsoletes the unsafe
`cp /tmp/s1 interpreter_mac_arm64` dance in AGENTS.md).

This restores the feedback loop the deadlock removed.

### 3. `bench.sh --repeat N` (default N=3)

- Run the `selfhosted_interpreter.sh` block N times.
- Report **min**, **median**, **max** (and sample count). **Min is the headline** — it is the standard for wall-clock micro-benchmarks because noise is one-sided (other processes only ever slow you down; nothing makes you faster than the machine's true speed).
- Single-run mode stays the default for quick smoke checks but is labelled "unreliable; use --repeat for decisions".

### 4. Noise controls

- Measure with `GOMAXPROCS=1`. GC background + sysmon threads are ~33% of stage2 wall (pprof) and are the dominant variance source; pinning to one P makes runs comparable. (Keep an unpinned run too, since production is multi-P — but gate decisions on the pinned min.)
- Report `user` time alongside `real`. `user` excludes OS-scheduling jitter and is a more stable cross-run comparator on a loaded box.
- Optional outlier filter: discard any run > 1.1× the median before reporting min.

### 5. Make the drop-rule enforceable (or replace it)

After §3+§4 land, re-measure the committed binary's noise band under `--repeat 3 + GOMAXPROCS=1 + min`. Then:

- If min-of-3 collapses the band below ~1.15×, the **1.3× drop-rule is usable** as written.
- If not, either raise the per-phase gate to a **consensus ≥1.5×**, or switch the *primary* signal to a **deterministic proxy**: re-instrument the dormant `ijCount*` counters (`src/interpreter.s:~4508`, declared + dumped via `IJ_COUNTERS` but never incremented since `b040672`) to count allocations / eval-node-visits / `ctx.Get` chain hops. A deterministic op-count is noise-free and a faithful proxy for tree-walker cost; wall-clock then becomes a secondary confirm.

## Testing / acceptance

- `IJ_BINARY=<binary> ./scripts/native_interpreter.sh src/sample.s` produces correct output ("Hello hi") using the overridden binary, proving the override path. (Verified 2026-05-29 with the committed binary as an explicit override; a bogus `IJ_BINARY` errors, proving the var is read.)
- `./scripts/bench.sh --fresh --repeat 3 n6-baseline` reports a min/median/max block and the fresh number matches the hand-rolled **stage2** timing (~2m26s at Run N+6), confirming the bench now sees source work. (Requires the two-stage fixed-point build above — a single-stage build would report parity and is the bug this spec corrected.)
- Default `./scripts/bench.sh` behaviour (committed binary, single run) is unchanged — the three-block `time` output format is preserved on the no-flag path; `--repeat`/`--fresh` only alter behaviour when explicitly passed.
- `compile-local.sh src/interpreter.s` twice is byte-identical (verify.sh check 5) — prerequisite for trusting `--fresh` reproducibility.

## Non-goals

- No change to what the selfhost benchmark *measures* (still interpreter-in-interpreter on `sample.s`). Removing an interpretation layer would change the benchmark and is out of scope.
- No CI/visualisation harness (the `bench-history.tsv` idea is a possible follow-up, not required here).

## Why this is the highest-priority work

It is cheap (shell only), it unblocks the deadlock that has hidden ~10 loops of source work, and it is a hard prerequisite for any honest 10×-feasibility judgement (IMPLEMENTATION_PLAN.md P-B). Until it lands, no perf decision is trustworthy.
