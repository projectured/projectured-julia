# Architecture

This document covers the layer diagram, the module inventory, and the
projection pipeline status. For design rationale see
[design-decisions.md](design-decisions.md). For the full reference/selection
mechanism see [selection-deep-dive.md](selection-deep-dive.md).

---

## Layer diagram

```
┌──────────────────────────────────────────────────────────┐
│                       Editor (REPL)                      │
│  read events → project(reader) → apply op → project(printer) → render  │
└────────────┬──────────────────────────────────┬──────────┘
             │                                  │
     ┌───────▼───────┐                ┌─────────▼─────────┐
     │   Backends     │                │   Projection      │
     │  (SDL2)        │                │   Pipeline        │
     └───────┬───────┘                └─────────┬─────────┘
             │                                  │
             │              ┌───────────────────┼───────────────────┐
             │              │                   │                   │
      ┌──────▼──────┐  ┌───▼────────┐  ┌───────▼───────┐  ┌───────▼──────┐
      │  SDL2/TTF   │  │ JSON →     │  │ Syntax →      │  │ Text →       │
      │  (FFI)      │  │ Syntax     │  │ Text          │  │ GraphicsCanvas│
      └─────────────┘  └───┬────────┘  └────────┬──────┘  └───────┬──────┘
                           │                    │                  │
                    ┌──────▼────────────────────▼──────────────────▼──────┐
                    │              Reactive Cell Engine                    │
                    │                  (Reactive.jl)                       │
                    └─────────────────────────────────────────────────────┘
```

Four layers, bottom to top:

| Layer | Modules | Role |
|---|---|---|
| 0 — Reactive engine | `Reactive.jl` | `Cell` type, dependency tracking, lazy invalidation |
| 1 — Domain modules | `document/*.jl` | Document/operation types per problem area |
| 2 — Projection modules | `projection/**/*.jl` | Domain-to-domain transformations |
| 3 — Editor + backend | `editor/*.jl`, `backend/Sdl.jl` | REPL loop, rendering, device I/O |

---

## Module inventory

### Layer 0 — Reactive Cell Engine

**`Reactive.jl`**

- A single `Cell` type — either *primitive* (holds a value) or *computed*
  (holds a zero-arg thunk).
- **Pull-based lazy evaluation:** computed cells evaluate only on read (`c[]`).
- **Automatic dependency tracking:** a global `_computing` stack registers
  every cell read during a computation as an upstream dependency.
- **Invalidation:** writing a primitive cell (`c[] = v`) marks all transitive
  downstream dependents invalid; they recompute lazily on next read.
- **Performance counters:** `perf_counters()` / `perf_reset!()` expose
  per-frame read/compute/write tallies.

### Layer 1 — Domain modules (`document/`)

| Module | Types |
|---|---|
| `Reference.jl` | `ReferencePath`, `EmptyReferencePath`, `ConcreteReferencePath`; step types `ElementReference`, `PositionReference`, `FieldReference`, `ProjectionReference`, `RangeReference`, `TypeReference`, `FunctionReference` |
| `Json.jl` | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`, `JsonObjectEntry` |
| `Xml.jl` | `XmlText`, `XmlAttribute`, `XmlElement` |
| `Text.jl` | `TextText`, `TextString`, `TextNewline` |
| `Syntax.jl` | `SyntaxLeaf`, `SyntaxNode`; wrapper types `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` |
| `Graphics.jl` | `GraphicsText`, `GraphicsRect`, `GraphicsCanvas`, `GraphicsViewport`, `GraphicsImage`, `GraphicsFence` |
| `Widget.jl` | `WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`, `WidgetMenuItem`, `WidgetComposite`, `WidgetShell`, `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`, `WidgetToolbar`, `WidgetScrollBar` |
| `Workbench.jl` | `WorkbenchWorkbench`, `WorkbenchPage`, `WorkbenchNavigator`, `WorkbenchConsole`, `WorkbenchDescriptor`, `WorkbenchOperator`, `WorkbenchSearcher`, `WorkbenchEvaluator`, `WorkbenchAssistant`, `WorkbenchEditor` |
| `Book.jl` | `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture` |
| `Math.jl` | `MathVariable`, `MathBinaryOperation`, `MathParenthesized`, `MathAssignment` |
| `Julia.jl` | `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOp`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock` |
| `Primitive.jl` | `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`; ops `NumberReplaceRangeOperation`, `StringReplaceRangeOperation` |
| `Table.jl` | `TableCell`, `TableRow`, `TableColumn`, `TableTable` |
| `FileSystem.jl` | `FileSystemFile`, `FileSystemDirectory` |
| `Collection.jl` | `CellVector`, `ListNode` |
| `Font.jl`, `Color.jl`, `Geometry.jl`, `Image.jl`, `Clipboard.jl` | Supporting types |

