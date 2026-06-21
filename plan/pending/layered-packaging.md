# Layered packaging: optional dependencies + kernel/domain/umbrella split

Restructure ProjecturEd into layers so that (1) every heavy dependency that can be
left out is optional, and (2) the code is split into three packages —
`ProjecturedKernel`, `ProjecturedDomain`, and `Projectured` (umbrella depending on
both). This is done in two phases, in this order, because Phase 1 forces the clean
interface boundaries that Phase 2 then cuts along while everything is still in one
package and refactorable in single PRs.

Status: **pending**.

## Current state (grounding)

- The repo is already a Julia monorepo environment. The root `Project.toml` is an
  *environment* (not a package) that `dev`s three path packages:
  - `Projectured` — `program/`, ~54k LOC, a single flat module
    `program/src/Projectured.jl` whose include list is a hand-maintained topological
    sort (api → common/reference/context → documents → parsers → projections →
    backends → editor), followed by a large `using .XxxModule: …` re-export block.
  - `ProjecturedExample` — `example/`, depends on `Projectured`.
  - `ProjecturedTest` — `test/`, depends on `Projectured` + `ProjecturedExample`.
- Internally the one module is already decomposed into ~80 submodules
  (`ReactiveModule`, `ReferenceModule`, `JsonModule`, `SqlDocumentModule`, …) that
  reference each other with **relative** paths (`..ReactiveModule`). There are
  **1134** such cross-module relative references — this is the main mechanical cost
  of Phase 2.
- Julia is **1.12** (extensions ≥1.9 and `[sources]` ≥1.11 both available).
- `program/Project.toml` heavy deps: `DBInterface`, `FFMPEG`, `HTTP`, `JSON3`,
  `ModelContextProtocol`, `ODBC`, `SDL2_jll`, `SimpleDirectMediaLayer`, `Tables`.
  Only `Base64` and `Markdown` (stdlib) are unconditionally needed.

## Goals

- A user editing JSON/XML/Text pays for none of ODBC, SDL2, HTTP, MCP, or FFMPEG.
- A reusable, headless `ProjecturedKernel` with no domain knowledge and no heavy deps.
- Separate precompile caches and separate test entry points per layer.
- Keep cross-layer refactors to single PRs (monorepo, not separate repos — separate
  git history is explicitly **out of scope** here; see the earlier analysis).

## Guiding principles

- **Optional = "leave it out and the editor is still useful."** By that test ODBC,
  SDL2, HTTP/JSON3, ModelContextProtocol, and FFMPEG are all optional: without SDL2
  the Console and Web backends remain; without ODBC the SQL/DbCatalog *documents and
  projections* remain (only live querying is lost); without HTTP/MCP the AI assistant
  is lost but editing remains; without FFMPEG only video recording is lost.
- **Two mechanisms, chosen per case:**
  - *Package extension* (`[weakdeps]` + `ext/`) when the optional code only **adds
    methods to existing generic functions** and is reached purely via dispatch — the
    core never needs to name a concrete type from it. Fits the ODBC adapter and
    FFMPEG video recording.
  - *Registry/factory indirection* when the optional code **exposes new API the app
    must construct by name** (the backends, the LLM editor). The core defines a
    generic factory (e.g. `make_backend(::Val{:sdl}, …)`) and the extension adds the
    method; callers go through the factory instead of naming `SdlBackend` directly.
    This is the crux that makes backends extension-compatible.
- Kernel owns every generic function/abstract type; domain and extensions only *add
  methods/subtypes*. No type piracy across the boundary.

---

## Phase 1 — Optional dependencies via package extensions

Done entirely within the current single `Projectured` package (no split yet). Each
optional dependency's code moves out of `src/` and into an extension under
`program/ext/`, triggered when its weakdep(s) load.

### 1.0 (optional stage) — SDL-independent text measurement

**This stage is optional and self-contained.** It is the gate on whether SDL2 can be
made *optional for graphical output*:
- **Skip it** → console editing is still fully SDL-free (it never used SDL), but the
  SDL/Web/PDF graphical path keeps SDL2 as a hard requirement. In that case the
  Phase-1 SDL extension bundles Web+PDF with SDL (they ship together), and SDL2 is
  *not* in the optional set.
- **Do it** → Web and PDF become SDL-free, SDL2 drops to a true optional dependency
  (GUI/image-decode/video only), and console + Web + PDF all run with no SDL loaded.

