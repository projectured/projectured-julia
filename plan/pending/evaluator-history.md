# Up and Down recall the history of the evaluator

**Status (2026-09-22): IN PROGRESS.** Worktree
`../projectured-julia-evaluator-history`, branch `evaluator-history`, from `main`
at `c8e55cf7`.

**Goal:** in the bottom form of an Evaluator tab, Up on the first line of the code
recalls an older form, and Down on the last line recalls a newer one, as the Julia
REPL does. In an older form, Up and Down at the edge of the code move the caret to
the form above or below.

## 1. Decisions

The owner decided all seven on 2026-09-22.

- **D1. The history is the forms of this tab**, oldest to newest. The bottom form,
  where a person types, is not part of it. A history that is saved between
  sessions can come later.
- **D2. A recall replaces the text of the bottom form** with the code of the
  older form. It does not move the caret into the older form.
- **D3. Only the bottom form has a history.** In an older form, Up on the first
  line moves the caret to the form above, and Down on the last line to the form
  below. So a recall never overwrites code that was evaluated.
- **D4. The draft comes back.** What a person typed before the first Up is kept,
  and Down past the newest entry shows it again.
- **D5. Prefix search.** The text before the caret, when the navigation starts, is
  the prefix. Up and Down show only the entries that start with it.
- **D6. Every evaluated form is an entry**, also one whose evaluation failed. An
  entry whose text is the same as the text shown now is skipped, so a key always
  changes something.
- **D7. The caret goes to the end** of the recalled code. In code of several
  lines, Up then moves through its lines before it goes further back.

## 2. What exists

- **The text layer moves the caret between lines.** The reader of
  `TextToGraphics` answers Up and Down with the line above or below. On the first
  line, Up finds no line and answers nothing; on the last line, Down does the
  same. A key that the text layer declines goes up the chain to the gesture table
  of `EvaluatorToplevel`, which already holds Enter and Shift+Enter. So D7 and the
  rule "Up on the first line" come from the chain as it is.
- **An empty line has no place in the text layer.** `_layout_group` records a
  `SegmentCoordinate` only for a line with glyphs. A caret on an empty line finds
  no segment, so Up and Down answer nothing there, and a caret above or below an
  empty line jumps over it. With a history, Up on an empty line in the middle of
  the code would recall an older form. That must be fixed first.
- **An evaluation moves the complete selection** from the root with
  `_select_under!`, so the caret of a recall can move the same way.
- `EvaluatorToplevel` holds `elements` and `follow_end`, the view state of its
  scroll pane.

## 3. Design

### The text layer: an empty line has a place

- `_layout_group` records a zero-width `SegmentCoordinate` for an empty sub-line:
  an empty span, a line between two line breaks, and the line after a line break
  at the end of a span. It stands where the caret stands, and it is as high as a
  line of the span's font. It changes no line height and draws nothing.
- The rule that makes a blank line one row high asks whether the group has a
  glyph, and no longer whether it has a coordinate.
- `_translate_click` indexes the drawn elements, so it counts only the
  coordinates that draw something.

### The evaluator

- **View state on `EvaluatorToplevel`**, beside `follow_end`:
  - `history_position::Int = 0`: 0 is the draft; `k` is the `k`-th entry, counted
    from the newest.
  - `history_draft::String = ""`: what the bottom form held before the navigation.
  - `history_prefix::String = ""`: the prefix of D5.
- **`RecallEvaluatorFormOperation(toplevel, direction)`**, with `direction`
  `:older` or `:newer`. It holds the toplevel and no path, so it travels up the
  chain unchanged, as `EvaluateSelectedFormOperation` does.
  - The entries are the sources of forms `1` to `n - 1`, newest first.
  - When `history_position` is 0, or the shown text is not the entry at that
    position because a person edited it, the navigation starts again: the draft is
    the shown text, the prefix is the text before the caret, and the position is 0.
  - `:older` takes the first entry past the position that starts with the prefix
    and is not the shown text. If there is none, nothing changes.
  - `:newer` takes the first such entry before the position. If there is none, the
    position is 0 and the draft comes back.
  - The bottom form takes the text, and the caret goes to its end through
    `_select_under!`.
- **The gestures**, with no modifier, so Shift+Up and Alt+Up keep their meaning:
  - Up in the bottom form: `:older`. Down in the bottom form: `:newer`.
  - Up in form `i < n`: the caret goes to the end of form `i - 1`; in form 1,
    nothing. Down in form `i < n`: the caret goes to the start of form `i + 1`.
    Both are a `ReplaceSelectionOperation` with a path from the toplevel.
- **An evaluation resets** the three fields.

## 4. Steps

- [ ] **Step 1. An empty line has a place in the text layer.** Test in
      `TextToGraphicsTest.jl`: Up and Down stop on an empty line, a caret on an
      empty line moves up and down, and an empty span keeps its one line of height.
- [ ] **Step 2. The history of the evaluator.** The three fields, the operation
      and the gestures. Tests in `EvaluatorToplevelTest.jl` for D1 to D7.
- [ ] **Step 3. Through the window.** A case in `ApplicationTest.jl` on a standing
      iomap: type and evaluate two forms, Up recalls the newest, Up again the
      older, Down comes back, Down again restores the draft, and code of two lines
      takes one Up to leave its second line.
- [ ] **Step 4. Documents and landing.** `conversation.md` and `text.md` say what
      the keys do. The plan moves to `plan/done/`, and `main` fast-forwards to the
      branch.

## 5. How it is tested

The narrowest suites: `test_text_to_graphics()`, `test_word_wrapping()`,
`test_evaluator_toplevel()` and `test_application()`. The text layer is shared, so
its users run too: `test_text()`, `test_widget_text_editing()`,
`test_text_range_selection()`, `test_assistant_composer_panel()` and
`test_mouse_clicks()`. On `main` at `c8e55cf7`, `test_mouse_clicks()` fails 10 of
45 and 3 are broken; any other failure is new.
