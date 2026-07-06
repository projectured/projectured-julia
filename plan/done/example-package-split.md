# Example package split

> **Status: done.** Deviations resolved at move time per the lowest-home rule
> (documentation/architecture-rules.md):
>
> - **`ProjecturedBaseExample` was not created**: every runnable example pairs
>   its document with a projection to a presentable output domain, and even
>   the collection/lazy pipelines go through the visual `CollectionToSyntax`
>   → `SyntaxToText` fabric — the base tier has no examples, and packages are
>   a strict boundary. The example DAG is kernel ← visual ← domain ← umbrella.
> - There are no kernel-tier examples either: `ProjecturedKernelExample` is
>   pure harness (the `Example` struct, `write_example_image` /
>   `record_example_video` via the kernel seams, `make_typein_gestures`).
> - The **gallery** (`run_example` + window-scene helpers + `Wrapper.jl`) went
>   to **domain-example**, not visual: its workbench / tooltip / inspector /
>   clipboard wrappers are domain vocabulary. `run_console_example` (json
>   pipeline defaults) and `record_assistant_conversation_video` went with it.
> - `focusing_example` is a JSON pipeline → domain; `rotating_vector_example`
>   builds a GraphicsCanvas → visual; `dragging` docs are JSON → domain;
>   `object`/`Wrapper` reflections split (ObjectToSyntax is visual; the
>   wrapper toolkit is domain per its clipboard parts); `print_example` uses
>   the visual `print_object` → visual-example.
> - The `Example`-typed `test_tree_navigation` overload (JsonDocument default
>   enumerator) lives in domain-test, beside `collect_json_tree_selections`.
> - The per-tier printer sweeps surfaced one more pre-existing failure:
>   `json_sorted`'s printer walk dies in RJsonObject positional construction
>   through `SortingAtProjection` — the same cell-kinds @document-constructor
>   drift family as TabularTest/ClipboardToAnyTest.

Split the monolithic `package/example` (`ProjecturedExample`, ~90 files) into
**explicit per-layer example packages** that mirror the source-package DAG,
exactly like plan/done/test-package-split.md did for the tests. Each example
package depends on the runtime package whose vocabulary its examples use plus
the example packages below it. The **example harness moves to its respective
package too**: each harness piece lands in the lowest package whose API it
hard-references (the `Example` struct is layer-agnostic → bottom; the
screen/window gallery composition is visual → visual; the cross-domain
registry, catalog and LLM-coupled pieces stay in the umbrella).

## Model — explicit sibling example packages

Example packages form their own DAG, parallel to the runtime and test DAGs:

```
runtime:   ProjecturedKernel ← ProjecturedBase ← ProjecturedVisual ← ProjecturedDomain ← Projectured ← {Sdl, Odbc, Tulip, Video, Llm}
examples:  ProjecturedKernelExample ← ProjecturedBaseExample ← ProjecturedVisualExample ← ProjecturedDomainExample ← ProjecturedExample ← ProjecturedExtrasExample
tests:     ProjecturedKernelTest ← ProjecturedBaseTest ← ProjecturedVisualTest ← ProjecturedDomainTest ← ProjecturedTest
```

- **`ProjecturedKernelExample`** — deps: `ProjecturedKernel`. Hosts the
  **harness core**: the `Example` struct (name, `make_document` /
  `make_projection` thunks, materialized pair, `render_width`/`render_height`,
  the `terminal` pivot) — plus the kernel-only examples (`focusing_example`,
  `rotating_vector_example` (confirm — check `make_rotating_vector_document`'s
  vocabulary; if it needs `CellVector` it is base)). Also `print_example`
  (confirm): it builds an `Editor` and obtains the console backend through the
  `make_backend(:console)` seam, so it compiles against kernel API alone — the
  console backend only has to be *loaded* at call time, which every consumer
  above guarantees.
- **`ProjecturedBaseExample`** — deps: `ProjecturedBase`,
  `ProjecturedKernelExample`. The collection examples and the generic
  doc-shaped projection examples over them.
- **`ProjecturedVisualExample`** — deps: `ProjecturedVisual`,
  `ProjecturedBaseExample`. The text/syntax/widget/layout examples and the
  **visual half of the harness**: the `run_example` gallery composition
  (it hard-constructs `WindowDocument`/`ScreenDocument`/`WidgetScrollPane`/
  window-managing projections), `write_example_image`, `write_example_pdf`.
  Like today, SDL is reached only through the `make_backend(:sdl)` /
  `write_image` seams — **no ProjecturedSdl dependency**; the backend package
  must be loaded by the caller (root env, executable, ProjecturedTest).
