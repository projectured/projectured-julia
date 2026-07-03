# Kernel Naming Consistency

Inventory of every exported name in the kernel package, plus a review of naming
inconsistencies and a proposed set of renames. Goal: meaningful names and
guessable naming schemes — a reader should be able to derive a name from the
concept (and vice versa) without looking it up. Idiomatic-Julia brevity is
explicitly not a goal.

---

## Naming rules to adopt

1. **Module = filename + `Module`.** Grep-by-guess must work in both directions.
2. **`Api` is a layer marker.** Every `api/X.jl` defines `XApiModule` — not just
   the ones that happen to clash with a `common/` twin.
3. **Projection stem rule.** From one stem derive all names: file `<Stem>.jl`,
   type `<Stem>Projection`, module `<Stem>ProjectionModule`, iomap
   `<Stem>ProjectionIoMap`. The stem answers a different question per folder:
   `generic/` stems are gerunds saying what the projection does to the
   *document* (Copying, Filtering, Sorting); `higherorder/` stems are gerunds
   saying what it does with its *child projections* (Chaining, Switching,
   TypeDispatching). Two exceptions: the degenerate projections take the
   standard math nouns (Identity, Constant), and Recursive stays a
   grandfathered adjective ("Recursing" is awkward, "Recursive" is
   universally understood).
4. **Operations are verb-first + `Operation` suffix**, no exceptions
   (`ReplaceSelectionOperation`, not `NumberReplaceRangeOperation`).
5. **One event shape: `<Source><Action>`**, suffixless and tenseless —
   `KeyDown`, `MouseLeave`, `WindowClose`, `WindowResize`. An event reports
   what the user/system did, never what should happen in response; the
   response is the reader's job, expressed as a verb-first `*Operation`
   (`WindowClose` event in, `CloseWindowOperation` out). The noun-first vs
   verb-first word order alone separates events from operations. Note the
   close/quit events are *requests* the app may refuse — say so in the
   docstrings since the names no longer do. If a completed counterpart ever
   appears, the request keeps the plain name and the completion takes a
   non-synonymous stem (e.g. `WindowDestroy`); never distinguish the two by
   docstring alone.
6. **Every function name starts with a verb.** Getters are `get_<stem>`,
   pairing with their `set_<stem>!` twins (`get_selection` / `set_selection!`).
   Protocol functions are verb + the unit that flows in, with dispatch
   carrying the subject: `print_document(projection, …)`,
   `read_intent(projection, iomap, intent)`, `read_gesture(document,
   gesture)`, `evaluate_operation(operation, …)` — the read-evaluate-print
   loop stays visible in the verbs themselves, just as in the REPL. The only
   blessed non-verb shapes: `with_<stem>` derived copies (`with_property`),
   DSL words (`when`, `prefix` in `@reference_case`), and declarative macros
   (`@document`, `@gestures`) — a macro is a DSL keyword, not an action.
7. **No abbreviated words inside names** (`val`, `fn`, `ref`, `op`, `perf`,
   `eval`). Domain compounds that are names in their own right (`iomap`)
   count as words, not abbreviations.
8. **snake_case with underscores between all words** for functions and macros
   (`is_up_to_date`, not `isuptodate`; `insert_row!`, not `insertrow!`).
9. **Keep the established schemes**: `I` prefix for immutable variants of a
   type (e.g. `ICellVector` is the immutable variant of `CellVector`;
   produced consistently by the `@document` macro), `make_` factories,
   `is_` predicates, qualifier suffixes (`_own`, `_ignoring_types`).
10. **The pipeline vocabulary is a ladder of distinct kinds**: Event →
    Gesture → Intent → Operation → Document. The user acts (events); acts
    combine (gesture); readers read the intent; the intent resolves to an
    executable edit (operation); evaluation applies it to the document. No
    two rungs are synonyms — in particular the reader pipeline's carrier is
    `Intent` (the gesture plus the operation-so-far), not a second
    "edit" word.