It is independent of the ODBC / HTTP / MCP / FFMPEG extensions — those do not depend
on this stage, so Phase 1 can proceed without it and this stage can be slotted in
whenever desired (before or after the others).

The blocker for making SDL optional is **text measurement**, not init. SDL_ttf's
`sdl_measure_text` is the de-facto font-metrics engine for the whole *graphical*
pipeline, not just the SDL GUI:
- `backend/Web.jl:60` does `import ..SdlBackendModule: sdl_measure_text` and
  `Web.jl:784` defines `measure_text(::WebBackend, …) = sdl_measure_text(…)` — every
  Web layout/bounds calculation routes through SDL_ttf; `Web.jl:43` additionally
  imports `LibSDL2: SDL_Init, SDL_INIT_VIDEO, TTF_Init`.
- `backend/Pdf.jl:784` builds `TextToGraphics(measure=sdl_measure_text)` — even PDF
  output measures glyphs via SDL_ttf.

By contrast `backend/Console.jl` has **no** SDL dependency (character-grid metrics),
so console editing already works SDL-free today.

The right seam already exists: `TextToGraphics` takes `measure=` as a parameter
(`TextToGraphics.jl:15`), and `Pdf.jl:217` notes it mirrors `sdl_measure_text`'s
contract "so the same projections can be driven without SDL." We just need a
non-SDL measurer plugged into it. Options:
- a pure-Julia metrics library (e.g. FreeTypeAbstraction.jl) — lighter, non-windowing;
- precomputed glyph-advance tables for the bundled fonts;
- keep SDL_ttf as *one* provider selected only when SDL is loaded (fallback to the above).

Tasks:
- [ ] Provide an SDL-free `measure_text` implementation and make it the default
      measurer for Web/PDF; route SDL_ttf in only when the SDL extension is active.
- [ ] Remove the `LibSDL2` init import from `Web.jl`; obtain video/TTF init without
      LibSDL2 (or only when SDL is present).
- [ ] Verify Web serves and renders, and PDF writes, with **no** SDL loaded.

### 1.1 Define the optional-feature seams in core (still hard-wired)

Before moving any code, introduce in `src/` the generic seams the extensions will
hook, so behaviour is identical while everything is still present:
- [x] Backend factory: a generic `make_backend(kind, …)` (or registry) in
      `api/Backend.jl`; route `run_example` / executable / example wiring through it
      instead of constructing `SdlBackend(…)` / `WebBackend(…)` directly. **Done**
      (commit `make_backend factory seam`): `make_backend(::Val{:sdl|:web|:console})`
      registered in each backend module; all 5 example construction sites routed
      through it; `make_backend` exported from the umbrella.
- [x] DB adapter seam. **Done** (commit `split DatabaseModule interface from ODBC
      adapter`): `DatabaseModule` is now dependency-free (abstract `DatabaseAdapter`,
      `RawDatabaseResult`, generic `db_*` stubs, new `make_database_adapter` factory;
      dropped `import ODBC/DBInterface/Tables`). The concrete `OdbcDatabaseAdapter`
      + all ODBC impls + `_build_select`/`_materialize` moved to new
      `OdbcAdapterModule` (`external/OdbcAdapter.jl`) — the *only* module touching
      ODBC/DBInterface/Tables — with `make_database_adapter(::Val{:odbc})`. By-name
      refs (`ConnectionPool`, `DatabaseTabular`, `DatabaseTableToTabularGrid`, umbrella
      re-export) repointed to `OdbcAdapterModule`; `db_*` generics still from
      `DatabaseModule`. (`DatabaseInstanceToDbCatalog`/`SqlToCellTable` only reference
      the pool, not the type — unchanged.) Note for 1.2: the umbrella still
      `using .OdbcAdapterModule: OdbcDatabaseAdapter` — that re-export becomes
      extension-gated when ODBC moves to a weakdep.
