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
- **A table of records** (2026-10-08, an answer in the omnet plan
  `legacy-simulation-catalog-implementation.md`, Q-6.1-7): the editable table
  of a list of records is generic, and the first user is the fingerprint store
  of omnet, a `CellVector` of `LegacyFingerprintEntry` documents. The owner:
  "agreed, it's (b), a generic table could work for any vector of the same
  struct type, btw". A person deletes a row, inserts one and edits a cell
  there; no projection does this today, and the data frame view is the only
  one that edits a cell.

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

**Decided when the implementation started (2026-10-08):**
- The view document is no part of a pane. It wraps the document that a place
  shows, by composition (the owner: "it could be used without panes and has
  nothing to do with panes in general. Composition is the rule"):
  `ArrangementDocument(document, entries)`, the main document of a new slice
  `arrangement`, after the projection algebra. The first chip puts it around
  the document, and the last chip takes it away (the owner).
- An entry is `ArrangementEntry(at, projections)` (mine: "placement" names the
  anchored placement of the layout slice and the force layout of the graph
  domain). The descriptions of the first two kinds are `ArrangementFilter` and
  `ArrangementSort` (mine). `make_arrangement_projection(description)` turns a
  description into its projection.
- `ArrangingProjection` prints an `ArrangementDocument`: its document prints
  through the recursion at the path `document`, with the arrangement and that
  path in the printer context, and the output is the output of the document.
- The dispatch is `ReferenceDispatchingProjection`, extended (the owner chose
  this over a new projection): its function form can take the printer context
  (`reads_context = true`), and its inner IO map is reconciled by the chosen
  projection with `make_reconciled_child_iomap_cell`, as `SwitchingProjection`
  does, with the print in a computation that is only peeked. A function that
  reads no cell chooses once, so the users that exist keep their behaviour.
  `make_arranged_dispatch(default)` gives the dispatch whose function
  `find_arranged_projection` reads the entries of the arrangement in the
  context; it builds the chain of an entry once for each list of projections.
- Facts: the tabbed pane prints the element of a page with its own
  `ctx.reference`, not extended by the step to the page, so the dispatch
  compares the path below the document of the arrangement, which the
  arrangement records when it prints. `ElementReferenceStep(i)` is
  `RangeReferenceStep(i - 1, i)`, the step that a selection uses, so the path
  of an entry and the path of a printer compare directly.

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

**Where to resume (2026-10-11).** Steps 1 to 4 are done, with the change of the
context menu that "Filter by text…" needed, and they landed on main together.
Open, in this order:
- Step 3: a bar for a collection that prints as syntax, and the design
  document of the slice `arrangement` in `documentation/package/`.
- Step 5: the printer of any table, with the lazy rows, the scroll bar and the
  sort glyph of a header (decided: answer 1 of 3d).
- Step 6: the data frame view onto the arrangement.
- Step 7: a collection that its parent prints inside its own print, such as a
  JSON array or the `children` of a layout, through a stage at the parent.

- [x] **1.** The view document of a pane, and the dispatch on it: the entries,
  the descriptions and their methods, and the IO map whose inner IO map is a
  computation. A test places a projection at a path and removes it, and only
  that position prints again. Done 2026-10-08, as the decisions after §5 say:
  `ArrangementDocument`, `ArrangementEntry`, `ArrangingProjection` and
  `make_arranged_dispatch` in the slice `arrangement`, and the extended
  `ReferenceDispatchingProjection`. Fact found: a dispatch whose choice was
  only a lazy cell chose no longer while it printed, and a test of the
  clipboard records the path at print time, so the dispatch makes its choice
  with `peek` as it prints, as `ChainingProjection` builds its stages.
  `test_arrangement` (10): an entry at a row prints only that row again, an
  entry with no projection and an edit of another entry print nothing, and
  the removal shows the row as it was. The platform: 102,416 pass, 8 broken
  and 2 fail; the base 102,406, with the same 2 failures of
  `test_interface_api`; the 10 more are the new test.
- [x] **2.** The filter and the sort stages: the index vector, the children
  printed with the source index, conditions and keys as paths inside an item,
  and the readers that map back. Tests over a vector of values, a vector of
  records, a nested collection with a pattern entry, and a table. Done
  2026-10-08, with a change of the design (mine):
  - A stage passes the kept items themselves to the printer of the place, and
    does not print them: `PickingProjection(compute_rows)`, whose output holds
    the items at the indices that `compute_rows` answers, and whose maps send
    `[j]` of the output to `[rows[j]]` of the input. A stage that printed its
    children through the recursion, as `SortingProjection` does, would hand
    their printed output to the printer of the place, which prints items.
  - So the printer of the place numbers the items by their shown place, and
    the chain of an entry tells the places below it the source index instead:
    `ArrangedChainingProjection` prints the stages and the printer of the place
    as a `ChainingProjection` does, and returns its `ChainingIoMap`, so the
    reader and the maps are those of a chain; but the printer of the place
    prints with the indices that the stages picked in the context
    (`:arranged_picks`). `find_arranged_projection` turns the index after each
    picked place into the source index, the innermost first.
  - `ArrangementFilter(conditions)` with `ArrangementCondition(key, operator,
    value)`, the operators `:equal`, `:not_equal`, `:less`, `:greater`,
    `:at_most`, `:at_least` and `:contains`; `ArrangementSort(keys)` with
    `ArrangementSortKey(key, direction)`, a stable sort. `get_arrangement_value`
    reads the value of an item, the `value` of a primitive document, and a
    domain adds a method. Numbers come before text, text before other values,
    and a missing value last in either direction.
  - An entry's place is a path or a pattern of `parse_reference_pattern`,
    matched with `match_reference_pattern(:at, …)`. A path wins over a pattern,
    and among entries of one kind the first wins (mine, the open question of
    §7).
  - Facts: a pattern needs a name before an index, so `[*].events` does not
    parse and `runs[*].events` does. A `CellVector` passed to the one
    `CellVector` field of a `@document` is wrapped once more, so a test builds
    the record from a plain vector. A copy of a record by `CopyingProjection`
    keeps the field values of its print, so the test of a nested entry prints
    the arrangement again for each check; a copy of a vector follows its
    children. `PickingProjection` takes a `CellVector` and a plain vector; a
    `ListNode` waits for the widget table of step 5.
  - `test_arrangement_filter_sort` (15): a vector of values, records with two
    sort keys, an entry inside a picked item by its source path, a pattern,
    the rows of a table by a column, and values of different kinds.
- [ ] **3.** The chips: the drawing of an entry beside a printed collection, in a
  text view and in a widget view, and the commands of §3: "Show only items
  like this", "Hide items like this", "Sort by this", a header, the quick text
  field, and "Show all"; and find. In parts:
  - [x] **3a.** The dispatch in the natural renderer (the owner chose shape A:
    "it doesn't change each domain, and that is good. Separation of concerns,
    sorting/filtering does not have anything to do with the JSON domain"). The
    natural and the syntax slices put `make_arranged_dispatch` in the three
    recursions that print data: the graphics recursion of `NaturalToGraphics`,
    the first stage of `make_natural_projection`, and the data stage of the
    syntax fabric; the stages after them print what the first made, and get no
    dispatch. No domain changes. Rules: a place is arranged once, so a
    document that two recursions print at one path is picked by the outer; a
    stage that can not pick its input passes it through, and the recursion
    inside arranges it.
    Fact found and measured (allocations, not time): a dispatch at every node
    made a print of a reflected vector of 2000 numbers allocate 9.9 MiB against
    6.7 MiB on the base. So `ReferenceDispatchingProjection` takes `applies`
    and `default`: where `applies(context)` is false it prints `default` as it
    is, with no IO map of its own, and the arranged dispatch applies only
    inside an arrangement. Then 7.1 MiB, about 6% more. A projection that holds
    the dispatch calls its reader and maps with the IO map of `default` then,
    so the dispatch has methods for any IO map that go to its projection.
    Fact found: `test_all` in one process ended at a memory cap of 12 GB, so the
    sweep runs the groups of `test_all` in processes of their own.
  - [x] **3b.** The bar of chips (the owner: "Q2: yes"): `make_arranged_dispatch`
    takes `bar`, and the natural renderer gives `ArrangementBarProjection`, a
    stage before the printer of the place that puts the items second in a
    `VerticalLayout` under an `ArrangementChips(entry, shown, total)`; the
    printer of the place prints that layout, so the layout routes a press and
    maps a path. `get_arranged_wrap_steps` names the steps that the bar puts
    above the items, `children[2]`, and a pick records the path of the place in
    the source and where its items print. `ArrangementChipsToGraphics` draws
    the count, a chip with × for each condition and sort key, and Show all; it
    turns the press of a chip into an edit that names its own document, so a
    history records it. Mine: a stage, not a wrapper around the chain, because
    a wrapper would need the routing of a layout again.
  - [x] **3c.** The context menu (the owner: a context menu). A right click
    collects a layer from each document around the part. `ArrangementDocument`
    has a binding in its gesture table that reads the path under the pointer
    from its mouse target, and `ArrangingProjection` hands a routed gesture to
    its document by the routed reader of a container, so the table of the
    arrangement reads it. `find_arranged_item` finds the nearest collection on
    the path, the item and the key; `make_arrangement_edits` gives "Show only
    items like this", "Hide items like this", greater and less for a number,
    "Sort by this" either way, and Show all, each an edit that names its own
    document. The first chip: `PaneTab` has a binding that offers
    `make_first_arrangement_edits`, which put `ArrangementDocument(content,
    [entry])` in the place of the content; the menus are computed in the
    `arrangement` slice and drawn by the natural and the pane slices, so the
    pane gets one edge, to `arrangement`. The last chip: an edit that leaves an
    arrangement with no entry becomes, in the reader of `ArrangingProjection`,
    the edit that puts its document in its place, rooted at the arrangement.
  - Facts of the checks of 3a to 3c (2026-10-08):
    - The layout that the bar makes holds no selection of its own, so it did
      not route a caret to the items; the bar sets the forward image of the
      selection and of the mouse target of the items below `children[2]`.
    - A document type with a printer needs an atom of the catalog or a place
      in its list of types with none (`_NO_ATOM`). The catalog reaches a
      document of a type that no domain bridges only through the Julia bridge,
      which draws it as one object, so no string in it can be typed in. So
      `ArrangementDocument` and `ArrangementChips` are in that list, as the
      wrappers `DragTrackingState` and `GestureTrackingState` are; the tests of
      the arrangement slice print them in the natural renderer.
    - A run without network fails the tests of an external agent, the MCP log
      and a file system document in the platform, and the Anthropic and the
      Ollama suites; with network the platform passes, and the base fails the
      model suites the same way without network.
    - The test of the natural notation reads the stage of a domain as the
      default of the dispatch of the first recursion.
    - Found in an editor: the pane documents did not read a right click or a
      dwell. The widget stage reads the documents of the content of a tab, but
      the tab, its group and the tree are the input of the pane stage, and the
      reader of `PaneTreeToWidget` asked only the table of the tree. So the
      menu of a tab came only in a direct read. Now that reader reads its own
      stretch by the rule of `read_gesture_outward`, along the mouse target of
      the tree, up to the content of a tab. A test in an editor right clicks a
      value and hides it, right clicks a value of the arranged content and
      hides it (the third drawn item is the fourth of the source), and presses
      Show all.
    - The tab adds its layer after the nearer ones, so the test of a navigator
      in a tab reads the menu of the part as the first layer.
    - A gap until step 7: the menu offers to arrange a collection that its
      parent prints inside its own print, such as the `children` of a
      `VerticalLayout`. No recursion passes that place, so the arrangement
      does not act there. Step 7 puts a stage at the parent node for such a
      field collection.
  - [ ] **3d.** The quick text field, the header gestures, and find. The
    owner's answers (2026-10-08) to my four recommendations:
    1. "yes": a sort glyph in the header of each table that the natural
       renderer draws, as the data frame view has: a click goes off, ↑, ↓,
       and Shift+click adds a key. A press on the label still selects the
       column.
    2. "(b)": a new operation, `ArrangeCollectionOperation(at, description)`.
       The nearest reader that holds an arrangement, or that can make one,
       turns it into the edit. The verbs of the assistant use it too.
    3. "yes": a quick text field at the end of the bar keeps the items where
       any value inside the item contains the text, with a key form for "any
       value"; the menu gets "Filter by text…", which makes the entry and puts
       the caret in the field.
    4. "agreed": find moves the selection only, as in the data frame view
       (Ctrl+F, F3, Shift+F3), and marks no match yet.

    Facts found before the code:
    - The natural renderer draws no table of data with a header: a vector of
      records prints as reflected syntax or a stack of blocks, and only some
      domains build a `WidgetTable`. The printer of any table comes in step 5,
      so the glyph goes with step 5.
    - A field in the bar needs its caret at a path in the entry, such as
      `entries[1].projections[1].conditions[2].value`, because there is one
      selection from the root. The bar draws at the collection, inside the
      print of the document, so `ArrangingProjection` can not map such a path
      forward to the field, and a key with that route reaches no field. The
      quick text field and the field of find wait for a decision of how.

    The rule that only the projection algebra holds projections (the owner,
    2026-10-08) and `ArrangedChainingProjection`, which holds a chain in the
    slice `arrangement`: the owner, 2026-10-09, "accept where it is now".

    Parts:
    - [x] **3d-1.** `ArrangeCollectionOperation` and its two holders: the
      reader of `ArrangingProjection` and the reader of the pane tree. Done
      2026-10-08:
      - `ArrangeCollectionOperation(at, description)` is a path operation
        (`operation_reference` and `retarget_operation`), so every reader on
        the way out reroots and maps `at` as it maps any path. Its description
        gives way to the description of the same kind at `at` (mine): a
        filter or a sort with items replaces the items of the one there, which
        keeps its identity, so the chain of the place is not built again; an
        empty one takes its kind away; `nothing` takes the entry away, as Show
        all does. A new filter goes first in an entry, any other kind last.
      - `make_arrangement_change_edit(arrangement, operation)` and
        `make_first_arrangement(document, operation)` in the slice
        `arrangement`; the reader of `ArrangingProjection` uses the first, and
        the pane reader the second, for a tab whose content nobody arranged.
        `make_entry_removal_edit` moved from the natural slice to the
        arrangement slice, so both use it.
      - The pane reader maps `at` back to the tree and walks it to the content
        of a tab, with the walk that the outward read of a right click uses
        (`_walk_pane_path`). `PaneArrangement.jl` is included after
        `PaneToWidget.jl`, so it holds this reader beside the menu of a tab.
      - `test_arrange_collection_operation` (20): the edits of an
        arrangement, the first arrangement, and in an editor an operation
        lifted from the content of a tab, then from inside the arranged
        content, and then `nothing`, which gives the plain document back.
    - The owner (2026-10-09) on the text of a field in the bar: "no new step
      if possible, that must be absolutely justified … why not projection
      induced step?", and then "agreed" to the projection-introduced step and
      to the move of the bar into the slice `arrangement`.
    - [x] **3d-3.** The quick text field. Done 2026-10-09:
      - The caret in a field is a path with the introduced step of the bar
        at the place: `‹ArrangementBarProjection(entry): .children[1].entry.projections[i].conditions[k].value{a:b}›`.
        Below `children[1]` the path goes through the entry itself, so the
        field edits a document. `ArrangementBarProjection` moved from the
        natural slice to `ArrangementBar.jl` of the slice `arrangement`, which
        is included after `layout` now and has the edge to it, so every slice
        that names an entry can name its bar.
      - `PickingProjection` passes an introduced step of a later stage
        through, forward and back. The bar maps `children[1]…` back to its
        introduced step and takes the step off forward, and it computes the
        selection and the part under the pointer of the chips as it does for
        the layout.
      - `ArrangementChipsToGraphics` draws a quick text condition
        (`is_quick_text_condition`: key `nothing`, `:contains`) as a
        `WidgetText` and a × at the end of the row. Its maps send the value of
        the condition to the field and back; its reader turns a text edit of
        the field into the write of the value, which names the condition, and
        the caret after it.
      - Fact found: a key has no route; each container sends it to the child
        that its own selection names. So the row of the chips gets the
        selection of the field that holds the caret, as the data frame view
        does for the layout around a field.
      - A condition whose key is `nothing` holds when any value inside the item
        holds it, at any depth; an empty text is in every item.
      - The menus get "Filter by text…" after the sort items, in the menu of an
        arrangement where the entry has no quick text and in the first
        arrangement of a tab.
      - The item could not put the caret in the field: the context menu
        lifted every item from the part under the pointer, and the field is no
        part below it. The owner chose (a), "I agree with (a)" (2026-10-09):
        each layer of a context menu acts on its own part. Done 2026-10-09:
        - A layer is `(title, menu, below)`: `below` counts the steps of the
          source below the part of the layer. The join of two menus computes
          it from the two sources; the steps below a part stay as they are on
          the way up, so the count stays right as the source is rerooted and
          mapped. Where the source of the outer menu does not start the source
          of the inner one, `below` is `0`, and the item acts on the part
          under the pointer, as before.
        - The window finds the layer of a chosen item by the operation that
          the item holds, and lifts the edit from the part of that layer
          (`find_menu_item_part`, which a test uses as the window does). An
          item that names its own document acts the same from any part, so the
          menus that exist keep working; the rule F2 of
          `EditMenuPartOperation` now says that the part of an item is the
          part of its menu.
        - Fact found: the reader of the pane tree dropped an operation that
          code routes to a node of the tree, such as an item of the menu of a
          tab: it mapped the operation as an answer of the widget stage. It now
          answers it rerooted by its route, as the reader that holds the place.
        - "Filter by text…" puts the caret in its field after the edit, in the
          menu of a tab and in the menu of an arrangement.
        - A test that read the menu of a layer as `last(layer)` reads `layer[2]`.
      - `test_arrangement_quick_text` (19): the condition on any value, and in
        an editor the item of the menu, a press in the field, two typed keys
        (2 of 4), a backspace (3 of 4), the caret after the text, and the × of
        the field, which gives the plain document back.
      - Still to write: the design document of the slice `arrangement` in
        `documentation/package/`.
    - [x] **3d-4.** Find. Done 2026-10-09:
      - `ArrangementFind(text)` is a description in the entry, so it is saved
        and undone with the entry and shows in the bar (mine). Its stage is
        `IdentityProjection`: it hides no item and changes no order, and its
        maps pass the introduced step of the bar. The bar shows its text as a
        field after the quick text field, with a ×.
      - The commands in the table of `ArrangementDocument`: Ctrl+F puts the
        caret at the end of the field of the find of the collection that holds
        the selection, after the edit that adds the find, or the entry, when
        there is none (`make_find_field_selection`); F3 and Shift+F3, and
        Return or Shift+Return in the field, select the next or the previous
        item where any value contains the text, in the order in which the
        items show (`compute_shown_rows`), round the end (`make_find_move`). As
        in the data frame view, a move marks nothing.
      - Fact found: a key reached the tables only through a route, and a key
        has none, so the reader of `ArrangingProjection` reads a key that its
        document does not answer with the table of the arrangement.
      - Ctrl+F in a content that nobody arranged is in the table of
        `PaneTree`, which reads the keys that its content does not answer: the
        first arrangement with an empty find (`make_first_find`) in the place
        of the content of the focused tab, and the caret in the field. A key
        table answers relative to its own document, so this caret needs no
        change of the context menu.
      - `test_arrangement_find` (16): the order in which the items show, and in
        an editor Ctrl+F in a content that nobody arranged, two typed keys that
        hide nothing, Return, F3 and Shift+F3 round the end, F3 in the order of
        a sort, the × of the field, and Ctrl+F in an entry with no find.
    - Open in step 3: a collection that prints as syntax, through the data
      stage of the syntax fabric, is filtered and sorted but shows no bar,
      because only the graphics recursion of `NaturalToGraphics` has one.
- [x] **4.** The verbs of the assistant, as edits of the view document, and the
  read of an entry. Done 2026-10-09:
  - The names: the owner asked "why not filter_collection! or sort_collection!
    etc. you don't know whether they are shown or not", and said "yes" to
    `filter_collection!(collection, conditions...)` and
    `sort_collection!(collection, keys...)`, where a call with no condition or
    no key takes the filter or the sort away, so no verb for Show all, and
    find stays out of the verbs.
  - A condition is `key => comparison`, with `==`, `!=`, `<`, `>`, `<=`, `>=`
    and `contains` of one value, or a comparison alone for the item itself; a
    key is a path of field names with dots, `""` for the item, `nothing` for
    any value; a sort key is a key or `key => :descending`. A second call
    replaces the conditions or the keys of the first, as
    `ArrangeCollectionOperation` replaces a description of its kind.
  - Each verb lifts an `ArrangeCollectionOperation` from the collection, or
    from the deepest place above it that a reader follows a route into
    (`find_rooted_operation`), evaluates it, and answers `Text` of how the
    collection shows (`describe_arranged_collection`), such as `2 of 3 items:
    status ≠ "failed", ↓ delay`. `make_filter_collection_operation` and
    `make_sort_collection_operation` read the edit and evaluate nothing.
  - Fact found: the first call puts an arrangement around the content, so a
    reference from before it, such as `.content`, misses the step `document`.
    The verbs put that step in where a path leaves it out, so the same
    reference works for every call.
  - Fact found: `ArrangementDocument` was a transparent wrapper that did not
    say so: `get_wrapped_document` answered the arrangement itself, so code
    that reads the tree, as a save of a file does, met the arrangement and
    not the document. It now has `get_wrapped_document`, `get_edited_field`
    and `replace_wrapped_document!`, as the undo buffer has.
  - The read: `describe_document` of an arrangement, which `show_layout`
    writes beside a pane, adds `describe_arrangement`, the path and the words
    of each entry. The chips and the read share `get_arrangement_parts` and
    `describe_arrangement_part`, which moved to the slice `arrangement`.
  - `make_application_api` declares the two verbs, and the slice
    `application` has the edge to `arrangement`. The system text of the tools
    names only the verbs that change data, so it does not name these.
  - `test_arrangement_program` (13): a filter, a sort with the same reference,
    a second filter, the read of the pane, two wrong calls, the empty calls
    that give the plain document back, and the wrapper.
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
