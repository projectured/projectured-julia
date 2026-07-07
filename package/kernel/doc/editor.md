# The editor layer

Layer 9 of the kernel — the **read-eval-print loop**. Pulls together every
lower layer into the frame-by-frame drive: read from the device, evaluate the
gesture into an operation, apply the operation to the document, print the
document through the projection, tick the clock.

The layer lives in [main/editor/](../main/editor/):

```
Editor.jl    (EditorModule)    — the run_editor! loop and Editor struct
Playback.jl  (PlaybackModule)  — scripted live playback on a wall-clock timeline
```

The gesture recognizer that synthesises `MousePress` from MouseDown/MouseUp
pairs and `KeyChord` from KeyDown sequences lives in `device/` (its
dependencies are device event types + `EventEnvelope`, no editor
coupling). The global animation clock `TimeModule` lives in `cell/`
(every animated projection reads it, so it belongs beside the engine it
depends on). What's left in `editor/` is the loop and its scripted
playback.

## The loop

Every frame:

1. `read!(editor)` polls the backend's device set through `DeviceModule`.
   The gesture recognizer folds MouseDown/MouseUp into MousePress and
   KeyDown sequences into KeyChords, wrapping everything in an
   `EventEnvelope` before yielding it.
2. `evaluate!(editor, envelope)` runs the reader side of the projection
   pipeline (`read_intent`), producing an `Operation`. If the operation
   carries a reference path, `reroot_operation` prepends the
   projection's steps so the reference is rooted in the document. The
   resulting operation is applied via `evaluate_operation`.
3. `print!(editor)` runs the printer side (`print_document`) over the
   updated document; the output tree is rendered by the backend via
   `write_to_devices`.
4. `tick_editor_time!(now)` advances the animation clock, invalidating
   every cell that subscribed to `get_reactive_editor_time()`.

## Downward edges

- `..ProjectionModule` — `Projection`, `print_document`, `read_intent`,
  `Intent`, `IoMap`.
- `..DeviceModule` — `Device`, `read_from_devices`, `write_to_devices`.
- `..BackendModule` — `Backend`, `initialize_backend!`, `quit_backend!`.
- `..ScreenDeviceModule` — `Screen`, `WindowQuit`.
- `..GestureModule` — `EventEnvelope`.
- `..PerformanceCounterModule` — the counters bumped inline in the loop.
- `..TimeModule` — `tick_editor_time!`.
- `..DocumentModule` — the abstract `Document` type.
- `..KeyboardModule`, `..MouseModule` — event type predicates.
- `..OperationModule` — the operation abstract + evaluate seam.
- `..GestureRecognizerModule` — the frame's gesture folding.
- `..AgentModule` — the make_agent_server/start/stop seam driven by
  `Editor` when an agent server is configured.

That is nearly the full kernel — the editor is the layer that consumes
every other layer. Playback additionally depends on `EditorModule` (to
reuse the four sub-steps) and `OperationModule` (to preview
`reroot_operation` as scripted events replay).

## Testing

The per-layer editor test folder, [test/editor/](../test/editor/), drives
the loop against the dependency-free `HeadlessBackend` from the backend
layer — one place the loop can be exercised without any real backend
package, and the biggest current kernel-local test gap.
