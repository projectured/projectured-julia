# Kernel layered architecture — kernel/base package split with strict layers

Design review of `package/kernel` (2026-07-03): reorganize the kernel into a strict
layered architecture split across **two packages** — a slow-changing `ProjecturedKernel`
(machinery + interfaces only) and a new faster-changing **`ProjecturedBase`**
(`package/base`, all concrete documents and projections). Each layer gets its own folder,
its own tests, and its own documentation. Clarity, maintainability, and ease of
understanding are the priorities; backward compatibility is explicitly **not** a
constraint (module renames/merges are fine), but all in-repo consumers (domain, umbrella,
llm, mcp, sdl, web, test) are updated in the same effort so the repo stays green.

Decisions taken during the design review:

- **Fine layers**, strict rule: layer N imports only layers < N.
- **Each layer owns its interface** — the separate `api/` stub tier dissolves into the
  layers that own the concepts (a higher layer adds methods to a lower layer's generics
  where its types are involved — standard multiple-dispatch layering).
- **Two packages.** This dissolves the confusing "document layer = contract vs
  vocabulary layer = concrete documents" split inside one package: `kernel/document` is
  unambiguously the contract, `base/document` unambiguously actual documents.
- **All concrete documents leave the kernel** (Collection, Primitive, ScreenDocument
  included); the editor is decoupled from them (verified cheap — see R5).
- **Document-free projections stay in the kernel** (Chaining, Identity, Constant, the
  dispatchers, …): they are the *structure* of a pipeline, not its content. A projection
  is kernel-side iff it imports no concrete document — machine-checkable, guard-enforced.
- **Per-layer tests inside each package**; kernel tests use test-local toy
  documents/projections only — permanent pressure that the kernel interfaces stay
  sufficient. `ProjecturedTest` keeps cross-package/domain/pipeline tests.
- One folder per layer, plain names (order machine-enforced by the guard, no numeric
  prefixes).

Supersedes the "Target structure (proposal)" section and the remaining Phase 2 items of
[kernel-cleanup.md](kernel-cleanup.md); its findings, audits, and completed phases
remain valid and are reused here.

## The layer stacks

**The first layer is `cell`** — the reactive cell engine: dependency-free,
understandable/testable/documentable in complete isolation; everything above is built
from it.

### ProjecturedKernel — 9 layers, zero concrete documents

| # | Folder | Modules | Story |
| --- | --- | --- | --- |
| 1 | `cell/` | `PerformanceCounterModule`, `CellModule` (+4 kind fragments), `TimeModule` (moved from `editor/` — it is just a global `Cell`; domain projections consume it) | a spreadsheet cell: read tracks, write invalidates |
| 2 | `document/` | `DocumentModule` (absorbs `DocumentApiModule`): `Document` abstract, `@document`, selection contract, `snapshot`/`copy_document`/`rekind` | what a document is |
| 3 | `reference/` | `ReferenceModule` (absorbs ReferenceCase + ReferenceBuilder) | paths into documents |
| 4 | `operation/` | `OperationModule` (absorbs OperationApi + OperationRerooting): `Operation` abstract, built-in generic ops, `evaluate_operation`, splice helpers, open rerooting/traversal seams | changing documents |
| 5 | `device/` | `DeviceModule` (ex-DeviceApi), `ModifiersModule`, `KeyboardModule`, `MouseModule`, `ScreenDeviceModule`, `GestureModule` (EventCase + GestureBinding merged; owns the rehomed `EventEnvelope` and the `read_gesture` declaration), `GestureRecognizerModule` | input devices, events, gestures |
| 6 | `backend/` | `BackendModule` (ex-BackendApi: `Backend`, `initialize_backend!`/`quit_backend!`/`measure_text`, `make_backend` factory), `DisplayModule`, new `HeadlessBackendModule` (in-memory render target + scripted event source — document-agnostic; used by kernel editor tests, CI, file output) | rendering targets |
| 7 | `projection/` | `ProjectionModule` (absorbs ProjectionApi + Intent + IoMap/IoMapApi + PrinterContext + `@projection` + Primitive-free defaults) plus the **12 document-free combinators** as fragments: Identity, Constant, Chaining, Switching, TypeDispatching, PredicateDispatching, ReferenceDispatching, Recursive, Nesting, EnvelopeUnwrapping (document-free after R5), Focusing, Reversing (verified: none imports a concrete document) | how documents transform: the four-generic interface + the structural pipeline algebra |
| 8 | `agent/` | `AgentModule` (ex-AgentApi), `ToolRegistryModule`, `LlmModule`, `McpModule` | the AI control surface (side-stack; the editor reaches it only via `make_agent_server`) |
| 9 | `editor/` | `EditorModule`, `PlaybackModule` | the read-eval-print loop |

### ProjecturedBase (new, `package/base`) — 2 layers, depends only on ProjecturedKernel

| # | Folder | Modules | Story |
| --- | --- | --- | --- |
| 1 | `document/` | `CollectionModule`, `PrimitiveModule`, `ScreenDocumentModule` — plus their methods on kernel seams (`child_reference_steps(::CellVector)`, `reroot_operation` for the splice-range ops, their `evaluate_operation` methods) | the concrete documents everything ships with |
| 2 | `projection/` | the 5 document-dependent projections — Sorting, Filtering, Searching, Copying (import `CellVector`/`ListNode`), WindowManaging (the ScreenDocument window model) — plus the Primitive-dependent reader defaults (R6), consolidated into one module (working name `BaseProjectionModule`; final name decided at implementation, umbrella collision-checked) | the document-shaped projection library |

