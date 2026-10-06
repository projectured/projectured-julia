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
| Referenced document | `ReferencedDocument`, `get_document`, `get_reference`, `find_pane`, `get_edited_document`, `get_parent`, `DocumentLocator`, `find_referenced_document` | `kernel/reference`, `guide/orientation` |
| Selection | `set_selection!`, `clear_selection!`, `replace_selection!`, `get_selection` | `kernel/selection` |
| Search (by content) | `search_references`, `search_documents`, `print_object` (search a document **or an iomap** — the whole pipeline) | `kernel/finding-and-selecting`, `guide/debugging-guide` |
| Operation | `Operation`, `evaluate_operation`, `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation` (+ `make_replace_document_operation` / `make_insert_elements_operation` / `make_delete_elements_operation`), `ReplaceStringRangeOperation`, `CompoundOperation` | `kernel/operation` |
| Editor & loop | `Editor`, `run_editor!`, `run_frame!`, `run_read_stage!`/`run_evaluate_stage!`/`run_print_stage!`, `McpServer`, `execute_julia_code!` | `kernel/editor` |
| Screen / pane tree | `ScreenDocument` → `WindowDocument` → `PaneTree` → `PaneSplit`/`PaneGroup` → `PaneTab`; `ScreenToScreen`, `WindowManagingProjection` | `pane/pane`, `kernel/editor` |
| Backends / devices | `Backend`/`SdlBackend`, `Device`/`Display`/`Keyboard`/`Mouse`, `KeyPress`, `MouseClick` | `kernel/devices-and-backends` |

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
- **Editor** — a verb acts on the editor that runs the code, so the code does not
  pass `editor` to a verb. `editor` is still bound, and `editor.document` is the
  root that a path starts at.
- **Intent** — build an `Operation`, then `evaluate_operation(editor, op)`
  (e.g. `ReplaceSelectionOperation(path)` to select), or call a verb that makes
  one, such as `replace_referenced_value!`, `insert_elements!` or
  `delete_elements!`. This is how to change the document;
  operations carry their own target, so they work through any
  `ScreenDocument`/`WindowDocument` wrapping. A direct write to a document, such as
  `part.value = new_value`, works, but the editor does not handle it as an edit:
  Ctrl+Z can not undo it, and the editor does not check its permissions or
  transform it, as it does for an operation.

## Reach what a tab holds

`find_pane(title)` answers the tab of that title as a
`ReferencedDocument`: the tab, and the reference to it from the root of
`editor.document`. A referenced document acts like its document: read a field,
index it, iterate it. Every document or collection that a read answers is a
referenced document too, with the reference to its place; a string, a number or a
`Bool` comes back plain. `get_edited_document(tab)` answers the data that the tab
shows, through the file and the history that hold it. The pane verbs and
`print_natural_text` take a referenced document where they take a reference or a
document.

Look at the data first, in one call. Here a tab shows `items.json`, a JSON array
of records with a `name` and a `price`:

```julia
items_tab_1 = find_pane("items.json")
items_1 = get_edited_document(items_tab_1)
println(print_natural_text(items_1))
```

Then use the same variables in the next call. A `JsonArray` acts as a vector, and
a `JsonObject` as a map from key to value; `.value` is the plain value of a leaf.
Build the rows of a table and sort them in one call, with a comprehension in its
brackets, `[… for item in items_1]`: `sort` takes a vector, not a generator.

```julia
rows_1 = sort([[item["name"].value, item["price"].value] for item in items_1]; by = first)
table_tab_1 = open_pane!(WidgetTable(["name", "price"], rows_1); title = "Items by name")
```

To change what a tab shows, give the part and its new value to
`replace_referenced_value!`, so the change is an edit that Ctrl+Z can undo:

```julia
replace_referenced_value!(items_1[2]["price"], JsonNumber(12))
```

and not `items_1[2]["price"].value = 12`, which changes the document outside the
editor's handling of an edit. To add a record, or to remove one, use
`insert_elements!` and `delete_elements!`, which take the collection and a
1-based index:

```julia
item_1 = JsonObject("name" => JsonString("lamp"), "price" => JsonNumber(25))
insert_elements!(items_1, length(items_1) + 1, [item_1])
```

Each of the three records the edit in the history of the file, so Ctrl+Z in the
tab of the file takes it back.

`open_pane!` puts the new tab where the focus is. To put it before a tab, or at
the end of a group, give that tab or group as `target`. To put it in a new pane
beside or under the group of the target, add `side`: `:left`, `:right`, `:above`
or `:below`. The new pane is always next to one group.
`get_parent(editor, items_tab_1)` answers the group that holds the tab, so this
puts the table in a new pane under the group of `items.json`:

```julia
table_tab_2 = open_pane!(WidgetTable(["name", "price"], rows_1); title = "Items",
                         target = get_parent(editor, items_tab_1), side = :below)
```

Each call runs in the same module, so a variable that one call binds at the top
level is still there in every later call. Keep each object that you find or make
in its own variable, named by what it holds and numbered: `items_tab_1`,
`items_1`, `rows_1`. When you make another object of the same kind, give it the
next number, `rows_2`, and do not overwrite the first. Use a variable again in a
later call instead of finding its object again.

### Gotchas

- Property access already unwraps `Cell`s — write `node.field`, **not** `node.field[]`.
- A pane tree can mirror the **same** document into two tabs at once, so a bare
  value match hits both — scope by **domain node type** (`v isa JsonString`).
- `execute_julia_code` keeps top-level bindings between calls, so build state up
  in numbered variables (`items_1 = …` in one call, use `items_1` in the next).
- A referenced document is not an instance of its document's type:
  `items_1 isa JsonArray` is false. Ask `get_document(items_1) isa JsonArray`.
