## Build & Run

Succinct rules for how to BUILD the project:

```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1  # transpile + compile
cp /tmp/ij_stage1 interpreter_mac_arm64                   # install binary
```

## Validation

Run these after implementing to get immediate feedback:

- Tests: `bash scripts/test.sh`
- Verify (5 checks): `bash scripts/verify.sh`
- Re-capture goldens: `bash scripts/verify.sh --capture`

## Operational Notes

Refer to [CLAUDE.md](CLAUDE.md) on how to RUN the project.

Key paths (scripts moved from root/ to scripts/):
- `scripts/test.sh`, `scripts/verify.sh`, `scripts/bench.sh`
- `scripts/native_interpreter.sh`, `scripts/interpreter.sh`, `scripts/selfhosted_interpreter.sh`
- `scripts/mcp.sh`, `scripts/native_mcp.sh`