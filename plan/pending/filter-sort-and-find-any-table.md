# Filter, sort and find any table, as a chain of projections

> **Kind:** plan · **Status:** tentative, 2026-10-05; the user's view (§3) is
> decided, 2026-10-07. Nothing else is decided past §2. The first release of
> the data frame view is done; a design review of the model (§5) comes before
> any step starts. ·
> **Stands on:** [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md),
> [concepts.md](../../documentation/design/concepts.md),
> [widget.md](../../documentation/package/platform/widget/widget.md),
> `FilteringProjection` and `SortingProjection` of the projection algebra

## 1. The goal

Every table gets the filter, the sort, the find, the scroll bar and the lazy
rows that the data frame view has now: a data frame, a `CellTable`, a JSON
array of objects, the result of a query of a database, the table of frame
statistics, and the tables of omnet-julia, such as the packet capture. The
code is generic, and a kind of table adds only what is its own.

The shape is the owner's (2026-10-05): "a table could be filtered by itself
whatever it's rows contain. A filter is a filter, any collection can be
filtered and you can get a similar kind of collection. I don't see why a table
coulnd not be filtered into another table."

So a filter is a projection from a table to a table of the same kind, and so
is a sort. They compose in a chain: the source table, a filter, a sort, and the
widget table at the end.

## 2. The owner's decisions (2026-10-05)

- **The state of a filter and of a sort can be both** ("for 1, both"): the
  parameters of the projection, as `TextFiltering` holds its pattern in a cell,
  and a query document that the stage reads, as `DataFrameQuery` is now. A
  query document is saved, undone and duplicated, and the assistant edits it;
  a parameter suits a filter that a program sets.
- **The filtered table can be both** ("for 2, both should be possible"): a
  native view of the kind where the kind has one, such as a `SubDataFrame`,
  which DataFrames writes through to its parent, and a generic view by
  indices for any other kind.
- **The plan is tentative** ("this should be just a tenative plan").

## 3. The user's view (decided 2026-10-07)

The owner asked, from first principles, what a person sees and does to sort
and filter any collection, and how the assistant does it. The proposal below
is mine; the owner answered "Agreed all", also to Q1 to Q4.

**The concepts a person meets.** A *collection* is any group of items that the
editor shows: a list, the rows of a table, the children of a tree node, the
lines of a text, a JSON array. A *filter* shows only the items where a
condition holds; the other items still exist. A *sort* shows the items in an
order; the data keeps its own order. *Find* moves to the next item where a
condition holds and hides nothing. A *view*, a pane, has its own filter and
sort, so a duplicate of a pane is a second view of the same data with another
filter. The words "projection", "lens" and "stage" are not in the interface.

**Start by pointing.** The menu of a value inside an item offers "Show only
items like this", "Hide items like this", "Sort by this", and for a number or a
date "… greater than this" and "… less than this". The path from the item to
that value applies to every item, at any depth (Q4): a column, a field of a
record, `address.city`. A header of a table gives the same commands; a click
on a header sorts, and a Shift+click adds a sort key. A quick text field keeps
the items that contain its text.

**Chips at the collection.** A filter or a sort shows as a bar of chips inline,
at the collection, in the flow of the document (Q3), for example
`12 of 340 · kind = b × · price > 3 × · ↑ price, ↓ id ×`. A click on a chip
edits its field, its operator and its value; × removes it; a drag orders the
sort keys; "Show all" removes every chip. A collapsed collection shows
"12 of 340", and an empty result says "No items match" with "Show all". The
chips are a small document: they are edited with the gestures of the editor,
undone, and copied with the view.

**The rules.**
- A filter and a sort never change the data. "Sort the data like this" and
  "Delete the hidden items" are separate commands, named as edits, each a step
  of undo.
- The filter and the sort are saved with the view, the pane and the workspace,
  and never in the file of the data (Q1).
- An edit through a view goes to the data: a new item shows at its sorted
  place and the selection follows it. An item that an edit makes fail the
  filter hides when the edit is committed, and the selection goes to the
  nearest item that shows, the rule of D6 and D10 of the data frame view, for
  every collection (Q2).
- Live data applies the filter again as it grows, and the selected item keeps
  its place on the screen.
- A tree shows each match with its ancestors.
- Values of different kinds sort as numbers, then text, then missing values.

**The kinds of collection.** Plain values: the item itself is the field.
Records (structs, JSON objects, the rows of a data frame): their fields or
columns. Nested items: any path inside the item. The lines of a text: the line,
as `TextFiltering` does. A tree: one level, with the ancestors of the matches.

**The assistant** uses the same concepts and the same operations as a person.
- It knows the collection that "this" names, from the selection or a
  referenced document, by its path.
- It edits the chips with verbs, such as `filter!`, `sort!` and `show_all!`,
  which make the operations that a press on a chip makes. Each change is a step
  of undo and shows in the gesture log, and a person removes a chip of the
  assistant with ×.
- It reads the chips, so it can say "12 of 340 runs: kind = b, sorted by price".
- It does not change the data to answer a question about the view: it reads
  the data with code to compute an answer, it changes the chips to show
  something, and it sorts or deletes in the data only when a person asks for
  that edit.

## 4. What exists

