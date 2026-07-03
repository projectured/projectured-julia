# Kernel layered architecture — kernel/base package split with strict layers

Design review of `package/kernel` (2026-07-03): reorganize the kernel into a strict
layered architecture split across **two packages** — a slow-changing `ProjecturedKernel`
(machinery + interfaces only) and a new faster-changing **`ProjecturedBase`**
(`package/base`, all concrete documents and projections). Each layer gets its own folder,
its own tests, and its own documentation. Clarity, maintainability, and ease of
understanding are the priorities; backward compatibility is explicitly **not** a
constraint (module renames/merges are fine), but all in-repo consumers (domain, umbrella,
llm, mcp, sdl, web, test) are updated in the same effort so the repo stays green.

Decisions taken during the design review:

- **Fine layers**, strict rule: layer N imports only layers < N.
- **Each layer owns its interface** — the separate `api/` stub tier dissolves into the
  layers that own the concepts (a higher layer adds methods to a lower layer's generics
  where its types are involved — standard multiple-dispatch layering).
- **Two packages.** This dissolves the confusing "document layer = contract vs
  vocabulary layer = concrete documents" split inside one package: `kernel/document` is
  unambiguously the contract, `base/document` unambiguously actual documents.
- **All concrete documents leave the kernel** (Collection, Primitive, ScreenDocument
  included); the editor is decoupled from them (verified cheap — see R5).
- **Document-free projections stay in the kernel** (Chaining, Identity, Constant, the
  dispatchers, …): they are the *structure* of a pipeline, not its content. A projection
  is kernel-side iff it imports no concrete document — machine-checkable, guard-enforced.
- **Per-layer tests inside each package**; kernel tests use test-local toy
  documents/projections only — permanent pressure that the kernel interfaces stay
  sufficient. `ProjecturedTest` keeps cross-package/domain/pipeline tests.
- One folder per layer, plain names (order machine-enforced by the guard, no numeric
  prefixes).

Supersedes the "Target structure (proposal)" section and the remaining Phase 2 items of
[kernel-cleanup.md](kernel-cleanup.md); its findings, audits, and completed phases
remain valid and are reused here.

## The layer stacks

**The first layer is `cell`** — the reactive cell engine: dependency-free,
understandable/testable/documentable in complete isolation; everything above is built
from it.

### ProjecturedKernel — 9 layers, zero concrete documents

| # | Folder | Modules | Story |
| --- | --- | --- | --- |
| 1 | `cell/` | `PerformanceCounterModule`, `CellModule` (+4 kind fragments), `TimeModule` (moved from `editor/` — it is just a global `Cell`; domain projections consume it) | a spreadsheet cell: read tracks, write invalidates |
| 2 | `document/` | `DocumentModule` (absorbs `DocumentApiModule`): `Document` abstract, `@document`, selection contract, `snapshot`/`copy_document`/`rekind` | what a document is |
| 3 | `reference/` | `ReferenceModule` (absorbs ReferenceCase + ReferenceBuilder) | paths into documents |
| 4 | `operation/` | `OperationModule` (absorbs OperationApi + OperationRerooting): `Operation` abstract, built-in generic ops, `evaluate_operation`, splice helpers, open rerooting/traversal seams | changing documents |
| 5 | `device/` | `DeviceModule` (ex-DeviceApi), `ModifiersModule`, `KeyboardModule`, `MouseModule`, `ScreenDeviceModule`, `GestureModule` (EventCase + GestureBinding merged; owns the rehomed `EventEnvelope` and the `read_gesture` declaration), `GestureRecognizerModule` | input devices, events, gestures |
| 6 | `backend/` | `BackendModule` (ex-BackendApi: `Backend`, `initialize_backend!`/`quit_backend!`/`measure_text`, `make_backend` factory), `DisplayModule`, new `HeadlessBackendModule` (in-memory render target + scripted event source — document-agnostic; used by kernel editor tests, CI, file output) | rendering targets |
| 7 | `projection/` | `ProjectionModule` (absorbs ProjectionApi + Intent + IoMap/IoMapApi + PrinterContext + `@projection` + Primitive-free defaults) plus the **12 document-free combinators** as fragments: Identity, Constant, Chaining, Switching, TypeDispatching, PredicateDispatching, ReferenceDispatching, Recursive, Nesting, EnvelopeUnwrapping (document-free after R5), Focusing, Reversing (verified: none imports a concrete document) | how documents transform: the four-generic interface + the structural pipeline algebra |
| 8 | `agent/` | `AgentModule` (ex-AgentApi), `ToolRegistryModule`, `LlmModule`, `McpModule` | the AI control surface (side-stack; the editor reaches it only via `make_agent_server`) |
| 9 | `editor/` | `EditorModule`, `PlaybackModule` | the read-eval-print loop |

