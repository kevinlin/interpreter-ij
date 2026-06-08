# Spec — Bytecode VM (Lever 3) Implementation

Date: 2026-05-30
Status: Implementation spec. Supersedes the "guessed 5–8×" placeholder in
`docs/specs/10x-feasibility-and-structural-levers.md` §Lever 3 with a **measured**
mandate. Drives `IMPLEMENTATION_PLAN.md` P-B → P-VM.

## 1. Decision + evidence

P-B measured the incremental tree-walker arc at **~1.25× cumulative** (the honest
same-session pinned head-to-head, `IMPLEMENTATION_PLAN.md` §0-A) and pivoted to a
structural lever. The de-risk prototype (`experiments/bytecode-vm-prototype/`,
2026-05-30) settles the lever's size against a **byte-for-byte faithful clone of the
emitted runtime** (88-byte `Value`, `Context{parent, map}` chain lookups,
`eval(*Node)(Value,bool)` dispatch, `FunctionCommand` closure, per-call `*Context` +
params-map + `*ArrayValue`):

| engine (same 88-byte Value) | fib(32) min wall | allocs/call | speedup |
|---|---|---|---|
| treeWalk (faithful emit clone) | 2.588 s | 35,245,806 | 1.00× |
| **vm — Lever 3 only** | **0.325 s** | **40** (one-time arena) | **7.96×** |
| vmLean — Lever 3 + lean Value (Lever 2) | 0.135 s | 38 | 19.19× |

**Verdict: GO.** The dispatch-only lever lands at the **top of the 5–8× estimate**
with no inflation from shrinking `Value`, and removes essentially **all** per-call
heap traffic (35.2M → ~0 allocs/call) — directly attacking both the dispatch cost
*and* the ~33%-of-wall GC cost from the stage2 pprof. This is the only lever in the
plan with the headroom to reach ≤7s (10×); P3/P4/Lever-1 each cap at ≤1.6×.

The prototype models the **Go-side typed-AST** tree-walk. The selfhost-dominant cost
is the **IJ-side `MapValue` `"evaluate"` tree-walk** (heavier: string-keyed method
dispatch + `ctxGet` chain walks), so the production lever is **≥ 8×**, i.e. 8× is a
lower bound, not a ceiling.

## 2. Scope

**Target:** replace recursive AST evaluation with *compile-to-bytecode + a flat
dispatch loop* in the evaluator that dominates the selfhost bench — the **IJ-side
evaluator** in `src/interpreter.s` (the `evaluate`-method tree-walker + `ctxGet`).
The same IR/VM design also benefits the Go-side `eval(*Node)` transpile runtime
(`goLibPrefix`); land it there first as the lower-risk staging ground (it is the path
the prototype validated and has no `MapValue` indirection), then mirror to the IJ
evaluator.

**Non-goals (this lever):** shrinking `Value` (that is Lever 2 / `vmLean`'s extra
~2.4×; sequence it *after* the VM lands and only if ≤7s is not yet hit). JIT / native
codegen. Changing language semantics.

**Hard invariants (must hold at every commit — `IMPLEMENTATION_PLAN.md` §2):**
1. **verify.sh check 5** — two `compile-local.sh src/interpreter.s` runs byte-identical,
   AND the committed binary equals the self-transpile output (true fixed point).
2. **verify.sh check 4** — the MCP override pattern (`let oldX = X; def X(...) { oldX(...) }`).
3. Determinism — all emit ordering is source-order (no map-iteration nondeterminism);
   the constant pool + function table must intern in first-appearance order.
4. Arity tolerance — IJ tolerates caller-arity ≠ callee-arity (extras dropped, missing
   vNull-padded). The VM calling convention must preserve this (see §5).

## 3. IR design

### 3.1 Chunk
```
Chunk {
  code     []Instr      // flat instruction stream
  consts   []Value      // constant pool (interned, first-appearance order)
  numSlots int          // params + function-scope locals (from resolver)
  name     string       // for diagnostics
}
Instr { op uint8; a int32; b int32 }   // two operands cover slot+argc, jump targets
```

