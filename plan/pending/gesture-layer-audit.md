# The audit of the gesture layer

The owner asked for a review of the whole shape of the gesture layer
(`source/kernel/gesture/`) and a re-audit against the rules in
`documentation/rule/`. The layer is two sealed files: `GestureRecognizerModule.jl`
and `GestureRecognizer.jl`. Its only import is `EventModule`, all its state is on
the recognizer instance, its names follow the naming rules, and its export block
follows the export rule.

On 2026-09-25 the owner:

- chose option (a) for item 1: a timestamp on each event;
- chose option (a) for item 4: keep chord recognition, and give it a way in;
- approved all the other items;
- gave permission to edit the sealed files that the items need.

## Items

1. **The click window uses the time of processing, not the time of the input.**
   The recognizer calls `clock()` when it processes a `MouseDown` and again when
   it processes the `MouseUp`. A slow frame or the first compilation between the
   two counts as hold time, and the click is lost. Each event gets a timestamp.
2. **A click can span two windows.** The recognizer does not compare the window
   of the `MouseUp` with the window of the `MouseDown`.
3. **The recognizer remembers one press for all buttons.** Press left, press
   right, release right, release left: the left click is lost.
4. **Nothing in the editor uses chord recognition.** The editor makes
   `GestureRecognizer()` with no chord table, `Editor` has no keyword to set
   one, and no reader, pattern or binding matches `KeyChord`.
5. The `clock::Function` field has an abstract type, so `clock()` returns `Any`.
6. The module docstring promises a "(future) drag", which the readers of the
   dragging and widget packages do; it does not list its fragment; it lists some
   of the events only; it says "whoever consumes it" and "normalized gesture
   vocabulary".
7. The fragment: a header line of 120 characters; "Recognised today:"; "should
   any arise" for a pass-through that `FrameDrainTest.jl` uses; the prose spells
   "recogniser" beside the name `GestureRecognizer`.
8. The test file: its header names `test/device/` and calls the recognizer "a
   kernel device type"; its cases are `let` blocks with no names; it does not
   test the window id of a `MousePress`, a key repeat during a chord prefix, or
   the order of a flush.
9. The guide: the file tree in `devices-and-backends.md` shows one file, and the
   text says "whoever binds it".

## The facts for items 1 and 4

- The event types: `KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`, `MouseUp`,
  `MouseMove` and `MouseScroll`, and the window events `WindowQuit`,
  `WindowClose`, `WindowResize` and `WindowDefocus`, are device events. `KeyChord`,
  `MousePress`, `MouseEnter` and `MouseLeave` are synthetic events.
- The three repositories construct events about 1900 times, most of them in
  tests. Some of them are pattern syntax in `@event_case` and `@gestures`.
- No source code compares events with `==`. 41 lines of tests do.
- The gesture log describes an event by its fields, not by `repr`.
- The backends make their events here:
  - SDL: `_poll_window_input` in `Sdl.jl`. Each SDL event has a `timestamp`, in
    milliseconds since `SDL_Init`. The backend does not read it now.
  - Web: `Web.jl` decodes the messages of `asset/web/client.js`. A browser event
    has `timeStamp`, in milliseconds since `performance.timeOrigin`. The page
    does not send it now.
  - Console: `Console.jl` decodes the bytes of the terminal. It has no time of
    its own.
  - Video: `VideoBackend.jl` answers the entries of its timeline at their
    video times. It gives events straight to the reader, with no recognizer.
  - Headless: `push_event!` gives the values that a test pushes.

## The design (proposed; the decisions D1 to D6 wait for the owner)

- **D1, the field.** Every concrete event gets a last field `time::Float64`.
  Every short constructor takes it as the keyword `time`, `0.0` by default, so
  the existing constructions do not change. `0.0` means that the producer knows
  no time. The interface declares `get_event_time(event)`.
  - Option: the time on `WindowInput`, not on the event. The owner asked for
    the time on the event.
- **D2, the time base.** Seconds on the clock of `time()`. Each backend converts
  its own stamps: SDL from its ticks at the poll, the web page sends
  `performance.timeOrigin + ev.timeStamp`, and the console takes `time()` when
  it reads the bytes.
  - Option: seconds from an origin of each backend. The recognizer needs only
    intervals, but a time on one clock can also go into a log.