### ProjecturedBase (new, `package/base`) — 2 layers, depends only on ProjecturedKernel

| # | Folder | Modules | Story |
| --- | --- | --- | --- |
| 1 | `document/` | `CollectionModule`, `PrimitiveModule`, `ScreenDocumentModule` — plus their methods on kernel seams (`child_reference_steps(::CellVector)`, `reroot_operation` for the splice-range ops, their `evaluate_operation` methods) | the concrete documents everything ships with |
| 2 | `projection/` | the 5 document-dependent projections — Sorting, Filtering, Searching, Copying (import `CellVector`/`ListNode`), WindowManaging (the ScreenDocument window model) — plus the Primitive-dependent reader defaults (R6), consolidated into one module (working name `BaseProjectionModule`; final name decided at implementation, umbrella collision-checked) | the document-shaped projection library |

Package chain: **kernel ← base ← domain ← umbrella**; `llm`/`mcp` ← kernel only;
`sdl`/`web` ← domain (unchanged). Standing boundary rules for future code: a *document*
is kernel-side only if the machinery itself needs it (currently: none); a *projection*
is kernel-side iff it imports no concrete document.

### No-cycle verification (2026-07-03)

Statically verified over the real import headers (all 53 modules, 181 `..Module` edges):
the raw module graph is a DAG (no cycles today), and after applying the six planned
refactors below as edge rewrites (4 edges dropped, 4 retargeted), **every edge points to
the same or a lower layer, with no kernel→base edge**. Notable legal edges:
`base/projection → kernel projection` ×15 (base implements the kernel interface),
`editor → agent` ×1 (the factory seam), `device → document` ×1 (GestureBinding reaching
down to the Document contract).

A layering pattern worth documenting (it looks like a cycle until you see the trick):
`ProjectionReference` ([reference/Reference.jl](../../package/kernel/src/reference/Reference.jl)
line ~231) stores its projection as an **untyped `Any` payload** — the reference layer
defines only the step's shape and never imports `Projection`; only higher layers
construct and interpret the payload (same pattern as `Intent`). So projection → reference
(PrinterContext, reference mapping) is the only edge, and it points down.

## The six refactors (the only semantic changes; all verified against source)

- **R1 — Operation → Collection** (`common/Operation.jl:23` + the `node isa CellVector`
  branch of `_preorder_documents!`, used by `SelectNextInsertionOperation`): declare an
  open traversal seam `child_reference_steps(node)` in kernel operation with the current
  `fieldnames`-walk default; base `Collection.jl` adds the `CellVector` method.
- **R2 — OperationRerooting → Primitive** (`common/OperationRerooting.jl:65-68`): convert
  `reroot_operation`'s closed if-chain to an open generic (methods for `Nothing`,
  catch-all, `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation`,
  `CompoundOperation`); base `Primitive.jl` adds the `ReplaceStringRangeOperation` /
  `ReplaceNumberRangeOperation` methods. Rewrite the `INVARIANT` comments: "a new
  path-bearing operation must add a `reroot_operation` method".
- **R3 — GestureBinding → ProjectionApi** (verified: only the `Projection` type in 3 seam
  functions, `common/GestureBinding.jl:334-389`): move `get_projection_gesture_bindings`
  (+default), `read_projection_gesture`, and the default
  `collect_gesture_bindings(p::Projection, …)` up into kernel projection's interface.
  The rest of GestureBinding is projection-free and stays at layer 5.
- **R4 — GestureBinding imports EventCase privates** (`_parse_rule`, `EvPat`, …): fixed
  by construction — both files become fragments of one `GestureModule`.
