# Event → Gesture → Operation pipeline

> **Retired 2026-06-24 — merged into
> [reified-gesture-bindings.md](../pending/reified-gesture-bindings.md).** That plan
> is now the single umbrella for the whole gesture pipeline (recognition + reified
> mapping + gesture-help); the recognition half lives there as **Stage 0**. This
> document is kept as the **full recogniser design record** (motivation, the
> "a gesture carries no intent" refinement, the recogniser contract, and the
> per-kind-gesture / `@gesture_case` direction that was *not* taken — superseded by
> `GesturePattern` + `@gestures` reification). Implemented and done: the recogniser
> spine, click-synthesis-out-of-backend, multi-click (`MousePress.count`), and key
> chords (`KeyChord`). The **only open item is drag** (Phase 2 C below), which is
> tracked in reified-gesture-bindings.md Stage 0 and remains blocked on
> [dragging.md](dragging.md). Nothing here is active work; consult
> reified-gesture-bindings.md for status.

Introduce an explicit **gesture-recognition stage** between raw device events
and the projection reader pipeline. Today readers pattern-match raw events
(`KeyDown`, `MousePress`, …) directly; this plan inserts a stateful step that
maps *combinations and sequences of events* to gestures.

> This plan supersedes the implicit "raw event in the `Change.gesture` slot"
> arrangement described in
> [program/src/api/Projection.jl](../../program/src/api/Projection.jl).

