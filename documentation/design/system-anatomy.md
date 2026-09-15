# Architecture

> **Kind:** design · **Status:** current · **Stands on:** [division-terminology.md](../rule/division-terminology.md), [editor-concepts.md](editor-concepts.md)

This document covers the conceptual pipeline, the package layout, the module
inventory, and the projection pipeline status. The division vocabulary
(package / layer / slice / module) is defined in [terminology.md](../rule/division-terminology.md).
For design rationale see the
[design decisions guide](architecture-decisions.md). For the full reference/selection
mechanism see the [reference guide](../package/kernel/reference.md) and
[selection guide](../package/kernel/selection.md).

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
*not* layers in the [terminology.md](../rule/division-terminology.md) sense, which are ordered
strata *inside* a package; the packages and their internal layers/slices are
described in the next section.)

| Stage | Modules | Role |
|---|---|---|
| 0 — Reactive engine | kernel `cell/` | the `Cell` kinds, dependency tracking, lazy invalidation |
| 1 — Domain modules | `document/*.jl` | Document/operation types per problem area |
| 2 — Projection modules | `projection/**/*.jl` | Domain-to-domain transformations |
| 3 — Editor + backend | `editor/*.jl`, Console/Pdf backends, opt-in backend packages | REPL loop, rendering, device I/O |

---

## Package layout — the package graph

The **kinds** of package (main, example, test, repl, build), what each may
depend on, and why the leaf the alias loads is the only place a
`@compile_workload` may live, are in [packages.md](../rule/package-rules.md).

ProjecturEd is organized as **one engine, twenty-eight substrate packages and
twenty domain packages**, plus an umbrella and the opt-in packages. The kernel
is the one *layered* package: its seventeen layers depend only downward, and
the ordering is enforced statically by the shared
[layered-architecture guard](../../test/kernel/layering/CheckLayering.jl).
Every other package is **one concept**, so it declares no layer index; the
guard checks its include order and its file inventory alone.

