# Source-tree reorganization

## Motivation

The repo root mixes everything at one level: 11 Julia packages (each its own
`Project.toml` + `src/`) intermingled with assets and docs. Nothing tells you at a
glance what is a package vs. an asset vs. documentation. Goal: **de-clutter the root
while keeping every package fully separate** (no merging of packages).

## The packages — what each is, and how a user uses it

The 11 packages form five layers. Names below are shown as
`directory/` → `Module` (post-rename module name where it changes). Dependencies and
the typical `using …` entry point are listed because they determine how a user
consumes each one. (Sources: each package's entry-file docstring.)

### Layer 1 — Core engine

- **`kernel/` → `ProjecturedKernel`** *(no internal deps)*
  The headless, domain-agnostic engine: the reactive cell system, the
  reference / operation / IO-map machinery, the projection algebra (higher-order
  combinators + generic projections), the input-device abstraction, the editor
  read-eval-print loop, and the agent control surface (LLM/MCP *seams*). Carries only
  the foundational document *vocabulary* (`Collection`, `Primitive`, `Screen`) the
  engine itself needs — **no concrete domains, no backends, no heavy deps**.
  *Used by:* anyone embedding the engine or building a brand-new domain on top of it —
  `using ProjecturedKernel`.

### Layer 2 — Concrete content

- **`domain/` → `ProjecturedDomain`** *(→ kernel)*
  Every concrete document type (JSON / XML / Text / Syntax / Graphics / Widget /
  Workbench / SQL / Math / Formula / Graph / …), their projections, the parsers, the
  Console/PDF backends, and the domain-coupled editors (WorkbenchAssistant,
  ConversationEditor).
  *Used by:* someone who wants the documents/projections but their own front-door, or
  who is adding a new domain alongside the existing ones — `using ProjecturedDomain`.

### Layer 3 — Umbrella front-door

- **`projectured/` → `Projectured`** *(→ kernel, domain)*
  Re-exports kernel + domain as a single flat namespace. **This is what most users
  load.** *Used by:* application code and the REPL — `using Projectured`.

### Layer 4 — Opt-in backends & integrations (each lights up on demand)

These are always loaded **alongside `Projectured`** (the umbrella that provides the
document/editor API and the `make_backend` / `make_database_adapter` /
`make_agent_server` / `run!` / `write_image` generics these packages plug methods into).
On its own a backend package exports only its own handle — e.g. `ProjecturedSdl`
exports `SdlBackend`, not `make_backend` — so `using ProjecturedSdl` **without**
`Projectured` is not useful: you'd have the backend type but neither the activation
generic nor any documents/projections to render. The activation call for each is shown
below, assuming `using Projectured` is already in effect. **This is a *usage* pairing,
not a dependency:** `ProjecturedSdl` depends on `ProjecturedDomain`, *not* on the
`Projectured` umbrella — you load the umbrella too only because it's what exports the
flat editing API the backend renders.

- **`sdl/` → `ProjecturedSdl`** *(→ domain)* — SDL window / GPU rendering / SDL_ttf
  text + offscreen image/PDF/video output. Activate with `make_backend(:sdl)`; exports
  `SdlBackend`, `GraphicsCanvasToImageFile`, `sdl_*` helpers. The interactive desktop
  editor *and* headless screenshot/video rendering.
- **`web/` → `ProjecturedWeb`** *(→ domain)* — HTTP/WebSocket browser backend
  (SDL-free). Activate with `make_backend(:web)`; exports `WebBackend`.
- **`odbc/` → `ProjecturedOdbc`** *(→ domain)* — live ODBC database access (adapter,
  connection pool, live-query projections). The SQL/DbCatalog *documents* stay in
  `domain`; only live querying lives here. Activate with `make_database_adapter(:odbc)`;
  exports `OdbcDatabaseAdapter`, `OdbcConnectionPool`, `SqlToCellTable`, ….
- **`llm/` → `ProjecturedLlm`** *(→ kernel)* — Anthropic Messages API client (real
  Claude); loading it adds `stream_turn(::AnthropicLlm)` to the kernel's LLM seam (no
  separate activation call — it wires real Claude into the editor's agent loop).
- **`mcp/` → `ProjecturedMcp`** *(→ kernel)* — MCP (Model Context Protocol) server
  transport; activate with `make_agent_server(:mcp, editor)`; exports `McpServer`.

(The `:sdl` / `:web` / `:odbc` / `:mcp` registration symbols are unchanged — only the
*module* names gain the `Projectured` prefix in Phase 3.)

**Why Console/PDF live in `domain` but SDL/Web/ODBC are opt-in packages:** the
Console and PDF backends (in `domain/src/backend/`) are **dependency-free** — pure
Julia (stdout/ANSI for Console; pure-Julia PDF emission for Pdf). They import only
internal modules and add **nothing** over `ProjecturedKernel`'s deps — they don't even
touch domain's two stdlib deps (`Base64`, `Markdown`; `Markdown` is used by
`WorkbenchAssistant`, not the backends). With nothing to gate, they ship inside
`domain`. SDL / Web / ODBC each pull **heavy third-party deps**
(SDL2_jll / FFMPEG; HTTP / JSON3; ODBC / DBInterface / Tables), so they are carved out
as opt-in packages a user loads only when needed.

