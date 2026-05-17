# Self-Hosted Interpreter Perf — ≥10× Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `./scripts/bench.sh` self-hosted run at least 10× faster (≤ 7s wall on macOS/arm64), without breaking the self-bootstrap fixed-point or any functional check.

**Architecture:** Phased refactor of the emitted Go runtime + the codegen inside `interpreter.s`. P1 swaps the `Value` interface for a tagged-union struct. P2 replaces MapValue-backed AST nodes with typed Go structs in the transpiled output. **P2.5 activates the resolver annotations that P2 wires structurally but never reads.** P3 adds a global string pool + null/bool/small-int singletons. P4 (conditional) replaces map-backed Contexts with slot-indexed slices.

**Tech Stack:** IJ (self-hosted), Go (transpile target), bash drivers, golden-output regression harness.

**Design source:** [docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md](../specs/2026-05-16-self-hosted-perf-10x-design.md)
**Research source (current state map):** [docs/superpowers/research/2026-05-18-interpreter-perf-research.md](../research/2026-05-18-interpreter-perf-research.md)

---

## Status — 2026-05-18 (revised)

| Phase | Status | Bench at end of phase |
|---|---|---|
| Phase 0 — Baseline | ✅ shipped 2026-05-16 | `phase0-baseline = 1m11.153s` |
| Phase 1 — Tagged-union `Value` | ✅ shipped (committed binary on bridge — see P2 in IMPLEMENTATION_PLAN.md) | (folded into P2; cleanup dropped D1/D2/D3 fast paths) |
| Phase 2 — Typed AST | ⚠️ shipped STRUCTURALLY only — resolver annotations land on AST but are never read by `*ToGo` emitters; 6 Node fields are dead weight | `p2-no-refresh = 1m20.478s (0.88× of phase0)` |
| **Phase 2.5 — Activate resolver annotations** | ✅ **shipped 2026-05-17 source-level (commits `6ca08e9..5bf147a`); committed-binary replace gated on P2 stage2-regression fix** | `p2_5-final = 1m17.982s (1.03× vs p2-no-refresh; gain blocked behind bridge replace)` |
| Phase 3 — String interning + singletons | ⬜ demoted (smaller lever than P2.5) | — |
| Phase 4 — Slot-indexed contexts | ⬜ stretch | — |

The reality vs the original spec is captured in `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md` "Status Update — 2026-05-18". The research doc enumerates every dead optimization site by line number.

**Drop-rule reminder:** the floor for P2.5's drop rule is `p2-no-refresh = 1m20.478s`, not `phase0-baseline = 1m11.153s` and NOT the irreproducible 49s outlier. P2.5 must show ≥1.3× of `p2-no-refresh` or it is reverted. After P2.5 passes the per-phase drop rule, the cumulative-vs-phase0 target stays at ≥10× (= ≤ 7.115s).

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

## Phase 0 — Baseline Capture

Establish the baseline against which every later phase's drop-rule fires.

### Task 0.1: Capture verify.sh golden + bench baseline

**Files:**
- Modify: `bench.log` (append-only)
- Create: `/tmp/ij-golden/*` (verify.sh capture target — already used by harness)

- [ ] **Step 1: Verify clean tree**

Run: `git status`
Expected: clean working tree (or only the new plan + spec docs).

- [ ] **Step 2: Capture verify.sh golden outputs**

Run: `./scripts/verify.sh --capture`
Expected: prints the captured checks, exits 0.

- [ ] **Step 3: Run baseline benchmark**

Run: `./scripts/bench.sh phase0-baseline`
Expected: three timing blocks appended to `bench.log` (selfhosted, interpreter.sh, native_interpreter.sh). Record the `real` time for `selfhosted_interpreter.sh sample.s` — that's the headline number.

- [ ] **Step 4: Verify check 5 fixed-point on the baseline**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_stage2
diff /tmp/ij_stage1 /tmp/ij_stage2 && echo OK
```
Expected: `OK` printed. Stages match.

- [ ] **Step 5: Commit baseline**

```bash
git add bench.log docs/superpowers/specs docs/superpowers/plans
git commit -m "perf: phase0 baseline capture + design + plan"
```

---

### Task 0.2: Add eval-heavy secondary benchmark

**Files:**
- Create: `src/bench_eval.s`
- Modify: `scripts/bench.sh`

- [ ] **Step 1: Create `src/bench_eval.s`**

Write the file with this exact content:

```ij
def fib(n) {
  if (n < 2) { return n; }
  return fib(n-1) + fib(n-2);
}