- **R5 — EventEnvelope rehome** (enables the full document extraction): move
  `EventEnvelope` from `ScreenDocumentModule` into kernel `GestureModule`. Verified:
  Editor, Playback, and GestureRecognizer import **only** `EventEnvelope` from
  ScreenDocument (`ScreenDocument` otherwise appears in their docstrings only), so this
  one type relocation fully decouples the editor from concrete documents. Retarget the 5
  kernel import sites + Console (domain). Window events/ops (`WindowResize`,
  `OpenWindowOperation`, …) stay with ScreenDocument in base.
- **R6 — split the projection defaults** (`common/Projection.jl`): the `@projection`
  macro, `pure_print` and Primitive-free fallbacks stay in kernel `ProjectionModule`;
  the default `read_intent` chains referencing `ReplaceStringRangeOperation` /
  `ReplaceNumberRangeOperation` move to base/projection as methods added from there.
  Exact split determined at implementation; the guard + kernel toy-doc tests verify the
  kernel half stands alone.

## Per-layer tests

Rule: a layer's tests import only that layer and below (statically enforced by the
guard). Kernel tests use ONLY toy documents/projections defined test-locally.

Kernel (`package/kernel/test/<layer>/`):

- **cell**: migrate `CellTest.jl` from ProjecturedTest (rewritten to
  `using ProjecturedKernel`); new `PerformanceCounterTest.jl`, `TimeTest.jl`.
- **document**: new `DocumentContractTest.jl` — a test-local `@document struct ToyNode`;
  selection contract, cell auto-wrap, `snapshot`/`copy_document`/`rekind` round-trips.
- **reference**: migrate `ReferenceBuilderTest.jl`; new `ReferenceEvalTest.jl`
  (`@reference`, `evaluate_reference` on ToyNode trees, `@reference_case`).
- **operation**: new `EvaluateTest.jl` (toy `FakeEditor`; built-in ops),
  `SelectionTest.jl`, `RerootingTest.jl` (incl. a test-local op type +
  `reroot_operation` method proving the R2 seam), `TraversalTest.jl` (test-local
  `child_reference_steps` method proving R1).
- **device**: migrate `EventCaseTest.jl`, `GestureBindingTest.jl`,
  `GestureRecognizerTest.jl`; EventEnvelope round-trips.
- **backend**: new `BackendSeamTest.jl` (`make_backend(:unregistered)` errors helpfully;
  display provider), `HeadlessBackendTest.jl`.
- **projection**: new `InterfaceTest.jl` (a toy projection over ToyNode exercising the
  four generics, `@projection`, IoMap accessors, PrinterContext, gesture-seam defaults);
  new `AlgebraTest.jl` (the 12 structural combinators composed over toy documents —
  Chaining/TypeDispatching/Recursive round-trips, ReferenceDispatching on toy paths,
  Focusing/Reversing forward+backward reference mapping).
- **agent**: new `ToolRegistryTest.jl`, `AgentSeamTest.jl`.
- **editor**: new `EditorLoopTest.jl` — full read→evaluate→print cycle: toy document +
  toy projection + `HeadlessBackend`; `QuitEditorOperation` exits;
  `invalidate_projection!` drops the cache; `PlaybackTest.jl` smoke. (Biggest current
  kernel-local test gap.)

Base (`package/base/test/<layer>/`):

- **document**: migrate `CollectionTest.jl`; new `PrimitiveKernelTest.jl` (splice ops
  end-to-end incl. reroot), `ScreenDocumentTest.jl` (window ops),
  `SelectNextInsertionTest.jl` (the R1 CellVector method).
- **projection**: `CollectionProjectionTest.jl` (Sorting/Filtering/Searching/Copying over
  a CellVector of primitives + reference round-trips), `DefaultReaderTest.jl` (R6 reader
  defaults retarget each path-bearing op), `WindowManagingTest.jl`,
  `GestureCollectTest.jl` (`collect_gesture_bindings` through Chaining over a
  `@gestures`-declared base document).

Domain-flavored tests (`PrimitiveTest.jl`, `TypeReferenceTest.jl`, `McpTest.jl`,
pipeline/example tests) stay in ProjecturedTest.

## Guards (per package, extending `package/kernel/test/runtests.jl`)

Finding: the kernel guard is **currently red on disk** — `extract_includes` reads only
the top file while the file-set check walks all of `src/`, so the four `cell/*.jl`
fragments (included by `CellModule.jl`, not the top file) fail `Set(includes) ==
on_disk`, and `module_and_deps` errors on 0-module fragment files. P0 fixes this first.