Each main package is one third of a **triad** in one folder:
`package/<name>/{main, test, example}` — its code, its tests and its examples
as separate packages under the same directory. The substrate shares one
example package and one test package
(`ProjecturedSubstrateExample`, `ProjecturedSubstrateTest`), because the files
of both were written against the flat namespace. See
[architecture-rules.md](../rule/architecture-rules.md#the-triad--every-main-package-has-its-code-its-tests-and-its-examples)
for the rules.

```
ProjecturedKernel (kernel/)    the engine — machinery + interfaces only
        ▲                      17 layers: cell → clock → event → device → gesture → backend →
        │                      document → reference → selection → operation → binding →
        │                      iomap → projection → tool → llm → agent → editor
        │                      Zero runtime deps, zero concrete documents.
The substrate: 28 packages     one concept each, an acyclic package graph
        ▲                      the vocabulary — collection, primitive, domain,
        │                      serialization;
        │                      the algebra — projection, reflection, dragging,
        │                      versioning;
        │                      the rendering — style, component, focus, plot,
        │                      graphics, screen, layout, text, widget, syntax,
        │                      pane;
        │                      the features — clipboard, tooltip, inspector,
        │                      gesturehelp, gesturelog, fileformat,
        │                      naturalprojection;
        │                      the two dependency-free backends — console, pdf.
        │                      Each declares the exact set it imports; the table
        │                      is in [packages.md](../rule/package-rules.md).
The twenty domain packages     one package per concrete source domain
        ▲                      json/ yaml/ xml/ markdown/ rst/ book/ math/ julia/
        │                      sql/ database/ filesystem/ graph/ chart/
        │                      sequencechart/ dbcatalog/ formula/ fsm/ process/
        │                      conversation/ workbench/. Each holds its
        │                      documents, its parser and its projections.
        │                      Deps: the kernel, the substrate packages it uses,
        │                      and the domains it embeds. See
        │                      [domains.md](domain-inventory.md).
Projectured (projectured/)     umbrella: `using Projectured` re-exports every
                               package above as a single flat public API.

Opt-in packages (depend on the above; loaded only when you `using` them):
  Sdl  (sdl/)   → Collection, Graphics, Screen, Style  SDL2/SimpleDirectMediaLayer  SdlBackend, write_image
  Web  (web/)   → Collection, Graphics, Screen, Style  HTTP/JSON3                   WebBackend; assets in web/assets/
  Video(video/) → Graphics, Sdl                        FFMPEG                       record_video method on the kernel seam
  Tulip(tulip/) → Layout                               MathOptInterface/Tulip       the linear-programming constraint solver
  Odbc (odbc/)  → Sql, DbCatalog, Database             ODBC/DBInterface/Tables      OdbcDatabaseAdapter, live-query projections
  Adaptagrams   → Graph                                native C++ shim              the graph layout engine
  Mcp  (mcp/)   → Kernel                               ModelContextProtocol         McpServer, make_agent_server(:mcp)
  Anthropic     → Kernel                               HTTP/JSON3                   AnthropicLlm; make_llm(:anthropic)
  Ollama        → Kernel                               HTTP/JSON3                   OllamaLlm; make_llm(:ollama)
```

The four-level division rule: **package** = one concept, or an
external dependency boundary; **layer** = direction-of-dependency boundary
inside a package, which the kernel alone declares; **slice** = vertical split
of a single layer by feature, which is now a kernel-only notion; **module** =
namespace/import surface. Files sit below all four levels as readability
boundaries only: fragments (0-module files that share their aggregator's
namespace) let a module split across files with zero API cost.

**A module is declared in the file that names it.** `JsonModule` lives in
`JsonModule.jl` and `CellModule` in `CellModule.jl`, without exception, and
`module_violations` in [test/suite/naming.jl](../../test/suite/naming.jl)
reports any file that breaks it. A module with several fragments keeps that file
for the head alone — the docstring, the header, the ordered includes and
`__init__`. A module with one fragment keeps its code there, because a head
listing one include gives a reader nothing. All 15 head files of the kernel
carry two or more includes.

See [terminology.md](../rule/division-terminology.md) for the definitions and
[architecture-rules.md](../rule/architecture-rules.md) for the durable division
rules.

Each source package also has a `doc/` directory with the per-layer / per-slice /
per-domain reference guides that used to live at the top level. The kernel set
([cell](../package/kernel/cell.md),
[macros](../package/kernel/macros.md),
[document](../package/kernel/document.md),
[reference](../package/kernel/reference.md),
[selection](../package/kernel/selection.md),
[finding-and-selecting](../package/kernel/finding-and-selecting.md),
[operation](../package/kernel/operation.md),
[projection-system](../package/kernel/projection-system.md),
[higher-order-projections](../package/kernel/higher-order-projections.md),
[generic-projections](../package/kernel/generic-projections.md),
[devices-and-backends](../package/kernel/devices-and-backends.md),
[agent](../package/kernel/agent.md),
[editor](../package/kernel/editor.md),
[naming](../rule/naming-rules.md)) is the largest; the per-domain guides
live next to the code, in the `doc/` folder of the package they document —
[widget](../package/widget/widget.md), [text](../package/text/text.md),
[collection](../package/collection/collection.md) and the rest.

Optional engines plug into **factory seams** owned by the kernel
(`make_agent_server(kind, …)`) or the domain (`make_database_adapter(kind)`):
generic code requests one by symbol and the opt-in package registers the method
on load. Display backends use a lighter mechanism — no seam: name the type
directly (`SdlBackend()`) where the package is a dependency, or let
`ProjecturedExample.default_backend` pick a loaded `Backend` subtype by
type-name reflection where it isn't. So the SQL and DbCatalog *documents and projections* stay in
`ProjecturedSql` and `ProjecturedDbCatalog` (they need nothing external) — only
**live ODBC querying** lives in `Odbc`. Likewise each editor's *tool surface* is
kernel-resident (the `tool` layer's `ToolSet`), and the LLM/MCP seams are
kernel-resident too (the `llm` and `agent` layers); only the MCP transport and
the Anthropic HTTP client are in the opt-in `Mcp`/`Llm`.

> The inventory below cites a file by name. Every one of them lives in
> `source/<slice>/`, one folder per slice, and the package that includes it is
> `Projectured<Slice>`. A slice's document file is `<Slice>Document.jl`, so the
> JSON documents are in `source/json/JsonDocument.jl` and the package is
> `ProjecturedJson`. [naming-rules.md](../rule/naming-rules.md) states the
> derivation and `test/suite/naming.jl` checks it.

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
| `JsonDocument.jl` | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`, `JsonObjectEntry` |
| `XmlDocument.jl` | `XmlText`, `XmlAttribute`, `XmlElement` |
| `TextDocument.jl` | `TextBlock`, `TextString`, `TextNewline` |
| `SyntaxDocument.jl` | `SyntaxLeaf`, `SyntaxNode`; wrapper types `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` |
| `GraphicsDocument.jl` | `GraphicsText`, `GraphicsRect`, `GraphicsCanvas`, `GraphicsViewport`, `GraphicsImage`, `GraphicsFence` |
| `WidgetDocument.jl` | Core: `WidgetInsertion`, `WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`, `WidgetMenuItem`, `WidgetComposite`, `WidgetToolbar`, `WidgetShell`, `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`, `WidgetScrollBar`. Extension: `WidgetBadge`, `WidgetSeparator`, `WidgetCard`, `WidgetSwitch`, `WidgetProgress`, `WidgetSlider`, `WidgetRadioGroup`, `WidgetAvatar`, `WidgetAlert`, `WidgetSkeleton`, `WidgetToggle`, `WidgetToggleGroup`, `WidgetSelect`, `WidgetTextarea`, `WidgetAccordion`, `WidgetTable`, `WidgetTree` |
| `WorkbenchDocument.jl` | `WorkbenchWorkbench`, `WorkbenchPage`, `WorkbenchNavigator`, `WorkbenchConsole`, `WorkbenchDescriptor`, `WorkbenchOperator`, `WorkbenchSearcher`, `WorkbenchEvaluator`, `WorkbenchAssistant`, `WorkbenchEditor` |
| `BookDocument.jl` | `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture` |
| `MathDocument.jl` | `MathVariable`, `MathBinaryOperation`, `MathParenthesized`, `MathAssignment` |
| `JuliaDocument.jl` | `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOperation`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock` |
| `ProcessDocument.jl` | `ProcessModel`, `ProcessSequence`, `ProcessStep`, `ProcessDecision`, `ProcessWhile`, `ProcessForeach`, `ProcessBreak`, `ProcessContinue`, `ProcessReturn`; presentation `ProcessDiagram`, `ProcessTerminal`, `ProcessEdgeLabel`, `ProcessDebugSession` |
| `PrimitiveDocument.jl` | `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`; ops `ReplaceNumberRangeOperation`, `ReplaceStringRangeOperation` |
| `ObjectField.jl` | `ObjectField` — one field of one object: a root object and a `Reference` to a value |
| `FileSystemDocument.jl` | `FileSystemFile`, `FileSystemDirectory` |
| `CollectionDocument.jl` | `CellVector`, `CellMatrix`, `CellTable`, `ListNode` |
| `Dragging.jl` | `DraggingState` — transparent wrapper marking a sub-tree as drag-and-drop reorderable (paired with `DraggingProjection`) |
| `Font.jl`, `Color.jl`, `Geometry.jl`, `Image.jl`, `ClipboardDocument.jl` | Supporting types |

### Stage 2 — Projection modules (`projection/`)

Every projection below — primitive, generic, or higher-order — implements the same
four-function interface (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) and recurses into children
**only** by delegating to the child projection's own version of those four. No
projection adds a fifth recursive function; that is [the recursion
contract](../package/kernel/projection-system.md#the-recursion-contract) and the reason any domain
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
| `ObjectFieldToWidget` | One `ObjectField` → the bare control that edits it; the author lays the labels out |

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
| `ObjectFieldToSyntax` | One `ObjectField` → a name leaf beside the projected value |
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
| `backend/Console.jl` | Terminal backend: renders the **Text** domain (a `TextBlock`) to the terminal with ANSI colors and reads keystrokes — no `TextToGraphics`/SDL ([devices and backends](../package/kernel/devices-and-backends.md#consolebackend)) |
| `Web.jl` (opt-in `package/web/`) | Web backend: HTTP + WebSocket server, JSON draw-list (with dirty-rect patches), browser renderer in [package/web/assets/](../../asset/web) |
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
ProjecturedKernel ◄── the 28 substrate packages ◄── the 20 domains ◄── Projectured
       ▲                          ▲                        ▲            (umbrella)
       │                          │                        │
   Mcp, Llm             Sdl, Web, Video, Tulip      Odbc, Adaptagrams
   (opt-in)                    (opt-in)                 (opt-in)
```

The substrate packages form their own DAG, and so do the twenty domains.
[packages.md](../rule/package-rules.md) has the substrate table; [domains.md](domain-inventory.md)
has the domain table.

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
               search_references, the @reference / @reference_case /
               @reference_rules DSLs
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
15 llm         the LLM provider abstraction: Llm, stream_turn, render_tool_schema,
               LlmMessage / LlmRequest, LlmEvent
16 agent       the AI control surface: AgentServerModule (inbound, the MCP
               seam) and AgentModule (outbound, the Agent and run_turn! loop)
17 editor      run_editor!, the read-eval-print loop, Playback
```

**The twenty-eight substrate packages**, in a topological order. Each is one
concept, and each declares the exact set of packages it imports:

```
   collection      CellVector, CellMatrix, CellTable, ListNode
   primitive       PrimitiveBool / Number / String / Insertion and their range operations, ObjectField
   domain          DocumentCore, the @domain macro, insertion completion
   serialization   BinarySerialization, FileProject, TextFile
   style           Color, Font, TrueType, Geometry, Image, strokes and text styles
   component       a named, reusable widget composition
   projection      the domain-free algebra: the generic and higher-order combinators,
                   the compound aggregates, Searching, Copying, Sorting, Filtering,
                   ReaderDefaults
   reflection      BoundedSync and DocumentReflection
   dragging        DraggingState and its press-drag-drop reader
   focus           the generic focus walk and the is_focusable_document trait
   versioning      VersionedObject and its version-eliminating projection
   plot            the plot arithmetic and the colour and marker vocabulary
   graphics        Graphics, GraphicsCaching, PointReferenceStep
   screen          ScreenDocument, WindowManaging, ScreenToScreen
   layout          Layout, the constraint solver, LayoutToGraphics, CollectionToLayout
   text            Text, TextToGraphics, the decorators, the three reference steps,
                   PrimitiveToText, ReferenceToText
   widget          Widget, WidgetToGraphics, ObjectToWidget, the decorators
   syntax          Syntax, SyntaxToText, the three bridges, InsertionToSyntax
   pane            the tab and split layout and its widget projection
   clipboard       copy, cut and paste over any wrapped content
   tooltip         the TooltipSource wrapper and its decorator
   inspector       the reference inspector and the hover probe
   gesturehelp     the gesture map, the command palette and their two decorators
   gesturelog      the log document, its printer, its recorder and its overlay
   fileformat      NaturalFormat, DocumentFile
   naturalprojection  NaturalRegistry and NaturalProjection: render anything
   console         the ANSI terminal backend
   pdf             the vector PDF backend
```

**The twenty domain packages** — one package per concrete source domain, each
holding one slice: its documents, its parser and its projections. Fourteen need
only the engine packages; five build on one layer of domains; the workbench
application sits on top. [domains.md](domain-inventory.md) has the table and the rules
for adding one.

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
| Selection movement across all major pipelines | ⚠️ rightwards ✅; leftwards stalls on projection-introduced text in every syntax-backed pipeline (`test_text_navigation_invariants_all`, `plan/pending/left-motion-stalls-on-introduced-text.md`) |
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
| JSON domain | `JsonDocument.jl` | ✅ |
| Tree domain | `SyntaxDocument.jl` | ✅ |
| Styled string domain | `TextDocument.jl` | ✅ |
| Graphics domain | `GraphicsDocument.jl` | ✅ |
| SDL backend | `backend/Sdl.jl` | ✅ |
| Console (terminal) backend | `backend/Console.jl` | ✅ (Text domain, no Lisp counterpart) |
| Web backend (browser renderer) | `backend/Web.jl` | ✅ (new in Julia port) |
| PDF export backend | `backend/Pdf.jl` | ✅ |
| IO Maps | `IoMapDefaults.jl` + per-projection | ✅ |
| References | `reference/` (layer 8) | ✅ |
| Navigation operations | `Operations.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `Editor.jl` | ✅ |
| All higher-order projections | `projection/higherorder/` | ✅ |
| Insert / delete operations | `Operations.jl` (`insert_elements` / `delete_elements` → a `ReplaceReferencedValueOperation` splice) | ✅ (collections; produced by JSON/XML readers) |
| Undo / redo | — | ❌ |
