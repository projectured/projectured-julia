# Layer 06 — event (`source/kernel/event/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (9 of 9).

## Verdict

The event layer is small, pure and well tested for its main path, and the recent
change (a mandatory `time` field on every event) is complete and consistent. The
two important items are contract text. The key names exist only as prose in the
`KeyDown` docstring, so each backend decides which keys have a name, and that
causes L09-1 (High). The `MouseScroll` docstring states the opposite sign of `dy`
to the one that every backend sends and every reader expects. The pattern
language has four small latent faults: `@event_case` and `EventPattern` read the
modifiers in two ways, `build_event_field_bindings` throws for the catch-all
rule, an unknown modifier name gets no error, and a `MouseDown` pattern reads as
a click. The design documents still describe the layer as it was before the
audit of 2026-09-25.

## Shape

- Purpose: the input vocabulary of the editor. An event is plain data (symbols,
  numbers, modifier flags, the time of the input). The layer also holds the
  pattern language that matches events: the reified `EventPattern`, its parser,
  and `@event_case`.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `EventModule.jl` | 58 | 🔒 | the docstring, the exports, eight includes |
  | `EventInterface.jl` | 54 | 🔒 | `Event`, `DeviceEvent`, `SyntheticEvent`; the generics `get_modifier_keys`, `get_event_time` |
  | `ModifierKeys.jl` | 28 | 🔒 | `ModifierKeys` |
  | `KeyboardEvent.jl` | 100 | 🔒 | `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord` |
  | `MouseEvent.jl` | 207 | 🔒 | `MouseButtons` and the seven mouse events |
  | `WindowEvent.jl` | 55 | 🔒 | `WindowQuit`, `WindowClose`, `WindowResize`, `WindowDefocus` |
  | `WindowInput.jl` | 13 | 🔒 | `WindowInput` |
  | `EventDefaults.jl` | 23 | 🔒 | the fallbacks of the two generics, the four `has_*_modifier_key` |
  | `EventPattern.jl` | 521 | 🔒 | `EventPattern`, its constructors, `describe_event_pattern`, the parser, `@event_case` |

- Imports: none. Imported by: the `gesture/`, `binding/`, `projection/`,
  `editor/` and `playback/` layers of the kernel; about 30 packages outside the
  kernel (screen, text, widget, layout, pane, tooltip, the SDL, web, console and
  video backends, and most domains); omnet-julia and inet-julia.
- Public surface: 45 exported names. Every event type, `ModifierKeys`,
  `MouseButtons`, `WindowInput`, `EventPattern`, `matches_event_pattern`,
  `describe_event_pattern`, `KeyDownPattern`, `KeyPressPattern`,
  `MousePressPattern` and `@event_case` have users outside the kernel. The
  parser API (`parse_event_pattern_rule`, `build_event_pattern_expr`,
  `build_event_field_bindings`) has one user, the `binding/` layer. No user
  anywhere: `has_shift_modifier_key`, `has_alt_modifier_key`,
  `has_meta_modifier_key`, `KeyUpPattern`, `MouseDownPattern`, `MouseUpPattern`,
  `MouseEnterPattern`, `MouseLeavePattern`. Only tests: `get_event_time`,
  `MouseMovePattern`, `MouseScrollPattern`. `KeyChord` has only the recognizer and
  its test (see layer 08). No code outside the layer names `DeviceEvent`.
- State: none. The one constant, `_MODIFIER_FLAGS`, is a tuple. An
  `EventPattern` holds a mutable `Vector{Symbol}` (L06-5).
- Tests: `test/kernel/event/EventModuleTest.jl` (141 lines) and
  `EventCaseTest.jl` (109 lines), 48 and 26 passes in the baseline log. They
  cover the constructors, `MouseButtons`, `WindowInput`, the reified patterns and
  their text, the parser and its errors, and `@event_case` (types, literals,
  bound names, exact modifiers, guards, wildcards, `^(expr)`, a type of another
  module). They do not cover the cases in L06-15.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 0 | 4 |
| Shape | 0 | 1 | 4 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 1 | 2 |
| Tests | 0 | 0 | 1 |

## Findings

### L06-1 The event layer names its keys only in prose, so each backend decides which keys have a name

