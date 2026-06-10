## Build & Run

Succinct rules for how to BUILD the project:

```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1  # transpile + compile
# Fresh self-builds emit a complete func main() and pass tests.
# COMMITTED BRIDGE (interpreter_mac_arm64) IS the true fixed point as of
# 2026-05-29 (fa1fe55..., NEW emit). A fresh compile-local now byte-equals the
# committed binary (verify.sh check 5 enforces it). The old one-way bridge
# (ac2e6f3) is gone; recover only for forensics: git show 062e95c:interpreter_mac_arm64.
# interpreter_linux_amd64 is STILL the old frozen bridge -> rebuild on a
# linux/Docker host. Default `bench.sh` (no --fresh) now measures current source.
# Honest cumulative since ac2e6f3: 1.25x (pinned head-to-head). 10x needs a
# structural lever (bytecode VM) -> see IMPLEMENTATION_PLAN P-B.
#
# ARITY GOTCHA: positional-arg conv enforces Go arity. IJ source tolerates
# caller-arity != callee-arity (extras dropped; missing params are UNBOUND --
# reads chain-walk to defCtx at read time, usually vInvalid -- NOT vNull-padded).
# CallExpression_toGoDirect falls back to _impl_wrapper([]Value{...}) when
# they mismatch. If you add a new direct-emit code path, preserve this.
#
# IJ_VM=1 runs the program node through the bytecode VM (P-VM.1, opt-in;
# default = tree-walk eval). IJ_VM_DEBUG=1 prints VM compile stats to stderr.
# STAGE GOTCHA: a committed-bridge build (stage1) carries new EMITTERS as data
# but the OLD runtime prelude -- runtime features like IJ_VM are silent no-ops
# on stage1. Test runtime behaviour on STAGE2 (IJ_BINARY=stage1 build), and
# confirm engagement with IJ_VM_DEBUG=1, not just by matching output.
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
- VM differential (IJ_VM=1 must equal default; ~8s): `bash scripts/vm_difftest.sh`
- Verify (5 checks): `bash scripts/verify.sh` (~9–10 min — checks 1–4 fast, check 5 is two `compile-local.sh` runs)
- Bench (committed binary, quick single-run smoke; unreliable for decisions): `bash scripts/bench.sh <label>`. The committed binary is now current source, so this is meaningful again — but still single-run; use `--repeat 3` for decisions.
- Bench source work (builds fixed-point stage2, min/median/max under GOMAXPROCS=1): `bash scripts/bench.sh --fresh --repeat 3 <label>` (~2 fast builds + N×~75s selfhost). Pinned min-of-3 noise band is ~1.01×, so the 1.3× drop-rule is enforceable.
- Re-capture goldens: `bash scripts/verify.sh --capture`

Note: `verify.sh` check 5 now enforces the TRUE fixed point (committed binary == self-transpile output), tightened 2026-05-29 from the old determinism-only check.

## Operational Notes

Refer to [CLAUDE.md](CLAUDE.md) on how to RUN the project.

Key paths (scripts moved from root/ to scripts/):
- `scripts/test.sh`, `scripts/verify.sh`, `scripts/bench.sh`
- `scripts/native_interpreter.sh`, `scripts/interpreter.sh`, `scripts/selfhosted_interpreter.sh`
- `scripts/mcp.sh`, `scripts/native_mcp.sh`