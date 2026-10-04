# Architecture

> **Kind:** design · **Status:** current · **Stands on:** [division-terminology.md](../rule/division-terminology.md), [concepts.md](concepts.md)

This document covers the conceptual pipeline, the package layout, the module
inventory, and the projection pipeline status. The division vocabulary
(package / layer / slice / module) is defined in [division-terminology.md](../rule/division-terminology.md).
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
                    │              (kernel layer 3 — `cell/`)             │
                    └─────────────────────────────────────────────────────┘
```

Four conceptual stages, bottom to top. These stages span packages. They are
*not* layers in the [division-terminology.md](../rule/division-terminology.md) sense, which are ordered
strata *inside* a package. The packages and their internal layers/slices are
described in the next section.

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
`@compile_workload` may live, are in [package-rules.md](../rule/package-rules.md).

ProjecturEd is organized as **one kernel, one platform package of
thirty-nine slices, seventeen domain packages, five backends and eight
adapters**, plus the umbrella `Projectured`, `AutoIntegration`,
`ProjecturedIntegrations`, the released package `ProjecturedAll` and the
tools. The kernel
is the one *layered* package: its twenty-three layers depend only downward,
and the ordering is enforced statically by the shared
[layered-architecture guard](../../test/kernel/layering/CheckLayering.jl).
Each layer holds exactly one module, so the root's include list is the layer
diagram itself: one line per layer, bottom to top, and a module's own file
carries its fragment include list.
Every other package is **one concept**, so it declares no layer index; the
guard checks its include order and its file inventory alone. The platform
declares no layer either: its thirty-nine slices form an acyclic graph of
their own, which the same guard checks.

Each main package is one third of a **triad**: `package/Projected<Name>`,
`package/Projected<Name>Test` and `package/Projected<Name>Example`, three
sibling packages, each with its own `Project.toml`. The platform shares one
example package and one test package
(`ProjecturedPlatformExample`, `ProjecturedPlatformTest`), because the files
of both were written against the flat namespace. See
[architecture-rules.md](../rule/architecture-rules.md#the-triad-every-main-package-has-its-code-its-tests-and-its-examples)
for the rules.

```
ProjecturedKernel (kernel/)    the engine — machinery + interfaces only
        ▲                      23 layers: fault → performance → cell → struct → clock → event →
        │                      device → gesture → backend → document → reference →
        │                      selection → operation → intent → binding → iomap →
        │                      projection → tool → llm → agent → feed → editor → playback
        │                      Zero runtime deps, zero concrete documents.
ProjecturedPlatform (platform/) one package, 39 slices, below every domain
        ▲                      one concept each, an acyclic slice graph
        │                      the vocabulary — collection, primitive, domain,
        │                      serialization;
        │                      the algebra — projection, reflection, dragging,
        │                      versioning;
        │                      the rendering — style, component, focus, plot,
        │                      graphics, screen, layout, text, widget, syntax,
        │                      pane;
        │                      the features — clipboard, tooltip, inspector,
        │                      gesturehelp, gesturelog, fault, fileformat,
        │                      natural, filesystem, display, gesturetracking,
        │                      dragtracking, essentials;
        │                      the application — undo, log, statistics, shell,
        │                      help, conversation, assistant, application.
        │                      Each slice declares the exact set it imports; the table
        │                      is in [package-rules.md](../rule/package-rules.md).
The seventeen domain packages  one package per concrete source domain
        ▲                      json/ yaml/ xml/ markdown/ rst/ book/ math/ julia/
        │                      sql/ database/ graph/ chart/
        │                      sequencechart/ dbcatalog/ formula/ fsm/ process/.
        │                      Each holds its
        │                      documents, its parser and its projections.
        │                      Deps: the kernel, the platform,
        │                      and the domains it embeds. See
        │                      [domain-inventory.md](domain-inventory.md).
Projectured (projectured/)     umbrella: depends on the platform and on
                               AutoIntegration, and re-exports the twelve
                               names of the platform's essentials slice
                               (`ProjecturedPlatform.EssentialsModule`).
