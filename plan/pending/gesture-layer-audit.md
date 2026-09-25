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

## The design (decided by the owner on 2026-09-25)

- **D1, the field.** Every concrete event gets a last field `time::Float64`, and
  the time is **mandatory**: no constructor has a default for it. The owner
  needs no backward compatibility here. Each short constructor takes the time as
  the required keyword `time`; the full constructor takes it as its last
  argument. The interface declares `get_event_time(event)`.
- **D2, the time base.** Seconds on the clock of `time()`. Each backend converts
  its own stamps: SDL from its ticks at the poll, the web page sends
  `performance.timeOrigin + ev.timeStamp`, and the console takes `time()` when
  it reads the bytes.
- **D3, equality.** The default equality of a struct compares the time too. The
  tests that compare an event of a backend with a literal event change.
- **D4, synthetic events.** `MousePress` takes the time of its `MouseUp`, and
  `KeyChord` the time of its last `KeyDown`.
- **D5, the recognizer.** It reads the time of each event, and its `clock`
  keyword goes. That also ends item 5. The tests give times to their events.
- **D6, chords.** The chord table of an editor will come from the `KeyChord`
  patterns of its gesture bindings, so each chord is written once. The owner
  deferred this; this plan only documents it, in
  `plan/pending/key-chords-from-bindings.md`.

Because the time is mandatory, each producer of an event must choose a time.
The rules:

- A backend gives the time of the input, from its own stamps (D2).
- A reader or a probe that makes an event from another event gives the time of
  that event: a move of a pointer event into the space of a child, a
  `MouseEnter` from a `MouseMove`, a `MousePress` that a probe makes from a
  `MouseMove`.
- A producer with no input, such as a script of a precompile workload, an
  example or a video tool, gives `time()`, the time when it makes the event.
- A test gives a literal time. Most tests give `time = 0.0`; a test of the
  recognizer gives the times that its case needs.
- A pattern does not bind `time` by position: `time` is not a part of what a
  gesture is. `_get_positional_event_fields` leaves it out.

The inventory (a parse with the parser of Julia; pattern syntax in
`@event_case`, `@gestures` and `@gesture_set` and quoted code do not count):
1521 constructions. projectured-julia has 1206 in `test/`, 119 in `source/`, 38
in `example/` and 18 in `tool/`; omnet-julia has 119, and inet-julia 21. No
code passes an event type as a function value, and no code constructs an event
through a type variable.

## The files

Sealed files that the items change:

- `gesture/GestureRecognizerModule.jl`, `gesture/GestureRecognizer.jl`: all items.
- `event/EventModule.jl`, `event/EventInterface.jl`, `event/EventDefaults.jl`,
  `event/KeyboardEvent.jl`, `event/MouseEvent.jl`, `event/WindowEvent.jl`: the
  time field and `get_event_time` (item 1).
