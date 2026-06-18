# Event → Gesture → Operation pipeline

Introduce an explicit **gesture-recognition stage** between raw device events
and the projection reader pipeline. Today readers pattern-match raw events
(`KeyDown`, `MousePress`, …) directly; this plan inserts a stateful step that
maps *combinations and sequences of events* to named **gestures**, and changes
readers to match gestures instead. The operation-producing half of the readers
is unchanged — only the thing they dispatch on changes.

> Status: planning. Nothing implemented yet. This plan supersedes the implicit
> "raw event in the `Change.gesture` slot" arrangement described in
> [program/src/api/Projection.jl](../../program/src/api/Projection.jl).

---

## Motivation

The current flow ([editor.md](../../guide/editor.md), `read!`):

```
SDL → EventEnvelope(KeyDown/MousePress/…) → Change(env, nothing)
     → projection_read pipeline → Operation
```

Each leaf reader matches the raw event with `@event_case`, e.g.
[Focusing.jl](../../program/src/projection/generic/Focusing.jl):

```julia
@event_case event begin
    KeyDown(:comma;  ctrl) => …   # focus out
    KeyDown(:period; ctrl) => …   # focus in
end
```

Limits of matching raw events directly:

1. **No multi-event gestures.** A gesture is exactly one event. Chords
   (`Ctrl-K Ctrl-C`), double/triple-click, click-drag (down → move… → up),
   and press-and-hold cannot be expressed — there is nowhere to accumulate
   state across events.
2. **Recognition is already leaking into the backend.** `MousePress` (click)
   is synthesised inside the SDL backend
   ([Sdl.jl](../../program/src/backend/Sdl.jl) ~L1554–1572: down/up within
   5 px and 300 ms). That is gesture recognition living in a backend, so every
   backend must re-implement it and it is untestable without SDL.
3. **Physical keys are hard-coded in ~50 readers.** The binding "Ctrl-comma =
   move focus out" is spelled out at the reader. There is no central keymap, no
   rebinding, and the same intent is re-encoded in many places. (`@event_case`
   appears in 14 files; `projection_read` in ~60.)
4. **The `Change.gesture` slot is misnamed.** `Change(gesture, operation)`
   already calls slot 1 "gesture", but it currently carries the *raw event*.
   This plan makes the name honest: the slot carries an actual gesture.

The [gesture-help (Ctrl-?)](../tentative/gesture-help.md) plan also wants a
catalogue of "available gestures"; that only becomes well-defined once gestures
are first-class objects produced by a central recogniser rather than ad-hoc
`@event_case` arms scattered across readers.

---

## Design overview

```
SDL (raw KeyDown/KeyUp/KeyPress/MouseDown/Up/Move/Scroll)
   → GestureRecognizer  (editor-owned, stateful)   ← NEW
   → Gesture
   → Change(gesture, nothing)
   → projection_read pipeline   (now matches Gesture)
   → Operation
```

- A new **`GestureRecognizer`** is owned by the `Editor`. It consumes the raw
  `EventEnvelope` stream and emits zero or one `Gesture` per event (some events
  only advance internal state — e.g. the first key of a chord, or a `MouseDown`
  that may become a click or a drag — and emit nothing yet).
- The recogniser is **stateful** (chord buffer, pending mouse-down, click
  counter/timer, drag state). This is why it lives in the editor and not in the
  reactive projection pipeline, which is pull-based and stateless.
- The recogniser is driven by a **keymap / gesture table** so bindings are data,
  not code — rebindable and introspectable.
- Readers stop matching raw event structs and match **`Gesture`** instead. The
  `Change.gesture` slot now genuinely carries a `Gesture`.

### What is a "gesture"?

A gesture names an **input intent**, decoupled from the physical keys/buttons
that produced it, but **not** yet domain-specific (it is not an `Operation`).
The vocabulary is a shared convention between the keymap (producer) and the
readers (consumers) — analogous to command ids in Emacs/VSCode: the keymap binds
keys → command id, handlers handle command ids.

Concretely a gesture is an intent name plus a typed payload:

```julia
struct Gesture
    name::Symbol      # :navigate, :commit, :cancel, :focus_in, :insert_char, :select, :scroll, …
    data::Any         # payload: direction Symbol, char, click position+count, scroll delta, …
    source::Any       # originating raw event(s), kept for debugging / fallthrough
end
```

Examples of the intended vocabulary (final list TBD during implementation):

