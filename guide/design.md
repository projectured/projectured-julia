# ProjecturEd — A Julia Reimplementation

This document describes the architecture, design decisions, and current implementation status of ProjecturEd (Julia), a reimplementation of the original Lisp-based ProjecturEd. It covers the core concepts of projectional editing, the reactive cell system that enables incrementality, the domain/projection/editor layering, and the mapping from the original Lisp implementation to idiomatic Julia code. The document also includes a module inventory, projection pipeline status, roadmap, and detailed explanation of the reference and selection mechanism.

## 1. What is ProjecturEd?

[ProjecturEd](https://github.com/projectured/projectured) is a **generic-purpose projectional editor**. Unlike traditional text editors that operate on flat character sequences, a projectional editor:

- Stores documents as **structured data** (trees, graphs, typed ASTs, etc.).
- Presents them to the user through **bidirectional, composable projections** that transform one domain into another.
- Lets the user edit the *presentation* while the editor maps changes back to the underlying structure via the reverse projection (the *reader*).

The key insight is that a text editor is just a degenerate case: a projectional editor specialised for the string domain with a single projection. By generalising over domains and projections, the same framework can edit JSON, XML, Java, styled documents, graphics, and anything else — all with the flexibility users expect from a text editor.

### Core Concepts (from the original wiki)

| Concept | Definition |
|---|---|
| **Domain** | A set of data structures for *documents*, *selections*, and *operations* that belong to a problem area (e.g. JSON, text, graphics). Domains are independent of each other and of projections. |
| **Document** | A piece of data being edited — an instance of a domain's document data structures. Documents may be compound, cyclic, or mix domains. |
| **Selection** | A path-like reference into a document (e.g. "character 5 of line 3", "the `name` key of the second object"). |
| **Operation** | A domain-specific mutation described in terms of selections and values (e.g. "delete character at selection", "insert child at index"). |
| **Projection** | A bidirectional transformation between two domains. Has two sides: the **printer** (forward, toward display) and the **reader** (backward, toward the document). Both are purely functional. |
| **IO Map** | A data structure returned alongside a projection's output that records the bidirectional correspondence between input and output elements, enabling the reader to invert the printer. |
| **Backend** | The IO boundary — renders graphics/text to a display and reads keyboard/mouse events. The original supports SDL, Web, and SLIME backends. |
| **Editor** | A generalised Read-Eval-Print Loop: *read* events from input devices → *project* (read) them into an operation on the document → *apply* the operation → *project* (print) the document to the output devices. |

### Projection Taxonomy

- **Domain-to-domain** — e.g. JSON → Tree, Tree → String, Styled String → Graphics.
- **Domain-preserving** — e.g. word wrapping, line numbering (input and output are in the same domain).
- **Domain-independent** — e.g. copy, sort, filter/focus, remove (work on any domain).
- **Higher-order** — combine other projections: sequential (pipeline), recursive, nested, type-dispatch, predicate-dispatch.

### Performance Strategy

The original ProjecturEd achieves interactive speed through three techniques:

1. **Parallelism** — printer and reader are purely functional, so they parallelise trivially.
2. **Laziness** — only compute the parts of the output that are actually visible on screen.
3. **Incrementality** — reuse previous results via constraint-based change propagation; recompute only the parts whose inputs changed.

---

## 2. Goals of This Julia Reimplementation

1. **Faithful architecture** — preserve the domain/projection/editor layering of ProjecturEd.
2. **Reactive incrementality** — replace the computed-class library with a lightweight pull-based reactive cell system built in Julia.
3. **Idiomatic Julia** — use multiple dispatch, parametric types, and Julia's module system instead of CLOS.
4. **SDL2 backend first** — render to a native window using SDL2 + SDL_ttf, matching the original's primary backend.
5. **Incremental scope** — start with a small but complete vertical slice (JSON editing) and expand domain by domain.

---

## 3. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                       Editor (REPL)                      │
│  read events → project(reader) → apply op → project(printer) → render  │
└────────────┬──────────────────────────────────┬──────────┘
             │                                  │
     ┌───────▼───────┐                ┌─────────▼─────────┐
     │   Backends     │                │   Projection      │
     │  (ReactiveSDL) │                │   Pipeline        │
     └───────┬───────┘                └─────────┬─────────┘
             │                                  │
             │              ┌───────────────────┼───────────────────┐
             │              │                   │                   │
      ┌──────▼──────┐  ┌───▼────┐    ┌─────────▼──────┐   ┌───────▼───────┐
      │  SDL2/TTF   │  │ JSON → │    │  Syntax →  │   │ Text →  │
      │  (FFI)      │  │ Syntax │    │  Text    │   │  SDLText      │
      └─────────────┘  └───┬────┘    └────────┬───────┘   └───────┬───────┘
                           │                  │                   │
                    ┌──────▼──────────────────▼───────────────────▼──────┐
                    │              Reactive Cell Engine                  │
                    │                  (Reactive.jl)                     │
                    └───────────────────────────────────────────────────┘
```

The architecture has four layers, bottom to top:

### Layer 0 — Reactive Cell Engine (`Reactive.jl`)
### Layer 1 — Domain Modules (document data structures)
### Layer 2 — Projection Modules (domain-to-domain transformations)
### Layer 3 — Editor + Backend (REPL loop, IO)

---

## 4. Current Module Inventory

### Common Infrastructure

#### `Reactive.jl` — The Incrementality Engine

**Role:** Provides the foundation that replaces the original's `hu.dwim.computed-class` library.

- A single `Cell` type that is either *primitive* (holds a value) or *computed* (holds a zero-arg thunk).
- **Pull-based lazy evaluation:** computed cells are only evaluated when read (`c[]`).
- **Automatic dependency tracking:** a global `_computing` stack records which cell is currently evaluating; any cell read during that evaluation is registered as an upstream dependency.
- **Invalidation propagation:** when a primitive cell is written (`c[] = v`), all transitive downstream dependents are marked invalid. They will recompute lazily on next read.
- **Performance counters:** `perf_counters()` / `perf_reset!()` expose per-frame read/compute/write tallies.

#### `Projection.jl` — Shared Projection Interface

Defines two shared interface functions dispatched on by all projection types:

```julia
projection_print(projection, input, recursion, reference) → IoMap
projection_read(projection, iomap, event_or_op) → op_or_nothing
```

#### `IoMap.jl` — Generic IO Map

```julia
abstract type IoMap end

struct SimpleIoMap <: IoMap     # input + output + optional mapping
struct ChildrenIoMap <: IoMap   # input + vector of child iomaps
struct ContentIoMap <: IoMap    # input + content iomap
```

`IoMap` is an abstract type. `SimpleIoMap` is the common case returned by primitive projections. Projections that recurse into children or content use `ChildrenIoMap` / `ContentIoMap`. Projections with richer mapping needs define a specialised `{ProjectionName}IoMap` subtype.

#### `Operation.jl` — Domain Operations

```julia
struct ReplaceSelectionOperation
    path::ReferencePath
end
```

`ReplaceSelectionOperation` is the primary navigation operation. It carries a complete `ReferencePath` in any domain and is produced by the reader side of the pipeline. Additional operations include `QuitEditorOperation`, widget operations (`HideWidgetOperation`, `ShowWidgetOperation`, `ScrollWidgetOperation`, `SelectTabOperation`), primitive editing operations (`StringReplaceRangeOperation`, `NumberReplaceRangeOperation`), and `ReplaceFocusPartOperation`. See [operations.md](operations.md) for the full list.

---

### Domain Modules (`document/`)

#### `Reference.jl` — Universal Reference Types

A **reference** is a path-like pointer into a document, implemented as an immutable linked list of typed steps:

```julia
abstract type ReferencePath end
struct EmptyReferencePath <: ReferencePath end
struct ConcreteReferencePath <: ReferencePath
    head::Cell   # holds a ReferenceStep
    tail::Cell   # holds the next ReferencePath
end
```

Reference steps:

| Type | Meaning |
|---|---|
| `ElementReference(index::Cell)` | Descend to the i-th element (1-based) — for array/collection access |
| `PositionReference(index::Cell)` | Cursor position between elements (0-based) — for character offsets |
| `FieldReference(name::Cell)` | Descend by named field (object key, struct field) |
| `ProjectionReference(projection, output_path)` | Points to an element *introduced by a projection* (e.g. a delimiter) that has no direct counterpart in the input domain |

`ProjectionReference` is the mechanism by which the editor can represent cursor positions on characters like `"` (JSON string delimiters) that exist only in the projection's output, not in the underlying document.

A **selection** is a specific use of a `ReferencePath` — it is the path stored in a document's `selection::Cell` that identifies the currently focused position in that subtree.

#### `Json.jl` — JSON Domain

| Type | Content |
|---|---|
| `JsonNull` | No data field; `selection::Reference` |
| `JsonBool` | `value::Bool`; `selection::Reference` |
| `JsonNumber` | `value::Real`; `selection::Reference` |
| `JsonString` | `value::String`; `selection::Reference` |
| `JsonArray` | `elements::CellVector`; `collapsed::Bool`; `selection::Reference` |
| `JsonObjectEntry` | `key::String`; `value::Document`; `collapsed::Bool`; `selection::Reference` |
| `JsonObject` | `entries::CellVector`; `collapsed::Bool`; `selection::Reference` |

All types carry a `selection::Reference` that holds the current `ReferencePath` for that node.

#### `Syntax.jl` — Syntax Tree Domain

Generic intermediate representation between semantic domains and text:

| Type | Content |
|---|---|
| `SyntaxLeaf` | `open`, `close`, `value` (all `TextString`); `indentation::Int`; `collapsed::Bool`; `selection::Reference` |
| `SyntaxNode` | `open`, `close`, `sep` (all `TextString`); `children::CellVector`; `indentation::Int`; `collapsed::Bool`; `selection::Reference` |

#### `Text.jl`, `Graphics.jl`

`TextText` holds an `elements::CollectionDocument` and a `selection::Cell`.
`Graphics.jl` provides `GraphicsText`, `GraphicsRect`, and `GraphicsCanvas` — the SDL render primitives.

---

### Higher-Order Projections (`projection/higherorder/`)

| Module | Struct | Role |
|---|---|---|
| `SequentialProjection.jl` | `SequentialProjection` | Chains projections left to right; `projection_read` chains them right to left |
| `TypeDispatching.jl` | `TypeDispatchProjection` | Dispatches on `typeof(input)` to select the inner projection |
| `RecursiveProjection.jl` | `RecursiveProjection` | Wraps a projection and passes itself as `recursion` argument for self-referential trees |

All three implement both `projection_print` and `projection_read`. For the reader, `RecursiveProjection` and `TypeDispatchProjection` are transparent wrappers that forward to the selected inner projection's reader.

`SequentialProjection` stores the intermediate IoMaps in `SequentialProjectionIoMap.step_iomaps` so the reader can walk backwards through them:

```julia
function projection_read(seq, iomap, event)
    op = projection_read(seq.projections[end], iomap.step_iomaps[end], event)
    for i in (n-1):-1:1
        op === nothing && return nothing
        op = projection_read(seq.projections[i], iomap.step_iomaps[i], op)
    end
    return op
end
```

---

### Primitive Projections (`projection/primitive/`)

#### `JsonToSyntax.jl`

One projection struct per JSON type: `JsonStringToSyntaxLeaf`, `JsonArrayToSyntaxNode`, etc. The convenience constructor `JsonToSyntax()` wraps them in `RecursiveProjection(TypeDispatchProjection(...))`.

**Reader** (`JsonStringToSyntaxLeaf`):
- `PositionReference` in the incoming path → pass `ReplaceSelectionOperation` through unchanged (cursor is in the value characters).
- `FieldReference` → wrap in `ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))` so the JSON domain can represent "cursor on the opening/closing delimiter introduced by this projection".

**Reader** (`JsonArrayToSyntaxNode`, `JsonObjectToSyntaxNode`): translates child index / pair index paths back to JSON array indices / object field names.

#### `SyntaxToText.jl`

`SyntaxLeafToText` — maps a `SyntaxLeaf` to `Text(spans=[open, value, close])`. The `Text.selection` is a *computed cell* that calls `_leaf_cursor(leaf)` to derive the flat character offset from the leaf's own selection path.

`_leaf_cursor` supports:
- `PositionReference(k)` → `open_len + k` (cursor in value)
- `ProjectionReference(_, FieldReference("open") + PositionReference(k))` → `k` (cursor in open delimiter)
- `ProjectionReference(_, FieldReference("close") + PositionReference(k))` → `open_len + value_len + k` (cursor in close delimiter)

`SyntaxNodeToText` — full word-wrapping layout engine with indentation. Returns `SyntaxNodeToTextIoMap` that includes `child_char_ranges::Cell` for mapping flat positions back to child indices.

**Reader** (`SyntaxLeafToText`): maps a flat `PositionReference(pos)` back to:
- `pos < open_len` → `FieldReference("open") + PositionReference(pos)`
- `pos < open_len + value_len` → `PositionReference(pos - open_len)`
- otherwise → `FieldReference("close") + PositionReference(pos - close_start)`

**Reader** (`SyntaxNodeToText`): walks `_pos_to_selection(node, flat_pos, p, depth)` to find which child subtree the position falls in and builds a recursive `ElementReference(child_i) + <child_sel>` path.

#### `TextToGraphics.jl`

Word-wrapping layout engine: `projection_print` produces `GraphicsText` + `GraphicsRect` (cursor) from a `Text`. Returns `TextToGraphicsIoMap` with `char_to_coord::Cell` (segment-start table of `(char_start, x, y)` triples).

**Reader**: receives a `KeyPress`; translates `:left`/`:right` into a new `PositionReference` clamped to `0 .. total_len`:

```julia
function projection_read(::TextToGraphics, iomap, evt)
    evt isa KeyPress || return nothing
    delta = evt.key == :left ? -1 : evt.key == :right ? +1 : return nothing
    current = _cursor_position(iomap.input.selection[])
    total_len = sum(length(s.text[]) for s in iomap.input; init=0)
    ReplaceSelectionOperation(ConcreteReferencePath(PositionReference(clamp(current + delta, 0, total_len))))
end
```

---

### Devices and Editor (`device/`, `editor/`)

#### `Keyboard.jl` — `KeyPress`

Device-agnostic key representation. SDL keysyms are translated to `KeyPress` in the editor before reaching projections:

```julia
struct KeyPress
    key::Symbol   # :left, :right, :up, :down, :return, …
    ctrl::Bool
end
```

#### `Screen.jl` — SDL Rendering Backend

`print_to_device(screen, canvas)` renders a `GraphicsCanvas` to an SDL window using SDL2 + SDL_ttf.

#### `Editor.jl` — REPL Loop

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
end
```

The REPL loop (`run!`):
1. **READ** — `projection_read(editor)` polls SDL events. Quit/Escape handled directly; key events translated via `_sdl_to_keypress` and forwarded to `_projection_read(projection, iomap, key)`.
2. **EVAL** — `evaluate_operation(op, document)`. For `ReplaceSelectionOperation`: clears the old selection via `clear_selection!` then sets the new path via `set_selection!`. Since the document's `selection` cell is *shared* with the deepest projection's leaf, the new path propagates through all computed cells automatically.
3. **PRINT** — `projection_print(editor)` runs the full pipeline, stores the fresh `iomap` on `editor.iomap`, and renders to the screen.

---

## 5. The Projection Pipeline (Current State)

```
JsonString ──JsonStringToSyntaxLeaf──► SyntaxLeaf ──SyntaxLeafToText──► Text ──TextToGraphics──► GraphicsCanvas ──► SDL window
    ▲  (selection shared)                  │                                       │
    └──────────────────────────────────────┘                                       │
                                                                                   │
KeyPress ◄──projection_read chain (right to left) ◄──────────────────────────────┘
```

**Printer status:**
- ✅ JSON → Syntax (all types)
- ✅ Syntax → Text (leaf and node with word-wrap)
- ✅ Text → GraphicsCanvas (SDL2 text + cursor rect)
- ✅ SDL2 window rendering via `Screen.jl`
- ✅ All intermediate results are reactive `Cell`s; incremental recomputation throughout

**Reader status:**
- ✅ `TextToGraphics` — `:left`/`:right` → `ReplaceSelectionOperation` with flat position
- ✅ `SyntaxLeafToText` — flat position → leaf-domain path (value / open-delimiter / close-delimiter)
- ✅ `SyntaxNodeToText` — flat position → recursive child-index path
- ✅ `JsonStringToSyntaxLeaf` — leaf path → JSON path (pass-through or `ProjectionReference` for delimiters)
- ✅ `JsonArrayToSyntaxNode`, `JsonObjectToSyntaxNode` — child-index / pair paths → JSON array/object paths
- ✅ `SequentialProjection` — backward chain
- ✅ `TypeDispatchProjection`, `RecursiveProjection` — transparent wrappers

---

## 6. Design Decisions and Rationale

### 6.1 Pull-Based Reactivity (not push-based)

The `Cell` system is **pull-based / lazy**: invalidation propagates eagerly (marking cells invalid), but recomputation happens only on read. This matches ProjecturEd's design where:

- The printer is lazy — only visible parts are computed.
- The reader is driven by events — only the affected projection path is traversed.

A push-based system would eagerly recompute all dependents, wasting work on off-screen content.

### 6.2 Structural vs. Value Incrementality

Every domain module distinguishes two kinds of changes:

- **Value changes** (e.g. changing a JSON string's content) — invalidate only the leaf cell in the syntax tree, and through it only the corresponding styled span's text cell. The span list itself stays cached.
- **Structural changes** (e.g. adding an array element) — invalidate the children/spans cell, triggering a rebuild of the affected subtree's flat representation.

This two-level strategy avoids full-document recomputation for the common case (editing a single value).

### 6.3 Every Field is a Cell

All domain types wrap every field in a `Cell`, even fields that rarely change (like delimiters). This uniform approach:

- Keeps the type hierarchy simple (no separate "static" vs "reactive" variants).
- Allows any field to become computed later without changing the type.
- Enables projections to be expressed as simple thunks that read upstream cells.

### 6.4 Multiple Dispatch for Projections

Julia's multiple dispatch is a natural fit for ProjecturEd's **type-dispatch projection** pattern. `projection_print` dispatches on the concrete projection struct and input type — no visitor pattern or explicit type-case needed.

### 6.5 Module-per-Domain / Module-per-Projection

Each domain and each projection lives in its own module. This mirrors ProjecturEd's principle that domains are independent of each other and of projections, and projections depend only on their source and target domains.

### 6.6 `projection_print` Returns an IoMap

Rather than returning the output directly, every `projection_print` method returns an `IoMap` (generic or specialised). This ensures the reader always has access to both the input and output contexts. `SequentialProjection` collects all step IoMaps into `SequentialProjectionIoMap.step_iomaps`, enabling backward traversal in `projection_read`.

### 6.7 Shared Selection Cell

For a `JsonString`, the `selection::Cell` field on the `JsonString` struct is passed through unchanged to the `SyntaxLeaf` and on to the `Text`. All three objects reference the *same* `Cell`. When `evaluate_operation` writes `doc.selection[] = new_path`, the change is instantly visible at every level without any additional wiring. The printed cursor position is a computed cell reading that shared selection, so the cursor redraws automatically.

### 6.8 `ProjectionReference` for Projection-Introduced Elements

When the cursor moves onto a character that was introduced by a projection (e.g. the `"` delimiters of a JSON string), there is no corresponding index in the JSON document to point to. Rather than clamping or skipping these positions, the reference path contains a `ProjectionReference` step:

```julia
struct ProjectionReference <: ReferenceStep
    projection::Any         # which projection introduced this element
    output_path::ReferencePath  # where within that projection's output
end
```

This allows the editor to faithfully represent cursor positions over delimiters as `ProjectionReference(json_string_proj, FieldReference("open") + PositionReference(k))`. The printer (`_leaf_cursor`) knows how to render such a reference as a cursor offset within the flat text.

### 6.9 `KeyPress` Abstraction

SDL keysyms are converted to a `KeyPress(key::Symbol, ctrl::Bool)` struct in the editor before being passed to `projection_read`. This decouples projections from the SDL backend — a future terminal or web backend would produce the same `KeyPress` values, and the projection reader code stays unchanged.

---

## 7. Status and Roadmap

### Domains

Implemented (each lives in `program/src/document/`):

| Domain | Notes |
|---|---|
| **Json** | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject` + `JsonObjectEntry`, plus `JsonInsertion`/`JsonForeign` |
| **Xml** | `XmlText`, `XmlAttribute`, `XmlElement` |
| **Text** | `TextString`, `TextNewline`, `TextText` |
| **Syntax** | `SyntaxLeaf`, `SyntaxNode`, plus wrapper types `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` |
| **Graphics** | `GraphicsText`, `GraphicsRect`, `GraphicsCanvas`, `GraphicsViewport`, `GraphicsImage`, `GraphicsFence` |
| **Widget** | Full hierarchy from `WidgetLabel`/`WidgetButton`/`WidgetCheckbox` to `WidgetShell`/`WidgetSplitPane`/`WidgetTabbedPane`/`WidgetScrollPane`/`WidgetToolbar`/`WidgetMenu`/`WidgetScrollBar` |
| **Workbench** | IDE shell: `WorkbenchWorkbench` × 3 pages × {Navigator, Console, Descriptor, Operator, Searcher, Evaluator, Editor} |
| **Book** | `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture` |
| **Math** | `MathVariable`, `MathBinaryOperation`, `MathParenthesized`, `MathAssignment` |
| **Julia** | `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOp`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock` |
| **Primitive** | `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString` (plus `NumberReplaceRangeOperation`, `StringReplaceRangeOperation`) |
| **Table** | `TableCell`, `TableRow`, `TableColumn`, `TableTable` |
| **FileSystem** | `FileSystemFile`, `FileSystemDirectory` |
| **Collection** | `CellVector` (indexed reactive vector), `ListNode` (doubly-linked, optionally lazy) |
| **Color**, **Font**, **Geometry**, **Image**, **Clipboard** | Supporting types |

### Projections

Higher-order (`program/src/projection/higherorder/`):
`SequentialProjection`, `TypeDispatchingProjection`, `PredicateDispatchingProjection`,
`ReferenceDispatchingProjection`, `RecursiveProjection`, `AlternativeProjection`,
`NestingProjection`.

Generic (`program/src/projection/generic/`):
`PreservingProjection`, `InvariablyProjection`, `CopyingProjection`,
`ReversingProjection`, `SortingProjection`, `FocusingProjection`,
`FilteringProjection` (stub).

Compound (`program/src/projection/compound/`):
`ApplyAtProjection`, `SortingAtProjection`.

Primitive (`program/src/projection/primitive/`):
`JsonToSyntax`, `XmlToSyntax`, `SyntaxToText`, `TextToGraphics`, `TextToString`,
`WidgetToGraphics`, `WorkbenchToWidget`, `BookToSyntax`, `JuliaToSyntax`,
`MathToSyntax`, `PrimitiveToSyntax`, `CollectionToSyntax`, `ObjectToSyntax`,
`FileSystemToSyntax`, `TableToGraphics`, `LineNumbering`, `WordWrapping`,
`GraphicsCaching`.

### Reader status

The reverse-projection (`projection_read`) chain works end-to-end for
selection movement across all major pipelines (JSON, XML, Object, Widget,
Workbench). Each generic and higher-order projection implements
`map_reference_forward` / `map_reference_backward`.

### Remaining

| Task | Description |
|---|---|
| **Insert/delete operations** | First-class character editing for JSON primitives (analogous to the existing primitive edits) |
| **Undo/redo** | Operation log with inverse operations |
| **Domain coverage** | Continue closing gaps in newer domains (Math, Julia) |
| **Terminal backend** | Add a `KeyPress`-compatible terminal backend |
| **Web backend** | HTTP + WebSockets |

---

## 8. Module Dependency Graph

```
Reactive  (no deps)
  │
  ├── Projection            (no deps — interface only)
  ├── Document              (no deps — interface only)
  ├── IoMap                 (no deps)
  ├── Selection             (depends on Reactive)
  ├── Operation             (depends on Selection)
  │
  ├── Text            (depends on Reactive)
  ├── Syntax            (depends on Reactive, Text)
  ├── Graphics              (depends on Reactive)
  ├── Json                  (depends on Reactive, Selection)
  ├── Xml                   (depends on Reactive, Selection)
  │
  ├── SequentialProjection  (depends on Projection, IoMap)
  ├── TypeDispatching       (depends on Projection)
  ├── RecursiveProjection   (depends on Projection)
  │
  ├── JsonToSyntax      (depends on Json, Syntax, Text, Operation, Selection)
  ├── XmlToSyntax       (depends on Xml, Syntax, Text)
  ├── SyntaxToText(depends on Syntax, Text, Operation, Selection)
  ├── TextToGraphics  (depends on Text, Graphics, Operation, Selection, Keyboard)
  │
  ├── Keyboard              (no deps)
  ├── Screen                (depends on Graphics, SDL2)
  └── Editor                (depends on everything)
```

---

## 9. Mapping to ProjecturEd Concepts — Summary

| ProjecturEd (Lisp) | ProjecturEd (Julia) | Status |
|---|---|---|
| `computed-class` (change propagation) | `Reactive.Cell` | ✅ |
| JSON domain documents | `Json.jl` (`JsonValue` hierarchy) | ✅ |
| Tree domain documents | `Syntax.jl` (`SyntaxLeaf`, `SyntaxNode`) | ✅ |
| Styled string domain documents | `Text.jl` (`TextText`, `TextString`) | ✅ |
| Graphics domain documents | `Graphics.jl` (`GraphicsText`, `GraphicsRect`, `GraphicsCanvas`) | ✅ |
| JSON → Tree projection (printer) | `JsonToSyntax.jl` | ✅ |
| Tree → Styled String projection (printer) | `SyntaxToText.jl` | ✅ |
| Styled String → Graphics projection (printer) | `TextToGraphics.jl` | ✅ |
| SDL backend (rendering + events) | `Screen.jl`, `Editor.jl` | ✅ |
| IO Maps | `IoMap.jl` + per-projection specialisations | ✅ |
| References | `Reference.jl` (`ElementReference`, `PositionReference`, `FieldReference`, `ProjectionReference`) | ✅ |
| Operations (navigation) | `Operation.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `Editor.jl` (`run!`) | ✅ |
| Reader (reverse projection) | `projection_read` on all pipeline projections | ✅ (JsonString pipeline) |
| Higher-order projections | `SequentialProjection`, `TypeDispatchProjection`, `RecursiveProjection` | ✅ |
| Operations (insert/delete) | — | ❌ |
| Mouse/click selection | — | ❌ |
| Undo/redo | — | ❌ |
| Domain-independent projections | — | ❌ |

---

## 11. The Reference and Selection Mechanism

### 11.1 What a Reference Is

A **reference** is a path-like pointer into a document tree — a sequence of typed *steps*, each one descending one level. A reference may identify a cursor position for editing, a highlighted region, a focused sub-document, or any other designated point of interest. The **selection** is a specific use of a reference: the path stored in a document's `selection::Cell` that identifies the currently focused position in that subtree.

| Step type | Meaning |
|---|---|
| `ElementReference(k)` | Descend to the `k`-th child (1-based) — for array/collection access |
| `PositionReference(k)` | Cursor position between elements (0-based) — for character offsets |
| `FieldReference(name)` | Descend into the named field of the current node |
| `ProjectionReference(p, inner)` | Points to something introduced by projection `p`; `inner` locates it within `p`'s output |

Paths are represented as an immutable linked list so that sharing and extending a path costs no copying:

```julia
abstract type ReferencePath end
struct EmptyReferencePath <: ReferencePath end
struct ConcreteReferencePath <: ReferencePath
    head::Cell   # holds a ReferenceStep
    tail::Cell   # holds the next ReferencePath
end
```

`EmptyReferencePath` terminates the list. The convenience constructor `ReferencePath(s1, s2, …)` builds a right-to-left chain. Both fields of `ConcreteReferencePath` are `Cell`s so the path is reactive — a computed cell can depend on a path's content.

### 11.2 The Document Contract

**Not every Julia object participates in the selection mechanism.** Only types that subtype `Document` do. `Document.jl` declares the contract:

```julia
abstract type Document end
```

Every concrete `Document` **must** carry a `selection::Cell` field. That cell holds the `ReferencePath` *relative to this node* — the suffix of the full path starting at this level.

The invariant is: **every child reached by a step in the path must itself be a `Document`**. There are no plain Julia collections or primitives along a selection path — any collection type that appears in the document tree must be wrapped in a document type with its own `selection` field.

### 11.3 Recursive Storage: `set_selection!`

When the editor applies a `ReplaceSelectionOperation` operation it calls:

```julia
set_selection!(document, new_path)
```

The generic implementation lives in `Reference.jl` and walks the path step by step:

1. If `path` is `EmptyReferencePath`, stop — there is nothing to descend into.
2. Read the head step `h = path.head[]`.
3. Navigate to the child document:
   - `FieldReference(name)` → `getfield(document, Symbol(name))`, unwrapping a `Cell` transparently if the field is reactive.
   - `ElementReference(k)` → `document[k]` (1-based indexing, matches Julia convention).
   - `PositionReference(k)` → cursor position, does not navigate into a child document.
   - `ProjectionReference` → stop; this step does not navigate into a child document.
4. Write `tail` into the child's `selection` cell: `child.selection[] = rest`.
5. Recurse: `set_selection!(child, rest)`.

`Syntax.jl` provides a specialised override for `SyntaxNode` that additionally clears the `selection` on every *other* child to `nothing` before setting the selected one, ensuring stale selection state does not linger on siblings.

**Example** — a `JsonObject` whose first entry contains a `JsonString`, with path `[1] + .value + {3}` (entry 1, cursor at offset 3 in the string):

```
JsonObject.selection[]       ← [1] + .value + {3}   (full path)
  └─ entries[1] (JsonObjectEntry).selection[] ← .value + {3}
       └─ value[] (JsonString).selection[]    ← {3}
```

Every node along the path is a `Document`. The `String` holding the actual characters is terminal and not navigated into.

### 11.4 Selection Stored in Each Domain Type

| Type | `selection` meaning |
|---|---|
| `JsonNull / JsonBool / JsonNumber / JsonString` | Path within this primitive — typically `{k}` for cursor at offset `k` |
| `JsonArray` | `[i] + <child path>` — into element `i` (1-based) |
| `JsonObjectEntry` | `.key + {k}` (cursor in key) or `.value + <child path>` |
| `JsonObject` | `[i] + <entry path>` — into entry `i` (1-based) |
| `SyntaxLeaf` | `.open/.value/.close + {k}` — cursor at offset `k` in the named span |
| `SyntaxNode` | `[i] + <child path>` — into child `i` (1-based); or `.open/.close + {k}` for cursor in delimiter |
| `Text` | `{k}` — flat cursor at offset `k` in the concatenated spans |

`GraphicsText`, `GraphicsRect`, and `GraphicsCanvas` are **not** selectable containers and carry no `selection` field. They are terminal objects in the projection pipeline's output and the selection mechanism does not enter them.

### 11.5 How the Printer Projects the Selection

Every `projection_print` method maps both the input *content* and the input *selection* forward into the output domain. The selection mapping is expressed as a **computed cell** on the output document so that it updates reactively whenever the input selection changes:

```julia
# SyntaxLeafToText — excerpt
function projection_print(::SyntaxLeafToText, leaf::SyntaxLeaf, ...)
    sel = Cell(() -> begin
        c = _leaf_cursor(leaf)   # reads leaf.selection[] as a dependency
        c < 0 ? nothing : ConcreteReferencePath(PositionReference(c))
    end)
    IoMap(leaf, Text(Cell(...spans...), sel))
end
```

`_leaf_cursor` translates the `SyntaxLeaf`-domain path into a single flat character offset according to these rules:

| Leaf selection | Flat offset |
|---|---|
| `.open + {k}` | `k` |
| `.value + {k}` | `open_len + k` |
| `.close + {k}` | `open_len + value_len + k` |
| `ProjectionReference(p, .open + {k})` | `k` |
| `ProjectionReference(p, .close + {k})` | `open_len + value_len + k` |

For `SyntaxNodeToText`, cursor projection is more involved: `_structural_cursor` calls `_syntax_to_flat` which recursively accumulates character widths across separators, newlines, and indentation spans until it reaches the selected child subtree, then adds the child's own local cursor offset.

The key point is that **the selection is not passed as a parameter through `projection_print`** — it is wired reactively. The output document's `selection` cell reads from the input document's `selection` cell as a computed dependency, so the projected selection updates automatically whenever `set_selection!` writes to any node's `selection[]`.

### 11.6 How the Reader Translates the Selection

The reader side walks the projection chain right-to-left, translating a `ReplaceSelectionOperation` operation from the output domain back to the input domain at each step.

**`TextToGraphics`** (outermost reader):
- Receives a `KeyPress(:left, false)` / `KeyPress(:right, false)` device event.
- Reads the current flat cursor offset from `iomap.input.selection[]`.
- Produces `ReplaceSelectionOperation({new_pos})` in `Text` domain.

**`SyntaxLeafToText`**:
- Receives `ReplaceSelectionOperation({pos})`.
- Partitions `pos` against `open_len` and `open_len + value_len`.
- Returns `ReplaceSelectionOperation(.open + {pos})`, `ReplaceSelectionOperation(.value + {pos - open_len})`, or `ReplaceSelectionOperation(.close + {pos - close_start})`.

**`SyntaxNodeToText`**:
- Receives `ReplaceSelectionOperation({flat_pos})`.
- Calls `_pos_to_selection(node, flat_pos, p, 0)` which walks the tree, accounting for all structural characters (delimiters, separators, newlines, indentation), to locate the owning child and its local offset.
- Returns `ReplaceSelectionOperation([child_i] + <recursive child path>)`. Positions that fall on structural characters not owned by any child become `ProjectionReference(p, {flat_pos})`.

**`JsonStringToSyntaxLeaf`** (innermost reader):
- `.value + {k}` → passes through as `{k}` (cursor is inside the JSON string value).
- `.open + {k}` / `.close + {k}` → wraps in `ProjectionReference` because quote delimiters have no counterpart in the JSON domain.

The final `ReplaceSelectionOperation` is applied by the editor:

```julia
function evaluate_operation(op::ReplaceSelectionOperation, document)
    clear_selection!(document)
    set_selection!(document, op.path)
end
```

`clear_selection!` recursively clears the old selection from the document tree; `set_selection!` then sets the full path on the root document and propagates the appropriate suffix down to each child document along the path.

### 11.7 The Shared-Cell Shortcut

For a simple single-leaf pipeline (e.g. `JsonString`), the printer passes the *same* `selection::Cell` object from the `JsonString` struct through to the `SyntaxLeaf` and on to the `Text`. All three objects reference the same `Cell` instance. When `evaluate_operation` writes `doc.selection[] = op.path`, the change is immediately visible at every projection level without any additional wiring, because the `Text.selection` computed cell reads `leaf.selection` which reads `json_string.selection` — they are the same cell.

This optimisation holds because `Cell` is a mutable heap object passed by reference, not a value. It is only valid for the degenerate case where the structure of the document does not change across projection levels. For compound structures (`JsonArray`, `JsonObject`, `SyntaxNode`) each child document manages its own `selection` cell, and `set_selection!` sets them individually.

### 11.8 Selection Path Conventions by Domain

Throughout: `[i]` is the i-th item (1-based), `{k}` is the cursor at boundary `k` (0-based) — see [the boundary axis](editor/reference.md#the-boundary-axis).

| Domain | Path form | Meaning |
|---|---|---|
| `Text` | `{k}` | cursor at offset `k` in the flat span sequence |
| `SyntaxLeaf` | `.value + {k}` | cursor at offset `k` in the value span |
| `SyntaxLeaf` | `.open + {k}` | cursor at offset `k` in the opening delimiter |
| `SyntaxLeaf` | `.close + {k}` | cursor at offset `k` in the closing delimiter |
| `SyntaxNode` | `[i] + <child path>` | into child `i` (1-based) |
| `SyntaxNode` | `.open + {k}` | cursor at offset `k` in the open delimiter span |
| `SyntaxNode` | `.close + {k}` | cursor at offset `k` in the close delimiter span |
| `SyntaxNode` | `ProjectionReference(p, {k})` | projection-introduced whitespace at flat offset `k` |
| `JsonString` | `{k}` | cursor at offset `k` in the string value |
| `JsonString` | `ProjectionReference(p, .open + {k})` | cursor on the `"` opening quote |
| `JsonString` | `ProjectionReference(p, .close + {k})` | cursor on the `"` closing quote |
| `JsonArray` | `[i] + <element path>` | into element `i` (1-based) |
| `JsonObject` | `[i] + .value + <value path>` | into the value of entry `i` (1-based) |
| `JsonObject` | `[i] + .key + {k}` | cursor at offset `k` in the key string of entry `i` |

### 11.9 Selection Projection Under Recursion

When a primitive projection recurses into child sub-documents (by calling
`projection_print(recursion, child, recursion)` for each element), the printer
must compute the **output** document's selection correctly. The rule is a
three-step algorithm executed inside the output selection's computed `Cell`:

**Step 1 — Recurse first, collect child iomaps.**
Before computing the output selection, the projection must recurse into all
relevant children and retain the resulting iomaps (not just the `.output`
fields). These iomaps record both the input child and the projected output
child, and in particular they hold the output child document whose `selection`
cell is the projected, domain-correct selection.

```julia
child_iomaps = Cell(() -> [projection_print(recursion, child, recursion)
                            for child in elements])
```

**Step 2 — Find the child pointed to by the input selection.**
Inspect the head of the input document's `selection[]` path to determine which
child (index `i`) the input selection designates. Strip the steps that the
projection itself owns (e.g. a `FieldReference("elements")` wrapper on a JSON
array) until the head step is the one that identifies the child.

**Step 3 — Extend the child's output selection with the projection's own fragment.**
Read `child_iomaps[][i+1].output.selection[]` — this is the selection already
translated into the output domain by the child's own printer. Then prepend
whatever selection step this projection introduces at the parent level (e.g.
`[i]` for the i-th child slot in a `SyntaxNode`) to obtain the full output
selection path.

```julia
sel = Cell(() -> begin
    path = input.selection[]
    # … strip projection-owned prefix steps to extract child index i …
    iomaps = child_iomaps[]
    (i + 1 > length(iomaps)) && return nothing
    child_sel = iomaps[i + 1].output.selection[]
    child_sel === nothing && return nothing
    ConcreteReferencePath(ElementReference(Cell(i)), child_sel)
end)
```

**Why the direct-tail shortcut is wrong.**
A naïve implementation strips the projection's prefix from the input selection
and passes the remaining tail directly as the output document's selection:

```julia
sel = Cell(() -> begin
    path = input.selection[]
    # strip .elements → returns [i] + <rest>
    path.tail[]   # ← WRONG: <rest> is in the INPUT domain
end)
```

This is incorrect because `<rest>` is a path in the **input domain** (e.g.
`{3}` for a `JsonString` cursor offset). The output child document lives
in the **output domain** (e.g. a `SyntaxLeaf`) and its `selection` must hold
an output-domain path (e.g. `.value + {3}`). Passing the input-domain
tail directly bypasses the child projection's selection mapping entirely, so
the output child's selection cell sees a semantically wrong path and fails to
locate the cursor.

**The shared-cell shortcut does not help here.**
Section 11.7 describes an optimisation where the input document's `selection`
cell is passed by reference through to the output document, so both share the
same `Cell`. This is only valid for *leaf-to-leaf* projections where the input
and output selection formats are identical (e.g. `JsonString → SyntaxLeaf`
when the selection is managed externally by `set_selection!`). For *compound*
projections that recurse into children the formats differ across domains, so
the three-step iomap-based algorithm is required.

**Concrete example — `JsonArrayToSyntaxNode`.**
Input: `JsonArray` with `selection[] = .elements + [2] + {5}` (second element, cursor at offset 5).
Output: `SyntaxNode` whose children are projected `Syntax` elements.

Correct computation of the `SyntaxNode`'s `selection`:
1. Recurse: `child_iomaps = [projection_print(recursion, x, recursion) for x in array]`
2. Strip `.elements`, then read `[2]` → child index `i = 2`.
3. Read `child_iomaps[2].output.selection[]` — the projected child selection
   in `Syntax` domain (e.g. `.value + {5}` for a `JsonString` element).
4. Prepend `[2]` → output selection = `[2] + .value + {5}`.

**Concrete example — `JsonObjectToSyntaxNode`.**
The outer `SyntaxNode` wraps per-entry pair `SyntaxNode`s. Each pair's
children are `[key_leaf (index 1), value_subtree (index 2)]` (1-based). For a
`JsonObject` selection `.entries + [1] + .value + {4}`:

1. Recurse into each entry to obtain pair-node iomaps.
2. Strip `.entries`, read `[1]` → entry index `i = 1`.
3. Read `pair_iomaps[1].output.selection[]` — the projected pair-node selection
   in `Syntax` domain (e.g. `[2] + .value + {4}` after the pair
   node's own selection projection maps the value child).
4. Prepend `[1]` → output selection = `[1] + [2] + .value + {4}`.

**Implication for child iomap caching.**
Because both the children `Cell` (which supplies the child output documents to
the `SyntaxNode`) and the selection `Cell` (which reads the child output
selections) must call `projection_print` on the same children, the child iomaps
must be computed in a **shared** reactive `Cell` rather than inline in each
consumer. Computing them inline in two separate cells would instantiate
different output document objects, breaking the identity invariant that the
selection cell reads from the same document the children cell exposes.

---

## 10. Key Differences from the Original

1. **Language:** Julia. Multiple dispatch replaces CLOS generic functions. Modules replace packages. `Cell` replaces `computed-class` slots.
2. **Reactivity model:** The original uses a computed-class library with slot-level change propagation. This reimplementation uses an explicit `Cell` type with manual thunk wiring — more verbose but more transparent and debuggable.
3. **No metaclass magic:** In the original, computed slots are part of the class definition via MOP. In Julia, each struct field is explicitly typed as `Cell`, and dependency wiring is done in constructors and projection functions.
4. **Projection as structs with dispatch:** Projections are lightweight structs (e.g. `JsonStringToSyntaxLeaf`, `TextToGraphics`). `projection_print` and `projection_read` are dispatched on the projection struct, enabling higher-order projections to compose them uniformly via the shared interface.
5. **Shared selection cell:** The document's `selection::Cell` is passed by reference through the projection chain, so `evaluate_operation` writing to it is immediately visible to the printer's cursor computation — no explicit selection propagation step needed.
6. **`ProjectionReference`:** The original ProjecturEd uses a different approach to delimiter selections. This reimplementation introduces `ProjectionReference` as an explicit reference step that encodes "cursor is on output introduced by this projection", allowing faithful round-tripping through the reader without clamping or special-casing.
7. **Scope:** The original supports dozens of domains and projections. This reimplementation has a complete vertical slice (JSON string editing with full cursor movement) and is expanding domain by domain.
