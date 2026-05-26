# Getting Started

ProjecturEd is a generic-purpose projectional editor reimplemented in Julia.
Documents are structured data (trees, ASTs, graphs); they are presented to
the user through *bidirectional projections*. The editor reads input events,
projects them backwards through the pipeline into a domain operation,
applies the operation to the document, then re-projects forward and renders.

This guide explains the layout of the codebase and where to look for each
concept. The deeper material is split across topic-specific guides.

## Prerequisites

- Julia 1.10+
- SDL2 and SDL_ttf installed (for the SDL backend)
- Familiarity with Julia (modules, multiple dispatch, structs)

## Core concepts

| Concept | Description | Where defined |
|---|---|---|
| **Domain** | A set of Document/Operation types for some problem area (JSON, XML, text, widget, …) | `program/src/document/*.jl` |
| **Document** | A reactive data structure being edited; subtypes `Document` and carries a `selection::Reference` | `program/src/api/Document.jl` + per-domain files |
| **Reference** | A path into a Document, used for selection and navigation | `program/src/reference/Reference.jl` |
| **Operation** | A user gesture expressed in a Document's own terms | `program/src/api/Operation.jl` |
| **Projection** | A bidirectional transformation between two domains | `program/src/api/Projection.jl` |
| **IoMap** | The result of `projection_print`; carries enough data to invert the transformation | `program/src/api/IoMap.jl` |
| **Cell** | The reactive primitive — every reactive value in the system is a `Cell` | `program/src/common/Reactive.jl` |
| **Backend** | Platform-specific I/O (SDL today; terminal/web in future) | `program/src/api/Backend.jl` |
| **Editor** | The read-eval-print loop that ties it all together | `program/src/editor/Editor.jl` |

**Indexing**: ProjecturEd is fully 1-based, consistent with Julia.

## Recommended reading order

1. **[reactive-cells.md](reactive-cells.md)** — the foundation. Everything else assumes you understand `Cell`, dependency tracking, and lazy invalidation.
2. **[macros.md](macros.md)** — `@document`, `@projection`, `@iomap`. Explains why the rest of the code can read Julia struct fields directly even though every field is wrapped in a `Cell`.
3. **[projection-system.md](projection-system.md)** — the heart of the architecture. The four interface functions (`projection_print`, `projection_read`, `map_reference_forward`, `map_reference_backward`) and how they compose.
4. **[editor/reference.md](editor/reference.md)** — reference paths, the `@reference` DSL, and the `@reference_case` pattern matcher.
5. **[editor/selection.md](editor/selection.md)** — how selection is stored and propagated through nested documents.
6. **[editor.md](editor.md)** — the editor loop, devices, backend wiring, and MCP server.

For the projection ecosystem:

- **[higher-order-projections.md](higher-order-projections.md)** — `Sequential`, `Recursive`, the four dispatchers, `Nesting`, `Alternative`, plus the `ApplyAtProjection` combinator.
- **[generic-projections.md](generic-projections.md)** — `Preserving`, `Invariably`, `Copying`, `Sorting`, `Reversing`, `Focusing`.
- **[operations.md](operations.md)** — what an operation is, when to add one, and how the reader chain produces them.
- **[devices-and-backends.md](devices-and-backends.md)** — the `Backend`/`Device` split and how to add a new one.

For specific domains:

- **JSON** → [document/json.md](document/json.md)
- **XML** → [document/xml.md](document/xml.md)
- **Text** → [document/text.md](document/text.md)
- **Syntax** → [document/syntax.md](document/syntax.md)
- **Graphics** → [document/graphics.md](document/graphics.md)
- **Widget** → [document/widget.md](document/widget.md)
- **Workbench** (IDE shell) → [document/workbench.md](document/workbench.md)
- **Collection** (`CellVector`, `ListNode`) → [document/collection.md](document/collection.md)

Plus deeper background:

- **[design.md](design.md)** — the architecture overview, design decisions, and mapping from the original Common Lisp ProjecturEd to this Julia port.

## A minimal example

```julia
using Projectured

doc = JsonObject(
    "name" => JsonString("Alice"),
    "age"  => JsonNumber(30),
)

backend = SdlBackend()
proj    = SequentialProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = (t, f) -> sdl_measure_text(backend, t, f)),
)

application(backend, proj, doc; title = "JSON", width = 1200, height = 800)
```

The editor opens an SDL window, renders the JSON document, and routes
keyboard/mouse events back through the projection pipeline.

## Debugging with `print_object`

`print_object` runs `ObjectToSyntax → SyntaxToText → TextToString` on any
Julia value and returns the resulting string. Useful for inspecting
document structures without firing up the editor:

```julia
print_object(editor.document)
print_object(my_struct; open_delimiter = "{", close_delimiter = "}")
print_object(doc; include_selection = false)
```

## Inspecting references

The `@reference` macro builds reference paths from a path-like DSL:

```julia
ref = @reference entries[1].value.value{3}
evaluate_reference(editor.document, ref)
```

See [editor/reference.md](editor/reference.md) for the full grammar
(`.field`, `[i]`, `{k}`, `[i, j]`, `.field(expr)`, `.point(x, y)`,
`.proj(p, sub)`).

## For AI assistants using MCP

When `run!` is active the editor exposes an MCP server on port 9876.
Recommended workflow:

1. Read `resource://guides` to discover the documentation layout.
2. Read `resource://guide/getting-started`, then the topic guides
   relevant to the task — usually `reactive-cells`, `projection-system`,
   `editor/reference`, and the affected domain's guide.
3. Use `print_object(editor.document)` to see the live structure.
4. Build reference paths with `@reference` and apply changes with
   `replace_selection!`, `set_selection!`, or domain operations.

Do not guess names or signatures. Look them up via `resource://modules`,
`resource://classes`, and `resource://functions`.