### Layer 2 — Projection modules (`projection/`)

**Higher-order** (`higherorder/`):

| Struct | Role |
|---|---|
| `SequentialProjection` | Chains projections left-to-right; reader chains right-to-left |
| `TypeDispatchingProjection` | Dispatches on `typeof(input)` |
| `RecursiveProjection` | Passes itself as `recursion` for self-referential trees |
| `AlternativeProjection` | Tries each sub-projection; uses the first that succeeds |
| `PredicateDispatchingProjection` | Dispatches on a boolean predicate over the input |
| `ReferenceDispatchingProjection` | Dispatches on the current selection reference |
| `NestingProjection` | Scopes an inner projection to a sub-document |

**Generic** (`generic/`):

| Struct | Role |
|---|---|
| `PreservingProjection` | Identity (output = input) |
| `InvariablyProjection` | Returns a fixed output regardless of input |
| `CopyingProjection` | Deep-copies a document tree |
| `ReversingProjection` | Reverses child order |
| `SortingProjection` | Sorts children by a key function |
| `FilteringProjection` | Removes elements that fail a predicate |
| `FocusingProjection` | Projects a focused sub-document |

**Compound** (`compound/`):
`ApplyAtProjection`, `SortingAtProjection`.

**Primitive** (`primitive/`):

| Struct | Source → Target |
|---|---|
| `JsonToSyntax` | `Json` → `Syntax` |
| `XmlToSyntax` | `Xml` → `Syntax` |
| `BookToSyntax` | `Book` → `Syntax` |
| `MathToSyntax` | `Math` → `Syntax` |
| `JuliaToSyntax` | `Julia` → `Syntax` |
| `PrimitiveToSyntax` | `Primitive` → `Syntax` |
| `CollectionToSyntax` | `Collection` → `Syntax` |
| `ObjectToSyntax` | Any Julia value → `Syntax` |
| `FileSystemToSyntax` | `FileSystem` → `Syntax` |
| `SyntaxToText` | `Syntax` → `Text` |
| `TextToGraphics` | `Text` → `Graphics` |
| `TextToString` | `Text` → `String` |
| `TableToGraphics` | `Table` → `Graphics` (direct) |
| `WidgetToGraphics` | `Widget` → `Graphics` |
| `WorkbenchToWidget` | `Workbench` → `Widget` |
| `GraphicsCaching` | `Graphics` → `Graphics` (caching layer) |
| `LineNumbering` | `Text` → `Text` (domain-preserving) |
| `WordWrapping` | `Text` → `Text` (domain-preserving) |

### Layer 3 — Editor and backend

| Module | Role |
|---|---|
| `Editor.jl` | REPL loop: read → eval → print |
| `Application.jl` | `application()` entry point; initialises backend and starts the loop |
| `backend/Sdl.jl` | SDL2 + SDL_ttf backend: rendering, event translation, `write_image` |
| `device/Window.jl` | `Window` device; `QuitEvent` |
| `device/Keyboard.jl` | `KeyDown`, `KeyUp`, `KeyPress` |
| `device/Mouse.jl` | `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll` |
| `editor/Mcp.jl` | MCP server: JSON-RPC over HTTP exposing documents and operations |