### Layer 5 — Tooling (not part of the shipped library)

- **`example/` → `ProjecturedExample`** *(→ projectured, +opt-in odbc)* — the example
  gallery (document + projection examples). `using ProjecturedExample; run_example(…)`.
- **`test/` → `ProjecturedTest`** *(→ projectured, example, +opt-in sdl/odbc)* — the
  test suite. `test_all()`, `test_printer(…)`, etc.
- **`executable/` → `ProjecturedExecutable`** *(→ projectured, example, +opt-in sdl)* —
  PackageCompiler build of a standalone native binary for distribution (`julia Build.jl`).

### External dependencies per package

Third-party / stdlib deps only (internal ProjecturEd deps are the `→ …` annotations
above). `*` = Julia stdlib; everything else is a third-party package. Verified from each
`Project.toml` `[deps]`. No package uses weakdeps/extensions.

| package        | external dependencies (and what they're for)                                  |
|----------------|-------------------------------------------------------------------------------|
| `kernel`       | **none** — zero deps, pure Julia Base                                          |
| `domain`       | `Base64`*, `Markdown`* (stdlib; `Markdown` for the assistant editor)           |
| `projectured`  | **none** (umbrella — only internal kernel+domain)                             |
| `sdl`          | `SimpleDirectMediaLayer` + `SDL2_jll` (native SDL2/SDL_ttf: window, rendering, text rasterisation), `FFMPEG` (encode frames → video, `record_video` only) |
| `web`          | `HTTP`, `JSON3` (HTTP/WebSocket server + JSON wire), `Base64`*                  |
| `odbc`         | `ODBC` (driver), `DBInterface` + `Tables` (query/result API)                   |
| `mcp`          | `ModelContextProtocol` (MCP server transport)                                 |
| `llm`          | `HTTP`, `JSON3` (Anthropic Messages API client)                               |
| `example`      | `Profile`* (profiling helpers in examples)                                     |
| `test`         | `Test`* (the test framework)                                                   |
| `executable`   | `PackageCompiler` (build the native binary), `FixedPointNumbers` (version-pinned in `Build.jl` as a Julia 1.12 precompile-compat fix) |

This is the concrete basis for the layering: the engine (`kernel`) and the umbrella
(`projectured`) carry **no third-party weight at all**, `domain` adds only two stdlib
packages, and *all* heavy third-party deps live in the opt-in Layer-4 packages
(`sdl`/`web`/`odbc`/`mcp`/`llm`) plus the tooling (`executable`). A user who only
`using Projectured` pulls in nothing beyond Base + two stdlibs.

> **Planned split (separate effort):** `FFMPEG` is used by `sdl` *only* for headless
> `record_video`, so it is being extracted into a new opt-in **`ProjecturedVideo`**
> package that depends on `ProjecturedSdl` + `FFMPEG` — see
> [extract-video-package.md](extract-video-package.md). After it lands, `sdl`'s external
> deps drop to `SimpleDirectMediaLayer` + `SDL2_jll`, a `video/` row joins this table,
> and the end-state package count becomes **12** (`package/video/`, a Layer-4 package
> that depends on another Layer-4 package, `sdl`). The reorg itself works on the current
> 11 packages regardless of whether the split lands first.

> **Planned split (separate effort):** `Graphics`/`Text` (+ their PDF/Console backends)
> extract into `ProjecturedGraphics`/`ProjecturedText` with their own test packages —
> see [extract-graphics-text-packages.md](extract-graphics-text-packages.md).

> **Planned (separate effort):** the `Projectured` umbrella stays as a thin REPL
> convenience but its ~846 manual re-exports become an automatic loop — see
> [mechanize-umbrella-reexports.md](mechanize-umbrella-reexports.md).

### Typical user recipes

- **Desktop editor:** `using Projectured, ProjecturedSdl` (umbrella = editing API; SDL =
  backend — two independent packages, not a dependency) → run in a native window.
- **Browser editor:** `using Projectured, ProjecturedWeb` (umbrella + web backend).
- **Headless rendering** (screenshots / PDF / video, e.g. in CI):
  `using Projectured, ProjecturedSdl` + `write_image` / `make_backend(:sdl)`.
- **Embed the engine / author a new domain:** `using ProjecturedKernel` (add
  `ProjecturedDomain` if you want the existing documents to build on).
- **AI-assisted editing:** add `ProjecturedLlm` (real Claude) and/or `ProjecturedMcp`
  (expose the editor as an MCP server to external agents).
- **Live database documents:** add `ProjecturedOdbc`.
- **Learn by example:** `using ProjecturedExample`.
- **Ship a binary:** build via `executable/`.

The five-layer split is exactly why the directories stay **flat siblings** under
`package/` rather than nested by layer (`package/backend/sdl`): the backends/
integrations reference `../domain` / `../kernel`, and keeping them siblings preserves
those relative paths (nesting would force `../../…` rewrites). The layer is conveyed by
the annotations in the tree below, not by directory nesting.

## Naming principle

Full, unabbreviated, **non-pluralized** names — consistent with the existing house
style (`font/`, `image/`, `guide/`, `example/`, `test/` are all singular even though
they hold many items).

- `package/`        (not `packages/`, not `pkg/`)
- `asset/`          (not `assets/`)
- `documentation/`  (not `doc/`, not `docs/` — **avoid the abbreviation**)

## Target structure

```
projectured-julia/
├─ Project.toml / Manifest.toml      # dev meta-env (root; no name/uuid, just devs members)
├─ README.md  CONTRIBUTING.md  CLAUDE.md  LICENCE-*  .gitignore
├─ package/                                  # module names shown are the FINAL (post-Phase-3) names
│  ├─ kernel/      (ProjecturedKernel)      ← core, no internal deps
│  ├─ domain/      (ProjecturedDomain)      → kernel
│  ├─ projectured/ (Projectured)            → kernel, domain   ← renamed from program/
│  ├─ mcp/         (ProjecturedMcp)          → kernel
│  ├─ llm/         (ProjecturedLlm)          → kernel
│  ├─ sdl/         (ProjecturedSdl)          → domain
│  ├─ web/         (ProjecturedWeb)          → domain
│  ├─ odbc/        (ProjecturedOdbc)         → domain
│  ├─ example/     (ProjecturedExample)      (tooling)
│  ├─ test/        (ProjecturedTest)         (tooling)
│  └─ executable/  (ProjecturedExecutable)   (tooling)
├─ asset/
│  ├─ font/
│  └─ image/
├─ documentation/        # guide/ + presentation/ contents FLATTENED in (no wrapper dirs)
│  ├─ README.md                  (← guide/README.md — the doc index)
│  ├─ concepts.md  architecture.md  reactive-cells.md  …   (all guide root .md)
│  ├─ document/                  (← guide/document/: json.md, xml.md, syntax.md, …)
│  ├─ editor/                    (← guide/editor/: reference.md, selection.md, …)
│  ├─ projectured-overview.md    (← presentation/projectured-overview.md)
│  └─ presentations.md           (← presentation/README.md — renamed, see collision note)
└─ plan/              (STAYS at root — plan-workflow convention expects top-level plan/)
```

All 11 packages stay flat siblings under `package/` (no layer sub-grouping like
`package/backend/sdl`), so every `../sibling` relative path is preserved.

**All five integration packages remain** — `mcp/`, `llm/`, `sdl/`, `web/`, `odbc/` are
moved into `package/` like the rest, nothing is dropped.

## Package module names — DECISION: (B) prefix the five

The module names are currently inconsistent:

- `Projectured`-prefixed: `ProjecturedKernel`, `ProjecturedDomain`, `Projectured`,
  `ProjecturedExample`, `ProjecturedTest`, `ProjecturedExecutable`.
- **Bare** (no prefix): `Mcp`, `Llm`, `Odbc`, `Web`, `Sdl`.

**Chosen: rename the five to `Projectured*`** (`Mcp` → `ProjecturedMcp`,
`Llm` → `ProjecturedLlm`, `Odbc` → `ProjecturedOdbc`, `Web` → `ProjecturedWeb`,
`Sdl` → `ProjecturedSdl`). Directory names stay short (`mcp/`, `llm/`, …). UUIDs are
unchanged. Done as its own phase (Phase 3) after the directory move.

Rename touch-points (verified by grep):

- **Entry file must match package name** — Julia loads `src/<name>.jl`. Rename:
  `mcp/src/Mcp.jl` → `ProjecturedMcp.jl`, `llm/src/Llm.jl` → `ProjecturedLlm.jl`,
  `odbc/src/Odbc.jl` → `ProjecturedOdbc.jl`, `web/src/Web.jl` → `ProjecturedWeb.jl`,
  `sdl/src/Sdl.jl` → `ProjecturedSdl.jl`; and `module Mcp` → `module ProjecturedMcp`
  (etc.) on the first line of each.
- **`name =` in each of the 5 `Project.toml`s.**
- **Root `Project.toml`** `[deps]` + `[sources]` keys: `Mcp`/`Llm`/`Odbc`/`Web`/`Sdl`
  → `Projectured*` (the `[sources]` path already became `package/mcp` etc. in Phase 1;
  here only the *key* changes).
- **Dependents' `[deps]` keys:** `example` (Odbc), `test` (Odbc, Sdl),
  `executable` (Sdl). (`program`/`Projectured` does NOT depend on these five.)
- **`using`/`import` sites** (~12 lines): `using Sdl` (4 files), `using Odbc`
  (3), `using Mcp`/`using Llm`/`using Web` (1 each).
- **Qualified references** (~8): `Sdl.` (3), `Mcp.` (3), `Llm.` (1), `Web.` (1),
  `Odbc.` (0). Exported-symbol call sites that don't qualify are unaffected.

## Directory rename: `program/` → `projectured/` (DECISION)

The `program/` package's module is **`Projectured`** — the umbrella front-door that
re-exports kernel + domain so users write `using Projectured` (per its own docstring).
It is the one package whose directory name doesn't echo its module. **Chosen: rename
the directory `program/` → `projectured/`; keep the module `Projectured` as-is** (so
`using Projectured` is unaffected). Do NOT rename to `ProjecturedEditor` — it's an
umbrella, not the editor (the editor engine is `ProjecturedKernel.EditorModule`), and
renaming the module would break the public API.

Real touch-points are tiny (module/entry-file unchanged — `src/Projectured.jl` already
matches the module):
- Root `Project.toml`: `Projectured = {path = "program"}` → `{path = "package/projectured"}`
  (key unchanged; only the path).
- `executable/Build.jl:29`: `Pkg.develop(path="../program")` → `"../projectured"`.

**Pre-existing doc rot (do NOT mass-rewrite `program→projectured`):** README.md,
CONTRIBUTING.md, and several guides link to `program/src/common/Reactive.jl`,
`program/src/api/…`, `program/src/document/…`, `program/src/editor/…`,
`program/src/projection/…`. Those files **no longer live in `program/`** — they moved
to `kernel/src/` and `domain/src/` in the earlier package split, so the links are
already broken. They must be repointed at `package/kernel/...` / `package/domain/...`,
not at `projectured/`. Treat this as a **separate doc-accuracy pass** (fold into the
Phase 2 documentation sweep), not part of the mechanical rename.

## What does NOT change

- **Inter-package `[sources]`** in sub-package `Project.toml`s use `../kernel`,
  `../domain` — since all packages move together they stay siblings → unchanged.
- **`executable/Build.jl`** `"../example"` stays a sibling → unchanged (but its
  `"../program"` → `"../projectured"`, see the rename section above).
- **Within-package `include()`** paths (relative to each package's own `src/`) →
  unchanged.

## What DOES change

1. **Root `Project.toml` `[sources]`** — prefix all 10 paths with `package/`
   (`kernel` → `package/kernel`, …). This is the package-dependency wiring.

2. **Cross-root `@__DIR__`-relative asset paths** — these reach from inside a package
   up to repo-root `font/`/`image/`, so they break when the package descends into
   `package/` (extra `../`) AND when the asset moves into `asset/`. Do the package +
   asset moves **in one pass** and recompute each path once. Known sites:
   - `domain/src/document/Font.jl:103` — `joinpath(@__DIR__, "../../../font")`
     → `package/domain/src/document` → `asset/font` = `"../../../../../asset/font"`
   - `web/src/Web.jl:105` — `normpath(joinpath(@__DIR__,"..","..","font"))`
     → `package/web/src` → `asset/font`
     (NB: `Web.jl:633-638` `/font/` is an **HTTP route**, not a filesystem path — leave.)
   - `example/src/document/Text.jl:52` — `joinpath(@__DIR__,"..","..","..","image",name)`
   - `example/src/Examples.jl:706,730` — `image_dir=joinpath(@__DIR__,"..","..","image","example")`
   - `example/src/Examples.jl` markdown-link generation (`../image/...`,
     `../../image/example/...`, `image/example/...`, the `_MD_EXAMPLE_IMG_RE` regex,
     and the literal `"Screenshots are in [image/](../image/)."` string) — these write
     **doc links** into generated example markdown; update to the `asset/image/` layout.
   - Before executing, re-grep for any other `@__DIR__`-relative path that escapes its
     own package (`grep -rn '@__DIR__' package/*/src` and inspect each `..` chain).

3. **`.gitignore`** — `executable/build` → `package/executable/build`;
   `image/baseline-shadcn/` → `asset/image/baseline-shadcn/`.

4. **`documentation/` — flatten guide + presentation in (higher churn)**:
   - Move guide's contents to `documentation/` root, **keeping its `document/` and
     `editor/` subdirs** (only the `guide/` wrapper level is removed). Move
     presentation's contents in too.
   - **README collision** — both `guide/README.md` and `presentation/README.md` exist.
     Resolve: `guide/README.md` → `documentation/README.md` (the doc index);
     `presentation/README.md` → `documentation/presentations.md` (it's the Marp
     slide-deck index/how-to — rename to avoid the clash);
     `presentation/projectured-overview.md` → `documentation/projectured-overview.md`.
   - guide-internal cross-links survive (relative structure preserved: root files +
     `document/` + `editor/`). Update the one presentation link that points at its old
     `README.md`.
   - Sweep external refs `guide/<x>` → `documentation/<x>` and
     `guide/document/<x>` → `documentation/document/<x>` (≈78 occurrences outside
     guide/ & plan/) in: `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, and ~10 source
     files that mention guide paths in docstrings/comments
     (`kernel/src/api/Projection.jl`,
     `kernel/src/common/{OperationRerooting,IoMap,Reactive,Projection}.jl`,
     `kernel/src/editor/Mcp.jl`,
     `domain/src/projection/primitive/{BookToSyntax,FormulaToSyntax,WorkbenchToWidget}.jl`,
     `domain/src/document/Workbench.jl`, `test/src/editor/McpTest.jl`).
   - **Historical plans** (`plan/done/`, `plan/obsolete/`) reference `guide/` heavily;
     leave them as-is (records of the past). Optionally update `plan/pending/` &
     `plan/tentative/`.

## Migration phases

**Phase 1 — `package/` + `asset/` (do together):**
1. `git mv` the 11 package dirs into `package/`, renaming program in the process:
   `git mv program package/projectured` (and `kernel`, `domain`, … into `package/`).
2. `git mv font asset/font`, `git mv image asset/image`.
3. Edit root `Project.toml` `[sources]` (prefix `package/`; `program` path →
   `package/projectured`). Also fix `executable/Build.jl` `"../program"` →
   `"../projectured"`.
4. Fix the cross-root asset paths in #2 above (recompute each once for the final
   `package/… → asset/…` layout).
5. Update `.gitignore` (#3).
6. Verify: `Pkg.resolve()`; load `Projectured`; run a smoke test (e.g.
   `test_printer(json_example)` or a single-example `test_example`); generate one
   example image to confirm font + image paths resolve.

**Phase 2 — `documentation/` (separate commit, after Phase 1 is green):**
7. Create `documentation/`; `git mv` guide's root `.md` files plus its `document/` and
   `editor/` subdirs into it; `git mv guide/README.md documentation/README.md`. Move
   presentation in: `git mv presentation/projectured-overview.md documentation/` and
   `git mv presentation/README.md documentation/presentations.md`. Remove the emptied
   `guide/` and `presentation/` dirs.
8. Sweep references (#4). Verify links render and source docstrings point at the new
   flattened paths.

**Phase 3 — rename the five bare modules to `Projectured*` (separate commit):**
9. For each of mcp/llm/odbc/web/sdl: `git mv package/<d>/src/<Old>.jl
   package/<d>/src/Projectured<Old>.jl`; change `module <Old>` → `module Projectured<Old>`;
   change `name =` in its `Project.toml`.
10. Rename `[deps]`/`[sources]` keys in root `Project.toml` and the `[deps]` keys in
    `example` (Odbc), `test` (Odbc, Sdl), `executable` (Sdl).
11. Update all `using`/`import` (~12) and qualified `Old.` references (~8).
12. Verify: `Pkg.resolve()`; load each renamed package; run a test that exercises one
    (e.g. an Sdl/Odbc path).

## Open questions / decisions to confirm

- **Resolved:** guide + presentation are **flattened** into `documentation/` (no
  `guide/`/`presentation/` wrapper dirs); guide's `document/` and `editor/` subdirs are
  kept. presentation's `README.md` → `documentation/presentations.md` to avoid clashing
  with the guide index `README.md`.
- Do all the work in a dedicated git worktree (per repo convention), one commit per
  phase.

## Status

- [x] Phase 1 — package/ + asset/ ✅ (resolve OK; Projectured/Example/Sdl load; font→asset/font (36 fonts); printer→GraphicsCanvas; write_image→34 KB PNG)
- [x] Phase 2 — documentation/ (guide + presentation) ✅ (flattened; presentation README→presentations.md; runtime guide-dir reads fixed in Mcp.jl + Examples.jl, resource://guide/ scheme kept; doc-link sweep: 0 stale, 0 broken; MCP list_guides/search verified reading documentation/)
- [ ] Phase 3 — rename Mcp/Llm/Odbc/Web/Sdl → Projectured* modules
