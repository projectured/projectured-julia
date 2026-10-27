# ClaudeCodeACP builds its own binary

> **Status:** step 2 is done. Step 1 is open. The owner agreed to the move on
> 2026-10-27.

## Goal

The native binary `claude-code-acp` is built from the repository
`ClaudeCodeACP.jl` itself. A person who does not use ProjecturEd clones only
that repository to build it. projectured-julia keeps no code that builds it.

## Why

The plan
[acp-is-a-julia-package-and-claude-runs-without-node.md](../done/acp-is-a-julia-package-and-claude-runs-without-node.md)
made ClaudeCodeACP a package of its own, which "also serves programs other
than ProjecturEd". Its step B.10 put the compiled program into the builder of
ProjecturEd, because that builder existed. So the dependency points the wrong
way: a Zed user must check out projectured-julia beside ClaudeCodeACP.jl to
build the binary. The build environment of ProjecturEd uses the released
PackageCompiler, so nothing ties the build to this repository.

## Design

In `ClaudeCodeACP.jl`:

- `compile/ClaudeCodeAcpApp/` is the package that PackageCompiler compiles. It
  has `julia_main`, which sets the log level to warn, makes `SIGTERM` end the
  process in silence, and calls `ClaudeCodeACP.main(ARGS)`. Its
  `@compile_workload` serves a client in the process through `initialize`, as
  the workload of the old build did.
- `compile/Project.toml` is the environment of the build: PackageCompiler.
- `julia compile/build.jl` writes `build/claude-code-acp/`, with the executable
  `build/claude-code-acp/bin/claude-code-acp`. It runs itself again in a Julia
  with `JULIA_PROBE_LIBSTDCXX=0`, so the bundle holds the `libstdc++` of Julia
  and not the one of the machine.
- The README gets a section "Build a native binary".

The build keeps the settings of the old build: incremental, `native` CPU
target, `-O3 -g1`, lazy artifacts. The old build took the generic options of
the front end of ProjecturEd, such as `--no-workload`; the new script takes no
option.

## Steps

1. [ ] **ClaudeCodeACP.jl**, branch `agent-build`: `compile/`, `/build/` in
   `.gitignore`, the README section. Build once and check `--help` and
   `initialize` on the binary.
2. [x] **projectured-julia**, branch `agent-build`: remove
   `bin/build_claude_code_acp`, `source/tool/builder/ClaudeCodeAcpProgram.jl`,
   its exports and include, its row and branch in `BuildCommand.jl`, the
   one-package root of `BuildContext.jl` (only this build used it), its tests,
   and its section of the build guide. The build guide names the new place.
   Run `test_builder()`.
   Done: `test_builder()` passes 553 of 553. `--backends` has its old help text
   again, without "Only for projectured". omnet-julia uses no one-package root.
3. [ ] **Landing**, with the owner's word: push ClaudeCodeACP.jl `main` first,
   because the build guide names its README; then land projectured-julia, and
   move this plan to `plan/done/`.
