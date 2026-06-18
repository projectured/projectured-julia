# Orientation — read first, then search

ProjecturEd is a **projectional editor**: a structured `document` is shown through
composable, bidirectional `projection`s, and you edit by acting on
`editor.document`. This page is an **index of the vocabulary** — not an
explanation. Use it to pick the right *search terms*, then dig in with the
browsing tools below. Do not guess names — search for them.

## Concepts → names to search

| Concept | Names to search | Guide |
|---|---|---|
| Document & domains | `@document`; `JsonObject`/`JsonString`/`JsonNumber`, `XmlElement`, `TextText`/`TextString`, `SyntaxNode`/`SyntaxLeaf`, `GraphicsCanvas`, `WidgetButton`, `JuliaCall`, `TableTable` | `concepts`, `architecture`, `document/*` |
| Reactive cell | `Cell`, `setfn!`, `getfield` (escape hatch), `perf_counters` | `reactive-cells` |
| Macros | `@document`, `@projection`, `@iomap` | `macros` |
| Projection (interface) | `Projection`, `projection_print`, `projection_read`, `map_reference_forward`, `map_reference_backward`, `PrinterContext`, `IoMap`/`SimpleIoMap`/`ChildrenIoMap` | `projection-system` |
| Projection composition | `SequentialProjection`, `RecursiveProjection`, `TypeDispatchingProjection`, `NestingProjection`, `AlternativeProjection`; generic: `CopyingProjection`, `SortingProjection`, `FilteringProjection`, `FocusingProjection` | `higher-order-projections`, `generic-projections` |
| Reference | `ReferencePath`, `EmptyReferencePath`, `ConcreteReferencePath`; steps `FieldReference`, `RangeReference` (`ElementReference`/`PositionReference`), `ProjectionReference`, `TypeReference`; DSL `@reference`, `@reference_case`; `evaluate_reference` | `editor/reference` |
| Selection | `set_selection!`, `clear_selection!`, `replace_selection!` | `editor/selection`, `selection-deep-dive` |
| Search (by content) | `search_references`, `search_objects`, `print_object` | `editor/finding-and-selecting` |
| Operation | `Operation`, `evaluate_operation`, `ReplaceSelectionOperation`, `StringReplaceRangeOperation`, `CollectionInsertOperation`/`CollectionDeleteOperation`, `WorkbenchOpenDocumentOperation` | `operations` |
| Editor & loop | `Editor`, `run!`, `read!`/`evaluate!`/`print!`, `McpServer`, `execute_julia_code` | `editor` |
| Screen / workbench | `ScreenDocument` → `WindowDocument` → `WorkbenchWorkbench` → `WorkbenchPage` → `WorkbenchEditor`; `ScreenToScreen`, `WindowManagerProjection` | `document/workbench`, `editor` |
| Backends / devices | `Backend`/`SdlBackend`, `Device`/`Screen`/`Keyboard`/`Mouse`, `KeyPress`, `MousePress` | `devices-and-backends` |

## How to browse

- `search_api("name")` — find a module, struct, or function by name/topic.
- `search_documentation("topic")` — find the relevant guide section.
- `read_guide("editor/reference")` / `read_resource(uri)` — read full text on demand.
- `resource://guides`, `resource://modules` — the full catalogues.

## Acting on the document (the essentials)

- **Find** — `search_references(editor.document, query)` → paths;
  `search_objects(...)` → nodes. `query` is a predicate `node -> Bool`, or a
  `String`/`Regex` matching leaf text.
- **Resolve** — `evaluate_reference(editor.document, path)` → the node at a path.
- **Change** — build an `Operation`, then `evaluate_operation(editor, op)`
  (e.g. `ReplaceSelectionOperation(path)` to select). This is the *one* way to
  change the document; operations carry their own target, so they work through any
  `ScreenDocument`/`WindowDocument` wrapping.

### Gotchas

- Property access already unwraps `Cell`s — write `node.field`, **not** `node.field[]`.
- The workbench shows the **same** document through several projections, so a bare
  value match hits all of them — scope by **domain node type** (`v isa JsonString`).
- `execute_julia_code` keeps top-level bindings between calls, so build state up
  incrementally (`paths = …` in one call, use `paths` in the next).
