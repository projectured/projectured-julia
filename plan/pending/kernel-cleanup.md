# Kernel cleanup — structure review and proposal

Review of `package/kernel` (2026-07-02): 49 source files, ~11.1k lines, **48 modules —
one module per file**, zero external dependencies. Findings are grouped by the cleanup
aspects that motivated the review; a phased execution plan and the open decisions follow.

## Current inventory

| Folder | Files | Modules | Content |
| --- | --- | --- | --- |
| `api/` | 7 | 7 | abstract types + generic-function stubs (Backend, Device, Projection, Operation, Document, IoMap, Agent) |
| `common/` | 7 | 7 | Reactive, Document impl, IoMap impl, Operation impl, OperationRerooting, GestureBinding, `@projection` + reader defaults |
| `reference/` | 3 | 3 | Reference, `@reference_case`, `@reference` |
| `device/` | 5 | 5 | Modifiers, Keyboard, Mouse, EventCase, Screen (device) |
| `document/` | 3 | 3 | Collection, Primitive, Screen (document) |
| `projection/higherorder/` | 9 | 9 | Sequential, TypeDispatching, Recursive, Alternative, PredicateDispatching, ReferenceDispatching, Nesting, WindowManager, EnvelopeUnwrapping |
| `projection/generic/` | 8 | 8 | Preserving, Reversing, Filtering, Searching, Sorting, Copying, Invariably, Focusing |
| `editor/` | 6 | 6 | PrinterContext, GestureRecognizer, ToolRegistry, Llm, Mcp, Editor |

Actual dependency strata (from the `import ..X` headers):

- **L0** (no kernel imports): Reactive, Modifiers, Llm, ToolRegistry, and the api stubs
  (Backend, ProjectionApi, OperationApi, DocumentApi, IoMapApi, Agent)
- **L1**: Device(→Backend), Document(→DocumentApi,Reactive), IoMap(→IoMapApi,Reactive), Mcp(→ToolRegistry)
- **L2**: Keyboard/Mouse(→Device,Modifiers), Reference(→Reactive,Document)
- **L3**: EventCase, ReferenceCase/ReferenceBuilder, PrinterContext, Operation, Collection, Primitive, ScreenDocument
- **L4**: GestureBinding, OperationRerooting
- **L5**: the 17 projection modules + ProjectionModule (defaults/`@projection`)
- **L6**: Screen device, GestureRecognizer, Editor

## Findings

### 1. Load order & internal dependencies

- The include list in `ProjecturedKernel.jl` is a **hand-maintained topological sort**
  whose section comments no longer match reality: the four device modules sit under
  "Foundational document vocabulary"; `common/Projection.jl` is sandwiched between the
  higher-order and generic projection includes; `editor/PrinterContext.jl` loads in the
  "Infrastructure" section; `editor/Llm.jl` loads mid-document-vocabulary.
- One genuine encapsulation break: `common/GestureBinding.jl:44` imports **private
  names** from EventCase (`_parse_rule`, `_EVENT_TYPES`, `EvPat`, `EvWild`, `EvBind`,
  `EvLit`, `EvInterp`). The two modules are one feature (event pattern matching)
  split across two files/folders.
- The interleaving is otherwise forced by real edges: GestureBinding needs the devices
  + DocumentApi + ProjectionApi; ProjectionModule needs Primitive (for
  `StringReplaceRangeOperation` defaults), hence its odd mid-projection slot.
- Of the seven api stub modules, only **ProjectionApi is structurally load-bearing**
  (every projection + GestureBinding need `Projection`/the four generics before
  `common/Projection.jl` can load, since that needs Primitive). DocumentApi, OperationApi
  and IoMapApi could merge into their impl modules without creating cycles — they are a
  style choice, not a necessity. Backend/Device/Agent have no impl counterpart at all.

### 2. Number of modules & dependencies between them

- 48 modules for one package. The projection algebra alone is 17 modules exporting 1–2
  names each; the `import ..ProjectionApiModule: projection_print, …` header is repeated
  ~17× inside the kernel and ~60× in domain.
