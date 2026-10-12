# Return and Tab give a KeyPress

> **Kind:** plan · **Status:** in progress, 2026-10-12, on the branch
> `return-keypress` (worktree `projectured-julia-return-keypress`). The owner
> decided the rule on 2026-10-12 (§1). No question is open. ·
> **Stands on:** [gesture.md](../../documentation/package/kernel/gesture.md),
> [devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md),
> [a-text-block-holds-only-lines.md](../done/a-text-block-holds-only-lines.md)

## 1. The rule

The owner's words, 2026-10-12: "return should also be a KeyPress (down + up)",
then "a keypress is fine as it is currently", and "holding down the SPACE or
ENTER should repeatedly type that".

- A `KeyPress` stays as it is: it comes at the down of a key that types a
  character, and it comes again for each repeat while the key is held.
- Return gives `KeyPress('\n')`, and Tab gives `KeyPress('\t')`, after its
  `KeyDown`, with the modifiers of the key, at each down and each repeat.
- Every meaning of Return, Tab and a plain Space reads the `KeyPress`. No binding
  and no reader gives a meaning to `KeyDown(:return)`, `KeyDown(:tab)` or a plain
  `KeyDown(:space)`. A chord, such as Ctrl+Space or Ctrl+S, types no character
  and stays a `KeyDown`.
- No state waits for a `KeyUp`. The owner rejected a rule where a taken `KeyDown`
  stops the `KeyPress` of the same press: "a KeyDown is only a down, what if the
  up never arrives?"

## 2. Why

One press of Return now has its meaning on a `KeyDown`, and Space already gives
a `KeyDown` and a `KeyPress` that two rules can both take. A key that types a
character must reach the rules of typed text as one event, so that a value that
a typed Return or Tab can reach decides once: it takes the character, or it
declines it. This also closes item 2 of the report after the landing of
[a-text-block-holds-only-lines.md](../done/a-text-block-holds-only-lines.md): a
typed Return reaches every rule that inserts typed text, so each of them must
take the break or decline it.

## 3. What it touches

- **The kernel:** the docstring of `KeyPress` and `KeyDown`
  (`event/KeyboardEvent.jl`), and the help text of a `KeyPress` pattern
  (`gesture/GesturePattern.jl`), which names `'\n'` "Return", `'\t'` "Tab" and
  `' '` "Space".
- **The backends:**
  - SDL: an `SDL_KEYDOWN` of Return, keypad Enter or Tab gives the `KeyDown` and
    then the `KeyPress`. SDL gives no `SDL_TEXTINPUT` for a control character,
    so the backend makes the `KeyPress`. `pending_input` holds one owed event;
    it becomes a queue.
  - Web: the `keydown` message of Enter or Tab gives the `KeyDown` and then the
    `KeyPress`, in `WebBackend.jl`; the client sends no `keypress` for them.
  - Console: the bytes CR and LF give `KeyPress('\n')`, and HT gives
    `KeyPress('\t')`, as a printable byte gives its `KeyPress` now.
- **The meanings:** about 33 places read Return, 17 read Tab, and 3 read a plain
  Space as a `KeyDown`: bindings in `@gestures` tables and `GestureBinding`s,
  and readers that test `key === :return` or `key === :tab`.
- **The rules that insert typed text** (`KeyPress(_, t)` and the readers of any
  `KeyPress`): they take printable text only, `!any(iscntrl, t)`, so `'\n'` and
  `'\t'` reach only a rule that names them. Without this guard, Ctrl+Return
  would type a break where only a plain Return breaks a line.
- **The tests:** 70 lines send Return and 32 send Tab as a `KeyDown`, in 40
  files; the scripted events of `Application.jl` and the example harness.
- **omnet-julia and inet-julia:** 11 lines in drivers, precompile workloads and
  tests.
- **The documents** that name `KeyDown(:return)` or `KeyDown(:tab)` as a meaning.

## 4. What it does not touch

