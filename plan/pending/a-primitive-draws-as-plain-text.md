# A primitive document draws as plain text

Status: a design, for the owner. Written 2026-10-02 in step 4.3 of
[view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md), at the owner's
word: the cells of a data frame are primitive documents (R2), "but we need to
fix the projections". Each point is the writer's unless the owner made it.

## 1. The problem

- **A string shows its quotes.** The natural renderer draws a primitive
  document through the syntax domain: its only row for one comes from the
  syntax table, `PrimitiveDocument => PrimitiveToSyntax`, and
  `PrimitiveStringToSyntaxLeaf` draws the quotes. So a string cell shows
  `"item 1"`. The owner, 2026-10-02: "syntax uses a quote around a primitive
  string, because in a syntactical document that distinguishes "2" from 2 but
  here we can do something else". In a column of a table, the column says the
  type.
- **The text domain draws primitives already.** `PrimitiveToText` has a printer
  for a `PrimitiveBool`, a `PrimitiveNumber` and a `PrimitiveString`, with no
  quotes and with a placeholder option for an empty string. The application
  draws a primitive in a tab through it ("A tab title and a plain text file are
  prose, not a quoted string"). The owner: "primitive documents doesn't have to
  go through syntax, they can go directly to the text domain".
- **The type-in of a number is in the syntax domain only**
  ([a-number-becomes-a-type-in.md](../done/a-number-becomes-a-type-in.md)):
  the text domain has no printer of a `PrimitiveInsertion`, and its number
  printer has no rule for a key that the number can not show.
- **A `PrimitiveBool` has no edit.** It has no gestures, and a text edit of its
  value has no defined result.

## 2. The design

1. **The natural renderer draws a primitive document through the text domain.**
   A row `PrimitiveDocument => PrimitiveToText → TextToGraphics` comes before
   the rows of the syntax table in the table of `NaturalToGraphics`. It draws a
   primitive that is a child of a widget, a layout, a pane or a collection: a
   cell of a table, an element of a `CellVector`, a value in a tab. A primitive
   inside a syntax tree keeps its syntax leaf and its quotes, because the syntax
   table prints that tree, child by child.
2. **The text domain gets the type-in.**
   - `PrimitiveNumberToText` reads a key whose text the number can not show as a
     replace of the number with a type-in, with `make_number_edit_operation` of
     the primitive slice, as the syntax leaf does. A range edit reaches it by
     the default reader, so the rule is in its method for `ReplaceRangeOperation`.
   - A new `PrimitiveInsertionToText` draws the typed text, green when it parses
     as one of the allowed types and red when it does not, and the placeholder
     when the text is empty. Its keys do what the syntax leaf of the type-in
     does: a key whose text an allowed type shows exactly replaces the type-in
     with it, Enter replaces it with the first allowed type that the text parses
     as, and Escape puts the first allowed type with no value. The parts of the
     rule are in the primitive slice, so the two domains share them.
   - `PrimitiveToText` has the row of the type-in, so its number printer has the
     type-in on.
3. **A Bool takes the same rule.** A key whose text a Bool can not show, such as
   `tru`, makes a type-in limited to a Bool, and `true` or `false` makes the
   Bool again. A text that a Bool shows exactly replaces the Bool with that
   Bool, because a range edit of a Bool has no result.
4. **A type-in has a placeholder of its own.** `PrimitiveInsertion` gets a field
   `placeholder`, `nothing` for the text of the printer. The cell of a missing
   value in a data frame is an empty type-in limited to the type of its column,
   with the placeholder `missing` (R5 of the data frame plan).
5. **What a person sees changes.**
   - A primitive that is no part of a syntax tree draws with no quotes: the
     cells of a data frame and of a result table (`CellTableToWidgetTable`), the
     elements of a collection, a value in a tab of the display.
   - A number draws its full text, `string(value)`, which reads back as the same
     number: `0.30000000000000004`, where the compact print of the REPL shows
     `0.3`. A cell is edited as it is shown, so its text must read back as its
     value.

## 3. Steps

1. **The text domain.** `PrimitiveInsertionToText`, the rule in
   `PrimitiveNumberToText` and for a Bool, the field `placeholder`, and the row
   in `PrimitiveToText`. Tests: the keys of `-5.2e3` through the text chain,
   Escape, a Bool by keys, the placeholder.
2. **The natural renderer.** The row of §2.1. The tests of the type-in of 4.0
   draw through the natural renderer, so they then run on the text domain. Find
   the tests that read the quotes of a primitive drawn by the natural renderer,
   and change them.
3. **The documents** of the primitive, the text and the natural slices.

## 4. Points for the owner

1. The row of §2.1 for every primitive outside a syntax tree, or only for the
   cells of a table? Mine: every one, because a primitive outside a syntax tree
   has no neighbour that its quotes tell it from.
2. A Bool by the rule of §2.3, or a toggle by a press or by Space? Mine: the
   rule now, because it is the rule of a number; a toggle can come with the
   commit of a cell (4.5).
3. A number in full (§2.5), with no display format. Mine: yes, because a cell is
   edited as it is shown; a format for display would need a text that is not
   the text of the edit.
