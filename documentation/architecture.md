# Architecture

This document covers the conceptual pipeline, the package layout, the module
inventory, and the projection pipeline status. The division vocabulary
(package / layer / slice / module) is defined in [terminology.md](terminology.md).
For design rationale see the
[design decisions guide](design-decisions.md). For the full reference/selection
mechanism see the [reference guide](../package/kernel/doc/reference.md) and
[selection guide](../package/kernel/doc/selection.md).

---

## Conceptual pipeline

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
                    │              (kernel layer 1 — `cell/`)             │
                    └─────────────────────────────────────────────────────┘
```

Four conceptual stages, bottom to top. (These stages span packages — they are
*not* layers in the [terminology.md](terminology.md) sense, which are ordered
strata *inside* a package; the packages and their internal layers/slices are
described in the next section.)

| Stage | Modules | Role |
|---|---|---|
| 0 — Reactive engine | kernel `cell/` | the `Cell` kinds, dependency tracking, lazy invalidation |
| 1 — Domain modules | `document/*.jl` | Document/operation types per problem area |
| 2 — Projection modules | `projection/**/*.jl` | Domain-to-domain transformations |
| 3 — Editor + backend | `editor/*.jl`, Console/Pdf backends, opt-in backend packages | REPL loop, rendering, device I/O |

---

## Package layout — the 4-package chain

ProjecturEd is organized as **four packages** with strictly layered
dependencies (`kernel ← base ← visual ← domain`). Each package's layer
ordering — no upward `..XxxModule` imports inside a declared layer — is
statically enforced by the shared
[layered-architecture guard](../package/kernel/test/layering/CheckLayering.jl),
applied per package by its test package (`test_kernel_layering()`, …).

Each main package is one third of a **triad** in one folder:
`package/<name>/{main, test, example}` — its code, its tests
(`ProjecturedKernelTest`, …), and its examples (`ProjecturedKernelExample`, …)
as three separate packages under the same directory. The three kinds form
parallel DAGs of identical shape, and every piece lives in the lowest package
of its DAG whose API it hard-references (seam calls don't count). See
[architecture-rules.md](architecture-rules.md#the-triad--every-main-package-has-its-code-its-tests-and-its-examples)
for the rules.

```
ProjecturedKernel (kernel/)    the engine — machinery + interfaces only
        ▲                      17 layers: cell → clock → event → device → gesture → backend →
        │                      document → reference → selection → operation → binding →
        │                      iomap → projection → tool → llm → agent → editor
        │                      Zero runtime deps, zero concrete documents.
ProjecturedBase (base/)        the domain-independent vocabulary & frameworks
        ▲                      3 layers: document (Collection, DocumentCore, Primitive,
        │                      Dragging) + projection (Sorting/Filtering/Searching/
        │                      Copying/ReaderDefaults/DraggingProjection) +
        │                      serialization (BinarySerialization).
        │                      Deps: kernel + Serialization stdlib.
ProjecturedVisual (visual/)    the rendering substrate
        ▲                      9 slices across 11 folders (acyclic DAG; include
        │                      order: style, screen, graphics, layout, text,
        │                      widget, syntax, interaction decorators
        │                      (clipboard + tooltip + inspector — one slice,
        │                      three folders), backend (Console, Pdf)).
        │                      Deps: kernel + base.
ProjecturedDomain (domain/)    concrete source domains, feature-sliced
        ▲                      20 slice folders (json/yaml/xml/julia/math/
        │                      markdown/book/sql/dbcatalog/database/graph/
        │                      filesystem/formula/gesturemap/versioning/
        │                      insertion/component/naturalformat + the
        │                      workbench/conversation apps). Flat — no layers.
        │                      Deps: kernel + base + visual + Base64 + Markdown.
Projectured (projectured/)     umbrella: `using Projectured` re-exports all four
                               as a single flat public API.

Opt-in packages (depend on the above; loaded only when you `using` them):
  Sdl  (sdl/)   → Domain  SDL2/SimpleDirectMediaLayer/FFMPEG  SdlBackend, write_image, record_video
  Web  (web/)   → Domain  HTTP/JSON3                          WebBackend; assets in web/assets/
  Video(video/) → Domain  FFMPEG                              record_video method on the kernel seam
  Odbc (odbc/)  → Domain  ODBC/DBInterface/Tables             OdbcDatabaseAdapter, make_database_adapter(:odbc), live-query projections
  Mcp  (mcp/)   → Kernel  ModelContextProtocol               McpServer, make_agent_server(:mcp)
  Llm  (llm/)   → Kernel  HTTP/JSON3                          stream_turn(::AnthropicLlm) — Anthropic Messages client
```

The four-level division rule: **package** = external dependency or consumer
boundary; **layer** = direction-of-dependency boundary inside a package
(layers depend only on lower layers); **slice** = vertical split of a single
layer by feature (slice→slice edges must stay acyclic); **module** =
namespace/import surface. Files sit below all four levels as readability
boundaries only: fragments (0-module files that share their aggregator's
namespace) let a module split across files with zero API cost. See
[terminology.md](terminology.md) for the definitions and
[architecture-rules.md](architecture-rules.md) for the durable division
rules.

Each source package also has a `doc/` directory with the per-layer / per-slice /
per-domain reference guides that used to live at the top level. The kernel set
([cell](../package/kernel/doc/cell.md),
[macros](../package/kernel/doc/macros.md),
[document](../package/kernel/doc/document.md),
[reference](../package/kernel/doc/reference.md),
[selection](../package/kernel/doc/selection.md),
[finding-and-selecting](../package/kernel/doc/finding-and-selecting.md),
[operation](../package/kernel/doc/operation.md),
[projection-system](../package/kernel/doc/projection-system.md),
[higher-order-projections](../package/kernel/doc/higher-order-projections.md),
[generic-projections](../package/kernel/doc/generic-projections.md),
[devices-and-backends](../package/kernel/doc/devices-and-backends.md),
[agent](../package/kernel/doc/agent.md),
[editor](../package/kernel/doc/editor.md),
[naming](../package/kernel/doc/naming.md)) is the largest; the per-domain guides
live in [visual/doc/](../package/visual/doc/), [domain/doc/](../package/domain/doc/),
and [base/doc/](../package/base/doc/). Each package's own `doc/architecture.md`
indexes its guides.

Optional engines plug into **factory seams** owned by the kernel
(`make_agent_server(kind, …)`) or the domain (`make_database_adapter(kind)`):
generic code requests one by symbol and the opt-in package registers the method
on load. Display backends use a lighter mechanism — no seam: name the type
directly (`SdlBackend()`) where the package is a dependency, or let
`ProjecturedBase.default_backend` pick a loaded `Backend` subtype by type-name
reflection where it isn't. So the SQL and DbCatalog *documents and projections* stay in
`ProjecturedDomain` (they need nothing external) — only **live ODBC
querying** lives in `Odbc`. Likewise each editor's *tool surface* is
kernel-resident (the `tool` layer's `ToolSet`), and the LLM/MCP seams are
kernel-resident too (the `llm` and `agent` layers); only the MCP transport and
the Anthropic HTTP client are in the opt-in `Mcp`/`Llm`.

> Per-file paths cited in the module inventory below sometimes reflect an
> older single-package layout; the code now lives across the four
> packages per the mapping above. A quick reference:
> — Collection.jl → base/main/document/Collection.jl
> — Primitive.jl → base/main/document/Primitive.jl
> — ScreenDocument.jl → visual/main/screen/ScreenDocument.jl
> — Widget.jl / Graphics.jl / Layout.jl / Text.jl / Syntax.jl / Color.jl / Font.jl → visual/main/<slice>/
> — Json.jl / Xml.jl / Sql.jl / Julia.jl / … → domain/main/<slice>/

---

## Module inventory

### Stage 0 — Reactive Cell Engine

**kernel layer 1 — `cell/`** (`CellModule`)

- `AbstractCell` and three kinds: `ReactiveCell` (tracks dependencies and
  invalidates lazily), `MutableCell` (a plain writable box), and `ImmutableCell`
  (a frozen value). `Cell` is the constructor that picks the kind. `@cell_struct`
  generates structs whose fields are transparently cell-backed.
- **Pull-based lazy evaluation:** computed cells evaluate only on read (`c[]`).
- **Automatic dependency tracking:** a per-task (task-local) `_computing` stack
  registers every cell read during a computation as an upstream dependency.
- **Invalidation:** writing a primitive cell (`c[] = v`) marks all transitive
  downstream dependents invalid; they recompute lazily on next read.
- **Performance counters:** `with_performance_counters()` binds a per-frame store and
  `get_performance_counters()` reads it — per-frame read/compute/write tallies, with no
  process-global state.

### Stage 1 — Domain modules (`document/`)

| Module | Types |
|---|---|
| kernel `reference/` | `Reference`, `EmptyReference`, `ConcreteReference` (`ReferencePath.jl`); the kernel step structs `RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep` (`ReferenceStep.jl`). `ElementReferenceStep`/`PositionReferenceStep` are convenience constructors producing a `RangeReferenceStep`, not distinct structs. Step types owned by higher packages each live with their owner and register through the layer's seam: `ProjectionReferenceStep` (kernel `projection/`), `PointReferenceStep` (visual `graphics/`), `TextRangeReferenceStep`/`TextColumnReferenceStep`/`TextSpanReferenceStep` (visual `text/`) |
| `Json.jl` | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`, `JsonObjectEntry` |
| `Xml.jl` | `XmlText`, `XmlAttribute`, `XmlElement` |
| `Text.jl` | `TextBlock`, `TextString`, `TextNewline` |
| `Syntax.jl` | `SyntaxLeaf`, `SyntaxNode`; wrapper types `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` |
| `Graphics.jl` | `GraphicsText`, `GraphicsRect`, `GraphicsCanvas`, `GraphicsViewport`, `GraphicsImage`, `GraphicsFence` |
| `Widget.jl` | Core: `WidgetInsertion`, `WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`, `WidgetMenuItem`, `WidgetComposite`, `WidgetToolbar`, `WidgetShell`, `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`, `WidgetScrollBar`. Extension: `WidgetBadge`, `WidgetSeparator`, `WidgetCard`, `WidgetSwitch`, `WidgetProgress`, `WidgetSlider`, `WidgetRadioGroup`, `WidgetAvatar`, `WidgetAlert`, `WidgetSkeleton`, `WidgetToggle`, `WidgetToggleGroup`, `WidgetSelect`, `WidgetTextarea`, `WidgetAccordion`, `WidgetTable`, `WidgetTree` |
| `Workbench.jl` | `WorkbenchWorkbench`, `WorkbenchPage`, `WorkbenchNavigator`, `WorkbenchConsole`, `WorkbenchDescriptor`, `WorkbenchOperator`, `WorkbenchSearcher`, `WorkbenchEvaluator`, `WorkbenchAssistant`, `WorkbenchEditor` |
| `Book.jl` | `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture` |
| `Math.jl` | `MathVariable`, `MathBinaryOperation`, `MathParenthesized`, `MathAssignment` |
| `Julia.jl` | `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOp`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock` |
| `Primitive.jl` | `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`; ops `ReplaceNumberRangeOperation`, `ReplaceStringRangeOperation` |
| `Table.jl` | `TableCell`, `TableRow`, `TableColumn`, `TableTable` |
| `FileSystem.jl` | `FileSystemFile`, `FileSystemDirectory` |
| `Collection.jl` | `CellVector`, `CellMatrix`, `CellTable`, `ListNode` |
| `Dragging.jl` | `DraggingState` — transparent wrapper marking a sub-tree as drag-and-drop reorderable (paired with `DraggingProjection`) |
| `Font.jl`, `Color.jl`, `Geometry.jl`, `Image.jl`, `Clipboard.jl` | Supporting types |

### Stage 2 — Projection modules (`projection/`)

Every projection below — primitive, generic, or higher-order — implements the same
four-function interface (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) and recurses into children
**only** by delegating to the child projection's own version of those four. No
projection adds a fifth recursive function; that is [the recursion
contract](../package/kernel/doc/projection-system.md#the-recursion-contract) and the reason any domain
composes with any higher-order projection.

**Higher-order** (`higherorder/`):

| Struct | Role |
|---|---|
| `ChainingProjection` | Chains projections left-to-right; reader chains right-to-left |
| `TypeDispatchingProjection` | Dispatches on `typeof(input)` |
| `RecursiveProjection` | Passes itself as `recursion` for self-referential trees |
| `SwitchingProjection` | Tries each sub-projection; uses the first that succeeds |
| `PredicateDispatchingProjection` | Dispatches on a boolean predicate over the input |
| `ReferenceDispatchingProjection` | Dispatches on the current selection reference |
| `NestingProjection` | Scopes an inner projection to a sub-document |
| `WindowManagingProjection` | Passthrough printer; reader applies window open/close ops to the `ScreenDocument` |
| `WindowInputUnwrappingProjection` | Passthrough printer; reader strips the `WindowInput` off the gesture — the window-input-unwrap seam for pipelines with no screen/window layer (e.g. the `ConsoleBackend`'s) |
| `TooltipDecoratorProjection` | Dispatches on `TooltipSource`; reader runs a show/hide state machine |
| `DraggingProjection` | Dispatches on `DraggingState`; reader runs a press→drag→drop state machine emitting `MoveRangeOperation` |
| `ProjectionConfiguringProjection` | Extends the inner projection's output with an editable parameter-control bar |

**Generic** (`generic/`):

| Struct | Role |
|---|---|
| `IdentityProjection` | Identity (output = input) |
| `ConstantProjection` | Returns a fixed output regardless of input |
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
| `GraphicsCaching` | `Graphics` → `Graphics` (caching projection) |
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

### Stage 3 — Editor and backend

| Module | Role |
|---|---|
| `Editor.jl` | REPL loop: read → eval → print; `run_editor!(backend, projection, document)` entry point |
| `Sdl.jl` (opt-in `package/sdl/`) | SDL2 + SDL_ttf backend: graphics rendering, event translation, `write_image` |
| `backend/Console.jl` | Terminal backend: renders the **Text** domain (a `TextBlock`) to the terminal with ANSI colors and reads keystrokes — no `TextToGraphics`/SDL ([devices and backends](../package/kernel/doc/devices-and-backends.md#consolebackend)) |
| `Web.jl` (opt-in `package/web/`) | Web backend: HTTP + WebSocket server, JSON draw-list (with dirty-rect patches), browser renderer in [package/web/assets/](../package/web/assets/) |
| `backend/Pdf.jl` (visual) | SDL-free vector-PDF export (`write_pdf`); hand-rolled TrueType embedding |
| `device/Display.jl` | `Display` device |
| `event/KeyboardEvent.jl` | `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord` |
| `event/MouseEvent.jl` | `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseEnter`, `MouseLeave`, `MouseScroll` |
| `event/WindowEvent.jl` | `WindowQuit`, `WindowClose`, `WindowResize`, `WindowDefocus` |
| `agent/AgentServer.jl` (kernel) | The MCP *seam* — `make_agent_server(:mcp, …)`. The transport (JSON-RPC over HTTP, exposing documents and operations) is the opt-in `package/mcp/` |

---

## Module dependency graph

Dependencies flow one way at every level: package → layer → slice. Each edge below
points from a thing to the things it may import; nothing imports upward. The layer
order inside each package is what the static guard (`test_kernel_layering()`, …)
enforces.

**Between packages:**

```
ProjecturedKernel ◄── ProjecturedBase ◄── ProjecturedVisual ◄── ProjecturedDomain ◄── Projectured
       ▲                                                                ▲            (umbrella)
       │                                                                │
   Mcp, Llm                                              Sdl, Web, Video, Odbc
   (opt-in)                                                        (opt-in)
```

**Inside ProjecturedKernel — 17 layers**, in include order; each imports only layers
above it in this list:

```
 1 cell        AbstractCell + the ReactiveCell / MutableCell / ImmutableCell kinds,
               @cell_struct, the per-frame performance counters
 2 clock       the animation Clock (a @cell_struct with a reactive time field),
               get_clock_time / set_clock_time!, the get_wall_clock singleton
 3 event       the input event vocabulary (Event/DeviceEvent/SyntheticEvent, ModifierKeys,
               KeyDown/KeyPress/Mouse*/Window*, WindowInput), the event pattern
               language (EventPattern, matches, describe, @event_case)
 4 device      Device abstract + Keyboard / Mouse / Display devices (physical properties)
 5 gesture     event → gesture recognition (MousePress / KeyChord synthesis)
 6 backend     the Backend seam (lifecycle, text, device I/O, display size, device
               config, image/video output)
 7 document    the Document supertype, @document, the is_element_collection /
               is_walk_opaque traits, search_documents
 8 reference   ReferenceStep / Reference and the step seam, evaluate_reference,
               search_references, the @reference / @reference_case DSLs
 9 selection   get_selection / set_selection! / clear_selection! / with_selection
