# The device layer

Layer 5 of the kernel — **input devices, events, and gestures**. Independent
sibling of the backend layer; the two abstractions only come together in a
concrete implementation.

The layer lives in [src/device/](../src/device/) as a set of small modules
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

Kernel plan P5 restructured this layer around three refactors:

## DeviceApiModule → DeviceModule (P5 rename)

The old `api/DeviceApi.jl`'s `DeviceApiModule` — the *Device* abstract type and
the batch I/O generics `write_to_devices` / `read_from_devices` — was renamed to
`DeviceModule` and moved into `device/Device.jl`. The `api/` tier's remaining
files are being dissolved into their owning layers phase by phase; the
"interface + implementation" split that used to justify the tier is now
handled by fragments sharing a module namespace. `ProjecturedDomain` keeps
`DeviceApiModule` as an alias so opt-in packages keep resolving.

## R4 — GestureModule merge

`EventCaseModule` (`device/EventCase.jl`) declared the `@event_case`
dispatch-table macro and its pattern parser. `GestureBindingModule`
(`common/GestureBinding.jl`) defined the reified `GestureBinding` data type,
the `@gestures` DSL, and the catch-all `read_gesture(::Document, …)` interpreter.
The two were only ever imported together, and `GestureBindingModule` reached
into `EventCaseModule`'s private parser internals (`_parse_rule`, `EvPat`, …)
— a documented cross-module private edge.

R4 merges both files into fragments of one `GestureModule`. The private edge
becomes a plain same-namespace reference; the `@gestures` DSL and
`@event_case` DSL share the same parser without any private cross-module
import. Generated code that used `GestureBindingModule.get_document_gesture_bindings_own`
in `@gestures` expansions now emits `GestureModule.…`.

## R5 — EventEnvelope rehome

`EventEnvelope` wraps every backend event with the id of the window it came
from. Before P5 it lived in `ScreenDocumentModule` — a **concrete document**
— but was imported by the editor loop, the gesture recognizer, and the
envelope-unwrapping projection. That was the last real kernel→ScreenDocument
edge in the engine; a plain struct declaration for a protocol type has no
business living inside a concrete document.

R5 moves the declaration into `GestureModule` (beside its consumers).
`ScreenDocumentModule` re-exports the name via an `import ..GestureModule:
EventEnvelope` block, so existing importers still resolve during transition;
they retarget to `..GestureModule` phase by phase. Window *events/ops*
(`WindowClose`, `WindowResize`, `OpenWindowOperation`, `CloseWindowOperation`,
`ResizeWindowOperation`) stay with `ScreenDocument` in base at P7 — those
*are* concrete document types, and belong with the document.

## GestureRecognizer moved into device/

`editor/GestureRecognizer.jl` synthesises `MousePress` from a MouseDown/MouseUp
pair within a click threshold and `KeyChord` from a KeyDown sequence — a
pure function of device events plus `EventEnvelope`, with no editor or
document coupling. Moved to `device/GestureRecognizer.jl` in P5 so its
location matches its dependencies.

## Downward edges

- `..CellModule` (Display; nothing else).
- `..DocumentModule: Document, read_gesture` (GestureBinding fragment;
  Document is opaque payload here, `read_gesture` gets the catch-all method).
- `..ProjectionApiModule: Projection` — a documented downward private seam
  the GestureBinding fragment uses for its projection-collector fallback.
  Removed when P8 folds the projection API into the projection layer.

That is the full import surface. No backend, no editor, no operation.
