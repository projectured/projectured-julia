# Layer 08 — gesture (`source/kernel/gesture/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (2 of 2).

## Verdict

The gesture layer has few faults. It imports only `EventModule`, keeps all of
its state on one recognizer for each editor, and makes a click and a double
click from the times of the events, for one button in one window. No item is
High or Medium. The chord part, which no editor uses, has a latent fault of
order: while a chord waits, events of other kinds overtake the kept keys, and a
chord can collect keys from two windows. A step of the chord table is an event
that needs a time which the code ignores. The docstring of `pop_gesture!` names its
callers, and the editor guide says that the editor makes chords, which it does
not.

## Shape

- Purpose: the stage between the backend and the readers where several events
  become one gesture: a `MousePress` (with the count of a double or triple
  click) from a `MouseDown` and a `MouseUp`, and a `KeyChord` from a sequence of
  the chord table. Other events pass through.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `GestureRecognizerModule.jl` | 44 | 🔒 | the docstring, `using ..EventModule`, the exports, one include |
  | `GestureRecognizer.jl` | 218 | 🔒 | `GestureRecognizer`, `recognize_gesture!`, `pop_gesture!`, the private `_ButtonPress` and `_Click` |

- Imports: `EventModule`. Imported by: the `editor/` layer only
  (`Editor.jl:89` makes `GestureRecognizer()`; `ReadEvaluatePrint.jl:28` calls
  `pop_gesture!`).
- Public surface: 3 exported names. None has a user outside the kernel: the two
  hits in `Sdl.jl` and `Web.jl` are comments. `recognize_gesture!` has callers
  only in `pop_gesture!` and in the tests.
- State: all on the instance. `pending` holds at most the gestures of one input,
  `presses` holds one press for each button, `last_click` one click,
  `chord_buffer` at most the longest chord. Each editor has its own recognizer,
  and only the editor task calls it.
- Tests: `test/kernel/gesture/GestureRecognizerTest.jl` (212 lines, 54 passes in
  the baseline log): a click, the times of the events, the limits of distance
  and time, two windows, two buttons, a release that consumes its press, the
  counts of a double and a triple click, the chord table, a repeat during a
  chord, the order of a flush, the pass-through of a value that is not a
  `WindowInput`. The gaps are in L08-4.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 0 | 1 |
| Shape | 0 | 0 | 1 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 0 | 1 |

## Findings

