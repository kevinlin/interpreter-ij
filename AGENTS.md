## Build & Run

Succinct rules for how to BUILD the project:

```bash
./src/compile-local.sh src/interpreter.s /tmp/ij_stage1  # transpile + compile
# Fresh self-builds emit a complete func main() and pass tests.
# COMMITTED BRIDGE (interpreter_mac_arm64) IS the true fixed point (since
# 2026-05-29; 28df121d... after P-VM.5b). A fresh compile-local
# byte-equals the committed binary (verify.sh check 5 enforces it). Recover the
# old one-way bridge only for forensics: git show 062e95c:interpreter_mac_arm64.
# interpreter_linux_amd64 is STILL the old frozen bridge -> rebuild on a
# linux/Docker host. mcp_mac_arm64 rebuilt with P-VM.5b (d990cae7...).
# Default `bench.sh` measures current source.
# P-VM.5b (2026-06-12): lean 40-byte Value; selfhost 27.51s -> 20.61s = 1.33x.
# Remaining to <=7s goal: 2.9x -> P-VM.5c (chunk bails + Value.Get/dispatch).
#
# LEAN VALUE (P-VM.5b): emitted Value struct has NO d/arr/m/cmd/inv fields.
# Payloads: double = v.f() (Float64bits in i), invalid msg = v.s, and
# arr/m/cmd share unsafe.Pointer p via v.arrp()/v.mp()/v.cmdp(). Constructors
# (vDouble/vArray/vMap/vFunc/vInvalid) unchanged in name -- emit those, never
# struct literals with removed fields. fix_app_go.py "already present?" guards
# are NEWLINE-ANCHORED: goLibPrefix now emits EqualsBool/New*AsValue itself,
# and their text appears as string literals in the transpiled body -- an
# unanchored guard false-positives and skips the stage1 injection.
#
# NEW-BUILTIN GOTCHA: once a commit adds a builtin (getenv, hasKey, ...), OLD
# binaries cannot interpret NEW source (undefined variable). Bench controls
# for an old commit must run old binary + OLD SOURCE from `git worktree add
# /tmp/ctrl <old-sha>` -- IJ_BINARY=<old> alone panics on new source.
# Adding a builtin = goLibPrefix ijb_* impl + ctx.Create + libraryFunctionNames
# + interpreted-layer chain (e.g. twoWrapper in *LibraryFunctionsInitializer);
# replace the committed binary in the same commit.
# Hot builtins also get a direct-emit fast path: libFastEmitName table ->
# CallExpression_toGoDirect emits ijb_<name>(args) for resolvedOrigin=="lib"
# callees with exact arity (skips the Execute/NewArrayValue shim).
# CPU profile: IJ_CPUPROFILE=/tmp/x.pprof is wired into the emitted main().
#
# ARITY GOTCHA: positional-arg conv enforces Go arity. IJ source tolerates
# caller-arity != callee-arity (extras dropped; missing params are UNBOUND --
# reads chain-walk to defCtx at read time, usually vInvalid -- NOT vNull-padded).
# CallExpression_toGoDirect falls back to _impl_wrapper([]Value{...}) when
# they mismatch. If you add a new direct-emit code path, preserve this.
#
# TWO bytecode VMs, both default-on: the Go-side VM (P-VM.3) runs the native
# layer's top-level program; the IJ-side VM (P-VM.4, `ijvm*` defs) runs every
# INTERPRETED layer's program + function chunks. IJ_VM=0 disables both at all
# nesting depths (getenv builtin chains down); IJ_VM_IJ=0 disables only the
# IJ-side VM. IJ_VM_DEBUG=1 prints [vm] (Go-side) + [ijvm] (IJ-side, one line
# per interpreted layer) compile stats to stderr. eputs = stderr puts builtin.
# Tree-walker still load-bearing: escape hatches + 12 ijvm chunk bails.
# Go toolchain: go1.26.4 EXACTLY (embedded in the binary -- any other version
# breaks check 5 byte-identity). If `go` vanishes from PATH: ~/sdk/go1.26.4/bin.
# STAGE GOTCHA: a committed-bridge build (stage1) carries new EMITTERS as data
# but the OLD runtime prelude -- runtime features like the VM gate are silent
# no-ops on stage1. Test runtime behaviour on STAGE2 (IJ_BINARY=stage1 build),
# and confirm engagement with IJ_VM_DEBUG=1, not just by matching output.
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
- VM differential (default VM must equal IJ_VM=0 eval; ~25s incl. a fresh MCP build): `bash scripts/vm_difftest.sh` (honours `IJ_BINARY=<stage2>` — use it to test VM changes BEFORE replacing the committed binary; stage1 is parity-blind)
- Verify (5 checks): `bash scripts/verify.sh` (~1–2 min since P-VM.4/5a — checks 1–4 fast, check 5 is two `compile-local.sh` runs)
- Bench (committed binary, quick single-run smoke; unreliable for decisions): `bash scripts/bench.sh <label>`. The committed binary is now current source, so this is meaningful again — but still single-run; use `--repeat 3` for decisions.
- Bench source work (builds fixed-point stage2, min/median/max under GOMAXPROCS=1): `bash scripts/bench.sh --fresh --repeat 3 <label>` (~2 fast builds + N×~21s selfhost since P-VM.5b). Pinned min-of-3 noise band is ~1.01×, so the 1.3× drop-rule is enforceable.
- Re-capture goldens: `bash scripts/verify.sh --capture`

Note: `verify.sh` check 5 now enforces the TRUE fixed point (committed binary == self-transpile output), tightened 2026-05-29 from the old determinism-only check.

## Operational Notes

Refer to [CLAUDE.md](CLAUDE.md) on how to RUN the project.

Key paths (scripts moved from root/ to scripts/):
- `scripts/test.sh`, `scripts/verify.sh`, `scripts/bench.sh`
- `scripts/native_interpreter.sh`, `scripts/interpreter.sh`, `scripts/selfhosted_interpreter.sh`
- `scripts/mcp.sh`, `scripts/native_mcp.sh`