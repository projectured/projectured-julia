# Kernel Naming Consistency

Inventory of every exported name in the kernel package, grouped by file.
Use this as a reference when auditing or enforcing consistent naming conventions
across modules, types, and functions.

---

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
