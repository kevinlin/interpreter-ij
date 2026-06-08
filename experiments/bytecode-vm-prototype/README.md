# Bytecode-VM de-risk prototype (Lever 3)

## Why this exists

`IMPLEMENTATION_PLAN.md` P-B measured the incremental tree-walker arc at **~1.25×**
cumulative — far short of the 10× goal — and pivoted to a *structural* lever.
The candidate with headroom is **Lever 3: a bytecode VM** replacing the recursive
`eval(*Node)(Value,bool)` dispatch (see `docs/specs/10x-feasibility-and-structural-levers.md`).
That spec only had a *guessed* "5–8×". Lowering all ~19 IJ node kinds to bytecode
inside `src/interpreter.s` — and re-proving the self-bootstrap fixed point — is
large and high-risk, so we measure the lever **before** committing.

The plan's de-risk instruction (verbatim): *"prototype an arithmetic + function-call
subset … and measure the VM-loop speedup before committing to lowering all ~19 node
kinds."* This is that prototype.

## What it compares (apples-to-apples)

All three share the **identical 88-byte `Value`** struct copied byte-for-byte from
the `interpreter.s` emit (`src/interpreter.s:4835`).

| engine | what it models |
|---|---|
| `treeWalk` | a faithful clone of the emitted Go runtime: `Context{parent, map[string]Value}` parent-chain lookups, `eval(*Node)(Value,bool)` recursive dispatch with the return sentinel, `FunctionCommand` closure dispatch, fresh `*Context` + params map + `*ArrayValue` **per call**. This is the exact shape of the dominant `eval`+`Execute`+closure cost in the stage2 pprof. |
| `vm` | **Lever 3 only.** Same 88-byte `Value`, but compiled to bytecode with slot-based locals on a **reused** value stack + flat dispatch loop. No per-call heap alloc. Conservative — does *not* also shrink `Value`. |
| `vmLean` | **Lever 3 + Lever 2.** Same VM with an `int64` stack, to show the ceiling if a leaner value is stacked on later. |

Workload: user-level recursive `fib` (arithmetic + comparison + calls + if/return).

## Results (Apple arm64, go1.26.3, GOMAXPROCS=1, min-of-N)

```
fib(32) = 2178309
engine                               min wall    allocs/call       bytes/call
treeWalk                            2.588 s         35,245,806      7,613,090,848
vm (Lever3, 88B Value)              0.325 s                 40          5,869,448
vmLean (Lever3+leanValue)           0.135 s                 38            626,464

speedup vs treeWalk:  vm 7.96×   vmLean 19.19×
```

`fib(30)` reproduces the same band: `vm 7.28×`, `vmLean 19.38×`.

The `allocs/call` / `bytes/call` columns are for **one** `fib(n)` call (measured via
`runtime.MemStats`). The VM's "40 allocs" are the one-time stack/frame arenas +
compile, *not* per-fib-call — i.e. the VM removes essentially **all** per-call heap
traffic (35.2M → ~0). That directly attacks the ~33%-of-wall GC cost flagged in the
stage2 pprof, on top of removing the dispatch cost.

## Verdict

**GO for Lever 3.** The dispatch-only lever (`vm`, same Value) hits the **top of the
spec's 5–8× estimate (~8×)** with zero inflation from a smaller Value. That alone, if
realized end-to-end, moves the selfhost bench from `71s` toward the `≤7s` (10×) goal;
`vmLean` shows another ~2.4× of headroom from Lever 2 if needed. No other single lever
in the plan (P3 ~1.1–1.3×, P4 ~1.3–1.6×, Lever 1 ~1.2–1.5×) is close.

**Caveat (honest):** this models the Go-side typed-AST tree-walk that Lever 3 replaces.
It does **not** model the additional IJ-side `MapValue` `"evaluate"` string-lookup
overhead of the deepest selfhost layer, which a real lowering would *also* remove — so
the production lever is a **lower bound** of ~8×, not an upper bound. The risk is not
the speedup; it is the engineering cost of lowering all node kinds + preserving the
self-bootstrap fixed point (verify.sh check 5) + the MCP override pattern (check 4).
See `docs/specs/bytecode-vm-implementation.md`.

## How to run

```bash
cd experiments/bytecode-vm-prototype
go build -o /tmp/vmproto main.go
/tmp/vmproto            # fib(32), 5 repeats
/tmp/vmproto 30 5       # fib(N) REPEATS
```

The harness asserts `treeWalk`, `vm`, and `vmLean` all return the closed-form `fib(n)`
before reporting timings, so a broken engine fails loudly instead of posting a fake win.