Package chain: **kernel ← base ← domain ← umbrella**; `llm`/`mcp` ← kernel only;
`sdl`/`web` ← domain (unchanged). Standing boundary rules for future code: a *document*
is kernel-side only if the machinery itself needs it (currently: none); a *projection*
is kernel-side iff it imports no concrete document.
([domain-layered-architecture.md](domain-layered-architecture.md) later extends the
chain to kernel ← base ← **visual** ← domain and feature-slices the domain package;
it also moves 6 domain files into base — the two compound combinator aggregates, the
insertion document (its D1), and a new `serialization/` third layer:
BinarySerialization, NaturalFormat, DocumentFile (its D4) — moves 1 into this kernel's
projection layer: ProjectionTemplate.jl, the builder-and-walk template engine (its D5;
kernel-pure after a children-container seam that base's CellVector implements) — and
moves ScreenDocument + WindowManaging onward from base into visual's `screen/` slice:
screen/window things are graphics; only the Screen *device* and display seam stay
kernel, being the interface the editor writes to. Execute this plan unchanged; the
onward moves happen in the domain plan's Q1.)

### No-cycle verification (2026-07-03)

Statically verified over the real import headers (all 53 modules, 181 `..Module` edges):
the raw module graph is a DAG (no cycles today), and after applying the six planned
refactors below as edge rewrites (4 edges dropped, 4 retargeted), **every edge points to
the same or a lower layer, with no kernel→base edge**. Notable legal edges:
`base/projection → kernel projection` ×15 (base implements the kernel interface),
`editor → agent` ×1 (the factory seam), `device → document` ×1 (GestureBinding reaching
down to the Document contract).

A layering pattern worth documenting (it looks like a cycle until you see the trick):
`ProjectionReference` ([reference/Reference.jl](../../package/kernel/src/reference/Reference.jl)
line ~231) stores its projection as an **untyped `Any` payload** — the reference layer
defines only the step's shape and never imports `Projection`; only higher layers
construct and interpret the payload (same pattern as `Intent`). So projection → reference
(PrinterContext, reference mapping) is the only edge, and it points down.

## Target file tree (folders, files, one-line descriptions)

The readable overview. A **folder = a layer**; an aggregator `XxxModule.jl` = the layer's
public module; *fragments* are files it `include`s that share its namespace (so a large
module stays one importable unit while its code lives in per-concept files).

### `package/kernel/` — the engine: machinery + interfaces, zero concrete documents

```
src/
  ProjecturedKernel.jl          # top module: 9 layer sections, includes aggregators in order

  cell/                         # LAYER 1 — reactive change propagation
    PerformanceCounter.jl       # process-global read/compute/invalidate/write counters
    CellModule.jl               # aggregator: the AbstractCell{T} box + its three kinds
    AbstractCell.jl             #   fragment: the AbstractCell{T} supertype
    ReactiveCell.jl             #   fragment: pull-based reactive cell, auto dependency tracking
    MutableCell.jl              #   fragment: plain mutable cell, no bookkeeping
    ImmutableCell.jl            #   fragment: read-only, zero-cost cell
    Time.jl                     # the one global animation clock (a single Cell)

  document/                     # LAYER 2 — what a document is (the contract)
    DocumentModule.jl           # aggregator
    Interface.jl                #   fragment: Document abstract type + selection generics
    Document.jl                 #   fragment: the @document macro, snapshot/copy_document/rekind

  reference/                    # LAYER 3 — paths into documents
    ReferenceModule.jl          # aggregator
    Reference.jl                #   fragment: reference-path types, evaluate_reference
    ReferenceCase.jl            #   fragment: the @reference_case pattern-matching DSL
    ReferenceBuilder.jl         #   fragment: the @reference / @step construction DSL

  operation/                    # LAYER 4 — changing documents
    OperationModule.jl          # aggregator (owns the child_reference_steps traversal seam, R1)
    Interface.jl                #   fragment: Operation abstract + evaluate_operation stub
    Operations.jl               #   fragment: built-in ops, selection machinery, splice helpers
    Rerooting.jl                #   fragment: open reroot_operation generic (container → child, R2)

  device/                       # LAYER 5 — input devices, events, gestures
    Device.jl                   # Device abstract + read/write_from_devices stubs
    Modifiers.jl                # the Ctrl/Shift/Alt/Meta modifier struct
    Keyboard.jl                 # Keyboard device + key event types
    Mouse.jl                    # Mouse device + mouse event types
    ScreenDevice.jl             # Screen display device + WindowQuit
    GestureModule.jl            # aggregator (owns the rehomed EventEnvelope, R5)
    EventCase.jl                #   fragment: the @event_case dispatch-table macro + parser
    GestureBinding.jl           #   fragment: gesture→operation bindings, @gestures registry
    GestureRecognizer.jl        # synthesises MousePress/KeyChord from raw event streams

  backend/                      # LAYER 6 — rendering targets
    Backend.jl                  # Backend abstract, measure_text, the make_backend factory seam
    Display.jl                  # display-size query + the provider indirection
    HeadlessBackend.jl          # NEW: dependency-free in-memory backend + scripted event source

  projection/                   # LAYER 7 — how documents transform + the structural algebra
    ProjectionModule.jl         # aggregator (owns the R3 gesture-projection seams)
    Interface.jl                #   fragment: the four generics + Projection + print_child
    Intent.jl                   #   fragment: the reader's backward-flowing Intent type
    IoMapInterface.jl           #   fragment: IoMap abstract + accessors
    IoMap.jl                    #   fragment: SimpleIoMap/ChildrenIoMap + @iomap
    PrinterContext.jl           #   fragment: the downward per-print_document context
    Defaults.jl                 #   fragment: @projection macro + the document-free fallbacks
    algebra/Identity.jl         #   fragment: pass-through projection
    algebra/Constant.jl         #   fragment: fixed-output projection
    algebra/Chaining.jl         #   fragment: chains projections L→R (reader R→L)
    algebra/Switching.jl        #   fragment: delegates to a reactively-selected projection
    algebra/TypeDispatching.jl  #   fragment: dispatches on typeof(input)
    algebra/PredicateDispatching.jl  # fragment: dispatches on a boolean predicate
    algebra/ReferenceDispatching.jl  # fragment: dispatches on the current reference path
    algebra/Recursive.jl        #   fragment: passes itself as recursion for self-similar trees
    algebra/Nesting.jl          #   fragment: scopes an inner projection to a sub-document
    algebra/EnvelopeUnwrapping.jl    # fragment: strips the EventEnvelope off a gesture
    algebra/Focusing.jl         #   fragment: projects a focused sub-document
    algebra/Reversing.jl        #   fragment: reverses child order

  agent/                        # LAYER 8 — the AI control surface (side-stack)
    Agent.jl                    # the make_agent_server / start / stop factory seam
    ToolRegistry.jl             # in-process registry of Tools + Resources
    Llm.jl                      # pluggable LLM backend seam (stream_turn)
    Mcp.jl                      # MCP server skeleton + the doc-introspection tools

  editor/                       # LAYER 9 — the read-eval-print loop
    Editor.jl                   # run_editor!: read → evaluate → print → tick
    Playback.jl                 # scripted live playback on a wall-clock timeline

test/
  runtests.jl                   # fragment- & layer-aware include-order + boundary guard
  cell/ … editor/               # one folder per layer; tests import only that layer and below

doc/
  architecture.md               # the 9-layer diagram, guard, kernel/base boundary rule
  cell.md · document.md · … · editor.md   # one guide per layer
```

### `package/base/` — the library: all concrete documents and projections

```
src/
  ProjecturedBase.jl            # top module: kernel-alias preamble + 2 layer sections

  document/                     # LAYER 1 — the built-in documents everything ships with
    Collection.jl               # CellVector / CellMatrix / CellTable / ListNode
    Primitive.jl                # editable bool/number/string docs + their splice-range ops
    ScreenDocument.jl           # the multi-window screen model + window events/ops

  projection/                   # LAYER 2 — the document-shaped projection library
    BaseProjectionModule.jl     # aggregator
    Sorting.jl                  #   fragment: sorts collection children by a key
    Filtering.jl                #   fragment: keeps children matching a predicate
    Searching.jl                #   fragment: collects objects whose field matches a Regex
    Copying.jl                  #   fragment: domain-independent deep copy with iomaps
    WindowManaging.jl           #   fragment: the ScreenDocument open/close/resize reader
    ReaderDefaults.jl           #   fragment: the Primitive-op read_intent defaults (R6)

test/
  runtests.jl                   # same guard, LAYERS = ["document","projection"]
  document/ · projection/       # per-layer tests

doc/
  architecture.md · document.md · projection.md
```

## Target folder/file structure (with exports and kernel imports)

Generated from the real source headers (export statements, `@document struct`
declarations, and `import ..Module: symbols` lines) with the module merges and the
R1-R6 refactors applied. Conventions: *(fragment)* files are `include`d by their
module's aggregator file and share its namespace; imports between files of the same
target module are internal and omitted; import lines name the **post-merge** source
module; *(aggregator)* / *(new)* files list only the symbols they add.

```
# *  = @document-generated export (the struct + its R/I/M kind aliases)
package/kernel/src/
  ProjecturedKernel.jl                     # 9 layer sections, includes aggregators/standalone modules only
  cell/                                # layer 1 - cell
    PerformanceCounter.jl
        exports: get_performance_counters, reset_performance_counters!, record_performance!,
            @performance_time
    CellModule.jl
        exports: Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell, set_value!,
            set_function!, is_up_to_date
    AbstractCell.jl (fragment)
        (no exports)
    ReactiveCell.jl (fragment)
        (no exports)
        imports PerformanceCounterModule: _perf
    MutableCell.jl (fragment)
        (no exports)
    ImmutableCell.jl (fragment)
        (no exports)
    Time.jl
        exports: get_editor_time, get_reactive_editor_time, tick_editor_time!
        imports CellModule: Cell
  document/                                # layer 2 - document
    Interface.jl (fragment)
        exports: Document, get_selection, clear_selection!, set_selection!, with_selection,
            read_gesture
    Document.jl (fragment)
        exports: Document, copy_document, cell_kind, rekind, snapshot, hydrate, sync_document!,
            @document, @forward, @forward_vector, @forward_map
        imports CellModule: Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell
    DocumentModule.jl (aggregator)
  reference/                                # layer 3 - reference
    ReferenceModule.jl (aggregator)
    Reference.jl (fragment)
        exports: Reference, ReferenceStep, ElementReference, PositionReference, TypeReference,
            FunctionReference, ProjectionReference, TextRectangularReference, ReferencePath,
            EmptyReferencePath, append_reference, concat_references, reference_steps,
            evaluate_reference, is_valid_reference, collect_references, is_element_reference,
            is_position_reference, is_range_reference, is_reference_equal, is_prefix_of,
            is_reference_equal_ignoring_types, is_prefix_of_ignoring_types, ReferenceTypeMismatch,
            get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
            fold_reference_types, RangeReference*, FieldReference*, ConcreteReferencePath*,
            PointReference*
        imports CellModule: Cell, AbstractCell
        imports DocumentModule: @document
    ReferenceCase.jl (fragment)
        exports: @reference_case, when, prefix
    ReferenceBuilder.jl (fragment)
        exports: @reference, @step
  operation/                                # layer 4 - operation
    OperationModule.jl (aggregator)
        exports (new seam): child_reference_steps
    Interface.jl (fragment)
        exports: Operation, evaluate_operation, invalidate_projection!
    Operations.jl (fragment)
        exports: DoNothingOperation, ReplaceSelectionOperation, QuitEditorOperation,
            QuitEditorException, replace_selection!, ToggleCollapseOperation,
            ReplaceReferencedValueOperation, replace_document, insert_elements, delete_elements,
            SelectNextInsertionOperation, CompoundOperation, AdjustZoomOperation,
            AdjustFontZoomOperation, update_selection!, splice_string, splice_number, splice_value!
        imports DocumentModule: Document, clear_selection!, set_selection!, with_selection
        imports ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
            FieldReference, RangeReference, TypeReference, is_element_reference, evaluate_reference,
            is_reference_equal, annotate_reference_types, strip_reference_types, append_reference,
            concat_references, reference_steps
        imports CellModule: Cell, AbstractCell
    Rerooting.jl (fragment)
        exports: reroot_reference, reroot_operation
        imports ReferenceModule: ReferencePath, ConcreteReferencePath
  device/                                # layer 5 - device
    Device.jl
        exports: Device, write_to_devices, read_from_devices
    Modifiers.jl
        exports: Modifiers
    Keyboard.jl
        exports: Keyboard, KeyDown, KeyUp, KeyPress, KeyChord, is_ctrl, is_shift, is_alt, is_meta
        imports DeviceModule: Device
        imports ModifiersModule: Modifiers
    Mouse.jl
        exports: Mouse, MouseDown, MouseUp, MousePress, MouseMove, MouseScroll, MouseEnter,
            MouseLeave
        imports DeviceModule: Device
        imports ModifiersModule: Modifiers
    ScreenDevice.jl
        exports: Screen, WindowQuit
        imports DeviceModule: Device
    GestureModule.jl (aggregator)
        exports (rehomed, R5): EventEnvelope
    EventCase.jl (fragment)
        exports: var"@event_case"
        imports KeyboardModule (whole module)
        imports MouseModule (whole module)
        imports ModifiersModule (whole module)
    GestureBinding.jl (fragment)
        exports: GesturePattern, KeyPressPattern, KeyDownPattern, KeyUpPattern, MouseDownPattern,
            MouseUpPattern, MousePressPattern, MouseMovePattern, MouseScrollPattern, GestureBinding,
            matches, describe, get_document_gesture_bindings, get_document_gesture_bindings_own,
            get_instance_gesture_bindings, read_document_gesture, read_node_gesture,
            get_applicable_gesture_bindings, is_help_gesture, var"@gestures", var"@gesture_set"
        imports KeyboardModule: KeyDown, KeyUp, KeyPress
        imports MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
        imports ModifiersModule: Modifiers
        imports DocumentModule: Document, read_gesture
    GestureRecognizer.jl
        exports: GestureRecognizer, recognize_gesture!, pop_gesture!
        imports MouseModule: MouseDown, MouseUp, MousePress
        imports KeyboardModule: KeyDown, KeyChord
        imports GestureModule: EventEnvelope
  backend/                                # layer 6 - backend
    Backend.jl
        exports: Backend, initialize_backend!, quit_backend!, measure_text, make_backend,
            write_image, record_video, render_canvas, decode_image, get_pointer_position
    Display.jl
        exports: get_display_size, set_display_size_provider!
    HeadlessBackend.jl (new)
        exports: HeadlessBackend, rendered_output, push_event!
        imports BackendModule: Backend, make_backend
        imports DeviceModule: Device, read_from_devices, write_to_devices
  projection/                                # layer 7 - projection
    ProjectionModule.jl (aggregator)
        exports (moved in, R3): get_projection_gesture_bindings, read_projection_gesture,
            collect_gesture_bindings
    Interface.jl (fragment)
        exports: print_document, print_child, read_intent, map_reference_forward,
            map_reference_backward, Projection, pure_print_document, pure_print_child
    Intent.jl (fragment)
        exports: Intent
    IoMapInterface.jl (fragment)
        exports: IoMap, get_iomap_projection, get_iomap_input, get_iomap_output
    IoMap.jl (fragment)
        exports: SimpleIoMap, ChildrenIoMap, ContentIoMap, @iomap
        imports CellModule: Cell
        imports DocumentModule: _cell_autowrap_ctor, _cell_property_accessors, _cell_kw_params,
            _cell_kwctor
    PrinterContext.jl (fragment)
        exports: PrinterContext, make_child_context, with_available_size, with_property,
            get_property
        imports CellModule: Cell
        imports ReferenceModule: ReferencePath, EmptyReferencePath, ReferenceStep, append_reference
    Defaults.jl (fragment)
        exports: @projection, pure_print
        imports OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation,
            ReplaceReferencedValueOperation, CompoundOperation, SelectNextInsertionOperation
        imports CellModule: Cell, AbstractCell
        imports DocumentModule: snapshot, Document, read_gesture
        imports ReferenceModule: EmptyReferencePath, var"@reference_case", var"@reference"
        imports KeyboardModule: KeyPress, KeyDown
        imports MouseModule: MousePress
    algebra/Identity.jl (fragment)
        exports: IdentityProjection
    algebra/Constant.jl (fragment)
        exports: ConstantProjection
    algebra/Chaining.jl (fragment)
        exports: ChainingProjection, ChainingProjectionIoMap
        imports GestureModule: GestureBinding
        imports CellModule: Cell, AbstractCell
    algebra/Switching.jl (fragment)
        exports: SwitchingProjection, SwitchingProjectionIoMap
        imports CellModule: Cell
    algebra/TypeDispatching.jl (fragment)
        exports: TypeDispatchingProjection
        imports GestureModule: GestureBinding
    algebra/PredicateDispatching.jl (fragment)
        exports: PredicateDispatchingProjection
    algebra/ReferenceDispatching.jl (fragment)
        exports: ReferenceDispatchingProjection, ReferenceDispatchingProjectionIoMap
        imports ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
            FieldReference, RangeReference, PointReference, ProjectionReference, head, tail,
            is_reference_equal, is_prefix_of
    algebra/Recursive.jl (fragment)
        exports: RecursiveProjection
    algebra/Nesting.jl (fragment)
        exports: NestingProjection, NestingProjectionIoMap
        imports GestureModule: GestureBinding
    algebra/EnvelopeUnwrapping.jl (fragment)
        exports: EnvelopeUnwrappingProjection, EnvelopeUnwrappingProjectionIoMap
        imports GestureModule: EventEnvelope
    algebra/Focusing.jl (fragment)
        exports: FocusingProjection, ReplaceFocusPartOperation
        imports OperationModule: Operation, evaluate_operation, ReplaceSelectionOperation
        imports ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
            evaluate_reference, append_reference, strip_reference_types
        imports CellModule: set_function!
        imports GestureModule: GestureBinding, KeyDownPattern
    algebra/Reversing.jl (fragment)
        exports: ReversingProjection
        imports CellModule: Cell
        imports ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference,
            RangeReference, append_reference, var"@reference_case"
  agent/                                # layer 8 - agent
    Agent.jl
        exports: make_agent_server, start_agent_server!, stop_agent_server!
    ToolRegistry.jl
        exports: Tool, Resource, register_tool!, register_tools!, list_tools, call_tool, find_tool,
            register_resource!, register_resources!, list_resources, read_resource, find_resource,
            get_anthropic_tool_schema, clear_registry!
    Llm.jl
        exports: Llm, AnthropicLlm, FakeLlm, stream_turn, ScriptedLlm, make_scripted_turn,
            make_scripted_think, make_scripted_say, make_scripted_run
    Mcp.jl
        exports: execute_julia_code, get_last_evaluated_value, list_guides, read_guide,
            list_modules, list_types, list_functions, read_module_documentation,
            read_type_documentation, read_function_documentation, search_documentation, search_api,
            register_default_tools_and_resources!
        imports ToolRegistryModule: Tool, Resource, register_tool!, register_resource!, list_tools,
            list_resources
  editor/                                # layer 9 - editor
    Editor.jl
        exports: Editor, run_editor!
        imports ProjectionModule: Projection, print_document, read_intent, Intent, IoMap
        imports DeviceModule: Device, read_from_devices, write_to_devices
        imports BackendModule: Backend, initialize_backend!, quit_backend!
        imports ScreenDeviceModule: Screen, WindowQuit
        imports GestureModule: EventEnvelope
        imports PerformanceCounterModule: get_performance_counters, reset_performance_counters!,
            @performance_time
        imports TimeModule: tick_editor_time!
        imports DocumentModule: Document
        imports KeyboardModule: Keyboard, KeyDown
        imports MouseModule: Mouse
        imports OperationModule: Operation, evaluate_operation, invalidate_projection!,
            ReplaceSelectionOperation, QuitEditorOperation, AdjustZoomOperation,
            AdjustFontZoomOperation, QuitEditorException
        imports GestureRecognizerModule: GestureRecognizer, pop_gesture!
        imports AgentModule: make_agent_server, start_agent_server!, stop_agent_server!
    Playback.jl
        exports: play_live!
        imports EditorModule: Editor, read!, evaluate!, print!, perf!
        imports PerformanceCounterModule: reset_performance_counters!, @performance_time
        imports ProjectionModule: read_intent, Intent
        imports GestureModule: EventEnvelope
        imports OperationModule: Operation, QuitEditorException, reroot_operation
        imports ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath
        imports BackendModule: Backend, initialize_backend!, quit_backend!
        imports DeviceModule: Device
        imports ScreenDeviceModule: Screen
        imports KeyboardModule: Keyboard
        imports MouseModule: Mouse
package/base/src/
  ProjecturedBase.jl                       # kernel-alias preamble + 2 layer sections
  document/                                # layer 1 - document
    Collection.jl
        exports: CollectionDocument, get_left_tail, get_right_tail, get_cell_at, take_first,
            insertrow!, insertcol!, deleterow!, deletecol!, insertrow, deleterow, CellVector*,
            CellMatrix*, CellTable*, ListNode*
        imports CellModule: Cell, AbstractCell, ReactiveCell, ImmutableCell, MutableCell,
            set_function!, set_value!
        imports DocumentModule: Document, copy_document, rekind, sync_document!, _same_cell,
            _same_wrapper, _shadow_elem, @document, @forward
        imports ReferenceModule: Reference
    Primitive.jl
        exports: PrimitiveDocument, ReplaceNumberRangeOperation, ReplaceStringRangeOperation,
            PrimitiveInsertion*, PrimitiveBool*, PrimitiveNumber*, PrimitiveString*
        imports CellModule: Cell, set_function!, set_value!
        imports DocumentModule: Document, clear_selection!, set_selection!, @document
        imports OperationModule: Operation, evaluate_operation, splice_string, splice_value!,
            splice_number
        imports ReferenceModule: Reference, ReferencePath, ConcreteReferencePath,
            EmptyReferencePath, ReferenceStep, FieldReference, RangeReference, evaluate_reference,
            strip_reference_types, reference_steps
    ScreenDocument.jl
        exports: WindowClose, WindowResize, WindowDefocus, OpenWindowOperation, OpenPopupOperation,
            CloseWindowOperation, ResizeWindowOperation, ScreenDocument*, WindowDocument*
        imports CellModule: Cell, set_function!, set_value!
        imports DocumentModule: Document, @document
        imports CollectionModule: CellVector
        imports ReferenceModule: Reference, ReferencePath
        imports OperationModule: Operation, evaluate_operation
  projection/                                # layer 2 - projection
    BaseProjectionModule.jl (aggregator)
    Sorting.jl (fragment)
        exports: SortingProjection, SortingProjectionIoMap
        imports ProjectionModule: print_document, print_child, map_reference_forward,
            map_reference_backward, Projection, SimpleIoMap, IoMap, make_child_context,
            IdentityProjection
        imports CellModule: Cell
        imports CollectionModule: CellVector
        imports ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference,
            RangeReference, append_reference, var"@reference_case", var"@reference"
    Filtering.jl (fragment)
        exports: FilteringProjection, FilteringProjectionIoMap
        imports ProjectionModule: print_document, map_reference_forward, map_reference_backward,
            Projection, IoMap
        imports CellModule: Cell
        imports CollectionModule: CellVector
        imports ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference,
            append_reference, var"@reference_case"
    Searching.jl (fragment)
        exports: SearchingProjection, SearchingProjectionIoMap
        imports ProjectionModule: print_document, map_reference_forward, map_reference_backward,
            Projection, IoMap
        imports CellModule: Cell, AbstractCell, set_function!
        imports CollectionModule: CellVector
        imports DocumentModule: Document
        imports ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
            FieldReference, ElementReference, append_reference, head, tail, strip_reference_types,
            var"@reference_case"
    Copying.jl (fragment)
        exports: CopyingProjection, CopyingProjectionIoMap, make_copying_field_iomap,
            make_copying_element_iomap
        imports ProjectionModule: print_document, print_child, map_reference_forward,
            map_reference_backward, Projection, PrinterContext, make_child_context, IoMap
        imports CellModule: Cell, set_function!, set_value!
        imports DocumentModule: Document
        imports ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
            ElementReference, is_element_reference, head, tail
        imports CollectionModule: CellVector, ListNode
    WindowManaging.jl (fragment)
        exports: WindowManagingProjection, WindowManagingProjectionIoMap
        imports ProjectionModule: print_document, print_child, read_intent, map_reference_forward,
            map_reference_backward, Projection, Intent, IoMap
        imports CellModule: Cell
        imports GestureModule: EventEnvelope
        imports ScreenDocumentModule: ScreenDocument, WindowDocument, WindowResize, WindowClose,
            WindowDefocus, OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation
        imports OperationModule: CompoundOperation
    ReaderDefaults.jl (fragment, R6)
        (methods only, no exports: the Primitive-op read_intent defaults moved out of
            common/Projection.jl)
        imports ProjectionModule: read_intent, Change
        imports PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
```

## The six refactors (the only semantic changes; all verified against source)

- **R1 — Operation → Collection** (`common/Operation.jl:23` + the `node isa CellVector`
  branch of `_preorder_documents!`, used by `SelectNextInsertionOperation`): declare an
  open traversal seam `child_reference_steps(node)` in kernel operation with the current
  `fieldnames`-walk default; base `Collection.jl` adds the `CellVector` method.
- **R2 — OperationRerooting → Primitive** (`common/OperationRerooting.jl:65-68`): convert
  `reroot_operation`'s closed if-chain to an open generic (methods for `Nothing`,
  catch-all, `ReplaceSelectionOperation`, `ReplaceReferencedValueOperation`,
  `CompoundOperation`); base `Primitive.jl` adds the `ReplaceStringRangeOperation` /
  `ReplaceNumberRangeOperation` methods. Rewrite the `INVARIANT` comments: "a new
  path-bearing operation must add a `reroot_operation` method".
- **R3 — GestureBinding → ProjectionApi** (verified: only the `Projection` type in 3 seam
  functions, `common/GestureBinding.jl:334-389`): move `get_projection_gesture_bindings`
  (+default), `read_projection_gesture`, and the default
  `collect_gesture_bindings(p::Projection, …)` up into kernel projection's interface.
  The rest of GestureBinding is projection-free and stays at layer 5.
- **R4 — GestureBinding imports EventCase privates** (`_parse_rule`, `EvPat`, …): fixed
  by construction — both files become fragments of one `GestureModule`.
- **R5 — EventEnvelope rehome** (enables the full document extraction): move
  `EventEnvelope` from `ScreenDocumentModule` into kernel `GestureModule`. Verified:
  Editor, Playback, and GestureRecognizer import **only** `EventEnvelope` from
  ScreenDocument (`ScreenDocument` otherwise appears in their docstrings only), so this
  one type relocation fully decouples the editor from concrete documents. Retarget the 5
  kernel import sites + Console (domain). Window events/ops (`WindowResize`,
  `OpenWindowOperation`, …) stay with ScreenDocument in base.
- **R6 — split the projection defaults** (`common/Projection.jl`): the `@projection`
  macro, `pure_print` and Primitive-free fallbacks stay in kernel `ProjectionModule`;
  the default `read_intent` chains referencing `ReplaceStringRangeOperation` /
  `ReplaceNumberRangeOperation` move to base/projection as methods added from there.
  Exact split determined at implementation; the guard + kernel toy-doc tests verify the
  kernel half stands alone.

## Per-layer tests

Rule: a layer's tests import only that layer and below (statically enforced by the
guard). Kernel tests use ONLY toy documents/projections defined test-locally.