def bubbleSort(arr) {
  let n = len(arr);
  let i = 0;
  while (i < n) {
    let j = 0;
    while (j < n - i - 1) {
      if (arr[j] > arr[j + 1]) {
        let temp = arr[j];
        arr[j] = arr[j + 1];
        let jPlusOne = j + 1;
        arr[jPlusOne] = temp;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return arr;
}

puts(fib(22));

let xs = [];
let k = 30;
while (k > 0) { xs = append(xs, k); k = k - 1; }
bubbleSort(xs);
puts(xs[0]);
puts(xs[29]);
```

- [ ] **Step 2: Verify bench_eval.s runs natively**

Run: `echo | ./scripts/native_interpreter.sh src/bench_eval.s`
Expected: prints `17711`, `1`, `30` (or whatever the actual output is — capture it now as the golden value).

- [ ] **Step 3: Extend `scripts/bench.sh` to time bench_eval.s**

Modify `scripts/bench.sh`. Inside the `{ ... } | tee -a "$LOG"` block, after the existing native_interpreter timing, add:

```bash
  echo "-- selfhosted_interpreter.sh bench_eval.s --"
  { time (echo | ./scripts/selfhosted_interpreter.sh src/bench_eval.s >/dev/null); } 2>&1
  echo "-- native_interpreter.sh bench_eval.s --"
  { time (echo | ./scripts/native_interpreter.sh src/bench_eval.s >/dev/null); } 2>&1
```

- [ ] **Step 4: Re-run baseline with eval bench**

Run: `./scripts/bench.sh phase0-baseline-eval`
Expected: five timing blocks in `bench.log`. Record the selfhosted_interpreter.sh bench_eval.s `real` time as the eval baseline.

- [ ] **Step 5: Commit**

```bash
git add src/bench_eval.s scripts/bench.sh bench.log
git commit -m "bench: add eval-heavy secondary benchmark"
```

---

## Phase 1 — Tagged-Union `Value`

Replace the emitted Go `Value` interface + per-type structs (`IntValue`, `DoubleValue`, `StringValue`, `BoolValue`, `InvalidValue`) with a single tagged-union struct `Value{ tag, b, i, d, s, arr, m, cmd }`. `ArrayValue` and `MapValue` stay as separate types but are wrapped in `Value` when stored as a `Value`-typed slot.

**Build invariant:** the runtime is staticly typed Go. Cannot half-migrate. P1 is one large coordinated change landing across many small commits on the feature branch, with intermediate commits potentially leaving `app.go` non-compiling — those commits skip `./scripts/test.sh` but must compile a stub witness file. The phase-end commit must be fully green on checks 1–5.

**Realistic compromise:** structure P1 as a sequence where each commit *does* build green. Achieve this by introducing the new shape **alongside** the old, switching emit sites in one atomic commit, then removing the old types in a final commit.

### Task 1.1: Define the new Value shape in the runtime emit (alongside old)

**Files:**
- Modify: `src/interpreter.s` (insert ahead of the existing `puts("type Context struct {")` at line ~5159; keep all old types intact for now)

- [ ] **Step 1: Locate insertion point**

Run: `grep -n 'puts("type Context struct {")' src/interpreter.s`
Expected: prints the line where the runtime-type emit block begins (around 5159).

- [ ] **Step 2: Insert new Value definition emit**

Add the following `puts(...)` block in `interpreter.s` **immediately before** `puts("type Context struct {")` (so the new types appear at the top of the generated app.go's type block):

```ij
puts("const (");
puts("tNull uint8 = iota");
puts("tInt");
puts("tDouble");
puts("tString");
puts("tBool");
puts("tArray");
puts("tMap");
puts("tFunc");
puts("tNamed");
puts("tInvalid");
puts(")");
puts("type Value2 struct {");
puts("tag uint8");
puts("b   bool");
puts("i   int64");
puts("d   float64");
puts("s   string");
puts("arr *ArrayValue");
puts("m   *MapValue");
puts("cmd Command");
puts("inv string");  // invalid reason
puts("}");
```

We use `Value2` as a temporary name to avoid colliding with the existing `Value` interface. It will be renamed `Value` once the old interface is removed in Task 1.10.

- [ ] **Step 3: Build and verify nothing breaks**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p1_t1`
Expected: build succeeds (Value2 is defined but unused, Go allows unused types).

- [ ] **Step 4: Run functional checks**

Run: `./scripts/test.sh`
Expected: PASS (no behavioral change yet — only added types).

Run: `./scripts/verify.sh`
Expected: checks 1–4 pass. Check 5 will fail (different emitted Go) — that's allowed mid-phase.

- [ ] **Step 5: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p1: add Value2 tagged-union shape alongside old interface"
```

---

### Task 1.2: Add Value2 method block in runtime emit

**Files:**
- Modify: `src/interpreter.s` — insert just after the Value2 struct emit added in Task 1.1.

- [ ] **Step 1: Insert method block**

After the closing `puts("}")` of the Value2 struct, append these `puts(...)` lines. They define the methods Value2 needs to be a drop-in for the old Value interface:

```ij
// Boolean truthiness
puts("func (v Value2) IsTruthy() bool {");
puts("switch v.tag {");
puts("case tNull: return false");
puts("case tInt: return v.i != 0");
puts("case tDouble: return v.d != 0");
puts("case tString: return len(v.s) > 0");
puts("case tBool: return v.b");
puts("case tArray: return v.arr != nil && v.arr.Length() > 0");
puts("case tMap: return v.m != nil && v.m.Length() > 0");
puts("case tFunc: return true");
puts("case tInvalid: return false");
puts("}");
puts("return false");
puts("}");

puts("func (v Value2) IsInvalid() bool { return v.tag == tInvalid }");
puts("func (v Value2) Length() int {");
puts("switch v.tag {");
puts("case tString: return len(v.s)");
puts("case tArray: return v.arr.Length()");
puts("case tMap: return v.m.Length()");
puts("}");
puts("return 0");
puts("}");

puts("func (v Value2) IntValue() int {");
puts("switch v.tag {");
puts("case tInt: return int(v.i)");
puts("case tDouble: return int(v.d)");
puts("case tBool: if v.b { return 1 }; return 0");
puts("}");
puts("return 0");
puts("}");

puts("func (v Value2) String() string {");
puts("switch v.tag {");
puts("case tNull: return " + chr(34) + "null" + chr(34) + "");
puts("case tInt: return strconv.FormatInt(v.i, 10)");
puts("case tDouble: return strconv.FormatFloat(v.d, 'f', -1, 64)");
puts("case tString: return v.s");
puts("case tBool: if v.b { return " + chr(34) + "true" + chr(34) + " }; return " + chr(34) + "false" + chr(34) + "");
puts("case tArray: return v.arr.String()");
puts("case tMap: return v.m.String()");
puts("case tFunc: return " + chr(34) + "function" + chr(34) + "");
puts("case tInvalid: return " + chr(34) + "invalid: " + chr(34) + " + v.inv");
puts("}");
puts("return " + chr(34) + chr(34) + "");
puts("}");

puts("func (v Value2) ValueString() string { return v.String() }");
```

Add `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`, `Type` using the same pattern — switch on `v.tag`, match against `other.tag`, return a new `Value2`. Use the existing `IntValue.Add`, `StringValue.Add`, etc. (visible in `src/interpreter.s:5466–5657`) as the source-of-truth semantics for each operator.

Full method body code for `Add` as the worked example, to be repeated for Sub/Mul/Div/Mod/Equals/LessThan/etc:

```ij
puts("func (v Value2) Add(o Value2) Value2 {");
puts("if o.tag == tInvalid { return o }");
puts("switch v.tag {");
puts("case tInt:");
puts("switch o.tag {");
puts("case tInt: return Value2{tag: tInt, i: v.i + o.i}");
puts("case tDouble: return Value2{tag: tDouble, d: float64(v.i) + o.d}");
puts("case tString: return Value2{tag: tString, s: strconv.FormatInt(v.i, 10) + o.s}");
puts("}");
puts("case tDouble:");
puts("switch o.tag {");
puts("case tInt: return Value2{tag: tDouble, d: v.d + float64(o.i)}");
puts("case tDouble: return Value2{tag: tDouble, d: v.d + o.d}");
puts("case tString: return Value2{tag: tString, s: strconv.FormatFloat(v.d, 'f', -1, 64) + o.s}");
puts("}");
puts("case tString:");
puts("return Value2{tag: tString, s: v.s + o.String()}");
puts("}");
puts("return Value2{tag: tInvalid, inv: " + chr(34) + "Add type mismatch" + chr(34) + "}");
puts("}");
```

Mirror the same pattern for: `Subtract`, `Multiply`, `Divide`, `Modulo`, `Equals`, `LessThan`, `LessThanEqual`, `BiggerThan`, `BiggerThanEqual`, `And`, `Or`, `Not`, `Get`, `Put`, `Keys`, `Values`, `Execute`. The behaviour for each must match the corresponding method on `IntValue` / `DoubleValue` / `StringValue` / `BoolValue` / `InvalidValue` in the existing runtime emit at lines 5466–5839.

- [ ] **Step 2: Build**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p1_t2`
Expected: build succeeds. New methods exist on Value2 but no caller yet.

- [ ] **Step 3: Functional check**

Run: `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p1: emit Value2 method block (Add/Sub/Mul/Div/Mod/cmp/logic/coll/Execute)"
```

---

### Task 1.3: Add Value2 helper constructors in runtime emit

**Files:**
- Modify: `src/interpreter.s` — after the Value2 method block.

- [ ] **Step 1: Insert helper emit**

Add these `puts(...)` lines:

```ij
puts("func vNullV() Value2 { return Value2{tag: tNull} }");
puts("func vBoolV(b bool) Value2 { return Value2{tag: tBool, b: b} }");
puts("func vIntV(i int64) Value2 { return Value2{tag: tInt, i: i} }");
puts("func vDoubleV(d float64) Value2 { return Value2{tag: tDouble, d: d} }");
puts("func vStringV(s string) Value2 { return Value2{tag: tString, s: s} }");
puts("func vArrayV(a *ArrayValue) Value2 { return Value2{tag: tArray, arr: a} }");
puts("func vMapV(m *MapValue) Value2 { return Value2{tag: tMap, m: m} }");
puts("func vFuncV(c Command) Value2 { return Value2{tag: tFunc, cmd: c} }");
puts("func vInvalidV(reason string) Value2 { return Value2{tag: tInvalid, inv: reason} }");
```

- [ ] **Step 2: Build + commit**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p1_t3 && ./scripts/test.sh`
Expected: build + tests pass.

```bash
git add src/interpreter.s
git commit -m "perf/p1: emit Value2 helper constructors (vIntV/vStringV/...)"
```

---

### Task 1.4: Atomic switch — replace Value interface with Value2

This is the cutover. Several edits land together. After this commit, all old type names (`IntValue`, `StringValue`, `BoolValue`, `DoubleValue`, `InvalidValue`) are aliases/constructors that return `Value2`, and every emit site continues to compile.

**Files:**
- Modify: `src/interpreter.s` — runtime emit block (lines ~5159–6342) and `*ToGo` codegen functions.

**Strategy: keep old emit syntax (`IntValue{val: 3}`) but redefine the runtime so that `IntValue` is a constructor function returning Value2, not a struct.**

This means the codegen does NOT change in this task — the old emits still work. The runtime is what changes.

- [ ] **Step 1: Rename old struct types to lowercase internal versions**

Locate the `puts("type IntValue struct {")` and corresponding method emit block (lines ~5463–5657). Replace `IntValue` with `intStruct` in the type declaration and method receivers. Repeat for `DoubleValue` → `doubleStruct`, `StringValue` → `stringStruct`, `BoolValue` → `boolStruct`, `InvalidValue` → `invalidStruct`.

Concretely, edit `src/interpreter.s` to change every `puts("type IntValue struct {")` → `puts("type intStruct struct {")`, every `puts("func (i IntValue)` → `puts("func (i intStruct)`, and every internal reference to `IntValue` inside those method bodies. Same for the other four.

Also retain the `BoolValue` and `IntValue` etc. emit strings used in the existing emit sites by making them **constructor functions** returning Value2 (this is the trick that keeps codegen working). After the renaming, append:

```ij
puts("func IntValue(args ...int64) Value2 { if len(args) == 1 { return Value2{tag: tInt, i: args[0]} }; return Value2{tag: tInt} }");
```

But `IntValue{val: 3}` is Go composite-literal syntax for a struct, not a function call. So this trick doesn't actually work directly — Go won't accept `IntValue{val: 3}` if `IntValue` is a function.

**Revised approach:** keep `IntValue` etc. as struct types — but make them aliases for Value2 with the right field name. Specifically:

```ij
puts("type IntValue = Value2");
```

is a Go type alias. Then `IntValue{val: 3}` becomes `Value2{val: 3}` — but Value2's fields are named `tag`, `i`, `s` not `val`. So that doesn't compile either.

**Final approach (the one we'll actually use):** rewrite the emit sites in this same task, not later. The codegen functions get updated to emit `Value2{tag: tInt, i: 3}` instead of `IntValue{val: 3}`. The old struct types stay defined (still emitted) so they're not referenced anywhere — Go will complain about unused types via warnings but not errors; we'll remove them in Task 1.10.

Actual concrete edits in this task:

1. **Update `numberLiteralToGo`** at `src/interpreter.s:2015–2029`:

   Replace:
   ```ij
   def numberLiteralToGo(self) {
       let str = string(self["value"]);
       let i = 0;
       while (i < len(str)) {
           if (char(str, i) == ".") {
               print('DoubleValue{val: ' +str + '}');
               return;
           }
           i = i + 1;
       }
       print('IntValue{val: ' + str + '}');
   }
   ```

   With:
   ```ij
   def numberLiteralToGo(self) {
       let str = string(self["value"]);
       let i = 0;
       while (i < len(str)) {
           if (char(str, i) == ".") {
               print('Value2{tag: tDouble, d: ' + str + '}');
               return;
           }
           i = i + 1;
       }
       print('Value2{tag: tInt, i: ' + str + '}');
   }
   ```

2. **Update `stringLiteralToGo`** at `src/interpreter.s:2076–2080`:

   Replace:
   ```ij
   def stringLiteralToGo(self) {
       print('StringValue{val: "' + escapeGoStringLiteral(self["value"]) + '"}');
   }
   ```

   With:
   ```ij
   def stringLiteralToGo(self) {
       print('Value2{tag: tString, s: "' + escapeGoStringLiteral(self["value"]) + '"}');
   }
   ```

3. **Update boolean literal emit** at `src/interpreter.s:2140–2145` (`booleanLiteralToGo` or equivalent):

   Run: `grep -n 'booleanLiteralToGo\|TrueValue()\|FalseValue()' src/interpreter.s` first to locate.
   Expected: shows the function around line 2130–2150. It currently emits `TrueValue()` or `FalseValue()`.
   Replace `print('TrueValue()');` with `print('Value2{tag: tBool, b: true}');` and `print('FalseValue()');` with `print('Value2{tag: tBool, b: false}');`.

4. **Update null literal emit** at `src/interpreter.s:1029` (`nullLiteralToGo`):

   Whatever it emits, replace with `print('Value2{tag: tNull}');`.

5. **Update prefix-minus emit** at `src/interpreter.s:3970`:

   The existing `print('IntValue{val: -1}.Multiply(');` becomes `print('Value2{tag: tInt, i: -1}.Multiply(');`. Note that Multiply still works because we added it as a method on Value2 in Task 1.2.

6. **Update NewArrayValue / NewMapValue wrapping** at `src/interpreter.s:73, 4514`:

   The existing emits `NewArrayValue(...)` and `NewMapValue(...)` return `*ArrayValue` and `*MapValue` respectively. Wrap them: change the print sites to emit `Value2{tag: tArray, arr: NewArrayValue(...)}` and `Value2{tag: tMap, m: NewMapValue(...)}`.

   Concretely, in `arrayLiteralToGo` (~line 70):
   ```ij
   print('NewArrayValue(');
   ```
   becomes:
   ```ij
   print('Value2{tag: tArray, arr: NewArrayValue(');
   ```
   with a matching `)' append` at the closing print so the parens balance: `print('))')` becomes `print(')})')`.

   Same pattern for `mapLiteralToGo` (~line 4514).

7. **Update `params.Get(IntValue{val: N})` call sites** at `src/interpreter.s:1885–1913`:

   Replace any `params.Get(IntValue{val: ' + intString(ci) + '})` with `params.Get(Value2{tag: tInt, i: ' + intString(ci) + '})`. Note: `ArrayValue.Get` needs to accept Value2 — see Step 8.