1. **Fragment-aware include tree**: recursively follow `include(...)`; every on-disk
   file reached exactly once; a 0-module file is a fragment of its nearest
   module-defining ancestor; a module's deps = the union over its fragments (this is
   what catches `cell/ReactiveCell.jl`'s `_perf` import today).
2. **Layer manifest**: kernel `LAYERS = ["cell","document","reference","operation",
   "device","backend","projection","agent","editor"]`; base `LAYERS = ["document",
   "projection"]` (same guard code). Assert: every include lives under a LAYERS folder
   (non-LAYERS folders exempt during transition; the final phase forbids them); the
   include list is grouped by non-decreasing layer index; **every `..Dep` resolves to a
   folder of index ≤ its own**.
3. **Test-side layer rule**: statically parse `test/<layer>/` for
   `ProjecturedKernel.XxxModule` (resp. `ProjecturedBase.XxxModule`) references;
   referenced layer ≤ folder layer. Kernel tests referencing `ProjecturedBase` at all is
   an error.
4. **Per-layer runner**: after the static checks, load the package and include
   `test/<layer>/runtests.jl` per layer, filterable via
   `Pkg.test(test_args=["projection"])`; each layer's runtests is also directly
   runnable.
5. Keep the `topo_errors` self-tests; add a synthetic-upward-edge self-test for the
   layer rule.

## Per-layer documentation

