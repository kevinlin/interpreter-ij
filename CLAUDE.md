# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A self-hosting interpreter + transpiler for the IJ language. `src/interpreter.s` is the interpreter, written in IJ. The committed native binaries (`interpreter_{mac_arm64,linux_amd64}`) were produced by transpiling `src/interpreter.s` to Go and compiling with `go build`. The interpreter can transpile itself, so the build is a bootstrap loop.

Repo layout:
- `src/*.s` — IJ source: `interpreter.s` (transpiler + tree-walker), `eval.s` + `mcp.s` (MCP server overlay), `test.s`, `sample.s`.
- `src/*.sh` — compile, verify, bench, MCP, and native driver scripts.
- `*.sh` at root — convenience drivers (`build.sh`, `interpreter.sh`, `selfhosted_interpreter.sh`, `test.sh`).
- `interpreter_{mac_arm64,linux_amd64}`, `mcp_{mac_arm64,linux_amd64}` — committed native binaries at repo root.
- No `go.mod`; transpiled Go is emitted as a single `app.go` and built directly.

## Common commands

```bash
# Run an IJ script with the native interpreter (fastest)
echo | ./src/native_interpreter.sh src/sample.s
echo "puts(22/7.0)" | ./src/native_interpreter.sh           # stdin program

# Run via the IJ-implemented interpreter (native runs interpreter.s, which runs your script)
echo | ./interpreter.sh src/sample.s

# Run via the self-hosted interpreter (interpreter inside interpreter — slow perf benchmark)
echo hi | ./selfhosted_interpreter.sh src/sample.s

# Dump AST as JSON
./src/native_ast.sh src/sample.s     # uses pre-built binary
./ast.sh src/sample.s            # uses interpreter.s

# Test suite (regression suite written in IJ)
./test.sh
# or:  echo | ./src/native_interpreter.sh src/test.s

# 5-check regression harness — run after any change to interpreter.s
./src/verify.sh                # compares against /tmp/ij-golden
./src/verify.sh --capture      # (re)capture golden outputs

# Benchmark (appends timings to ./bench.log)
./bench.sh [label]
```

Compile IJ to a native binary:

```bash
# Host-local Go toolchain, no Docker. Exits non-zero on failure.
./src/compile-local.sh src/sample.s sample_binary

# Reproducible cross-compile via Docker
./src/compile-mac.sh   src/sample.s sample_mac_arm64
./src/compile-linux.sh src/sample.s sample_linux_amd64

# Generic current-platform compile (older path, less strict error handling)
./src/compile.sh src/sample.s sample_binary

# Full rebuild: re-transpile interpreter.s twice (self-bootstrap), run tests,
# rebuild MCP. Silently skips the Go build when Docker is unreachable.
./build.sh
```

MCP server (LLM-callable IJ eval over stdio JSON-RPC):

```bash
./src/mcp.sh         # interpreted (rebuilds mcp_eval.s and runs it)
./src/native_mcp.sh  # pre-built native binary
```

## Big-picture architecture

### Pipeline

IJ source → `interpreter.s` → (lex → parse → AST as nested maps) → either **evaluate** (tree-walk) or **transpile** to Go. The Go path emits a self-contained `app.go` plus a small shell wrapper that pipes it through `go build`. The native interpreter binary at repo root is the Go-build output of `interpreter.s` going through that same pipeline — it is the chicken that laid itself.

### Stdin sentinel protocol

`interpreter.s` reads source from stdin, with leading/trailing sentinel lines selecting the mode. All wrappers (`native_interpreter.sh`, `interpreter.sh`, `ast.sh`, etc.) inject the markers around the user's file:

| Marker (last line) | Mode |
|---|---|
| `//<EOF>` | Evaluate (default) — remaining stdin is `gets()` input |
| `//<AST>` | Emit AST as JSON, do not evaluate |
| `//<GO>` | Emit Go source for the program body, do not evaluate |
| `//<GO2>` | Emit a `bash` script that writes `app.go` (full prelude + body + suffix + `go build app.go`) |

