# An evaluated form becomes a Julia document

**Status (2026-09-23): IN PROGRESS.** Worktree
`../projectured-julia-evaluator-parses-forms`, branch `evaluator-parses-forms`,
from `main` at `232c9c35`.

**Goal:** when a person presses Enter in an Evaluator tab, the code of the form
changes from a string to a Julia document, so the form keeps its syntax
structure after it runs. The screen does not change under the person's hands:
a form whose parse would rewrite its text stays a string.

## 1. Decisions

The owner agreed to D1 to D3 and to D5 on 2026-09-23. D4, D6 and D7 follow from
them and are recorded here so that the review can see them.

- **D1. Swap only on an exact round trip.** On Enter, the typed text is parsed
  with `parse_natural_text(:jl, …)`. When `print_natural_text` of the result is
  the same as the typed text, the form holds the parsed document. When it is
  not, the form keeps its `PrimitiveString`. So a comment, the person's own
  spacing and a block are never rewritten or lost.
- **D2. The switch is a field of the document**, not a parameter of the
  projection: `EvaluatorToplevel.parse_evaluated_forms::Bool = true`. The swap
  replaces the content of `element.form`, which is an edit of the document, not
  a change to how it is drawn. The alternative, a projection that parses the
  string for display only, has no way back: the Julia projection's IO map
  inverts to a Julia document, not to a range of characters in a string.
- **D3. The default is on.**
- **D4. The typed text goes into the form's `source` field**, which
  `EvaluatorForm` already has and the assistant already fills.
- **D5. Surrounding whitespace is stripped before the compare.** A trailing line
  break from Shift+Enter must not block the swap. So the round trip compares
  `strip(text)`, and a swapped form recalls without its surrounding blank
  lines.
- **D6. Evaluation runs the text that was typed**, read before the swap. The swap
  changes only what the form holds after the evaluation.
- **D7. A form that does not parse stays a string**, and so does every form when
  no Julia parser is loaded (`has_natural_parser(:jl)` is false).

## 2. What exists

- **The natural-format seam.** The conversation package already depends on
  `ProjecturedNatural` and calls `parse_natural_text` and `has_natural_parser`
  (`source/conversation/ConversationEditor.jl:316`). No new dependency.
- **The assistant does the same for a tool call.** `_eval_form_doc` in
  `source/assistant/AssistantTurn.jl:367` parses the code of an
  `execute_julia_code` call and falls back to a `PrimitiveString`. It swaps
  always, with no round-trip rule, so it drops comments today.
- **A parsed form already reads back.** `_get_form_source_text(form::Document)`
  prints it (`source/conversation/Evaluator.jl:250`), and the history uses that
  function. With D1 the print of a swapped form is its typed text, so a recall
  gives back what was typed. A form that the person edits later recalls its
  edited text, the same as a string form does today.
- **The round trip, measured 2026-09-23** on 14 snippets. Four print back
  exactly: `x = 1`, `s = "a\tb"`, `using Printf` and
  `GraphicsCircle(10, 10, 10)`. Ten change: comments are dropped (the Julia domain
  has no comment type), spacing is normalized (`f(a,b)` becomes `f(a, b)`),
  indentation becomes two spaces, blank lines are dropped, a lambda gains
  parentheses (`x -> x^2` becomes `(x) -> x ^ 2`), and a docstring reflows.
- **The Julia domain takes a caret poorly.** Its type-in baseline is 0 of 6: a
  name leaf renders no caret. Editing a swapped form is weaker than editing a
  string one. This plan does not fix it.

## 3. What breaks, and the fix