| Gesture name        | Produced from                              | Payload            |
| ------------------- | ------------------------------------------ | ------------------ |
| `:insert_char`      | `KeyPress(c)`                              | `char`             |
| `:delete_backward`  | `KeyDown(:backspace)`                      | —                  |
| `:delete_forward`   | `KeyDown(:delete)`                         | —                  |
| `:navigate`         | arrow / home / end (± modifiers)           | direction `Symbol` |
| `:focus_in`         | `Ctrl-.`                                   | —                  |
| `:focus_out`        | `Ctrl-,`                                   | —                  |
| `:toggle_collapse`  | `Ctrl-period`                              | —                  |
| `:commit` / `:cancel` | `Return` / `Escape`                      | —                  |
| `:select`           | single primary click                       | `x, y, count`      |
| `:context`          | secondary click                            | `x, y`             |
| `:drag`             | down → move… → up (primary)                | `from, to, phase`  |
| `:scroll`           | wheel                                      | `dx, dy, x, y`     |
| `:chord`            | a recognised key sequence                  | `Vector{Gesture}`  |

Note `:focus_in`/`:focus_out`/`:toggle_collapse` are intent names, not domain
operations — only `FocusingProjection` / `SyntaxNodeToText` choose to handle
them. The keymap may bind these without knowing which projection consumes them.

### Decision: phased semantic depth

There is a tension between two extremes:

- **Thin normalization** — gestures are barely-enriched events (`KeyGesture`,
  `ClickGesture`, `DragGesture`) carrying raw key/button info; readers still see
  `Ctrl-comma`.
- **Fully semantic** — gestures are abstract intents (`:focus_out`) and physical
  keys live only in the keymap.

**Recommendation: build thin first, add the semantic keymap second.**

- **Phase 1** introduces the gesture *layer and recognition* (clicks, drags,
  double-click, chords) but gestures still carry the normalized key/button so
  readers migrate mechanically (`@event_case` → `@gesture_case` over the same
  fields). This delivers multi-event gestures and removes backend-side click
  synthesis with minimal churn and no behaviour change.
- **Phase 2** layers a *named-intent keymap* on top (`Ctrl-, → :focus_out`) and
  migrates readers to match intent names, enabling rebinding and feeding
  [gesture-help.md](../tentative/gesture-help.md). Phase 2 is independently
  shippable and can be deferred.

This keeps each step reviewable and never leaves the tree in a broken state.

---

## Phase 1 — recognition layer (no behaviour change)

### 1. `Gesture` types — `program/src/device/Gesture.jl`

New `GestureModule`. Define `Gesture` (above) and constructors for the Phase-1
gesture set that mirrors today's matched events plus the recognised composites:
`KeyGesture(key, mods, repeat)`, `CharGesture(char, text, mods)`,
`ClickGesture(button, x, y, count, mods)`, `DragGesture(button, from, to, phase, mods)`,
`ScrollGesture(dx, dy, x, y, mods)`. Include in
[Projectured.jl](../../program/src/Projectured.jl) next to the device modules.

### 2. `@gesture_case` macro — generalize `@event_case`

[EventCase.jl](../../program/src/device/EventCase.jl) is a first-match table over
the event structs. Add a sibling `@gesture_case` (or extend `_EVENT_TYPES` to
include the gesture structs so the *same* macro matches both during migration).
Same surface syntax — only the type table grows. Keep `@event_case` working so
migration is incremental, file by file.

### 3. `GestureRecognizer` — `program/src/editor/GestureRecognizer.jl`

A mutable struct holding recognition state:

```julia
mutable struct GestureRecognizer
    pending_down::Union{MouseDown, Nothing}   # may become click or drag
    dragging::Bool
    last_click_button::Symbol
    last_click_time::Float64
    click_count::Int
    chord_buffer::Vector{KeyGesture}          # Phase 1: empty unless a chord prefix is active
    keymap::Keymap                             # Phase 2; Phase 1 can use a fixed table
end
```

Core entry point:

```julia
recognize!(rec::GestureRecognizer, env::EventEnvelope) -> Union{Gesture, Nothing}
```

- `KeyPress(c)` → `CharGesture`.
- `KeyDown(k, mods)` → `KeyGesture` (chord handling lands here in Phase 2).
- `MouseDown` → store `pending_down`, emit nothing.
- `MouseMove` while `pending_down` and past threshold → start `:drag`,
  emit `DragGesture(:begin)`; subsequent moves emit `:drag(:update)`.
- `MouseUp`:
  - if dragging → `DragGesture(:end)`;
  - else within 5 px / 300 ms of `pending_down` → `ClickGesture` with
    `click_count` (double/triple by the time/position window).
- `MouseScroll` → `ScrollGesture`.

This subsumes the SDL backend's `MousePress` synthesis (step 5).

### 4. Wire the recogniser into `Editor.read!`

In [Editor.jl](../../program/src/editor/Editor.jl) add `recognizer::GestureRecognizer`
to the `Editor` struct and change `read!`:

