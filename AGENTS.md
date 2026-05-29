## Build & Run

Succinct rules for how to BUILD the project:

```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1  # transpile + compile
# Fresh self-builds emit a complete func main() and pass tests.
# Stage2 selfhost trajectory (pinned GOMAXPROCS=1 min-of-3): N+6 214.42s ->
# N+7 75.61s (ctxGet/mapHasKey hot-path reorder, 2.84x, 2026-05-29). Stage2 is
# now BELOW the committed bridge -> the "drops below ~2m" precondition for
# replacing the committed binary is MET. Bridge replacement is still a
# DELIBERATE, separately-verified step (capture committed pinned min-of-3
# head-to-head first); it was intentionally NOT done in the N+7 commit. Until
# then the committed bridge stays canonical; if you accidentally overwrite it,
# run `git restore interpreter_mac_arm64`.
#
# ARITY GOTCHA: positional-arg conv enforces Go arity. IJ source tolerates
# caller-arity != callee-arity (extras dropped, missings vNull-pad).
# CallExpression_toGoDirect falls back to _impl_wrapper([]Value{...}) when
# they mismatch. If you add a new direct-emit code path, preserve this.
#
# IJ_BINARY overrides the BRIDGE binary in compile-local.sh and the runtime
# binary in native_interpreter.sh. Build a fixed point WITHOUT touching the
# committed binary (no more cp/restore dance):
#   ./src/compile-local.sh src/interpreter.s /tmp/s1                 # committed bridge -> stage1
#   IJ_BINARY=/tmp/s1 ./src/compile-local.sh src/interpreter.s /tmp/s2  # stage1 bridge  -> stage2
#   IJ_BINARY=/tmp/s2 ./src/compile-local.sh src/interpreter.s /tmp/s3  # stage2 bridge  -> stage3
#   cmp /tmp/s2 /tmp/s3   # true fixed point: must be byte-identical
```

## Validation

Run these after implementing to get immediate feedback:

- Tests: `bash scripts/test.sh` (~3s)
- Verify (5 checks): `bash scripts/verify.sh` (~9–10 min — checks 1–4 fast, check 5 is two `compile-local.sh` runs)
- Bench (committed binary, quick smoke; unreliable for decisions): `bash scripts/bench.sh <label>`
- Bench source work (builds fixed-point stage2, min/median/max): `bash scripts/bench.sh --fresh --repeat 3 <label>` (~2 builds + N×~150s selfhost). Use this for any perf decision — plain `bench.sh` measures the frozen committed binary, not your changes.
- Re-capture goldens: `bash scripts/verify.sh --capture`

Caveat: `verify.sh` check 5 currently validates determinism (same binary → same output twice), NOT true fixed-point. See IMPLEMENTATION_PLAN P2.

## Operational Notes

Refer to [CLAUDE.md](CLAUDE.md) on how to RUN the project.

Key paths (scripts moved from root/ to scripts/):
- `scripts/test.sh`, `scripts/verify.sh`, `scripts/bench.sh`
- `scripts/native_interpreter.sh`, `scripts/interpreter.sh`, `scripts/selfhosted_interpreter.sh`
- `scripts/mcp.sh`, `scripts/native_mcp.sh`