- The table interface is on main (5d282dd0e, from the pivot plan, P5 and P9):
  `TableInterface.jl` in the `collection` slice, with `is_table`,
  `get_table_row_count`, `get_table_column_names`, `get_table_column_type`,
  `get_table_value`, `find_table_column` and `make_table_part`, whose
  `TablePart` is the generic view by indices. A vector of named tuples, a named
  tuple of vectors and an `AbstractDataFrame` are tables. It covers the records
  of §3; plain values, trees and the lines of a text are not tables in it.

- `FilteringProjection(predicate)` keeps the elements of a collection that the
  predicate passes. Its IO map holds the kept indices, so `[j]` of the output
  maps to `[kept[j]]` of the input and back.
- `SortingProjection(by, lt, rev)` holds a permutation in the same way.
- Both build their output as a vector of the kept elements, and the sort prints
  every element: fine for a short list, too much for a frame of ten million
  rows.
- `TextFiltering` and `TextHighlighting` filter and mark the lines of a text,
  with the pattern in a cell; `ProjectionConfiguringProjection` gives such
  parameters a control.
- The widget table of a list builds only the rows that it shows, from the head
  of the list, holds open cells for an owner, and writes the commit, the drop
  and the opening of a cell as operations that the owner converts.
- The data frame view does all of it in one document and one projection
  (3,026 lines, 535 tests): its `kept_rows` is a filter and then a sort, kept
  as one vector of indices; its query is a document; its paths name the rows
  and the columns of the frame; its find walks the kept rows.

## 5. The model (tentative)

- **A table** is a collection of rows with named columns. A small interface
  reads it: the count of rows, the names and the types of the columns, and the
  value at a row and a column; a kind that has a vector of a column gives it,
  for speed. A kind that takes a write says so, by column, and a kind that
  can grow or shrink says so.
- **A filter stage** maps a table to a table of the same kind, with the rows
  that its predicate passes. Its IO map holds the kept indices, so a path
  `rows[j]` of the output goes back to the row of the source, and an edit in
  the output goes back with it.
  - A kind with a native view gives it: a filtered data frame is a
    `SubDataFrame` of the kept rows, with no copy.
  - Any other kind gets a generic view by indices over the source.
- **A sort stage** does the same with a permutation. A filter and a sort that
  follow each other can be one stage with one index vector, as `kept_rows` is.
- **The predicate and the sort keys** come from the parameters of the stage, or
  from a query document that the stage reads. The filter of a column (a text, a
  regular expression, a range of numbers, a list of values) is a predicate on
  one column, by its element type; the expression filter of the data frame is a
  predicate of a kind that reads its columns as vectors.
- **Find is not a stage that makes a table.** It marks the matches in the
  output, as `TextHighlighting` marks a text, and a command moves the
  selection to the next match.
- **Size.** A stage keeps only its index vector, and builds no document for a
  row. The widget table builds the rows that it shows, from the head of its
  list, and the scroll bar moves into the widget table, so every table has one.
- **Edit.** A write in the output maps back through the chain to the source. A
  native view writes through by itself. The kinds that take no write, and the
  ones that can not grow or shrink, turn the edit off by column or for the
  table.

## 6. What the data frame view becomes

- The source, the frame, with the table interface on `AbstractDataFrame`.
- A query document, which the filter and the sort stages read, and which the
  filter row, the expression bar and the find field edit.
- The chain: the frame, the filter, the sort, the widget table.
- Its own part: the expression filter, compiled over the column vectors; the
  native operations (a write of a value, the insert and the delete of rows and
  columns); the refresh of a frame that a program changed; the rules of a
  `SubDataFrame`; `display`.

## 7. Open questions

- The names: of the table interface, of the generic view by indices, of the
  stages.
- Whether the filter row, the expression bar and the find field are parts of
  the widget table, or a decorator around it. §3 puts the chips inline at any
  collection, not only at a table, which points to a decorator of a
  collection.
- How the model reaches the collections of §3 that are not tables: plain
  values, the children of a tree node, the lines of a text; and how a key is a
  path inside an item.
- How the rules that keep the row of the selection at its place on the screen
  (D10 of the data frame plan) read the order of the rows before and after a
  write, when the order is the output of a chain.
- The cost of a generic sort over the table interface, against the sort of
  DataFrames.
- How a stage with its parameters in cells shows in the gesture help and is
  saved, beside a stage that reads a query document.

## 8. Steps (tentative)

- [ ] **1.** The table interface, and filter and sort stages that keep only an
  index vector, over it. The interface and the view by indices are on main
  (§4); the stages are not.
- [ ] **2.** The widget table takes any table, with the lazy rows from an
  anchor and the scroll bar.
- [ ] **3.** The query document, the filter row and the find, as generic
  parts.
- [ ] **4.** The data frame view onto the chain, with its tests unchanged, and a
  comparison with the view before the change.
- [ ] **5.** A second table: a `CellTable`, or the packet capture table of
  omnet-julia.
- [ ] **6.** The edit back through the chain, and the native and the generic
  views.

## 9. Risks

- A wide change of the data frame adapter and its 535 tests, just after its
  first release.
- A frame of ten million rows: a stage that builds anything for each row, or a
  print of each element, is too slow.
- Two ways to hold the state of a filter can confuse a reader of the code; the
  plan must say when each is the right one.