- [x] Agent control-surface seam (prerequisite for putting LLM/MCP in the kernel).
      **Done** (commits `make ToolRegistry dependency-free; invert Mcp->Workbench`,
      `add agent-server factory seam`, `make LlmModule dependency-free`):
      - `ToolRegistryModule` is now dependency-free (dropped `using
        ModelContextProtocol`); the MCP wire bridges `mcp_tools`/`mcp_resources`
        moved into `McpModule` (the MCP extension). The dep-free
        `anthropic_tool_schema` stayed in the registry (kept simple — it needs no
        heavy dep, deviating slightly from "move all bridges to the LLM ext").
      - Inverted `Mcp → WorkbenchModule: DEFAULT_ASSISTANT_SYSTEM`: `McpServer` takes
        an `instructions` kwarg defaulting to a generic, domain-free
        `DEFAULT_MCP_INSTRUCTIONS`; `run!` threads an optional `mcp_instructions`.
        (Minor behavioural nuance: default MCP-client prompt is the generic string
        unless a caller passes the richer one.)
      - The abstract LLM-client seam already existed as `LlmModule`'s `LlmBackend` +
        `stream_turn` generic (with `AnthropicLlm`/`FakeLlm`). Made `LlmModule`
        dependency-free by moving `stream_turn(::AnthropicLlm)` (calls
        `stream_message`, HTTP/JSON3) into `AnthropicModule`; swapped include order so
        `Llm` precedes `Anthropic`; dropped the unused `stream_message` import from
        `WorkbenchAssistant`. (No separate `complete` generic was added — the existing
        `stream_turn` plays that role.)
      - Added `make_agent_server(kind, editor)` + `agent_server_start!`/
        `agent_server_stop!` generics in new `AgentModule` (`api/Agent.jl`); `:mcp`
        methods registered in `McpModule`; the editor loop drives them through the
        generics so `EditorModule` no longer imports `McpServer`.
- [x] Video seam. **Done** (commit `forward-declare write_image/record_video
      generics`): `write_image`/`record_video` are now generic forward-declarations
      in `BackendModule`; the SDL backend's existing definitions became methods;
      umbrella re-exports them from `BackendModule`. Finding: FFMPEG is used *only*
      inside the SDL `record_video` (SDL offscreen frames + ffmpeg), so it is **not
      independently optional** — it rides with the SDL extension as an extra weakdep
      that gates `record_video` specifically. No separate FFMPEG extension is
      warranted; fold FFMPEG into the SDL extension's `[weakdeps]` in 1.2.

### 1.2 Create the extensions

Move code into `program/ext/`, add `[weakdeps]`, `[extensions]`, and `[compat]`
entries to `program/Project.toml`, and drop the moved deps from `[deps]`.

- [ ] **`ProjecturedODBCExt`** — weakdeps `ODBC`, `DBInterface`, `Tables`. Holds:
      `external/Database.jl` (the `OdbcDatabaseAdapter`), `external/ConnectionPool.jl`,
      `external/DatabaseTabular.jl`, and the query-executing parts of
      `projection/primitive/DatabaseTableToTabularGrid.jl`,
      `SqlToCellTable.jl`, `DatabaseInstanceToDbCatalog.jl`. Adds methods to the core
      DB generics. **Keep in core:** `Sql.jl`, `DbCatalog.jl`, `Database.jl`
      documents and the pure `*ToSyntax`/`*ToJson`/`*ToSql` projections — they need
      no ODBC.
- [ ] **`ProjecturedSDLExt`** — weakdeps `SimpleDirectMediaLayer`, `SDL2_jll`. Holds
      `backend/Sdl.jl`; adds `make_backend(::Val{:sdl}, …)`.
- [ ] **`ProjecturedWebExt`** — weakdeps `HTTP`, `JSON3`. Holds `backend/Web.jl`;
      adds `make_backend(::Val{:web}, …)`. If stage 1.0 was done, Web is SDL-free; if
      not, Web keeps a hard SDL dep and ships with the SDL extension instead.
- [ ] **`ProjecturedLLMExt`** — weakdeps `HTTP`, `JSON3`. Holds `editor/Anthropic.jl`
      (the concrete `LLMClient` over the Anthropic Messages API) + the
      `anthropic_tool_schema` wire bridge; implements the kernel's `complete`/`LLMClient`
      seam. Attaches to **`ProjecturedKernel`** (the orchestration is kernel-level),
      not domain. The HTTP/JSON3 parts of `WorkbenchAssistant`/`ConversationEditor`
      are domain UI calling the kernel seam.