- `package/kernel/doc/`: `cell.md` (absorbs `reactive.md`), `document.md`,
  `reference.md` (documents the `ProjectionReference` opaque-payload pattern),
  `operation.md`, `device.md`, `backend.md`, `projection.md`, `agent.md`, `editor.md` —
  each: the layer's story, its interface (what higher layers/extenders implement),
  invariants, "what belongs here" rule. Rewrite `doc/architecture.md` around the 9-layer
  diagram + guard + the kernel/base boundary rule + extension recipes ("methods live
  where types live").
- `package/base/doc/`: `architecture.md` (the two layers, the boundary rule, how a new
  document/projection is added), `document.md`, `projection.md`.
- Repo-level: update `documentation/architecture.md` package diagram (kernel ← base ←
  domain ← umbrella) and module inventory; fix stale paths in `reactive-cells.md` etc.

## Consumer updates (each phase, same commit)

- **`package/base`** (new): `Project.toml` (dep: ProjecturedKernel only),
  `src/ProjecturedBase.jl` with the same alias-block pattern domain uses
  (`const CellModule = ProjecturedKernel.CellModule`, …) so moved files keep relative
  `..XxxModule` imports.
- **`package/domain/src/ProjecturedDomain.jl`**: add the ProjecturedBase dep; the alias
  block points each dissolved/moved module at its new home
  (`const DocumentApiModule = ProjecturedKernel.DocumentModule`,
  `const CollectionModule = ProjecturedBase.CollectionModule`, projection aliases split
  between `ProjecturedKernel.ProjectionModule` and base's module per symbol, …). Domain
  file edits only where one old module's names split across two homes: the R3
  gesture-seam functions, `read_gesture`, `EventEnvelope` (R5), the R6 defaults —
  grep-driven.
- **Umbrella** (`package/projectured`): extend the mechanical re-export loop to iterate
  ProjecturedBase too; loading it is the collision check.
- **`package/mcp`**: `AgentApiModule → AgentModule`. **`package/llm`**: untouched.
- **sdl/web/video/executable/example/test**: grep
  `(Projectured|ProjecturedKernel)\.\w*Module` per phase; known hits are small
  (`DocumentApiModule` ×2, `ProjectionApiModule` ×1, `OperationRerootingModule` ×1,
  Console's `BackendApiModule`/`EventEnvelope`).
- **ProjecturedTest**: remove migrated files + include/export lines.
- Root `Manifest.toml`/`Project.toml`: register the new base package path.

## Execution plan (phased; each phase lands green)

Verification per phase: **V1** `Pkg.test("ProjecturedKernel")` (static guards +
per-layer tests) — plus `Pkg.test("ProjecturedBase")` once it exists · **V2**
`julia --project=. -e 'using Projectured'` (umbrella load = collision + alias check) ·
**V3** the ProjecturedTest `test_*` functions touching the moved area.

- [ ] **P0 — guard rework**: fragment-aware include tree (fixes the existing red —
      verify before/after), `LAYERS=["cell"]` + per-layer runner skeleton + self-tests.
- [ ] **P1 — cell**: `git mv editor/Time.jl cell/Time.jl`; CellModule docstring tweak
      (Time now lives beside the engine); migrate CellTest + new tests; `doc/cell.md`.
- [ ] **P2 — document (contract)**: merge DocumentApi into `DocumentModule`; move
      `common/Document.jl`; retarget ~9 importers + aliases; ToyNode contract tests;
      `doc/document.md`. (Concrete documents stay put until P7. Note: `IoMapModule`
      imports the private `_cell_autowrap_ctor`/`_cell_property_accessors` — keep as a
      documented downward private seam.)
- [ ] **P3 — reference**: merge the trio into `ReferenceModule`; retarget 5 kernel
      importers + aliases; migrate/new tests; `doc/reference.md`.
- [ ] **P4 — operation**: merge OperationApi + Operation + Rerooting into
      `OperationModule`; **R1 + R2 seams** (the concrete methods land beside
      Collection/Primitive at their current location, moving with them in P7);
      INVARIANT rewrites; seam tests; `doc/operation.md`.
- [ ] **P5 — device**: DeviceApi rename; **R4** GestureModule merge; **R5**
      EventEnvelope rehome (retarget 5 kernel sites + Console); GestureRecognizer +
      ScreenDevice moves; `read_gesture` rehome; GestureModule temporarily keeps
      `import ..ProjectionApiModule: Projection` (api/ guard-exempt until P8); update
      sdl/web refs; tests; `doc/device.md`.
- [ ] **P6 — backend**: `BackendApiModule → BackendModule` rename + move; Display move;
      new HeadlessBackend + tests; retarget Console/Pdf/sdl/web; `doc/backend.md`.
- [ ] **P7 — base package + base/document**: create `package/base` (Project.toml, alias
      preamble, its own guard with `LAYERS=["document"]`); `git mv`
      Collection/Primitive/ScreenDocument (+ their R1/R2 methods) to
      `base/src/document/`; umbrella loop extended; domain gains the base dep + alias
      retargets; migrate/new base document tests; `base/doc/document.md`.
- [ ] **P8 — projection split** (biggest; 3–4 green sub-commits): kernel
      `ProjectionModule` consolidates ProjectionApi + Intent + IoMap/IoMapApi +
      PrinterContext + `@projection` + Primitive-free defaults + the 12 document-free
      combinators as fragments (**R3** completes here; GestureModule drops the
      Projection import); the 5 document-dependent projections + **R6** reader defaults
      move to `base/src/projection/` (one consolidated module; rename `Searching.jl`'s
      `_strip_prefix` — it collides with Focusing's); ~24 alias updates split between
      the two new homes; base `LAYERS=["document","projection"]`. Verify with
      `test_reader`/`test_typein` + Copying/Focusing tests from ProjecturedTest.
- [ ] **P9 — agent**: moves + `AgentModule` rename; mcp package update; new agent
      tests; `doc/agent.md`.
- [ ] **P10 — editor + closeout**: Editor/Playback import retargets; delete empty
      `api/`/`common/`/old folders; LAYERS complete + exemptions removed in both
      guards; HeadlessBackend loop test; `doc/editor.md`; rewrite kernel/base/repo
      architecture docs; full ProjecturedTest sweep.

Risk concentration: P4 (semantic refactor — mitigated by the seam tests landing with
it), P7 (new package wiring — mitigated by the alias-preamble pattern domain already
proves out), P8 (bulk move + R6 split — mitigated by sub-commits; the umbrella load
after each is the observable check). Everything else is mechanical moves under machine
guards.

## Open decisions (implementation-time, non-blocking)

1. Name of the consolidated base projection module (`BaseProjectionModule` is the
   working name; umbrella collision check decides).
2. Exact R6 split line inside `common/Projection.jl` (which defaults are truly
   Primitive-free); the kernel toy-doc tests are the arbiter.
3. Whether `Reversing` (statically document-free but a sibling of Sorting/Filtering)
   stays kernel-side per the rule or moves to base for family cohesion — the rule says
   kernel; revisit only if it confuses.
4. Whether `Mcp.jl` (901 lines, mostly doc-introspection tools) splits into
   `Mcp.jl` + `McpDocTools.jl` fragments of one module (cosmetic follow-up).