- **`ProjecturedDomainExample`** — deps: `ProjecturedDomain`,
  `ProjecturedVisualExample`. All concrete-domain examples (json/xml/sql/…)
  and the `FileEditor` harness (`EditorDomain` + the per-domain editor domains
  + `run_file_editor` — its domain table hard-references json/text/xml
  loaders, so this is its lowest home).
- **`ProjecturedExample`** (existing umbrella — keeps its name and UUID) —
  deps: the four `*Example` packages + `Projectured` + `ProjecturedLlm` +
  `Profile`. Keeps only what is genuinely cross-cutting or opt-in-coupled:
  the global `examples` registry (it enumerates every tier), the
  assistant/conversation examples (LLM seam registration via
  `using ProjecturedLlm`), `Catalog.jl` (discovers examples across every
  loaded domain), `LiveExamples.jl` (drives `record_video` / `play_live!` —
  video/SDL presentation), `run_example(name::String)` (registry lookup), and
  `demo/`. Re-exports the lower packages' exported names with the same
  mechanical loop `Projectured` uses, so `using ProjecturedExample` keeps
  providing every example and factory unchanged.
- **`ProjecturedExtrasExample`** (existing) — unchanged: the ODBC / native
  Adaptagrams / Tulip examples on top of the umbrella.

Each package follows the established model: a single module file with
topologically ordered includes, `document/` + `projection/` folders, factories
exported. The runtime seam pattern (`make_backend`, `record_video`,
`stream_turn`) is what keeps the lower example packages free of Sdl / Video /
Llm dependencies — a moved harness function may *call* a seam, never `using`
an opt-in package.

### Assigned UUIDs

```
ProjecturedKernelExample = "b2967ee9-386e-4698-a92b-2bf5f698f2fd"
ProjecturedBaseExample   = "73f3e5d2-8cbb-4e35-981e-a93c86a0a9bd"
ProjecturedVisualExample = "5049da3f-9201-47d6-95d8-24bb99c7096c"
ProjecturedDomainExample = "5393e5bd-6135-44b9-9645-408b92f5eb98"
```

Directories: `package/kernel-example/`, `package/base-example/`,
`package/visual-example/`, `package/domain-example/` (siblings of the
existing umbrella `package/example/`). Each is added to the **root
`Project.toml`** `[deps]` **and** `[sources]` (and the root Manifest), so
`using ProjecturedKernelExample` resolves from the root env.

## What this replaces (already on disk)

The test-package split left **mirrored fixture copies** in the test packages
precisely so this split becomes a no-op swap
(plan/done/test-package-split.md, "Future phase"):

- `package/visual-test/src/Fixtures.jl` — `make_widget_projection_example`,
  `make_widget_popup_projection_example`, `make_layout_projection_example`,
  `make_nested_object_to_widget_document_example` (+ its `AppSettings` /
  `WindowSettings` fixture types).
- `package/domain-test/src/Fixtures.jl` — `make_json_document_example`,
  `make_graphics_image_projection_example`,
  `make_json_console_projection_example`, the table/math-table factories,
  `make_graph_document_example`, `JsonXmlToSyntax`,
  `make_mixed_projection_example`, `make_graph_projection_example`.

Both files are **deleted**; each test package instead depends on its example
package and uses the real factories. The copies were byte-for-byte mirrors,
so behavior is unchanged by construction — diff them against the example
sources before deleting to catch any drift since the test split.

## Design principles

1. **Lowest-home rule** (same as the test split, and it overrides the
   classification table below — entries marked (confirm) get a vocabulary
   check at move time). An example goes to the example package of the lowest
   runtime package whose API its document *and* projection factories
   hard-reference. Seam calls don't count as references.
2. **Harness to its layer.** `Example` (pure data) → kernel-example. Gallery
   composition (screen/window/widget vocabulary) → visual-example. Per-domain
   file editing → domain-example. Cross-tier registry / discovery / LLM /
   video → umbrella.
3. **One `Example` type.** The struct is defined once, in
   `ProjecturedKernelExample`; every package above imports it. No duplicate
   definitions (type identity matters — the test drivers dispatch on it).
