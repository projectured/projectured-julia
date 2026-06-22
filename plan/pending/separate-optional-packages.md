# Separate Julia packages for the optional components (SDL, Web, DB, MCP, LLM)

Promote the five optional components that currently live as **package extensions**
into **standalone, opt-in Julia packages** in their own top-level folders. SQL/DbCatalog
**documents and projections stay in `ProjecturedDomain`** — they are pure and need
nothing external; only the *live ODBC querying* moves out.

Status: **pending**.

## Why (the trade we are accepting)

This reverses the Phase-1 mechanism (weakdep extensions) for these five components.
A Julia extension must physically live in its parent's `ext/` directory, so "separate
top-level folders" *necessarily* means "standalone packages." The deliberate trade:

- **Gain:** clean public API (packages can `export SdlBackend`, `WebBackend`,
  `OdbcDatabaseAdapter`, `McpServer`, `AnthropicLlm` — no `Base.get_extension(...)`
  gymnastics); independent versioning / precompile cache / CI / ownership (serves the
  "more contributors" goal); the shared `HTTP`+`JSON3` trigger ambiguity disappears
  (`using ProjecturedWeb` no longer co-loads the LLM client and vice-versa).
- **Cost:** lose automatic activation (a user who already has SDL2 must now explicitly
  `add ProjecturedSDL` + `using ProjecturedSDL`); 3 packages → 8; SDL/Web/DB now depend
  on `ProjecturedDomain` **internal** modules across a versioned boundary (acceptable —
  they are co-developed with the domain and the const-alias re-export already makes those
  modules reachable, see "Mechanism").

The umbrella `Projectured` **stays kernel+domain only**; the five packages are opt-in and
are *not* re-exported by it.

## Current state (grounding — verified 2026-06-22 on `main`)

Five extensions exist after the kernel/domain split:

| Extension (file) | LOC | Parent | Trigger weakdeps | Registers (seam methods) |
|---|---|---|---|---|
| `kernel/ext/ProjecturedLLMExt.jl` | 179 | Kernel | HTTP, JSON3 | `stream_turn(::AnthropicLlm)` |
| `kernel/ext/ProjecturedMCPExt.jl` | 193 | Kernel | ModelContextProtocol | `make_agent_server(::Val{:mcp})` |
| `domain/ext/ProjecturedODBCExt.jl` | 748 | Domain | ODBC, DBInterface, Tables | `make_database_adapter(::Val{:odbc})` |
| `domain/ext/ProjecturedWebExt.jl` | 838 | Domain | HTTP, JSON3 | `make_backend(::Val{:web})` |
| `domain/ext/ProjecturedSDLExt.jl` | 2296 | Domain | SimpleDirectMediaLayer, SDL2_jll, FFMPEG | `make_backend(::Val{:sdl})`, `render_canvas`, `decode_image`, `write_image`, `record_video`, `set_display_size_provider!` |

The ext files **already** reference their parent by qualified path (`ProjecturedDomain.GraphicsModule`,
`ProjecturedKernel.LlmModule`, …). Domain re-exports its own submodules *and* const-aliases
the 37 kernel modules it uses, so `ProjecturedDomain.BackendModule` etc. resolve — this is
exactly what a downstream standalone package needs.

**Consumer surface (small):**
- `example/src/ProjecturedExample.jl:10-15` — `using ODBC, DBInterface, Tables` +
  `const _ODBCEXT = Base.get_extension(ProjecturedDomain, :ProjecturedODBCExt)` + 4 type binds.
- `test/src/ProjecturedTest.jl:10-22` — `using SimpleDirectMediaLayer, SDL2_jll, FFMPEG`,
  `using ODBC, DBInterface, Tables`, `const _ODBCEXT = …` + 8 type binds; `__init__` does
  `init!(make_backend(:sdl))`.
- `test/src/projection/GraphicsToFileTest.jl:30` — `Base.get_extension(ProjecturedDomain,
  :ProjecturedSDLExt).GraphicsCanvasToImageFile`.
- `executable/` — `using Projectured, ProjecturedExample`; the compiled GUI app needs SDL
  baked in (currently relies on SDL2 being in the build env to trigger the ext).