### 3.2 Opcode set (covers all ~19 node kinds)
| op | operands | effect |
|---|---|---|
| `OpConst` | a=const idx | push consts[a] |
| `OpNull` / `OpTrue` / `OpFalse` | — | push singleton (P3 synergy) |
| `OpLoadSlot` | a=slot | push frame-local slot a |
| `OpStoreSlot` | a=slot | pop → frame-local slot a |
| `OpLoadGlobal` | a=global idx | push global (top-level let/def) |
| `OpStoreGlobal` | a=global idx | pop → global (override pattern, rkGlobalLet) |
| `OpInfix` | a=op code | pop r, pop l, push binop(l,r) |
| `OpPrefix` | a=op code | pop v, push unop(v) |
| `OpJumpIfFalse` / `OpJump` | a=abs target | control flow |
| `OpArray` / `OpMap` | a=count | build literal from stack |
| `OpIndex` / `OpIndexStore` | — | collection get / put |
| `OpCallIJ` | a=fn slot, b=argc | call an IJ function (new frame) |
| `OpCallNative` | a=builtin idx, b=argc | call a Go builtin (`puts`, `len`, …) |
| `OpMakeClosure` | a=proto idx | build a closure capturing upvalues |
| `OpReturn` | — | pop result, pop frame |
| `OpPop` | — | discard top (statement-expression result) |

### 3.3 Runtime state
- **Value stack** `[]Value` — preallocated, reused across calls (the prototype's
  zero-per-call-alloc property; this is where the 35.2M→0 alloc win comes from).
- **Frame stack** `[]Frame{chunk, pc, base}` — preallocated; locals are stack slots
  `[base, base+numSlots)`, **slot-indexed, no map, no parent-chain walk**.
- **Globals** — top-level lets/defs in a flat indexed table (keeps the override
  pattern: `OpStoreGlobal` to the same index re-binds). Builtins in a native table.

### 3.4 Reuse existing scaffolding
- **`resolvedSlot` + `resolvedKind` are already on the `Node` struct** (zero-valued,
  scaffolded for P4 — `IMPLEMENTATION_PLAN.md` §3.1). The compiler pass reads the
  resolver's slot assignment instead of P4 wiring it into a slot-`Context`. **P4 is
  subsumed by this lever** — do not land P4 separately.
- **`analyzeIsStatic` / `resolvedIsStatic`** already classify pure top-level defs;
  reuse to choose `OpCallIJ` vs an inlined/native fast path.
- The resolver's `rkLib`/`rkGlobalLet`/`rkParam`/`rkLocal` kinds map 1:1 onto
  `OpCallNative`/`OpStoreGlobal`/`OpLoadSlot`/`OpLoadSlot`.

## 4. Compiler pass (AST → bytecode)

A new pass between resolve and emit (or at runtime startup — see §6.1). Per kind:
- literals → `OpConst`/`OpNull`/`OpTrue`/`OpFalse` (consts interned).
- ident → `OpLoadSlot resolvedSlot` (param/local) | `OpLoadGlobal` (top-level) |
  `OpCallNative`-ref (lib). Falls back to a global lookup for unannotated nodes.
- infix/prefix → operands then `OpInfix`/`OpPrefix` (short-circuit `&&`/`||` via jumps).
- if/while → condition + `OpJumpIfFalse`/`OpJump` with **backpatching** (prototype shows
  the pattern; `while` loops the condition).
- block → compile stmts; only function-scope `let`s consume slots (matches the existing
  `hasLocals` gate — inner blocks reuse the frame, no new scope).
- funcDecl → compile body into a child Chunk; register in the function table at a
  source-order index; `counts==1` gate preserved so the override idiom still works.
- call → args then `OpCallIJ`/`OpCallNative` with argc (arity handled in §5).
- return → expr then `OpReturn`.

## 5. Calling convention
- `OpCallIJ a=fnSlot b=argc`: callee chunk's slots begin at `sp-argc`. If
  `argc < numParams`, vNull-pad up to `numParams`; if `argc > numParams`, the extra
  args sit below the slot window and are dropped on return (preserves the **arity
  gotcha**, `AGENTS.md`). Push frame; no heap alloc.
- `OpCallNative a=builtinIdx b=argc`: gather argc values into the existing
  `*ArrayValue` shim (builtins keep their `Execute(ctx, *ArrayValue)` signature — no
  rewrite of `registerLibraryFunctions`), call, push result.