- **Up and Down into a form above.** `_make_up_operation` and
  `_make_down_operation` put the caret at `elements[i].form.value{k}`
  (`_make_form_caret_reference`). A Julia document has no `value` field, so that
  reference names nothing. *As built:* a parsed neighbor is selected whole,
  `elements[i].form` ending in `EmptyReference()`. The plan first said the caret
  goes to the first or last position of the parsed form. That position is known
  only through the projection of the form, which a gesture of the toplevel does
  not see; the enumeration of positions exists only as a test helper
  (`test/substrate/document/SelectionEnumeration.jl`). A caret on a Julia
  identifier also draws nothing today. Measured before the choice: the whole
  selection draws a highlight exactly over the code of the form, Up and Down
  from it reach the neighbors, Enter on it evaluates the form again, and a
  typed key on it answers nothing.
- **Shift+Enter in a swapped form.** `_make_form_newline_operation` declines a
  form that is not a `PrimitiveString`. That stays: a line break in a Julia
  document is an edit of the Julia domain, not of the evaluator.
- **The existing test "UP and DOWN in a form above move the caret to its
  neighbors"** (`test/projectured/editor/EvaluatorToplevelTest.jl:290`) assumes
  string forms above. With D3 its forms swap, so the test changes with step 2.

## 4. Steps

Work in the worktree `../projectured-julia-evaluator-parses-forms`, branch
`evaluator-parses-forms`, one commit per step. Do not land on `main` without the
owner's word.

- [x] **Step 1. The field and the swap.** *Done.* The swap runs after the caret
  has moved to the fresh form, so no selection names a place in the string it
  replaces. The print of the parsed document is inside the `try` as well: a
  failure there keeps the string. An error result carries a stack trace that
  names the line of its caller, so the test compares an error by its first
  line. `test_evaluator_toplevel()` passes; `test_conversation()` keeps its one
  known failure. Add `parse_evaluated_forms` to
  `EvaluatorToplevel` and to its positional constructor. In
  `evaluate_operation(editor, ::EvaluateSelectedFormOperation)`, after the
  result is set, swap the form by D1, D5 and D7, and set `source` by D4.
  Tests: a round-trip form becomes a `JuliaDocument`, and its print is its
  typed text; a form with a comment stays a `PrimitiveString` and keeps the
  comment; a form that does not parse stays a string; with the field `false`
  every form stays a string; `source` holds the typed text; the result of the
  evaluation is the same in all four cases.
- [x] **Step 2. Up and Down reach a swapped form.** *Done:* a parsed neighbor
  is selected whole (see §3). The test checks that the selection ends at the
  form, that the highlight lies over its code, the walk both ways, the caret in
  the bottom form, and Enter on a selected form. 124 of 124 pass.
  Originally: the caret goes to the last or first position of a parsed form. Test the coordinate of the caret, not
  only that a selection exists. Change the test at line 290 to cover a string
  form above and a parsed form above.
- [ ] **Step 3. The history over swapped forms.** Test that Up in the bottom form
  recalls the typed text of a swapped form, and that the prefix search finds it.
- [ ] **Step 4. It renders.** Open an Evaluator tab in the application, type
  `GraphicsCircle(10, 10, 10)` and `x = 1  # why`, and press Enter on each. The
  first form draws as Julia, the second as the typed string, and the `>` and
  `=` column stays aligned in both. A test of what renders, not of what the
  operation returns.
- [ ] **Step 5. The package document.** Add a paragraph on the swap and its rule
  to `documentation/package/conversation/conversation.md`.

Run for each step: `test_evaluator_toplevel()`, and `test_conversation()`, whose
package suite loads no Julia domain and so must keep every form a string. The
known baseline of `test_conversation()` is one failure, the import check of
`make_insertion_document`.

## 5. Not in this plan

- **A comment type in the Julia domain.** With it, D1 could relax towards
  "swap always", and the assistant would stop dropping comments.
- **The assistant's `_eval_form_doc` taking the round-trip rule.** One call, but
  it changes what the assistant shows, so it is its own decision.
- **A `@projection_gestures` macro** with the grammar of `@gestures`, for the six
  hand-written `get_projection_gesture_bindings` methods.
- **The caret in the Julia domain** (type-in baseline 0 of 6).
- **The cell count of a long session.** Each swapped form is a tree of cells
  instead of one string. Not measured; measure if a long session feels slow.