```julia
env = read_from_devices(...)
gesture = recognize!(editor.recognizer, env)   # may be nothing → continue draining
gesture === nothing && continue
change = projection_read(editor.projection, nothing, Change(gesture, nothing), editor.iomap)
```

`QuitEvent` keeps its current short-circuit. The `Change.gesture` slot now holds
a `Gesture`; the threading invariant (gesture preserved unchanged through the
chain) is unchanged.

### 5. Remove `MousePress` synthesis from the SDL backend

Strip the click-synthesis state and logic from
[Sdl.jl](../../program/src/backend/Sdl.jl) (`last_down_*`, `pending_events`
press injection, ~L152–156, L1554–1572). The backend now emits only raw
`MouseDown`/`MouseUp`/`MouseMove`; click/drag recognition is the recogniser's
job. (Keep `MousePress` the *type* until readers migrate, or map
`ClickGesture` ↔ the old reader expectations in step 6.)

### 6. Migrate readers `@event_case` → `@gesture_case`

For each of the 14 `@event_case` files, switch the scrutinee from the raw event
to the gesture and the arms to gesture patterns. Phase-1 gestures carry the same
fields, so this is largely mechanical:

```julia
# before
KeyDown(:comma; ctrl)        => focus_out_op
MousePress(:left, x, y)      => select_at(x, y)
# after
KeyGesture(:comma; ctrl)     => focus_out_op
ClickGesture(:left, x, y)    => select_at(x, y)
```

Priority order (highest-traffic, validates the design earliest):
`SyntaxToText` → `TextToGraphics` → `Focusing` → `PrimitiveToSyntax` /
`PrimitiveToText` → `WidgetToGraphics` → remainder. Each file migrated in its
own commit; the generic `projection_read` bridge
([common/Projection.jl](../../program/src/common/Projection.jl)) is unaffected
since it just unwraps `Change.gesture`.

### 7. Tests

- `test_cell()` unaffected.
- Add focused recogniser unit tests: down+up→click, down+move+up→drag,
  two quick clicks→double-click, wheel→scroll. Pure, no SDL.
- Re-run the existing navigation/printer/reader suites per domain as files
  migrate (`test_text_navigation(json_example)`, `test_repl(json_example)`, …).
  Behaviour must be unchanged at the end of Phase 1.

---

## Phase 2 — semantic keymap (optional, ships separately)

### A. `Keymap` type

A data structure mapping event/chord patterns → intent `Symbol` (+ a default
keymap matching today's bindings). Lives in `device/Keymap.jl`. The recogniser
consults it to label gestures: `KeyGesture(:comma; ctrl)` → `Gesture(:focus_out, …)`.

### B. Chords

With a keymap, a binding can be a *sequence* (`Ctrl-K Ctrl-C`). The recogniser's
`chord_buffer` accumulates the prefix; a partial match emits nothing (and can
surface a "pending chord" indicator), a full match emits the intent, a miss
flushes/falls back.

### C. Migrate readers to intent names

`KeyGesture(:comma; ctrl) => …` becomes `Gesture(:focus_out) => …`. Readers no
longer mention physical keys; rebinding is pure keymap data.

### D. Feed gesture-help

Implement `projection_available_gestures` (see
[gesture-help.md](../tentative/gesture-help.md)) by walking the keymap + the
readers' handled-intent sets, now that intents are first-class.

---

## Open questions

- **Gesture vocabulary granularity.** Exact Phase-1 gesture set and field
  layout (single `Gesture{name,data}` vs. one struct per gesture kind). Leaning
  to per-kind structs in Phase 1 (so `@gesture_case` field-matching stays as
  ergonomic as `@event_case`), with the `name` Symbol introduced in Phase 2.
- **Where double/triple-click thresholds live.** Recogniser constants vs.
  keymap/config. Start as recogniser constants (mirroring today's 5 px / 300 ms).
- **Drag routing.** A drag spans many frames; does each `:drag(:update)` run the
  full reader pipeline, or does the editor cache the drag target from `:begin`?
  Interacts with [dragging.md](../pending/dragging.md) — reconcile before
  implementing drags (Phase 1 can emit drag gestures but leave readers ignoring
  them until that plan lands).
- **Backend compatibility shim.** Whether to keep emitting `MousePress` from a
  thin adapter during migration, or migrate all click readers in one commit
  alongside step 5.

---

## Dependencies & related plans

- [gesture-help.md](../tentative/gesture-help.md) — consumes Phase 2 intents.
- [dragging.md](../pending/dragging.md) — the `:drag` gesture is its input;
  coordinate drag routing.
- No dependency on logging or other pending plans.
