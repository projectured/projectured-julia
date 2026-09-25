# The audit of the event layer

The owner asked for a review of the whole shape of the event layer
(`source/kernel/event/`) and a re-audit against the rules in
`documentation/rule/`. The shape stays: an interface, one fragment for each kind
of event, the defaults, and the pattern language. The re-audit found defects in
the pattern language, a false constructor in a docstring, a syntax that only a
comment documents, text that breaks the writing rules, and thin tests.

On 2026-09-25 the owner approved every suggested change, gave permission to
unseal the nine files of the layer, and added two changes:

- `buttons` holds every mouse button that is held, because a person can press
  more than one at the same time.
- `@event_case` is extensible for an event type that another package defines.

`PointerRest`, the synthetic event of the tooltip slice, is the business of that
package and is not part of this plan.

## Items

1. `describe_event_pattern` drops the modifiers of a `KeyPress` pattern:
   `KeyPress('a'; ctrl)` reads as `"a"`.
2. The docstring of `MousePress` promises `MousePress(button, x, y, count)`, which
   throws a `MethodError`.
3. `@event_case` matches only the event types that `EventModule` exports. It
   becomes extensible (the owner's addition).
4. The pattern constructors do not agree: `KeyPressPattern` takes `guard` and
   `label` by position and no modifiers; `MouseMovePattern` and three more take
   three optional arguments by position.
5. `matches_event_pattern` infers `Any`.
6. A window event reads as `"windowresize"`.
7. The syntax of the patterns is only in a code comment; the module docstring does
   not list `EventPattern.jl`.
8. The docstring of `KeyDown` lists the key names as closed, and misses `:minus` and
   `:slash`.
9. The writing rules: objects that know and refuse, "may", "e.g.", metaphors,
   comments that repeat docstrings, 14 lines over 90 characters.
10. Docstrings that describe a reader and "select on click".
11. `buttons` holds one button (the owner's addition: it holds all).
12. The export block has two statements, not one for each fragment.
13. Most of the pattern language has no test, and `EventModuleTest.jl` imports
    `EventModule` twice.

## Design (confirmed by the owner on 2026-09-25)

- **`MouseButtons`, like `ModifierKeys`.** An immutable struct of three flags,
  `left`, `middle` and `right`, with a keyword constructor and a constructor from
  button names: `MouseButtons()`, `MouseButtons(:left)`, `MouseButtons(:left,
  :right)`. `MouseMove`, `MouseEnter` and `MouseLeave` hold `buttons::MouseButtons`.
  It is isbits, so an event still allocates nothing.
  - The 77 constructions that pass a button name, such as `MouseMove(x, y, :left,
    mods)`, change to `MouseButtons(:left)`, by a rewrite. They are mostly tests,
    and three tools. One way to write the buttons is clearer than a second
    constructor that takes a name.
  - The four tests of `buttons === :none` compare with `MouseButtons()`: the SDL
    backend, the tooltip probe, one widget reader and one SDL test.
  - The SDL backend reads every held button from the mask of
    `SDL_GetMouseState`, in place of `_held_button`, which kept the first.
  - `describe_event_pattern` and the key names do not change.
- **An event type resolves in the module of the pattern.** `@event_case` and
  `@gestures` pass the module they expand in (`__module__`) to
  `parse_event_pattern_rule(expr; scope)`. The parser looks the type name up in
  that module first, and in `EventModule` after it. Any concrete `Event` type is
  then matchable where its name is visible, with no registry and no global state.
  The type must exist before the macro expands, as for any type a macro names.
  - `EventPatternRule` holds the event type itself, not its name, and the fields
    come from the type (`fieldnames` without `modifiers`). The table
    `_EVENT_TYPES` goes.
  - `describe_event_pattern` describes a custom event by its type name in words, as
    item 6 does for a window event: `PointerRest` reads as `"pointer rest"`.

## Steps

- [x] 1. Unseal the nine files, and add this plan.
- [x] 2. The pattern language: items 1, 3, 4, 5, 6, with tests.
- [x] 3. `MouseButtons` (item 11): the event layer, the SDL backend, the four tests
  of `:none`, and the 77 constructions.
- [x] 4. The texts: items 2, 7, 8, 9, 10, and the export block of item 12.
- [x] 5. The tests of item 13.
- [x] 6. Verification: `test_kernel`, `test_substrate`, the SDL tests that can run
  here, the guards, a precompile of every package, and omnet-julia against the
  worktree.

## What the implementation found

- The web backend and its page also carried one button. `asset/web/client.js` sent
  the first held button by name, and `Web.jl` made a `MouseMove` from that name.
  The page now sends the button mask of the browser, and `Web.jl` makes
  `MouseButtons` from it: 1 is the left, 2 the right and 4 the middle button.
- `ProjecturedSdl` and `ProjecturedWeb` import the event names by a list, so
  `MouseButtons` had to join both lists. A precompile did not show this: Julia
  resolves a name in a function body only when the function runs. The SDL suite
  showed it with five `UndefVarError`s.
- The rewrite changed 81 constructions in 22 files: 73 by the pattern of the
  plan, and 8 whose arguments hold parentheses, by hand.
- `build_event_field_bindings` returns escaped names, which are valid only in the
  expansion of a macro, so its test uses a small macro, as a caller does.
- The private helpers of the pattern language start with a verb now, as in the
  cell layer: `_match_modifiers`, `_get_modifier_prefix`, `_build_rule`.
- The export guard reports two violations in `source/help/HelpModule.jl`, a module
  of the Help package that came to `main` from another session. `main` reports the
  same two, so they are not part of this plan.

## Verification

- Every package of `environment/all` precompiles.
- `test_kernel()`: the six known failures; `EventModule` 48, `EventCase` 26,
  `GestureBinding` 81, `GestureRecognizer` 49.
- The same on the branch and on `main`: `test_substrate()` 80850 pass with the five
  known failures of the split pane drag test, `test_chart()` 345, `test_shell()`
  202, `test_projections()` 450 pass, 3 fail, 2 error, and `test_video()` 34.
- `test_sdl()` 117 on the branch after the import fix, as on `main`.
- `test_web_backend()` 31, with a test of a motion that holds two buttons.
- The export guard passes for `EventModule`, and the naming guard reports nothing.
- omnet-julia against the worktree: every package precompiles, and
  `test_presentation()` gives 1694 pass, 12 fail, 2 error and 1 broken, with the same
  failing tests as before the change. Its scratch environment needed a
  `Pkg.resolve()`, because `ProjecturedFileSystem` now depends on
  `ProjecturedFocus`.
