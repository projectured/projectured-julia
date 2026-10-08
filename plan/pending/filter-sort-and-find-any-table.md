# Filter, sort and find any table, as a chain of projections

> **Kind:** plan · **Status:** pending. The user's view (§3) is decided,
> 2026-10-07, and the model (§5), 2026-10-08. The steps (§8) wait for the
> owner's word to start. ·
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
- A printer knows where its input is: `PrinterContext.reference` is the path
  from the root of the document to the input, and a printer extends it for a
  child with `make_child_context`.
- `ReferenceDispatchingProjection` chooses an inner projection by that path,
  from pairs or from a function with the patterns of `@reference_case`
  (`above()`, `_`). It chooses once, when the position prints. Its IO map sends
  the output of the inner one through a cell, so the IO map keeps its identity.
  `ApplyAtProjection` and `SortingAtProjection` are built on it: a projection
  at one path, the part above it copied, and everything below it kept.
- `SortingProjection` prints each child with the source index
  (`make_child_context(ctx, ElementReferenceStep(i))`), so a position below it
  sees the path of the source. `FilteringProjection` passes the kept items
  through without a print, so the printer after it numbers them by their
  shown place. The readers of both map a path of the output back to the
  source, so an operation reaches the right item.

## 5. The model (decided 2026-10-08)

The owner compared two ways to give each collection its own filter and sort:
a stage that is always there in front of the printer of each kind of
collection and passes its input through, or a dispatch on the path that
follows a document of what a person placed where. The owner asked which one is
more future proof and combines better by composition, and agreed to the second
(way 1). It is the first composition that a person edits: by the chips, a
person places projections at a collection.

**The view document of a pane.** The pane keeps one document of entries. An
entry is a place, a path or a pattern of `@reference_case`, and an ordered list
of the projections that a person put there; the order is the order of the
chain. With the example of §3 and an array `events` in each run:

```
view of the pane
  entries:
    [1] at: .runs
        projections:
          [1] filter     conditions: [ .status ≠ "failed" ]
          [2] sort       keys:       [ ↑ .delay ]
    [2] at: .runs[_].events                (a pattern: the events of every run)
        projections:
          [1] first      count: 10
    [3] at: .notes
        projections:
          [1] show as    table
```

- A projection in the list is a small document, its kind and its parameters,
  and not a Julia closure, so the view document is saved with the pane,
  copied with a duplicate of the pane, undone, and edited by the assistant as
  any document. A method for each kind turns it into a projection, for example
  `make_view_projection(description::FilterDescription) = FilterStage(description)`.
- The chips of §3 are a drawing of one entry: a chip for each condition and
  for each sort key. A stage reads its parameters through their cells, so an
  edit of a value or of an operator changes only the data of the stage. The
  composition at a path changes only when a projection is added to the list
  or removed from it.
- Filter and sort are the first two kinds. The same entry takes later ones with
  no new wiring: group, pivot, the first n items, show as a table, a chart of a
  column; and their order is free, for example a sort, then the first 10, then
  a filter.

**The dispatch.** The pipeline is built once, before it prints, as a dispatch
on the path:

```julia
RecursiveProjection(ReferenceDispatchingProjection(reference ->
    # the chain of the entry whose place matches `reference`, then the default
    # printer; the default printer alone when no entry matches
))
```

The IO map of the dispatch makes its inner IO map a computation that reads only
the entry of its own path. When that entry changes, it prints the chosen chain
again, and the output cell, which keeps the identity of the IO map, follows it.
The readers and the maps read the inner IO map from its cell. The inner print
runs under `peek`, so that what it reads as it prints does not make the
dispatch print again, as the parts of a table of a list do. The kernel does not
change.

**Paths below a stage.** A stage prints its children with the source index, as
`SortingProjection` does, so `ctx.reference` below a filtered or sorted
collection is the path of the source item, `.runs[4].events`, and a nested
entry such as [2] matches. The readers of the stages map an operation back to
the source, so the selection and an edit find the right item.