AutoIntegration               loads an installed package when the packages it
                               names as triggers are loaded and its state is
                               "auto" — a domain, Console, Pdf, a model adapter
                               or an integration (SDL, Video, DataFrames, ODBC,
                               Tulip, MCP). Depends on the TOML standard
                               library alone, names no ProjecturEd package,
                               and lives in its own repository,
                               projectured/AutoIntegration.jl, beside this one.
ProjecturedIntegrations        depends on Projectured and the six packages that
                               own a third-party dependency, and loads each one
                               with a package extension when the package it
                               joins is loaded.
ProjecturedAll (all/)          re-exports the kernel, the platform, Console,
                               Pdf and the 17 domains as one flat namespace for
                               the tests, the examples and the REPL.

The five backends (depend on the kernel and the platform):
  Console (console/) → required, no third-party dependency   the ANSI terminal backend
  Pdf     (pdf/)      → required, no third-party dependency   SDL-free vector-PDF export
  Sdl     (sdl/)       → opt-in, SDL2/SimpleDirectMediaLayer   SdlBackend, write_image
  Web     (web/)       → opt-in, HTTP/JSON3                    WebBackend; assets in web/assets/
  Video   (video/)     → opt-in, FFMPEG; depends on Sdl         record_video method on the kernel seam

The eight adapters (opt-in, loaded only when you `using` them):
  Tulip      (tulip/) → Platform's layout slice      MathOptInterface/Tulip       the linear-programming constraint solver
  Odbc       (odbc/)  → Sql, DbCatalog, Database      ODBC/DBInterface/Tables      OdbcDatabaseAdapter, live-query projections
  Adaptagrams          → Graph                        native C++ shim              the graph layout engine
  Mcp        (mcp/)   → Kernel                        ModelContextProtocol         McpServer, make_agent_server(:mcp)
  Anthropic            → Kernel                       HTTP/JSON3                   AnthropicLlm; make_llm(:anthropic)
  Ollama               → Kernel                       HTTP/JSON3                   OllamaLlm; make_llm(:ollama)
  OpenRouter           → Kernel                       HTTP/JSON3                   the relevance model on the Decisions API
  DataFrames           → Kernel, Platform; DataFrames.jl                           DataFrameView