- ProjecturedDomain must maintain a **37-line const-alias preamble** so its files can
  keep `..XxxModule` relative imports; test files use `Projectured.ReactiveModule.…`
  paths. Module names are therefore de-facto public API.
- Merge-safety audit: submodule exports have **no name collisions** (the umbrella's
  mechanical flattening already proves this), and among private helpers only
  `_strip_prefix` is defined in two files (`projection/generic/Focusing.jl`,
  `projection/generic/Searching.jl`). Consolidation is cheap.

### 3. External vs internal APIs

- `using ProjecturedKernel` currently exports **nothing** — the kernel has no flat API
  of its own. The flattening loop lives only in the `Projectured` umbrella, which
  re-exports *every* exported name of *every* submodule, uncurated. There is no
  external/internal distinction anywhere: whatever any file exports becomes public.
- Narrow internals leak into the public surface this way (e.g.
  `copying_field_iomap`, `prepend_steps_to_ref`, `perf_record!`).

### 4. Folder & file structure

- **Duplicate basenames**: `Document.jl`, `IoMap.jl`, `Operation.jl`, `Projection.jl`
  each exist in both `api/` and `common/`; `Screen.jl` exists in both `device/` and
  `document/`. Confusing in editor tabs, include lists, and grep output.
- **Inconsistent module naming**: api modules are `DocumentApiModule` /
  `OperationApiModule` / `ProjectionApiModule` / `IoMapApiModule` but `BackendModule` /
  `DeviceModule` / `AgentModule`; projection modules are 13× `XxxProjectionModule`
  but 4× plain (`TypeDispatchingModule`, `PredicateDispatchingModule`,
  `ReferenceDispatchingModule`, `EnvelopeUnwrappingModule`).
- `common/` is a grab-bag spanning L0–L5 (Reactive next to `@projection` defaults).
- Gesture machinery is scattered across three folders: `device/EventCase.jl`,
  `common/GestureBinding.jl`, `editor/GestureRecognizer.jl`.
- `editor/PrinterContext.jl`: inside the kernel it is imported only by projection-side
  files (ProjectionModule, Copying, Sorting, Reversing) — the editor never touches it —
  and it loads in the early infrastructure section. It reads as projection-layer
  infrastructure despite the recent move into `editor/`. (Flagged as an open decision,
  since that move was deliberate.)
- The agent control surface (`Agent` api, ToolRegistry, Llm, Mcp) is spread between
  `api/` and `editor/`. `editor/Mcp.jl` is the largest file in the kernel (901 lines);
  most of it is documentation/introspection *tools*, not MCP plumbing.

### 5. Separation of API definitions from implementations

The `api/` tier exists but is **impure and incomplete**:

- `api/Operation.jl` contains implementations: `NoOperation` + its
  `evaluate_operation` method, `splice_string`, `splice_number`, two `splice_value!`
  methods.
- `api/Backend.jl` contains the `make_backend` Val-dispatch registry, a
  `pointer_position` default, and the `display_size` provider with a module-level
  `Ref` global.
- `api/Agent.jl` contains the `make_agent_server` Val-dispatch implementation.
- `api/Device.jl` and parts of `api/Backend.jl` define **silent no-op methods**
  (`function write_to_device(::Backend, device, document) end`) instead of true stubs
  (`function write_to_device end`) — a missing backend method silently does nothing
  rather than erroring.
- Conversely, interface-ish defaults live outside `api/`: the four-generic fallbacks in
  `common/Projection.jl`, the `document_read` catch-all in `common/GestureBinding.jl`.

### 6. Documentation rot

- `ProjecturedKernel.jl` module docstring and the Llm/Mcp include comments still
  describe the LLM/MCP code as **weakdep extensions** (`ProjecturedLLMExt`,
  `ProjecturedMCPExt`) — `Project.toml` says they are standalone packages (`llm/`,
  `mcp/`) now.
- Stale pre-split paths: `program/src/common/Projection.jl` (`api/Projection.jl:70`),
  `program/ext/ProjecturedMCPExt.jl` (`editor/Mcp.jl:18`), `backend/Sdl.jl`
  (`api/Backend.jl:6`).

## Target structure (proposal)

Consolidate 48 modules → **~12 layer modules**, with folders matching layers matching
load order, and a single pure interface module at the bottom:

