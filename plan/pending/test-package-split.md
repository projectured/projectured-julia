# Test package split

Replace the monolithic `package/test` (`ProjecturedTest`, 102 files) with a set of
**explicit test packages** that mirror the source-package DAG. Each test package
depends on the runtime package it tests plus `Test`, and reuses the generic test
drivers from `ProjecturedKernelTest`.

## Model — explicit sibling test packages

Test packages form their own DAG, parallel to the runtime DAG:

```
runtime:   ProjecturedKernel ← ProjecturedBase ← ProjecturedVisual ← ProjecturedDomain ← Projectured (umbrella) ← {Example, Sdl, Odbc, Tulip, Video}
tests:     ProjecturedKernelTest ← ProjecturedBaseTest ← ProjecturedVisualTest ← ProjecturedDomainTest ← ProjecturedTest (umbrella integration)
```

- **`ProjecturedKernelTest`** — deps: `ProjecturedKernel`, `Test`. Hosts (a) kernel's
  own unit tests, and (b) the **shared generic drivers** — `test_printer`,
  `test_reader`, `test_repl`, `walk_printer_output`, `walk_reader_events`,
  `walk_repl_loop`, the generic navigation/typein explorers, `WalkStatus`, `_walk!` —
  all exported. They already only call kernel API (`print_document`, `read_intent`,
  `evaluate_operation`, `clear_selection!`) + `Test`, so kernel is their natural home.
- **`ProjecturedBaseTest`** — deps: `ProjecturedBase`, `ProjecturedKernelTest`, `Test`.
- **`ProjecturedVisualTest`** — deps: `ProjecturedVisual`, `ProjecturedBaseTest`, `Test`.
- **`ProjecturedDomainTest`** — deps: `ProjecturedDomain`, `ProjecturedVisualTest`,
  `Test`. This is where `test_printer(json_example)` runs — the domain example is built
  here (later: imported from the split example package), the driver comes transitively
  from `ProjecturedKernelTest`.
- **`ProjecturedTest`** (existing umbrella) — now also deps the four `*Test` packages +
  the full runtime stack (`Example`, `Sdl`, `Odbc`, `Tulip`, `Video`). Keeps only the
  full-stack integration suite and the `Example`-typed driver overloads.

Each test package follows the umbrella's **function-library model**: `src/` exports
`test_<layer>()` (aggregator) + the individual `test_*` functions, callable
interactively from the root env (`julia --project=.`). Optionally a one-line
`test/runtests.jl` (`using ProjecturedKernelTest; test_kernel()`) so `Pkg.test` works
too.

### Assigned UUIDs

```
ProjecturedKernelTest = "8053727f-93c2-44b0-a108-4c98e4ff6a44"
ProjecturedBaseTest   = "13b5dafd-eba4-481d-8e1b-67ff5e19061b"
ProjecturedVisualTest = "38f1c7f4-274b-4c10-ad20-becff0e69ef8"
ProjecturedDomainTest = "5a3bf5be-5cdd-4f4d-8463-417e5a608a2d"
```

Directories: `package/kernel-test/`, `package/base-test/`, `package/visual-test/`,
`package/domain-test/` (sibling to the existing umbrella `package/test/`). Each new
package is added to the **root `Project.toml`** `[deps]` **and** `[sources]` (path), so
`using ProjecturedKernelTest` resolves from the root test env (memory:
test-env-is-repo-root-project).

## What this replaces (already on disk)

The in-progress `[extras]` + `[targets] test` per-package model — `package/kernel/test/`,
`package/base/test/`, `package/domain/test/`, `package/visual/test/` and the
`[extras] Test` / `[targets] test` lines in those runtime `Project.toml`s — is
**superseded**. Its content migrates into the new test packages and the old folders +
Project.toml lines are removed:

- The substantive kernel tests under `package/kernel/test/{cell,agent,backend,device,
  document,operation,reference}/` → `ProjecturedKernelTest`.
- `package/base/test/document/CollectionTest.jl` → `ProjecturedBaseTest` (reconcile with
  the drifted umbrella copy; base version canonical).