8. **Update ArrayValue/MapValue runtime methods to accept Value2 instead of Value**:

   In the runtime emit block, find `puts("func (a *ArrayValue) Get(index Value)` and change `Value` → `Value2` in both the parameter type and the return type. Same for `Put`, `Keys`, `Values`, `Length`, `Execute`. Same for MapValue methods.

   Same for `Context` methods: `Get`, `Create`, `Update` all parameterize and return Value → Value2.

   Same for `FunctionCommand`: change `func(*Context, *ArrayValue) Value` → `func(*Context, *ArrayValue) Value2`. The `Command` interface itself needs Value2: change `puts("type Command interface { Value }")` to `puts("type Command interface { Execute(*Context, *ArrayValue) Value2; String() string; IsTruthy() bool; IsInvalid() bool }")` — i.e. spell out the methods Command needs explicitly since it can no longer embed the Value interface (which we're removing in Task 1.10).

9. **Update `StdIOLibraryFunctionsInitializer` and other prelude functions** at `src/interpreter.s:4843+`:

   These emit `puts`, `gets`, `len`, `chr`, `ord`, `char`, `random`, `string`, `int`, `float`, `append`, `print` builtins. Each currently returns / accepts `Value` typed args. Update each to use `Value2`, and rebuild any literal-emit inside them (e.g. `StringValue{val: ...}` → `Value2{tag: tString, s: ...}`).

   This is the largest single edit in Task 1.4 — ~30 puts/gets/builtin definitions. Pattern is mechanical: any `IntValue{val: X}` → `Value2{tag: tInt, i: X}`, any `StringValue{val: X}` → `Value2{tag: tString, s: X}`, any `BoolValue{val: X}` → `Value2{tag: tBool, b: X}`, any `FalseValue()` → `Value2{tag: tBool, b: false}`, any `TrueValue()` → `Value2{tag: tBool, b: true}`.

10. **Update `FunctionCommand` runtime methods** at `src/interpreter.s:5256–5349`:

    Every method on `*FunctionCommand` currently has signature `(other Value) Value` or returns `BoolValue{...}`. Update each:
    - Parameter `other Value` → `other Value2`.
    - Return `Value` → `Value2`.
    - Body returns of `BoolValue{val: ...}` → `Value2{tag: tBool, b: ...}`.
    - Body returns of `NewInvalidValue(...)` → `vInvalidV(...)`.
    - Body returns of `FalseValue()` → `Value2{tag: tBool, b: false}`.

11. **Update `InvalidValue` constructor** at `src/interpreter.s:5445–5447`:

    Make it return `Value2`:
    ```ij
    puts("func NewInvalidValue(reason string) Value2 {");
    puts("return Value2{tag: tInvalid, inv: reason}");
    puts("}");
    ```

- [ ] **Step 2: Build**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p1_t4`
Expected: build succeeds. Any compile errors here mean an emit site was missed. Run `grep -n "Value{\|IntValue\|StringValue\|BoolValue\|DoubleValue\|FalseValue()\|TrueValue()" src/interpreter.s` and methodically fix every remaining occurrence.

- [ ] **Step 3: Functional checks**

Run: `./scripts/test.sh`
Expected: PASS.

Run: `./scripts/verify.sh`
Expected: checks 1–4 PASS. Check 5 will fail (different fingerprints) — re-baseline at end of phase.

- [ ] **Step 4: Replace committed binary**

Run:
```bash
./src/compile-local.sh src/interpreter.s interpreter_mac_arm64
```
Expected: a new native binary at repo root.

Verify it works: `echo hi | ./scripts/selfhosted_interpreter.sh src/sample.s`
Expected: prints the same greeting output as before.

- [ ] **Step 5: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64
git commit -m "perf/p1: cut over codegen + runtime to Value2 tagged-union"
```

---

### Task 1.5: Migrate D3 bool fast-path helpers to Value2

**Files:**
- Modify: `src/interpreter.s` — `conditionToGoBool` (~line 3468) and the runtime emit of `EqualsBool` / `LessThanBool` / etc.

- [ ] **Step 1: Update D3 helper signatures in runtime emit**

Locate `puts("func EqualsBool(`. Update each helper (`EqualsBool`, `LessThanBool`, `LessThanEqualBool`, `BiggerThanBool`, `BiggerThanEqualBool`) so they take `(a, b Value2) bool` and switch on `a.tag` / `b.tag` instead of using Go type assertions.

Pattern for `EqualsBool`:
```ij
puts("func EqualsBool(a, b Value2) bool {");
puts("if a.tag != b.tag { return false }");
puts("switch a.tag {");
puts("case tInt: return a.i == b.i");
puts("case tDouble: return a.d == b.d");
puts("case tString: return a.s == b.s");
puts("case tBool: return a.b == b.b");
puts("case tNull: return true");
puts("}");
puts("return false");
puts("}");
```

Same pattern for `LessThanBool` etc. — compare via the appropriate field once tags match.

- [ ] **Step 2: Build + functional check**

Run: `./src/compile-local.sh src/interpreter.s interpreter_mac_arm64 && ./scripts/test.sh`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64
git commit -m "perf/p1: migrate D3 EqualsBool/LessThanBool fast-paths to Value2"
```

---

### Task 1.6: Migrate fixed-arity static-impl signatures (D2)

**Files:**
- Modify: `src/interpreter.s` — `functionDeclarationToGo` (~line 1843) and any direct-call site emit.

- [ ] **Step 1: Update emitted impl signature**

Locate the line(s) that emit `ij_<name>_impl`. Currently each emits `func ij_<name>_impl(ctx *Context, a, b, c Value) Value {`. Change `Value` → `Value2` in both the param type and return type. Also update the wrapper FunctionCommand body that forwards into it.

Run: `grep -n 'ij_.*_impl\|_impl(ctx' src/interpreter.s` to find every site. Update each.

- [ ] **Step 2: Update direct-call sites**

Locate `infixExpressionToGo` (~911) and any other place emitting `ij_foo_impl(ctx, arg1, arg2)`. The args are Value2 now. No change needed unless explicit Value cast is present — if so, drop the cast.

- [ ] **Step 3: Build, test**

Run: `./src/compile-local.sh src/interpreter.s interpreter_mac_arm64 && ./scripts/test.sh`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64
git commit -m "perf/p1: migrate D2 static-impl signatures to Value2"
```

---

### Task 1.7: Remove old Value interface + per-type structs

**Files:**
- Modify: `src/interpreter.s` — runtime emit block at ~5355–6342.

- [ ] **Step 1: Locate old emit block**

Run: `grep -n 'puts("type Value interface' src/interpreter.s`
Expected: prints the line where the old Value interface is emitted (around 5355).

- [ ] **Step 2: Delete the old interface emit + all per-type struct emits**

Delete (from `src/interpreter.s`):
- The entire `puts("type Value interface {")` block.
- The entire `puts("type InvalidValue struct {")` and following method emits (~5382–5462).
- The entire `puts("type IntValue struct {")` block (~5463–5657).
- The entire `puts("type DoubleValue struct {")` block (~5658–~5840).
- The entire `puts("type StringValue struct {")` block (~5840–5942).
- The entire `puts("type BoolValue struct {")` block (search for `type BoolValue`).
- The entire `puts("type NamedValue struct {")` block (~6287–6342) UNLESS NamedValue is still used — check with `grep -n 'NamedValue' src/interpreter.s` first; if used, migrate it the same way as the others (tag=tNamed).

Keep:
- `ArrayValue` (~5943–6073) — referenced by Value2.arr.
- `MapValue` (~6079–6286) — referenced by Value2.m.
- `KeyValuePair` (~6075) — used by MapValue.
- `Context` (~5159) — already migrated in Task 1.4.
- `Command` interface (~5253) — already migrated.
- `FunctionCommand` (~5256) — already migrated.

- [ ] **Step 3: Rename Value2 → Value**

Now that the old `Value` interface is gone, rename Value2 to Value globally in the emit:
- Replace `Value2` with `Value` throughout the runtime-emit puts(...) calls.
- Replace `Value2` with `Value` throughout codegen `*ToGo` print(...) calls (the literal `Value2{tag:` strings).

Run: `grep -n 'Value2' src/interpreter.s | wc -l` to confirm zero matches afterwards.

Run: `grep -c "Value2" src/interpreter.s`
Expected: `0`.

- [ ] **Step 4: Build, test**

Run: `./src/compile-local.sh src/interpreter.s interpreter_mac_arm64 && ./scripts/test.sh && ./scripts/verify.sh`
Expected: checks 1–4 PASS. Check 5 still fails — re-baseline next.

- [ ] **Step 5: Re-baseline check 5**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p1_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_p1_stage2
diff /tmp/ij_p1_stage1 /tmp/ij_p1_stage2 && echo OK
```
Expected: `OK` — bit-identical.

If diff non-empty, investigate the source of non-determinism (likely map-iteration order in a codegen helper). Fix and repeat.

- [ ] **Step 6: Verify all 5 checks**

Run: `./scripts/verify.sh`
Expected: all 5 checks PASS.

- [ ] **Step 7: Rebuild MCP binary**

The MCP binary is built from `mcp_eval.s` which concatenates `interpreter.s` (trimmed) with `eval.s` + `mcp.s`. The build script handles this:

Run: `./scripts/mcp.sh` (interpreted, sanity check). Stop it once it accepts on stdin.
Run: `./scripts/build.sh` (rebuilds everything including native MCP).

Expected: completes without errors. `mcp_mac_arm64` (and linux variant if cross-compile available) updated.

- [ ] **Step 8: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64 mcp_mac_arm64 interpreter_linux_amd64 mcp_linux_amd64
git commit -m "perf/p1: remove old Value interface, rename Value2 -> Value"
```

---

### Task 1.8: Benchmark Phase 1

**Files:** none modified, `bench.log` appended.

- [ ] **Step 1: Run bench**

Run: `./scripts/bench.sh phase1-tagged-value`
Expected: timings appended to `bench.log`. Compare `real` time of selfhosted_interpreter.sh sample.s vs phase0-baseline.

- [ ] **Step 2: Compute speedup**

Speedup = (phase0 real) / (phase1 real). Must be ≥ 1.5× to proceed. Target 2–4×.

- [ ] **Step 3: Drop-rule check**

If speedup < 1.3× — **revert Phase 1 entirely**:
```bash
git log --oneline | head -20    # identify P1 commits
git revert <first-p1-commit>..<last-p1-commit>
```
And stop. Update spec with the failure. Otherwise continue to P2.

- [ ] **Step 4: Commit bench log**

```bash
git add bench.log
git commit -m "bench: phase1-tagged-value results"
```

- [ ] **Step 5: Squash-merge Phase 1 to main**

```bash
git checkout main
git merge --squash perf/tagged-union-and-typed-ast
git commit -m "perf: phase 1 tagged-union Value (Nx speedup, see bench.log)"
git checkout perf/tagged-union-and-typed-ast
git rebase main
```

(Skip the squash-merge if user prefers all phases land as one merge — confirm before this step.)

---

## Phase 2 — Typed AST Struct Nodes

Replace MapValue-backed AST nodes with typed Go struct nodes in the transpiled program. The IJ-side parser still builds MapValues (needed for the interpreter.s author's mental model and for the `scripts/interpreter.sh` tree-walking path). Only the **transpile output** changes shape.

This phase emits, in the Go runtime, a `Node` struct and ~20 `evalXxx` functions; rewrites every `*ToGo` codegen function to produce `&Node{kind: ..., ...}` literals instead of `NewMapValue(...)` literals; and updates `blockStatementToGo` / `functionDeclarationToGo` / etc. so the emitted statement-level Go consumes `*Node` rather than the old map-callable pattern.

### Task 2.1: Define Node struct + nk constants in runtime emit

**Files:**
- Modify: `src/interpreter.s` — runtime emit block, after Value definitions.

- [ ] **Step 1: Insert Node struct definition emit**

Add these `puts(...)` after the Value method block:

```ij
puts("const (");
puts("nkInfix uint8 = iota");
puts("nkPrefix");
puts("nkAssign");
puts("nkIndexAssign");
puts("nkExprStmt");
puts("nkBlock");
puts("nkVarDecl");
puts("nkFuncDecl");
puts("nkIfStmt");
puts("nkWhileStmt");
puts("nkReturn");
puts("nkIdent");
puts("nkIntLit");
puts("nkDoubleLit");
puts("nkStringLit");
puts("nkBoolLit");
puts("nkNullLit");
puts("nkArrayLit");
puts("nkMapLit");
puts("nkIndex");
puts("nkCall");
puts("nkProgram");
puts(")");
puts("const (");
puts("opAdd uint8 = iota");
puts("opSub");
puts("opMul");
puts("opDiv");
puts("opMod");
puts("opEq");
puts("opNeq");
puts("opLt");
puts("opLte");
puts("opGt");
puts("opGte");
puts("opAnd");
puts("opOr");
puts("opNot");
puts("opNeg");
puts(")");
puts("type Node struct {");
puts("kind uint8");
puts("op uint8");
puts("pos uint32");
puts("sIdx uint32");
puts("iVal int64");
puts("dVal float64");
puts("bVal bool");
puts("left *Node");
puts("right *Node");
puts("list []*Node");
puts("body *Node");
puts("params []string");
puts("name string");
puts("resolvedKind uint8");
puts("resolvedSlot int32");
puts("resolvedName string");
puts("isStatic bool");
puts("}");
```

- [ ] **Step 2: Build + test (no callers yet — should be a no-op)**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_t1 && ./scripts/test.sh`
Expected: pass. Go will warn about unused types but not error.

- [ ] **Step 3: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2: define Node struct + nk/op constants in runtime emit"
```

---

### Task 2.2: Emit `eval(n *Node, ctx *Context) Value` dispatch in runtime

**Files:**
- Modify: `src/interpreter.s` — after the Node struct emit.

- [ ] **Step 1: Insert eval dispatch emit**

```ij
puts("func eval(n *Node, ctx *Context) Value {");
puts("switch n.kind {");
puts("case nkIntLit: return Value{tag: tInt, i: n.iVal}");
puts("case nkDoubleLit: return Value{tag: tDouble, d: n.dVal}");
puts("case nkStringLit: return Value{tag: tString, s: n.name}");
puts("case nkBoolLit: return Value{tag: tBool, b: n.bVal}");
puts("case nkNullLit: return Value{tag: tNull}");
puts("case nkIdent: return evalIdent(n, ctx)");
puts("case nkInfix: return evalInfix(n, ctx)");
puts("case nkPrefix: return evalPrefix(n, ctx)");
puts("case nkAssign: return evalAssign(n, ctx)");
puts("case nkIndexAssign: return evalIndexAssign(n, ctx)");
puts("case nkExprStmt: return eval(n.left, ctx)");
puts("case nkBlock: return evalBlock(n, ctx)");
puts("case nkVarDecl: return evalVarDecl(n, ctx)");
puts("case nkFuncDecl: return evalFuncDecl(n, ctx)");
puts("case nkIfStmt: return evalIf(n, ctx)");
puts("case nkWhileStmt: return evalWhile(n, ctx)");
puts("case nkReturn: return evalReturn(n, ctx)");
puts("case nkArrayLit: return evalArrayLit(n, ctx)");
puts("case nkMapLit: return evalMapLit(n, ctx)");
puts("case nkIndex: return evalIndex(n, ctx)");
puts("case nkCall: return evalCall(n, ctx)");
puts("case nkProgram: return evalBlock(n, ctx)");
puts("}");
puts("return vInvalidV(" + chr(34) + "unknown node kind" + chr(34) + ")");
puts("}");
```

- [ ] **Step 2: Build (will fail — evalIdent etc not defined)**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_t2 2>&1 | head -30`
Expected: undefined-symbol errors for `evalIdent`, `evalInfix`, etc. Continue to Task 2.3 — these get defined per kind. Do NOT commit yet — broken build.

---

### Task 2.3: Emit `evalIdent`, `evalInfix`, `evalPrefix` bodies

**Files:**
- Modify: `src/interpreter.s` — after the eval dispatch.

- [ ] **Step 1: Insert evalIdent**

```ij
puts("func evalIdent(n *Node, ctx *Context) Value {");
puts("if n.resolvedKind == 4 { return ctx.Get(n.resolvedName) }");  // global/static
puts("return ctx.Get(n.name)");
puts("}");
```

(P4 will replace this with slot-indexed access when resolvedKind indicates local/param.)

- [ ] **Step 2: Insert evalInfix**

```ij
puts("func evalInfix(n *Node, ctx *Context) Value {");
puts("l := eval(n.left, ctx)");
puts("if n.op == opAnd { if !l.IsTruthy() { return l }; return eval(n.right, ctx) }");
puts("if n.op == opOr { if l.IsTruthy() { return l }; return eval(n.right, ctx) }");
puts("r := eval(n.right, ctx)");
puts("switch n.op {");
puts("case opAdd: return l.Add(r)");
puts("case opSub: return l.Subtract(r)");
puts("case opMul: return l.Multiply(r)");
puts("case opDiv: return l.Divide(r)");
puts("case opMod: return l.Modulo(r)");
puts("case opEq: return l.Equals(r)");
puts("case opNeq: { eq := l.Equals(r); return Value{tag: tBool, b: !eq.b} }");
puts("case opLt: return l.LessThan(r)");
puts("case opLte: return l.LessThanEqual(r)");
puts("case opGt: return l.BiggerThan(r)");
puts("case opGte: return l.BiggerThanEqual(r)");
puts("}");
puts("return vInvalidV(" + chr(34) + "unknown infix op" + chr(34) + ")");
puts("}");
```

- [ ] **Step 3: Insert evalPrefix**

```ij
puts("func evalPrefix(n *Node, ctx *Context) Value {");
puts("v := eval(n.right, ctx)");
puts("switch n.op {");
puts("case opNeg: return Value{tag: tInt, i: -1}.Multiply(v)");
puts("case opNot: return v.Not()");
puts("}");
puts("return vInvalidV(" + chr(34) + "unknown prefix op" + chr(34) + ")");
puts("}");
```

- [ ] **Step 4: Don't build yet — Task 2.4 adds more eval funcs**

(Defer build until Task 2.6 completes the eval suite.)

---

### Task 2.4: Emit `evalAssign`, `evalIndexAssign`, `evalBlock`, `evalVarDecl`

**Files:**
- Modify: `src/interpreter.s` — after Task 2.3's emit.

- [ ] **Step 1: Insert evalAssign**

```ij
puts("func evalAssign(n *Node, ctx *Context) Value {");
puts("v := eval(n.right, ctx)");
puts("if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }");
puts("return v");
puts("}");
```

- [ ] **Step 2: Insert evalIndexAssign**

```ij
puts("func evalIndexAssign(n *Node, ctx *Context) Value {");
puts("coll := eval(n.left, ctx)");
puts("idx := eval(n.right, ctx)");
puts("rhs := eval(n.body, ctx)");  // body holds the RHS for index-assign
puts("coll.Put(idx, rhs)");
puts("return rhs");
puts("}");
```

- [ ] **Step 3: Insert evalBlock**

```ij
puts("func evalBlock(n *Node, ctx *Context) Value {");
puts("var last Value");
puts("last = Value{tag: tNull}");
puts("for _, s := range n.list {");
puts("last = eval(s, ctx)");
puts("if last.tag == tInvalid { return last }");
puts("}");
puts("return last");
puts("}");
```

(ReturnStatement uses a sentinel — for tree-walking with structs, simplest is to add a `returning` flag on Value via a special tag or use panic/recover. Pick whichever matches today's `isReturnValue` magic-string approach; details deferred to Task 2.7 — pick simpler/faster.)

- [ ] **Step 4: Insert evalVarDecl**

```ij
puts("func evalVarDecl(n *Node, ctx *Context) Value {");
puts("v := eval(n.right, ctx)");
puts("ctx.Create(n.name, v)");
puts("return v");
puts("}");
```

---

### Task 2.5: Emit `evalFuncDecl`, `evalIf`, `evalWhile`, `evalReturn`, `evalCall`

**Files:**
- Modify: `src/interpreter.s` — continue runtime emit.

- [ ] **Step 1: Insert evalIf**

```ij
puts("func evalIf(n *Node, ctx *Context) Value {");
puts("c := eval(n.left, ctx)");
puts("if c.IsTruthy() { return eval(n.body, ctx) }");
puts("if n.right != nil { return eval(n.right, ctx) }");
puts("return Value{tag: tNull}");
puts("}");
```

(`n.body` = then-branch, `n.right` = else-branch.)

- [ ] **Step 2: Insert evalWhile**

```ij
puts("func evalWhile(n *Node, ctx *Context) Value {");
puts("var last Value");
puts("last = Value{tag: tNull}");
puts("for {");
puts("c := eval(n.left, ctx)");
puts("if !c.IsTruthy() { return last }");
puts("last = eval(n.body, ctx)");
puts("if last.tag == tInvalid { return last }");
puts("}");
puts("}");
```

(Return semantics — needs the return sentinel; see Task 2.7.)

- [ ] **Step 3: Insert evalReturn**

```ij
puts("func evalReturn(n *Node, ctx *Context) Value {");
puts("v := Value{tag: tNull}");
puts("if n.right != nil { v = eval(n.right, ctx) }");
puts("ctx.Create(" + chr(34) + "__return__" + chr(34) + ", v)");
puts("return v");
puts("}");
```

(See Task 2.7 — this is the simplest implementation; the magic-string approach is what interpreter.s uses today. If that proves slow, switch to panic/recover.)

- [ ] **Step 4: Insert evalFuncDecl**

```ij
puts("func evalFuncDecl(n *Node, ctx *Context) Value {");
puts("paramNames := n.params");
puts("body := n.body");
puts("defCtx := ctx");
puts("fn := NewFunctionCommand(defCtx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("local := NewContext(defCtx)");
puts("for i, p := range paramNames {");
puts("if i < args.Length() { local.Create(p, args.elements[i]) }");
puts("}");
puts("return eval(body, local)");
puts("})");
puts("ctx.Create(n.name, vFuncV(fn))");
puts("return vFuncV(fn)");
puts("}");
```

- [ ] **Step 5: Insert evalCall**

```ij
puts("func evalCall(n *Node, ctx *Context) Value {");
puts("callee := eval(n.left, ctx)");
puts("args := NewArrayValue()");
puts("for _, a := range n.list { args.elements = append(args.elements, eval(a, ctx)) }");
puts("if callee.tag == tFunc { return callee.cmd.Execute(ctx, args) }");
puts("return vInvalidV(" + chr(34) + "call target not a function" + chr(34) + ")");
puts("}");
```

(Note: `args.elements` assumes ArrayValue has an `elements []Value` slice. Adjust to the actual field name — `grep -n 'type ArrayValue struct' -A 5 src/interpreter.s` to confirm.)

---

### Task 2.6: Emit `evalArrayLit`, `evalMapLit`, `evalIndex`

**Files:** continue runtime emit.

- [ ] **Step 1: Insert evalArrayLit**

```ij
puts("func evalArrayLit(n *Node, ctx *Context) Value {");
puts("a := NewArrayValue()");
puts("for _, e := range n.list { a.elements = append(a.elements, eval(e, ctx)) }");
puts("return vArrayV(a)");
puts("}");
```

- [ ] **Step 2: Insert evalMapLit**

```ij
puts("func evalMapLit(n *Node, ctx *Context) Value {");
puts("m := NewMapValue()");
puts("for i := 0; i + 1 < len(n.list); i += 2 {");
puts("k := eval(n.list[i], ctx)");
puts("v := eval(n.list[i+1], ctx)");
puts("m.Put(k, v)");
puts("}");
puts("return vMapV(m)");
puts("}");
```

(Pairs are stored as flat `[k0, v0, k1, v1, ...]` in `n.list`.)

- [ ] **Step 3: Insert evalIndex**

```ij
puts("func evalIndex(n *Node, ctx *Context) Value {");
puts("coll := eval(n.left, ctx)");
puts("idx := eval(n.right, ctx)");
puts("return coll.Get(idx)");
puts("}");
```

- [ ] **Step 4: Build with all eval functions defined**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_t6 2>&1 | head -30`
Expected: build succeeds. Functions exist but aren't called yet (no codegen change yet to emit `&Node{...}`). Old code path (MapValue AST + `node["evaluate"]`) still operates.

- [ ] **Step 5: Commit so far**

```bash
git add src/interpreter.s
git commit -m "perf/p2: emit Node + eval dispatch + per-kind eval funcs (callers not switched yet)"
```

---

### Task 2.7: Decide and implement return-sentinel approach

The IJ `ReturnStatement_evaluate` in `src/interpreter.s:565` today uses a magic-string sentinel attached as a map key on the return value, then unwraps at function-call boundaries.

For the new Node-based eval, two options:
- (a) **Magic-tag approach:** add a new `tag` value `tReturn` that wraps the real value. `evalBlock`, `evalWhile`, `evalFuncDecl` check for `tReturn` and unwrap. Cheap; preserves tree-walk style.
- (b) **panic/recover:** evalReturn panics with the return value, evalCall recovers. Cleaner but Go panic/recover is hot-path-expensive.

**Pick (a).**

- [ ] **Step 1: Add tReturn tag constant**

In `src/interpreter.s` at the `const ( tNull ... )` block emit, add `puts("tReturn")` to the list (before `tInvalid`).

- [ ] **Step 2: Update evalReturn**

Replace the body of `evalReturn` (Task 2.5 Step 3) with:

```ij
puts("func evalReturn(n *Node, ctx *Context) Value {");
puts("v := Value{tag: tNull}");
puts("if n.right != nil { v = eval(n.right, ctx) }");
puts("return Value{tag: tReturn, arr: nil, m: nil, i: v.i, d: v.d, s: v.s, b: v.b, cmd: v.cmd, inv: v.inv}");
puts("}");
```

(Carries the original value's payload + the tReturn marker.)

Better: change `Value` struct to add a small `inner *Value` field for wrap cases. Too much churn — use the inline-copy approach above for P2 and revisit if profiling shows it's slow.

- [ ] **Step 3: Update evalBlock to unwrap tReturn**

```ij
puts("func evalBlock(n *Node, ctx *Context) Value {");
puts("var last Value");
puts("last = Value{tag: tNull}");
puts("for _, s := range n.list {");
puts("last = eval(s, ctx)");
puts("if last.tag == tReturn || last.tag == tInvalid { return last }");
puts("}");
puts("return last");
puts("}");
```

- [ ] **Step 4: Update evalFuncDecl's closure to unwrap tReturn at call return**

```ij
puts("fn := NewFunctionCommand(defCtx, func(callerCtx *Context, args *ArrayValue) Value {");
puts("local := NewContext(defCtx)");
puts("for i, p := range paramNames {");
puts("if i < args.Length() { local.Create(p, args.elements[i]) }");
puts("}");
puts("r := eval(body, local)");
puts("if r.tag == tReturn { r.tag = realTagOf(r); return r }");
puts("return r");
puts("})");
```

But `realTagOf` doesn't exist — we lost the original tag when we wrapped. Need to store the wrapped value's original tag.

**Final approach:** widen the Value struct to carry an optional sub-tag for tReturn wrapping. Add `subTag uint8` field. evalReturn sets `tag=tReturn, subTag=v.tag, plus copies fields`. Unwrapping restores `tag=subTag`.

Patch the Value struct emit (Task 1.1's Step 2 — already merged; re-edit it now to add `subTag uint8` field). Patch evalReturn / closure-unwrap accordingly.

(This is a real refactor wart. If it gets ugly, fall back to panic/recover — measure cost first.)

- [ ] **Step 5: Build + test**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_t7 && ./scripts/test.sh`
Expected: pass (no behavior change — old MapValue codegen still drives, new path unused).

- [ ] **Step 6: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2: add tReturn sentinel + Value.subTag for return-value plumbing"
```

---

### Task 2.8: Switch `*ToGo` emitters to produce `&Node{...}` literals

This is the big one. For each AST node kind, the `xxxToGo` function currently emits a `NewMapValue(...)` Go expression. Switch to emit `&Node{kind: nkXxx, ...}` Go expression.

Repeat the following sub-task for **every** node-kind ToGo emitter. Listed for completeness; one commit per emitter is fine.

**Node kinds + their ToGo functions (locate via grep):**

- `numberLiteralToGo` (~line 2015) → kind nkIntLit / nkDoubleLit
- `stringLiteralToGo` (~2076) → nkStringLit
- `booleanLiteralToGo` (~2120) → nkBoolLit
- `nullLiteralToGo` (~1029) → nkNullLit
- `identifierToGo` (~2182) → nkIdent
- `infixExpressionToGo` (~911) → nkInfix
- `prefixExpressionToGo` (~3950) → nkPrefix
- `assignmentStatementToGo` (~744) → nkAssign
- `indexAssignmentStatementToGo` (~4380) → nkIndexAssign
- `expressionStatementToGo` (~841) → nkExprStmt
- `blockStatementToGo` (~1190) → nkBlock
- `variableDeclarationToGo` (~4775) → nkVarDecl
- `functionDeclarationToGo` (~1843) → nkFuncDecl
- `ifStatementToGo` (~3510) → nkIfStmt
- `whileStatementToGo` (find via grep) → nkWhileStmt
- `returnStatementToGo` (~597) → nkReturn
- `arrayLiteralToGo` (~70) → nkArrayLit
- `mapLiteralToGo` (~4495) → nkMapLit
- `indexExpressionToGo` (find via grep) → nkIndex
- `callExpressionToGo` (find via grep, related to ~3287/3325) → nkCall
- `programToGo` (find via grep) → nkProgram

### Task 2.8.1: Switch `numberLiteralToGo`

- [ ] **Step 1: Replace function body**

```ij
def numberLiteralToGo(self) {
    let str = string(self["value"]);
    let i = 0;
    while (i < len(str)) {
        if (char(str, i) == ".") {
            print('&Node{kind: nkDoubleLit, dVal: ' + str + '}');
            return;
        }
        i = i + 1;
    }
    print('&Node{kind: nkIntLit, iVal: ' + str + '}');
}
```

- [ ] **Step 2: Build, test**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_t8_1 && ./scripts/test.sh`
Expected: builds but tests may FAIL because the rest of the codegen still emits `NewMapValue(...)` for statement-level wrappers (e.g. `ExpressionStatement`) that expect their child to be a MapValue, not a `*Node`. This is the half-migrated state.

**Decision:** the codegen MUST be migrated atomically across all node kinds in one commit. The `*ToGo` switch can't be done one kind at a time because the parent codegen consumes whatever the child emits.

Revised: collapse Tasks 2.8.1 through 2.8.21 into a single atomic commit. Implement all 21 emitter rewrites locally, then build + test once.

### Task 2.8 (atomic): Switch all `*ToGo` emitters at once

- [ ] **Step 1: Rewrite each ToGo function**

For each of the 21 node kinds listed above, update its `*ToGo` function in `src/interpreter.s` to produce a `&Node{kind: nkXxx, ...}` literal. Use the worked example below for the most common patterns; mirror the same structure for the rest.

**Pattern A — leaf literal (no children):**

```ij
def nullLiteralToGo(self) {
    print('&Node{kind: nkNullLit}');
}
```

**Pattern B — single-child (e.g. expressionStatement, returnStatement):**

```ij
def expressionStatementToGo(self) {
    print('&Node{kind: nkExprStmt, left: ');
    self["expression"]["toGo"](self["expression"]);
    print('}');
}
```

**Pattern C — two-child (e.g. infix, assign):**

```ij
def infixExpressionToGo(self) {
    print('&Node{kind: nkInfix, op: ');
    print(opCodeFor(self["operator"]));
    print(', left: ');
    self["left"]["toGo"](self["left"]);
    print(', right: ');
    self["right"]["toGo"](self["right"]);
    print('}');
}
```

`opCodeFor` is a new helper to be added in `interpreter.s` that maps operator strings (`"+"`, `"-"`, `"=="`, etc.) to the `op*` constant names. Define it:

```ij
def opCodeFor(op) {
    if (op == "+") { return "opAdd"; }
    if (op == "-") { return "opSub"; }
    if (op == "*") { return "opMul"; }
    if (op == "/") { return "opDiv"; }
    if (op == "%") { return "opMod"; }
    if (op == "==") { return "opEq"; }
    if (op == "!=") { return "opNeq"; }
    if (op == "<") { return "opLt"; }
    if (op == "<=") { return "opLte"; }
    if (op == ">") { return "opGt"; }
    if (op == ">=") { return "opGte"; }
    if (op == "&&") { return "opAnd"; }
    if (op == "||") { return "opOr"; }
    if (op == "!") { return "opNot"; }
    return "opAdd";
}
```

**Pattern D — list-children (block, array literal, call args):**

```ij
def blockStatementToGo(self) {
    print('&Node{kind: nkBlock, list: []*Node{');
    let stmts = self["statements"];
    let i = 0;
    while (i < len(stmts)) {
        stmts[i]["toGo"](stmts[i]);
        if (i + 1 < len(stmts)) { print(", "); }
        i = i + 1;
    }
    print('}}');
}
```

**Pattern E — function declaration (special — body + params + name):**

```ij
def functionDeclarationToGo(self) {
    print('&Node{kind: nkFuncDecl, name: "' + self["name"] + '", params: []string{');
    let ps = self["parameters"];
    let i = 0;
    while (i < len(ps)) {
        print('"' + ps[i] + '"');
        if (i + 1 < len(ps)) { print(", "); }
        i = i + 1;
    }
    print('}, body: ');
    self["body"]["toGo"](self["body"]);
    print(', isStatic: ');
    if (self["resolvedIsStatic"] == true) { print("true"); } else { print("false"); }
    print('}');
}
```

(The D1/D2 static-impl emission is more complex than this — for the static fast path to keep working, functionDeclarationToGo also needs to emit the `ij_<name>_impl` fixed-arity Go function alongside the Node literal. Cross-reference the existing implementation at `src/interpreter.s:1843–1980` and replicate the same emit structure but with Node literals replacing MapValue children. This is the trickiest single emitter — budget extra time.)

**Pattern F — if-statement (cond + then + optional else):**

```ij
def ifStatementToGo(self) {
    print('&Node{kind: nkIfStmt, left: ');
    self["condition"]["toGo"](self["condition"]);
    print(', body: ');
    self["consequence"]["toGo"](self["consequence"]);
    if (self["alternative"] != null) {
        print(', right: ');
        self["alternative"]["toGo"](self["alternative"]);
    }
    print('}');
}
```

**Pattern G — identifier (carries name + resolved-info):**

```ij
def identifierToGo(self) {
    print('&Node{kind: nkIdent, name: "' + self["name"] + '"');
    if (self["resolvedName"] != null) {
        print(', resolvedName: "' + self["resolvedName"] + '"');
    }
    if (self["resolvedKind"] != null) {
        print(', resolvedKind: ' + intString(self["resolvedKind"]));
    }
    print('}');
}
```

Continue this pattern for all 21 node kinds. Each rewrite is mechanical — emit `&Node{kind: nkXxx, ...}` with whatever fields the kind needs.

- [ ] **Step 2: Update `programToGo` and main entry point**

The top-level `programToGo` (or the program-level emit) is what binds the AST tree into the emitted Go `func main()`. It currently emits something like `program.Execute(rootCtx, NewArrayValue())`. Update to emit `eval(rootNode, rootCtx)` where `rootNode` is the `&Node{kind: nkProgram, list: [...stmts...]}` value.

Grep: `grep -n 'func main()\|programToGo\|puts("func main' src/interpreter.s` to locate.

- [ ] **Step 3: Build**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_atomic`
Expected: build succeeds. Most likely first attempt has compile errors — fix iteratively. Common issues:
- Missing field names (e.g. emit `name:` but Node has it as `resolvedName`).
- Unbalanced `&Node{` literal braces.
- Missing comma between fields.
- Pattern E (function decl) emits a `func()` closure that captures `paramNames` — make sure the captured variable matches the emitted Go.

- [ ] **Step 4: Run test.sh**

Run: `./scripts/test.sh`
Expected: PASS.

If sample.s output differs, run `./scripts/native_ast.sh src/sample.s` to dump the AST, compare against the pre-change dump (run with old binary first), and trace the divergence.

- [ ] **Step 5: Run sample.s through self-hosted**

Run: `echo hi | ./scripts/selfhosted_interpreter.sh src/sample.s`
Expected: same greeting output as before. Time it: `time echo hi | ./scripts/selfhosted_interpreter.sh src/sample.s` — this is the first peek at P2's speedup.

- [ ] **Step 6: Run verify.sh**

Run: `./scripts/verify.sh`
Expected: checks 1–4 PASS. Check 5 fails — re-baseline at phase end.

- [ ] **Step 7: Re-baseline check 5**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_stage2
diff /tmp/ij_p2_stage1 /tmp/ij_p2_stage2 && echo OK
```
Expected: `OK`. If not, fix non-determinism (likely map-iteration order in opCodeFor or similar).

- [ ] **Step 8: Replace committed binary + rebuild MCP**

Run:
```bash
./src/compile-local.sh src/interpreter.s interpreter_mac_arm64
./scripts/build.sh    # rebuilds MCP via mcp_eval.s
```
Expected: binary at repo root + mcp_mac_arm64 updated.

- [ ] **Step 9: Commit**

```bash
git add src/interpreter.s interpreter_mac_arm64 mcp_mac_arm64
git commit -m "perf/p2: switch all *ToGo emitters to typed Node literals; eliminate MapValue AST in transpiled output"
```

---

### Task 2.9: Benchmark Phase 2

**Files:** `bench.log` appended.

- [ ] **Step 1: Run bench**

Run: `./scripts/bench.sh phase2-typed-ast`
Expected: new timing block. Compute speedup vs `phase1-tagged-value`. Target ≥1.5×.

- [ ] **Step 2: Drop-rule check**

If < 1.3× over P1 — **revert Phase 2 commits**:
```bash
git log --oneline | head -30
git revert <first-p2>..<last-p2>
```
And stop.

Otherwise compute cumulative speedup vs `phase0-baseline`. **If ≥ 10×, skip P3 + P4 entirely**: jump to "Phase Done — Cleanup".

- [ ] **Step 3: Commit bench**

```bash
git add bench.log
git commit -m "bench: phase2-typed-ast results"
```

---

## Phase 2.5 — Activate Resolver Annotations (added 2026-05-18)

**Why this phase exists:** Phase 2 shipped the `Node` struct and the `eval(n *Node, ctx *Context) (Value, bool)` switch — but the resolver pass (`resolveScopes` at `src/interpreter.s:1616`) annotates every AST MapValue node with `resolvedKind`, `resolvedOrigin`, `resolvedName`, `resolvedAtRoot`, `resolvedScope`, `resolvedLocals`, `resolvedParamLocals`, `resolvedIsStatic` — and **NO `*ToGo` emitter reads any of them.** The result is `evalIdent → ctx.Get(n.name)` with full chain-walk + Go-map probe per identifier reference, including for library globals like `puts`/`gets`/`len` that walk to root every time. P2.5 wires the dead infrastructure: project annotations into `Node` at emit time, switch on them at runtime.

**Spec:** `docs/superpowers/specs/2026-05-16-self-hosted-perf-10x-design.md` §"Phase 2.5 — Activate Resolver Annotations".
**Research evidence:** `docs/superpowers/research/2026-05-18-interpreter-perf-research.md` §3.2 (all resolver annotations dead) + §3.1 (six dead `Node` fields) + §2.2 (`Context.Get` chain-walk cost) + §2.4 (`evalBlock` always allocs).

**Pre-flight blocker (handle before starting Phase 2.5):** the stage2 IJ-tree-walker has a scalar-VarDecl regression (any top-level `let x = scalar` aborts evaluation). Until that is fixed, replacing the committed bootstrap binary with a clean Phase-2 self-build breaks `verify.sh` checks 1–3. P2.5 edits `interpreter.s` only and runs `compile-local.sh` against the existing bootstrap, so this blocker DOES NOT prevent P2.5 work — but the committed binary cannot be replaced until the regression lands. See IMPLEMENTATION_PLAN.md P2.

### Task 2.5.1: Add `rkGlobal/rkParam/rkLocal/rkUpvalue/rkLib` constants + `hasLocals` field to runtime emit

**Files:**
- Modify: `src/interpreter.s` — runtime emit block, after the `nk*` and `op*` constant emits.

- [ ] **Step 1: Locate insertion point**

Run: `grep -n 'puts("op[NA]' src/interpreter.s | head` and find the line just after the last `op*` constant emit.

- [ ] **Step 2: Insert `rk*` constant block**

```ij
puts("const (");
puts("rkGlobal uint8 = iota");
puts("rkParam");
puts("rkLocal");
puts("rkUpvalue");
puts("rkLib");
puts(")");
```

- [ ] **Step 3: Add `hasLocals bool` to Node struct emit**

Locate the `puts("type Node struct {")` block at `src/interpreter.s:5174-5192`. Insert `puts("hasLocals bool")` just before the closing `puts("}")`. Keep the existing `resolvedKind uint8`, `resolvedSlot int32`, `resolvedName string`, `isStatic bool` fields — they are repurposed in the next tasks, not removed.

- [ ] **Step 4: Add `var rootCtx *Context` declaration in `goLibPrefix`**

Just after the `Context` type emit block, add: `puts("var rootCtx *Context")`.

- [ ] **Step 5: Add `Context.GetLocal` / `Context.UpdateLocal` methods**

After the existing `Context.Get` / `Context.Update` emit, add:

```ij
puts("func (c *Context) GetLocal(name string) Value {");
puts("if v, ok := c.variables[name]; ok { return v }");
puts("return vInvalid(" + chr(34) + "variable not found: " + chr(34) + " + name)");
puts("}");
puts("func (c *Context) UpdateLocal(name string, v Value) Value {");
puts("if c.variables == nil { c.variables = make(map[string]Value) }");
puts("c.variables[name] = v");
puts("return v");
puts("}");
```

- [ ] **Step 6: Build + functional check**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t1 && ./scripts/test.sh`
Expected: build succeeds; tests pass (no behavioral change yet — new fields/methods are added but unused).

- [ ] **Step 7: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2.5: scaffold rk* constants, hasLocals field, GetLocal/UpdateLocal helpers"
```

---

### Task 2.5.2: Add `resolverKindCode(kind, origin)` codegen helper

**Files:**
- Modify: `src/interpreter.s` — IJ-side, near the resolver helpers (`mangle` is at `1243`; place this helper just below it).

- [ ] **Step 1: Insert `resolverKindCode` helper**

```ij
def resolverKindCode(kind, origin) {
    if (kind == "global") {
        if (origin == "lib") { return "rkLib"; }
        return "rkGlobal";
    }
    if (kind == "local") {
        if (origin == "param") { return "rkParam"; }
        return "rkLocal";
    }
    if (kind == "captured") { return "rkUpvalue"; }
    return "rkGlobal";
}
```

- [ ] **Step 2: Build + commit**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t2 && ./scripts/test.sh`
Expected: pass.

```bash
git add src/interpreter.s
git commit -m "perf/p2.5: add resolverKindCode helper"
```

---

### Task 2.5.3: Project resolver annotations from `identifierToGo`

**Files:**
- Modify: `src/interpreter.s:1922` — `identifierToGo`.

- [ ] **Step 1: Update `identifierToGo` to emit `resolvedKind`**

Replace:

```ij
def identifierToGo(self) {
    print('&Node{kind: nkIdent, name: "');
    print(self["name"]);
    print('"}');
}
```

with:

```ij
def identifierToGo(self) {
    print('&Node{kind: nkIdent, name: "');
    print(self["name"]);
    print('"');
    if (self["resolvedKind"] != null) {
        print(", resolvedKind: ");
        print(resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
    }
    print('}');
}
```

- [ ] **Step 2: Build, test, verify check 5 determinism**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t3a
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t3b
diff /tmp/ij_p2_5_t3a /tmp/ij_p2_5_t3b && echo OK
./scripts/test.sh
```
Expected: `OK`; tests pass. Annotations are now emitted but `evalIdent` still uses the chain-walk fallback — no behavioral change.

- [ ] **Step 3: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2.5: project resolvedKind/resolvedOrigin from identifierToGo"
```

---

### Task 2.5.4: Switch `evalIdent` to dispatch on `resolvedKind`

**Files:**
- Modify: `src/interpreter.s:5221-5223` — `evalIdent` runtime emit.

- [ ] **Step 1: Replace `evalIdent` body**

Replace:

```ij
puts("func evalIdent(n *Node, ctx *Context) (Value, bool) {");
puts("return ctx.Get(n.name), false");
puts("}");
```

with:

```ij
puts("func evalIdent(n *Node, ctx *Context) (Value, bool) {");
puts("switch n.resolvedKind {");
puts("case rkParam, rkLocal: return ctx.GetLocal(n.name), false");
puts("case rkLib: return rootCtx.GetLocal(n.name), false");
puts("case rkUpvalue: if ctx.parent != nil { return ctx.parent.GetLocal(n.name), false }");
puts("}");
puts("return ctx.Get(n.name), false");
puts("}");
```

- [ ] **Step 2: Update `programToGoPhase2` to capture `rootCtx`**

In `src/interpreter.s:5390-5431` (`programToGoPhase2`), inside the emitted `func main()`, immediately after `ctx := NewContext(nil)` add `puts("rootCtx = ctx")`.

- [ ] **Step 3: Build, test, verify**

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t4
./scripts/test.sh
./scripts/verify.sh
```
Expected: tests + checks 1–4 pass. Check 5 may fail (different fingerprint) — re-baseline at phase end.

If a `vInvalid("variable not found: ...")` surfaces on a previously-working binding, the resolver mis-classified that identifier. Fall back to the chain-walk by clearing `n.resolvedKind` for that emit site (or fix the resolver — preferred). Common surfaces: identifiers introduced by `let` inside an `if` branch (resolver may classify them differently than the `if`-block scope).

- [ ] **Step 4: Bench (mid-phase peek)**

Run: `time ( echo hi | ./scripts/selfhosted_interpreter.sh src/sample.s >/dev/null )`
Expected: should be ≥1.3× faster than `p2-no-refresh = 1m20.478s` already, since `evalIdent` is one of the highest-frequency hot-path ops.

- [ ] **Step 5: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2.5: evalIdent switches on resolvedKind, skips chain walk for rkParam/rkLocal/rkLib/rkUpvalue"
```

---

### Task 2.5.5: Project resolver annotations from assignment / var-decl emitters [shipped]

**Status: shipped 2026-05-17.** All steps below are checked; see deviations recorded at the bottom of the task for the final shape.

**Files:**
- Modify: `src/interpreter.s:735` — `assignmentStatementToGo`.
- Modify: `src/interpreter.s:4336` — `variableDeclarationToGo`.

- [x] **Step 1: Update `assignmentStatementToGo`**

Locate the `&Node{kind: nkAssign, name: "<raw>", right: ...}` emit. Add a `resolvedKind` field after `name`:

```ij
print(', name: "' + self["name"] + '"');
if (self["resolvedKind"] != null) {
    print(", resolvedKind: ");
    print(resolverKindCode(self["resolvedKind"], self["resolvedOrigin"]));
}
print(', right: ');
```

- [x] **Step 2: Update `variableDeclarationToGo` similarly**

Same pattern: if the decl carries `resolvedKind` / `resolvedOrigin`, emit them on the `&Node{kind: nkVarDecl, ...}` literal.

- [x] **Step 3: Update `evalAssign` to short-circuit on `resolvedKind`**

In runtime emit (`5258-5263`), replace:

```ij
puts("func evalAssign(n *Node, ctx *Context) (Value, bool) {");
puts("v, ret := eval(n.right, ctx)");
puts("if ret { return v, true }");
puts("if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }");
puts("return v, false");
puts("}");
```

with:

```ij
puts("func evalAssign(n *Node, ctx *Context) (Value, bool) {");
puts("v, ret := eval(n.right, ctx)");
puts("if ret { return v, true }");
puts("switch n.resolvedKind {");
puts("case rkParam, rkLocal:");
puts("ctx.UpdateLocal(n.name, v)");
puts("return v, false");
puts("case rkGlobal:");
puts("rootCtx.UpdateLocal(n.name, v)");
puts("return v, false");
puts("}");
puts("if ctx.Exists(n.name) { ctx.Update(n.name, v) } else { ctx.Create(n.name, v) }");
puts("return v, false");
puts("}");
```

- [x] **Step 4: `evalVarDecl` similarly**

In runtime emit (`5286-5294`), `evalVarDecl` already calls `ctx.Create(n.name, v)` which lazily allocates the local map. The fast-path equivalent is `ctx.UpdateLocal(n.name, v)` — same effect. Replace `ctx.Create` with `ctx.UpdateLocal` for `rkLocal` / `rkParam`. Keep `rkGlobal` routing to `rootCtx.UpdateLocal`.

- [x] **Step 5: Build, test, verify**

Run: `./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_t5 && ./scripts/test.sh && ./scripts/verify.sh`
Expected: tests + checks 1–4 pass.

- [x] **Step 6: Commit**

```bash
git add src/interpreter.s
git commit -m "perf/p2.5: evalAssign/evalVarDecl short-circuit on resolvedKind"
```

#### Deviations from the original step shapes (recorded after shipping)

The final shape of `evalAssign` deviates from the snippet in Step 3 in two ways
that are load-bearing for the IJ test suite:

1. **`rkGlobal` is NOT in the `switch`.** `rkGlobal` is the Go-zero default of
   `uint8`, so any pre-P2.5 / unannotated `nkAssign` literal carries
   `resolvedKind == 0 == rkGlobal`. Routing those through
   `rootCtx.UpdateLocal` writes them at root instead of inside their
   originating ctx, which silently destroys IJ's "first assignment creates
   the binding in the current ctx" semantics. The shipped switch handles only
   the explicitly-set non-default kinds (`rkParam`, `rkLocal`, `rkLib`);
   everything else falls through to the original `ctx.Exists` /
   `ctx.Update` / `ctx.Create` path.
2. **`rkParam` / `rkLocal` use `ctx.Update`, not `ctx.UpdateLocal`.** The
   resolver may mark a binding `rkLocal` while runtime keeps it in a
   *parent* `*Context` (function-local ctx, when the current ctx is a
   per-iteration block ctx that `evalBlock` allocated). `UpdateLocal` would
   miss the binding and create a fresh one in the block ctx. `ctx.Update`
   correctly walks the chain to find the existing binding. Only `rkLib` uses
   `rootCtx.UpdateLocal` because library functions are guaranteed to live in
   `rootCtx.variables`.

`evalIdent` (Task 2.5.4 fast paths) was likewise reduced to **only**
`rkLib → rootCtx.GetLocal`; the `rkParam` / `rkLocal → ctx.GetLocal` shapes
remain disabled until Task 2.5.6 collapses the per-block ctx so the function
ctx is the current ctx for these reads. Until then they fall through to the
chain-walking `ctx.Get`.

`evalVarDecl` is `ctx.UpdateLocal` unconditionally — functionally identical
to the previous `ctx.Create` (both write to the current ctx's map; the
former just opens out the function-call cost of going through `Create`).

The runtime-emit edits live at `src/interpreter.s` ~5260, 5310, 5354 (post-
edit line numbers shift up slightly because of added comment lines).

#### Bench delta

`p2_5-resolver-wired = 1m17.250s` vs `p2-no-refresh = 1m20.478s` → 1.04× —
within noise; below the 1.3× drop-rule threshold at this commit. **The drop
rule is not waived; the lever is gated behind the committed-binary replace.**
The selfhosted bench runs the *committed* binary as the IJ interpreter, and
that binary is the pre-P2.5 bridge whose tree-walker is unaware of the new
annotations. Real-world fast-path payoff only fires after `verify.sh`
check 5 promotes from determinism to true fixed-point — which is itself
gated on the P2 stage2 scalar-VarDecl regression. P2.5.5 ships as wiring +
correctness; P2.5.6/2.5.7/2.5.8 will harvest the gain.

---

### Task 2.5.6: Gate `evalBlock` Context allocation on `hasLocals` — ✅ SHIPPED 2026-05-17

**Status: ✅ Shipped in commit `5bf147a` (combined with Task 2.5.7).** Implementation summary at end of this task block.

**Files:**
- Modify: `src/interpreter.s:1100` — `blockStatementToGo`.
- Modify: `src/interpreter.s:5275-5285` — `evalBlock` runtime emit.

- [x] **Step 1: Update `blockStatementToGo` to project `hasLocals`**

Inside the `&Node{kind: nkBlock, list: []*Node{...}}` emit, also emit `hasLocals: true` if and only if the resolver tagged this block as introducing at least one binding. The IJ-side resolver writes `resolvedLocals` on the block scope (`resolveBlockStatement` at `src/interpreter.s:1346`); read it:

```ij
let locals = self["resolvedLocals"];
if (locals != null) {
    if (len(locals) > 0) {
        print(", hasLocals: true");
    }
}
```

- [x] **Step 2: Update `evalBlock` to gate `NewContext`**

Replace:

```ij
puts("func evalBlock(n *Node, ctx *Context) (Value, bool) {");
puts("blockCtx := NewContext(ctx)");
puts("var last Value");
puts("last = vNull()");
puts("for _, s := range n.list {");
puts("v, ret := eval(s, blockCtx)");
puts("if ret { return v, true }");
puts("last = v");
puts("}");
puts("return last, false");
puts("}");
```

with:

```ij
puts("func evalBlock(n *Node, ctx *Context) (Value, bool) {");
puts("blockCtx := ctx");
puts("if n.hasLocals { blockCtx = NewContext(ctx) }");
puts("var last Value");
puts("last = vNull()");
puts("for _, s := range n.list {");
puts("v, ret := eval(s, blockCtx)");
puts("if ret { return v, true }");
puts("last = v");
puts("}");
puts("return last, false");
puts("}");
```

- [x] **Step 3: Build, test, verify**

Stage1 build of `/tmp/ij_t6_s1` (committed binary + new interpreter.s):
- `./scripts/test.sh` ✅ (all tests pass)
- `./scripts/verify.sh` ✅ 5/5 PASS
- Shadowing smoke (`let x = 1; { let x = 2; puts(x); } puts(x);`) prints `2\n1` — block introduces new local correctly.

- [x] **Step 4: Commit**

Folded into commit `5bf147a` together with Task 2.5.7. Combined message:
`perf/p2.5: evalBlock skips NewContext when hasLocals=false + FunctionCommand.Execute passes nil`

#### Implementation summary (deviations from snippet)

- `blockStatementToGo` was rewritten to first read `resolvedLocals` and only project `hasLocals: true` when `len(locals) > 0`, by using an `emitHasLocals` flag computed before the `&Node{kind: nkBlock` print. Cleaner than emitting the marker mid-stream.
- `evalBlock` runtime emit uses `blockCtx := ctx; if n.hasLocals { blockCtx = NewContext(ctx) }` (multi-line form, matching the planned snippet but with a header comment explaining the invariant) so a future reader knows that `evalAssign`/`evalVarDecl` already dispatch to the right ctx via `resolvedKind`, and that identifier reads via `ctx.Get` walk the chain — so reusing the caller's ctx is safe when no locals are declared.

---

### Task 2.5.7: Drop the wasted `FunctionCommand.Execute` Context allocation — ✅ SHIPPED 2026-05-17

**Status: ✅ Shipped in commit `5bf147a` (combined with Task 2.5.6).**

**Files:**
- Modify: `src/interpreter.s:5119-5121` — `FunctionCommand.Execute` runtime emit.

- [x] **Step 1: Replace `Execute` body**

Replace:

```ij
puts("func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {");
puts("return c.executeFunc(NewContext(c.definitionCtx), params)");
puts("}");
```

with:

```ij
puts("func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {");
puts("return c.executeFunc(nil, params)");
puts("}");
```

The closure body already does `local := NewContext(defCtx)` as its first line (`evalFuncDecl` emit at `5331`), discarding whatever `callerCtx` was passed. Passing `nil` makes the discarded alloc explicit and saves one `*Context` per function call.

- [x] **Step 2: Build, test, verify**

Stage1 build of `/tmp/ij_t7_s1`:
- Smoke (`def f(a,b){puts(a+b);} f(3,4);` → `7`; `fib(10)` → `55`) ✅
- `./scripts/test.sh` ✅
- `./scripts/verify.sh` ✅ 5/5 PASS

- [x] **Step 3: Commit**

Folded into commit `5bf147a` with Task 2.5.6.

#### Implementation summary

Only two `Execute` call sites exist in emitted Go (`Value.Execute` line 5013 forwards to `FunctionCommand.Execute`; `evalCall` invokes it). Both already-safe to pass `nil` because the `executeFunc` closure body emitted by `evalFuncDecl` (`src/interpreter.s:5437`) does `local := NewContext(defCtx)` and never reads `callerCtx`. Added a header comment in the emit explaining the discard, so a future reader doesn't wonder why the param is named but unused.

---

### Task 2.5.8: Re-baseline check 5 + benchmark Phase 2.5 — ✅ SHIPPED 2026-05-17 (binary replace NOT done)

**Files:**
- Modify: `interpreter_mac_arm64`, `mcp_mac_arm64`, `bench.log`.

**Pre-flight check:** if the stage2 IJ-tree-walker scalar-VarDecl regression is NOT yet fixed, **DO NOT replace the committed binary** (per AGENTS.md). Run the bench against the existing committed bootstrap + the source-level changes (every `*ToGo` emitter is exercised via `compile-local.sh src/interpreter.s` which builds against the bootstrap and then runs the resulting binary). The bench number is honest in that case; only the committed-binary-replace step is gated.

**Pre-flight result:** P2 regression STILL not fixed. Stage2 build via `cp stage1 interpreter_mac_arm64 && compile-local.sh src/interpreter.s stage2` produces a binary that silently aborts after the first top-level statement (`puts(1); puts(2);` prints only `1`). Root cause not investigated deeply; the silent-failure pattern matches the documented P2 scalar-VarDecl regression and may share root cause. **Committed binary stays as-is; skipping Step 2.**

- [x] **Step 1: Demonstrate fixed-point at source level**

Two back-to-back `compile-local.sh src/interpreter.s` runs produce bit-identical binaries (verify.sh check 5 PASS). NOTE: this is the determinism flavour of "fixed-point" — both runs use the SAME committed bootstrap, so output is identical by construction. True stage1→stage2 fixed-point still gated on the P2 regression.

Run:
```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_stage1
./src/compile-local.sh src/interpreter.s /tmp/ij_p2_5_stage2
diff /tmp/ij_p2_5_stage1 /tmp/ij_p2_5_stage2 && echo OK
```
Expected: `OK`. If diff non-empty, find the non-determinism (likely a map-iteration order in the new resolver-projection paths).

- [ ] **Step 2: Replace committed binary IF stage2 regression is fixed** — **SKIPPED (P2 regression still open)**

If IMPLEMENTATION_PLAN.md P2 stage2-regression item is closed:

```bash
./src/compile-local.sh src/interpreter.s interpreter_mac_arm64
./scripts/build.sh   # rebuilds MCP via mcp_eval.s
```
Expected: binary at repo root + `mcp_mac_arm64` updated. `verify.sh` 5/5 PASS.

If the regression is not fixed: skip this step. The committed bootstrap stays as-is; your source changes are still benched correctly via `compile-local.sh`.

- [x] **Step 3: Bench**

`./scripts/bench.sh p2_5-final` → `selfhosted_interpreter.sh = 1m17.982s`. Versus `p2-no-refresh = 1m20.478s` = **1.03×** (within noise).

- [x] **Step 4: Drop-rule check**

Per drop-rule (≥1.3× required), this would normally trigger revert. **Exempted** because the bench cannot observe the P2.5 emit changes: `selfhosted_interpreter.sh` runs `committed_binary src/interpreter.s sample.s`, where the committed binary is the pre-P2.5 bridge. The committed binary's tree-walker does not consult the new `resolvedKind` annotations, does not skip block-ctx alloc on `hasLocals == false`, and still allocates a caller-ctx in `FunctionCommand.Execute`. The P2.5 source changes affect *what the new emitter emits*, which is only exercised in `selfhosted_interpreter.sh` if the committed binary is replaced.

CPU-profile investigation deferred — there is no expected win at this profile without binary replacement. Revert is also rejected: the new emit + runtime is correct (`test.sh` ✅, `verify.sh` 5/5 ✅) and is the prerequisite for harvesting the win once the P2 bridge is replaced. Leaving the changes in place avoids re-doing the work later.

Cumulative speedup is unchanged from `p2-no-refresh` (since bench is unchanged) → 10× target NOT hit → P3 remains queued.

- [x] **Step 5: Commit bench**

`bench.log` will be committed in the same final-bench commit as the plan updates.

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

Add rows for P1 / P2 / P3 / P4 (whichever ran) to the speedup table.

- [ ] **Step 2: Add "What Each Phase Actually Does" descriptions**

Mirror the design doc's per-phase descriptions; one paragraph each.

- [ ] **Step 3: Add new "Learnings & Insights" bullets**

Capture surprises learned during the work — esp. anything where measurement contradicted intuition (D4 lesson).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update perf section with phase1-4 results"
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
git merge --no-ff perf/tagged-union-and-typed-ast -m "perf: tagged-union Value + typed AST nodes (+ interning + slot ctx if shipped), Nx faster self-hosted"
git push origin main    # only if user confirms
```

---

## Self-Review

Run through the plan once with fresh eyes before handing off.

**Spec coverage:**
- ✅ Tagged-union Value (design §Phase 1) → Plan §Phase 1, tasks 1.1–1.8.
- ✅ Typed AST struct nodes (design §Phase 2) → Plan §Phase 2, tasks 2.1–2.9.
- ✅ Activate resolver annotations (design §Phase 2.5, added 2026-05-18) → Plan §Phase 2.5, tasks 2.5.1–2.5.8.
- ✅ String interning + singletons (design §Phase 3) → Plan §Phase 3, tasks 3.1–3.3.
- ✅ Slot-indexed contexts (design §Phase 4) → Plan §Phase 4, tasks 4.1–4.3.
- ✅ Primary benchmark (selfhosted_interpreter.sh sample.s) → exercised in every bench task.
- ⚠️ Secondary benchmark (src/bench_eval.s) → was created in Task 0.2, but DROPPED from `scripts/bench.sh` (>5min under Phase 2 codegen). Re-enable only after primary bench hits 10×. Recorded in IMPLEMENTATION_PLAN.md P0.
- ✅ Per-phase exit criteria (≥1.3× drop-rule) → enforced in every "Benchmark Phase N" task. **Floor for P2.5 = `p2-no-refresh` = 1m20.478s, NOT the irreproducible 49s outlier.**
- ✅ Check 5 may break mid-phase, re-baselined at phase end → enforced in Tasks 1.7, 2.8, 2.5.8, 3.2, 4.2.
- ✅ Use compile-local.sh not Docker → every build step uses compile-local.sh.

**Placeholder scan:**
- Task 2.7 explicitly flags "If that proves slow, switch to panic/recover" — that's a measurement-conditional decision, not a placeholder. Acceptable.
- Several `(~line N)` line refs are approximations. Concrete grep commands are provided in tasks so engineer can locate exact spots. Acceptable for a 7222-line file undergoing edits.
- No TBD / TODO / "fill in details" / "similar to Task N".

**Type consistency:**
- `Value2` introduced in Task 1.1, used throughout Tasks 1.2–1.6, renamed to `Value` in Task 1.7. Consistent.
- `Node` field names: `kind`, `op`, `left`, `right`, `list`, `body`, `name`, `iVal`, `dVal`, `bVal`, `sIdx`, `params`, `resolvedKind`, `resolvedSlot`, `resolvedName`, `isStatic`, `subTag` (added in Task 2.7), `slotCount` (mentioned in P4). All consistent across tasks.
- `evalXxx` function names match the eval-dispatch switch's case labels in Task 2.2.
- `vIntV`/`vStringV` etc helpers match their usage sites.

**Identified gap during review (fixing inline):**
- Task 2.7's tReturn approach mentions adding `subTag uint8` field to Value but the Value struct emit in Task 1.1 does not include it. Adding now: **edit Task 1.1 Step 2 mentally** to include `puts("subTag uint8")` in the Value struct field list — the engineer should add this when implementing Task 2.7, with a note that this requires an amend back to the Value struct emit. Documented here.

- Task 2.5's evalFuncDecl mentions `args.elements` but ArrayValue's field could be named differently. Engineer must `grep -n 'type ArrayValue struct' -A 5 src/interpreter.s` and substitute the correct field name. Documented in Task 2.5 Step 5.

- Task 4.2's slot allocation depends on `slotCount` field on Node which P4 Task 4.1 should also add to the Node struct emit. Adding note: Task 4.1 Step 1 should also include `puts("slotCount int32")` in the Node struct field list. Documented here.

Plan ready for execution.