```
src/
  ProjecturedKernel.jl        # includes in folder order + curated flat re-export
  reactive/Reactive.jl        # ReactiveModule                                 (L0)
  api/…                       # ONE module (KernelApiModule?), several files:  (L0)
                              #   abstract types + `function foo end` stubs only
                              #   (Document, Operation, Projection, IoMap,
                              #    Backend, Device, Agent — pure, no globals)
  document/                   # DocumentModule (+@document), Collection,
                              #   Primitive, ScreenDocument
  reference/                  # ReferenceModule = Reference + ReferenceCase
                              #   + ReferenceBuilder (one module, three files)
  iomap/                      # IoMapModule (SimpleIoMap/ChildrenIoMap/@iomap)
  operation/                  # OperationModule + OperationRerooting
  device/                     # Modifiers, Keyboard, Mouse, ScreenDevice,
                              #   backend registry impl (make_backend, display_size)
  gesture/                    # GestureModule = EventCase + GestureBinding
                              #   (+ GestureRecognizer?)         — fixes the
                              #   private-name import by construction
  projection/                 # ProjectionModule = PrinterContext + defaults +
      higherorder/…           #   @projection + all 17 algebra files as plain
      generic/…               #   includes (rename one _strip_prefix)
  agent/                      # AgentModule = ToolRegistry + Llm + Mcp tools
                              #   (+ split Mcp.jl into McpTools / doc-tools?)
  editor/                     # EditorModule = Editor + (GestureRecognizer?)
```

Compatibility: ProjecturedDomain's alias preamble shrinks and keeps working — aliases
for merged modules point at the merged module (e.g.
`const ReferenceCaseModule = ProjecturedKernel.ReferenceModule`), so domain files'
`import ..ReferenceCaseModule: var"@reference_case"` still resolve. Clean the aliases
up in a later pass.

Rejected alternative — single flat namespace (no submodules at all): feasible
name-wise (see §2 audit) and maximally idiomatic, but it erases the layer boundaries
and the per-module docs, and makes every private helper share one namespace. The
layer-module middle ground keeps the boundaries that the architecture docs teach.

## Execution plan (phased, each phase independently landable)

### Phase 0 — hygiene, no structural change  **(DONE 2026-07-02)**
- [x] Fix docstring rot: extension→package wording in `ProjecturedKernel.jl`, `Llm.jl`,
      `Mcp.jl`; stale `program/src`/`program/ext`/`backend/Sdl.jl` paths.
      Done: rewrote the module docstring + Llm/Mcp include comments to the standalone
      `ProjecturedLlm` (`package/llm`) / `ProjecturedMcp` (`package/mcp`) reality;
      `AnthropicModule.stream_message` → `ProjecturedLlm.stream_message` (2 spots in
      `Llm.jl`); `program/src/common/Projection.jl` → `package/kernel/src/...`;
      `backend/Sdl.jl` → the opt-in `ProjecturedSdl` (`package/sdl`). Full
      `grep -rn "program/src|program/ext|Ext extension|weakdep|AnthropicModule|
      ProjecturedLLMExt|ProjecturedMCPExt|backend/Sdl" package/kernel/src` now clean.
- [x] Rewrite the include-list section comments to tell the truth (or reorder includes
      into honest sections where no dependency forbids it).
      Done: reordered the 48 includes (same set — verified by diffing the sorted include
      lists) into honestly-labelled sections: API stubs / Reactive engine / Document core
      & references / Input devices & events / Foundational documents / Gestures /
      Projection infrastructure & algebra / Projection defaults / Agent surface / Editor.
      Moves made: `common/Projection.jl` (ProjectionModule) → after the whole algebra
      (nothing in the kernel imports it); `editor/PrinterContext.jl` → leads the
      projection section (its only kernel consumers are projection-side); device modules
      grouped under "Input devices & events"; `editor/Llm.jl` → the agent-surface section
      with ToolRegistry + Mcp. Verified two ways: a static topo-check script (every file's
      `..Module` imports precede it) and the live load below.