### Target projection name set

The mnemonic: *generic stems say what happens to the document, higher-order
stems say what happens to the children, and the two trivial projections are
named after the two trivial functions.*

| generic/ (transforms the document) | higherorder/ (combines children) |
|---|---|
| CopyingProjection | ChainingProjection *(was Sequential)* |
| IdentityProjection *(was Preserving)* | SwitchingProjection *(was Alternative)* |
| ConstantProjection *(was Invariably)* | NestingProjection |
| FilteringProjection | RecursiveProjection |
| FocusingProjection | TypeDispatchingProjection |
| ReversingProjection | PredicateDispatchingProjection |
| SearchingProjection | ReferenceDispatchingProjection |
| SortingProjection | EnvelopeUnwrappingProjection |
| | WindowManagingProjection *(was WindowManager)* |

The Identity/Constant/Copying triangle is the main payoff: today Preserving,
Copying and Invariably all sound like "output resembles input"; after the
rename they read as *same object through* / *fresh copy with iomaps* /
*fixed output ignoring input*.

## Rename checklist

The full old → new mapping with reasoning is in the table at the end of this file.

- [x] **Batch 1 — module/file alignment** *(done)*: api layer markers (`AgentApiModule`,
      `BackendApiModule`, `DeviceApiModule`), `ScreenDeviceModule`,
      `LivePlaybackModule` → `PlaybackModule` and `EditorTimeModule` →
      `TimeModule` (the files keep their names — `editor/Playback.jl` and
      `editor/Time.jl` — the `editor/` folder already gives the context the
      `Live`/`Editor` prefixes were adding).
- [ ] **Batch 2 — projection stem rule**: add `Projection` to the four
      higher-order module names and the two IoMap names; rename the stems
      that break the scheme or mislead (each covers file + module + type +
      iomap): `Invariably` → `Constant`, `Preserving` → `Identity`,
      `Alternative` → `Switching`, `Sequential` → `Chaining`,
      `WindowManager` → `WindowManaging`. Also fix the Invariably/Preserving
      docstrings, which call themselves "higher-order" although they live in
      `generic/` and hold no child projections.
- [ ] **Batch 3 — operation names**: `ReplaceReferencedValueOperation`,
      `ReplaceNumberRangeOperation`, `ReplaceStringRangeOperation`.
- [ ] **Batch 4 — event names**: `WindowClose`, `WindowResize`,
      `WindowDefocus`, `WindowQuit`.
- [ ] **Batch 5 — collisions & export ownership**: `LlmBackend` → `Llm`
      (frees `Backend` to uniquely mean the platform/render backend;
      `AnthropicLlm <: Llm` reads naturally); `Document` exported from
      `api/` only; `evaluate_operation` owned and exported by `api/` only —
      `PrimitiveModule` imports the generic and adds methods without
      re-exporting it.
- [ ] **Batch 6 — function abbreviations & snake_case**: `set_value!`,
      `set_function!`, `is_up_to_date`, `reroot_reference`/`reroot_operation`,
      `insert_row!`/`insert_column!`/`delete_row!`/`delete_column!` (+ pure forms).
- [ ] **Batch 7 — core protocol verbs and the Intent rename**:
      `projection_print` → `print_document`, `projection_read` →
      `read_intent`, `projection_printer_recurse` → `print_child`,
      `document_read` → `read_gesture`, and the type `Change` → `Intent`
      (file `common/Change.jl` → `common/Intent.jl`, module `ChangeModule` →
      `IntentModule`; update the `clone-command` cross-reference to note the
      Lisp name was `command`). Each protocol function is verb + the unit
      that flows in; the `projection_` prefix disappears. Highest-churn
      batch — these are the most-implemented functions in the codebase.
      (`read_document_gesture`, `read_node_gesture`, `read_projection_gesture`,
      `matches` and `describe` were already verb-first and stay unchanged.)
