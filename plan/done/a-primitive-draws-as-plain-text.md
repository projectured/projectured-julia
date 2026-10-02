# A primitive document draws as plain text

Status: done 2026-10-02 (§5). Written 2026-10-02 in step 4.3 of
[view-and-edit-a-data-frame.md](../pending/view-and-edit-a-data-frame.md), at the owner's
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
  ([a-number-becomes-a-type-in.md](a-number-becomes-a-type-in.md)):
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
3. **A Bool switches with one key** (the owner, §4): `t` makes it `true` and `f`
   makes it `false`, as a JSON document takes `t` and `f`, and Space switches it.
   These are gestures of the `PrimitiveBool` document, so both domains read
   them. A key that would edit the text of a Bool does nothing, because a range
   edit of a Bool has no result. (The writer had proposed the rule of a number.)
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
   `PrimitiveNumberToText`, the keys of a Bool, the field `placeholder`, and the
   row in `PrimitiveToText`. Tests: the keys of `-5.2e3` through the text chain,
   Escape, `t`, `f` and Space on a Bool, the placeholder.
2. **The natural renderer.** The row of §2.1. The tests of the type-in of 4.0
   draw through the natural renderer, so they then run on the text domain. Find
   the tests that read the quotes of a primitive drawn by the natural renderer,
   and change them.
3. **The documents** of the primitive, the text and the natural slices.

## 4. The owner's decisions, 2026-10-02

1. **Every primitive outside a syntax tree** draws through the text domain
   (the owner: "yes"; the writer's recommendation, because such a primitive has
   no neighbour that its quotes tell it from).
2. **A Bool switches with one key** (the owner: "a bool can be switched from one
   state to the other with a single key like in json for example, or perhaps
   space"): §2.3.
3. **A number in full**, with no display format (the owner: "yes"; the writer's
   recommendation, because a cell is edited as it is shown).

## 5. What was done, 2026-10-02

Steps 1 to 3 are done, with these facts:

- **The text domain.** `PrimitiveInsertionToText` draws the typed text in the
  style of the type that it parses as (the style of a number, a Bool or a
  string), red while it parses as none, and the placeholder of the type-in
  while it is empty; a place in an empty type-in maps back to its start. The
  writer chose the style of the type over the green of the syntax type-in, so a
  type-in that parses looks like what it becomes. The text theme has two new
  fields, `wrong_color` and `placeholder_text`. `PrimitiveNumberToText` has
  `allows_type_in`, on in `PrimitiveToText`, which has the row of the type-in.
- **The parts that the two domains share** are in the primitive slice:
  `make_type_in_edit_operation`, `make_type_in_commit_operation`,
  `make_type_in_cancel_operation`, `make_empty_primitive_document`,
  `find_value_range` (of a selection or of a path), `find_deletion_range` and
  `get_type_in_placeholder`. The keys of a type-in in the text domain are
  `@gestures PrimitiveInsertion`, and a text edit from a later stage takes the
  same rule; the syntax leaf reads its own table first. `InsertionToSyntaxLeaf`
  takes a placeholder that is a function of the insertion, so the syntax
  type-in shows the placeholder of its document too.
- **A Bool** has `@gestures PrimitiveBool` (`t`, `f`, Space), which both domains
  read, and both of its printers drop a range edit.
- **The natural renderer** has the row of §2.1 after the rows of the domains
  that draw themselves and before the fallback rows.
- **Inside a syntax tree the rule of the type-in does not run.** A collection
  that the syntax domain prints maps a key back itself, so the reader of the
  leaf is not asked. The natural renderer draws a collection as a stack of
  blocks, each element on its own, so it is not such a tree; a number inside
  one, such as a field of a reflected struct, keeps the edit of its text.
- **The catalog** has the atom `primitive/insertion`. A type-in becomes
  another primitive at a key, so its text variant goes through
  `PrimitiveToText()` (`_text_sequence` in `Catalog.jl`), not the printer of one
  type. Its text is `-.`, because the sweep of the type-in round trip expects
  every key that types one character to be an edit of the text, and no such key
  makes `-.` a number. The string walker of that sweep skips a type, a value of
  `allowed_types`.
- **Tests:** `test_primitive_type_in()` 115, which runs the keys of a number,
  Escape and the keys of a Bool through the natural renderer, so the text
  domain, and through a renderer that draws each primitive through the syntax
  domain, and checks a string with no quotes and the placeholder; the platform
  86,727 (8 broken); markdown 233; data frames 289; the primitive catalog
  6,191; its type-in sweep 48; the natural sweeps over every atom. The umbrella
  integration has only the failures of main: the catalog coverage (its list
  without `PrimitiveInsertion` once the atom is in), the history sweep (2), the
  click round trip (3 errors) and the JSON string cell (3 and 1).
