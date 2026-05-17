## Build & Run

Succinct rules for how to BUILD the project:

```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1  # transpile + compile
# DO NOT cp /tmp/ij_stage1 interpreter_mac_arm64 yet — the committed binary is
# a bridge artifact (see IMPLEMENTATION_PLAN.md P2). Fresh self-builds produce
# a binary that lacks func main() due to a Phase 2 evalAssign closure-scope bug.
# If you accidentally overwrite, run `git restore interpreter_mac_arm64`.
```

## Validation

Run these after implementing to get immediate feedback:

- Tests: `bash scripts/test.sh` (~3s)
- Verify (5 checks): `bash scripts/verify.sh` (~9–10 min — checks 1–4 fast, check 5 is two `compile-local.sh` runs)
- Bench: `bash scripts/bench.sh <label>` (~80–90s, appends to `bench.log`)
- Re-capture goldens: `bash scripts/verify.sh --capture`

Caveat: `verify.sh` check 5 currently validates determinism (same binary → same output twice), NOT true fixed-point. See IMPLEMENTATION_PLAN P2.

## Operational Notes

Refer to [CLAUDE.md](CLAUDE.md) on how to RUN the project.

Key paths (scripts moved from root/ to scripts/):
- `scripts/test.sh`, `scripts/verify.sh`, `scripts/bench.sh`
- `scripts/native_interpreter.sh`, `scripts/interpreter.sh`, `scripts/selfhosted_interpreter.sh`
- `scripts/mcp.sh`, `scripts/native_mcp.sh`