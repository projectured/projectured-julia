# Live examples — scripted, timed example sessions (record + live playback)

> **Status: PENDING**

## Context

ProjecturEd already has two pieces that drive an example through a sequence of
gestures:

- **Headless recording** — [`record_video(document, projection, gestures, filename)`](../../program/src/backend/Sdl.jl#L1755)
  runs `projection_read → evaluate_operation → projection_print` for each
  `(event = …, hold = …)` entry and assembles BMP frames into an MP4 via ffmpeg.
  Timing is in *video time* (frame counts), so output is deterministic.
- **Live editor** — [`run!(backend, projection, document)`](../../program/src/editor/Editor.jl#L194)
  opens a real SDL window and runs the read-eval-print loop against live user
  input.

What is missing is a **named, reusable artifact** that *captures an existing
example* and pairs it with a *predefined, timed script* — so the same script can
be (a) recorded into a video and (b) replayed on a real window where the user
watches the action unfold at wall-clock speed. The script must be able to carry
**both timed events** (typed/clicked gestures, fed through `projection_read`) and
**timed operations** (domain operations injected directly, bypassing the
reader) — operations let a script express actions that aren't naturally
reachable from a single device event (seed a selection, scroll a widget, swap
the focused part, replace the document).

This enables: scripted README/demo clips, "watch it edit itself" live demos in
talks, and reproducible regression sessions that exercise both the reader and
the operation evaluator.

## Design summary

Introduce a **`LiveExample`** that bundles an existing `Example` with a
**timeline** of timed entries, plus two drivers that consume the *same*
timeline:

- `record_live_example(live, filename)` → headless MP4 (reuses `record_video`).
- `play_live_example(live)` → opens a real window and replays the timeline with
  wall-clock timing so the user sees it live.

A single timeline drives both because the entry `hold` field is *seconds* in
both worlds: in the recorder `hold` → `round(hold*fps)` frames; in the live
player `hold` → the dwell before the next entry fires.

### Timeline entry format

A timeline is a `Vector` of `NamedTuple`s; the present key selects the kind
(this mirrors the existing `(event = …, hold = …)` gesture format, so existing
gesture vectors and `make_typein_gestures` output slot in unchanged):

```julia
timeline = [
    (event     = KeyPress('h'),              hold = 0.3),   # typed/clicked gesture
    (event     = MousePress(:left, 80, 40, Modifiers()), hold = 0.5),
    (operation = ReplaceSelectionOperation(path), hold = 0.6),   # injected op (value)
    (operation = doc -> ScrollWidgetOperation(…),  hold = 0.4),  # injected op (thunk)
]
```

- **`event`** — any backend-agnostic device event (`KeyDown`, `KeyUp`,
  `KeyPress`, `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll`).
  Translated to an operation via `projection_read`, exactly like a real event.
- **`operation`** — either an `Operation` value, or a 0/1-arg `Function`
  evaluated at fire time to produce one (passed the live `document`, so the op
  can reference current state/paths). Injected straight into
  `evaluate_operation`, skipping the reader.
- **`hold`** — seconds the resulting state is shown before the next entry.

An entry with neither key (or both) is an error.

### `LiveExample` struct + registry

```julia
struct LiveExample
    name::String
    example::Example          # the captured existing example (document + projection)
    timeline::Vector          # timed entries (above)
    initial_selection         # optional ReferencePath seed (caret for typein), or nothing
    width::Int
    height::Int
    fps::Int
end
```

A `live_examples::Vector{LiveExample}` registry parallels `examples`, with a
handful of predefined scripts (see step 5) so `play_live_example("json_typein")`
and `record_live_example("json_typein", "/tmp/x.mp4")` work by name.

## Files to modify

### 1. `program/src/backend/Sdl.jl` — teach `record_video` about operation entries

Today the gesture loop only handles `entry.event`
([Sdl.jl:1795-1805](../../program/src/backend/Sdl.jl#L1795)). Generalize it so an
entry is dispatched on which field it carries:

```julia
for entry in gestures
    if haskey(entry, :operation)
        op = entry.operation isa Function ? entry.operation(document) : entry.operation
    else
        op = projection_read(projection, iomap, entry.event)
    end
    if op !== nothing
        ed = _VideoEditor(document, iomap)
        evaluate_operation(ed, op)
        document = ed.document          # pick up a whole-document swap
    end
    iomap = print_iomap(document)
    _emit_frames!(off, canvas_of(iomap), width, height, background,
                  tmpdir, frame, round(Int, entry.hold * fps))
end
```

This is backward compatible — existing callers only pass `:event` entries.
Extend the docstring to document the `:operation` entry form. No other part of
`record_video` changes (renderer, ffmpeg, `wait_for`, `initial_selection` all
stay).

### 2. `program/src/editor/Editor.jl` — `play_live!` scripted live loop

Add a driver that runs the live editor loop while firing the timeline on a
wall-clock schedule, interleaved with real input (so the user can also interact
and close the window). It reuses the existing `read!`/`evaluate!`/`print!`
methods rather than forking them.

```julia
"""
    play_live!(editor::Editor, timeline; window_id::Symbol,
               content_origin::Tuple{Int,Int}=(0,0),
               initial_hold::Real=0.5, loop::Bool=false)

Run the read-eval-print loop, firing `timeline` entries on a wall-clock
schedule. Entry i fires at `initial_hold + sum(hold[1..i-1])` seconds after
start. A `:event` entry is wrapped in `EventEnvelope(window_id, event)` and run
through `projection_read` (the same path as live input); an `:operation` entry
is injected straight into `evaluate!`. Real user input is still polled every
frame, so the user can interact and the window-close button / Escape quits.
When `loop=true` the schedule restarts after the last entry.
"""
```

Implementation sketch (one frame):

1. `read!(editor)` — real input. If it produced an operation, `evaluate!` +
   `print!` as usual (lets the user interrupt/close).
2. If `now - start ≥ schedule[next]`, apply that entry:
   - `:event` → `env = EventEnvelope(window_id, _offset_mouse(event, content_origin))`;
     `change = projection_read(editor.projection, nothing, Change(env, nothing), editor.iomap)`;
     `editor.operation = change isa Change ? change.operation : change`.
   - `:operation` → `editor.operation = entry.operation isa Function ? entry.operation(editor.document) : entry.operation`.
   Then `evaluate!(editor)`; `editor.iomap = nothing` if the op swapped the
   document root; `print!(editor)`. Advance `next` (or wrap if `loop`).
3. `sleep(0.01)`.

Exit on `QuitEditorException` (Escape / window close), same as `run!`.

`_offset_mouse` adds `content_origin` to the x/y of mouse events so a timeline
authored in **example-content coordinates** lands correctly inside the window's
content area (which sits below the title bar). Keyboard events pass through
unchanged. See the coordinate decision below.

Export `play_live!` from `program/src/Projectured.jl` alongside `run!`.

### 3. `example/src/LiveExamples.jl` — new file: `LiveExample`, drivers, registry

New file (included from `ProjecturedExample.jl`, after `Examples.jl`):

- `struct LiveExample` (above).
- `record_live_example(live::LiveExample, filename=tempname()*".mp4"; kwargs...)`
  → `record_video(live.example.document, live.example.projection, live.timeline,
  filename; width=live.width, height=live.height, fps=live.fps,
  initial_selection=live.initial_selection, kwargs...)`.
- `play_live_example(live::LiveExample; kwargs...)`:
  1. Build a **single-window scene** around the example: reuse the
     `run_example` single-example wrapping — a `ScreenDocument` holding one
     `WindowDocument(id=Symbol(live.name), width, height, content=document)` and
     the `_multi_window_projection([projection])` composed projection (so the
     SDL backend opens a real window and the output is a `ScreenDocument`).
  2. Apply `initial_selection` (lifted to a screen-rooted path, mirroring
     `run_example`'s selection lifting).
  3. `init!(SdlBackend())`, construct the `Editor`, and call `play_live!(editor,
     live.timeline; window_id=Symbol(live.name),
     content_origin=window_content_origin(...))`.
- Name-string convenience overloads for both drivers (look up in
  `live_examples`), mirroring `record_example_video`'s pattern
  ([Examples.jl:486](../../example/src/Examples.jl#L486)).
- A `live_examples` registry with a few predefined scripts (step 5).
- Builders: reuse `make_typein_gestures` for event runs; add
  `timed_operation(op; hold=…)` and `timed_event(event; hold=…)` thin
  constructors for readability.

Export `LiveExample`, `play_live_example`, `record_live_example`,
`live_examples`, `timed_event`, `timed_operation` from
[ProjecturedExample.jl](../../example/src/ProjecturedExample.jl#L88).

### 4. `example/src/ProjecturedExample.jl` — include + export

`include("LiveExamples.jl")` after the `Examples.jl` include; add the new
symbols to the export list.

### 5. Predefined live examples (in `LiveExamples.jl`)

Seed the registry with 2–3 scripts that exercise both entry kinds:

- **`json_typein`** — captures `json_example`, `initial_selection` at a string
  value caret, timeline = `make_typein_gestures("hello")` then a couple of
  `KeyDown(:right)` navigations. Pure events.
- **`json_select_and_edit`** — captures `json_example`, timeline mixes a
  `(operation = ReplaceSelectionOperation(path), …)` to jump the selection,
  then `make_typein_gestures(...)` to edit there. Demonstrates timed operations
  + events together.
- **`assistant_demo`** (optional) — reuse the
  [`record_assistant_conversation_video`](../../example/src/Examples.jl#L534)
  script as a `LiveExample` to validate the `wait_for`/async path also plays
  live.

### 6. `guide/debugging.md` — document `play_live_example` / `record_live_example`

Add a short section next to the existing `record_video` notes showing: define a
`LiveExample`, `record_live_example(live, "/tmp/x.mp4")`, and
`play_live_example(live)` to watch it on a real window.

## Key design decisions

### One timeline, two clocks

`hold` is seconds in both drivers. The recorder converts to frame counts
(`round(hold*fps)`); the live player converts to wall-clock dwell. The *same*
timeline therefore produces a video and a live session that look the same,
just one is real-time and the other deterministic frame-time.

### Mouse-coordinate parity (the one fiddly bit)

The recorder renders the example as a **bare canvas** at `width×height`, so
`MousePress(x, y)` addresses content coordinates directly. The live player runs
the example inside a real **window with a title bar**, so the content origin is
offset by the window chrome. To let a single timeline work in both:

- **Decision:** author timeline mouse coordinates in *example-content* space
  (matching the recorder). The live player adds the window's content origin
  offset (`_offset_mouse`) when synthesizing the `EventEnvelope`, so the same
  coordinates hit the same content point on screen.

This confines all offset logic to `play_live!` and keeps `record_video`
unchanged. Most demo scripts are keyboard-heavy with a few clicks, so the offset
is rarely load-bearing; if a borderless window style becomes available, the
offset collapses to `(0,0)` and the two paths converge exactly.

### Operations bypass the reader; events go through it

`:event` entries flow through `projection_read` (identical to live input — the
reader is exercised). `:operation` entries are injected straight into
`evaluate_operation`, which is the only way to script actions that have no
single-event trigger (selection seeding, scrolling, focus/part swaps, document
replacement). Operation thunks `doc -> op` are evaluated at fire time so they
can reference the current document/paths.

## What is intentionally NOT in scope

- **Pause / scrub / step controls** during live playback — v1 plays straight
  through (with optional `loop`); the user can still interact and close.
- **Recording through the windowed scene** (with chrome) — the recorder stays
  bare-canvas; parity is handled by the content-origin offset, not by
  re-rendering the recorder through a window.
- **Multi-window / multi-example live scripts** — one example per
  `LiveExample`.
- **GIF/WebM** — recording remains MP4-only (`record_video` constraint).
- **Editing the timeline in the editor** — scripts are authored in Julia.

## Verification

1. **Recorder still works + operation entries** (from `example/` env):
   ```julia
   using Projectured, ProjecturedExample
   live = live_examples[findfirst(l -> l.name == "json_select_and_edit", live_examples)]
   record_live_example(live, "/tmp/live.mp4")
   ```
   `/tmp/live.mp4` exists, non-zero, and the edit produced by the timed
   `:operation` + typein is visible. Frame count = `round(initial_hold*fps) +
   Σ round(hold_i*fps) + round(final_hold*fps)`.
2. **Backward compatibility** — `test_record_video` (in
   [VideoTest.jl](../../test/src/editor/VideoTest.jl)) still passes (only
   `:event` entries), confirming the loop generalization didn't regress.
3. **Live playback** — `play_live_example("json_typein")` opens a window, types
   "hello" into the selected value at roughly the authored cadence, and the
   window stays interactive; Escape / close quits cleanly.
4. **New test** in `test/src/editor/` (e.g. extend `VideoTest.jl`): record a
   short `LiveExample` whose timeline contains one `:operation` (a
   `ReplaceSelectionOperation`) followed by a `KeyPress`, and assert the typed
   character landed at the operation-selected path — proving operation entries
   reach `evaluate_operation` and the subsequent event reads against the updated
   state. Wire in after `test_record_video`.