10 operation   the Operation supertype, evaluate_operation, the reroot_operation seam
11 binding     GestureBinding, the per-document-type registry, @gestures /
               @gesture_set, read_gesture / read_bound_gesture
12 iomap       the IoMap contract (IoMap + accessors) and the concrete IO maps
               (SimpleIoMap, ChildrenIoMap, ContentIoMap, @iomap)
13 projection  the four interface functions, Intent, @projection,
               ProjectionTemplate, ProjectionReferenceStep
14 tool        the editor's capability surface: Tool / Resource / ToolSet,
               execute_julia_code, doc/API search, register_default_tools!
15 llm         the LLM provider abstraction: Llm, stream_turn, tool_schema,
               LlmMessage / LlmRequest, LlmEvent
16 agent       the AI control surface: AgentServerModule (inbound, the MCP
               seam) and AgentModule (outbound, the Agent and run_turn! loop)
17 editor      run_editor!, the read-eval-print loop, Playback
```

**Inside ProjecturedBase — 3 layers** (plus a `backend/DefaultBackend.jl` preamble
that picks a loaded `Backend` subtype by reflection):

```
 1 document       Collection (CellVector, …), Primitive, DocumentCore, Dragging
 2 projection     the domain-independent algebra — generic (Identity, Reversing,
                  Constant, Focusing) + higher-order (Chaining, TypeDispatching,
                  Recursive, Switching, PredicateDispatching, ReferenceDispatching,
                  Nesting, WindowInputUnwrapping) + Sorting / Filtering / Searching /
                  Copying / ReaderDefaults / DraggingProjection
 3 serialization  BinarySerialization
