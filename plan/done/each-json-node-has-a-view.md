# Each JSON node has a view

**Status:** done on 2026-11-18, on the branch `json-views`. The owner approved the
plan on 2026-11-18 ("Yes").

This plan is the first of the three plans of point 4 of the order in section
13.3 of `plan/tentative/content-and-view-for-the-whole-project.md`. The owner
agreed with the three plans on 2026-11-18 ("Yes", to "Do you agree with the split
into 4a, 4b and 4c, so that I write the plan for 4a now?"). The design is
`documentation/design/content-and-view.md`. Points 1 and 2 are on `main`. The
plan lands nothing and pushes nothing: it ends with a request to land.

The plan changes only views, tests and examples. The editor shows a JSON file as
content with no view after this plan, as it does now. No file of the kernel
changes.

## The problem

**An object, an entry and the place for a new value have no view.**

```julia
object = JsonObject("name" => JsonString("lamp"))

# now
make_content_view(object)             # nothing: the object prints as content
make_content_view(JsonInsertion())    # nothing

# after this plan
view = make_content_view(object)      # a JsonObjectView
view.entries[1]                       # the JsonObjectEntryView of the first entry
view.entries[1].value                 # the JsonStringView of "lamp"
```

So a caret in an object, shown through a view, has no place: the view of a list
gives `nothing` for an element that has no view type.

**The keys of an object are only in the key table of the content.**

```julia
# the caret is in the key of the first entry, at `.entries[1].key{2}`
press(',')    # now, through a view: no answer.   after: a new entry, and the caret is in its key
press('\t')   # now, through a view: no answer.   after: the caret is on the value of the entry
```

**An edit that comes back from the print of the content writes at a path of the
views.**

```julia
# the caret is in the place for a new value, at `.elements[2].value{0}`
press('7')
# the print of the place answers: replace the document at `.elements[2]` with JsonNumber(7)
# now, through a view:  `.elements` is the view of the list, so the write goes to a list of views
# after this plan:      the write goes to `.elements.viewed[2]`, which is the list of the array
```

## The decisions of the owner that this plan builds

They are in section 13.1 of the order document.

- **The tree of views mirrors the tree of content** (decision 6). A node is a
  document, a collection, an element of a collection, or the value in a slot
  that takes any value.
- **A field of a fixed plain type is a part of its node** (decision 7). The key
  of an entry is a `String`, so it gets no view of its own.
- **`@content_view` declares a view type** (decision 12).
- **A gesture that acts at the caret belongs to the key table of the view** (the
  owner on 2026-11-17: "why isn't the caret specific operations belong to the
  gesture table of the view?").
- **The step `.viewed` in a caret comes together with the loss of the selection
  field** (the owner on 2026-11-17: "I agree with A"). So the caret of a JSON
  view keeps the form of today in this plan, such as `.entries[1].key{2}`.
- **A printer is not the place that frees memory** (the owner on 2026-11-17).

## Proposed decisions

They are approved with this plan.

1. **Five new view types.**

   | View type | Content type | Child field | State |
   | --- | --- | --- | --- |
   | `JsonObjectView` | `JsonObject` | `entries`, the view of the list | `collapsed` |
   | `JsonObjectEntryView` | `JsonObjectEntry` | `value`, the view of the value | none |
   | `JsonInsertionView` | `JsonInsertion` | none | none |
   | `JsonNothingView` | `JsonNothing` | none | none |
   | `SyntaxDelimitationView` | `SyntaxDelimitation` | none | none |

   The last one is in the syntax slice. The place for a new value prints as a
   `SyntaxDelimitation`, and the step of a view needs the view type of what it
   printed. `SyntaxDelimitationView` is one view of the whole wrapper, as
   `TextView` is one view of a whole text. It takes the keys of
   `SyntaxNodeView` through one shared set of rows.
2. **The slot rule of `@content_view`.** The macro writes a child field for a
   field of the content type that is declared as `Document`, or as the union of
   `Document` and `Nothing`. The child field has the name of the field of the
   content. It holds the view of the document that the field of the content
   holds now, or `nothing` when that document has no view type. Of the content
   types that have a view, only `JsonObjectEntry.value` is such a field. Two
   kinds of field still wait:
   - a field that takes any value, such as `SyntaxDelimitation.content`, which
     is declared with no type. Its view can be the view of a plain value, and
     no plain value has a view type yet: point 8 or point 11;
   - a field of one document type, such as `SyntaxLeaf.value`: point 11.

   This closes one more part of open point 2 of the design document.
3. **The child field of a slot keeps one view.** While the slot holds the same
   document, the child field gives the same view. When the slot gets another
   document, the child field gives the view of that document, and nothing holds
   the view of the document that left. No code drops a view. After an undo, the
   document that comes back gets a new view, and the undo puts the caret back
   by its path.
4. **An edit through a view writes the content, by one function.** The function
   takes a view and an operation whose paths are paths of the tree of views. It
   finds, for each write, the deepest view above the written place, and it puts
   the step `.viewed` after that view. The view of a list is a view, so a write
   of element 2 of `.elements` becomes a write of `.elements.viewed[2]`. A
   write that has no view above its place gives no operation: a view that no
   view holds can not replace its own content. The step of a view applies the
   function to each operation that it answers: an answer of a key table of a
   view, and an answer of the readers of the print of the content. The function
   is `make_content_edit(view, operation)`, in the place of
   `make_content_edit(operation)`. That name came on 2026-10-21, after the
   release 0.1.0, so no released name changes.
5. **A row of a view acts for the node of that view.** The view at the end of
   the caret reads a key first, and its row answers with a path from itself.
   The step of a view makes the write of it (proposed decision 4). So
   `_find_innermost_array`, `_find_replaceable_view` and the reroot by hand in
   `JsonView.jl` go.
6. **The home of each key that acts at the caret.**

   | Key | Table | What it does |
   | --- | --- | --- |
   | `n`, `f`, `t`, `"`, `[`, `{`, a digit | `JsonView` (now) | replace the node of the view with a node of another kind |
   | `:` | `JsonView` (new) | replace the node of the view with an entry |
   | `,` | `JsonArrayView` (now) | append the place for a new value |
   | `,` | `JsonObjectView` (new) | append a new entry, with the caret in its key |
   | Tab | `JsonObjectEntryView` (new) | move the caret from the key to the value |
   | no key, by name | `JsonObjectEntryView` (new) | move the caret from the value to the key |
   | no key, by name | `JsonObjectView` (new) | sort the entries by key |
   | Return | `JsonInsertionView` (new) | make the document that the typed text names |
   | Escape | `JsonInsertionView` (new) | put the empty place back |
   | Tab | `JsonInsertionView` (new) | take the completion of the typed text |
   | Insert | `JsonNothingView` (new) | make the place for a new value of the empty place |

   Each row calls the function that the content uses now, with the caret of the
   view as an argument. The key table of each content type stays as it is,
   because the editor still shows JSON as content with no view.
7. **A new document still carries its caret.** A row gives the new document
   with the caret in it (`@selected`), as now. `make_content_edit` takes that
   caret out of the content and gives it to the view, as now. The caret place
   in the operation is a step of plan 4c.
8. **The test of a key is a comparison.** For each row of proposed decision 6,
   one test presses the key two times, with the caret at the same path: on a
   JSON content with no view, and on an equal content through its view. After
   the key, the two contents are equal and the two carets have the same path.
   The content under the view holds no caret. The comparison is possible
   because the caret of a view has the form of today.

## Facts of the code

- The five view types of JSON are in `source/domain/json/JsonView.jl`: null,
  boolean, number, string and array. The content types are in
  `JsonDocument.jl`. `@domain Json` makes `JsonInsertion`, with one field
  `value::String`, and `JsonNothing`, with no field
  (`source/platform/domain/Domain.jl`, lines 832 to 854).
- `JsonObject.entries` is declared as `CellVector{Document}`, so the macro
  writes its child field now. `JsonObjectEntry.key` is a `String` and
  `JsonObjectEntry.value` is declared as `Document` (`JsonDocument.jl`, lines 64
  to 67).
- The macro is `_make_content_view_declaration` in
  `source/platform/projection/higherorder/ContentViewDeclaration.jl`. It asks
  `find_child_view_type` for each declared field type.
- The key tables of the content: `JsonDocument`, 8 rows (`JsonDocument.jl`, line
  110); `JsonArray`, 1 row (line 128); `JsonObject`, 4 rows (line 139). The key
  tables of the views: `JsonView`, 7 rows (`JsonView.jl`, line 85);
  `JsonArrayView`, 1 row (line 129).
- The step of a view reads a key only with the key tables of the views on the
  caret, the deepest first (`read_intent` of `ViewingProjection` in
  `Viewing.jl`, line 362). It asks no table of a content and no table of a
  printer. An operation from the next stage goes back through the readers of
  the print of the content, and the step passes the answer on with no change.
- `make_content_edit(operation)` puts `viewed` before the path of a write, from
  the view that answers (`Viewing.jl`, line 84). So it is correct only when the
  content of that view holds the written place. `_find_innermost_array` in
  `JsonView.jl` finds that view by hand for one case.
- The keys of the place for a new value are a table of its printer, and not of
  a document: Return, Escape, Tab and Insert, in
  `get_projection_gesture_bindings` of `InsertionToSyntaxLeaf`
  (`source/platform/syntax/InsertionToSyntax.jl`, line 302). The Tab row reads
  the caret of the content (`_value_range`, line 250). The functions that the
  rows call for JSON are in `JsonToSyntax.jl`: `_commit_json_insertion` and
  `_complete_json_insertion`.
- A key that changes the text of the place for a new value comes back as an
  operation, through `map_operation_backward` of `InsertionToSyntaxLeaf` (line
  286). For JSON, a text that is a number gives a replace of the whole
  document, at the empty path.
- The print of the place for a new value gives a `SyntaxDelimitation` around
  one leaf (`InsertionToSyntax.jl`, line 240). The step of a view throws when
  the output has no view type (`Viewing.jl`, line 219). No view type of
  `SyntaxDelimitation` exists.
- The print of the empty place gives a `SyntaxLeaf`. A key on its label comes
  back as a text edit, and the printer reads it again as a key with the key
  table of the content (`InsertionToSyntax.jl`, line 550). That table reads the
  caret of the content.
- The print of an entry makes a node with two children: the leaf of the key,
  which the rule makes itself, and the print of the value
  (`JsonToSyntax.jl`, lines 118 to 129). The print keeps one child print, of
  the value. `_make_output_children` in `Viewing.jl` (line 318) gives one view
  for each child print, in their order. So the view of the value is at index 1
  of that list, and the value is child 2 of the node.
- Every place of JSON takes any document: the elements, the entries and the
  value of an entry. So the declared type of a place never limits the kinds
  that a person can type there.
- `_copy_view_state!` in `Viewing.jl` (line 122) copies a field of a view by
  assignment, except a child field that holds the view of a list.
- The examples of the JSON views are `example/domain/json/JsonViewDocumentExample.jl`
  and `JsonViewProjectionExample.jl`. The tests are four functions in
  `test/domain/json/projection/JsonViewTest.jl`.
- `omnet-julia` uses no view type and no `make_content_edit`.

## Steps

- [x] **1. The slot rule.** `@content_view` writes the child field of a field
  that is declared as `Document`, or as the union of `Document` and `Nothing`.
  The child field keeps one view (proposed decision 3). The copy of the state of
  a view goes through the view in a slot, as it goes through the view of a
  list.
  Tests, in `test_content_view_declaration`: the test type gets a child field
  for its slot; the child field gives the view of the document in the slot; it
  gives the same view at the next read; it gives another view after a write of
  the slot; it gives `nothing` for an empty slot and for a document with no
  view type; a copy of a view copies the state of the view in the slot and
  shares no view. The twelve view types of `main` keep their fields.
  **Done on 2026-11-18.** `test_content_view_declaration` has 49 of 49, and it
  had 27 before. The child field is a cell with a computation that keeps the
  document that it saw last and the view of that document. The copy of the
  state of a view takes each field that holds a view as a child field, and it
  writes no field whose value is equal already, so an empty child field of a
  copy still follows its content. The eighteen narrow tests keep their counts of
  the branch before the change.
- [x] **2. The views of the object and of its entry.** `JsonObjectView` and
  `JsonObjectEntryView`, by the declaration. The output view of a step holds
  the view of each child at the index of that child in the printed node.
  The step starts with a test of one fact: the print of an entry keeps one
  child print, and its node has two children.
  Tests, new, in a function `test_json_object_view`: each entry has a view and
  each value has the view of its kind; the object through its view prints the
  text of the object with no view; a caret in a key and a caret in a value are
  on the views, and no content holds one; a typed character changes a key and a
  value; two views of one object keep two carets; the fold of an object is the
  fold of a view; an object in an array in an object.
  **Done on 2026-11-18.** `test_json_object_view` has 52 of 52. The fact is
  true, and it is a test set of that function: the print of an entry keeps one
  child print, and its node has two children. The first run had 42 passes and 2
  errors, in the two test sets that looked for the step of an entry in the IO
  map (found fact 2). The eighteen narrow tests keep their counts.
- [x] **3. An edit through a view writes the content.**
  `make_content_edit(view, operation)`, and the step of a view applies it to
  each answer. The rows of `JsonView` and of `JsonArrayView` take the form of
  proposed decision 5.
  The step starts with a test of one fact: a replace of an element that comes
  back from the print of the content fails or writes a list of views now.
  Tests: the comparison of proposed decision 8 for the 8 rows of today, in an
  array in an array; a replace of the content of a view that no view holds
  gives no operation; the four test functions of today keep their counts.
  **Done on 2026-11-18.** The new platform test `test_content_edit` has 31 of 31.
  The four test functions of today keep their counts: 42, 34, 25 and 66. The
  fact could not be tested on the base: there the place for a new value has no
  view, so no print of it through a view exists. The comparison of a typed digit
  in step 5 tests the same write. Steps 3, 4 and 5 are one commit, because the
  comparison presses keys on a tree that holds the place for a new value, and so
  the tests of each of the three steps need the code of the two others.
- [x] **4. The keys of the object and of its entry.** The six new rows of
  `JsonView`, `JsonObjectView` and `JsonObjectEntryView` in the table of
  proposed decision 6.
  Tests: the comparison for each row. A comma on the brace that closes an object
  goes to the node around it, as now.
  **Done on 2026-11-18.** `test_json_view_keys` has 181 of 181. Its first run
  had 10 failures: Tab wrote spaces into a key through a view (found fact 6),
  and the test compared the text of a caret that holds a projection (the test
  now prints the type of the projection). The rows that have no key are tested
  through the list that a palette collects. After the first commit the tests of
  the comma name the effect of the key, with 215 of 215: a comma in a number, a
  comma at a place of the node around, and a comma on the bracket that closes
  the inner array.
- [x] **5. The place for a new value, and the empty place.**
  `JsonInsertionView`, `JsonNothingView` and `SyntaxDelimitationView`, with the
  five rows of the table. The function of the Tab row takes the caret as an
  argument.
  The step starts with a test of one fact: what a key on the label of the empty
  place gives now, when the content holds no caret.
  Tests: the comparison for each row; the comparison for a typed name and
  Return, for a typed digit, for a typed `-` and then a digit, and for a key on
  the label of the empty place; a place for a new value as an element, as the
  value of an entry, and as a view that no view holds.
  **Done on 2026-11-18.** `test_json_insertion_view` has 147 of 147. Its first
  run had 50 failures and 1 error, all from one cause: the syntax stage refused
  each character that a person typed into the empty place (found fact 7). The
  fact of this step: with no caret in the content, the rows of the content
  answer nothing for a key on the label of the empty place. The chain then gives
  the key to the key tables of the views, and the row of `JsonView` answers. So
  the printer of the empty place needs no change.
- [x] **6. The example.** One example of an object in two views at three
  places, with a fold and with the place for a new value, beside the three
  examples of the array and of the string. It is registered as they are.
  **Done on 2026-11-18.** The example is `json_object_view`. The test of its
  printer has 7496 passes and no failure. The 116 other examples of the platform
  and of the JSON and the Markdown domains have the counts of the base commit.
- [x] **7. The wide check and the guides.** `test_platform()`, the suites of
  the JSON and the Markdown domains, and the examples, against the same runs at
  the base commit. The six guard scripts. The recorded precompile calls, if a
  list goes above its limit. `Pkg.precompile` of `omnet-julia` against the
  branch, with a count of the compiled packages. In
  `documentation/design/content-and-view.md`: "The code now" and open point 2.
  In `documentation/rule/architecture-rules.md`: the slot rule, and the rule
  that an edit through a view writes below `viewed`. The package documents of
  JSON and of the syntax. The plan moves to `plan/done/`. Then the session asks
  for the landing, and for the push apart.
  **Done on 2026-11-18.** The base commit is `f7c6d4339`.
  - `test_platform()` at the base: 236427 passes, 16 failures, 1 error, 21
    broken. On the branch: 236480 passes, 16 failures, 1 error, 21 broken. The 17
    lines of the failures and of the error are the same. The 53 more passes are
    the new tests: 22 in `test_content_view_declaration` and 31 in
    `test_content_edit`.
  - The JSON suite: 418 of 418 at the base, 832 of 832 on the branch. The 414
    more are the new tests: 52, 215 and 147. The Markdown suite: 358 of 358 at
    the base and on the branch.
  - The test of the printer of each example of the platform and of the JSON and
    the Markdown domains: 116 examples with the same counts, and the new example
    with 7496 passes.
  - The eighteen narrow tests have the counts of the branch before the change.
    The layering guard of the platform has the two failures of `main`, with the
    same text.
  - The six guard scripts of `test/suite/` give the same output at the base and
    on the branch, except one finding of the documentation guard that moved to
    another line of `json.md`. The arguments guard had one new finding in the
    first run: an optional positional argument of `make_completion_operation`.
    The argument is a keyword now.
  - No recorded list of precompile calls names a function that this plan changed
    or removed.
  - `Pkg.precompile` of `omnet-julia` (`main` at `64014ec5d`) against the branch:
    295 packages compiled, 199 were compiled before, and none failed. All 68
    paths of the manifest into this repository lead to the branch. The 295 hold
    all 75 packages of the environment. The log has no warning. `omnet-julia`
    and `inet-julia` use no name that this plan added or changed.
  - The documents: `documentation/design/content-and-view.md` ("The code now"
    and open point 2), `documentation/rule/architecture-rules.md`,
    `documentation/package/kernel/projection-system.md`, and the package
    documents of JSON and of the syntax.

## Found during the work

1. **The views that a step gives are placed by their content.** The method of
   `make_content_view` that takes the views of a step is written by the macro,
   and only that method knows the list of the printed node. So the macro puts
   each given view at the index of its content in that list
   (`_make_given_views`), and `_make_output_children` stays as it is. A given
   view at a wrong place of the given list is found too. The change is in the
   commit of step 1, because it is in the file of the macro.
2. **A test can not find the step of the view of a child in the IO map of a
   print.** The recursion of a view keeps the steps of the children in a table
   of its own. The tests read the output view of the step of the whole view,
   and the views below it.
3. **The step of a view makes the edit at each stage, in two directions.** A
   chain has a step of a view at more than one stage. An answer of a later stage
   is an operation of the output view of the stage before it, and that stage
   maps it back with the readers of its content print. So each step also takes
   the step `viewed` out of a write that comes from the next stage
   (`_make_printed_edit`). The two functions are the two path functions of point
   4 of the order, for a write. Plan 4c uses them for a caret too.
4. **`make_content_edit` takes a wrapped operation and the rows of a palette.**
   A palette collects each row with its operation, so the function makes the
   edit of each row, and it leaves out a row whose write has no place.
5. **A write of a field of state of a view stays a write of the view.** The
   function reads the declared type of the field of the view: a child field
   holds a view, and any other field of the view is state.
6. **The fold stage of a view lost the mark of an edit of the indentation.** Tab
   in a text makes an edit with the mark `changes_indentation`, and the syntax
   stage declines such an edit, so Tab goes to the key tables. The reader of
   `TextFolding` for a view made a new edit with no mark. So Tab in a key
   through a view wrote spaces into the key. The comparison of the Tab row
   found it. The correction is one line in `source/platform/text/TextFolding.jl`.
7. **The syntax stage reads the caret of its content at one more place.** Two
   parts of a node can share one position of the text, for example the end of
   an empty delimiter and the start of the typed text after it. The reader of a
   node in `SyntaxToText.jl` reads the caret of the node to choose the part. A
   node under a view has no caret, so the stage refused each character that a
   person typed into an empty place for a new value. The view of a node now
   makes that choice with its own caret, in a method of `read_view_operation`
   for `SyntaxNodeView` and `SyntaxDelimitationView`. The read of the caret of
   the node stays for a node with no view. It goes in point 11.
8. **`SyntaxDelimitationView` takes the rows of the table of `SyntaxNodeView`.**
   Its table splices the table of the node view, so the rows are the same
   objects and they keep their tag.
9. **The Tab of the place for a new value is one function with the caret as an
   argument.** `make_completion_operation(insertion, caret; completion, place)`
   is a new exported function of the syntax slice. The Tab row of the printer
   calls it with the caret of the content, and the Tab row of the view calls it
   with the caret of the view. `find_value_range` reads the caret, as it did for
   an operation.

10. **Two starts of one job were in the queue.** A second start of a run with
    the same name does not replace a start that still waits for memory. The
    start that got memory first ran the job, and the other start ended. The job
    ran the state of the worktree at that time, which was the state that the
    second start was for.

## Risks

1. **Another plan changes the readers.** `a-reader-is-split-by-its-jobs.md` has
   steps open, and it changes each reader. This plan changes one reader, of
   `ViewingProjection`. The branch that lands second takes the form of the
   first.
2. **The comparison can show a difference that is correct.** A key can act in
   another way through a view for a good reason, for example on a view that no
   view holds. Each such case gets a line in "Found during the work", and a
   test of its own.
3. **The print of the content can read the caret of the content at more
   places.** The search found three: the Tab row of the place for a new value,
   the key on the label of the empty place, and the entry, which gives its
   selection cell to its node (`JsonToSyntax.jl`, line 129). Step 5 tests the
   first two. The third is tested in step 2, by the caret in a key.
4. **`SyntaxDelimitationView` is a view of the syntax, which other domains
   print too.** In this plan only JSON makes one. Its form for a wrapper around
   a node with folds is a part of point 11.

## Not in this plan

- **The editor.** A tab shows a JSON file as content with no view. Plan 4b
  changes that, with the views of the file and of the undo buffer.
- **The place for a new value of every domain.** `DocumentInsertion` and
  `DocumentNothing` are types of the platform, and they get views in plan 4b.
  So the Insert row that makes the place of JSON a place of every domain is not
  a row of `JsonInsertionView` here.
- **A document inside a JSON tree whose type has no view.** Most documents of
  the other domains are such documents. It prints as content and it takes no
  caret through a view, as now. A document of a type that has a view, such as a
  Markdown document, takes its view.
- **The rule that a view reads the key table of its content after its own.** It
  comes in plan 4c, when the key tables of the JSON content keep no row that
  reads a caret. Until then, the row that sorts the entries is in both tables.
- **The step `.viewed` in a caret, the selection field of the JSON content, the
  kernel hook, and the caret place in an operation.** Plan 4c.
- **The limit of the kinds by the declared type of the place.** A row of
  `JsonInsertionView` asks for the kinds with no limit. Every place of JSON
  takes any document, so the answer is the same.