```

The four-level division rule: **package** = one concept, or an
external dependency boundary; **layer** = direction-of-dependency boundary
inside a package, which the kernel alone declares; **slice** = vertical split
of a layer, or of a package with no layer of its own — the kernel's layers,
and the thirty-nine feature folders of the platform, are both slices;
**module** = namespace/import surface. Files sit below all four levels as
readability boundaries only: fragments (0-module files that share their
aggregator's namespace) let a module split across files with zero API cost.

**A module is declared in the file that names it.** `JsonModule` lives in
`JsonModule.jl` and `CellModule` in `CellModule.jl`, without exception, and
`module_violations` in [test/suite/naming.jl](../../test/suite/naming.jl)
reports any file that breaks it. A module file holds the head alone — the
docstring, the header, the ordered includes and `__init__` — whatever the count of
its fragments.

See [division-terminology.md](../rule/division-terminology.md) for the definitions and
[architecture-rules.md](../rule/architecture-rules.md) for the durable division
rules.

Each slice's reference guides live under `documentation/package/<group>/<slice>/`, one
folder per slice. The kernel set
([cell](../package/kernel/cell.md),
[macros](../package/kernel/macros.md),
[document](../package/kernel/document.md),
[reference](../package/kernel/reference.md),
[selection](../package/kernel/selection.md),
[finding-and-selecting](../package/kernel/finding-and-selecting.md),
[operation](../package/kernel/operation.md),
[projection-system](../package/kernel/projection-system.md),
[higher-order-projections](../package/platform/projection/higher-order-projections.md),
[generic-projections](../package/platform/projection/generic-projections.md),
[devices-and-backends](../package/kernel/devices-and-backends.md),
[agent](../package/kernel/agent.md),
[editor](../package/kernel/editor.md),
[naming](../rule/naming-rules.md)) is the largest; the per-slice guides sit
next to it, one folder per slice —
[widget](../package/platform/widget/widget.md), [text](../package/platform/text/text.md),
[collection](../package/platform/collection/collection.md) and the rest.

Optional engines plug into **factory seams** owned by the kernel
(`make_agent_server(kind, …)`) or the domain (`make_database_adapter(kind)`):
generic code requests one by symbol and the opt-in package registers the method
on load. Display backends use a lighter mechanism — no seam: name the type
directly (`SdlBackend()`) where the package is a dependency, or let
[`default_backend`](../package/platform/application/application.md) pick a
loaded `Backend` subtype by type-name reflection where it isn't. So the SQL and DbCatalog *documents and projections* stay in
`ProjecturedSQL` and `ProjecturedDBCatalog` (they need nothing external) — only
**live ODBC querying** lives in `Odbc`. Likewise each editor's *tool surface* is
kernel-resident (the `tool` layer's `ToolSet`), and the LLM/MCP seams are
kernel-resident too (the `llm` and `agent` layers); only the MCP transport and
the HTTP clients of the model providers are in the opt-in `ProjecturedMCP`,
`ProjecturedAnthropic` and `ProjecturedOllama`.

> The inventory below cites a file by name. Every one of them lives in
> `source/<group>/<slice>/`, one folder per slice in the folder of its group, and the package that includes it is
> `Projectured<Slice>`. A slice's document file is `<Slice>Document.jl`, so the
> JSON documents are in `source/domain/json/JsonDocument.jl` and the package is
> `ProjecturedJSON`. [naming-rules.md](../rule/naming-rules.md) states the
> derivation and `test/suite/naming.jl` checks it.

---

## Module inventory

### Stage 0 — Reactive Cell Engine

**kernel layer 3 — `cell/`** (`CellModule`)

- `AbstractCell` and three kinds: `ReactiveCell` (tracks dependencies and
  invalidates lazily), `MutableCell` (a plain writable box), and `ImmutableCell`
  (a frozen value). `Cell` is the constructor that picks the kind. The struct
  layer above it holds `@cell_struct`, which generates structs whose fields are
  transparently cell-backed.
- **Pull-based lazy evaluation:** computed cells evaluate only on read (`c[]`).
- **Automatic dependency tracking:** a per-task (task-local) computing stack
  registers every cell read during a computation as an upstream dependency.
- **Invalidation:** writing a cell (`c[] = v`) marks all transitive
  downstream dependents invalid; they recompute lazily on next read.
- **Performance counters:** `run_with_performance_counters()` binds a per-frame store and
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
| `WidgetDocument.jl` | Core: `WidgetInsertion`, `WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`, `WidgetMenuItem`, `WidgetToolbarItem`, `WidgetComposite`, `WidgetToolbar`, `WidgetShell`, `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`, `WidgetScrollBar`. Extension: `WidgetBadge`, `WidgetSeparator`, `WidgetCard`, `WidgetSwitch`, `WidgetProgress`, `WidgetSlider`, `WidgetRadioGroup`, `WidgetAvatar`, `WidgetAlert`, `WidgetSkeleton`, `WidgetSwatch`, `WidgetToggle`, `WidgetToggleGroup`, `WidgetSelect`, `WidgetTextarea`, `WidgetAccordion`, `WidgetTable`, `WidgetTree` |
| `PaneDocument.jl` | `PaneTree`, `PaneSplit`, `PaneGroup`, `PaneTab` |
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
| `FaultCatchingProjection` | The fault barrier of one part at a recursion point: a fault in a cell that the part built draws the mark of the output domain in place of the part |
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
| `WidgetToGraphics` | `Widget` → `Graphics` |
| `PaneToWidget` | `Pane` → `Widget` |
| `GraphicsCaching` | `Graphics` → `Graphics` (caching projection) |
| `LineNumbering` | `Text` → `Text` (domain-preserving) |
| `WordWrapping` | `Text` → `Text` (domain-preserving) |
| `PrimitiveToText` | `Primitive` → `Text` |
| `ReferenceToText` | `Reference` → `Text` |
| `TextFiltering` | `Text` → `Text` (filter rows) |
| `TextHighlighting` | `Text` → `Text` (highlight matches) |
| `SqlToSyntax` | `Sql` → `Syntax` |
| `SqlToCellTable` | `Sql` → `CellTable` |
| `CellTableToWidgetTable` | `CellTable` → `WidgetTable` |
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
| `EditorModule.jl` | REPL loop: read → eval → print; `make_editor(document, projection; backend)`, `build_editor` and `run_editor!` entry points |
| `sdl/SdlBackend.jl` (opt-in `ProjecturedSDL`) | SDL2 + SDL_ttf backend: graphics rendering, event translation, `write_image` |
| `console/ConsoleBackend.jl` (required `ProjecturedConsole`) | Terminal backend: renders the **Text** domain (a `TextBlock`) to the terminal with ANSI colors and reads keystrokes — no `TextToGraphics`/SDL ([devices and backends](../package/kernel/devices-and-backends.md#consolebackend)) |
| `web/WebBackend.jl` (opt-in `ProjecturedWeb`) | Web backend: HTTP + WebSocket server, JSON draw-list (with dirty-rect patches), browser renderer in [asset/web/](../../asset/web) |
| `video/VideoBackend.jl` (opt-in `ProjecturedVideo`) | Video backend: plays a scripted timeline through the editor loop into the frames of a video file |
| `pdf/PdfWriter.jl` (required `ProjecturedPDF`) | SDL-free vector-PDF export (`write_pdf`); hand-rolled TrueType embedding |
| `device/Display.jl` | `Display` device |
| `event/KeyboardEvent.jl` | `KeyDown`, `KeyUp`, `KeyPress` |
| `event/MouseEvent.jl` | `MouseButtons`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseScroll` |
| `event/WindowEvent.jl` | `WindowQuit`, `WindowClose`, `WindowResize`, `WindowDefocus`, `WindowLeave` |
| `event/TimerEvent.jl` | `TimerExpire` |
| `event/DisplayEvent.jl` | `DisplayUpdate` |
| `agent/AgentInterface.jl` (kernel) | The MCP *seam* — `make_agent_server(:mcp, …)`. The transport (JSON-RPC over HTTP, exposing documents and operations) is the opt-in `ProjecturedMCP` |