`//multiline` is the leading marker that switches the reader into multi-line collect mode. Compile scripts feed `//multiline … //<GO2>` and pipe the resulting shell script through `bash` to produce `app.go` and the binary. See `src/interpreter.s:6989` (`readSources`).

### MCP server build

`src/mcp.sh` strips the bootstrap suffix from `interpreter.s` via `until.rb "interpreter is ready"` to make `interpreter_base.s`, then concatenates with `eval.s` + `mcp.s` into `mcp_eval.s` and runs it. The native MCP binary is built by transpiling `mcp_eval.s` (see `build.sh`). `eval.s` and `mcp.s` override `gets`/`puts`/`StdIOLibraryFunctionsInitializer` so the inner-interpreter can be fed scripts and have its output captured per JSON-RPC request — i.e. MCP is a second consumer of the same transpiler and is sensitive to the IJ "override pattern" (`let oldX = X; def X(...) { ... }`).

### Performance machinery in the transpiler

A resolver pass annotates AST nodes with whether identifiers are parameters, local `let`s, captured upvalues, or top-level globals. The Go emitter uses these annotations to:

- Replace `ctx.Get("x")` / `ctx.Update("x", …)` with direct Go variable access.
- For function bodies that have no nested `def`, no dynamic lookups, and no global writes, mark `resolvedIsStatic=true` and emit `ij_<name>_impl(ctx, args…)` fixed-arity Go functions. Direct call sites bypass `FunctionCommand.Execute`/`NewArrayValue`.
- A `lastDefIndex` pre-pass tolerates the override pattern (`let oldX = X; def X(...) { oldX(...) }`) without emitting duplicate impls.
- `if`/`while` condition slots use raw-`bool` helpers (`EqualsBool`, `LessThanBool`, …) that avoid heap-allocating a `BoolValue`.
- Arithmetic was tried and **reverted** — the helper indirection regressed the benchmark.

If you touch the transpiler, the load-bearing invariant is that two consecutive `compile-local.sh interpreter.s …` runs produce **bit-identical** binaries. `verify.sh` check 5 enforces this.

## Verification discipline

`verify.sh` runs five checks and exits non-zero on any regression:

1. `test.s` via `interpreter.sh` matches golden.
2. `test.s` via `selfhosted_interpreter.sh` matches golden.
3. `sample.s` via `selfhosted_interpreter.sh` matches golden.
4. Native MCP JSON-RPC responses match golden.
5. **Double self-transpile fixed-point** — `compile-local.sh interpreter.s` twice; binaries must be bit-identical.

Run `./src/verify.sh --capture` once on a clean baseline before working on a perf or codegen change so checks 1–4 have a golden to diff against. Check 5 needs no golden.
- Check 5 needs `compile-local.sh` (Docker-less). The Docker-backed `compile-mac.sh` will silently skip the Go build step if the Docker daemon is unreachable, which would mask regressions — `build.sh` has this same hazard. Use `compile-local.sh` for any verification that needs hard failures.

## Language quirks worth remembering

- IJ string literals do **not** support `\"` escapes. To embed `"` inside emitted code, concatenate `chr(34)`. This bites code that does `puts("…")` of Go source.
- Top-level `let oldX = X; def X(...) { oldX(...) }` is the IJ idiom for overriding a builtin or earlier `def`. The transpiler is aware of it (see `lastDefIndex`); MCP relies on it. Any codegen change must preserve it.
- AST nodes are `MapValue`s with `evaluate`/`toJson`/`toGo` callable entries — IJ has no closures-over-self other than via `self` being passed as the first arg.
- For scripts that don't call `gets()`, prefix invocations with `echo |` so stdin is closed and the script doesn't block.

## Current branch state

The recent commit history (`983eadb`, `e173a27`, `16d5423`, `1be072c`, `58ec0e9`) is a perf-tuning sequence — see the README's *Self-Hosted Performance* section for the C1–D3 phase details and the dropped D4 regression.