- `event/EventPattern.jl`: the positional fields of a pattern leave `time` out.

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
3. [ ] Item 1: the time field in the event layer, the constructions in
   projectured-julia, the backends, and the recognizer on the event time
   (item 5 with it).
   - The event layer: every concrete event has `time::Float64` as its last
     field. The full constructor takes it as its last argument, and every short
     form as the required keyword `time`. `get_event_time` is declared in
     `EventInterface.jl` and defined in `EventDefaults.jl`. A pattern leaves
     `time` out of its positional fields.
   - The constructions: a script over the parse tree
     (`/var/tmp/gesture-audit/events.jl`) added `time = …` to each
     construction that had none, and left pattern syntax, quoted code and
     definitions alone. The tests got `time = 0.0` (1157 sites in 94 files).
     The readers got the time of the event that they read from (`evt.time`,
     `event.time` or `g.time`); four probes with no input got `time()`. The
     drivers of the precompile workloads, the examples and the video tools got
     `time()`, and a driver whose start time `t0` comes before its list got
     `t0`. The test macro `@em_test_bind_fields` takes a pattern as its first
     argument, and that argument has no time.
   - The backends: SDL converts `evt.common.timestamp` with its ticks
     (`_get_sdl_event_time`), and `sdl_to_keydown`, `sdl_to_keyup` and
     `sdl_to_keypress` take the time as a keyword. The web page sends `t`, the
     time of the browser event or of the send, and `Web.jl` reads it; a message
     with no `t` gets the time when it arrives. The console reads `time()` once
     after it drains the input, and its decoder takes the time as a keyword.
     The video backend gives its last `WindowQuit` the time when it builds its
     timeline.
   - The recognizer reads the time of each event; its `clock` keyword and field
     are gone. A `MousePress` has the time of its `MouseUp`, and a `KeyChord` the
     time of its last key. A new test processes a release a third of a second
     after its press, with event times 0.1 s apart, and gets a click.
   - The lines that the time made longer than 90 characters in main code are
     wrapped. The lines of the tests are not: most tests read as lists of
     events, and the budget of a line is not wrapped there.
   - The first run of the suites found three faults of this step, all fixed:
     - The script skipped the whole body of `@event_case`, but only the left
       side of a rule `pattern => result` is pattern syntax. 40 constructions
       on right sides had no time: 37 in `WidgetToGraphics.jl` and 3 in
       `PaneGestures.jl`. The script now skips only the left side. In
       `@gestures` the event has a generated name that the right side can not
       name, so the 3 in `PaneGestures.jl` got `time()`.
     - `ApplicationVideo.jl` replaced the clock of the recognizer with the clock
       of the video frames. The video backend now gives each event it delivers
       the time of the schedule when it fires (`_restamp_event`), so clicks and
       double clicks are measured in video time, and the example no longer
       touches the recognizer.
     - The tests of the web and console backends compared an event of the
       backend with a literal event at the time 0.0 (D3). The web test messages
       now carry `"t":1500`, and the tests expect the time 1.5 s; a message with
       no `t` must get a time between the times before and after it arrives.
       The console tests compare the other fields, and check that the time of
       the read lies between the times before and after it.
   - The guides: the examples of events in `devices-and-backends.md`,
     `engineer-tour.md`, `focus.md`, `video.md` and `debugging-guide.md` show the
     time, and `web.md` documents the field `t`. `web.md` also said that the web
     backend keeps SDL alive for the font cache of SDL, which is false.
4. [x] Item 4: `plan/pending/key-chords-from-bindings.md`, deferred.
5. [ ] The same constructions in omnet-julia and inet-julia, in worktrees of
   their own, to land together with this branch.
   - omnet-julia: branch `event-time` in `../omnet-julia-event-time`. The tests
     and the test package give `time = 0.0` (89 sites), the precompile
     workloads give `time()` or the start time `t0` of the driver (30 sites),
     and the folder `demo/`, which the first inventory did not scan, gives
     `time()` (15 sites). Commits `d1793365` and `4b693eb9`.
   - inet-julia: branch `event-time` in `../inet-julia-event-time`. The test
     gives `time = 0.0`, and the precompile driver gives `time()`, one event on
     each line. Commit `658b4d4`.
   - The check runs in scratch environments that point projectured-julia at
     this worktree and each repository at its own worktree. The baseline runs
     in a scratch environment that points at the main checkouts. The two test
     packages `OmnetCampaignUiTest` and `OmnetIdeTest` are added to both,
     because their tests changed. The omnet suites need 4 threads: with 2, the
     presentation suite waits for a simulation session that never ends.
   - The baseline of omnet-julia on main (`b585d8fa`, projectured-julia
     `ae39586c`): `test_presentation()` 1689 pass, 14 fail, 3 error, 1 broken;
     `test_legacy()` 1027 pass, 6 fail, 59 error; `test_campaign_ui()` passes;
     `test_ide()` 447 pass, 1 fail, 2 error.
6. [ ] The check: the suites as on main plus the new tests, the guards,
   omnet-julia and inet-julia precompile and pass their suites, and a live
   window gives a click and a double click.
