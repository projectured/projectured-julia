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
2. [ ] Move the folders. Remove the worktree `package-compiler-reactive`, check
   out `reactive` in `package-compiler`, rename the five folders, and repair the
   link of the worktree `package-compiler-parallel`.
3. [ ] Fast-forward `main` of both repositories to `clone-names`. Apply the
   commit to each other worktree, and change the paths in the untracked
   manifests.
4. [ ] Check: no `[sources]` path is missing, `environment/build` of
   `omnet-julia` resolves and writes the IDE app, and `environment/all` of
   `projectured-julia` instantiates.
5. [ ] Make `reactive` the default branch of projectured/PackageCompiler.jl.