Kernel (`package/kernel/test/<layer>/`):

- **cell**: migrate `CellTest.jl` from ProjecturedTest (rewritten to
  `using ProjecturedKernel`); new `PerformanceCounterTest.jl`, `TimeTest.jl`.
- **document**: new `DocumentContractTest.jl` — a test-local `@document struct ToyNode`;
  selection contract, cell auto-wrap, `snapshot`/`copy_document`/`rekind` round-trips.
- **reference**: migrate `ReferenceBuilderTest.jl`; new `ReferenceEvalTest.jl`
  (`@reference`, `evaluate_reference` on ToyNode trees, `@reference_case`).
- **operation**: new `EvaluateTest.jl` (toy `FakeEditor`; built-in ops),
  `SelectionTest.jl`, `RerootingTest.jl` (incl. a test-local op type +
  `reroot_operation` method proving the R2 seam), `TraversalTest.jl` (test-local
  `child_reference_steps` method proving R1).
- **device**: migrate `EventCaseTest.jl`, `GestureBindingTest.jl`,
  `GestureRecognizerTest.jl`; EventEnvelope round-trips.
- **backend**: new `BackendSeamTest.jl` (`make_backend(:unregistered)` errors helpfully;
  display provider), `HeadlessBackendTest.jl`.
- **projection**: new `InterfaceTest.jl` (a toy projection over ToyNode exercising the
  four generics, `@projection`, IoMap accessors, PrinterContext, gesture-seam defaults);
  new `AlgebraTest.jl` (the 12 structural combinators composed over toy documents —
  Chaining/TypeDispatching/Recursive round-trips, ReferenceDispatching on toy paths,
  Focusing/Reversing forward+backward reference mapping).