- [x] Export (or stop importing) the EventCase internals used by GestureBinding.
      **Decision: documented, NOT exported** (and not renamed). Rationale: the
      `Projectured` umbrella mechanically re-exports *every* exported name of *every*
      kernel submodule, so exporting `_parse_rule`/`_EVENT_TYPES`/`EvPat`/`EvWild`/
      `EvBind`/`EvLit`/`EvInterp` would push these internals into the public flat API —
      strictly worse than a private cross-module import. The private-import seam is left
      in place with a "deliberately-shared parser internals" note at the definitions in
      `device/EventCase.jl` and a back-reference at the import site in
      `common/GestureBinding.jl`. The real fix is the **Phase 2** merge of EventCase +
      GestureBinding into one gesture module, after which the cross-module import vanishes.
- [x] Rename the twin basenames: `device/Screen.jl` → `ScreenDevice.jl` (or
      `document/Screen.jl` → `ScreenDocument.jl`).
      Done **both** renames via `git mv`: `device/Screen.jl` → `device/ScreenDevice.jl`
      and `document/Screen.jl` → `document/ScreenDocument.jl`. Module names left
      **unchanged** (`ScreenModule`, `ScreenDocumentModule`) since ProjecturedDomain, the
      SDL backend and tests alias them by module name. Updated the two `include(...)`
      lines, the sibling cross-ref inside `ScreenDevice.jl`, and the two live docs
      (`documentation/architecture.md`, `documentation/devices-and-backends.md`).
      Historical `plan/done/*.md` archives that mention the old path were left as-is
      (point-in-time records, mostly under the defunct `program/src/` tree).

### Phase 1 — guard rails
- [ ] Add a test (or generator script) that parses each file's `import ..X` headers and
      asserts the include list is a valid topological order — makes the hand-maintained
      order self-checking before anything moves.

### Phase 2 — module consolidation (the big one; order within phase = risk order)
- [ ] Merge Reference + ReferenceCase + ReferenceBuilder → one `ReferenceModule`.
- [ ] Merge EventCase + GestureBinding (→ `gesture/`).
- [ ] Merge the 17 projection-algebra modules + ProjectionModule + PrinterContext into
      one `ProjectionModule` (files stay separate; rename the duplicated
      `_strip_prefix`; unify the `XxxProjectionModule` naming question away).
- [ ] Merge api stubs: fold DocumentApi/OperationApi/IoMapApi into one pure
      `KernelApiModule` together with ProjectionApi, Backend, Device, Agent stubs.
- [ ] Group agent surface: ToolRegistry + Llm + Mcp (+ Agent stub stays in api).
- [ ] Update ProjecturedDomain aliases + llm/mcp package imports; keep old alias names
      pointing at merged modules for compatibility.

### Phase 3 — API surface
- [ ] Purify the api tier: move `splice_*` to `operation/`, `make_backend` registry +
      `display_size` provider + `pointer_position` default to `device/`,
      `make_agent_server` dispatch to `agent/`.
- [ ] Audit the silent no-op interface methods (`write_to_device` etc.): convert to
      true stubs where no caller relies on the no-op, document the rest.
      **Behavior-sensitive — needs a call-site audit per method.**
- [ ] Give the kernel (and domain) their own flat export surface: move the umbrella's
      mechanical re-export loop into each package — but **curated**: an explicit export
      list at the top module (internals stay reachable via qualified names; optionally
      mark them `public` on Julia ≥1.11). The umbrella then just re-exports two
      packages.
- [ ] Update `documentation/architecture.md` module inventory to the new layout.

## Open decisions (blocking Phase 2+)

1. **Consolidation depth**: layer modules (~12, recommended) vs keep one-module-per-file
   (fix naming/order only) vs single flat namespace.
2. **PrinterContext home**: `projection/` (its consumers) vs `editor/` (current, recent
   deliberate move) — what was the rationale for the move into `editor/`?
3. **One api module vs per-area api modules** — one pure `KernelApiModule` minimizes
   import boilerplate; per-area keeps today's shape.
4. **GestureRecognizer home**: `gesture/` (with its kin) vs `editor/` (its only caller).
5. Whether the umbrella's "re-export everything" convenience should survive as-is on
   top of a curated kernel/domain export list, or become curated itself.