- Tab types no tab character into a text: a block of lines, a string and a
  type-in decline `'\t'`, as they decline `KeyDown(:tab)` now, and Tab keeps its
  meanings (the next field, the next hole, the next focus).
- A chord stays a `KeyDown`.
- `KeyDown` and `KeyUp` stay the facts of the key for every key.

## 5. Steps

0. **Baseline** on main at the base of the branch: `test_platform` (12 GB), the
   umbrella tests that send Return or Tab, `test_console`, the web and SDL
   backend tests, and the omnet and inet tests in §3.
1. **The kernel:** the docstrings and the help text of a `KeyPress` pattern.
   *Built (2026-10-12), `78dc30100`.* The help names `'\n'` "Return", `'\t'`
   "Tab" and `' '` "Space", so `KeyPressPattern('\n'; modifiers = [:shift])`
   reads "Shift+Return".
2. **The backends:** SDL, web and console give the `KeyPress` of Return and Tab.
   *Built (2026-10-12), `08965e959`.* The kernel holds the rule once:
   `find_typed_character(key)` gives `'\n'` for `:return`, `'\t'` for `:tab`, and
   `nothing` for any other key (a new export of `EventModule`). SDL keeps the owed
   events in a queue, `pending_inputs`, which replaces the one owed event; an
   event behind a held motion goes before the `KeyPress` that its poll queued.
   Keypad Enter is `:return` now. The web backend makes the `KeyPress` in Julia,
   after the `KeyDown`, since the client prevents Enter and Tab. The console gives
   the `KeyPress` alone, as it gives a letter, also for Shift+Tab (`ESC [ Z`).
3. **The meanings** of Return, Tab and a plain Space read the `KeyPress`, with
   the same modifier pattern as before.
4. **The rules that insert typed text** take printable text only; a block of
   lines names `'\n'` as "Break the line".
   *Steps 3 and 4 built together (2026-10-12)*, file by file, since a table that
   moves Return to a `KeyPress` also guards its insert rule. Decisions:
   - The guard is `!any(iscntrl, t)`, in a `when` of the rule, or the `guard` of a
     `KeyPressPattern`: `TextBlock`, `PrimitiveString`, `PrimitiveInsertion`,
     `JuliaInsertion`, the type-in of `InsertionToSyntaxLeaf` and the tab name.
     The readers of any `KeyPress` that test `isprint` already (the palette, the
     navigator address, the choice list, an open table cell) keep that test.
   - Widgets: `_is_plain_typed(evt, chars...)` beside `_is_plain_key`; Return
     and Space activate a button, a checkbox, a switch, a radio and a list by
     `_is_plain_typed(evt, '\n', ' ')`. The text area needs no rewrite of
     Return into `'\n'` any more.
   - Tables: Return navigates by a `KeyPress` method of `_wt_key_navigate` and of
     `_read_table_parts_key`, and an open cell reads its exit (`:return`, `:tab`,
     `:backtab`, `:escape`) by `_find_open_cell_exit`. The plain `read_intent` of
     both tables sends a `KeyPress` to the reader of the table, as a `KeyDown`.
   - The choice list of the navigator does nothing for a `KeyPress` of a control
     character without Ctrl, Alt or Meta, as it did for the `KeyDown` of Tab.
   - XML: Space inserts an attribute by `override(KeyPress(' '))`: a space typed
     in the tag name reaches the name first, and the action answers only in the
     tag or the attributes, so in a child text the space goes into the text.
   - `TextToGraphics` declines the `KeyDown` of Tab and Return before its
     geometry arms, since the text no longer takes the `KeyDown` of Return.
   - Shift+Space and Ctrl+Space in a table stay `KeyDown` rules: Ctrl+Space types
     nothing, and the two select the row and the column as a pair.
5. **The tests**, the scripted events and the example harness send what a
   backend sends.
6. **omnet-julia and inet-julia**, on branches of the same name, to land with
   this one.
7. **The documents.**
8. **A sweep** against step 0.
