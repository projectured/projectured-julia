# Projectured native executable

This directory builds a **standalone native binary** of a Projectured editor with
PackageCompiler.jl. The build is *configurable*: a `BuildSpec` chooses which kind
of editor gets baked in (which document domain, with or without the workbench,
file-backed or not) and which display backend(s) are compiled in — and whether the
backend choice is fixed ("baked in") or selectable at runtime ("delayed").

## Building

The build interface is a plain Julia function, `build_executable` (in the
[`ProjecturedBuilder`](../../../package/ProjecturedBuilder/) package) — there is no CLI and no build script.
Name the backend by its real type, so load its package first (`using ProjecturedSdl`
for `SdlBackend`, `using ProjecturedWeb` for `WebBackend`; `ConsoleBackend` comes with
`Projectured`). The repository root environment resolves both packages:

```julia
using ProjecturedSdl, ProjecturedBuilder     # julia --project=environment/all
```

### The two shipping configurations

```julia
build_executable(workbench_app(SdlBackend))     # what ships: workbench, json/xml/sql/julia
build_executable(default_json_app(SdlBackend))  # the v1 default: a plain JSON file editor
```

Output goes to `build/bin/projectured`. Both are *functions of the backend type*
rather than constants, so this package stays independent of any backend package.
Pass `logfile="build.log"` to send the long, noisy compile output to a file
instead of the terminal.

### Custom builds

```julia
# A workbench-less JSON file editor, SDL baked in, named "json-editor":
build_executable(; app_name="json-editor", domain=:json, workbench=false,
                   file_backed=true, backends=[SdlBackend])

# Generate the config only (no multi-minute compile) — useful for inspection:
build_executable(BuildSpec(; domain=:json, backends=[SdlBackend]); compile=false)
```

The compile has to `Pkg.activate` the app environment; `build_executable` restores
the caller's active project on the way out, so a REPL session is left where it was.

`build_executable` (1) generates [`source/executable/AppConfig.jl`](../../../source/executable/) — the baked
configuration constants plus the `using` line(s) for exactly the compiled-in
backends; (2) develops the local Projectured packages it needs by path (so they
resolve without a registry); and (3) runs `create_app`.

### `BuildSpec` options

| keyword | default | meaning |
|---|---|---|
| `app_name` | `"projectured"` | binary name (`build/bin/<app_name>`) |
| `domain` | `:json` | content domain — a key in `ProjecturedExample.EDITOR_DOMAINS` |
| `workbench` | `false` | wrap the content in the workbench shell |
| `file_backed` | `true` | the binary takes a `FILE` argument to open/edit |
| `backends` | (required) | display backend **types** compiled in (`SdlBackend`, `WebBackend`, `ConsoleBackend`) |
| `default_backend` | first of `backends` | backend type used when none is requested at runtime |
| `expose_backend_flag` | `false` | whether the binary honors `--backend` at runtime |
| `width`, `height` | `nothing` | fixed window size (defaults to the display size) |
| `mcp` | `false` | start an MCP server alongside the editor loop |

The generated `source/executable/AppConfig.jl` is git-ignored; the checked-in
[`source/executable/AppConfig.default.jl`](../../../source/executable/AppConfig.default.jl) (the v1 spec) is the fallback
used when no build has run yet.

## Running the produced binary

```bash
build/bin/projectured path/to/document.json   # open and edit a JSON file
build/bin/projectured                          # start on a scratch document
build/bin/projectured --help
build/bin/projectured --version
```

When the build was made with `expose_backend_flag=true` and multiple `backends`,
the binary also accepts `--backend KIND` (e.g. `--backend web`) to pick among the
compiled-in backends; on a baked build `--backend` is rejected.

> **Note:** saving / loading / export / import of the edited file is integrated
> separately and is not part of this build yet — the binary currently opens and
> edits a file in memory.

## Project structure

```
executable/
├── builder/                  # ProjecturedBuilder: BuildSpec + build_executable
│   ├── Project.toml
│   └── ProjecturedBuilder.jl
├── README.md                 # this file
├── main/
│   ├── Project.toml              # package configuration / dependencies
│   ├── ProjecturedExecutable.jl  # generic, AppConfig-driven entry module (julia_main)
│   ├── AppConfig.default.jl      # checked-in default config (v1 spec) — the fallback
│   ├── AppConfig.jl              # GENERATED per build (git-ignored)
│   └── Precompile.jl             # config-agnostic warm-up (calls precompile_warmup)
└── build/                    # generated build output (git-ignored)
    └── bin/<app_name>
```
