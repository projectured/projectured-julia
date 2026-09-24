# Orientation — read first, then search

> **Kind:** reference · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md), [system-anatomy.md](../design/system-anatomy.md)

ProjecturEd is a **projectional editor**: a structured `document` is shown through
composable, bidirectional `projection`s, and you edit by acting on
`editor.document`. This page is an **index of the vocabulary** — not an
explanation. Use it to pick the right *search terms*, then dig in with the
browsing tools below. Do not guess names — search for them.

## Concepts → names to search

| Concept | Names to search | Guide |
|---|---|---|
| Document & domains | `@document`; `JsonObject`/`JsonString`/`JsonNumber`, `XmlElement`, `TextBlock`/`TextString`, `SyntaxNode`/`SyntaxLeaf`, `GraphicsCanvas`, `WidgetButton`, `JuliaCall` | `design/concepts`, `kernel/architecture`, `kernel/document` |
| Reactive cell | `Cell`, `set_cell_computation!`, `getfield` (escape hatch), `get_performance_counters` | `kernel/cell` |
| Macros | `@document`, `@projection`, `@projection_template`, `@iomap` | `kernel/macros` |
| Projection (interface) | `Projection`, `print_document`, `read_intent`, `map_reference_forward`, `map_reference_backward`, `PrinterContext`, `IoMap`/`SimpleIoMap`/`ChildrenIoMap` | `kernel/projection-system` |
| Projection composition | `ChainingProjection`, `RecursiveProjection`, `TypeDispatchingProjection`, `NestingProjection`, `SwitchingProjection`; generic: `CopyingProjection`, `SortingProjection`, `FilteringProjection`, `FocusingProjection` | `projection/higher-order-projections`, `projection/generic-projections` |
| Reference | `Reference`, `EmptyReference`, `ConcreteReference`; steps `FieldReferenceStep`, `RangeReferenceStep` (`ElementReferenceStep`/`PositionReferenceStep`), `ProjectionReferenceStep`, `TypeReferenceStep`; DSL `@reference`, `@reference_case`, `@reference_rules`; `evaluate_reference` | `kernel/reference` |
| Selection | `set_selection!`, `clear_selection!`, `replace_selection!`, `get_selection` | `kernel/selection` |
| Search (by content) | `search_references`, `search_documents`, `print_object` (search a document **or an iomap** — the whole pipeline) | `kernel/finding-and-selecting`, `guide/debugging-guide` |
| Operation | `Operation`, `evaluate_operation`, `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation` (+ `replace_document` / `insert_elements` / `delete_elements`), `ReplaceStringRangeOperation`, `CompoundOperation` | `kernel/operation` |
| Editor & loop | `Editor`, `run_editor!`, `run_frame!`, `read!`/`evaluate!`/`print!`, `McpServer`, `execute_julia_code` | `kernel/editor` |
| Screen / pane tree | `ScreenDocument` → `WindowDocument` → `PaneTree` → `PaneSplit`/`PaneGroup` → `PaneTab`; `ScreenToScreen`, `WindowManagingProjection` | `pane/pane`, `kernel/editor` |
| Backends / devices | `Backend`/`SdlBackend`, `Device`/`Display`/`Keyboard`/`Mouse`, `KeyPress`, `MousePress` | `kernel/devices-and-backends` |

## How to browse

- `search_api("name")` — find the name to call: a module, a type, or a function.
- `search_guides("topic")` — learn how the parts fit together: a guide section,
  with the `resource://guide/<name>#<heading>` URI that reads it.
- Both take `mode`: `"keywords"` by default (`+word` must match, `-word` must
  not, `a|b` is either, `"a phrase"`), `"regex"`, or `"description"` for a
  sentence that says what you want to do; and `detail`: `"names"`, `"summary"`
  or `"full"`.
- `read_guide("kernel/reference")` / `read_resource(uri)` — read full text on demand.
- `resource://guides`, `resource://modules` — the full catalogues.

## Acting on the document (the essentials)

- **Find** — `search_references(editor.document, query)` → paths;
  `search_documents(...)` → matching document nodes. `query` is a predicate `node -> Bool`, or a
  `String`/`Regex` matching leaf text (string/regex matches fold to the enclosing `Document` by
  default; pass `raw=true` for the exact matched value). Both walk **any** graph, so passing an
  **iomap** (`print_document(proj, doc)`) searches the whole projection
  pipeline — a debugging move for "where did the value go?" (see `guide/debugging-guide`).
- **Resolve** — `evaluate_reference(editor.document, path)` → the node at a path.
- **Intent** — build an `Operation`, then `evaluate_operation(editor, op)`
  (e.g. `ReplaceSelectionOperation(path)` to select). This is the *one* way to
  change the document; operations carry their own target, so they work through any
  `ScreenDocument`/`WindowDocument` wrapping.

### Gotchas

- Property access already unwraps `Cell`s — write `node.field`, **not** `node.field[]`.
- A pane tree can mirror the **same** document into two tabs at once, so a bare
  value match hits both — scope by **domain node type** (`v isa JsonString`).
- `execute_julia_code` keeps top-level bindings between calls, so build state up
  incrementally (`paths = …` in one call, use `paths` in the next).