- The four near-identical **static layered-architecture guards**
  (`*/test/runtests.jl`) → a single shared `check_layering(src_root, top_file, layers,
  aliases)` helper exported from `ProjecturedKernelTest`; each `test_<layer>()` calls it
  with that package's src root + declared layers. De-duplicates ~200 lines × 4.

## Design principles

1. **Lowest-home rule.** A test goes to the test package for the lowest runtime package
   whose public API it uses. "No new runtime deps" is the constraint: a test needing
   `Sdl`/`Odbc`/`Tulip`/`Example` stays in the umbrella `ProjecturedTest`.
2. **Drivers generic, examples layered.** The `(document, projection)` driver forms are
   layer-agnostic → in `ProjecturedKernelTest`. The `(example::Example)` overloads +
   global-`examples` sweeps stay in the umbrella (until examples split — see below).
3. **Subfolders mirror src slices** so tests stay legible; the shared `check_layering`
   helper keeps enforcing src include-order/layer discipline from the test package.

## Classification of the 102 umbrella files

*(entries marked (confirm) need a quick src-layer check at move time)*

**→ ProjecturedKernelTest** — `reference/TypeReferenceTest`, `common/GestureBindingTest`,
`device/EventCaseTest` (plus the already-migrated `cell/`, `agent/`, `backend/`,
`device/`, `document/`, `operation/`, `reference/` from `package/kernel/test/`).

**→ ProjecturedBaseTest** — `document/PrimitiveTest`, `document/CollectionTest`,
`serializer/SerializationTest`; generic doc-shaped projections (confirm base-only):
`SelectionInvertingTest`, `CopyingProjectionTest`, `ProjectionConfiguringTest`,
`ClipboardToAnyTest`, `VersioningToAnyTest`.

**→ ProjecturedVisualTest** — docs: `SyntaxTest`, `TextTest`, `GraphicsTest`,
`GeometryTest`, `GraphicsLayoutTest`, `LayoutAllocatorTest`; backends:
`ConsoleBackendTest`, `PdfTest`, `DirtyRectTest`; text/graphics projections:
`SyntaxToTextTest`, `PrimitiveToTextTest`, `TextToGraphicsTest`, `WordWrappingTest`,
`TextFilteringTest`, `TextHighlightingTest`; widget projections: `ObjectToWidgetTest`,
`Widget{Button,TextEdit,Gesture,Select,Menu,ContextMenu,Dialog,Action,Icon,Tree,
Toolbar,Table,Forms}Test`, `LayoutCloseoutTest`, `AnchorPointTest` (confirm).

**→ ProjecturedDomainTest** — docs: `JsonTest`, `JsonParserTest`, `SqlParserTest`,
`SqlDocumentTest`, `TabularTest`; projections: `JsonToSyntaxTest`, `XmlToSyntaxTest`,
`SqlToSyntaxTest`, `FormulaToSyntaxTest`, `FileSystemToSyntaxTest`, `GraphTest`;
`ProjectionTemplateTest`, `AtomicFixtureTest` (confirm layer).

**stays in ProjecturedTest (umbrella)** — all `editor/*` (Printer/Example/Repl/Reader/
Typein/Julia/Mcp/Conversation*/GestureRecognizer/MouseClick/ClickRoundtrip/Collapse/
SyntaxTreeNav/TextNav/SelectionEnumeration/PrinterLocality/RecursionContract/Video/
WorkbenchFile/AssistantMvp/ConversationPanel); example/editor-coupled projections
(`Dragging`, `SplitPaneDrag`, `WorkbenchTabClick`, `Tooltip`, `HoverProbe`,
`GraphicsToFile`(SDL), `Catalog`, `ConversationEditor`, `DocumentInsertion`,
`GestureMap`, `GestureHelp`, `Focusing`(confirm), `WidgetPopupExample`);
`ConstraintSolverTest` (Tulip); `external/*` (Odbc live-DB).

## Phases