- [x] **`ProjecturedMCPExt`** — weakdep `ModelContextProtocol`. **Done** (commit
      `extract MCP transport into ProjecturedMCPExt`). `program/ext/ProjecturedMCPExt.jl`
      holds the transport (`McpServer`, HTTP lifecycle, `mcp_tools`/`mcp_resources`
      bridges) and the `:mcp` `make_agent_server` methods; `program/Project.toml` has
      `[weakdeps]`/`[extensions]`; root env declares `ModelContextProtocol`.
      **Verified both ways** (dormant: `using Projectured` → `test_json` 29/29,
      factory errors; active: `using ModelContextProtocol` → extension loads, builds
      an `McpServer`). **Key finding:** most of `Mcp.jl` was *not* MCP — the
      dep-free editor tools (imported by core `ConversationEditor`/`WorkbenchAssistant`)
      had to stay in core `McpModule`; only the ~150-line transport moved. Each
      extension needs this kind of core-consumer disentangling, not just a file move.
- [ ] **`ProjecturedFFMPEGExt`** — **not needed** (finding from the video seam):
      FFMPEG is used only inside SDL `record_video`, so it folds into
      `ProjecturedSDLExt`'s `[weakdeps]` (gating `record_video`), not its own extension.

(`backend/Console.jl` and `backend/Pdf.jl` have **no** heavy deps — they stay in
core. **Note:** `Pdf.jl` currently uses `sdl_measure_text`, so it shares SDL's
text-measurement coupling — see stage 1.0.)

**Per-extension prerequisites discovered while doing MCP** (update before
attempting each):
- **LLM (`HTTP`/`JSON3`)** is *not* a clean single-consumer weakdep yet: `HTTP` is
  shared by `Anthropic` + `Web`; `JSON3` by `Anthropic` + `Web` + `WorkbenchAssistant`.
  Making `HTTP`/`JSON3` weakdeps requires Web extracted (blocked on stage 1.0) and
  `WorkbenchAssistant`'s `JSON3` use addressed.
- **ODBC** spans several modules (`OdbcAdapter`, `ConnectionPool`, `DatabaseTabular`,
  and the live-query projections) plus a `using ODBC`/`DBInterface` reference inside
  the `DatabaseInstance` *document* — verify/relocate that before moving ODBC code to
  the extension. Pure SQL/DbCatalog docs + `*ToSyntax`/`*ToJson`/`*ToSql` stay in core.
- **SDL + Web** remain blocked on **stage 1.0** (SDL-free text measurement); `Web`
  also imports `sdl_measure_text` and `LibSDL2` init.

### 1.3 Verification (Phase 1)

- [ ] In an environment **without** ODBC/SDL2/HTTP/MCP/FFMPEG, `using Projectured`
      precompiles and loads; Console + (decoupled) Web backends work; JSON/XML/Text/
      Syntax/SQL-document editing works. Run the smallest covering tests
      (`test_json()`, `test_syntax()`, `test_repl(...)`).
- [ ] In an environment **with** each weakdep, the corresponding feature lights up
      (SDL render, live DB query, AI assistant, video) — driven through the factory/
      seam, not direct type names.
- [ ] `ProjecturedTest` is split or gated so DB/SDL/LLM integration tests only run
      when their weakdep is present.

### Phase 1 known risks

- **Extension API-surface limitation.** Extensions can't export names the core
  references at load time; that is exactly why backends go through `make_backend`
  rather than `using .SdlBackendModule: SdlBackend`. Every current
  `using .SdlBackendModule`/`.WebBackendModule`/etc. in the umbrella re-export block
  and in example/executable code must be replaced by factory calls or
  `Base.get_extension` access. Audit all such sites.
- **SDL2 optionality depends on the optional stage 1.0** (SDL-free text
  measurement). Skip 1.0 and SDL2 stays mandatory for graphical output; the rest of
  Phase 1 (ODBC/HTTP/MCP/FFMPEG optionality) is unaffected either way.
- Trigger granularity: `ProjecturedWebExt` and `ProjecturedLLMExt` share
  `HTTP`+`JSON3`; if both should not co-trigger, give one an extra distinguishing
  weakdep or merge them.

---

## Phase 2 — Split into `ProjecturedKernel` / `ProjecturedDomain` / `Projectured`

### Target package graph