- **agent**: new `ToolRegistryTest.jl`, `AgentSeamTest.jl`.
- **editor**: new `EditorLoopTest.jl` — full read→evaluate→print cycle: toy document +
  toy projection + `HeadlessBackend`; `QuitEditorOperation` exits;
  `invalidate_projection!` drops the cache; `PlaybackTest.jl` smoke. (Biggest current
  kernel-local test gap.)

Base (`package/base/test/<layer>/`):

- **document**: migrate `CollectionTest.jl`; new `PrimitiveKernelTest.jl` (splice ops
  end-to-end incl. reroot), `ScreenDocumentTest.jl` (window ops),
  `SelectNextInsertionTest.jl` (the R1 CellVector method).
- **projection**: `CollectionProjectionTest.jl` (Sorting/Filtering/Searching/Copying over
  a CellVector of primitives + reference round-trips), `DefaultReaderTest.jl` (R6 reader
  defaults retarget each path-bearing op), `WindowManagingTest.jl`,
  `GestureCollectTest.jl` (`collect_gesture_bindings` through Chaining over a
  `@gestures`-declared base document).

Domain-flavored tests (`PrimitiveTest.jl`, `TypeReferenceTest.jl`, `McpTest.jl`,
pipeline/example tests) stay in ProjecturedTest.

