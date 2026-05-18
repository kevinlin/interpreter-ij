# Self-Hosted Interpreter Perf — ≥10× Implementation Plan

> **This file is the design recipe for future phases.** Running state (what's shipped, what's blocked, the next-loop roadmap) lives in [`IMPLEMENTATION_PLAN.md`](../../../IMPLEMENTATION_PLAN.md) at the repo root. Shipped phases (0 / 1 / 2 / 2.5 / 2.6) are stubbed to single-paragraph pointers below — read IMPLEMENTATION_PLAN.md for status, forensics, and the next-run roadmap. Future phases (3 / 4 / Cleanup) keep their full step-by-step recipe here.

**Goal:** Make `./scripts/bench.sh` self-hosted run at least 10× faster (≤ 7s wall on macOS/arm64), without breaking the self-bootstrap fixed-point or any functional check.

**Architecture:** Phased refactor of the emitted Go runtime + the codegen inside `interpreter.s`. P1 swapped the `Value` interface for a tagged-union struct. P2 replaced MapValue-backed AST nodes with typed Go structs in the transpiled output. **P2.5 activated the resolver annotations that P2 wired structurally but never read.** **P2.6 (D2-reborn) added direct-fn-pointer dispatch for promoted static defs; root-caused the stage2 5× perf regression to a structural mismatch with the committed bridge's emit shape.** P3 adds a global string pool + null/bool/small-int singletons. P4 (conditional) replaces map-backed Contexts with slot-indexed slices.

**Tech Stack:** IJ (self-hosted), Go (transpile target), bash drivers, golden-output regression harness.

**Design source:** [docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md](../specs/2026-05-16-self-hosted-perf-10x-design.md)
**Research source (current state map):** [docs/research/2026-05-18-interpreter-perf-research.md](../../research/2026-05-18-interpreter-perf-research.md)

---

## Status — 2026-05-18 (running state lives in IMPLEMENTATION_PLAN.md)

| Phase | Status | Bench at end of phase |
|---|---|---|
| Phase 0 — Baseline | ✅ shipped 2026-05-16 | `phase0-baseline = 1m11.153s` |
| Phase 1 — Tagged-union `Value` | ✅ shipped (committed binary on bridge) | folded into P2; cleanup dropped D1/D2/D3 fast paths |
| Phase 2 — Typed AST | ⚠️ shipped STRUCTURALLY only — resolver annotations land on AST but were dead in P2; resurrected in P2.5 | `p2-no-refresh = 1m20.478s (0.88× of phase0)` |
| Phase 2.5 — Activate resolver annotations | ✅ shipped 2026-05-17 source-level (commits `6ca08e9..5bf147a`); visible gain blocked behind bridge replace | `p2_5-final = 1m17.982s` |
| Phase 2.6 — D2-reborn + stage2 root-cause | ✅ source shipped 2026-05-18 (commits `fdf23ec, 6c4d429, 6add785`); committed-binary replace blocked behind D1-reborn perf parity fix — see IMPLEMENTATION_PLAN.md P2.6 | `p2.6-diagnosis-alloc-reduction = 1m37.904s` (committed-bridge bench; source-only changes invisible until bridge replace) |
| **D1-reborn (next critical path)** | ⬜ scoped — multi-loop, run-by-run roadmap in IMPLEMENTATION_PLAN.md P2.6 "Runs N…N+3" | — |
| Phase 3 — String interning + singletons | ⬜ queued (recipe below) | — |
| Phase 4 — Slot-indexed contexts | ⬜ stretch (recipe below) | — |

**Headline:** committed bridge bench is stuck at ~1m17–1m37s. Every P2.5/P2.6 source-level win is invisible to `bench.sh` because the bench runs the committed bridge. D1-reborn (in IMPLEMENTATION_PLAN.md P2.6) is the gating critical path; P3/P4 stay queued behind it. See `IMPLEMENTATION_PLAN.md` for the per-loop scope breakdown and forensics.

**Drop-rule reminder:** the floor for any post-P2 phase's drop-rule is `p2-no-refresh = 1m20.478s`, not `phase0-baseline = 1m11.153s` and NOT the irreproducible 49s outlier. Each phase must show ≥1.3× over its predecessor or it is reverted. The cumulative-vs-phase0 target stays at ≥10× (= ≤ 7.115s).

---

## Cross-Phase Conventions

**Branch:** all work on a single feature branch `perf/tagged-union-and-typed-ast` off `main`. Each phase merges back as one squash commit on completion; intermediate commits inside a phase land on the feature branch.