---

## Module dependency graph

Dependencies flow one way at every level: package → layer → slice. Each edge below
points from a thing to the things it may import; nothing imports upward. The layer
order inside each package is what the static guard (`test_kernel_layering()`, …)
enforces.

**Between packages:**

```
ProjecturedKernel ◄── ProjecturedPlatform ◄── the 17 domains ◄── ProjecturedAll
       ▲                  ▲       ▲                 ▲
       │                  │       │                 │
       │                  │   Projectured      Odbc, Adaptagrams
       │                  │        ▲
       │                  │        │
   Mcp, Anthropic,  Console, Pdf, AutoIntegration
   Ollama,          Sdl, Web,
   OpenRouter       Video, Tulip,
                     DataFrames

ProjecturedIntegrations ◄── Projectured, and the six packages above that own a
                             third-party dependency (Sdl, DataFrames, Video,
                             Odbc, Tulip, Mcp)
```

The umbrella depends on the platform and on `AutoIntegration`, and re-exports
only the twelve names of the platform's essentials slice
(`ProjecturedPlatform.EssentialsModule`). AutoIntegration loads an installed
package whose triggers are all loaded and whose state is `auto`; see
[autointegration.md](../package/autointegration/autointegration.md). Every
other package is one that a user adds by name. `ProjecturedIntegrations`
depends on `Projectured` and the six packages that own a third-party
dependency, and loads each one with a package extension when the package it
joins is loaded. `ProjecturedAll` also depends on Console and Pdf.

The platform's thirty-nine slices form their own DAG, and so do the
seventeen domains. [package-rules.md](../rule/package-rules.md) has the
platform's table; [domain-inventory.md](domain-inventory.md)
has the domain table.

### The 23 kernel layers

In include order, each importing only layers above it in this list — the order
[package/ProjecturedKernel/src/ProjecturedKernel.jl](../../package/ProjecturedKernel/src/ProjecturedKernel.jl)
includes them in:

```
 1 fault       the FaultRecord, the FaultStore a computation may write, the FaultPolicy,
               run_fault_barrier! and the report_fault! cascade. It imports nothing,
               which is why it comes first: every layer above can report.
 2 performance the per-frame performance counters and the FrameMeasurementStore of
               an editor
 3 cell        AbstractCell + the ReactiveCell / MutableCell / ImmutableCell kinds,
               Computation and @computation
 4 struct      @cell_struct, CellStructPlan and the builders of a struct of cells
 5 clock       the animation Clock (a @cell_struct with a reactive time field),
               get_clock_time / set_clock_time!, start_wall_clock! / stop_wall_clock!
 6 event       the input events (Event, ModifierKeys, KeyDown/KeyPress/Mouse*/Window*,
               WindowInput)
 7 device      Device abstract + Keyboard / Mouse / Display devices (physical properties)
 8 gesture     the gestures (Gesture, MouseClick/MouseDwell, KeyChord), the pattern language
               (GesturePattern, matches_gesture_pattern,
               describe_gesture_pattern, @gesture_case) and the recognitions
               (GestureRecognition, ChordRecognition, ClickRecognition, DwellRecognition,
               make_standard_recognitions)
 9 backend     the Backend seam (lifecycle, device I/O, the wait and the wake, display
               size, device config, image/video output)
10 document    the Document supertype, @document, the is_element_collection /
               is_walk_opaque traits, search_documents
11 reference   ReferenceStep / Reference and the step seam, evaluate_reference,
               search_references, the @reference / @reference_case /
               @reference_rules DSLs
12 selection   get_selection / set_selection! / clear_selection!
13 operation   the Operation supertype, evaluate_operation, the reroot_operation seam
14 intent      Intent and ClaimedGesture, the unit that flows back through the
               readers, CollectIntents and CollectedIntentsOperation
15 binding     GestureBinding, the per-document-type registry, @gestures /
               @gesture_set, read_gesture / read_bound_gesture
16 iomap       the IoMap contract (IoMap + accessors), the concrete IO maps
               (SimpleIoMap, ChildrenIoMap, ContentIoMap, @iomap), and the child
               reconcilers (make_reconciled_child_iomaps_cell,
               make_reconciled_child_iomap_cell)
17 projection  the four interface functions, @projection, ProjectionTemplate,
               ProjectionReferenceStep
18 tool        the editor's capability surface: Tool / Resource / ToolSet,
               execute_julia_code!, doc/API search, register_default_tools!
19 llm         the LLM provider abstraction: Llm, stream_turn, render_tool_schema,
               LlmMessage / LlmRequest, LlmEvent
20 agent       the AI control surface: AgentModule, with the inbound MCP seam
               and the outbound Agent and run_turn! loop
21 feed        the feed contract: a registered inflow that the editor moves into a
               target document once per frame
22 editor      run_editor!, the read-eval-print loop
23 playback    scripted live playback: a timeline that fires in the editor loop on a
               wall-clock schedule
```

**The thirty-nine slices of `ProjecturedPlatform`**, in a topological order.
Each is one concept, and each declares the exact set of slices it imports;
[package-rules.md](../rule/package-rules.md) has the table. (Console and Pdf,
the two backends with no third-party dependency, are packages of their own,
not slices of the platform.)

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
   gesturetracking the projection that runs the recognitions of the kernel
                   gesture layer over the inputs, and its state document
   dragtracking    the projection that keeps the part whose drag is on and
                   gives it the parts of its drag, and its state document
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
   inspector       the reference inspector and the selection inspector
   gesturehelp     the gesture map, the command palette and their two decorators
   gesturelog      the log document, its printer, its recorder and its overlay
   fault           the fault report and log documents, the barrier projection that
                   catches, the four renderers and the safe mode
   fileformat      NaturalFormat, DocumentFile
   filesystem      the file-system tree, the workspace, and the Explorer view
   natural         NaturalRegistry and NaturalProjection: render anything
   display         a value shown in an editor window beside the REPL
   essentials      the few names of the kernel and the platform that most
                   users call: display_in_editor, run_editor!, parse_natural_text
   undo            UndoBuffer and its transparent recording projection
   log             the message log of the session, filled from any task
   statistics      the frame-time table and plot of the editor loop
   shell           the wrappers a binary stacks over a window, and its chrome
   help            the document-type list, the projection list, and the about page
   conversation    the evaluator documents and the chat transcript
   assistant       the chat with a model, and the turn that streams a reply
   application     the window of files, the navigator and the assistant, and
                   the command line of a binary