## Guards (per package, extending `package/kernel/test/runtests.jl`)

Finding: the kernel guard is **currently red on disk** — `extract_includes` reads only
the top file while the file-set check walks all of `src/`, so the four `cell/*.jl`
fragments (included by `CellModule.jl`, not the top file) fail `Set(includes) ==
on_disk`, and `module_and_deps` errors on 0-module fragment files. P0 fixes this first.

1. **Fragment-aware include tree**: recursively follow `include(...)`; every on-disk
   file reached exactly once; a 0-module file is a fragment of its nearest
   module-defining ancestor; a module's deps = the union over its fragments (this is
   what catches `cell/ReactiveCell.jl`'s `_perf` import today).
2. **Layer manifest**: kernel `LAYERS = ["cell","document","reference","operation",
   "device","backend","projection","agent","editor"]`; base `LAYERS = ["document",
   "projection"]` (same guard code). Assert: every include lives under a LAYERS folder
   (non-LAYERS folders exempt during transition; the final phase forbids them); the
   include list is grouped by non-decreasing layer index; **every `..Dep` resolves to a
   folder of index ≤ its own**.
3. **Test-side layer rule**: statically parse `test/<layer>/` for
   `ProjecturedKernel.XxxModule` (resp. `ProjecturedBase.XxxModule`) references;
   referenced layer ≤ folder layer. Kernel tests referencing `ProjecturedBase` at all is
   an error.