Discipline every phase: move file → narrow its `using` to the target package's API +
`ProjecturedKernelTest` drivers → register in the test package's `test_<layer>()`
aggregator → **delete the old copy** (umbrella and/or `package/*/test/`) → run
`test_<layer>()` from the root env **and** confirm the umbrella still loads → commit.
(Memory: precompile-green ≠ loads — verify with an actual `using`.)

- [ ] **Phase 0 — `ProjecturedKernelTest`.** Create `package/kernel-test/`
  (Project.toml with the UUID above, deps `ProjecturedKernel` + `Test`). Move the
  generic driver bodies out of the umbrella's `editor/{PrinterTest,ReaderTest,ReplTest,
  TextNavigationTest,SyntaxTreeNavigationTest,TypeinTest,ClickRoundtripTest}.jl` into
  it and export them. Move `package/kernel/test/*` into it; fold the four layering
  guards into a shared exported `check_layering(...)` + `test_kernel_layering()`.
  Expose `test_kernel()`. Add to root `[deps]`+`[sources]`; delete `package/kernel/test/`
  and kernel's `[extras]`/`[targets]`. Point the umbrella at `using ProjecturedKernelTest`
  (drop moved driver bodies; keep `Example` overloads + sweeps). Verify `test_kernel()`
  and umbrella load.
- [ ] **Phase 1 — `ProjecturedBaseTest`.** `package/base-test/` (deps `ProjecturedBase`,
  `ProjecturedKernelTest`, `Test`). Move `PrimitiveTest`, reconcile `CollectionTest`,
  `SerializationTest`, generic projections; `test_base()` (calls `check_layering` on
  base src). Delete `package/base/test/` + umbrella copies.
- [ ] **Phase 2 — `ProjecturedVisualTest`** (largest). `package/visual-test/` (deps
  `ProjecturedVisual`, `ProjecturedBaseTest`, `Test`). Move docs + Console/Pdf/DirtyRect
  backends + text/graphics/widget projection tests on local fixtures + kernel drivers;
  `test_visual()`. Delete `package/visual/test/` + umbrella copies.
- [ ] **Phase 3 — `ProjecturedDomainTest`.** `package/domain-test/` (deps
  `ProjecturedDomain`, `ProjecturedVisualTest`, `Test`). Move json/xml/sql docs +
  parsers + `*_to_syntax` + graph; build the domain examples here and drive them with
  `test_printer(json_example)`; `test_domain()`. Delete `package/domain/test/` + umbrella
  copies.
- [ ] **Phase 4 — umbrella shrink & docs.** `ProjecturedTest` deps the four `*Test`
  packages + runtime stack; `test_all()` = `test_kernel();test_base();test_visual();
  test_domain();` + the remaining integration tests. Keep `Example`-typed overloads.
  Update `CLAUDE.md` "Testing a change" + `documentation/testing.md` for the new
  per-package entry points.

## Future phase (out of scope — noted for forward-compatibility)

Examples split among packages later. Until then, low test packages build **small local
fixture documents** inline (as migrated kernel/base tests already do). Once examples
split, each test package imports its own example set and calls `test_printer(example)`
via the same `ProjecturedKernelTest` drivers — no driver changes. Keep the driver
signatures example-shape-agnostic (`(document, projection)` or an object with
`.name/.document/.projection`) so this is a no-op swap.

## Risks

- **Drift:** never leave a test in two places (already true of `CollectionTest`). Delete
  on move.
- **Over-broad `using`:** a moved test often uses more than the target layer; narrowing
  it to that layer's API (so it resolves in the smaller test package) is the real work.
- **Test-package DAG cycles:** keep the `*Test` chain strictly parallel to the runtime
  DAG; a test package must never depend on a runtime package above its own layer.
- **Root env wiring:** each `*Test` must be in root `[deps]` + `[sources]`, else
  `using` fails from the root test env.

## Out of scope

Splitting `examples`; converging the interactive `test_*()` functions onto `Pkg.test`;
adding tests to `sdl/web/llm/mcp/odbc` (they have none yet).