- `OpReturn`: result = top; `sp = frame.base`; pop frame; push result. Replaces the
  `(Value,bool)` sentinel entirely — return is now a stack-unwind, not a per-node
  boolean check (removes the §2.6 sentinel-branch cost).

## 6. Self-bootstrap & landing

### 6.1 Compile timing decision
**Runtime compile (recommended).** Keep the existing `*ToGo` Node emit; the emitted
runtime gains `compileChunk(programNode)` at `func main()` startup + `vmRun(chunk,
ctx)` instead of `eval(programNode, ctx)`. Smallest diff, reuses the whole existing
parser/resolver/emit, and the compile cost is one-time (negligible vs the eval loop).
*Alternative* (emit bytecode arrays statically into `app.go`) is a far larger emit
rewrite — defer.

### 6.2 Phased plan (each phase independently `verify.sh`-gated)
- **P-VM.0 ✅ — de-risk prototype + this spec** (2026-05-30). 8× measured.
- **P-VM.1 — Go-side VM behind a build flag.** Add Chunk/Instr/VM + `compileChunk` to
  `goLibPrefix`; gate `func main()` on `IJ_VM=1` to pick `vmRun` vs `eval`. Lower the
  arithmetic+call+if+return+block subset first. Differential-test: `IJ_VM=1` vs default
  on `test.s` + `sample.s` must match. Bench `bench.sh --fresh phase-vm1`.
- **P-VM.2 — full node-kind coverage** (arrays, maps, index, prefix, closures/upvalues,
  while, var-decl, the override pattern). `verify.sh` 5/5 with `IJ_VM=1`.
- **P-VM.3 — flip default to VM; re-establish the fixed point.** This is the
  delicate step: the *committed binary itself* must be a VM build, and a fresh
  `compile-local.sh` of the (VM-emitting) source must reproduce it byte-identically
  (check 5). Procedure mirrors the P-C bridge-replace (committed→s1→s2, `cmp s2 s3`).
- **P-VM.4 — mirror the VM into the IJ-side evaluator** (the selfhost-dominant path);
  bench the real ≥8× selfhost win. Then drop the dead tree-walker (`eval*` /
  `evaluate*`) once `scripts/interpreter.sh` + `ast.sh` + resolver are migrated.
- **P-VM.5 (optional) — stack Lever 2** (NaN-box / tagged-pointer `Value`) only if
  ≤7s is still not met; `vmLean` shows ~2.4× more headroom.

### 6.3 Determinism / fixed-point notes
- Constant pool + function table interned in **source order** (same discipline as
  `staticDefNames`). Any map-iteration over consts/functions breaks check 5.
- The compiler runs inside interpreter.s, so it transpiles to Go and must itself be a
  fixed point. Keep it allocation-deterministic (no `keys()`-order dependence).

## 7. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Fixed-point break (check 5) at the default flip | Build behind `IJ_VM` flag until P-VM.3; reuse the proven committed→s1→s2 `cmp` procedure. |
| MCP override pattern (check 4) | `counts==1` gate + `OpStoreGlobal`-to-same-index re-bind; differential-test MCP with `IJ_VM=1` before flip. |
| Arity mismatch regressions | §5 vNull-pad / drop-extra convention; carry the `test.s` arity cases. |
| Closures / upvalues | `OpMakeClosure` + upvalue capture; the resolver already tracks `captured`. Land last (P-VM.2) behind differential tests. |
| Scope creep | Strict subset → flag → full → flip → mirror. Never flip the default before `verify.sh` 5/5 under the flag. |

## 8. Open questions
- Upvalue representation: flat captured-slot array vs boxed cells. Decide in P-VM.2
  from the IJ closure usage in `interpreter.s` itself (it relies on `self`-passed map
  methods, not lexical closures — may simplify).
- Whether the IJ-side evaluator (P-VM.4) shares the Go-side Chunk format or needs an
  IJ-level mirror. Likely an IJ-level compiler emitting the same opcodes the Go VM
  consumes — TBD after P-VM.1 reveals the Go-side shape.
- Do builtins stay `*ArrayValue`-based forever (§5) or get a fast fixed-arity path
  later? Defer; not on the critical path to 10×.