4. **Registry stays global, tiers get slices.** Each example package exports
   its own `<layer>_examples::Vector{Example}` list; the umbrella's `examples`
   is the concatenation (order-preserved, since sweep output ordering is part
   of the developer experience). Test sweeps can then run per tier.

## Classification of the example files

*(one line per `document/` + `projection/` pair; (confirm) = check vocabulary
at move time)*

**→ ProjecturedKernelExample** — harness core (`Example` struct out of
`Examples.jl`, `print_example` (confirm)); `Focusing` (FocusingProjection is a
kernel generic); `RotatingVector` (confirm).

**→ ProjecturedBaseExample** — `Collection` (ListNode/CellVector documents),
`Lazy` (lazy/lazy_bidirectional), the generic collection projections
`Reversing`/`Filtering`/`Searching`/`Sorting` (base doc-shaped projections;
their *_example wrappers pair them with the collection document).

**→ ProjecturedVisualExample** — documents: `Text` (text/plain_text/
text_with_image), `Syntax`, `Widget` (the ~40 widget_* examples), `Layout`
(layout + constraint_layout — the default `FallbackConstraintSolver` is
dependency-free; Tulip is only reached when the caller passes a
`TulipConstraintSolver`), `ObjectToWidget` (object_to_widget,
nested_object_to_widget + the `SearchSettings`/`WindowSettings`/`AppSettings`
fixture types), `LineNumbering`, `WordWrapping`, `TextFiltering`,
`TextHighlighting`, `TextToString` (confirm), `Primitive` (primitive_string —
drives the visual PrimitiveStringToSyntaxLeaf), `Dragging` (confirm);
harness: `run_example(::Example)` / `run_example(::Vector{Example})` gallery
composition, `run_web_example` (confirm — web backend via seam),
`write_example_image`, `write_example_pdf`.

**→ ProjecturedDomainExample** — `Json` (json/json_sorted/json_null/
json_insertion/json_string), `Yaml`, `Xml`, `Mixed`, `Natural`, `Sql` (the four
sql_*_syntax examples), `Formula`, `Math`, `Julia`, `Markdown`
(markdown/markdown_rendered), `Book`, `FileSystem` (filesystem/
filesystem_widget), `Navigator`, `Graph`, `Table` (table/math_table — WidgetTable
cells are JSON/Math documents), `Object` + `Wrapper` (ObjectToSyntax is a
domain projection), `Clipboard`, `Versioning`, `Graphics`
(graphics_image — the json→graphics pipeline), `Conversation` (confirm —
conversation/conversation_widget/conversation_editor; if the *documents* only
need the domain conversation/workbench modules they belong here, with only
the LLM-driven assistant staying above), `Workbench`, `DatabaseInstance` (the
config document is domain vocabulary; live connections stay in extras);
harness: `FileEditor.jl` (`EditorDomain` + domain table + `run_file_editor`).

**stays in ProjecturedExample (umbrella)** — `Assistant` (registers the LLM
seam via `using ProjecturedLlm`); the global `examples` registry (rebuilt as
the concatenation of the tier lists); `run_example(name::String)` /
`run_example(names::Vector{String})` (registry lookups); `Catalog.jl`
(cross-domain discovery; also uses the graphics bridge); `LiveExamples.jl`
(record_video / play_live!); `record_example_video`, `typing_gestures`
(confirm — video-coupled); `demo/CellKindSimDemo.jl`; the `Profile` dep
(run_example's `profile=true` — confirm: if only the gallery uses it, Profile
moves to visual-example with it).

## Test-package payoff (wired in the same phases)

- `ProjecturedKernelTest` gains a dep on `ProjecturedKernelExample` and takes
  back the `Example`-typed driver overloads (`test_printer(::Example)`,
  `test_reader(::Example)`, `test_repl(::Example)`,
  `test_text_navigation(::Example; …)`, `test_tree_navigation(::Example; …)`)
  from the umbrella's ExampleSweeps.jl — they only need the struct.
- Each test package deps its example package; `visual-test` and `domain-test`
  delete their `Fixtures.jl` and use the real factories; per-tier sweeps
  (`for ex in visual_examples … test_printer(ex)`) become possible inside
  `test_visual()` / `test_domain()`.
- The umbrella `ProjecturedTest` keeps the whole-registry sweeps
  (`test_printers()`, `test_readers()`, …) and everything Example-coupled that
  also needs Sdl/Odbc/Tulip/Video.