```
ProjecturedKernel   (headless engine; no domain types, no heavy deps)
        ▲
        │
ProjecturedDomain   (all concrete documents, projections, parsers, backends;
        ▲            owns the Phase-1 extensions via its [weakdeps])
        │
Projectured          (umbrella: depends on Kernel + Domain, re-exports public API)
        ▲
        ├── ProjecturedExample (retarget to umbrella)
        └── ProjecturedTest    (retarget to umbrella)
```

### Kernel / domain boundary

`ProjecturedKernel` (the reusable, domain-agnostic engine):
- `api/*` — abstract types + generic stubs (Backend, Device, Projection, Operation,
  Document, IoMap).
- `common/*` — Reactive, Document, IoMap, Operation, DocumentCopy, Projection,
  OperationRerooting.
- `reference/*` — Reference, ReferenceCase, ReferenceBuilder.
- `context/PrinterContext`.
- `device/*` — Modifiers, Keyboard, Mouse, EventCase, Screen (input abstraction).
- The **domain-agnostic projection algebra**: the higher-order combinators
  (Sequential, TypeDispatching, Recursive, Alternative, PredicateDispatching,
  ReferenceDispatching, Nesting, EnvelopeUnwrapping) and the generic projections
  (Preserving, Reversing, Filtering, Searching, Sorting, Copying, Invariably).
- The headless editor loop core (`editor/Editor.jl`'s read-eval-print over a
  projection, using only Backend/Device/Screen abstractions).
- **The agent control surface** (domain-agnostic LLM/MCP orchestration). Conceptually
  this is another Device/Backend: an MCP server is a channel that reads *operations*
  from an agent and writes *document state* back, structurally identical to a
  keyboard+screen. The kernel-resident, dep-free pieces are:
  - an abstract `LLMClient` type + a `complete(client, messages)::response` generic;
  - the agent turn-loop (drive tools given a client + registry);
  - the Tool/Resource **registry** and its `(editor, args::Dict) -> String` handler
    protocol — the *pure* part of `editor/ToolRegistry.jl`, with the
    `ModelContextProtocol`/Anthropic wire bridges removed (see prerequisites below);
  - the generic editor-control tools whose handlers touch only the kernel's
    operation/selection/reference/projection API;
  - an abstract agent Device/Backend hooked into the editor loop, started via a
    factory (`make_agent_server(:mcp, editor)`) since the concrete server type lives
    in an extension.

`ProjecturedDomain` (everything concrete):
- `document/*` — all specific domains (incl. the `Conversation` document).
- `projection/primitive/*` — all concrete projections; `projection/compound/*`
  (incl. `ConversationToSyntax`/`ConversationToWidget`).
- `parser/*`.
- `backend/*` (Console, Pdf in-package; Sdl/Web via the Phase-1 extensions).
- App editors that are domain-coupled: `WorkbenchAssistant` (Workbench panel +
  `DEFAULT_ASSISTANT_SYSTEM`), `ConversationEditor`, `GestureRecognizer`, and any tool
  whose handler dispatches on a concrete document type (registered into the kernel
  registry at startup).
- Owns the **non-agent** Phase-1 extensions (ODBC/SDL/Web/FFMPEG). The **LLM/MCP
  extensions attach to `ProjecturedKernel`**, not domain — see 1.2.

`Projectured` (umbrella):
- `using ProjecturedKernel`, `using ProjecturedDomain`; carries the large re-export
  `using .XxxModule: …` block (now sourced from the two packages) so existing
  `using Projectured` user code is unchanged.

### Ambiguous files — resolve case-by-case during implementation

These straddle the line; decide per file whether the kernel gets a domain-free core
with the domain-coupled part staying in domain:
- `projection/generic/ObjectToWidget.jl`, `projection/primitive/ScreenToScreen.jl`,
  `higherorder/WindowManager.jl`, `higherorder/TooltipDecorator.jl`,
  `higherorder/Dragging.jl`, `higherorder/ProjectionConfiguring.jl`,
  `projection/generic/Focusing.jl` — all reference concrete domain modules
  (Widget/Screen/Tooltip/Dragging). Default: **domain**, unless a clean
  domain-agnostic core can be split out into kernel.
- `editor/Editor.jl` — split the generic loop (kernel) from app wiring (domain).

### The cross-module reference rewrite (main mechanical cost)