- **MCP / LLM / Web have NO trigger in example/test/executable** — the agent tests
  (`test_mcp_tools`, `test_assistant_mvp`) exercise the *kernel-resident* registry + tools
  and `FakeLlm`/`ScriptedLlm`; the MCP transport and Anthropic HTTP client are validated by
  precompile + manual load only. So Web/MCP/LLM standalone packages have essentially **zero
  consumer-retarget work** beyond their own Project.toml + load validation.
- **Factory-seam call sites that must keep working** (generic, by-symbol — preserved):
  `example/src/Examples.jl` `make_backend(:sdl)`/`make_backend(:web)`,
  `example/src/LiveExamples.jl` `make_backend(:sdl)`, `test` `make_backend(:sdl)`.

## Target package graph

```
ProjecturedKernel ──────────────┐
   ▲          ▲                  │
   │          │                  │
ProjecturedMCP   ProjecturedLLM  │   (depend on Kernel only; agent surface)
                                 │
ProjecturedDomain ───────────────┘
   ▲          ▲          ▲
   │          │          │
ProjecturedODBC  ProjecturedWeb  ProjecturedSDL   (depend on Domain)

Projectured (umbrella) = Kernel + Domain only  (unchanged; opt-in pkgs not re-exported)
ProjecturedExample → Projectured + ProjecturedODBC (+ seams)
ProjecturedTest    → Projectured + ProjecturedSDL + ProjecturedODBC
executable         → Projectured + ProjecturedExample + ProjecturedSDL
```

### Folders, names, deps

| Package | Folder | Depends on | New **regular** deps (were weakdeps) |
|---|---|---|---|
| `ProjecturedMCP` | `mcp/` | ProjecturedKernel | ModelContextProtocol |
| `ProjecturedLLM` | `llm/` | ProjecturedKernel | HTTP, JSON3 |
| `ProjecturedODBC` | `odbc/` | ProjecturedDomain | ODBC, DBInterface, Tables |
| `ProjecturedWeb` | `web/` | ProjecturedDomain | HTTP, JSON3 |
| `ProjecturedSDL` | `sdl/` | ProjecturedDomain | SimpleDirectMediaLayer, SDL2_jll, FFMPEG |

**Naming note:** the user referred to the DB package as "DB"; it is named `ProjecturedODBC`
(folder `odbc/`) because the implementation is ODBC-specific and the factory key is
`:odbc`. SQL/DbCatalog documents + `*ToSyntax`/`*ToJson`/`*ToSql` projections remain in
`ProjecturedDomain`. (If we later want a vendor-neutral umbrella, `ProjecturedDB` could
re-export `ProjecturedODBC` — out of scope here.)

## Mechanism — converting an extension to a package (mostly mechanical)

For each ext the steps are:
1. `git mv <parent>/ext/ProjecturedXxxExt.jl <folder>/src/ProjecturedXxx.jl`.
2. Rename the module: `module ProjecturedXxxExt` → `module ProjecturedXxx`.
3. Keep the `import ProjecturedDomain.YModule: …` / `import ProjecturedKernel.YModule: …`
   lines **verbatim** — they already resolve (domain submodules are public; kernel modules
   are const-aliased into domain). The standalone package additionally needs `using
   ProjecturedDomain` (or `ProjecturedKernel`) at the top, which the ext already has.
4. Add `<folder>/Project.toml`: `name`/`uuid`/`version`, `[deps]` = the parent package +
   the (now **regular**) external deps, `[sources]` path-dev'ing the parent, `[compat]`.
5. **`export` the public API** so consumers name it directly (see per-package lists below).
6. **Move runtime global-state registration into `__init__()`** (see correctness note).
7. Delete that ext's entries from the parent's `[weakdeps]`/`[extensions]` and drop the
   now-unused external weakdeps from the parent's `[weakdeps]`. **Do this per-package, not
   batched at step 6** — leaving a `[extensions]` entry whose file has moved makes the
   parent fail to load the (missing) ext when the trigger dep is present in the env.

### Critical correctness notes