- The `Example`-typed default-enumerator overload
  (`_default_tree_collector(::JsonDocument)`) moves next to
  `collect_json_tree_selections` in domain-test.

## Phases

Discipline every phase (same as the test split): move file → narrow its
`using` to the target package's API (the flat-namespace loop over the tier's
runtime packages, as ProjecturedVisualTest does) → register in the package's
module + tier list → **delete the old copy** → run the affected per-tier test
suite from its own env (`julia --project=package/<tier>-test`) **and** parse-
check the umbrella → commit. (Memory: precompile-green ≠ loads — verify with
an actual `using`; the umbrella `ProjecturedExample` still loads offline-free
of Sdl but needs ProjecturedLlm's HTTP deps, so full umbrella verification
needs a networked env — same caveat as ProjecturedTest.)

- [x] **Phase 0 — `ProjecturedKernelExample`.** Create `package/kernel-example/`
  (UUID above, dep `ProjecturedKernel`). Move the `Example` struct out of
  `Examples.jl`; move `Focusing` (+ `RotatingVector`, `print_example` after
  confirm). Export `kernel_examples`. Wire root env. Umbrella
  `ProjecturedExample` deps + re-exports it; `ProjecturedKernelTest` deps it
  and takes the `Example`-typed driver overloads from the umbrella test's
  ExampleSweeps.jl (which shrinks to the sweeps). Verify `test_kernel()` and
  the example packages' own loads.
- [x] **Phase 1 (skipped) — `ProjecturedBaseExample`.** Collection/Lazy +
  reversing/filtering/searching/sorting examples; `base_examples`;
  base-test deps it (sweep over `base_examples` inside `test_base()`).
- [x] **Phase 2 — `ProjecturedVisualExample`** (largest). Text/Syntax/Widget/
  Layout/ObjectToWidget/text-decorator examples + the gallery harness
  (`run_example` composition, `write_example_image`, `write_example_pdf`);
  `visual_examples`; visual-test deps it, **deletes Fixtures.jl**, sweeps its
  tier. Confirm no Sdl/Tulip `using` sneaks in (seams only).
- [x] **Phase 3 — `ProjecturedDomainExample`.** All domain examples +
  `FileEditor.jl`; `domain_examples`; domain-test deps it, **deletes
  Fixtures.jl**, sweeps its tier — `test_printer(json_example)` now runs in
  domain-test against the real example, closing the loop the test split
  promised.
- [x] **Phase 4 — umbrella shrink & docs.** `ProjecturedExample` keeps
  Assistant + registry + Catalog + LiveExamples + demo, re-exports the tiers;
  `examples` = concatenation of tier lists (preserve current order). Update
  `documentation/debugging.md` (run_example/print_example homes),
  `documentation/testing.md` (per-tier sweeps), `CLAUDE.md`, and
  `documentation/architecture.md`'s package inventory. Move this plan to
  `plan/done/`.

## Risks

- **`Example` type identity:** exactly one definition (kernel-example);
  every re-export must alias, never redefine — the test drivers and the
  executable dispatch on it.
- **Registry order:** the umbrella `examples` vector's order is visible in
  sweep output and the `run_example` gallery; keep the concatenation in the
  current authored order, not per-tier convenience order.
- **Seam discipline:** the gallery/image/pdf/video harness pieces must keep
  reaching Sdl/Video through `make_backend`/`record_video` seams; adding a
  hard dep would drag SDL into the visual tier and break the offline
  per-tier envs the test split just created.
- **Hidden cross-tier references:** some widget examples embed JSON documents
  (e.g. table cells) — anything that does belongs in domain-example no matter
  what its name says; the (confirm) markers exist for exactly this.
- **Umbrella export compatibility:** `using ProjecturedExample` must keep
  providing every name it does today (examples, factories, harness); the
  mechanical re-export loop plus explicit harness re-exports cover it —
  verify with a names() diff before/after.
- **Executable/extras coupling:** `package/executable` and
  `package/extras-example` consume the umbrella; they should keep working
  unchanged, but their `using`s are the first thing to smoke-test after
  Phase 4.

## Out of scope

Converging `run_example` and `run_file_editor`; splitting
`ProjecturedExtrasExample`; adding examples for packages that have none
(llm/mcp/web); changing the `Example` struct itself (e.g. lazy
materialization) — the split moves code, it does not redesign it.
