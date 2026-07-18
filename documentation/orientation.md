# Orientation — read first, then search

ProjecturEd is a **projectional editor**: a structured `document` is shown through
composable, bidirectional `projection`s, and you edit by acting on
`editor.document`. This page is an **index of the vocabulary** — not an
explanation. Use it to pick the right *search terms*, then dig in with the
browsing tools below. Do not guess names — search for them.

## Concepts → names to search

| Concept | Names to search | Guide |
|---|---|---|
| Document & domains | `@document`; `JsonObject`/`JsonString`/`JsonNumber`, `XmlElement`, `TextBlock`/`TextString`, `SyntaxNode`/`SyntaxLeaf`, `GraphicsCanvas`, `WidgetButton`, `JuliaCall`, `TableTable` | `concepts`, `architecture`, `document/*` |
| Reactive cell | `Cell`, `set_cell_function!`, `getfield` (escape hatch), `get_performance_counters` | `reactive-cells` |
| Macros | `@document`, `@projection`, `@iomap` | `macros` |
| Projection (interface) | `Projection`, `print_document`, `read_intent`, `map_reference_forward`, `map_reference_backward`, `PrinterContext`, `IoMap`/`SimpleIoMap`/`ChildrenIoMap` | `projection-system` |
| Projection composition | `ChainingProjection`, `RecursiveProjection`, `TypeDispatchingProjection`, `NestingProjection`, `SwitchingProjection`; generic: `CopyingProjection`, `SortingProjection`, `FilteringProjection`, `FocusingProjection` | `higher-order-projections`, `generic-projections` |
| Reference | `Reference`, `EmptyReference`, `ConcreteReference`; steps `FieldReferenceStep`, `RangeReferenceStep` (`ElementReferenceStep`/`PositionReferenceStep`), `ProjectionReferenceStep`, `TypeReferenceStep`; DSL `@reference`, `@reference_case`; `evaluate_reference` | `editor/reference` |
| Selection | `set_selection!`, `clear_selection!`, `replace_selection!` | `editor/selection`, `selection-deep-dive` |
| Search (by content) | `search_references`, `search_documents`, `print_object` (search a document **or an iomap** — the whole pipeline) | `editor/finding-and-selecting`, `debugging` |
| Operation | `Operation`, `evaluate_operation`, `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation` (+ `replace_document` / `insert_elements` / `delete_elements`), `ReplaceStringRangeOperation`, `CompoundOperation` | `operations` |
| Editor & loop | `Editor`, `run_editor!`, `read!`/`evaluate!`/`print!`, `McpServer`, `execute_julia_code` | `editor` |
| Screen / workbench | `ScreenDocument` → `WindowDocument` → `WorkbenchWorkbench` → `WorkbenchPage` → `WorkbenchEditor`; `ScreenToScreen`, `WindowManagingProjection` | `document/workbench`, `editor` |
| Backends / devices | `Backend`/`SdlBackend`, `Device`/`Display`/`Keyboard`/`Mouse`, `KeyPress`, `MousePress` | `devices-and-backends` |

## How to browse

- `search_api("name")` — find a module, struct, or function by name/topic.
- `search_documentation("topic")` — find the relevant guide section.
- `read_guide("editor/reference")` / `read_resource(uri)` — read full text on demand.
- `resource://guides`, `resource://modules` — the full catalogues.

## Acting on the document (the essentials)

- **Find** — `search_references(editor.document, query)` → paths;
  `search_documents(...)` → matching document nodes. `query` is a predicate `node -> Bool`, or a
  `String`/`Regex` matching leaf text (string/regex matches fold to the enclosing `Document` by
  default; pass `raw=true` for the exact matched value). Both walk **any** graph, so passing an
  **iomap** (`print_document(proj, doc)`) searches the whole projection
  pipeline — a debugging move for "where did the value go?" (see `debugging`).
- **Resolve** — `evaluate_reference(editor.document, path)` → the node at a path.
- **Intent** — build an `Operation`, then `evaluate_operation(editor, op)`
  (e.g. `ReplaceSelectionOperation(path)` to select). This is the *one* way to
  change the document; operations carry their own target, so they work through any
  `ScreenDocument`/`WindowDocument` wrapping.

### Gotchas

- Property access already unwraps `Cell`s — write `node.field`, **not** `node.field[]`.
- The workbench shows the **same** document through several projections, so a bare
  value match hits all of them — scope by **domain node type** (`v isa JsonString`).
- `execute_julia_code` keeps top-level bindings between calls, so build state up
  incrementally (`paths = …` in one call, use `paths` in the next).
