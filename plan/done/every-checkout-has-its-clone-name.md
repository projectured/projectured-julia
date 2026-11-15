# Every checkout has its clone name

A checkout that a `[sources]` path names has the folder name that a plain
`git clone` gives it. Then a person clones the repositories beside
`projectured-julia` with no folder argument, and the CI workflow moves each one
under the same name.

## The folders

| Folder before | Folder after | Repository |
| --- | --- | --- |
| `agent-client-protocol` | `AgentClientProtocol.jl` | projectured/AgentClientProtocol.jl |
| `auto-integration` | `AutoIntegration.jl` | projectured/AutoIntegration.jl |
| `claude-code-acp` | `ClaudeCodeACP.jl` | projectured/ClaudeCodeACP.jl |
| `model-context-protocol` | `ModelContextProtocol.jl` | projectured/ModelContextProtocol.jl |
| `package-compiler-reactive` | `PackageCompiler.jl`, branch `reactive` | projectured/PackageCompiler.jl |

The names of programs and build products do not change: the binary
`claude-code-acp`, `build/claude-code-acp/` and `bin/build_claude_code_acp`.

## Steps

1. [x] Change the paths in `projectured-julia` and `omnet-julia`, on the branch
   `clone-names` of each: the `[sources]`, the tracked manifests, the CI
   workflow, the default source folder of the `claude-code-acp` build, and the
   guides.
2. [x] Move the folders. Remove the worktree `package-compiler-reactive`, check
   out `reactive` in `package-compiler`, rename the five folders, and repair the
   link of the worktree `package-compiler-parallel`.
3. [x] Fast-forward `main` of both repositories to `clone-names`. Apply the
   commit to each other worktree, and change the paths in the untracked
   manifests.
4. [x] Check: no `[sources]` path is missing, `environment/build` of
   `omnet-julia` resolves and writes the IDE app, and `environment/all` of
   `projectured-julia` instantiates.
5. [x] Make `reactive` the default branch of projectured/PackageCompiler.jl.

## Facts found on the way

- The `project_hash` of a manifest includes the `[sources]` of its project. A
  change of a source path thus makes `Pkg.instantiate` warn that the manifest
  is stale. `Pkg.resolve()` in `environment/all` changed only that hash line.
- The permission check blocks the fast-forward of `main`. The owner runs the
  two `git merge --ff-only clone-names` commands.
- `git apply --3way` of the commit failed in the worktrees
  `projectured-julia-release` and `projectured-julia-task-slice`, because their
  branches are older and lack `release-guide.md`. The same substitutions,
  applied by content, changed them. The manifest hash of
  `environment/all` in `projectured-julia-task-slice` was stale before the
  change, so it stays as it was.
- Eight untracked manifests held the old paths: the alias environments
  `environment/all` of `omnet-julia` and `inet-julia`, `environment/build` of
  `omnet-julia`, `ProjecturedACPTest`, and four app packages under `build/app/`.
  Only their `path` lines changed.
- The check: the walk of the `[sources]` finds no missing path in 208 projects.
  `environment/build` resolves and writes the IDE app with `compile = false`,
  and `PackageCompiler` loads from `PackageCompiler.jl`. The three alias
  environments instantiate with no warning.
- The gate scripts of the reactive compiler still default to
  `package-compiler-reactive`. They take `PC=`, so they did not change.
