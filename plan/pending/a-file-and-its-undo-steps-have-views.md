# A file and its undo steps have views

**Status:** approved by the owner on 2026-11-18 ("yes", to "Do you approve this plan, so
that I start it in a worktree?"). In work on the branch `file-views`.

This plan is the first of two plans in the place of plan 4b of point 4 of the
order in section 13.3 of `plan/tentative/content-and-view-for-the-whole-project.md`.
The cut into two plans is proposed decision 1, which the owner approved with the
plan. The design is
`documentation/design/content-and-view.md`. Plan 4a is
`plan/done/each-json-node-has-a-view.md`, and it is on `main`. The plan lands
nothing and pushes nothing: it ends with a request to land.

The plan changes only views, printers of views, tests and one example. The
editor shows each file as content with no view after this plan, as it does now.
No file of the kernel changes.

**If a step needs a change of a kernel file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

A tab holds a JSON file through a file and an undo buffer. Each JSON node has a
view after plan 4a, but nothing stands between a tab and a JSON view.

**The file and the undo buffer have no place for the view of what they hold.**

```julia
file = make_file_tab("people.json", make_history_wrap(settings))
# a File, which holds an UndoBuffer, which holds a JsonArray
view = make_file_view(file)             # a FileView: the file and the scroll of one tab

# now
make_content_view(file.content)         # nothing: the undo buffer has no view
view.file.content.content               # the JsonArray, and the caret of the tab is in it

# after this plan
view = make_file_view(file; views = true)
view.content                            # the UndoBufferView of the undo buffer
view.content.content                    # the JsonArrayView of the array
get_selection(view)                     # .content.content.elements[2].value{3}, a path of the views
get_selection(file.content.content)     # nothing: the array holds no caret
```

**No printer records an edit that comes through views.**

```julia
# the caret is in a JSON string, through the view of the undo buffer
press('x'); press('y'); press(Ctrl+Z)
# now:   the undo buffer has no view, so its printer is not on the path of the key
# after: the two characters are one undo step, and Ctrl+Z takes them back
```

**The view at the top can not replace its own node.**

```julia
# a new JSON file: its content is the place for a new value, and the caret is in it
press('7')
# now, through a view:  no answer. No view is above the place, so the write has no place
# after this plan:      the write goes to `.viewed.content` of the view of the undo buffer
```

**A part that has no view takes no caret through a view.**

```julia
# element 2 of a JSON array is a document of a type that has no view
click(in element 2)
# now:   element 2 prints as content, and the click gives no caret
# after: the caret is at `.elements.viewed[2].<path in element 2>`, and element 2 holds
#        its caret, as with no view. A key goes to the key table and the printer of element 2
```

**The general renderer has no row for a view.** A JSON view that a file view
holds prints through the row for any value, which prints a struct by
reflection.

## The decisions of the owner that this plan builds

- **The tree of views mirrors the tree of content** (decision 6 of section 13.1
  of the order document).
- **The undo buffer gets a view that has no state and is only a link** (the
  owner on 2026-11-18: "yes", to "Do you accept a view of the undo buffer that
  has no state and is only this link?"). Its jobs: it holds the JSON view below
  it, it keeps the printer of the undo buffer on the path of a key, and it
  writes the root value of the file.
- **The owner reviews the JSON domain before the design goes to the other parts
  of the editor** (2026-11-17). So no tab of another domain changes before that
  review. In this plan no tab changes.
- **The step `.viewed` in a caret comes together with the loss of the selection
  field** (the owner on 2026-11-17: "I agree with A"). So the caret of a view
  keeps the form of today. With the field still there, a path through `viewed`
  writes the caret into the content.
- **A reference step means what it says, and a view gets no special treatment
  in the kernel** (the owner on 2026-11-16).
- **A printer is not the place that frees memory** (the owner on 2026-11-17).

## Proposed decisions

They are approved with this plan.

1. **Plan 4b becomes two plans.** This plan gives the views and their printers,
   with no change of the editor. The second plan is "The editor shows a JSON
   file through its views". It turns the views on for JSON files, and it
   changes each feature of the editor that names a place by a path through the
   content. Between the two plans is a measurement (see "After this plan"), so
   the steps of the second plan are fixed from facts. The reason for the cut:
   about a dozen features name a place by a path through the content, and
   about 20 test files outside the JSON suite open a JSON file.
2. **`UndoBufferView` has one child field, `content`.** It holds the view of the
   document that the undo buffer holds now, by the slot rule of plan 4a. The
   two lists of undo steps get no child field. A content type can declare that
   a field gets no child field in a view, and `@content_view` reads that
   declaration. `UndoBuffer` declares it for its two lists, as it keeps a walk
   out of them now (`is_field_walked`).
3. **The printer of the undo buffer prints the buffer or its view.**
   `UndoBufferToAnyProjection` takes an `UndoBufferView` too, with a row of its
   own in the same table. For a view it prints the view of the content. Its
   maps keep the step `content`. Its reader is the reader of today: it records
   each edit, and it reads Ctrl+Z and Ctrl+Y last.
4. **The run of typing is read at the caret of what the printer printed.** Two
   typed characters are one undo step while the caret is where the first
   character left it. That caret is the caret of the undo buffer now. Through a
   view it is the caret of the `UndoBufferView`. The operation that records an
   edit carries the document whose caret it reads. `RecordUndoOperation` gets
   one field for it, and its two constructors of today stay.
5. **The printer that holds the place of a view writes the node of that view.**
   The step of a view gives no operation now for a write of its own node. In
   this plan the printer of `UndoBufferView` says, in the context of the print
   of its child, that it holds the place of the child. The step of the child
   keeps that fact in its IO map. Its reader then passes a write of its own
   node up, and the printer of `UndoBufferView` writes it at `.viewed.content`
   with `make_content_edit`. The live place of a print is said in the context
   in the same way now (`with_live_place`). The step of a view takes the fact
   away for a child that prints as content. A view that no view holds still
   gives no operation, as plan 4a decided.
6. **A caret into a part that has no view takes the step `.viewed`.** A part
   that has no view is an element of a list or the document in a slot, of a
   type with no view type. The path of a caret into it is: the steps to the
   deepest view, the step `viewed`, and the steps in the content. Examples:
   `.elements.viewed[2].value{3}` and `.entries[1].viewed.value.value{3}`. So
   the walk of the kernel puts the caret into that part, and the part keeps its
   caret as it does with no view. The maps of the step of a view take the step
   `viewed` out on the way forward, and they put it in on the way back. A key
   goes to the part by the route of an intent, which the readers of the content
   print follow now (`Intent.route`). So the key table and the printer of the
   part read the key as they do with no view. The printer of `UndoBufferView`
   uses the same form for a content with no view: `.viewed.content`.
7. **`FileView` gets one field, `content`.** It holds the view of what the file
   holds, or `nothing`. `make_file_view(file; views = true)` makes a file view
   with that field in use. The default is `false`, so each file view of the
   editor is as now. With the field in use:
   - the scroll pane of the file view shows the view in `content`. When
     `content` holds `nothing`, the pane shows the file, as now;
   - the caret of the file view is its own, and it does not follow the caret of
     the file;
   - a path of the file view is `content.<rest>`, where it is `file.<rest>` now;
   - the printer of the file view reads the key table of its file after the
     answer of what it shows: Ctrl+S and F5. The printer of the file is not on
     the path then, so the file view does that job.

   `FileView` keeps the field `file` and its type. The field `viewed` and the
   type `ContentView` come in point 7 of the order.
8. **The general renderer gets one row for a view.** The row is for
   `ContentView`, in the rows of the syntax slice. It prints a view in the
   stages of the examples of plan 4a: the step of a view around the table from
   any domain to syntax, the step of a view around syntax to text with folds as
   text folds, the fold stage of the text, and the text stage with the line
   spacing of code. The barrier for a fault stays at each of the two recursive
   stages. A row for one view type, such as the row of `TextView` of the
   widgets, comes before it.
9. **Two view types for the place of every domain.** `DocumentInsertionView` and
   `DocumentNothingView`, in the syntax slice, because `@content_view` loads
   after the slice of the two content types. Their rows are the rows of
   `JsonInsertionView` and `JsonNothingView`: Return, Escape and Tab, and
   Insert. `JsonInsertionView` gets the Insert row that makes the place of JSON
   a place of every domain. The function that the row calls becomes a public
   function of the syntax slice, `make_insertion_widen_operation`.
10. **The tests compare.** A test of a key presses the key two times, with the
    caret at the same place: on a content with no view, and on an equal content
    through its views. After the key, the two contents are equal, and the two
    carets name the same place. A test of the row of the general renderer
    compares the pixels of a JSON file through views with the pixels of an
    equal file as content.

## Facts of the code

- `PaneTab.content` holds a `FileView(file, scroll)`
  (`source/platform/fileformat/FileView.jl`). `File.content` is declared with no
  type (`source/platform/serialization/FileFormat.jl`, line 87). The open of a
  file puts an `UndoBuffer` there (`make_history_wrap`,
  `source/platform/undo/HistorySettings.jl`, line 27).
  `UndoBuffer.content` is declared as `Document`, and its two lists as
  `CellVector` (`source/platform/undo/UndoDocument.jl`, line 82).
- `make_file_view` makes the selection of the file view follow the selection of
  the file (`follow_content_selection!`, `FileView.jl`, line 44).
- The printer of a file view makes a vertical layout of the row of the band and
  the scroll pane. It prints no child itself, and it has no reader of its own.
  Its maps change `file.<rest>` to `<scroll pane>.content.<rest>`
  (`source/platform/fileformat/FileViewToWidget.jl`).
- The content of a scroll pane can be a computation
  (`set_cell_computation!`, `source/platform/widget/WidgetDocument.jl`, line
  1747).
- The printer of a file prints its content through the recursion. Its reader
  asks the content first, and then the key table of the file. It puts the file
  on the path of the files of the context, so a file below itself shows as a
  closed card (`source/platform/fileformat/FileToContent.jl`).
- The printer of an undo buffer prints its content through the recursion. Its
  reader wraps each answer of the content in a `RecordUndoOperation`, and it
  reads Ctrl+Z and Ctrl+Y last (`source/platform/undo/UndoBufferToAny.jl`).
  The run of typing reads the selection of the buffer at two places:
  `_is_typing_run_open` in the reader (line 188), and the evaluation of
  `RecordUndoOperation` (`UndoDocument.jl`, line 324).
- An undo step keeps the caret of the root of the editor from before the step,
  and an undo puts it back by its path (`UndoDocument.jl`, lines 319 and 397).
  That path is a path of the views when the tab shows views.
- `@content_view` writes a child field for each field that is declared as a
  `CellVector`, and for each field that is declared as `Document`. It has no
  way to leave a field out
  (`source/platform/projection/higherorder/ContentViewDeclaration.jl`, line
  151).
- `make_content_edit` gives `nothing` for a write at the empty path, and it
  leaves a write that has the step `viewed` already as it is
  (`source/platform/projection/higherorder/Viewing.jl`, lines 135 and 139).
- A child that the view has no view for prints as content
  (`ViewRecursion`, `Viewing.jl`, line 408). The maps of the step read a path of
  the view as a path of the content (`get_content_path`, line 273). For a raw
  key, the reader of the step asks only the key tables of the views on the
  caret (line 469).
- The selection walk of the kernel enters a field only when the document has
  that field. So a path `.viewed.x` puts the caret into the content.
- The rows of the general renderer for a value that prints as code are in
  `source/platform/syntax/SyntaxNatural.jl`, line 118. No row is for a view. The
  rows of the file and of the file view are in `FileToContent.jl`, line 181.
  The row of the undo buffer is in `source/platform/undo/UndoModule.jl`, line
  89.
- The stages of a JSON view are in
  `example/domain/json/JsonViewProjectionExample.jl`.
- `DocumentInsertion` and `DocumentNothing` are in
  `source/platform/domain/DocumentCore.jl`. That slice loads before the slice of
  `@content_view`. Their printers are in
  `source/platform/syntax/InsertionToSyntax.jl`, and the function that makes
  the place of one domain a place of every domain is private there (line 324).
- `omnet-julia` uses `UndoBuffer` in one source file and in 7 test lines. It
  uses no `FileView`, no `make_file_view` and no `RecordUndoOperation`.
  `inet-julia` uses none of them.

## Steps

- [ ] **1. The row of the general renderer for a view.** Proposed decision 8.
  Tests, new, in the tests of the syntax slice: a `JsonArrayView` in a layout
  prints through the general renderer, with the same pixels as an equal array
  as content; a typed character and a key of a view act through it; a
  `TextView` of a widget takes the row of the widgets, as now; a fault in the
  print of one node costs that node only. One test records the picture of a
  closed fold through views beside the picture of a closed fold of a tab of
  today.
- [ ] **2. The view of the undo buffer.** Proposed decisions 2, 3 and 4.
  Tests, new, in a function `test_undo_buffer_view`: the view has the child
  field `content` and no field for the lists of steps; the child field gives
  the same view while the buffer holds the same document, and another view
  after a replace; the buffer through its view prints the pixels of the buffer
  with no view; a typed character through the view makes one undo step, and
  Ctrl+Z takes it back and puts the caret back; two typed characters are one
  step; two views of one buffer keep two carets, and Ctrl+Z in one view takes
  back the edit of the other; the buffer and its content hold no caret. The
  tests of the undo buffer of today keep their counts.
- [ ] **3. The write of the node of a view that a view holds.** Proposed
  decision 5.
  The step starts with a test of one fact: a key on the place for a new value
  that an undo buffer holds gives no operation through views now.
  Tests: the comparison of proposed decision 10 for a typed digit, for a typed
  name with Return, for Escape, and for the key `[` on a null, each at the root
  of an undo buffer; the undo of each; a view that no view holds gives no
  operation, and the tests of plan 4a keep their counts.
- [ ] **4. A caret in a part that has no view.** Proposed decision 6.
  The step starts with a test of two facts: a click in such a part gives no
  caret through a view now, and a key with a route reaches the printer of such
  a part through the readers of the content print.
  Tests, with a document of the platform that has no view type as the part: a
  click puts the caret at the path with the step `viewed`, and the part holds
  its caret; the comparison of proposed decision 10 for a typed character and
  for a key of the key table of the part; the caret moves from a view into the
  part and back with the arrow keys; the part as an element of an array, as the
  value of an entry, and as the content of an undo buffer.
- [ ] **5. The file view holds the view of what its file holds.** Proposed
  decision 7.
  The step starts with a test of one fact: which reader gets a key that
  nothing below the scroll pane of a file view took.
  Tests, new, in a function `test_file_view_content`: with `views = true`, a
  JSON file with undo steps gives the views of the first code block of this
  plan; the caret is a path of the views, and the file, the buffer and the
  array hold no caret; two file views of one file keep two carets and two
  scrolls, and one caret is live; the pixels are the pixels of the file view of
  today; Ctrl+S saves the file, and F5 reads it again and the view shows the
  new content; the row of the band shows, and a path below it maps; a file that
  is not read yet shows its views after the read; a file whose content has no
  view shows as now. With the default, each test of a file view of today keeps
  its count. One test records where the closed card of a file below itself
  shows through views.
- [ ] **6. The place for a new value of every domain.** Proposed decision 9.
  Tests: the comparison for each row of the two new view types; Insert in the
  place of JSON gives the place of every domain, with its view; a typed name of
  a domain and Return gives a document of that domain, as a view when its type
  has one, and as a part with no view when it has none.
- [ ] **7. The example.** One example: a JSON file with undo steps in two file
  views side by side, with a caret in each, a fold in one, and one part that
  has no view. It is registered as the examples of plan 4a are.
- [ ] **8. The wide check and the guides.** `test_platform()`, the suites of the
  JSON and the Markdown domains, and the examples, against the same runs at the
  base commit. The six guard scripts. The recorded precompile calls, if a list
  goes above its limit. `Pkg.precompile` of `omnet-julia` against the branch,
  with a count of the compiled packages. In
  `documentation/design/content-and-view.md`: "The code now", and the rule for
  a node that has no state. In `documentation/rule/architecture-rules.md`: the
  path of a caret into a part that has no view, and the write of the node of a
  view. The package documents of the undo, of the file formats, of the syntax
  and of JSON. Section 13.3 of the order document takes the cut of plan 4b. The
  plan moves to `plan/done/`. Then the session asks for the landing, and for
  the push apart.

## After this plan

The session makes a measurement before it writes the second plan. In a copy of
the repository, the JSON domain makes each file view of a JSON file with
`views = true`. The session runs the suites of the editor there, and it lists
each failure with the feature that it belongs to. The copy lands nowhere, and
the session deletes it. The steps of "The editor shows a JSON file through its
views" come from that list.

## Risks

1. **Another plan changes the readers.** `a-reader-is-split-by-its-jobs.md` is
   in work on the branch `reader-split`, and it changes each reader. This plan
   changes the readers of `ViewingProjection` and of
   `UndoBufferToAnyProjection`, and it gives `FileViewToWidget` a reader. The
   branch that lands second takes the form of the first.
2. **A key with a route can stop before the printer of a part.** Step 4 tests
   that fact first. If the kernel must change for it, the work stops and the
   session asks.
3. **A closed fold can look different through views.** The rows of a tab of
   today have no fold stage of the text, and the stage from syntax to text
   makes no text folds there. A view folds the lines of its text. Step 1
   records the two pictures. The difference shows in the editor only
   after the second plan.
4. **A file below itself.** The printer of a file view prints no child, so it
   can not put its file on the path of the files. Through views, the closed
   card of a file below itself can show one level deeper than now. Step 5
   records the place. The second plan decides it, because only that plan shows
   views in the editor.
5. **Two views share the caret of a part that has no view.** That part keeps
   its selection field, so one file in two tabs has one caret in it. The same
   is true for each content of today. It ends when the domain of the part gets
   views, in points 9 and 10 of the order.
6. **A walk reaches a document two times.** A file view with views holds the
   file and the views, and each view holds its content. A search that walks
   each field finds a document through both. In this plan no file view of the
   editor has views. The measurement shows each such walk.
7. **`a-history-records-every-edit-of-its-document.md` waits for its design.**
   Its goal is one undo history for a document in each place that shows it.
   This plan gives two file views of one file one history, because they share
   the undo buffer. It decides nothing of that plan.

## Not in this plan

- **The editor.** No tab shows a view after this plan. The second plan turns
  the views on for JSON files only.
- **The features that name a place by a path through the content**: the edits
  of the assistant, the open of a page at a place, Alt with the arrow keys, the
  place of the caret after a reload, the note under the pointer, the row of a
  file in the explorer and a dashboard card, a copy and a paste between tabs,
  and the arrangement of a tab. The second plan.
- **A function that gives the place in the views for a place of the content.**
  Its callers are the features of the second plan. Some start from a path and
  some from a document, and the measurement shows which form they need.
- **The step `.viewed` in each caret, the selection field of the JSON content,
  the kernel hook, and the caret place in an operation.** Plan 4c. The caret
  that an undo step keeps is a part of that plan too.
- **`FileView` below `ContentView`, with the field `viewed`.** Point 7 of the
  order.
- **A tab of another domain.** Markdown and the text have view types, and
  their tabs stay as they are until the review of the owner.