```

**Inside ProjecturedVisual — 9 slices** across 11 folders, an acyclic DAG in include
order:

```
 1 style     Color, Font, TrueType, Geometry, Image, strokes and text styles
 2 screen    ScreenDocument, WindowManaging
 3 graphics  Graphics, GraphicsCaching, PointReferenceStep
 4 layout    Layout, the constraint solver, CollectionToLayout
 5 text      Text, TextToGraphics, word-wrapping, line-numbering, filtering,
             highlighting, TextRange/Column/SpanReference, ReferenceToText
 6 widget    Widget, WidgetToGraphics, ObjectToWidget, ProjectionConfiguring
 7 syntax    Syntax, SyntaxToText, ObjectToSyntax, CollectionToSyntax,
             PrimitiveToSyntax
 8 interaction decorators   clipboard + tooltip + inspector (one slice, three folders)
 9 backend   the dependency-free concrete backends: Console, Pdf
```

**Inside ProjecturedDomain — 20 slice folders**, flat (no layers): json, yaml, xml,
julia, math, markdown, book, sql, dbcatalog, database, graph, filesystem, formula,
gesturemap, versioning, insertion, component, naturalformat, plus the workbench and
conversation apps. Each slice holds its documents, its parser, and its projections;
slice→slice edges stay acyclic.

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
| Selection movement across all major pipelines | ⚠️ rightwards ✅; leftwards stalls on projection-introduced text in every syntax-backed pipeline (`test_text_nav_invariants_all`, `plan/pending/left-motion-stalls-on-introduced-text.md`) |
| `TextToGraphics` — `:left` / `:right` → `ReplaceSelectionOperation` | ✅ |
| `SyntaxLeafToText` — flat position → leaf-domain path | ✅ |
| `SyntaxCompoundToText` — flat position → recursive child path | ✅ |
| `JsonToSyntax` — all node types | ✅ |
| `ChainingProjection`, `TypeDispatching`, `RecursiveProjection` | ✅ |
| Character editing (`ReplaceStringRangeOperation`) | ⚠️ wired + tested (`test_typeins`) for field-addressed examples; not every domain |
| Mouse click-to-select | ⚠️ wired + tested (`test_mouse_clicks` / `test_click_roundtrips`); not every domain |
| Undo / redo | ❌ |

---

## Mapping to the original ProjecturEd

| Lisp ProjecturEd | Julia ProjecturEd | Status |
|---|---|---|
| `computed-class` (change propagation) | `CellModule` (`ReactiveCell`) | ✅ |
| JSON domain | `Json.jl` | ✅ |
| Tree domain | `Syntax.jl` | ✅ |
| Styled string domain | `Text.jl` | ✅ |
| Graphics domain | `Graphics.jl` | ✅ |
| SDL backend | `backend/Sdl.jl` | ✅ |
| Console (terminal) backend | `backend/Console.jl` | ✅ (Text domain, no Lisp counterpart) |
| Web backend (browser renderer) | `backend/Web.jl` | ✅ (new in Julia port) |
| PDF export backend | `backend/Pdf.jl` | ✅ |
| IO Maps | `IoMap.jl` + per-projection | ✅ |
| References | `reference/` (layer 8) | ✅ |
| Navigation operations | `Operation.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `Editor.jl` | ✅ |
| All higher-order projections | `projection/higherorder/` | ✅ |
| Insert / delete operations | `Operation.jl` (`insert_elements` / `delete_elements` → a `ReplaceReferencedValueOperation` splice) | ✅ (collections; produced by JSON/XML readers) |
| Undo / redo | — | ❌ |
