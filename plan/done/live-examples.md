# Live examples — scripted, timed example sessions (record + live playback)

> **Status: DONE** — implemented on branch `worktree-live-examples`.
> See **Implementation notes** at the end for decisions made during the work.

## Context

ProjecturEd already had two pieces that drive an example through a sequence of
gestures:

- **Headless recording** — `record_video(document, projection, gestures, filename)`
  ([Sdl.jl](../../program/src/backend/Sdl.jl)) runs `projection_read →
  evaluate_operation → projection_print` per `(event = …, hold = …)` entry and
  assembles BMP frames into an MP4. Timing is in *video time* (frame counts).
- **Live editor** — `run!(backend, projection, document)`
  ([Editor.jl](../../program/src/editor/Editor.jl)) opens a real SDL window and
  runs the read-eval-print loop against live input.

Missing was a **named, reusable artifact** that captures an existing example and
pairs it with a *predefined, timed script* — so the same script can be (a)
recorded into a video and (b) replayed on a real window where the user watches.
The script must carry **both timed events** (through the reader) and **timed
operations** (domain operations injected directly), since operations express
actions with no single device-event trigger.

## Design summary

A **`LiveExample`** bundles an existing `Example` with a **timeline** of timed
entries. Two drivers consume the *same* timeline:

- `record_live_example(live, filename)` → headless MP4 (reuses `record_video`).
- `play_live_example(live)` → opens a real window and replays the timeline at
  wall-clock speed.

A single timeline drives both because `hold` is *seconds* in both worlds:
recorder → `round(hold*fps)` frames; live player → wall-clock dwell.

### Timeline entry format

A `Vector` of `NamedTuple`s; the present key selects the kind (mirrors the
existing `(event = …, hold = …)` gesture format, so existing gesture vectors and
`make_typein_gestures` output slot in unchanged):

- `(event = <Event>, hold = <sec>)` — device event, translated via
  `projection_read` (exercises the reader, like live input).
- `(operation = <Operation|Function>, hold = <sec>)` — domain `Operation` value,
  or a `doc -> op` thunk evaluated at fire time, injected straight into
  `evaluate_operation`.

## Files modified

1. **`program/src/backend/Sdl.jl`** ✅ — `record_video`'s gesture loop now
   dispatches on `haskey(entry, :operation)`: an `:operation` entry is taken
   directly (value or `doc -> op` thunk), an `:event` entry goes through the
   reader as before. Backward compatible. Docstring extended.
2. **`program/src/editor/Editor.jl`** ✅ — added `play_live!(editor, timeline;
   window_id, initial_hold)` (scripted loop) + a bootstrap overload
   `play_live!(backend, projection, document, timeline; …)` mirroring `run!`, and
   the `_timeline_operation` helper. Exported `play_live!`.
3. **`program/src/Projectured.jl`** ✅ — re-export `play_live!`.
4. **`example/src/LiveExamples.jl`** ✅ — new file: `LiveExample` struct,
   `timed_event`/`timed_operation` builders, `record_live_example` /
   `play_live_example` (each with `LiveExample` + name-string overloads), the
   `live_examples` registry, and two predefined examples (`json_typein_live`,
   `json_select_and_edit_live`).
5. **`example/src/ProjecturedExample.jl`** ✅ — include `LiveExamples.jl` and
   export the new symbols.
6. **`guide/debugging.md`** ✅ — documented operation-carrying timeline entries
   and the new "Live examples" section.
7. **`test/src/editor/VideoTest.jl`** ✅ — added a case proving an `:operation`
   entry (`ReplaceSelectionOperation`) seeds the caret for a following `:event`
   keypress.

## Implementation notes (as built)

- **Mouse-coordinate parity is free.** The plan worried that a windowed live
  player would offset content by a title bar relative to the bare recorder
  canvas. It does not: the SDL backend uses the *native OS* window chrome, so the
  SDL drawable (the `WindowDocument` content area) starts at `(0,0)` — and
  `ScreenToScreen`'s reader routes the envelope's inner event to the content
  reader **without** modifying x/y. So a `MousePress(x, y)` hits the same content
  point in both the recorder and the live window. The planned
  `content_origin`/`_offset_mouse` machinery was dropped as unnecessary.
- **No `loop` parameter.** The plan floated an optional `loop=true`. Replaying a
  mutating timeline (e.g. typein) against an already-edited document is
  misleading, so `play_live!` does not loop; after the last entry the window
  stays live and interactive. Dropped to avoid a misleading feature.
- **`play_live!` reuses the loop primitives.** It calls the existing
  `read!`/`evaluate!`/`print!`/`perf!` methods. Each frame: poll real input;
  if no real-input operation is pending and the next scheduled entry is due
  (`time()-start ≥ fire_at[next]`), set `editor.operation` from it; then
  evaluate + print. At most one scheduled entry per frame, so each state is
  visible; real input wins a contested frame and the scheduled entry retries
  next frame. Exits on `QuitEditorException` like `run!`.
- **Drivers build fresh docs.** Both `record_live_example` and
  `play_live_example` call `example.make_document()` / `make_projection()` so a
  replay starts clean rather than reusing a possibly-edited shared instance.
- **`initial_selection` may be a path or a `doc -> path` thunk** (resolved by
  `_resolve_selection`), since end-of-string carets etc. are easiest to express
  per fresh document.
- **Predefined reference paths.** `json_typein_live` seeds
  `@reference entries[1].value.value{5}` (end of `"Alice"`) and types `" world"`;
  `json_select_and_edit_live` uses a timed `ReplaceSelectionOperation` to jump to
  `@reference entries[4].value.entries[1].value.value{11}` (`"123 Main St"`) then
  types. An end-of-string `{n}` caret is a valid *selection* even though
  `evaluate_reference` can't return a character past the end — validate seeds via
  `set_selection!`, not `evaluate_reference`.
- **Worktree manifest.** The fresh worktree's `test/Manifest.toml` lacked
  `Profile` (a dep of `ProjecturedExample`); `Pkg.resolve()` in `test/` fixed it.

## Verification (run)

- `record_live_example` for both predefined examples produced non-empty MP4s
  (operation + event entries both fire).
- `test_record_video()` passes 10/10, including the new operation-entry case
  asserting the keypress lands at the operation-seeded caret.
- The `play_live_example` scene builds and prints to a `ScreenDocument` (so the
  backend opens a real window); the loop reuses the verified read/eval/print
  primitives.

## What is intentionally NOT in scope

- Pause / scrub / step controls and timeline looping during live playback.
- Recording through the windowed scene (recorder stays bare-canvas; parity is
  inherent, see notes).
- Multi-window / multi-example live scripts (one example per `LiveExample`).
- GIF/WebM (recording remains MP4-only).