- **Method definitions are fine at top level** — `make_backend(::Val{:sdl})`,
  `render_canvas(::GraphicsCanvas)`, `decode_image`, `write_image`, `record_video`,
  `make_database_adapter(::Val{:odbc})`, `make_agent_server(::Val{:mcp})`,
  `stream_turn(::AnthropicLlm)` are method-table additions owned by the new package's
  precompile image; they light up on `using ProjecturedXxx`. **Keep the factory seams** —
  by-symbol construction (`make_backend(:sdl)`) stays working for generic code, and the
  erroring fallback when the package is *not* loaded is preserved.
- **Mutating another package's global state must move to `__init__()`.** Today
  `ProjecturedSDLExt.jl:2294` calls `set_display_size_provider!(sdl_display_size)` at top
  level. In an *extension* that runs after the parent loads — fine. In a *standalone
  package* top-level code runs during that package's **own precompile**, and writing
  `ProjecturedKernel._DISPLAY_SIZE_PROVIDER[]` then does not persist. → put it in a
  `function __init__(); set_display_size_provider!(sdl_display_size); end`. Audit each
  package for any other such cross-module `Ref`/dict mutation and do the same.
- **Web asset paths** (`ProjecturedWebExt.jl:103-104`): currently
  `normpath(joinpath(@__DIR__, "..", "web"))` → `domain/web/` and `(@__DIR__, "..", "..",
  "font")` → repo-root `font/`. Move `domain/web/` → `web/assets/` (rename to avoid the
  awkward `web/web/`) and refit to `(@__DIR__, "..", "assets")` from `web/src/`; the shared
  repo-root `font/` stays put — from `web/src/` it is `(@__DIR__, "..", "..", "font")`
  (unchanged form, still resolves because `web/` sits at the same depth as `domain/`).

### Per-package public exports (proposed)

- `ProjecturedMCP`: `McpServer`, `mcp_start!`/`mcp_stop!` (transport lifecycle), plus the
  `:mcp` `make_agent_server` method.
- `ProjecturedLLM`: `AnthropicLlm` is defined in kernel `LlmModule`; the package adds
  `stream_turn(::AnthropicLlm)` and exports the HTTP client entry (`stream_message`).
- `ProjecturedODBC`: `OdbcDatabaseAdapter`, `OdbcConnectionPool`, `with_connection`,
  `close_pool!`, `dsn_for`, `DatabaseInstanceToDbCatalog`, `SqlToCellTable`,
  `DatabaseTableToTabularGrid`, `DatabaseTableIoMap` (the set example/test bind today).
- `ProjecturedWeb`: `WebBackend`, `web_key_to_symbol`, plus the `:web` `make_backend` method.
- `ProjecturedSDL`: `SdlBackend`, `GraphicsCanvasToImageFile`, the `sdl_*` helpers if we
  want them public, plus the `:sdl` `make_backend` + render/decode/image/video methods.

## Consumer retargeting

- **`ProjecturedExample`**: drop `using ODBC, DBInterface, Tables` + the `_ODBCEXT`
  `get_extension` block; add `using ProjecturedODBC` (types now exported, so the four
  `const … = _ODBCEXT.X` binds disappear). Add `ProjecturedODBC` to `example/Project.toml`.
  `make_backend(:web)` / `make_backend(:sdl)` in `Examples.jl` are unchanged (seam).
- **`ProjecturedTest`**: replace `using SimpleDirectMediaLayer, SDL2_jll, FFMPEG` with
  `using ProjecturedSDL`, and `using ODBC, …` + `_ODBCEXT` block with `using ProjecturedODBC`;
  drop the 8 `const` binds. `GraphicsToFileTest.jl` uses `GraphicsCanvasToImageFile` directly
  (exported) instead of `get_extension(...)`. Add `ProjecturedSDL`, `ProjecturedODBC` to
  `test/Project.toml`. `init!(make_backend(:sdl))` unchanged.
- **`executable`**: add `ProjecturedSDL` to `executable/Project.toml` and `using
  ProjecturedSDL` in `ProjecturedExecutable.jl` so the compiled GUI binary has the SDL
  backend baked in (it can no longer rely on weakdep auto-activation).