- [ ] **Batch 8 — getters become `get_*`**: every noun-phrase accessor gains
      the `get_` prefix so it pairs with its `set_stem!` twin
      (`get_selection` / `set_selection!`); ~20 renames, see the table.
- [ ] **Batch 9 — remaining non-verb stragglers**:
      `start_agent_server!`/`stop_agent_server!`,
      `is_reference_equal(_ignoring_types)`, `pop_gesture!`,
      `make_child_context`, `make_copying_field_iomap`/`make_copying_element_iomap`,
      `make_scripted_*`, `reset_performance_counters!`/`record_performance!`.

### Open decisions (not yet scheduled)

- Selection verbs: `set_selection!`/`clear_selection!` (api) vs
  `replace_selection!`/`update_selection!` (OperationModule). A newcomer cannot
  guess how they differ — clarify in docstrings or rename one pair to something
  meaning-bearing.
- Collection API asymmetry: pure `insertrow`/`deleterow` exist but the column
  counterparts don't. Complete or document.
- Lisp-heritage divergence: 13 of the 17 projection stems are inherited
  verbatim from projectured-lisp; the Batch 2 stem renames (Invariably,
  Preserving, Alternative, Sequential) diverge from the original. If
  cross-repo grep-correspondence matters, `Sequential` and `Alternative` are
  the two worth reconsidering; otherwise keep a short old↔new mapping in the
  docs. (Batch 7 also diverges: Lisp's `call-printer`/`call-reader`/`command`
  become `print_document`/`read_intent`/`Intent` — the concepts and the REPL
  verbs survive, the literal names don't.)

### Resolved during discussion

- Function grammar settled (rule 6): every function name starts with a verb.
  Getters take `get_` (pairing `set_stem!`); `with_`, DSL words and
  declarative macros are the only blessed non-verb shapes. Namespace prefixes
  for functions (`perf_`, `scripted_`) are reordered verb-first rather than
  blessed. Protocol functions are verb + the unit that flows in
  (`print_document`, `read_intent`), keeping the REPL's own verbs
  read/evaluate/print; the printer/reader role nouns live on in prose and in
  types like `PrinterContext`.
- `call_printer`/`call_reader` were considered and dropped: in Julia the
  method *is* the printer (there is no separate dispatcher artifact as in
  Lisp), so "call" described the wrong side at definition sites — where these
  names are read hundreds of times. Verb + flowing unit reads correctly at
  both definition and call sites.
- `Change` → `Intent`: Change and operation were two "edit" words fighting
  over one concept while the real concept — meaning in transit — went
  unnamed. `Intent(gesture, operation = nothing)` is born unresolved and
  refined one domain inward per reader step, encoding the doctrine that a
  gesture carries no intent; discovering it is the reader's job. This
  produced the vocabulary ladder of rule 10.
- `evaluate_operation` / `evaluate_reference` stay as-is — verb-first became
  the rule, so the earlier `operation_evaluate` idea is dropped.
- `get_property` stays — the earlier idea to shorten it to bare `property`
  is reversed by the `get_` rule.
- The earlier Batch 7 (subject-first gesture readers, `document_read_gesture`
  etc.) and the `matches` → `gesture_matches` / `describe` →
  `describe_gesture` renames were the wrong direction and are withdrawn —
  those names were already verb-first.

---

## Inventory

Exported names per file, captured 2026-07-02.

## api/

### Agent.jl

```
module: AgentModule
function: make_agent_server, agent_server_start!, agent_server_stop!
```

### Backend.jl

```
module: BackendModule
type: Backend
function: init!, quit!, measure_text, make_backend, write_image, record_video,
          render_canvas, decode_image, pointer_position
```

### Device.jl

```
module: DeviceModule
type: Device
function: write_to_devices, read_from_devices
```

### Document.jl

```
module: DocumentApiModule
type: Document
function: selection, clear_selection!, set_selection!, with_selection, document_read
```

### IoMap.jl

```
module: IoMapApiModule
type: IoMap
function: iomap_projection, iomap_input, iomap_output
```

### Operation.jl

```
module: OperationApiModule
type: Operation
function: evaluate_operation
```

### Projection.jl

```
module: ProjectionApiModule
type: Projection
function: projection_print, projection_printer_recurse, projection_read,
          map_reference_forward, map_reference_backward
```

---

## common/

### Change.jl

```
module: ChangeModule
type: Change
```

### Document.jl

```
module: DocumentModule
type: Document
function: copy_document, @document, @forward, @forward_vector, @forward_map
```

### GestureBinding.jl

```
module: GestureBindingModule
type: GesturePattern, KeyPressPattern, KeyDownPattern, KeyUpPattern,
      MouseDownPattern, MouseUpPattern, MousePressPattern, MouseMovePattern,
      MouseScrollPattern, GestureBinding
function: matches, describe, document_gestures, document_gestures_own,
          instance_gestures, read_document_gesture, read_node_gesture,
          projection_gestures, read_projection_gesture, collect_gestures,
          applicable_gestures, is_help_gesture, @gestures, @gesture_set
```

### IoMap.jl

```
module: IoMapModule
type: SimpleIoMap, ChildrenIoMap, ContentIoMap
function: @iomap
```

### Operation.jl

```
module: OperationModule
type: NoOperation, ReplaceSelectionOperation, QuitEditorOperation,
      QuitEditorException, OpenWindowOperation, OpenPopupOperation,
      CloseWindowOperation, ResizeWindowOperation, ToggleCollapseOperation,
      ReplaceReferencedValue, SelectNextInsertionOperation, CompoundOperation,
      AdjustZoomOperation, AdjustFontZoomOperation
function: replace_selection!, replace_document, insert_elements, delete_elements,
          update_selection!, splice_string, splice_number, splice_value!
```

### OperationRerooting.jl

```
module: OperationRerootingModule
function: prepend_steps_to_ref, prepend_steps_to_op
```

### Projection.jl

```
module: ProjectionModule
function: @projection
```

---

## device/

### Display.jl

```
module: DisplayModule
function: display_size, set_display_size_provider!
```

### EventCase.jl

```
module: EventCaseModule
function: @event_case
```

### Keyboard.jl

```
module: KeyboardModule
type: Keyboard, KeyDown, KeyUp, KeyPress, KeyChord
function: is_ctrl, is_shift, is_alt, is_meta
```

### Modifiers.jl

```
module: ModifiersModule
type: Modifiers
```

### Mouse.jl

```
module: MouseModule
type: Mouse, MouseDown, MouseUp, MousePress, MouseMove, MouseScroll,
      MouseEnter, MouseLeave
```

### ScreenDevice.jl

```
module: ScreenModule
type: Screen, QuitEvent
```

---

## document/

### Collection.jl

```
module: CollectionModule
type: CellVector, CellMatrix, CellTable, ListNode, CollectionDocument,
      ICellVector, ICellMatrix, ICellTable, IListNode
function: left_tail, right_tail, cell_at, take_first_n,
          insertrow!, insertcol!, deleterow!, deletecol!, insertrow, deleterow
```

### Primitive.jl

```
module: PrimitiveModule
type: PrimitiveDocument, PrimitiveInsertion, PrimitiveBool, PrimitiveNumber,
      PrimitiveString, NumberReplaceRangeOperation, StringReplaceRangeOperation,
      IPrimitiveInsertion, IPrimitiveBool, IPrimitiveNumber, IPrimitiveString
function: evaluate_operation
```

### ScreenDocument.jl

```
module: ScreenDocumentModule
type: ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest,
      WindowResizeEvent, WindowFocusLost, IScreenDocument, IWindowDocument
```

---

## editor/

### Editor.jl

```
module: EditorModule
type: Editor
function: run!
```

### GestureRecognizer.jl

```
module: GestureRecognizerModule
type: GestureRecognizer
function: recognize!, next_gesture!
```

### Llm.jl

```
module: LlmModule
type: LlmBackend, AnthropicLlm, FakeLlm, ScriptedLlm
function: stream_turn, scripted_turn, scripted_think, scripted_say, scripted_run
```

### Mcp.jl

```
module: McpModule
function: execute_julia_code, last_eval_value, list_guides, read_guide,
          list_modules, list_classes, list_functions, read_module_documentation,
          read_class_documentation, read_function_documentation,
          search_documentation, search_api, register_default_tools_and_resources!
```

### Playback.jl

```
module: LivePlaybackModule
function: play_live!
```

### PrinterContext.jl

```
module: PrinterContextModule
type: PrinterContext
function: child_context, with_available_size, with_property, get_property
```

### Time.jl

```
module: EditorTimeModule
function: editor_time, reactive_editor_time, tick!
```

### ToolRegistry.jl

```
module: ToolRegistryModule
type: Tool, Resource
function: register_tool!, register_tools!, list_tools, call_tool, find_tool,
          register_resource!, register_resources!, list_resources, read_resource,
          find_resource, anthropic_tool_schema, clear_registry!
```

---

## projection/generic/

### Copying.jl

```
module: CopyingProjectionModule
type: CopyingProjection, CopyingProjectionIoMap
function: copying_field_iomap, copying_element_iomap
```

### Filtering.jl

```
module: FilteringProjectionModule
type: FilteringProjection, FilteringProjectionIoMap
```

### Focusing.jl

```
module: FocusingProjectionModule
type: FocusingProjection, ReplaceFocusPartOperation
```

### Invariably.jl

```
module: InvariablyProjectionModule
type: InvariablyProjection
```

### Preserving.jl

```
module: PreservingProjectionModule
type: PreservingProjection
```

### Reversing.jl

```
module: ReversingProjectionModule
type: ReversingProjection
```

### Searching.jl

```
module: SearchingProjectionModule
type: SearchingProjection, SearchingProjectionIoMap
```

### Sorting.jl

```
module: SortingProjectionModule
type: SortingProjection, SortingProjectionIoMap
```

---

## projection/higherorder/

### Alternative.jl

```
module: AlternativeProjectionModule
type: AlternativeProjection, AlternativeProjectionIoMap
```

### EnvelopeUnwrapping.jl

```
module: EnvelopeUnwrappingModule
type: EnvelopeUnwrappingProjection, EnvelopeUnwrappingIoMap
```

### Nesting.jl

```
module: NestingProjectionModule
type: NestingProjection, NestingProjectionIoMap
```

### PredicateDispatching.jl

```
module: PredicateDispatchingModule
type: PredicateDispatchingProjection
```

### Recursive.jl

```
module: RecursiveProjectionModule
type: RecursiveProjection
```

### ReferenceDispatching.jl

```
module: ReferenceDispatchingModule
type: ReferenceDispatchingProjection, ReferenceDispatchingIoMap
```

### Sequential.jl

```
module: SequentialProjectionModule
type: SequentialProjection, SequentialProjectionIoMap
```

### TypeDispatching.jl

```
module: TypeDispatchingModule
type: TypeDispatchingProjection
```

### WindowManager.jl

```
module: WindowManagerProjectionModule
type: WindowManagerProjection, WindowManagerProjectionIoMap
```

---

## reactive/

### PerformanceCounter.jl

```
module: PerformanceCounterModule
function: perf_counters, perf_reset!, perf_record!, @perf_time
```

### Reactive.jl

```
module: ReactiveModule
type: Cell
function: setval!, setfn!, isuptodate
```

---

## reference/

### Reference.jl

```
module: ReferenceModule
type: Reference, ReferenceStep, ElementReference, PositionReference,
      RangeReference, FieldReference, TypeReference, FunctionReference,
      ProjectionReference, PointReference, TextRectangularReference,
      ReferencePath, EmptyReferencePath, ConcreteReferencePath,
      IRangeReference, IFieldReference, IConcreteReferencePath,
      IPointReference, ReferenceTypeMismatch
function: append_reference, evaluate_reference, is_valid_reference,
          collect_references, is_element_reference, is_position_reference,
          is_range_reference, reference_equal, is_prefix_of,
          reference_equal_ignoring_types, is_prefix_of_ignoring_types,
          valid_reference_prefix, annotate_reference_types,
          strip_reference_types, fold_reference_types
```

### ReferenceCase.jl

```
module: ReferenceCaseModule
function: @reference_case, when, prefix
```

### ReferenceBuilder.jl

```
module: ReferenceBuilderModule
function: @reference, @step
```

---

## Suggested renames

| Current | Suggested | Kind | Why |
|---|---|---|---|
| `AgentModule` | `AgentApiModule` | module | `Api` marks the api layer uniformly, not only where a `common/` clash forced it |
| `BackendModule` | `BackendApiModule` | module | same |
| `DeviceModule` | `DeviceApiModule` | module | same |
| `ScreenModule` | `ScreenDeviceModule` | module | match filename `ScreenDevice.jl` |
| `LivePlaybackModule` | `PlaybackModule` | module | match filename `Playback.jl`; the `editor/` folder gives the context |
| `EditorTimeModule` | `TimeModule` | module | match filename `Time.jl`; the `editor/` folder gives the context |
| `EnvelopeUnwrappingModule` | `EnvelopeUnwrappingProjectionModule` | module | projection stem rule |
| `PredicateDispatchingModule` | `PredicateDispatchingProjectionModule` | module | projection stem rule |
| `ReferenceDispatchingModule` | `ReferenceDispatchingProjectionModule` | module | projection stem rule |
| `TypeDispatchingModule` | `TypeDispatchingProjectionModule` | module | projection stem rule |
| `EnvelopeUnwrappingIoMap` | `EnvelopeUnwrappingProjectionIoMap` | type | iomap name = projection type + `IoMap` |
| `ReferenceDispatchingIoMap` | `ReferenceDispatchingProjectionIoMap` | type | same |
| `InvariablyProjection` | `ConstantProjection` | type (+ file, module) | adverb stem hides the meaning; it emits a constant output |
| `PreservingProjection` | `IdentityProjection` | type (+ file, module) | "Preserving" vs "Copying" is unguessable; Identity = same object passes through |
| `AlternativeProjection` | `SwitchingProjection` | type (+ file, module, iomap) | misleading: a reactive index cell switches the active child, not a fallback chain |
| `SequentialProjection` | `ChainingProjection` | type (+ file, module, iomap) | combinator stems are gerunds on the children; chains printer forward, reader backward |
| `WindowManagerProjection` | `WindowManagingProjection` | type (+ file, module, iomap) | the only noun stem; fit the gerund scheme |
| `ReplaceReferencedValue` | `ReplaceReferencedValueOperation` | type | the only operation missing the `Operation` suffix |
| `NumberReplaceRangeOperation` | `ReplaceNumberRangeOperation` | type | operations are verb-first |
| `StringReplaceRangeOperation` | `ReplaceStringRangeOperation` | type | operations are verb-first |
| `WindowCloseRequest` | `WindowClose` | type | events are `<Source><Action>`, like `KeyDown`/`MouseLeave` |
| `WindowResizeEvent` | `WindowResize` | type | same |
| `WindowFocusLost` | `WindowDefocus` | type | same; parallels `MouseEnter`/`MouseLeave` |
| `QuitEvent` | `WindowQuit` | type | same; joins the window event family |
| `LlmBackend` | `Llm` | type | frees `Backend` for the render backend; `AnthropicLlm <: Llm` reads naturally |
| `Document` (exported twice) | export from `api/` only | export | one owning module per exported name |
| `evaluate_operation` (exported twice) | export from `api/` only | export | the owning module exports the generic; extenders add methods, not exports |
| `setval!` | `set_value!` | function | no abbreviated words |
| `setfn!` | `set_function!` | function | no abbreviated words |
| `isuptodate` | `is_up_to_date` | function | snake_case predicate |
| `prepend_steps_to_ref` | `reroot_reference` | function | no abbreviations; matches module name `OperationRerooting` |
| `prepend_steps_to_op` | `reroot_operation` | function | same |
| `insertrow!` / `insertrow` | `insert_row!` / `insert_row` | function | snake_case; aligns with `insert_elements` |
| `insertcol!` | `insert_column!` | function | same, plus no abbreviation |
| `deleterow!` / `deleterow` | `delete_row!` / `delete_row` | function | same |
| `deletecol!` | `delete_column!` | function | same |
| `Change` | `Intent` | type (+ file, module) | Change/operation were synonyms; Intent = gesture + operation-so-far, born unresolved |
| `projection_print` | `print_document` | function | verb + the unit that flows in; the document flows forward |
| `projection_read` | `read_intent` | function | same; the Intent flows backward |
| `projection_printer_recurse` | `print_child` | function | prints a child document through the recursion |
| `document_read` | `read_gesture` | function | leaf reader: bare gesture in, operation out |
| `selection` | `get_selection` | function | getters are `get_*`, pairing `set_*!` |
| `display_size` | `get_display_size` | function | same |
| `pointer_position` | `get_pointer_position` | function | same |
| `editor_time` / `reactive_editor_time` | `get_editor_time` / `get_reactive_editor_time` | function | same |
| `iomap_projection` / `iomap_input` / `iomap_output` | `get_iomap_projection` / `get_iomap_input` / `get_iomap_output` | function | same |
| `document_gestures` / `document_gestures_own` / `instance_gestures` / `projection_gestures` / `applicable_gestures` | `get_document_gestures` / `get_document_gestures_own` / `get_instance_gestures` / `get_projection_gestures` / `get_applicable_gestures` | function | same |
| `left_tail` / `right_tail` / `cell_at` | `get_left_tail` / `get_right_tail` / `get_cell_at` | function | same |
| `anthropic_tool_schema` | `get_anthropic_tool_schema` | function | same |
| `valid_reference_prefix` | `get_valid_reference_prefix` | function | same |
| `last_eval_value` | `get_last_evaluated_value` | function | getter + expand the `eval` abbreviation |
| `perf_counters` | `get_performance_counters` | function | getter + expand the `perf` abbreviation |
| `perf_reset!` | `reset_performance_counters!` | function | verb first; expand the abbreviation |
| `perf_record!` | `record_performance!` | function | same |
| `agent_server_start!` / `agent_server_stop!` | `start_agent_server!` / `stop_agent_server!` | function | verb first; keeps the `agent_server` stem shared with `make_agent_server` |
| `reference_equal` / `reference_equal_ignoring_types` | `is_reference_equal` / `is_reference_equal_ignoring_types` | function | predicates start with `is_` |
| `next_gesture!` | `pop_gesture!` | function | mutating action needs a verb; it consumes the pending queue |
| `child_context` | `make_child_context` | function | constructs a derived context; factories are `make_*` |
| `copying_field_iomap` / `copying_element_iomap` | `make_copying_field_iomap` / `make_copying_element_iomap` | function | factories are `make_*` |
| `scripted_turn` / `scripted_think` / `scripted_say` / `scripted_run` | `make_scripted_turn` / `make_scripted_think` / `make_scripted_say` / `make_scripted_run` | function | factories are `make_*`; verb first |