**Build pipeline assumptions:**
- `./src/compile-local.sh src/interpreter.s /tmp/ij_stage1` produces a fresh native binary using the host Go toolchain. Use this — never the Docker path during this work.
- The committed binary at repo root (`interpreter_mac_arm64`) is replaced once per phase, after the phase's final verify.sh check passes.
- Each phase ends with `./scripts/bench.sh phaseN-<name>` appending labeled timings to `bench.log`.

**Per-commit gate (every commit on the feature branch must pass):**
- `./scripts/test.sh` — golden tests pass.
- `./scripts/verify.sh` runs checks 1–4 green. Check 5 may be skipped/non-green mid-phase but **must** be re-baselined and green before merging the phase.

**Drop-rule:** if `./scripts/bench.sh phaseN-<name>` shows < 1.3× over the previous phase, revert the phase commits and stop. No "but it should be faster" excuses (the README's D4 lesson).

**Re-baselining check 5 mid-phase:**
- `./scripts/verify.sh --capture` at phase start, recording any new emitted-Go fingerprints.
- After the phase's last functional commit, re-run `./src/compile-local.sh src/interpreter.s /tmp/ij_stage1` and `./src/compile-local.sh src/interpreter.s /tmp/ij_stage2` then `diff /tmp/ij_stage1 /tmp/ij_stage2`. Must be byte-identical.

---

## File Structure

This refactor edits a small set of files repeatedly. No new IJ source files except the new benchmark.

- Modify: `src/interpreter.s` — the only file in 99% of tasks. Contains both the runtime-type emit block (~5159–6342) and every `*ToGo` codegen function (~70–4843).
- Modify: `scripts/bench.sh` — extend to also run the new `bench_eval.s`.
- Modify: `scripts/verify.sh` — only if new golden capture sites are needed (not expected).
- Modify: `README.md` — perf section update at the end.
- Create: `src/bench_eval.s` — eval-heavy secondary benchmark.
- Modify: `interpreter_mac_arm64`, `interpreter_linux_amd64`, `mcp_mac_arm64`, `mcp_linux_amd64` (committed binaries, regenerated at phase end).

The committed binaries change every phase. That's expected and how this repo has always worked.

---

## Shipped phases — see IMPLEMENTATION_PLAN.md for status and forensics

The step-by-step recipes for Phase 0 / 1 / 2 / 2.5 / 2.6 used to live here. They were collapsed 2026-05-18 because the work is shipped and the running state has moved to `IMPLEMENTATION_PLAN.md` at the repo root. Each phase is summarised below; for forensics, drop-rule decisions, and any surviving open carry-forward items, read `IMPLEMENTATION_PLAN.md` (sections P0–P2.6).

### Phase 0 — Baseline Capture (shipped 2026-05-16)

Captured `verify.sh --capture` golden + `phase0-baseline = 1m11.153s` floor. `src/bench_eval.s` was created but subsequently dropped from `scripts/bench.sh` (>5min under Phase 2 codegen). Re-enable only after primary bench hits 10×.

### Phase 1 — Tagged-Union `Value` (shipped, then cleaned 2026-05-17)

Replaced the Go `Value` interface + per-type structs (`IntValue`/`StringValue`/`BoolValue`/`DoubleValue`/`InvalidValue`) with a single 88-byte tagged-union `Value{tag, b, i, d, s, arr, m, cmd, inv}`. `ArrayValue` and `MapValue` kept as separate types, wrapped via `tArray`/`tMap` tags. The Phase 1 cleanup commit (`fb2b299`) accidentally dropped the D1/D2/D3 fast-path emit code along with the dual-runtime deletion — recovered partially by P2.5 (D1) and P2.6 (D2-reborn). D3 still GONE; recipe to re-introduce lives in the design spec under §Phase 1 / §Phase 2.5 *Out of scope*. See IMPLEMENTATION_PLAN.md P1 for the dead-code cleanup forensics + the 49s-outlier post-mortem.

### Phase 2 — Typed AST Struct Nodes (shipped 2026-05-17)

Replaced `*MapValue` AST node emit with `&Node{kind: nkXxx, ...}` typed Go struct emit. Added the per-kind `evalXxx` switch dispatch (`evalIdent`, `evalInfix`, `evalAssign`, `evalBlock`, `evalCall`, …). Picked `(Value, bool)` over `tReturn`/`subTag` for the return-sentinel (Plan §Task 2.7 alternative; design §6.4 records the choice). Resolver annotations land on AST nodes but were DEAD at P2 ship time (no `*ToGo` emitter read them) — fixed in P2.5. `refreshToGoPointers` excised in commit `c42261c` (was dead post-cleanup). Stage2 IJ tree-walker scalar-VarDecl regression resolved in commit `fdf23ec` via `isReturnValue` isMap guard at `src/interpreter.s:1210`. See IMPLEMENTATION_PLAN.md P2 for forensics and the stage1→stage2→stage3 source-level fixed-point demonstration.

### Phase 2.5 — Activate Resolver Annotations (shipped 2026-05-17, commits `6ca08e9..5bf147a`)

Wired the existing-but-dead resolver annotations into `Node`:
- `rk*` constants (`rkGlobal`/`rkParam`/`rkLocal`/`rkUpvalue`/`rkLib`) + `Context.GetLocal`/`UpdateLocal` + package-level `var rootCtx *Context` in `goLibPrefix`.
- `identifierToGo` / `assignmentStatementToGo` / `variableDeclarationToGo` project `resolvedKind` into emitted Node literals.
- `evalIdent` switches on `resolvedKind` (rkLib → `rootCtx.GetLocal`); `evalAssign` switches similarly; `evalBlock` gates `NewContext(ctx)` alloc on `hasLocals`; `FunctionCommand.Execute` drops the wasted caller-ctx alloc.

All changes pass `test.sh` ✅ and `verify.sh` 5/5 ✅. Visible bench gain is blocked behind the committed-binary replace (the bench runs the COMMITTED bridge, whose pre-P2.5 tree-walker doesn't honour any of these). IMPLEMENTATION_PLAN.md P2.5 has the per-task changelog + the gain-vs-bench-floor discussion.

### Phase 2.6 — D2-reborn + Stage2 Perf-Regression Root-Cause (shipped 2026-05-18, commits `fdf23ec, 6c4d429, 6add785`)

D2-reborn: pre-pass `collectStaticDefs` promotes 205 top-level `FunctionDeclaration` nodes (`resolvedAtRoot && single binding`); each gets a sibling `ij_<name>_impl(ctx, args []Value) Value` Go function. `CallExpression_toGo` emits `nkStaticCall` with `staticImpl` func-pointer baked into the Node when the callee is a known static def. Runtime `evalStaticCall` bypasses `evalIdent + ctx.Get + FunctionCommand.Execute + ArrayValue alloc`. 89 nkStaticCall sites in the new emit.

Stage2 perf regression (5× vs stage1) ROOT-CAUSED: the committed bridge emits each `ij_<n>_impl` as **direct Go statements** (one Go stmt per IJ stmt); the new src emits each `ij_<n>_impl` as `result, _ := eval(ij_<n>_body, local)` — wraps a Node-tree tree-walker. Stage2 runs every IJ-level op through the Go-side `eval()` switch with alloc per Node visit. pprof confirms 33.6% cum is in `evalFuncDecl.func1` reached via `FunctionCommand.Execute`. **D2-reborn was the wrong shape of fix** — it collapses direct-by-name calls but doesn't touch the dominant closure-body path. The correct structural fix is **D1-reborn** — emit promoted-static-def bodies as direct Go statements.

Pprof defer-order bug fixed (was masking all `IJ_CPUPROFILE` output as 0-byte). `evalCall` + `evalFuncDecl` alloc-reduction patches landed (~5% per-call cost reduction, invisible to bench until bridge replace).

**The next critical-path work is D1-reborn**, scoped run-by-run in `IMPLEMENTATION_PLAN.md` P2.6 "🎯 D1-reborn — the critical path". When that lands, the committed bridge is replaced and `verify.sh` check 5 is tightened from determinism to true fixed-point. P3 then becomes observable.

---

## Phase 3 — String Interning + Constant Singletons

Cumulative speedup not yet ≥10× — add interning. Otherwise skip to "Phase Done — Cleanup".

### Task 3.1: Add singleton vars in runtime emit

**Files:**
- Modify: `src/interpreter.s` — after the helper constructors (`vIntV` etc).

- [ ] **Step 1: Insert singletons**

```ij
puts("var vNull = Value{tag: tNull}");
puts("var vTrue = Value{tag: tBool, b: true}");
puts("var vFalse = Value{tag: tBool, b: false}");
puts("var vEmpty = Value{tag: tString, s: " + chr(34) + chr(34) + "}");
puts("var smallInt [256]Value");
puts("var strPool []Value");
puts("func init() {");
puts("for i := range smallInt { smallInt[i] = Value{tag: tInt, i: int64(i - 128)} }");
puts("}");
puts("func vIntFast(i int64) Value {");
puts("if i >= -128 && i < 128 { return smallInt[i+128] }");
puts("return Value{tag: tInt, i: i}");
puts("}");
puts("func vStrPool(idx uint32) Value { return strPool[idx] }");
```

- [ ] **Step 2: Build + commit**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p3_t1 && ./scripts/test.sh`
Expected: pass.

```bash
git add src/interpreter.s
git commit -m "perf/p3: emit Value singletons (vNull/vTrue/vFalse/smallInt) + strPool scaffolding"
```

---

### Task 3.2: Wire codegen to collect string literals into strPool

**Files:**
- Modify: `src/interpreter.s` — global state (top-level `let` declarations near `transpilerImplQueue`) + `stringLiteralToGo` + `identifierToGo` + final `programToGo` emit.

- [ ] **Step 1: Add a global string-pool table during codegen**

Near the top of `interpreter.s` (e.g. just after `let transpilerStaticImpls = {};` at line 1419), add:

```ij
let strPoolList = [];
let strPoolIndex = {};

def strPoolIntern(s) {
    if (strPoolIndex[s] != null) {
        return strPoolIndex[s];
    }
    let idx = len(strPoolList);
    strPoolList = append(strPoolList, s);
    strPoolIndex[s] = idx;
    return idx;
}
```

- [ ] **Step 2: Update `stringLiteralToGo`**

Replace its body (modified in P2 Task 2.8) with:

```ij
def stringLiteralToGo(self) {
    let idx = strPoolIntern(escapeGoStringLiteral(self["value"]));
    print('&Node{kind: nkStringLit, sIdx: ' + intString(idx) + '}');
}
```

And update `evalDispatch`'s case for `nkStringLit` (in runtime emit) to use `strPool[n.sIdx]` instead of `Value{tag: tString, s: n.name}`. Adjust accordingly.

- [ ] **Step 3: Emit the strPool population after main()**

At the very end of `programToGo` (or wherever the emit ends with `}` for the main package), emit a `strPool = []Value{...}` initialization block from the collected `strPoolList`. Append something like:

```ij
puts("func initStrPool() {");
puts("strPool = []Value{");
let i = 0;
while (i < len(strPoolList)) {
    puts('{tag: tString, s: "' + strPoolList[i] + '"},');
    i = i + 1;
}
puts("}");
puts("}");
```

And add `initStrPool()` to the existing `init()` function (also emitted):

```ij
puts("func init() {");
puts("for i := range smallInt { smallInt[i] = Value{tag: tInt, i: int64(i - 128)} }");
puts("initStrPool()");
puts("}");
```

- [ ] **Step 4: Update integer-literal emit to route through smallInt cache**

In `numberLiteralToGo` (after P2 modification), the int-literal case prints `&Node{kind: nkIntLit, iVal: ...}`. No change to the Node literal itself. But in `eval`'s dispatch for `nkIntLit`, change:

```ij
puts("case nkIntLit: return Value{tag: tInt, i: n.iVal}");
```
to:
```ij
puts("case nkIntLit: return vIntFast(n.iVal)");
```

- [ ] **Step 5: Update bool/null literal emits**

In `eval`'s dispatch:
```ij
puts("case nkBoolLit: if n.bVal { return vTrue }; return vFalse");
puts("case nkNullLit: return vNull");
```

- [ ] **Step 6: Build + test**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p3_t2 && ./scripts/test.sh`
Expected: pass.

- [ ] **Step 7: Verify determinism of strPool order**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p3_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_p3_stage2
diff /tmp/ij_p3_stage1 /tmp/ij_p3_stage2 && echo OK
```
Expected: `OK`. If diff non-empty, the strPool ordering depends on map iteration somewhere — switch to a list-based interning if hash-map iteration is happening.

- [ ] **Step 8: Replace committed binary + MCP**

Run: `./src/compile-local.sh src/interpreter.s interpreter_mac_arm64 && ./scripts/build.sh`

- [ ] **Step 9: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64 mcp_mac_arm64
git commit -m "perf/p3: intern string literals into strPool, route bool/null/smallint via singletons"
```

---

### Task 3.3: Benchmark Phase 3

- [ ] **Step 1: Bench**

Run: `./scripts/bench.sh phase3-intern`
Expected: timing block appended. Speedup vs P2 ≥ 1.2× (target 1.3–1.8×).

- [ ] **Step 2: Drop-rule**

If < 1.2× — revert P3 and skip to "Phase Done — Cleanup" with P1+P2 result. If cumulative ≥ 10×, skip P4.

- [ ] **Step 3: Commit bench**

```bash
git add bench.log
git commit -m "bench: phase3-intern results"
```

---

## Phase 4 (Stretch) — Slot-Indexed Contexts

Only run if cumulative speedup after P3 still < 10×.

### Task 4.1: Annotate resolver scopes with slot indices

**Files:**
- Modify: `src/interpreter.s` — `resolverScopeDeclare` (~1432) and `resolverScopeLookup` (~1449).

- [ ] **Step 1: Add slot counter to resolverScope**

In `makeResolverScope` (~1421), add `scope["nextSlot"] = 0;` to the initialised fields.

In `resolverScopeDeclare(scope, name, origin)`, after assigning the declaration, also assign:
```ij
scope["slots"] = scope["slots"];   // initialise once if null
if (scope["slots"] == null) { scope["slots"] = {}; }
scope["slots"][name] = scope["nextSlot"];
scope["nextSlot"] = scope["nextSlot"] + 1;
```

In `resolverScopeLookup(scope, name)`, when returning info about a resolution, also include `resolvedSlot` and `resolvedDepth` walked from the lookup point.

- [ ] **Step 2: Project resolvedSlot into the codegen**

In `identifierToGo` (P2 version), add emission of `resolvedSlot`:
```ij
if (self["resolvedSlot"] != null) {
    print(', resolvedSlot: ' + intString(self["resolvedSlot"]));
}
```

In `variableDeclarationToGo` and `functionDeclarationToGo`, similarly emit slot info.

- [ ] **Step 3: Build, test**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p4_t1 && ./scripts/test.sh`
Expected: pass (resolvedSlot is carried but not yet consumed).

- [ ] **Step 4: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p4: resolver assigns slot indices to scope vars; codegen propagates"
```

---

### Task 4.2: Switch Context to slot-indexed slice

**Files:**
- Modify: `src/interpreter.s` — Context emit block (~5159) and the `eval` dispatch's local lookup.

- [ ] **Step 1: Add `slots []Value` to Context emit**

```ij
puts("type Context struct {");
puts("parent *Context");
puts("variables map[string]Value");  // keep for global / dynamic
puts("slots []Value");
puts("inlineLen int");
puts("inlineKeys [6]string");
puts("inlineVals [6]Value");
puts("}");
puts("func (c *Context) GetSlot(depth, slot int) Value {");
puts("cur := c");
puts("for i := 0; i < depth; i++ { cur = cur.parent }");
puts("return cur.slots[slot]");
puts("}");
puts("func (c *Context) SetSlot(depth, slot int, v Value) {");
puts("cur := c");
puts("for i := 0; i < depth; i++ { cur = cur.parent }");
puts("cur.slots[slot] = v");
puts("}");
```

- [ ] **Step 2: Update evalIdent**

```ij
puts("func evalIdent(n *Node, ctx *Context) Value {");
puts("if n.resolvedKind == 1 || n.resolvedKind == 2 { return ctx.GetSlot(0, int(n.resolvedSlot)) }");
puts("if n.resolvedKind == 3 { return ctx.GetSlot(1, int(n.resolvedSlot)) }");
puts("return ctx.Get(n.name)");
puts("}");
```

(resolvedKind: 1=param, 2=local, 3=upvalue, 4=static, 0=global.)

- [ ] **Step 3: Update evalAssign + evalVarDecl + evalFuncDecl to allocate + use slots**

`evalFuncDecl`'s closure now allocates a `local.slots = make([]Value, paramCount + localCount)` based on resolver counts (carried on the Node — add a `slotCount int32` field to Node).

`evalVarDecl` uses `ctx.SetSlot(0, int(n.resolvedSlot), v)` instead of `ctx.Create(n.name, v)`.

`evalAssign` uses `ctx.SetSlot(0, int(n.resolvedSlot), v)` when `n.resolvedSlot >= 0`.

- [ ] **Step 4: Build, test**

Run: `./src/compile-local.sh src/interpreter.s interpreter_mac_arm64 && ./scripts/test.sh`
Expected: pass. If failures appear, walk the failing test, dump AST with `scripts/native_ast.sh`, identify any node where `resolvedSlot` is not set when expected.

- [ ] **Step 5: Re-baseline check 5**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p4_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_p4_stage2
diff /tmp/ij_p4_stage1 /tmp/ij_p4_stage2 && echo OK
```
Expected: `OK`.

- [ ] **Step 6: Run verify.sh**

Run: `./scripts/verify.sh`
Expected: all 5 checks PASS.

- [ ] **Step 7: Rebuild MCP**

Run: `./scripts/build.sh`

- [ ] **Step 8: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64 mcp_mac_arm64
git commit -m "perf/p4: slot-indexed local/param Context access"
```

---

### Task 4.3: Benchmark Phase 4

- [ ] **Step 1: Bench**

Run: `./scripts/bench.sh phase4-slots`
Expected: speedup ≥ 1.3× over P3.

- [ ] **Step 2: Drop-rule**

If < 1.3×, revert P4.

- [ ] **Step 3: Commit bench**

```bash
git add bench.log
git commit -m "bench: phase4-slots results"
```

---

## Phase Done — Cleanup

Reached cumulative ≥10× at some phase. Final tidy.

### Task Z.1: Update README perf section

**Files:**
- Modify: `README.md` — the "Self-Hosted Performance" section (~line 416).

- [ ] **Step 1: Append the new phase rows to the table**

Add rows for P1 / P2 / P2.5 / P2.6 / D1-reborn / P3 / P4 (whichever ran) to the speedup table.

- [ ] **Step 2: Add "What Each Phase Actually Does" descriptions**

Mirror the design doc's per-phase descriptions; one paragraph each.

- [ ] **Step 3: Add new "Learnings & Insights" bullets**

Capture surprises learned during the work — esp. anything where measurement contradicted intuition (D4 lesson). The D2-reborn-wrong-shape / D1-reborn-was-the-actual-fix arc is one such lesson.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update perf section with phase1-N results"
```

---

### Task Z.2: Final verify + bench summary

- [ ] **Step 1: Final 5-check run**

Run: `./scripts/verify.sh`
Expected: all 5 PASS.

- [ ] **Step 2: Final bench**

Run: `./scripts/bench.sh final`
Expected: timing block appended. Record cumulative speedup vs phase0-baseline.

- [ ] **Step 3: Commit**

```bash
git add bench.log
git commit -m "bench: final results, total Nx speedup over baseline"
```

- [ ] **Step 4: Squash-merge feature branch to main**

```bash
git checkout main
git merge --no-ff perf/tagged-union-and-typed-ast -m "perf: tagged-union Value + typed AST nodes (+ resolver / D2-reborn / D1-reborn / interning / slot ctx if shipped), Nx faster self-hosted"
git push origin main    # only if user confirms
```

---

## Self-Review Notes (from original plan; trimmed 2026-05-18 alongside the shipped-phase stub-out)

- Phase 3 / Phase 4 / Cleanup tasks above are unchanged from the original 2026-05-16 draft. The shipped phases' detailed step-by-step recipes were collapsed into status pointers (see "Shipped phases" above).
- Secondary benchmark `src/bench_eval.s` was dropped from `scripts/bench.sh` because it runs >5min under Phase 2 codegen. Re-enable only after primary bench hits 10× (Phase Done — Cleanup Task Z.1 should also re-add it then). Recorded in IMPLEMENTATION_PLAN.md P0.
- `Value` field names are stable: `tag`, `b`, `i`, `d`, `s`, `arr`, `m`, `cmd`, `inv` (no `subTag` — the `tReturn` magic-tag approach was rejected in favour of in-band `(Value, bool)` return-sentinel; see IMPLEMENTATION_PLAN.md and design §6.4).
- `Node` field names are stable: `kind`, `op`, `left`, `right`, `list`, `body`, `name`, `iVal`, `dVal`, `bVal`, `sIdx`, `params`, `resolvedKind`, `resolvedSlot`, `resolvedName`, `isStatic`, `hasLocals` (added P2.5), `staticImpl` (added P2.6). `pos` / `sIdx` / `resolvedSlot` / `resolvedName` / `isStatic` are still partially dead — research doc §3.1 audits which are live after P2.5. Phase 3 (`sIdx`) and Phase 4 (`resolvedSlot`) light up the remaining ones; Phase 5 cleanup drops anything still unused.
- Phase 4 Task 4.1 Step 1 should also include `puts("slotCount int32")` in the Node struct field list — needed by Task 4.2's `evalFuncDecl` slot allocation. Documented inline in Task 4.2 Step 3.
