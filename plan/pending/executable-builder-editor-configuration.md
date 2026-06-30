# Configurable executable builder — choose the editor at build time

Status: **pending** (design)

## Goal

Extend the standalone-executable build so that **a REPL-callable Julia function
describes what kind of editor to bake into the binary**, and the produced binary
takes **runtime arguments** (a file to edit, and — when the build left it open — a
backend to use). Concretely the user wants to be able to build, for example:

- A **JSON editor without the workbench** that **directly edits a single JSON
  file** named on the command line (read on start, write on save/exit).
- A binary with the backend **baked in** (only SDL compiled, no choice), *or* a
  binary that **delays the backend choice** to runtime (`--backend=sdl|web|...`).

This is fundamentally about turning the current single, hard-coded executable into
a *family* of binaries produced from one configurable build.

### Build interface: Julia functions, not a CLI

The builder's interface is **Julia functions callable from the REPL** — e.g.
`build_executable(; domain=:json, workbench=false, backends=[:sdl], …)`. There is
**no requirement** for `Build.jl` to parse `ARGS`: a function is the primitive,
and a CLI wrapper (or a thin `Build.jl` script) is trivial to layer on top later
if wanted. So `Build.jl`'s job shrinks to "call `build_executable` with a spec".

### v1 scope (this plan)

**v1 = a JSON file editor with the SDL backend baked in.** That fixes the spec to
`domain=:json`, `workbench=false`, `file_backed=true`, `backends=[:sdl]`,
`expose_backend_flag=false`. The multi-backend / "delay the backend" machinery and
other domains are **designed here but exercised only in v2** (see Phases).

**Out of scope:** the actual **save / load / export / import operations** and the
JSON **document↔text serializer**. These are integrated separately (handled by the
user after this work lands), so this plan builds only the editor and the builder
and does not implement the serializer or a save trigger. Loading a JSON file on
start reuses the **already-existing** `jsonparse_file`, so the v1 binary opens and
edits a file regardless. `EditorDomain.save_file` is simply left `nothing` for now
— a save can be dropped into that field later without reshaping anything here.

## Current state (what exists today)

- [`package/executable/Build.jl`](../../package/executable/Build.jl) — no
  arguments. Hard-codes: `Pkg.develop` of `projectured` + `example`, the
  FixedPointNumbers pin, and a single `create_app(@__DIR__, …/build,
  precompile_execution_file=src/Precompile.jl)` call.