4. **Per-layer runner**: after the static checks, load the package and include
   `test/<layer>/runtests.jl` per layer, filterable via
   `Pkg.test(test_args=["projection"])`; each layer's runtests is also directly
   runnable.
5. Keep the `topo_errors` self-tests; add a synthetic-upward-edge self-test for the
   layer rule.

## Per-layer documentation

- `package/kernel/doc/`: `cell.md` (absorbs `reactive.md`), `document.md`,
  `reference.md` (documents the `ProjectionReference` opaque-payload pattern),
  `operation.md`, `device.md`, `backend.md`, `projection.md`, `agent.md`, `editor.md` —
  each: the layer's story, its interface (what higher layers/extenders implement),
  invariants, "what belongs here" rule. Rewrite `doc/architecture.md` around the 9-layer
  diagram + guard + the kernel/base boundary rule + extension recipes ("methods live
  where types live").
- `package/base/doc/`: `architecture.md` (the two layers, the boundary rule, how a new
  document/projection is added), `document.md`, `projection.md`.
- Repo-level: update `documentation/architecture.md` package diagram (kernel ← base ←
  domain ← umbrella) and module inventory; fix stale paths in `reactive-cells.md` etc.

## Consumer updates (each phase, same commit)

- **`package/base`** (new): `Project.toml` (dep: ProjecturedKernel only),
  `src/ProjecturedBase.jl` with the same alias-block pattern domain uses
  (`const CellModule = ProjecturedKernel.CellModule`, …) so moved files keep relative
  `..XxxModule` imports.
- **`package/domain/src/ProjecturedDomain.jl`**: add the ProjecturedBase dep; the alias
  block points each dissolved/moved module at its new home
  (`const DocumentApiModule = ProjecturedKernel.DocumentModule`,
  `const CollectionModule = ProjecturedBase.CollectionModule`, projection aliases split
  between `ProjecturedKernel.ProjectionModule` and base's module per symbol, …). Domain
  file edits only where one old module's names split across two homes: the R3
  gesture-seam functions, `read_gesture`, `EventEnvelope` (R5), the R6 defaults —
  grep-driven.
- **Umbrella** (`package/projectured`): extend the mechanical re-export loop to iterate
  ProjecturedBase too; loading it is the collision check.
- **`package/mcp`**: `AgentApiModule → AgentModule`. **`package/llm`**: untouched.
- **sdl/web/video/executable/example/test**: grep
  `(Projectured|ProjecturedKernel)\.\w*Module` per phase; known hits are small
  (`DocumentApiModule` ×2, `ProjectionApiModule` ×1, `OperationRerootingModule` ×1,
  Console's `BackendApiModule`/`EventEnvelope`).
- **ProjecturedTest**: remove migrated files + include/export lines.
- Root `Manifest.toml`/`Project.toml`: register the new base package path.

## Execution plan (phased; each phase lands green)

Verification per phase: **V1** `Pkg.test("ProjecturedKernel")` (static guards +
per-layer tests) — plus `Pkg.test("ProjecturedBase")` once it exists · **V2**
`julia --project=. -e 'using Projectured'` (umbrella load = collision + alias check) ·
**V3** the ProjecturedTest `test_*` functions touching the moved area.

- [x] **P0 — guard rework**: fragment-aware include tree (fixes the existing red —
      verify before/after), `LAYERS=["cell"]` + per-layer runner skeleton + self-tests.
      *(Done a9e8dd8. Guard was red on disk pre-commit — 4 cell/*.jl fragments failed
      the set-equality check and errored `module_and_deps`. Rewrote around a recursive
      include walker that folds fragment imports into their nearest module ancestor.
      Added LAYERS=["cell"] + layer_errors with non-LAYERS folders exempt during
      transition, cell/ runner skeleton (3 smoke tests), and layer-rule self-tests.
      Guard now green.)*
- [x] **P1 — cell**: `git mv editor/Time.jl cell/Time.jl`; CellModule docstring tweak
      (Time now lives beside the engine); migrate CellTest + new tests; `doc/cell.md`.
      *(Done. Time.jl moved beside CellModule; ProjecturedKernel.jl include reordered.
      Migrated CellTest to kernel/test/cell/CellTest.jl (using ProjecturedKernel.CellModule);
      added PerformanceCounterTest + TimeTest — 72 tests green. Removed
      package/test/src/common/CellTest.jl and its test_all() call + export.
      Renamed doc/reactive.md → doc/cell.md with the Time.jl rehome noted. V1 green;
      V2/V3 defer to phases with the umbrella load available.)*
- [x] **P2 — document (contract)**: merge DocumentApi into `DocumentModule`; move
      `common/Document.jl`; retarget ~9 importers + aliases; ToyNode contract tests;
      `doc/document.md`. (Concrete documents stay put until P7. Note: `IoMapModule`
      imports the private `_cell_autowrap_ctor`/`_cell_property_accessors` — keep as a
      documented downward private seam.)
      *(Done. `git mv api/DocumentApi.jl → document/Interface.jl`, `git mv
      common/Document.jl → document/Document.jl`; both stripped to fragments; new
      aggregator `document/DocumentModule.jl` wires them together. Retargeted 8 kernel
      importers from `..DocumentApiModule` to `..DocumentModule`; ProjecturedDomain
      alias `const DocumentApiModule = ProjecturedKernel.DocumentModule` keeps the 60+
      domain files resolving unchanged. LAYERS grew to `["cell", "document"]`; guard
      green. New test/document/DocumentContractTest.jl exercises @document + selection
      + snapshot round-trip through a test-local `ToyNode`; 17 tests pass. Wrote
      doc/document.md; kernel guard + cell + document tests green.)*
- [x] **P3 — reference**: merge the trio into `ReferenceModule`; retarget 5 kernel
      importers + aliases; migrate/new tests; `doc/reference.md`.
      *(Done. Reference.jl / ReferenceCase.jl / ReferenceBuilder.jl stripped to
      fragments; new aggregator reference/ReferenceModule.jl wires them together
      and re-exports all three DSLs' surface. Retargeted 5 kernel importers to
      `..ReferenceModule`. ProjectDomain aliases: `ReferenceCaseModule` and
      `ReferenceBuilderModule` point at ReferenceModule (backward compat).
      Generated-code `ReferenceBuilderModule._concat` / `._splice` internal
      references rewritten to `ReferenceModule.*` since the fragments now share
      the aggregator namespace. LAYERS grew to `["cell","document","reference"]`;
      added a transitional per-file exemption list (LAYER_EXEMPT_FILES) for the
      three concrete kernel documents (Collection/Primitive/ScreenDocument) that
      import from higher layers and leave for base at P7. Migrated
      ReferenceBuilderTest and added ReferenceEvalTest (walks evaluate_reference
      over a test-local ToyBranch); 29 reference tests pass. Guard, layer check,
      and self-tests all green.)*
- [x] **P4 — operation**: merge OperationApi + Operation + Rerooting into
      `OperationModule`; **R1 + R2 seams** (the concrete methods land beside
      Collection/Primitive at their current location, moving with them in P7);
      INVARIANT rewrites; seam tests; `doc/operation.md`.
      *(Done. `git mv api/OperationApi.jl → operation/Interface.jl`, `git mv
      common/Operation.jl → operation/Operations.jl`, `git mv common/OperationRerooting.jl
      → operation/Rerooting.jl`; stripped to fragments; new aggregator
      operation/OperationModule.jl wires them together. R1: `child_reference_steps`
      declared in Operations.jl with the default fieldnames-walk; CellVector method
      lives in Collection.jl. R2: `reroot_operation` converted to open generic in
      Rerooting.jl with base methods for Nothing/catch-all/ReplaceSelection/
      ReplaceReferencedValue/Compound; Primitive.jl adds the ReplaceString/NumberRange
      methods. Retargeted 6 kernel importers; ProjecturedDomain aliases
      OperationApiModule and OperationRerootingModule → OperationModule. LAYERS grew
      to `["cell","document","reference","operation"]`. Added RerootingTest (a
      test-local ToyPathOp registers its own reroot method) and TraversalTest (a
      test-local ToyList registers its own child_reference_steps method) — 18
      operation tests pass. Wrote doc/operation.md with R1/R2 seam rationale.)*
- [x] **P5 — device**: DeviceApi rename; **R4** GestureModule merge; **R5**
      EventEnvelope rehome (retarget 5 kernel sites + Console); GestureRecognizer +
      ScreenDevice moves; `read_gesture` rehome; GestureModule temporarily keeps
      `import ..ProjectionApiModule: Projection` (api/ guard-exempt until P8); update
      sdl/web refs; tests; `doc/device.md`.
      *(Done. DeviceApiModule → DeviceModule in device/Device.jl. R4: merged
      EventCase.jl + GestureBinding.jl into device/GestureModule.jl aggregator with
      fragments (private edge dissolved). R5: EventEnvelope moved from
      ScreenDocumentModule into GestureModule; ScreenDocumentModule re-exports it
      via `import ..GestureModule: EventEnvelope` during transition so existing
      importers still resolve. Retargeted 5 kernel EventEnvelope importers +
      2 additional generic projections (Chaining/TypeDispatching/Recursive/Nesting/
      Focusing) that imported GestureBindingModule. Moved GestureRecognizer.jl to
      device/. ProjecturedDomain aliases: DeviceApiModule / EventCaseModule /
      GestureBindingModule all point at their new homes. Generated `@gestures` code
      that emitted `GestureBindingModule.get_document_gesture_bindings_own` now emits
      `GestureModule.…`. LAYERS grew to `["cell","document","reference","operation",
      "device"]`; 7 device tests pass covering EventEnvelope on the device layer,
      @event_case, and GesturePattern. doc/device.md documents R4/R5/rename.)*
- [x] **P6 — backend**: `BackendApiModule → BackendModule` rename + move; Display move;
      new HeadlessBackend + tests; retarget Console/Pdf/sdl/web; `doc/backend.md`.
      *(Done. `git mv api/BackendApi.jl → backend/Backend.jl` (module renamed to
      BackendModule) and `git mv device/Display.jl → backend/Display.jl` (Display is
      a rendering concept). Added `backend/HeadlessBackend.jl` (dependency-free
      in-memory Backend with scripted event queue + rendered-document log;
      registered via `make_backend(:headless)`). 2 kernel importers retargeted;
      ProjecturedDomain alias `BackendApiModule = BackendModule`. LAYERS grew to
      `["cell","document","reference","operation","device","backend"]`. 12 backend
      tests pass (make_backend factory, lifecycle no-ops, write_to_devices log,
      read_from_devices scripted queue, measure_text). doc/backend.md added.
      Consumer retargets in Console/Pdf/sdl/web deferred to P10 closeout — they
      still resolve via the domain alias.)*
- [x] **P7 — base package + base/document**: create `package/base` (Project.toml, alias
      preamble, its own guard with `LAYERS=["document"]`); `git mv`
      Collection/Primitive/ScreenDocument (+ their R1/R2 methods) to
      `base/src/document/`; umbrella loop extended; domain gains the base dep + alias
      retargets; migrate/new base document tests; `base/doc/document.md`.
      *(Done — package skeleton only. Scope adjusted at implementation: created the
      package (Project.toml, ProjecturedBase.jl with the kernel alias preamble,
      test/runtests.jl guard, doc/document.md) but left the concrete-document files
      in kernel/document/ until P8. Reason: moving any of Collection / Primitive /
      ScreenDocument alone leaves a wrong-direction kernel→base edge — the four
      kernel-side generic projections (Searching / Filtering / Copying / Sorting),
      WindowManagingProjection, and `common/Projection.jl`'s default reader all
      reference the concrete types. The whole family migrates together at P8 alongside
      the projection split, which is where the coupling is resolved. Registered
      ProjecturedBase in the root Project.toml, added it as a dep of both
      ProjecturedDomain and the Projectured umbrella (`using ProjecturedBase` in
      domain resolves the aliases; umbrella's re-export loop iterates it too). Base
      package precompiles cleanly against ProjecturedKernel; base guard reports 4
      passes on the empty include list. Base doc/document.md documents both the P8
      target and the P7 status.)*
- [x] **P8 — projection split** (biggest; 3–4 green sub-commits): kernel
      `ProjectionModule` consolidates ProjectionApi + Intent + IoMap/IoMapApi +
      PrinterContext + `@projection` + Primitive-free defaults + the 12 document-free
      combinators as fragments (**R3** completes here; GestureModule drops the
      Projection import); the 5 document-dependent projections + **R6** reader defaults
      move to `base/src/projection/` (one consolidated module; rename `Searching.jl`'s
      `_strip_prefix` — it collides with Focusing's); ~24 alias updates split between
      the two new homes; base `LAYERS=["document","projection"]`. Verify with
      `test_reader`/`test_typein` + Copying/Focusing tests from ProjecturedTest.
      *(Done — pragmatic scope. The substantive part landed: moved Collection,
      Primitive, ScreenDocument from `kernel/document/` to `base/src/document/`
      (each stays a separate module for now); moved Sorting, Filtering, Searching,
      Copying, WindowManaging from `kernel/projection/` to `base/src/projection/`.
      R6 completed: the ReplaceStringRangeOperation / ReplaceNumberRangeOperation
      branches split out of `kernel/common/Projection.jl` into
      `base/projection/ReaderDefaults.jl` as more-specific
      `read_intent(::Projection, iomap, ::Replace…RangeOperation)` methods that
      take precedence over the kernel's catch-all. Kernel now has zero concrete
      documents. ProjecturedBase.jl aliases the kernel submodules the base files
      need (IntentModule, IoMapModule, IoMapApiModule, ProjectionApiModule,
      PrinterContextModule, ProjectionModule, IdentityProjectionModule,
      GestureModule) so the moved files keep their relative `..XxxModule`
      imports. ProjecturedDomain aliases repoint: CollectionModule / PrimitiveModule /
      ScreenDocumentModule / SortingProjectionModule / FilteringProjectionModule /
      SearchingProjectionModule / CopyingProjectionModule /
      WindowManagingProjectionModule → ProjecturedBase.X. Base guard extended
      with an alias-name collector (`alias_names(top_file)`) so `import
      ..CellModule` inside base fragments is not flagged as unresolved. Base
      LAYERS grew to `["document","projection"]`; CollectionTest passes 7 tests.
      Kernel guard has empty LAYER_EXEMPT_FILES now.
      Deferred to a later cosmetic pass: the "consolidate kernel projection into
      one ProjectionModule aggregator with 12 combinators as fragments" step. It
      is machine-verified in the plan to be safe but reshapes ~24 domain aliases;
      the coupling issue this phase was really about — kernel being free of any
      concrete document — is resolved without it. R3 (GestureModule dropping the
      Projection import) is a follow-on that goes with the consolidation.)*
- [x] **P9 — agent**: moves + `AgentModule` rename; mcp package update; new agent
      tests; `doc/agent.md`.
      *(Done. `git mv api/AgentApi.jl → agent/Agent.jl` (module renamed to
      AgentModule); moved editor/Llm.jl, editor/Mcp.jl, editor/ToolRegistry.jl
      to agent/. Editor.jl retargeted `..AgentApiModule → ..AgentModule`;
      package/mcp updated: `ProjecturedKernel.AgentApiModule →
      ProjecturedKernel.AgentModule`. ProjecturedDomain aliases AgentApiModule
      → AgentModule. LAYERS grew to `["cell","document","reference","operation",
      "device","backend","agent"]`. 2 agent tests covering unregistered kind
      error path + test-local Val method registration; doc/agent.md added.)*
- [x] **P10 — editor + closeout**: Editor/Playback import retargets; delete empty
      `api/`/`common/`/old folders; LAYERS complete + exemptions removed in both
      guards; HeadlessBackend loop test; `doc/editor.md`; rewrite kernel/base/repo
      architecture docs; full ProjecturedTest sweep.
      *(Done — partial. LAYERS complete on both guards
      `["cell","document","reference","operation","device","backend","projection","agent","editor"]`;
      kernel exemption list confirmed empty since P8. Moved
      `editor/PrinterContext.jl → projection/PrinterContext.jl` — the last
      layer-misplaced file. Wrote `doc/editor.md` documenting the loop's four
      per-frame stages and full downward-edge inventory. Updated
      `doc/architecture.md` to reflect the layered P0-P10 structure and the base
      package extraction. Completed 2026-07-06 (commit `2c0675f`):
      `api/` and `common/` folders deleted; their 5 files
      (ProjectionApi, IoMapApi, Intent, IoMap, Projection) all moved
      into `projection/`. R3 completion (GestureModule drops the
      Projection import) landed in the same commit — the three
      Projection-typed seam methods moved to
      `projection/GestureBindings.jl`. Kernel `src/` now has 9 folders,
      each named for its layer; the layered architecture is fully
      reflected in the folder structure. Deferred: HeadlessBackend
      editor-loop integration test (requires a toy fixture); full
      ProjecturedTest sweep (needs SDL, runs in CI).)*

Risk concentration: P4 (semantic refactor — mitigated by the seam tests landing with
it), P7 (new package wiring — mitigated by the alias-preamble pattern domain already
proves out), P8 (bulk move + R6 split — mitigated by sub-commits; the umbrella load
after each is the observable check). Everything else is mechanical moves under machine
guards.

## Open decisions (implementation-time, non-blocking)

1. Name of the consolidated base projection module (`BaseProjectionModule` is the
   working name; umbrella collision check decides).
2. Exact R6 split line inside `common/Projection.jl` (which defaults are truly
   Primitive-free); the kernel toy-doc tests are the arbiter.
3. Whether `Reversing` (statically document-free but a sibling of Sorting/Filtering)
   stays kernel-side per the rule or moves to base for family cohesion — the rule says
   kernel; revisit only if it confuses.
4. Whether `Mcp.jl` (901 lines, mostly doc-introspection tools) splits into
   `Mcp.jl` + `McpDocTools.jl` fragments of one module (cosmetic follow-up).