- **Root env** (`Project.toml`): add the five new packages to `[deps]` and `[sources]`
  (path-dev). The external libs (HTTP/JSON3/ODBC/SDL2/…) can be **removed** from the root
  `[deps]` since they are now regular deps of the opt-in packages (keep only if the dev REPL
  wants them directly).

## Strip extensions from Kernel & Domain

After all five move out:
- `kernel/Project.toml`: remove `[weakdeps]` (HTTP, JSON3, ModelContextProtocol) and the
  `[extensions]` table entirely → kernel returns to **zero deps, no extensions**.
- `domain/Project.toml`: remove `[weakdeps]` (DBInterface, FFMPEG, HTTP, JSON3, ODBC,
  SDL2_jll, SimpleDirectMediaLayer, Tables) and `[extensions]` → domain keeps only
  `[deps]` = Base64, Markdown, ProjecturedKernel.
- Delete `kernel/ext/` and `domain/ext/` once empty.

## Verification

- [ ] Each new package precompiles standalone (with its parent dev'd) and `using
      ProjecturedXxx` exposes the exported API; `make_backend(:sdl|:web)` /
      `make_database_adapter(:odbc)` / `make_agent_server(:mcp)` dispatch only when the
      package is loaded (erroring fallback otherwise).
- [ ] `ProjecturedKernel` and `ProjecturedDomain` still precompile after losing their
      `[weakdeps]`/`[extensions]`; `Projectured` umbrella unchanged.
- [ ] SDL: `test_write_image` (incl. `GraphicsCanvasToImageFile`), `test_record_video`,
      measurement; provider set via `__init__` (display_size works after `using ProjecturedSDL`).
- [ ] DB: `make_database_adapter(:odbc)` builds; the live-query projections construct.
- [ ] Web: `make_backend(:web)` builds and serves assets from `web/assets/`.
- [ ] MCP: `McpServer` builds over a headless kernel editor; LLM: `stream_turn(::AnthropicLlm)`
      present.
- [ ] Full env precompiles (8 packages); targeted tests `test_json`/`test_syntax`/
      `test_json_to_syntax`/`test_repl(json)` pass; broad `test_printers()`+`test_readers()`
      sweep = the **5 pre-existing `sql_table` failures only** (zero new regressions vs main).

## Sequencing / commits (simplest-first to de-risk)

Work in a dedicated worktree. One package per commit, each verified before the next:
1. `ProjecturedMCP` (193 LOC, kernel-only, single seam) — smallest, proves the pattern. **DONE.**
2. `ProjecturedLLM` (179 LOC, kernel-only). **DONE** — kernel now has zero weakdeps/extensions; `kernel/ext/` deleted.
3. `ProjecturedODBC` (748 LOC) + retarget Example/Test off `get_extension`. **DONE.**
4. `ProjecturedWeb` (838 LOC) + move `domain/web/` → `web/assets/` + path refit. **DONE.**
5. `ProjecturedSDL` (2296 LOC) + `__init__` provider + retarget Test/executable. **DONE.**
6. Strip `[weakdeps]`/`[extensions]` from kernel & domain; delete `*/ext/`. **DONE incrementally** (kernel stripped with LLM, domain with SDL; `kernel/ext` and `domain/ext` deleted).
7. Wire root env `[sources]`/`[deps]`; verification sweep.
8. Docs: update `guide/architecture.md` module/package inventory, `README.md` reading order,
   and the CLAUDE.md "where does the SDL backend live" answer; move this plan to `plan/done/`.

## Open questions

- Folder/name for the DB package: `odbc/` + `ProjecturedODBC` (proposed) vs `db/` +
  `ProjecturedDB`. Recommend `ProjecturedODBC` (honest about the adapter).
- Do we want a convenience meta-package (`ProjecturedAll`) that `using`s all five for REPL
  ergonomics? Default: **no** (opt-in is the point); revisit if the dev workflow is noisy.
- `ProjecturedWeb` and `ProjecturedLLM` both pull `HTTP`+`JSON3` independently now — confirm
  that is acceptable (it removes the co-trigger coupling but duplicates the dep declaration).
- Keep the factory seams *and* the direct exports (recommended), or drop the seams in favor
  of direct construction only? Recommend keep — generic by-symbol construction in
  `run_example`/editor stays decoupled from the concrete package types.
```
