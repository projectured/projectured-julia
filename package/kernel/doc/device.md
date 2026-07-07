# The device layer

Layer 5 of the kernel — **input devices, events, and gestures**. Independent
sibling of the backend layer; the two abstractions only come together in a
concrete implementation.

The layer lives in [main/device/](../main/device/) as a set of small modules
plus one aggregator (`GestureModule`) covering the gesture machinery:

```
Device.jl                (DeviceModule)       — Device abstract + batch I/O generics
Display.jl               (DisplayModule)      — display-size query + provider glue
Modifiers.jl             (ModifiersModule)    — the Ctrl/Shift/Alt/Meta struct
Keyboard.jl              (KeyboardModule)     — Keyboard device + key event types
Mouse.jl                 (MouseModule)        — Mouse device + mouse event types
ScreenDevice.jl          (ScreenDeviceModule) — Screen display device + WindowQuit
GestureModule.jl         (GestureModule)      — aggregator (owns rehomed EventEnvelope)
        ├─ EventCase.jl        — the @event_case macro + parser
        └─ GestureBinding.jl   — reified GestureBinding, @gestures DSL,
                                 read_gesture(::Document) interpreter
GestureRecognizer.jl     (GestureRecognizerModule) — MousePress + KeyChord synthesis
```

## DeviceModule

`DeviceModule` (`device/Device.jl`) declares the abstract *Device* type and
the batch I/O generics `write_to_devices` / `read_from_devices`. Here, the
"interface + implementation" split that would otherwise justify a separate
pure-stub module is handled by fragments sharing one module namespace
instead. `ProjecturedDomain` keeps `DeviceApiModule` as an alias for
`DeviceModule` so opt-in packages depending on the old name keep resolving.

## GestureModule

`GestureModule` aggregates two fragments that are only ever imported
together: the `EventCase` fragment (`device/EventCase.jl`) declares the
`@event_case` dispatch-table macro and its pattern parser; the
`GestureBinding` fragment (`device/GestureBinding.jl`) defines the reified
`GestureBinding` data type, the `@gestures` DSL, and the catch-all
`read_gesture(::Document, …)` interpreter. `GestureBinding` reaches into
`EventCase`'s private parser internals (`_parse_rule`, `EvPat`, …) — a
documented cross-module private edge that sharing one module namespace turns
into a plain same-namespace reference. The `@gestures` DSL and `@event_case`
DSL share the same parser without any private cross-module import; generated
`@gestures` expansions emit `GestureModule.get_document_gesture_bindings_own`.

## EventEnvelope

`EventEnvelope` wraps every backend event with the id of the window it came
from. It lives in `GestureModule`, not in the concrete `ScreenDocumentModule`
document, because it is a protocol type consumed by the editor loop, the
gesture recognizer, and the envelope-unwrapping projection — a plain struct
declaration for a protocol type has no business living inside a concrete
document; keeping it here means the kernel has no edge onto `ScreenDocument`.
`ScreenDocumentModule` re-exports the name via an `import ..GestureModule:
EventEnvelope` block, so existing importers resolve either way. Window
*events/ops* (`WindowClose`, `WindowResize`, `OpenWindowOperation`,
`CloseWindowOperation`, `ResizeWindowOperation`) stay with `ScreenDocument` in
`visual` — those *are* concrete document types, and belong with the document.

## GestureRecognizer

`GestureRecognizer.jl` (`device/GestureRecognizer.jl`) synthesises
`MousePress` from a MouseDown/MouseUp pair within a click threshold and
`KeyChord` from a KeyDown sequence — a pure function of device events plus
`EventEnvelope`, with no editor or document coupling; its location in
`device/` matches its dependencies.

## Downward edges

- `..CellModule` (Display; nothing else).
- `..DocumentModule: Document, read_gesture` (GestureBinding fragment;
  Document is opaque payload here, `read_gesture` gets the catch-all method).
- `..ProjectionApiModule: Projection` — a documented downward private seam
  the GestureBinding fragment uses for its projection-collector fallback.
  Removed once the projection API folds into the projection layer.

That is the full import surface. No backend, no editor, no operation.
