# Architecture

This document covers the layer diagram, the module inventory, and the
projection pipeline status. For design rationale see the
[design decisions guide](design-decisions.md). For the full reference/selection
mechanism see the [selection deep dive](selection-deep-dive.md).

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
     │ (SDL2/Console) │                │   Pipeline        │
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
| 3 — Editor + backend | `editor/*.jl`, `backend/{Sdl,Console,Web}.jl` | REPL loop, rendering, device I/O |

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
| `Reference.jl` | `ReferencePath`, `EmptyReferencePath`, `ConcreteReferencePath`; step structs `RangeReference`, `FieldReference`, `ProjectionReference`, `TypeReference`, `FunctionReference`, `PointReference`, `TextRectangularReference` (`ElementReference`/`PositionReference` are convenience constructors that produce a `RangeReference`, not distinct structs) |
| `Json.jl` | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`, `JsonObjectEntry` |
| `Xml.jl` | `XmlText`, `XmlAttribute`, `XmlElement` |
| `Text.jl` | `TextText`, `TextString`, `TextNewline` |
| `Syntax.jl` | `SyntaxLeaf`, `SyntaxNode`; wrapper types `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` |
| `Graphics.jl` | `GraphicsText`, `GraphicsRect`, `GraphicsCanvas`, `GraphicsViewport`, `GraphicsImage`, `GraphicsFence` |
| `Widget.jl` | Core: `WidgetInsertion`, `WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`, `WidgetMenuItem`, `WidgetComposite`, `WidgetToolbar`, `WidgetShell`, `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`, `WidgetScrollBar`. Extension: `WidgetBadge`, `WidgetSeparator`, `WidgetCard`, `WidgetSwitch`, `WidgetProgress`, `WidgetSlider`, `WidgetRadioGroup`, `WidgetAvatar`, `WidgetAlert`, `WidgetSkeleton`, `WidgetToggle`, `WidgetToggleGroup`, `WidgetSelect`, `WidgetTextarea`, `WidgetAccordion`, `WidgetTable`, `WidgetTree` |
| `Workbench.jl` | `WorkbenchWorkbench`, `WorkbenchPage`, `WorkbenchNavigator`, `WorkbenchConsole`, `WorkbenchDescriptor`, `WorkbenchOperator`, `WorkbenchSearcher`, `WorkbenchEvaluator`, `WorkbenchAssistant`, `WorkbenchEditor` |
| `Book.jl` | `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture` |
| `Math.jl` | `MathVariable`, `MathBinaryOperation`, `MathParenthesized`, `MathAssignment` |
| `Julia.jl` | `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOp`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock` |
| `Primitive.jl` | `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`; ops `NumberReplaceRangeOperation`, `StringReplaceRangeOperation` |
| `Table.jl` | `TableCell`, `TableRow`, `TableColumn`, `TableTable` |
| `FileSystem.jl` | `FileSystemFile`, `FileSystemDirectory` |
| `Collection.jl` | `CellVector`, `CellMatrix`, `CellTable`, `ListNode` |
| `Dragging.jl` | `DraggingState` — transparent wrapper marking a sub-tree as drag-and-drop reorderable (paired with `DraggingProjection`) |
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
| `WindowManagerProjection` | Passthrough printer; reader applies window open/close ops to the `ScreenDocument` |
| `EnvelopeUnwrappingProjection` | Passthrough printer; reader strips the `EventEnvelope` off the gesture — the envelope-unwrap seam for pipelines with no screen/window layer (e.g. the `ConsoleBackend`'s) |
| `TooltipDecoratorProjection` | Dispatches on `TooltipSource`; reader runs a show/hide state machine |
| `DraggingProjection` | Dispatches on `DraggingState`; reader runs a press→drag→drop state machine emitting `MoveRangeOperation` |
| `ProjectionConfiguringProjection` | Extends the inner projection's output with an editable parameter-control bar |

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
| `SearchingProjection` | Collects every object with a field matching a `Regex` |
| `ObjectToWidget` | Reflection-driven editable form for an object's `Cell` fields |

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
| `PrimitiveToText` | `Primitive` → `Text` |
| `ReferenceToText` | `Reference` → `Text` |
| `TextFiltering` | `Text` → `Text` (filter rows) |
| `TextHighlighting` | `Text` → `Text` (highlight matches) |
| `SqlToSyntax` | `Sql` → `Syntax` |
| `SqlToCellTable` | `Sql` → `CellTable` |
| `CellTableToTable` | `CellTable` → `Table` |
| `ConversationToSyntax` | `Conversation` → `Syntax` |
| `ConversationToWidget` | `Conversation` → `Widget` |
| `LayoutToGraphics` | `Layout` → `Graphics` |
| `WorkspaceToFileSystem` | `Workspace` → `FileSystem` |
| `DatabaseInstanceToDbCatalog` | `DatabaseInstance` → `DbCatalog` |
| `DatabaseTableToTabularGrid` | `DatabaseTable` → `TabularGrid` |
| `DbCatalogToSyntax` | `DbCatalog` → `Syntax` |
| `DbCatalogToJson` | `DbCatalog` → `Json` |

### Layer 3 — Editor and backend

| Module | Role |
|---|---|
| `Editor.jl` | REPL loop: read → eval → print; `run!(backend, projection, document)` entry point |
| `backend/Sdl.jl` | SDL2 + SDL_ttf backend: graphics rendering, event translation, `write_image` |
| `backend/Console.jl` | Terminal backend: renders the **Text** domain (a `TextText`) to the terminal with ANSI colors and reads keystrokes — no `TextToGraphics`/SDL ([devices and backends](devices-and-backends.md#consolebackend)) |
| `backend/Web.jl` | Web backend: HTTP + WebSocket server, JSON draw-list (with dirty-rect patches), browser renderer in [program/web/](../program/web/) |
| `backend/Pdf.jl` | SDL-free vector-PDF export (`write_pdf`); hand-rolled TrueType embedding |
| `device/Screen.jl` | `Screen` device; `QuitEvent` |
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
  ├── backend/Sdl.jl        (depends on Graphics, Keyboard, Mouse, Screen, Image, ProjectionApi, IoMap)
  ├── backend/Web.jl        (depends on Graphics, Keyboard, Mouse, Screen, Sdl [text metrics], HTTP, JSON3)
  ├── backend/Pdf.jl        (depends on Graphics, Font, Image, ProjectionApi, IoMap — no SDL)
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
| Text → terminal (`ConsoleBackend`, ANSI colors, no `TextToGraphics`) | ✅ |
| Web rendering (browser canvas, dirty-rect patches) | ✅ |
| Offscreen BMP/PNG export (`write_image`) | ✅ |
| Vector PDF export, multi-page (`write_pdf`) | ✅ |

### Reader (reverse projection)

| Step | Status |
|---|---|
| Selection movement across all major pipelines | ✅ |
| `TextToGraphics` — `:left` / `:right` → `ReplaceSelectionOperation` | ✅ |
| `SyntaxLeafToText` — flat position → leaf-domain path | ✅ |
| `SyntaxNodeToText` — flat position → recursive child path | ✅ |
| `JsonToSyntax` — all node types | ✅ |
| `SequentialProjection`, `TypeDispatching`, `RecursiveProjection` | ✅ |
| Character editing (`StringReplaceRangeOperation`) | ⚠️ wired + tested (`test_typeins`) for field-addressed examples; not every domain |
| Mouse click-to-select | ⚠️ wired + tested (`test_mouse_clicks` / `test_click_roundtrips`); not every domain |
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
| Console (terminal) backend | `backend/Console.jl` | ✅ (Text domain, no Lisp counterpart) |
| Web backend (browser renderer) | `backend/Web.jl` | ✅ (new in Julia port) |
| PDF export backend | `backend/Pdf.jl` | ✅ |
| IO Maps | `IoMap.jl` + per-projection | ✅ |
| References | `Reference.jl` | ✅ |
| Navigation operations | `Operation.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `Editor.jl` | ✅ |
| All higher-order projections | `projection/higherorder/` | ✅ |
| Insert / delete operations | `Operation.jl` (`CollectionInsertOperation` / `CollectionDeleteOperation`) | ✅ (collections; produced by JSON/XML readers) |
| Undo / redo | — | ❌ |