```

**The seventeen domain packages** — one package per concrete source domain,
each holding one slice: its documents, its parser and its projections.
Thirteen need only the engine and the platform; four build on one layer of
domains. The assistant and the conversation slice it builds on are slices of
the platform, not domains. [domain-inventory.md](domain-inventory.md) has the table and the rules
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
| Widget → GraphicsCanvas | ✅ |
| Pane → Widget → GraphicsCanvas | ✅ |
| SDL2 window rendering | ✅ |
| Text → terminal (`ConsoleBackend`, ANSI colors, no `TextToGraphics`) | ✅ |
| Web rendering (browser canvas, dirty-rect patches) | ✅ |
| Offscreen BMP/PNG export (`write_image`) | ✅ |
| Vector PDF export, multi-page (`write_pdf`) | ✅ |

### Reader (reverse projection)

| Step | Status |
|---|---|
| Selection movement across all major pipelines | ⚠️ rightwards ✅; leftwards stalls on projection-introduced text in every syntax-backed pipeline (`test_text_navigation_invariants_all`, [plan/pending/left-motion-stalls-on-introduced-text.md](../../plan/pending/left-motion-stalls-on-introduced-text.md)) |
| `TextToGraphics` — `:left` / `:right` → `ReplaceSelectionOperation` | ✅ |
| `SyntaxLeafToText` — flat position → leaf-domain path | ✅ |
| `SyntaxCompoundToText` — flat position → recursive child path | ✅ |
| `JsonToSyntax` — all node types | ✅ |
| `ChainingProjection`, `TypeDispatching`, `RecursiveProjection` | ✅ |
| Character editing (`ReplaceStringRangeOperation`) | ⚠️ wired + tested (`test_typeins`) for field-addressed examples; not every domain |
| Mouse click-to-select | ⚠️ wired + tested (`test_mouse_clicks` / `test_click_roundtrips`); not every domain |
| Undo / redo | ✅ (`UndoBuffer` + `UndoBufferToAnyProjection`; opt-in, and the application installs two levels) |

---

## Mapping to the original ProjecturEd

| Lisp ProjecturEd | Julia ProjecturEd | Status |
|---|---|---|
| `computed-class` (change propagation) | `CellModule` (`ReactiveCell`) | ✅ |
| JSON domain | `JsonDocument.jl` | ✅ |
| Tree domain | `SyntaxDocument.jl` | ✅ |
| Styled string domain | `TextDocument.jl` | ✅ |
| Graphics domain | `GraphicsDocument.jl` | ✅ |
| SDL backend | `sdl/SdlBackend.jl` | ✅ |
| Console (terminal) backend | `console/ConsoleBackend.jl` | ✅ (Text domain, no Lisp counterpart) |
| Web backend (browser renderer) | `web/WebBackend.jl` | ✅ (new in Julia port) |
| PDF export backend | `pdf/PdfWriter.jl` | ✅ |
| IO Maps | `IoMapDefaults.jl` + per-projection | ✅ |
| References | `reference/` (layer 11) | ✅ |
| Navigation operations | `Operations.jl` (`ReplaceSelectionOperation`) | ✅ |
| Editor REPL | `EditorModule.jl` | ✅ |
| All higher-order projections | `projection/higherorder/` | ✅ |
| Insert / delete operations | `Operations.jl` (`make_insert_elements_operation` / `make_delete_elements_operation` → a `ReplaceReferencedValueOperation` splice) | ✅ (collections; produced by JSON/XML readers) |
| Undo / redo | `undo/` (`UndoBuffer`, `UndoBufferToAnyProjection`, `make_inverse_operation`) | ✅ |