- [`package/executable/src/ProjecturedExecutable.jl`](../../package/executable/src/ProjecturedExecutable.jl)
  — the app module. `julia_main(args)` parses a tiny demo command set
  (`hello`/`info`/`version`/`help`); with **no** args it runs
  `run_example("workbench")`. It **hard-codes `using ProjecturedSdl`** ("bakes in
  the SDL backend").
- [`package/executable/Project.toml`](../../package/executable/Project.toml) deps:
  `Projectured`, `ProjecturedExample`, `ProjecturedSdl`, `FixedPointNumbers`,
  `PackageCompiler`.
- [`package/executable/src/Precompile.jl`](../../package/executable/src/Precompile.jl)
  — warm-up workload (currently the demo commands + `cmd_workbench_example`).

### How the pieces we need already work

- **Backends self-register** via `make_backend(::Val{kind}; kwargs...)`
  ([`kernel/src/api/Backend.jl`](../../package/kernel/src/api/Backend.jl#L32)).
  A backend becomes available **simply by `using` its package** — SDL
  ([`sdl/src/ProjecturedSdl.jl:2488`](../../package/sdl/src/ProjecturedSdl.jl#L2488)),
  web ([`web/src/ProjecturedWeb.jl:864`](../../package/web/src/ProjecturedWeb.jl#L864)),
  console ([`domain/src/backend/Console.jl:338`](../../package/domain/src/backend/Console.jl#L338),
  always present via the domain package). `make_backend(:kind)` errors clearly if
  the providing package was not loaded.
- **Scene composition** lives in `run_example`
  ([`example/src/Examples.jl:258`](../../package/example/src/Examples.jl#L258)):
  it takes `Example`s, applies a wrapping mode (`workbench` / `scrolling` /
  `introspection` / …), lays out `WindowDocument`s into a `ScreenDocument`, builds
  a backend (`backend===nothing && make_backend(:sdl; …)`), composes the
  multi-window projection, and calls
  `run!(backend, composed, screen)`
  ([`kernel/src/editor/Editor.jl:252`](../../package/kernel/src/editor/Editor.jl#L252)).
  The single-window path is also shown by
  `play_live_example` ([`example/src/LiveExamples.jl:98`](../../package/example/src/LiveExamples.jl#L98)).
- **Workbench wrapping**: `make_workbench_document(document; title, filename)` +
  `make_workbench_projection()`
  ([`example/src/document/Wrapper.jl:28`](../../package/example/src/document/Wrapper.jl#L28)).
- **JSON load already exists**: `jsonparse(text)` / `jsonparse_file(path)`
  ([`domain/src/parser/JsonParser.jl`](../../package/domain/src/parser/JsonParser.jl)).
  XML/SQL/Julia parsers exist too. **No serializer (document → text) exists yet**
  for any domain — `jsonunparse` etc. are **out of scope** (save / export, added
  later); this plan only needs the existing load path.
- **The run loop** quits on `QuitEditorException` (window close)
  ([`Editor.jl:214-227`](../../package/kernel/src/editor/Editor.jl#L214)). There is
  **no save hook** today — adding one is out of scope too.
- The flat API (`jsonparse`, `make_backend`, `JsonObject`, …) comes from
  `using Projectured`; `run_example`, `Example`, etc. from `using ProjecturedExample`.

## Key constraints & the central insight

**Two distinct argument layers — keep them separate:**

1. **Build-time arguments** (to `build_executable`) decide *what is compiled into
   the binary* and *what runtime surface it exposes*. This is where "bake in vs
   delay the backend", "with/without workbench", "which domain" are fixed.
2. **Runtime arguments** (to the produced `main` binary) choose *within the baked
   capabilities*: which file to open, and — only if the build left it open — which
   backend to use.

**PackageCompiler constraint that shapes everything:** a compiled app **cannot
`using` a package that was not compiled in**. Therefore:

- *"Bake in the backend"* = compile **one** backend package in, hard-code its
  `using` + `make_backend`, and **do not** expose a backend flag.
- *"Delay the backend"* = compile **several** backend packages in and pick among
  them at runtime via `--backend`. There is no way to load an uncompiled backend
  later; "delay" only means "choose among the ones that were baked".

So the backend choice is **primarily a build-time decision** (which deps + which
`using` lines are generated), optionally surfaced as a runtime flag.

## Design

### 1. `BuildSpec` — the description of the editor to build

A plain struct (or `NamedTuple`/`Dict`) assembled by `build_executable` from its
keyword arguments:

| field | meaning | example |
|---|---|---|
| `app_name` | binary name + banner | `"json-editor"` |
| `domain` | which editor kind (selects makers + file loader/saver) | `:json`, `:xml`, `:text`, `:workbench`, `:examples` |
| `workbench::Bool` | wrap in the workbench shell, or a bare single-window editor | `false` |
| `file_backed::Bool` | binary takes a file path and reads/writes it | `true` |
| `backends::Vector{Symbol}` | backends to **compile in** | `[:sdl]` / `[:sdl,:web]` |
| `default_backend::Symbol` | backend used when none is requested | `:sdl` |
| `expose_backend_flag::Bool` | whether the binary accepts `--backend` | `false` (baked) / `true` (delayed) |
| `width`,`height` | optional default window size | |
| `mcp::Bool` | start an MCP server alongside the loop | `false` |

`expose_backend_flag=false` with `backends=[:sdl]` is the fully-baked case;
`expose_backend_flag=true` with `backends=[:sdl,:web]` is the delayed case.

### 2. Library support (reusable, REPL-testable — not in the executable)

Put the real logic in the `example`/`domain` packages so it is testable without a
multi-minute `create_app`, and the executable stays a thin arg-parser.

- **`EditorDomain` registry** (new, in `example`): maps a domain symbol to its
  pieces so the builder/launcher are data-driven, not a `if domain==…` ladder:
  ```
  struct EditorDomain
      name::Symbol
      make_empty_document        # () -> Document  (scratch / no file)
      make_projection            # () -> Projection
      load_file                  # path -> Document               (e.g. jsonparse_file)
      save_file                  # (document, path) -> nothing | nothing (unset for now)
  end
  const EDITOR_DOMAINS = Dict(:json => EditorDomain(:json, () -> JsonInsertion(),
      make_json_projection_example, jsonparse_file, nothing), …)  # save_file = nothing in v1
  ```
  v1 registers `:json` (load via existing `jsonparse_file`, `save_file = nothing`).
  The registry keys by *content* domain only; `:xml`/`:text` follow in v2.
  (`workbench` is a wrapping flag handled in `run_file_editor`, not a domain; the
  `examples` gallery stays the `run_example` path — neither is a registry entry.)
- **JSON serializer** — *out of scope.* The `save_file` field stays `nothing`; a
  serializer/save (`jsonunparse_file(doc, path)`, the inverse of `jsonparse`) can
  be dropped into it later without touching the rest. This plan does not write one.
- **`run_file_editor`** (new, in `example`), the single reusable entry the
  executable calls:
  ```
  run_file_editor(domain::Symbol; file=nothing, workbench=false,
                  backend=nothing, width=nothing, height=nothing, mcp=false)
  ```
  It: resolves the `EditorDomain`; builds the document (`load_file(file)` if the
  file exists, else `make_empty_document()`); builds the projection (bare
  single-window, or workbench-wrapped via `make_workbench_document/projection`);
  composes the single-window scene (factor the `WindowDocument`/`ScreenDocument`
  +`_multi_window_projection` block out of `run_example` so both share it);
  resolves the backend (arg, else `make_backend(default)`); runs the loop. The
  **save** step (calling `save_file` on exit, or wiring Ctrl+S) is **out of scope**
  and added later — `run_file_editor` only needs to keep `document`/`file`
  reachable so a save can be wired in without reshaping it.

### 3. Build-time flow — a `build_executable` REPL function

The build entry is a Julia function, not an `ARGS` parser:

```
build_executable(; app_name="projectured", domain=:json, workbench=false,
                   file_backed=true, backends=[:sdl], default_backend=:sdl,
                   expose_backend_flag=false, output=…/build, force=true)
```

(Optionally it takes a `BuildSpec` value: `build_executable(spec::BuildSpec)`.) It
runs the same steps `Build.jl` runs today, parametrized by the spec:

1. **Set the compiled dependency set from `backends`.** On the activated
   executable env, `Pkg.develop` the locals as today and `Pkg.add`/ensure exactly
   the backend packages in `backends` (`:sdl`→`ProjecturedSdl`,
   `:web`→`ProjecturedWeb`; `:console` needs nothing extra). Excluding SDL from a
   web-only binary requires the dep to be *absent*, so the dep set is generated,
   not a fixed superset. (v1: `backends=[:sdl]` → unchanged from today's deps.)
2. **Generate `src/AppConfig.jl`** — the spec embedded as constants
   (`const APP_DOMAIN = :json`, `APP_WORKBENCH = false`, `APP_BACKENDS =
   (:sdl,)`, `APP_DEFAULT_BACKEND = :sdl`, `APP_EXPOSE_BACKEND = false`,
   `APP_FILE_BACKED = true`, `APP_NAME = "json-editor"`, …) **and** the exact
   `using` line(s) for the baked backends (`using ProjecturedSdl` [, `ProjecturedWeb`]).
   The `ProjecturedExecutable.jl` module `include`s this and stays generic.
3. **Generate the precompile workload** to exercise *this* configuration (e.g.
   load a tiny sample file through `run_file_editor`'s document-build + a headless
   `write_image`/print pass) so startup is warm for the built editor, not the demo.
4. `create_app(...)` as today, naming the binary `app_name`.

`build_executable` lives in the `executable` package (or a small build module it
loads) so it is callable from a REPL: `julia --project=package/executable -e
'using …; build_executable(; domain=:json)'`. `Build.jl` is reduced to a one-line
script that calls `build_executable()` with the default (v1) spec, preserving the
existing `julia Build.jl` entry point. A CLI front-end (mapping `--flags` to
keyword args) is a trivial later add — explicitly **not** required.

The generated `AppConfig.jl` is git-ignored (build artifact); a checked-in
`AppConfig.default.jl` (the v1 JSON-editor/SDL spec) lets a plain `julia Build.jl`
build without first generating one.

### 4. Runtime flow — generic `julia_main(args)` reads `AppConfig` + args

`ProjecturedExecutable.jl` is rewritten to be generic over `AppConfig`:

```
function julia_main(args)::Cint
    opts = parse_runtime_args(args)            # file path, --backend, --help, --version
    opts.help    && (print_help(); return 0)
    opts.version && (print_version(); return 0)
    backend_kind = if APP_EXPOSE_BACKEND && opts.backend !== nothing
        opts.backend in APP_BACKENDS || error("backend :$(opts.backend) not built into this binary (have: $(APP_BACKENDS))")
        opts.backend
    else
        APP_DEFAULT_BACKEND
    end
    if APP_FILE_BACKED
        run_file_editor(APP_DOMAIN; file=opts.file, workbench=APP_WORKBENCH,
                        backend=make_backend(backend_kind), …)
    else
        run_example(...)                       # examples/workbench demo modes
    end
    return 0
end
```

- `--help` lists only the flags this binary actually honors (e.g. omits
  `--backend` when `APP_EXPOSE_BACKEND=false`).
- A `file_backed` binary with no path argument starts on an empty/scratch
  document (saving with no path is the save agent's concern; recommend it require
  a path).

## Build API (from the REPL)

v1 — a baked, workbench-less JSON file editor on SDL only (the default spec):
```julia
build_executable(; app_name="json-editor", domain=:json,
                   workbench=false, file_backed=true, backends=[:sdl])
# → build/bin/json-editor  document.json   (read + edit; save wired in later, out of scope)
```
or just `julia Build.jl` (the script calls `build_executable()` with this spec).

v2 — a JSON editor that delays the backend choice (SDL + web compiled in):
```julia
build_executable(; domain=:json, file_backed=true,
                   backends=[:sdl, :web], default_backend=:sdl,
                   expose_backend_flag=true)
# → build/bin/json-editor --backend=web document.json
```

A CLI wrapper, if ever wanted, is a thin shim that maps `--flags` to these keyword
arguments — not part of this plan.

## Phased implementation plan

v1 = JSON file editor, SDL baked in. The save/load serializer + save trigger are
out of scope (added later) and are **not** phases here.

- [x] **Phase 0 — Refactor (no behavior change). DONE.** Factored `run_example`'s
      windows→screen→run! tail into two helpers in `Examples.jl`:
      `_build_window_scene(docs, names; width, height, content_unwrap)` (pure —
      builds the `ScreenDocument` and lifts the first window's selection; testable
      with no backend/window) and `_run_window_scene(docs, projs, names; …, backend,
      compose, profile, content_unwrap)` (adds compose + run loop). `run_example`
      delegates via a `compose(projs, backend)` closure (the inspector pipeline
      needs the backend for its pointer closure) and a `content_unwrap` symbol
      (`:plain`/`:tooltip`/`:clipboard`) — behavior preserved exactly (backend knobs,
      profiler path, selection-lift depth). Added `EditorDomain` + `EDITOR_DOMAINS`
      + `editor_domain(name)` in new `FileEditor.jl` (registers `:json`;
      `load_file = jsonparse_file`, `save_file = nothing`); wired include + exports.
      **Decision:** `:examples`/`:workbench` are *not* registry domains —
      `workbench` is a wrapping flag (`make_workbench_*`) applied in
      `run_file_editor`, and the `examples` gallery stays the `run_example` path.
      The registry keys by *content* domain only (`:json`, later `:xml`/`:text`).
      Verified: clean precompile, registry + `_build_window_scene` assertions pass,
      dup-id / unknown-domain error paths work, `print_example(json_example)` runs.
- [ ] **Phase 1 — `run_file_editor`.** Resolve `EditorDomain`; load-or-scratch
      document; bare single-window (v1) vs workbench composition; resolve backend;
      run loop; expose `document`/`file`/`save_file` for the save seam. Verify in
      the REPL: `run_file_editor(:json; file="/tmp/x.json")` opens and edits the
      file. Commit.
- [ ] **Phase 2 — `BuildSpec` + `build_executable` function.** Spec struct +
      `build_executable(; …)`; generate the dep set from `backends`, `AppConfig.jl`,
      and a config-specific precompile workload; checked-in `AppConfig.default.jl`
      (v1 spec). `Build.jl` reduced to call `build_executable()`. Verify a plain
      `julia Build.jl` still produces a working binary. Commit.
- [ ] **Phase 3 — Generic `julia_main` + runtime args.** `AppConfig`-driven:
      file-path arg, help/version, baked SDL (no `--backend` since
      `APP_EXPOSE_BACKEND=false`). Build and run the v1 JSON-editor binary on a real
      file end-to-end (open + edit). Commit.
- [ ] **Phase 4 — v2 follow-ups (separate plan if large).** Delayed/multi-backend
      (`backends=[:sdl,:web]`, `expose_backend_flag=true`, `--backend` runtime arg
      + "not built in" rejection); other domains (`:xml`/`:text`, pending their
      serializers); workbench-with-files / multiple files; `mcp=true`; optional thin
      CLI/`--config` TOML wrapper; README + `documentation/` page for the build.

## Testing

- Library pieces are REPL/`@testset`-testable without `create_app`: the
  `EditorDomain` registry + `run_file_editor`'s document-build (Phase 1) — load a
  temp JSON file via `jsonparse_file` and assert the resulting document matches
  `make_json_document_example`-style expectations, no window needed. Follow the
  repo rule: narrowest scope first (`test_json()` / targeted new tests), not
  `test_all()`.
- Build-level smoke (Phase 2-3): `build_executable(; domain=:json, backends=[:sdl])`
  then launch the binary on a sample file and confirm it opens and renders the
  JSON. (Round-trip-through-the-binary checks come once save/export lands, later.)

## Open questions / decisions (defaults chosen; revisit if wrong)

- **Build interface**: REPL-callable `build_executable(; …)` Julia function; no
  CLI required (a wrapper is trivial to add later). *(Per user.)*
- **v1 scope**: JSON file editor, **SDL baked in** (`backends=[:sdl]`,
  `expose_backend_flag=false`, `workbench=false`). *(Per user.)*
- **Save / load / export / import**: **out of scope** (added later). This plan
  leaves `EditorDomain.save_file = nothing` and keeps `document`/`file` reachable
  in `run_file_editor`.
- **No-path file_backed binary**: start on a scratch document. *(Revisit once the
  save agent lands: could instead require a path argument to launch.)*