> **Conceptual refinement (2026-06-24).** A gesture is **just a combination or
> sequence of raw events — it carries no intent.** A mouse click is a gesture
> because its native events are a button *down* + *up*; a key chord like
> `Ctrl-C Ctrl-K` is a gesture because it is two key presses combined. What a
> gesture *means* (which operation it triggers) is decided by the **projection**,
> never by the gesture itself. This retires the earlier "gesture = named input
> intent" / "semantic keymap" framing: there is **no layer between the recogniser
> and the readers that assigns intent**. The recogniser's job is purely to
> recognise event combinations; intent assignment is, and stays, distributed
> across the projection readers (each projection decides what a given gesture
> means in its context). The already-implemented recogniser — passing single
> events through and only *adding* the click composite — is exactly this thin,
> intent-free shape. See [What is a "gesture"?](#what-is-a-gesture) and the
> revised Phase 2 below.

## Implementation status (2026-06-18)

> **Audit 2026-06-23 (verified against current `package/` tree).** All four ✅
> claims below re-confirmed in code after the restructure; the three ⏳ items are
> still OPEN (not done). Path mapping for the audit:
> - `program/src/editor/GestureRecognizer.jl` → `package/kernel/src/editor/GestureRecognizer.jl`
> - `program/src/editor/Editor.jl` → `package/kernel/src/editor/Editor.jl`
> - `program/src/backend/Sdl.jl` → `package/sdl/src/ProjecturedSdl.jl`
> - `test/src/editor/GestureRecognizerTest.jl` → `package/test/src/editor/GestureRecognizerTest.jl`
>
> Evidence summary: `GestureRecognizer`/`recognize!`/`next_gesture!` defined at
> `package/kernel/src/editor/GestureRecognizer.jl:66,99,133`; wired into `Editor`
> (`recognizer::GestureRecognizer` field at `Editor.jl:51`, `next_gesture!` call
> in `read!` at `Editor.jl:82`); SDL backend has **no** `MousePress(` construction
> (synthesis removed — only doc comments remain, `ProjecturedSdl.jl:172,1911`);
> recogniser test present and registered (`GestureRecognizerTest.jl`, included at
> `package/test/src/ProjecturedTest.jl:89`). No `Gesture.jl`, no `@gesture_case`,
> no `KeyGesture/ClickGesture/...` structs anywhere; `@event_case` still used in
> ~14 reader files (deferred steps 1/2/6 confirmed OPEN).

**The recognition-stage spine is implemented and tested.** During
implementation the scope was split to manage risk (see "Decision: gestures stay
thin; intent is the projection's" below); the first increment was deliberately
reduced:

- ✅ **Done — the event → gesture stage exists.** A stateful
  [`GestureRecognizer`](../../program/src/editor/GestureRecognizer.jl) is owned
  by the `Editor` and driven once per input event via `next_gesture!` in
  `Editor.read!`. It is the place where multi-event combinations become gestures.
- ✅ **Done — click synthesis moved out of the backend.** The `MousePress`
  click (a `MouseDown`/`MouseUp` combination) is now recognised in the
  `GestureRecognizer`, not the SDL backend. The backend emits only raw events.
  This is backend-agnostic and unit-tested
  ([GestureRecognizerTest.jl](../../test/src/editor/GestureRecognizerTest.jl),
  21 assertions) — previously the logic was buried in SDL and untested.
- ✅ **Done — no behaviour change.** The existing backend-agnostic input structs
  (`KeyDown`, `KeyPress`, `MouseScroll`, `MouseDown/Up/Move`) serve as the
  normalized gesture vocabulary and still flow unchanged, so no reader was
  touched. Verified: recognizer unit tests, json printer (3517), mouse-click
  roundtrips (all examples bar the pre-existing `searching` failure), click
  roundtrips, repls, typeins (159), and the split-pane drag suite (31,
  confirming raw `MouseDown/Move/Up` still reach the splitter reader).

**Composite recognition landed (2026-06-24): multi-click + key chords.** The
recogniser now recognises two more pure event combinations (Phase 2 A & B), both
carrying no intent:

- ✅ **Done — multi-click counting.** `MousePress` gained a `count` field
  (1 = single, 2 = double, 3 = triple, …); the recogniser increments it for
  consecutive same-button clicks within a 5 px / 0.3 s window and resets
  otherwise. Back-compat constructors default `count = 1`, and `:count` was added
  to the `@event_case` table, so existing readers matching `MousePress(:left,
  x, y)` are untouched while a reader *can* now match `MousePress(:left, x, y, 2)`.
- ✅ **Done — key chords.** A new synthesised `KeyChord` event (analogous to
  `MousePress`, in `KeyboardModule`) collapses a recognised `KeyDown` *sequence*
  (e.g. `Ctrl-C Ctrl-K`) into one gesture. Recognition is driven by a per-recogniser
  **chord table that defaults empty** — so production behaviour is unchanged and no
  reader consumes chords yet (consumption is a reader's future decision). Unit-tested
  ([GestureRecognizerTest.jl](../../package/test/src/editor/GestureRecognizerTest.jl),
  now 49 assertions): multi-click counting + resets, chord prefix-buffering /
  completion / flush, empty-table passthrough, and the `next_gesture!` absorb-the-
  prefix path. Verified no new failures: `test_event_case` (26), `test_gesture_binding`
  (46), `test_click_roundtrips` (34); `test_mouse_clicks` deltas are the pre-existing
  `xml_widget`/`filesystem_widget` cursor failures (identical on base `main`) plus a
  worktree-only Adaptagrams native-shim build gap — none from this change.

**Deferred to follow-up increments (not yet implemented):**

- ⏳ Distinct gesture *types* (per-kind structs, no intent) + `@gesture_case` +
  migrating the ~14 reader files to match gestures instead of raw events
  (original Phase 1 steps 1, 2, 6).
- ⏳ Drag begin/update/end (Phase 2 C) — still blocked on reconciling drag
  routing with [dragging.md](dragging.md).
- ⏳ Wiring a production chord table + a reader that consumes `KeyChord`, and
  exposing multi-click `count` to specific readers (both are the *consumer* side,
  intent territory, left to whichever reader wants them).

Rationale for the reduced first increment: a faithful "rename the matched event
in every reader" change touches ~98 `KeyDown` + 44 `MousePress` + 40 `KeyPress`
+ 28 `MouseScroll` matches across 14 files — a repo-wide rewrite with broad
regression surface — for *zero* behaviour change. Establishing the recognition
seam first (and moving the one real multi-event combination, the click, into it)
delivers the architectural value and a testable home for future composites while
keeping the change small and reviewable. The remaining items build on this seam.

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

1. **No multi-event gestures.** Today each handled input is exactly one raw
   event. Combinations of events — chords (`Ctrl-K Ctrl-C`), double/triple-click,
   click-drag (down → move… → up), press-and-hold — cannot be expressed, because
   there is nowhere to accumulate state across events. A gesture *is* such a
   combination, so it needs a stateful place to be recognised.
2. **Recognition is already leaking into the backend.** `MousePress` (click)
   is synthesised inside the SDL backend
   ([Sdl.jl](../../program/src/backend/Sdl.jl) ~L1554–1572: down/up within
   5 px and 300 ms). That is gesture recognition living in a backend, so every
   backend must re-implement it and it is untestable without SDL.
3. **Raw physical events are matched directly in ~50 readers, with no
   normalization of combinations.** Each reader pattern-matches a raw event
   (`KeyDown(:comma; ctrl)`, `MouseDown`/`MouseUp`); there is no shared stage that
   first turns event combinations into gestures, so any composite (click, drag,
   chord) would have to be re-recognised ad hoc in every reader. Note this is
   *not* a complaint that intent is decided per-reader — that is by design (the
   projection owns meaning). The gap is the missing recognition seam, not a
   missing intent table. (`@event_case` appears in 14 files; `projection_read` in
   ~60.)
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
- The recogniser only **recognises event combinations** — it assigns no intent.
  A `Gesture` is the combination of events, nothing more; what it *means* is each
  reader's call.
- Readers stop matching raw event structs and match **`Gesture`** instead, and it
  is there — in the reader — that a gesture is turned into an `Operation`. The
  `Change.gesture` slot now genuinely carries a `Gesture`.

### What is a "gesture"?

A gesture is **a combination or sequence of raw input events, and nothing more.**
It carries **no intent** and no domain meaning — it is a purely syntactic pattern
recognised in the event stream. Deciding what a gesture *means* (which operation
it triggers) is the **projection's** job, downstream of the gesture, never the
gesture's own.

Two canonical examples:

- A **mouse click** is a gesture: its native events are a `MouseDown` followed by
  a `MouseUp` at roughly the same place within a short window. The recogniser
  combines those two events into one click gesture. (This is exactly what the
  implemented recogniser already does — see step 3.)
- A **key chord** such as `Ctrl-C Ctrl-K` is a gesture: it is two successive
  key-press events recognised as a single unit.

Because a gesture is just "these events happened, in this combination," the same
gesture can mean different things in different projections — a click selects in
one reader, toggles a checkbox in another, opens a context menu in a third. The
gesture layer never picks; each reader maps the gesture it receives to the
operation it wants. That is the boundary:

```
raw events → GestureRecognizer → Gesture (combination of events, NO intent)
           → projection reader  → Operation (intent decided HERE)
```

Concretely, gestures are per-kind structs that carry their constituent
events/fields — there is **no intent `Symbol`** on a gesture:

```julia
KeyGesture(key, mods, repeat)               # one key event
CharGesture(char, text, mods)               # one text-producing key event
ClickGesture(button, x, y, count, mods)     # MouseDown + MouseUp combination
DragGesture(button, from, to, phase, mods)  # MouseDown + MouseMove… + MouseUp
ScrollGesture(dx, dy, x, y, mods)           # one wheel event
ChordGesture(keys::Vector{KeyGesture})      # a key sequence, e.g. Ctrl-C Ctrl-K
```

Each gesture kind is named after the *combination of events* it represents, not
after a meaning:

| Gesture kind   | Combination of events                          | Carries                       |
| -------------- | ---------------------------------------------- | ----------------------------- |
| `KeyGesture`   | one `KeyDown`                                  | key, mods, repeat             |
| `CharGesture`  | one `KeyPress`                                 | char, text, mods              |
| `ClickGesture` | `MouseDown` + `MouseUp` (same spot/window)     | button, x, y, count, mods     |
| `DragGesture`  | `MouseDown` + `MouseMove`… + `MouseUp`         | button, from, to, phase, mods |
| `ScrollGesture`| one `MouseScroll`                              | dx, dy, x, y, mods            |
| `ChordGesture` | a sequence of `KeyDown`s (e.g. `Ctrl-C Ctrl-K`)| keys (`Vector{KeyGesture}`)   |

A single event is the degenerate "combination of one event," so most raw events
pass straight through as their one-event gesture; the recogniser only *adds*
structure for the genuine multi-event combinations (click, drag, multi-click,
chord). There is deliberately **no** `:focus_in` / `:select` / `:commit` gesture:
`Ctrl-.` is just a `KeyGesture(:period; ctrl)`, and it is `FocusingProjection`
that decides that means "focus in"; a left `ClickGesture` is just a click, and
each reader decides whether that selects, toggles, or opens a menu.

### Decision: gestures stay thin; intent is the projection's

An earlier draft of this plan weighed two extremes:

- **Thin normalization** — gestures are barely-enriched events (`KeyGesture`,
  `ClickGesture`, `DragGesture`) carrying raw key/button info; readers still see
  `Ctrl-comma`.
- **Fully semantic** — gestures are abstract intents (`:focus_out`) and physical
  keys live only in a keymap.

**The fully-semantic extreme is rejected outright** (conceptual refinement
2026-06-24): a gesture *never* carries intent. A gesture is permanently a thin
combination of events; the semantic mapping (gesture → operation) lives in the
projection readers, where it already lives today. There is therefore **no
separate "named-intent keymap" layer** that owns intent — that framing is dropped.

Given that, phasing is purely about *how much composite recognition* the
recogniser does, not about adding a semantic layer on top:

- **Phase 1** introduces the recognition *seam* and the one real composite that
  already existed (the click), passing every other event through unchanged. Done.
- **Phase 2** grows the recogniser's repertoire of event combinations — drag,
  double/triple-click, key chords — and (separately) migrates readers from
  `@event_case` over raw events to `@gesture_case` over gesture structs. All of
  this is still thin: every gesture is just a combination of events, and the
  reader is still the only place intent is assigned.

A user-facing *rebinding* feature (which physical key combo produces which
gesture) is conceivable later, but it would live at the recognition level and
still would **not** move intent into the gesture; it is out of scope here.

This keeps each step reviewable and never leaves the tree in a broken state.

---

## Phase 1 — recognition layer (no behaviour change)

> Status: steps 3–5 ✅ implemented (the recogniser, the `read!` wiring, and the
> backend cleanup). Steps 1, 2, 6 ⏳ deferred (distinct gesture types,
> `@gesture_case`, reader migration). What landed differs from the original
> sketch below in two ways, by design: (a) the recogniser **passes raw events
> through** and only *adds* the synthesised `MousePress` — it does not emit a
> new `Gesture` type yet (no reader churn); (b) drag/double-click recognition
> were left as ⏳ follow-ups, so the `pending_down`/`dragging`/`click_count`
> state and `recognize! -> Union{Gesture,Nothing}` signature below were not
> built as drawn. The implemented `recognize!` returns the forwarded
> `EventEnvelope` and queues synthesised gestures on `rec.pending`; a
> `next_gesture!(rec, source)` helper drains that queue before pulling new input.

### 1. `Gesture` types — `program/src/device/Gesture.jl` ⏳ deferred (audit 2026-06-23: OPEN — no `Gesture.jl` and no gesture structs exist under `package/`)

New `GestureModule`. Define an abstract `Gesture` supertype (carrying **no**
intent field) and the per-kind structs for the Phase-1 gesture set that mirrors
today's matched events plus the recognised composites:
`KeyGesture(key, mods, repeat)`, `CharGesture(char, text, mods)`,
`ClickGesture(button, x, y, count, mods)`, `DragGesture(button, from, to, phase, mods)`,
`ScrollGesture(dx, dy, x, y, mods)`, `ChordGesture(keys)`. Each struct names a
*combination of events*, not a meaning. Include in
[Projectured.jl](../../program/src/Projectured.jl) next to the device modules.

### 2. `@gesture_case` macro — generalize `@event_case` ⏳ deferred (audit 2026-06-23: OPEN — no `@gesture_case` defined; `@event_case` unchanged at `package/kernel/src/device/EventCase.jl`)

[EventCase.jl](../../program/src/device/EventCase.jl) is a first-match table over
the event structs. Add a sibling `@gesture_case` (or extend `_EVENT_TYPES` to
include the gesture structs so the *same* macro matches both during migration).
Same surface syntax — only the type table grows. Keep `@event_case` working so
migration is incremental, file by file.

### 3. `GestureRecognizer` — `program/src/editor/GestureRecognizer.jl` ✅ done (audit 2026-06-23: VERIFIED at `package/kernel/src/editor/GestureRecognizer.jl:66,99,133` — click-synthesis only, injectable clock; drag/multi-click state still ⏳)

> Implemented with click synthesis only (queued on `rec.pending`, injectable
> `clock` for deterministic tests). Drag/multi-click state shown below is ⏳.

A mutable struct holding recognition state:

```julia
mutable struct GestureRecognizer
    pending_down::Union{MouseDown, Nothing}   # may become click or drag
    dragging::Bool
    last_click_button::Symbol
    last_click_time::Float64
    click_count::Int
    chord_buffer::Vector{KeyGesture}          # accumulates a chord prefix (e.g. after Ctrl-C)
    chord_table::Set                           # recognised key sequences (no intent — just which
                                               #   combinations count as a ChordGesture)
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

### 4. Wire the recogniser into `Editor.read!` ✅ done (audit 2026-06-23: VERIFIED — `recognizer::GestureRecognizer` field at `package/kernel/src/editor/Editor.jl:51`, `next_gesture!(editor.recognizer, …)` at top of `read!`, `Editor.jl:82`; QuitEvent short-circuit + `Change(env, nothing)` seeding intact)

> Implemented as `next_gesture!(editor.recognizer, () -> read_from_devices(...))`
> at the top of the `read!` loop; the rest of `read!` (QuitEvent short-circuit,
> `Change(env, nothing)` seeding) is unchanged.

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

### 5. Remove `MousePress` synthesis from the SDL backend ✅ done (audit 2026-06-23: VERIFIED — `package/sdl/src/ProjecturedSdl.jl` has zero `MousePress(` constructions; synthesis removed, only doc comments at lines 172 and 1911 note the recogniser now owns it)

Strip the click-synthesis state and logic from
[Sdl.jl](../../program/src/backend/Sdl.jl) (`last_down_*`, `pending_events`
press injection, ~L152–156, L1554–1572). The backend now emits only raw
`MouseDown`/`MouseUp`/`MouseMove`; click/drag recognition is the recogniser's
job. (Keep `MousePress` the *type* until readers migrate, or map
`ClickGesture` ↔ the old reader expectations in step 6.)

### 6. Migrate readers `@event_case` → `@gesture_case` ⏳ deferred (audit 2026-06-23: OPEN — `@event_case` still present in ~14 reader files under `package/`, e.g. `package/kernel/src/projection/generic/Focusing.jl`, `package/domain/src/projection/primitive/SyntaxToText.jl`, `TextToGraphics.jl`, etc.; no gesture patterns used)

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

### 7. Tests ✅ done (for what landed) (audit 2026-06-23: VERIFIED — `package/test/src/editor/GestureRecognizerTest.jl` exists with the listed click/none/passthrough/queue cases via injectable clock + scripted source; registered at `package/test/src/ProjecturedTest.jl:89`. The drag/double-click test items remain ⏳.)

- ✅ Recogniser unit tests added
  ([GestureRecognizerTest.jl](../../test/src/editor/GestureRecognizerTest.jl)):
  down+up→click, too-far→none, too-slow→none, wrong-button→none, non-mouse
  pass-through, and `next_gesture!` queue ordering. Deterministic via an
  injectable clock and a scripted source — no SDL. Registered in `test_all`.
- ✅ Re-ran the input-related suites with no new failures: json printer,
  mouse-click roundtrips, click roundtrips, repls, typeins, split-pane drag.
  (The `searching` mouse-click failure is pre-existing on the base branch — a
  `PrimitiveString` `:open`/`:close` selection-mapping bug, unrelated.)
- ⏳ down+move+up→drag and double-click tests land with those recogniser
  features (deferred).

---

## Phase 2 — richer composite gestures (optional, ships separately)

> **Reframed 2026-06-24.** This phase was previously a "semantic keymap" that
> mapped keys → intent `Symbol`s. That is dropped: a gesture carries no intent, so
> there is no keymap layer that assigns one — readers (projections) own meaning.
> What remains is purely *more event-combination recognition* in the recogniser,
> plus the mechanical reader migration. **A & B landed 2026-06-24** (in the
> `event-to-gesture-composites` worktree); C, D, E remain ⏳ OPEN.

### A. Multi-click counting ✅ done (2026-06-24)

Double/triple-click is recognised by maintaining a click count over a
time/position window in the recogniser (`last_click_*` state +
`MULTI_CLICK_MAX_DISPLACEMENT` 5 px / `MULTI_CLICK_MAX_INTERVAL` 0.3 s). Still a
pure combination of `MouseDown`/`MouseUp` events — no intent.

**As built (differs from the original sketch):** the count rides on the existing
synthesised `MousePress` event as a new `count` field — there is *no* separate
`ClickGesture` type (that belongs to the deferred per-kind gesture-type layer).
`MousePress` keeps modifiers last; `count` is a positional non-modifier field, so
`:count` was added to the `@event_case` table
([EventCase.jl](../../package/kernel/src/device/EventCase.jl)) and back-compat
3-arg / 4-arg(`::Modifiers`) constructors default `count = 1`. Every existing
`MousePress(:left, x, y)` reader and call site is therefore unchanged.

### B. Chords ✅ done (2026-06-24)

A chord is a *sequence* of `KeyDown`s (`Ctrl-C Ctrl-K`) recognised as one event.
The recogniser accumulates the prefix in `chord_buffer`; while a valid prefix is
pending it absorbs the key (`recognize!` returns `nothing`), a completed sequence
emits the chord, and a key that breaks the sequence flushes the buffered keys
back as raw events. This is recognition only — *what* a chord does is still each
reader's decision.

**As built (differs from the original sketch):**

- The chord event is a new synthesised `KeyChord(keys::Vector{KeyDown})` in
  [`KeyboardModule`](../../package/kernel/src/device/Keyboard.jl) — analogous to
  the synthesised `MousePress`, **not** the deferred per-kind `ChordGesture`
  struct. It carries the constituent presses; modifiers live on each `KeyDown`.
- Which sequences are chords is a per-recogniser **chord table that defaults
  empty**, so production behaviour is unchanged and chords are opt-in. The table
  says only *which* combinations are a chord, never what they mean.
- `next_gesture!` now **loops**, so a buffered prefix is absorbed *inside* one
  pull and never surfaces to `Editor.read!` as the "input exhausted" `nothing`.
  A dangling prefix persists across an input-exhausted pull (recognised on a
  later frame, Emacs-style).
- Flush simplification: the breaking key is emitted raw and does **not** itself
  start a new chord; auto-repeat `KeyDown`s never start/extend a chord.
- No production reader consumes `KeyChord` yet (consumption is intent territory,
  deferred). `KeyChord` is intentionally *not* in the `@event_case` table until a
  reader needs it.

### C. Drag

`MouseDown` → `MouseMove`… → `MouseUp` past a movement threshold becomes a
`DragGesture` with `:begin`/`:update`/`:end` phases. Coordinate drag routing with
[dragging.md](dragging.md) before implementing (see Open questions).

### D. Migrate readers `@event_case` → `@gesture_case`

The reader migration from Phase 1 step 6: switch the scrutinee from the raw event
to the gesture. The reader is, and remains, where intent is assigned — e.g.
`KeyGesture(:comma; ctrl) => focus_out_op`, `ClickGesture(:left, x, y) =>
select_at(x, y)`. Rebinding, if ever added, changes which gesture a reader
matches (or which key combo forms a gesture), not where intent lives.

### E. Feed gesture-help

Implement `projection_available_gestures` (see
[gesture-help.md](../tentative/gesture-help.md)) by walking the **readers'
handled-gesture sets** — the catalogue of "available gestures" is sourced from
the projections that consume them, since that is where meaning lives, not from a
keymap.

---

## Open questions

- **Gesture vocabulary granularity.** *Resolved (2026-06-24):* per-kind structs
  (`KeyGesture`, `ClickGesture`, …) carrying their constituent events, **no**
  intent `name` Symbol — a gesture carries no intent. The earlier `Gesture{name,
  data}` / "name Symbol added in Phase 2" idea is dropped; intent lives in the
  projection readers. Per-kind structs also keep `@gesture_case` field-matching as
  ergonomic as `@event_case`. Remaining: the exact field set of each struct.
- **Where double/triple-click thresholds live.** *Resolved (2026-06-24):*
  recogniser constants — `MULTI_CLICK_MAX_DISPLACEMENT` (5 px) /
  `MULTI_CLICK_MAX_INTERVAL` (0.3 s) in `GestureRecognizer.jl`, mirroring the
  click window. Config/keymap overrides can come later if needed.
- **Drag routing.** A drag spans many frames; does each `:drag(:update)` run the
  full reader pipeline, or does the editor cache the drag target from `:begin`?
  Interacts with [dragging.md](dragging.md) — reconcile before
  implementing drags (Phase 1 can emit drag gestures but leave readers ignoring
  them until that plan lands).
- **Backend compatibility shim.** Whether to keep emitting `MousePress` from a
  thin adapter during migration, or migrate all click readers in one commit
  alongside step 5.

---

## Dependencies & related plans

- [gesture-help.md](../tentative/gesture-help.md) — its "available gestures"
  catalogue is sourced from the readers' handled-gesture sets (Phase 2 E).
- [dragging.md](dragging.md) — the `:drag` gesture is its input;
  coordinate drag routing.
- No dependency on logging or other pending plans.