**The filter and the sort stages.**
- A condition and a sort key name a path inside one item: the empty path for a
  plain value, a field of a record, a column of a table, or a deeper path such
  as `.address.city`. So the stages reach every collection of §3, a table or
  not.
- A stage keeps only its vector of indices, and builds no document for an
  item. A kind of collection with a native view gives it, such as a
  `SubDataFrame` of the kept rows; a table gets the generic view by indices,
  `TablePart`, and any other collection a vector of its kept items.
- The filter of a column by its element type (a text, a regular expression, a
  range of numbers, a list of values) is a condition on one path; the
  expression filter of the data frame is a condition of a kind that reads the
  columns as vectors.

**Find** is not a stage. It marks the matches, as `TextHighlighting` marks a
text, and a command moves the selection to the next match.

**Size.** A stage keeps only its index vector. The widget table builds the rows
that it shows, from the head of its list, and the scroll bar moves into the
widget table, so every table has one.

**Edit.** A write through the view maps back through the readers to the
source. A native view writes through by itself. A kind that takes no write, or
that can not grow or shrink, turns the edit off by column or for the
collection.

**State.** View state that a document keeps, such as a scroll position or the
open nodes of a tree, survives a change of the composition at a path. State
that no document keeps is lost then, as it is at any print (the owner).

## 6. What the data frame view becomes

- The source, the frame, with the table interface on `AbstractDataFrame`.
- Its query becomes the entry of the frame in the view document: the filter
  row, the expression bar and the sort of a header edit the projections of
  that entry; the find marks and moves as §5 says.
- The chain at the frame: its filter, its sort, the widget table.
- Its own part: the expression filter, compiled over the column vectors; the
  native operations (a write of a value, the insert and the delete of rows and
  columns); the refresh of a frame that a program changed; the rules of a
  `SubDataFrame`; `display`.

## 7. Open questions

- The names: of the view document and its entries, of the descriptions of the
  projections, and of the stages.
- How the bar of chips draws beside a printed collection in each kind of
  output: a line of syntax in a text view, a widget in a widget view.
- Which entry wins when a path and a pattern both match one place.
- In which slice the view document, the descriptions and their methods go, so
  that every builder of a pipeline names them (the slice order).
- How the rules that keep the row of the selection at its place on the screen
  (D10 of the data frame plan) read the order of the rows before and after a
  write, when the order is the output of a chain.
- The cost of a generic sort over the table interface, against the sort of
  DataFrames.
- How the projections of an entry show in the gesture help.

## 8. Steps

Each step ends with its own tests and a commit, in a worktree.

- [ ] **1.** The view document of a pane, and the dispatch on it: the entries,
  the descriptions and their methods, and the IO map whose inner IO map is a
  computation. A test places a projection at a path and removes it, and only
  that position prints again.
- [ ] **2.** The filter and the sort stages: the index vector, the children
  printed with the source index, conditions and keys as paths inside an item,
  and the readers that map back. Tests over a vector of values, a vector of
  records, a nested collection with a pattern entry, and a table.
- [ ] **3.** The chips: the drawing of an entry beside a printed collection, in a
  text view and in a widget view, and the commands of §3: "Show only items
  like this", "Hide items like this", "Sort by this", a header, the quick text
  field, and "Show all"; and find.
- [ ] **4.** The verbs of the assistant, as edits of the view document, and the
  read of an entry.
- [ ] **5.** The widget table takes any table, with the lazy rows from an anchor
  and the scroll bar.
- [ ] **6.** The data frame view onto the view document and the chain, with its
  tests unchanged, and a comparison with the view before the change.
- [ ] **7.** A second kind: a JSON array, or the packet capture table of
  omnet-julia.

## 9. Risks

- A wide change of the data frame adapter and its 535 tests, just after its
  first release.
- A frame of ten million rows: a stage that builds anything for each row, or a
  print of each element, is too slow.
- A printer that does not extend `ctx.reference` for its children puts a
  nested entry at the path of its parent; each domain needs a test that an
  entry at a path reaches the collection at that path.
- The composition at a path changes when a person adds or removes a
  projection, so that position prints again; state that no document keeps is
  lost then.
