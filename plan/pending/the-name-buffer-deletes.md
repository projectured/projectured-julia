# The name buffer deletes, and the open gaps close

## Why

Three items were open after `plan/done/the-type-search-reads-the-modules-once.md`,
and one report arrived:

- **The report:** Backspace and Delete do nothing in the name buffer
  (`DocumentInsertion`) of a new tab.
- `get_insertion_candidates` runs `insertable(T)` first in its filter.
- The assertion `string(node.selection) == ".content.value{0}"` in
  `DocumentInsertionTest.jl` fails.
- The warm-up does not press Backspace or Delete in the name buffer.

## What the report is

Reproduced headless in the application window: after "evx", Backspace and Delete
answer a bare `KeyDown`, and the buffer keeps "evx".

`SyntaxLeafToText` lowers Backspace to a `ReplaceStringRangeOperation` on the
one-character range it removes, `::SyntaxLeaf.value::TextString[3]`. The
generic `Intent` bridge then offers the leaf that operation and not the key, so
the Backspace binding of `InsertionToSyntaxLeaf` never runs. The leaf's
`ReplaceStringRangeOperation` reader maps the reference backward, and the map
matched only the caret pattern `value{k}`. A range matched nothing, so the edit
was dropped.

## Design

- `InsertionToSyntaxLeaf` maps `value{s:e}` in both directions. A caret is the
  range `{k:k}`, so the caret cases keep working. Every leaf built on it, the
  domain insertions and the SQL and Julia source insertions, gets the fix.
- A test in `InsertionInTabTest.jl` presses Backspace, Left and Delete through
  the standing iomap of a pane, and asserts the buffer after each step.
- The filter puts `insertable` last. The checks before it are pure, so the result
  does not change, and a layout variant or a stray insertion cursor no longer
  compiles a constructor probe.
- The old assertion compares the path without its types. `ff43f219` made the
  node selection the typed forward image of the insertion's cursor, and the
  assertion was not updated.
- The warm-up types "evaluatorxy", presses Backspace, Left and Delete, and
  commits "evaluator". The list is recorded again.

## Steps

1. [x] The four edits, and the tests. `test_document_insertion()` 119 of 119,
   `test_insertion_in_tab()` 11 of 11, `test_application()` 76 of 76. In the
   session of `ProjecturedRepl` both filter orders give the same 159 candidates,
   and the `insertable` probes fall from 988 to 486.
2. [ ] Record the list again at `:none`.

## Found, and left for a decision

- Home and End put the caret on the prompt text ("Insert a new ", " here"), a
  caret that the projection introduces. From there, typing, Backspace and Delete
  do nothing, until an arrow key brings the caret back into the buffer.