### L08-1 While a chord waits, events of other kinds overtake the kept keys

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [GestureRecognizer.jl:115](../../../source/kernel/gesture/GestureRecognizer.jl#L115) 🔒,
  [GestureRecognizer.jl:156](../../../source/kernel/gesture/GestureRecognizer.jl#L156) 🔒
- Evidence: only a `KeyDown` goes to `_recognize_key!`; every other event takes
  the branch `else return window_input` at once, also while `chord_buffer` holds
  keys. With the table `[[Ctrl+C, Ctrl+K]]`, the input Ctrl+C down, C up,
  Ctrl+Z down gives the reader `KeyUp(:c)`, then `KeyDown(:c)`, then
  `KeyDown(:z)`: the release comes before its press. A `KeyPress` of a chord step
  without Ctrl, and a `MouseDown` between two steps, overtake the same way. The
  docstring of `pop_gesture!` promises that "the reader sees the order of the
  input". The chord also collects keys from any window, and the `KeyChord` goes
  to the window of the first key (`window_id = recognizer.chord_buffer[1].window_id`),
  while a click needs one window. The fault is latent: no editor sets a chord
  table (`Editor.jl:89`).
- Rule: bug (the order of the input); the gesture audit rule "one window" for a
  click, not applied to a chord.
- Fix: while `chord_buffer` holds keys, keep each later input behind them (in the
  buffer or in `pending`), and break the chord when the window changes.
- Reach: `GestureRecognizer.jl` (sealed), `GestureRecognizerTest.jl`. Planned in
  part: plan/pending/key-chords-from-bindings.md (it asks whether a chord needs a
  timeout; it does not name the order).

### L08-2 A step of the chord table is an event, with a time that means nothing

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [GestureRecognizer.jl:64](../../../source/kernel/gesture/GestureRecognizer.jl#L64) 🔒,
  [GestureRecognizer.jl:187](../../../source/kernel/gesture/GestureRecognizer.jl#L187) 🔒
- Evidence: `chords::Vector{Vector{KeyDown}}`. Since every event holds a
  mandatory time, a table must give one: the tests write
  `KeyDown(:c, _GR_CTRL; time = 0.0)`. `_is_chord_step` compares only `key` and
  `modifiers`, so `repeat` and `time` of a step are data that the code ignores. A
  step is a pattern (a key and its exact modifiers), and the event layer has the
  type for it (`KeyDownPattern`).
- Rule: design fault (an event used as a pattern); the event layer has
  `EventPattern` for a pattern as data.
- Fix: a chord table of `EventPattern{KeyDown}` values, matched with
  `matches_event_pattern`.
- Reach: `GestureRecognizer.jl` (sealed), `GestureRecognizerTest.jl`. Planned:
  plan/pending/key-chords-from-bindings.md (a chord is written as a sequence of
  `KeyDown` patterns).

### L08-3 The docstrings name their callers, and the editor guide promises chords that the editor does not make

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [GestureRecognizer.jl:194](../../../source/kernel/gesture/GestureRecognizer.jl#L194) 🔒,
  [GestureRecognizer.jl:31](../../../source/kernel/gesture/GestureRecognizer.jl#L31) 🔒
- Evidence:
  - `pop_gesture!`: "The editor gives a function over `read_from_devices`, and a
    test gives a scripted source." and "The tests of the frame loop push such
    values through the editor." `read_from_devices` belongs to the backend layer
    (layer 9, above this one), the editor to layer 22.
  - `GestureRecognizer`: "The click windows compare the times of the events
    (`get_event_time`)". The code reads the field `event.time` (lines 97, 101,
    158) and never calls `get_event_time`.
  - editor.md:48-50 and :206-210 say that the recognizer of the editor folds "a
    `KeyDown` sequence into `KeyChord`", and editor.md:499-501 says the same. The
    editor makes `GestureRecognizer()` with no chord table, so it never makes a
    `KeyChord`. editor.md:210 also lists `KeyChord` among the events that a
    reader gets, and omits `WindowClose`, `WindowResize` and `WindowDefocus`.
- Rule: PAR-NO-CONSUMER-DOCS; PAR-HONEST-DOCS.
- Fix: "`source` answers the next input, or `nothing`"; call `get_event_time`
  or name the field; in editor.md, say that the chord table of an editor is
  empty until the plan below lands.
- Reach: `GestureRecognizer.jl` (sealed), `editor.md`. Planned for the chord
  text: plan/pending/key-chords-from-bindings.md.

### L08-4 The tests miss the order and the window of a chord, and one test sleeps for nothing

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/gesture/GestureRecognizerTest.jl:67`
- Evidence:
  - No test gives an event of another kind between the keys of a chord (L08-1),
    a chord across two windows, or a double click whose second click is in
    another window (the window test of `_count_click!`, line 127). No test
    checks the limits of the click windows: the code uses a strict `<` at 5
    pixels and 0.3 seconds.
  - "the times of the events decide, not the time of processing" calls
    `sleep(0.35)` between the press and the release. Since fea89ffd the
    recognizer reads no clock, so the sleep adds 0.35 s to each run and checks
    nothing that the event times alone do not.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add the four cases; remove the sleep and keep the two event times.
- Reach: `GestureRecognizerTest.jl`.

## Accepted before, not raised again

- The recognizer keeps chord recognition although no editor uses it, and the
  chord table of an editor comes later from the rules of its gesture tables
  (plan/done/gesture-layer-audit.md item 4; deferred:
  plan/pending/key-chords-from-bindings.md, with its open question on a
  timeout).
- `pop_gesture!` passes a value that is not a `WindowInput`, for the frame tests
  (gesture audit item 7).
- The times of the events are on the clock of `time()` (gesture audit D2).
- The module is `GestureRecognizerModule` in the folder `gesture/` (the gesture
  audit found that the names follow the rules).

## Checked and clean

- The layering: the one import is `EventModule`, a lower layer; no document, no
  operation and no backend type is named in code.
- PAR-PER-EDITOR-STATE: all state is on the instance, one instance for each
  editor (`Editor.jl:89`), and every buffer is bounded.
- A click needs one button and one window, and so does the next click of a
  double click; the click windows use the times of the events, so a slow frame
  loses no click (items 1 to 3 of the gesture audit, all tested).
- A gesture carries no intent: the stage makes events from events, and the
  readers decide what they do.
- The export block, PAR-MODULE-DOCSTRING, the fragment header, the names
  (`recognize_gesture!`, `pop_gesture!`), concrete field types with no `Any`; no
  history comment; no line over 90 characters.