Julia's relative `..XxxModule` only resolves within one top-level module tree. Every
domain-file reference to a **kernel** submodule must become an absolute reference
(`using ProjecturedKernel.ReactiveModule` / re-exported alias). From the survey the
heavily-referenced kernel modules are: `ReactiveModule` (107), `ReferenceModule`
(102), `CollectionModule`*, `ProjectionApiModule` (74), `OperationModule` (45),
`IoMapModule` (45), `DocumentModule` (42), `PrinterContextModule` (39),
`IoMapApiModule` (38), `ReferenceBuilderModule` (33), `ReferenceCaseModule` (28),
`KeyboardModule` (25), `OperationApiModule` (20), `EventCaseModule` (14), the
projection combinators, etc.
- [ ] Decide whether `CollectionModule` / `PrimitiveModule` / `TextModule` /
      `SyntaxModule` are kernel or domain (they are referenced like infrastructure but
      are arguably domains — `*` Collection at 80 refs is the key judgement call).
- [ ] Have `ProjecturedKernel` re-export its public submodules so domain files can
      write one stable `using ProjecturedKernel: ReactiveModule, ReferenceModule, …`.
- [ ] **Delegate the ~1134-reference rewrite to a Sonnet subagent** once the boundary
      list is frozen (pure mechanical sweep: `..KernelModule` → absolute form),
      verifying with a load + targeted tests afterward. Keep kernel-internal
      `..` references as-is.

### Monorepo wiring

- [ ] Create `kernel/` and `domain/` package dirs (or `program/` becomes the umbrella
      and two new dirs hold kernel/domain — pick one layout and record it here).
- [ ] Add `name`/`uuid`/`version` to each new `Project.toml`; use path deps via the
      root environment's `[sources]` (Julia ≥1.11) or `Pkg.develop(path=…)`, matching
      how Example/Test are already wired.
- [ ] Retarget `ProjecturedExample` and `ProjecturedTest` deps to the umbrella (and
      to Kernel directly where a test exercises kernel-only behaviour).
- [ ] Update root `Project.toml` to `dev` all five packages.

### Verification (Phase 2)

- [ ] `using ProjecturedKernel` precompiles and loads alone, with **zero** heavy deps
      and no domain symbols.
- [ ] `using Projectured` reproduces today's public surface (spot-check the re-export
      block; run `test_json()`, `test_syntax()`, `test_json_to_syntax()`,
      `test_repl(...)`).
- [ ] Optional features still gate correctly through their extensions —
      ODBC/SDL/Web/FFMPEG owned by `ProjecturedDomain`, **LLM/MCP owned by
      `ProjecturedKernel`** (agent control surface). `using ProjecturedKernel` alone,
      with `ModelContextProtocol` loaded, can start an MCP server over a headless
      editing session with no domain loaded.
- [ ] A broad sweep (`test_printers()`/`test_readers()`) only after targeted tests
      pass.

## Sequencing / commits

Work in a dedicated worktree. Commit per checkpoint:
1. Stage 1.0 SDL-free text measurement (**optional**; only needed to make SDL2
   optional for graphical output — can be deferred or skipped).
2. Phase 1.1 seams (backend factory, DB interface, agent control surface — registry
   split + `Mcp`→`Workbench` import inversion + `LLMClient`/`complete` + video) —
   still hard-wired.
3. One commit per extension (1.2), each verified loadable with and without its weakdep.
4. Phase 1.3 test gating.
5. Phase 2 boundary freeze (the kernel/domain file list + Collection/Primitive/Text
   judgement) — record decisions in this file.
6. Kernel package extraction + re-exports.
7. Domain package extraction + the delegated reference rewrite.
8. Umbrella re-export block + retarget Example/Test + root env.

## Open questions to resolve before/while implementing

- Is `CollectionModule` kernel infrastructure or a domain? (80 refs — biggest lever.)
- Same for `PrimitiveModule` / `TextModule` / `SyntaxModule` — these read like
  foundational vocabulary but are technically domains.
- `ProjecturedWebExt` (domain) and `ProjecturedLLMExt` (kernel) share an
  `HTTP`+`JSON3` trigger but attach to different packages — confirm both extensions
  fire correctly and don't race on the shared deps.
- How much of the agent control surface is genuinely domain-free? Audit each
  registered tool handler: generic editor-control (kernel) vs. document-type-specific
  (domain). The split is only worth it if the generic core is substantial.
- Final directory layout for the new packages (reuse `program/` as umbrella vs. new
  `umbrella/`).
```