- **D3, equality.** The default equality of a struct compares the time too. The
  tests that compare an event of a backend with a literal event then compare
  the fields, or give the literal the same time.
  - Option: `==` and `hash` of an event ignore the time. That keeps the tests,
    but two events at different times are then equal.
- **D4, synthetic events.** `MousePress` takes the time of its `MouseUp`, and
  `KeyChord` the time of its last `KeyDown`. Other producers, such as the hover
  tracking of widgets, keep `0.0` in this plan.
- **D5, the recognizer.** It reads the time of each event, and its `clock`
  keyword goes. That also ends item 5. The tests give times to their events.
- **D6, the way in for chords.**
  - `Editor`, `make_editor` and `run_editor!` take a keyword `chords`, the chord
    table of the recognizer.
  - A pattern `KeyChord(KeyDown(:x; ctrl), KeyDown(:s; ctrl)) => …` in
    `@event_case` and `@gestures` matches a chord of those steps. Each step is a
    `KeyDown` pattern, with its own modifiers. `describe_event_pattern` gives
    "Ctrl+x Ctrl+s".
  - Option: the editor collects the chord table from the patterns of its
    bindings, so a chord is written once. That needs a walk over every binding
    of the projection, and it is a larger change.

## The files

Sealed files that the items change:

- `gesture/GestureRecognizerModule.jl`, `gesture/GestureRecognizer.jl`: all items.
- `event/EventModule.jl`, `event/EventInterface.jl`, `event/KeyboardEvent.jl`,
  `event/MouseEvent.jl`, `event/WindowEvent.jl`: the time field and
  `get_event_time` (items 1 and 4).
- `event/EventPattern.jl`: the `KeyChord` pattern (item 4).

Files that are not sealed: `Sdl.jl`, `Web.jl`, `client.js`, `Console.jl`,
`VideoBackend.jl`, `Editor.jl`, `EditorLoop.jl`, the tests, and the guides
`devices-and-backends.md`, `editor.md`, `sdl.md` and `web.md`.

## Steps

Each step is a commit in this worktree.

0. [x] The baseline on main at `ae39586c`:

   | Suite | Pass | Fail | Error | Broken |
   | --- | --- | --- | --- | --- |
   | `test_kernel()` | 2333 | 3 | 3 | 0 |
   | `test_sdl()` | 150 | 0 | 0 | 0 |
   | `test_video()` | 34 | 0 | 0 | 0 |
   | `test_web_backend()` | 30 | 1 | 0 | 0 |
   | `test_console_backend()` | 83 | 0 | 0 | 0 |
   | `test_substrate()` | 80530 | 3 | 2 | 1 |

   The 12 failures are known: 5 in `DocumentMacroTest.jl`, 1 in
   `ReferenceEvalTest.jl`, 5 in `SplitPaneDragTest.jl`, and the bound of 5 s in
   `WebTest.jl:110`, which the load of the machine breaks.
1. [x] Items 6 to 9: the text of the gesture layer, its test file, and the guide.
2. [x] Items 2 and 3: the same window, and one press for each button. Steps 1
   and 2 are one commit, because the new text describes the new behaviour.
   - The recognizer keeps a `_ButtonPress` for each button in `presses`, and
     the last click as a `_Click`. A `MouseUp` takes its press out of
     `presses`, so a second release without a press makes no click.
   - A click and the next click of a double click need the same window.
   - New tests: two windows; two buttons held at the same time; a release
     that consumes its press; a key repeat during a chord; the order of a
     flush of two kept keys; a value that is not a `WindowInput`.
   - The suites give the baseline, with the kernel at 2335 passes (2 more) and
     the same 12 failures at the same lines.
3. [ ] Item 1, after the owner confirms D1 to D5: the time field, the backends,
   and the recognizer on the event time (item 5 with it).
4. [ ] Item 4, after the owner confirms D6: the `chords` keyword and the
   `KeyChord` pattern.
5. [ ] The check: the suites as on main plus the new tests, the guards, omnet-julia
   precompiles, and the live-window check.
