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
2. **The backends:** SDL, web and console give the `KeyPress` of Return and Tab.
3. **The meanings** of Return, Tab and a plain Space read the `KeyPress`, with
   the same modifier pattern as before.
4. **The rules that insert typed text** take printable text only; a block of
   lines names `'\n'` as "Break the line".
5. **The tests**, the scripted events and the example harness send what a
   backend sends.
6. **omnet-julia and inet-julia**, on branches of the same name, to land with
   this one.
7. **The documents.**
8. **A sweep** against step 0.
