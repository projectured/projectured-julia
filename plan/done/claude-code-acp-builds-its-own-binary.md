# ClaudeCodeACP builds its own binary

> **Status:** done. The owner agreed to the move on 2026-10-27, and said to
> land it on the same day.

## Goal

The native binary `claude-code-acp` is built from the repository
`ClaudeCodeACP.jl` itself. A person who does not use ProjecturEd clones only
that repository to build it. projectured-julia keeps no code that builds it.

## Why

The plan
[acp-is-a-julia-package-and-claude-runs-without-node.md](acp-is-a-julia-package-and-claude-runs-without-node.md)
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

1. [x] **ClaudeCodeACP.jl**, branch `agent-build`: `compile/`, `/build/` in
   `.gitignore`, the README section. Build once and check `--help` and
   `initialize` on the binary.
   Done in `ccae6b5`, on Julia 1.13.1 and PackageCompiler 2.4.3:
   - The build takes about 2 minutes, with a peak of 9.0 to 9.5 GB. A cap of
     8 GB ends it with an out-of-memory kill in the compile of the system
     image. The bundle is 595 MB; the old build gave 573 MB.
   - The binary answers `--help` and `initialize` in 0.23 to 0.44 s. The old
     binary took 0.23 s and 1.7 s. `SIGTERM` ends it with nothing on the
     standard error.
   - The bundle holds the `libstdc++` of Julia (6.0.34), not the newer one of
     the machine (6.0.35).
   - The script resolves the app before `create_app` and does not delete its
     manifest. Without a manifest, PackageCompiler warns "it is not
     recommended to create an app/library without a preexisting manifest".
   - No version of ClaudeCodeACP is needed: `src/` does not change.
2. [x] **projectured-julia**, branch `agent-build`: remove
   `bin/build_claude_code_acp`, `source/tool/builder/ClaudeCodeAcpProgram.jl`,
   its exports and include, its row and branch in `BuildCommand.jl`, the
   one-package root of `BuildContext.jl` (only this build used it), its tests,
   and its section of the build guide. The build guide names the new place.
   Run `test_builder()`.
   Done: `test_builder()` passes 553 of 553. `--backends` has its old help text
   again, without "Only for projectured". omnet-julia uses no one-package root.
3. [x] **Landing**, with the owner's word: push ClaudeCodeACP.jl `main` first,
   because the build guide names its README; then land projectured-julia, and
   move this plan to `plan/done/`.
   Done on 2026-10-27: ClaudeCodeACP.jl `main` is `ccae6b5`, pushed. The branch
   of projectured-julia landed on `main` as a fast-forward.