- Category: Shape · Severity: Medium · Confidence: Confirmed
- Where: [KeyboardEvent.jl:11](../../../source/kernel/event/KeyboardEvent.jl#L11) 🔒
- Evidence: the `KeyDown` docstring says that the names include "letters, such as
  `:c`", and `:char` "for a key whose name does not matter". No table, function
  or constant in the layer says which keys have a name. Each backend keeps its
  own list: SDL names 9 letters, the web backend 4, the console none (L09-1).
  SDL names the letters that a rule of a gesture table needed when the letter
  was added: its comments name the consumers ("Ctrl+T — open a pane tab").
- Rule: PAR-BACKEND-SEAM ("A single source of truth governs any cross-backend
  mapping"); architecture-rules.md, a framework sinks below its users.
- Fix: add to the event layer the rule, or the function, that gives the name of
  a key from its character (every letter and digit has its own name), and let
  every backend call it. L09-1 has the backend half.
- Reach: `KeyboardEvent.jl` (sealed), `Sdl.jl`, `Web.jl`, `Console.jl`.

### L06-2 The `MouseScroll` docstring states the wrong sign of `dy`

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the docstring at `MouseEvent.jl:186-187`: "positive to the right and down".
- Where: [MouseEvent.jl:186](../../../source/kernel/event/MouseEvent.jl#L186) 🔒
- Evidence: the docstring says "`dx` and `dy` are the amounts, positive to the
  right and down". The code that makes and reads the event uses the opposite
  sign for `dy`:
  - SDL passes the wheel value of SDL, which is positive when the wheel turns
    away from the user: `dx, dy = Int(evt.wheel.x), Int(evt.wheel.y)`
    ([Sdl.jl:3537](../../../source/sdl/Sdl.jl#L3537)).
  - The web page negates the browser value: `dy: -Math.sign(ev.deltaY)`
    (`asset/web/client.js:623`).
  - The scroll pane moves by `-evt.dy * scroll_step`, so a positive `dy` moves
    toward the start (`_self_scroll`, `source/widget/WidgetToGraphics.jl:4858`).
  A new backend that follows the docstring scrolls every pane the wrong way. The
  docstring also does not state the sign of `dx` that the readers use; the pane
  moves by `-evt.dx`. Whether that is correct for a tilt wheel is Suspected, and
  needs a check on a device.
- Rule: PAR-HONEST-DOCS; PAR-MODULE-DOCSTRING (the docstring is the contract).
- Fix: state "a positive `dy` is a turn away from the user, which scrolls up",
  and state the sign of `dx` that the readers use.
- Reach: `MouseEvent.jl` (sealed). No code change.

### L06-3 `@event_case` reads the field `modifiers`, and `EventPattern` calls `get_modifier_keys`

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:416](../../../source/kernel/event/EventPattern.jl#L416) 🔒,
  [EventPattern.jl:83](../../../source/kernel/event/EventPattern.jl#L83) 🔒
- Evidence: the compiled table tests
  `:($event.modifiers.$flag === $(flag in modifiers))`, and the reified pattern
  tests `_match_modifiers(pattern.modifiers, get_modifier_keys(event))`. For an
  event type with no `modifiers` field (`KeyChord`, the window events, the
  `PointerRest` of the tooltip package), a pattern with `;` throws a field error
  in `@event_case` and matches in `EventPattern` and `@gestures`. For an event
  type of another package that keeps its modifiers under another name and adds a
  `get_modifier_keys` method, the two give different answers. No such pattern
  exists today.
- Rule: bug (one syntax with two meanings).
- Fix: `_build_modifier_test` reads `get_modifier_keys($event)`.
- Reach: `EventPattern.jl` (sealed).

### L06-4 `build_event_field_bindings` throws for the catch-all rule

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:390](../../../source/kernel/event/EventPattern.jl#L390) 🔒
- Evidence: the docstring says "The result is `body` itself when the rule binds
  no field". For the rule `_ => …`, `rule.type` is `nothing`, and the first line
  calls `_get_positional_event_fields(rule.type)`, whose argument is typed
  `::Type` (line 20): a `MethodError`. The one caller, `@gestures`, rejects `_`
  before the call (`source/kernel/binding/Gestures.jl:96`), so the fault is
  latent.
- Rule: bug.
- Fix: return `body` when `rule.type === nothing`.
- Reach: `EventPattern.jl` (sealed).

### L06-5 A reified pattern accepts an unknown modifier name without an error

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:88](../../../source/kernel/event/EventPattern.jl#L88) 🔒,
  [EventPattern.jl:170](../../../source/kernel/event/EventPattern.jl#L170) 🔒
- Evidence: the macro path rejects an unknown flag (`_parse_modifiers`,
  line 279). The constructors `KeyDownPattern` and its siblings, and
  `EventPattern{E}(…)`, do no check. `KeyDownPattern(:s; modifiers =
  [:control])` then matches only an event with no modifier held, because
  `_match_modifiers` compares only the four known flags. `describe_event_pattern`
  gives `"+S"` for it, because the join of no label is `""` and the prefix adds
  `"+"`. The field is a mutable `Vector{Symbol}`, so a caller can also change a
  shared constant pattern such as `COMMAND_PALETTE_GESTURE`.
- Rule: bug; the syntax has one check in the macro and none in the constructor.
- Fix: check the flags in an inner constructor of `EventPattern`, or store the
  modifiers as `Union{ModifierKeys,Nothing}`.
- Reach: `EventPattern.jl` (sealed). The callers of `KeyDownPattern` (13 files)
  keep their syntax if the constructor converts.

### L06-6 `describe_event_pattern` calls a `MouseDown` a click

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:213](../../../source/kernel/event/EventPattern.jl#L213) 🔒
- Evidence: `_describe(::Type{MouseDown}, pattern) = "press " *
  _describe_button(pattern)` gives `"press Left click"`, and `MouseUp` gives
  `"release Left click"`. A `MouseDown` is not a click: the `MousePress`
  docstring says "A pattern that must fire on a click matches `MousePress`, not
  `MouseDown`". A person reads this text on the gesture map, because
  `@gestures` uses it as the default description. No rule has a `MouseDown` or
  `MouseUp` pattern today.
- Rule: bug (text for a person).
- Fix: `"Left button down"` and `"Left button up"`.
- Reach: `EventPattern.jl` (sealed).

### L06-7 Eight exported names have no user and no test

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [EventDefaults.jl:20](../../../source/kernel/event/EventDefaults.jl#L20) 🔒,
  [EventPattern.jl:130](../../../source/kernel/event/EventPattern.jl#L130) 🔒,
  [EventInterface.jl:54](../../../source/kernel/event/EventInterface.jl#L54) 🔒
- Evidence: `has_shift_modifier_key`, `has_alt_modifier_key`,
  `has_meta_modifier_key`, `KeyUpPattern`, `MouseDownPattern`, `MouseUpPattern`,
  `MouseEnterPattern` and `MouseLeavePattern` have no user in the three
  repositories and no test. `get_event_time` has callers only in tests: the
  recognizer reads the field (`event.time`, GestureRecognizer.jl:97, 101, 158),
  and so do the readers and the video backend. `has_ctrl_modifier_key` and
  `get_modifier_keys` have one caller each.
- Rule: code-quality-rules.md §4 ("A public function costs every call site");
  PAR-NEW-CODE-SHIPS-TESTS.
- Fix: keep the families, because one pattern constructor for each event type
  is a set that a reader can guess, and add one test for each name. Or remove the
  names that have no user. Let the recognizer call `get_event_time`.
- Reach: `EventPattern.jl`, `EventDefaults.jl` (sealed) for a removal;
  `EventModuleTest.jl` for the tests.

### L06-8 The parser API gives no way to ask whether a rule binds a field

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:247](../../../source/kernel/event/EventPattern.jl#L247) 🔒
- Evidence: `EventPatternRule.fields` is a `Vector{FieldPattern}`, and
  `FieldPattern`, `BoundField`, `LiteralField` and `ExpressionField` are not
  exported. The `binding/` layer must know whether a right side reads the event,
  so it compares object identity: `reads_event = bound_body !== escaped_body`
  (`source/kernel/binding/Gestures.jl:122`), with a comment that explains the
  indirection. The answer rests on a promise of `build_event_field_bindings` that
  its docstring gives in other words ("The result is `body` itself").
- Rule: PAR-MODULE-BOUNDARY-IS-API (a consumer gets a fact from an exported
  name).
- Fix: export a predicate, for example `has_bound_event_fields(rule)`.
- Reach: `EventPattern.jl`, `EventModule.jl` (sealed), `Gestures.jl`.

### L06-9 Public constructors take a `Bool` by position

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [KeyboardEvent.jl:37](../../../source/kernel/event/KeyboardEvent.jl#L37) 🔒,
  [ModifierKeys.jl:4](../../../source/kernel/event/ModifierKeys.jl#L4) 🔒,
  [MouseEvent.jl:9](../../../source/kernel/event/MouseEvent.jl#L9) 🔒
- Evidence: `KeyDown(key, modifiers, repeat::Bool; time)` is a short form with a
  positional `Bool`. The docstrings of `ModifierKeys(ctrl, shift, alt, meta)` and
  `MouseButtons(left, middle, right)` present the positional forms of four and
  three `Bool`s as public, and callers use them
  (`ModifierKeys(false, false, false, false)` in `Web.jl:539`,
  `ModifierKeys(modifiers.ctrl, true, modifiers.alt, modifiers.meta)` in
  `Console.jl:429`). The argument guard does not check a `Bool`.
- Rule: code-quality-rules.md §4, "A `Bool` is never positional".
- Fix: document only the keyword forms, and make `repeat` a keyword of the short
  `KeyDown` form.
- Reach: `KeyboardEvent.jl`, `ModifierKeys.jl`, `MouseEvent.jl` (sealed); the
  callers in `Sdl.jl`, `Web.jl`, `Console.jl` and the tests.

### L06-10 `EventPattern.jl` is over the size budget of a file

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:222](../../../source/kernel/event/EventPattern.jl#L222) 🔒
- Evidence: 521 lines. The file holds two parts for two kinds of reader: the
  reified pattern and its text (lines 1–220), and the parser with `@event_case`
  (lines 222–521).
- Rule: code-quality-rules.md §5 (a file: 500 lines).
- Fix: move the parser and `@event_case` into a fragment of their own.
- Reach: `EventPattern.jl`, `EventModule.jl` (sealed).

### L06-11 The matcher iterates an abstract field on each call, and `@event_case` allocates on each call

- Category: Types/performance · Severity: Low · Confidence: Suspected (needs `@allocated` on `fire_gesture_bindings`)
- Where: [EventPattern.jl:56](../../../source/kernel/event/EventPattern.jl#L56) 🔒,
  [EventPattern.jl:517](../../../source/kernel/event/EventPattern.jl#L517) 🔒
- Evidence: `fields::NamedTuple` is an abstract field type, so
  `for (name, value) in pairs(pattern.fields); getfield(event, name) == value`
  runs with dynamic dispatch. `fire_gesture_bindings` calls
  `matches_event_pattern` for each `GestureBinding` of each document on the path,
  for each event. Each evaluation of `@event_case` makes
  `_nomatch = Base.RefValue{Any}()`, and many readers evaluate it for each event.
- Rule: a cost on a hot path; this is not the carve-out for cells.
- Fix: `EventPattern{E,F<:NamedTuple}`, and one sentinel at module level for
  `@event_case`.
- Reach: `EventPattern.jl` (sealed).

### L06-12 Two names of the pattern language do not follow the naming table

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [EventPattern.jl:166](../../../source/kernel/event/EventPattern.jl#L166) 🔒,
  [EventPattern.jl:126](../../../source/kernel/event/EventPattern.jl#L126) 🔒
- Evidence: `describe_event_pattern` produces text, and the verb table gives
  `format_` for "it produces text". This is a judgement, because "describe" reads
  as English. `KeyDownPattern` and the nine sibling constructors are functions
  with names of types; naming-rules.md lists them as "Gesture patterns" among
  the types.
- Rule: naming-rules.md, "The verb follows the nature of the work".
- Fix: the owner decides both. Planned: plan/pending/naming-rule-violations.md,
  item 25 (the pattern constructors).
- Reach: `EventPattern.jl`, `EventModule.jl` (sealed); the callers of
  `describe_event_pattern` in 4 source files and 3 test files.

### L06-13 Docstrings of the layer hold an example that throws, and pixels of no stated kind

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [MouseEvent.jl:23](../../../source/kernel/event/MouseEvent.jl#L23) 🔒,
  [MouseEvent.jl:48](../../../source/kernel/event/MouseEvent.jl#L48) 🔒,
  [WindowEvent.jl:34](../../../source/kernel/event/WindowEvent.jl#L34) 🔒,
  [EventInterface.jl:1](../../../source/kernel/event/EventInterface.jl#L1) 🔒
- Evidence:
  - The `MouseButtons` example is `MouseMove(10, 20, MouseButtons(:left),
    ModifierKeys(); time).buttons.left`. `; time` passes `time = Base.time`, the
    function, and the keyword is `time::Real`: a `TypeError`. Commits c7ad41e8 and
    4519761f corrected the same fault in `EventPattern.jl` and `ModifierKeys.jl`,
    not here.
  - `MouseDown`, `MouseMove` and `WindowResize` say "pixel coordinates" and "in
    pixels". The backends deliver logical pixels (`_to_logical` in `Sdl.jl`), and
    the device layer defines two kinds of pixel.
  - The header of `EventInterface.jl` says where the `get_modifier_keys`
    methods are, but not that the body of `get_event_time` is in
    `EventDefaults.jl`.
- Rule: code-quality-rules.md §1 ("A contract fragment says where each body
  lives"; an example runs); PAR-HONEST-DOCS.
- Fix: `time = 0.0` in the example; "logical pixels"; name `EventDefaults.jl`.
- Reach: `MouseEvent.jl`, `WindowEvent.jl`, `EventInterface.jl` (sealed).

### L06-14 The design documents describe the event layer as it was before its audit

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: `documentation/package/kernel/devices-and-backends.md`,
  `documentation/design/system-anatomy.md`,
  `documentation/package/kernel/architecture.md`
- Evidence:
  - devices-and-backends.md:371-386: "seven fragments"; a second row
    `EventModule.jl (EventModule) — the event pattern language` for the file
    `EventPattern.jl`; no `get_event_time`.
  - devices-and-backends.md:388 and :402: two headings `### EventModule`.
  - devices-and-backends.md:406-417: `matches(pattern, event)`,
    `describe(pattern)`, `parse_event_rule`, `event_pattern_expr` and
    `event_field_bindings` (the old names), and "The field table each pattern may
    bind is *derived* from `EventModule`'s own exports, so a new event type is
    matchable the moment it is exported". Since a730fabd a type resolves in the
    module of the pattern, and the export list has no part in it.
  - devices-and-backends.md:61: `WindowQuit(; time = t) # the window was
    closed`. `WindowQuit` is a request to quit the application; `WindowClose` is
    the close of one window.
  - system-anatomy.md:369-371: "(EventPattern, matches, describe, @event_case)".
  - architecture.md:167: "`EventModule` (…) and `EventModule` (`EventPattern`,
    `@event_case`)"; architecture.md:107 gives `EventModule` the layer 3.
- Rule: PAR-UPDATE-THE-GUIDE; PAR-HONEST-DOCS.
- Fix: write the event part of devices-and-backends.md again from the module
  docstring, and correct the lines in the other two documents.
- Reach: three documents. No source.

### L06-15 Tests do not cover several promises, and one test file has the name of no file

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/event/EventCaseTest.jl`, `test/kernel/event/EventModuleTest.jl`
- Evidence:
  - No test for: the four `has_*_modifier_key`; `get_modifier_keys` of a
    `KeyChord` or of a window event; `get_event_time` of an event type of another
    module; the five pattern constructors of L06-7; the text of a `KeyUp`,
    `MouseDown`, `MouseUp` or `KeyChord` pattern; an unknown flag in a reified
    pattern (L06-5); `;` on an event with no `modifiers` field (L06-3);
    `build_event_field_bindings` on `_` (L06-4).
  - `EventCaseTest.jl` tests `@event_case`, which is in `EventPattern.jl`; no
    file `EventCase.jl` exists. The test file has no module docstring, and it
    ends in `export test_event_case`, which `KernelSuite.jl:104` exports again.
- Rule: naming-rules.md ("`<Thing>Test.jl` — `<Thing>` is the file it tests");
  PAR-MODULE-DOCSTRING; PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add the cases; rename the file `EventPatternTest.jl`, give it a
  docstring, and remove its `export`.
- Reach: the two test files and `ProjecturedKernelTest.jl` (the include).

## Accepted before, not raised again

- Every event holds a mandatory `time::Float64` as its last field, on the clock
  of `time()` (a wall clock), and the default equality compares the time
  (plan/done/gesture-layer-audit.md, D1 to D3, 2026-09-25).
- `MouseButtons` holds every held button; an event type resolves in the module
  of the pattern; items 1 to 13 of plan/done/event-layer-audit.md.
- `KeyChord` has no pattern syntax and no detail in `describe_event_pattern`
  (deferred: plan/pending/key-chords-from-bindings.md).
- The mouse constructors with four or more positional arguments carry a
  `# @positional:` marker (plan/done/keyword-arguments.md).

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `EventInterface.jl` holds three abstract types and
  two bodiless generics, and the kernel guard checks it.
- PAR-MODULE-BOUNDARY-IS-API and PAR-QUALIFIED-EXTENSION: the layer imports
  nothing, and each fragment defines bare in the one namespace.
- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS: no mutable global state.
- The export block: one statement for each fragment, in include order (the
  export guard passes; `EventModule` left `EXPORT_UNMIGRATED` on 2026-09-25).
- PAR-MODULE-DOCSTRING and the fragment headers; no history comment; no line
  over 90 characters; no requirement cited in the source (PAR-CITE-EXCEPTIONS-ONLY).
- The names of the events (`<Source><Action>`), the predicates (`has_…`,
  `matches_…`) and the builders (`build_…_expr`).
- The time contract: every concrete event of the kernel holds `time` last, each
  short constructor takes it as a keyword, and `_get_positional_event_fields`
  leaves it out of a pattern.