---

## Module dependency graph

```
Reactive  (no deps)
  │
  ├── ProjectionApiModule   (no deps — interface only)
  ├── DocumentApiModule     (no deps — interface only)
  ├── IoMapApiModule        (no deps)
  ├── OperationApiModule    (depends on Reactive)
  │
  ├── Reference.jl          (depends on Reactive)
  ├── Text.jl               (depends on Reactive)
  ├── Syntax.jl             (depends on Reactive, Text)
  ├── Graphics.jl           (depends on Reactive)
  ├── Json.jl               (depends on Reactive, Reference)
  ├── Xml.jl                (depends on Reactive, Reference)
  │
  ├── SequentialProjection  (depends on ProjectionApi, IoMap)
  ├── TypeDispatching       (depends on ProjectionApi)
  ├── RecursiveProjection   (depends on ProjectionApi)
  │
  ├── JsonToSyntax          (depends on Json, Syntax, Text, Operation, Reference)
  ├── XmlToSyntax           (depends on Xml, Syntax, Text)
  ├── SyntaxToText          (depends on Syntax, Text, Operation, Reference)
  ├── TextToGraphics        (depends on Text, Graphics, Operation, Reference, Keyboard)
  │
  ├── Keyboard.jl           (no deps)
  ├── backend/Sdl.jl        (depends on Graphics, Keyboard, Mouse, Window, Image, ProjectionApi, IoMap)
  └── editor/Editor.jl      (depends on everything)
```

---

## Projection pipeline status

### Printer

| Step | Status |
|---|---|
| JSON → Syntax (all types) | ✅ |
| XML → Syntax | ✅ |
| Book / Math / Julia / Primitive / Collection → Syntax | ✅ |
| Syntax → Text (leaf and node with word-wrap) | ✅ |
| Text → GraphicsCanvas (SDL2 text + cursor rect) | ✅ |
| Table → GraphicsCanvas (direct) | ✅ |
| Widget → GraphicsCanvas | ✅ |
| Workbench → Widget → GraphicsCanvas | ✅ |
| SDL2 window rendering | ✅ |
| Offscreen BMP export (`write_image`) | ✅ |

### Reader (reverse projection)

| Step | Status |
|---|---|
| Selection movement across all major pipelines | ✅ |
| `TextToGraphics` — `:left` / `:right` → `ReplaceSelectionOperation` | ✅ |
| `SyntaxLeafToText` — flat position → leaf-domain path | ✅ |
| `SyntaxNodeToText` — flat position → recursive child path | ✅ |
| `JsonToSyntax` — all node types | ✅ |
| `SequentialProjection`, `TypeDispatching`, `RecursiveProjection` | ✅ |
| Character editing (`StringReplaceRangeOperation`) | ⚠️ partial |
| Mouse click-to-select | ⚠️ partial |
| Undo / redo | ❌ |

---

## Mapping to the original ProjecturEd

| Lisp ProjecturEd | Julia ProjecturEd | Status |
|---|---|---|
| `computed-class` (change propagation) | `Reactive.Cell` | ✅ |
| JSON domain | `Json.jl` | ✅ |
| Tree domain | `Syntax.jl` | ✅ |
| Styled string domain | `Text.jl` | ✅ |
| Graphics domain | `Graphics.jl` | ✅ |
| SDL backend | `backend/Sdl.jl` | ✅ |
| IO Maps | `IoMap.jl` + per-projection | ✅ |
| References | `Reference.jl` | ✅ |
| Navigation operations | `Operation.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `Editor.jl` | ✅ |
| All higher-order projections | `projection/higherorder/` | ✅ |
| Insert / delete operations | — | ❌ |
| Undo / redo | — | ❌ |
