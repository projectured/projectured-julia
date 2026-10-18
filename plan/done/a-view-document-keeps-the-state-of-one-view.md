# A view document keeps the state of one view

Status: DONE. Steps 1 to 4 are done.

## The ask

The owner, 2026-10-17: "I have the feeling that we often put some object
representing some concept which is not UI concept and then we put the UI state
data on some parent object which really happens to be about the view. But maybe a
lot of code and state would be simpler if we would have separate view objects,
no? [...] This really is a generic separation of concerns, and this is a
projectional editor, so there's nothing wrong with introducing new types and
dispatch on them."

After the evaluation, the owner: "Write down the rule, that's good. I also agree
with where to apply first. I'm not sure about the Page suffix, I was thinking of
View suffix."

The first use is the page of an omnet configuration with its runs, the plan
`omnet-julia/plan/pending/a-configuration-view-shows-the-runs.md`. This plan holds
the parts of projectured-julia that it needs.

## What the code does now

Five slices already keep the state of a view apart from what the view shows, and
these are the slices where two views of one thing work:

| Content, which all views share | View, one for each view | Where it says so |
| --- | --- | --- |
| a folder: its listing, its read state, its watch (`FileSystemDirectory`) | the open folders (`WorkspaceExplorer.open`) | `filesystem.md`: "An explorer owns what a person controls, and shares what it reads." |
| a chart: its series and axes | the zoom, the cursor, a drag (`ChartPlot`) | `chart.md`: "A saved chart has no view state, and two views of one chart zoom apart." |
| a graph (`GraphGraph`) | its geometry (`GraphLayout`) | `ChartDocument.jl` |
| a data frame | the anchor, the top row, the filter, the sort (`DataFrameView`) | two tabs on one frame show two queries |
| any document | the open and shown nodes (`DocumentTree`); the address, Back and Forward (`Navigator`) | one for each tree and each navigator |

Other places mix the two:

- **The omnet configuration.** `LegacyConfigurationEntry` holds the configuration
  beside the read flag of the details of its runs. The flag is one flag on an
  entry that two editors can share, but the holds are counted for each editor, so
  the rows of the second editor can miss their read.
- **Folds on content.** About 40 content types have a `collapsed` field (JSON,
  Markdown, YAML, XML, workflow, conversation and others). Two tabs on one JSON
  document fold together, and a save writes the fold.
- **A page shows its content and keeps nothing.** A navigator shows the document at
  its address, so the state of the page, such as the place of a long table, has no
  document of its own, and a view of a page can hold nothing that only the page
  shows.

## The rule

Step 1 writes it, in these words or close to them:

- **A content document says what a thing is**, and what was read about it from
  outside, with the state of the read. There is one for each thing in an editor,
  and all views of the thing share it.
- **A view document says how one view shows content**: the open nodes, the head of
  a lazy list, the rows in view, a filter, a sort, a fold, the current part. There
  is one for each view, and for each place when a view has places. It names the
  content that it shows with `get_edited_field`, so a path into the content goes
  through the view.
- **A view document holds the content that it shows**, so a read of outside state
  follows the views by the count of holders, and the content shares what it read.
  A view document is held only while it shows.
- **A view document of one kind of content takes the suffix `View`**, as
  `DataFrameView` and `ResultTableView` do. A view that is a tool of its own keeps
  its name: `DocumentTree`, `Navigator`, `WorkspaceExplorer`, `ChartPlot`.
- **The reader still decides what is view state** (`undo.md`): a view document can
  itself be edited as content, as the sections of an explorer are.
- **A save of content writes no view state.** A view can save its own state apart.

"View" in `concepts.md` is what a view definition makes from the data. A view
document is an input of a view definition, beside the content that it shows. Step 1
says this in `concepts.md`, so the two words do not meet.

## Decisions

1. **Write the rule down** (the owner, 2026-10-17: "Write down the rule, that's
   good").
2. **Apply it first to the omnet configuration and its runs** (the owner: "I also
   agree with where to apply first").
3. **The suffix is `View`** (the owner: "I was thinking of View suffix").
4. **The view of a page lives in the visit of the navigator** (Q1 (a), the owner,
   2026-10-17: "I agree with your recommendations"). The navigator keeps the view
   of its page, as it keeps the address and the selection of each visit; what the
   view shows and holds stays in the view.
5. **The selection of a view follows the selection of its content (D1)** (the
   owner, 2026-10-18: "I agree it's D1"). A selection path keeps going through the
   content, `content.<address>.<rest>`, and every user of the navigator keeps its
   paths. When the navigator makes a view, the selection cell and the cell of the
   part under the pointer of the view are computations: the edited field of the
   view, then the cell of its content. The map of the navigator to its drawing puts
   that field into the path, and its map back takes it out. A part that only the
   view draws has no content path, so it names nothing, and a press there leaves
   the selection where it is. Over
   D2, in which the paths of the navigator go through the view: D2 changes eight
   places of the navigator and the paths that the explorer reads, while the
   content still keeps the selection. D2 is the direction of the later plan
   `views-compose-as-content-composes.md`, in which a view keeps its own
   selection; then the computed cell becomes a stored one.

## Q1. Where the view of a page lives (decided: (a))

A configuration opens as a page from many places: the explorer, the link of a task
to its run, a tab, the Runner. The view of the page must exist only while the page
shows, because it holds the rows that its table shows.

- **(a) In the visit of the navigator (my recommendation).** A new generic,
  `make_document_view(document)`, makes the view of a document when a page opens;
  its default answers the document itself, so every other page stays as it is. The
  navigator keeps the view of its page, holds it, and draws it. Each visit keeps its
  view, so Back returns to the same rows, as a browser keeps the place of each page
  in its history. A visit already keeps the selection that the person had when they
  left the page, so the view sits beside it.
- **(b) In the node of the explorer tree, one for each place.** The tree keeps no
  document for a place now (its `_TreeEntry` lives in its projection), the
  explorer branch of another session changes the tree, and a page that opens from a
  task link has no node.
- **(c) One for each configuration in the editor.** The navigator must still hold
  and draw the view, so this is (a) with a registry more, and two navigators share
  one place in the table.

## Steps

Each step is one commit with its tests, in a worktree. Mark each step done here.

1. [x] **The rule.** A section "Content documents and view documents" in
   `documentation/rule/architecture-rules.md`, the term in `concepts.md`, and the
   sentence of the suffix in `naming-rules.md`. Test: `test_documentation()`.

   Done 2026-10-17. The guides of projectured name no type of omnet-julia, so the
   rule names only projectured examples: `FileSystemDirectory` and
   `WorkspaceExplorer`, `ChartPlot`, `DataFrameView`, `DocumentTree`, `Navigator`,
   `FilePage`; the suffix sentence names `DataFrameView` and `FindBarView`. The fold
   is written as the exception that the code has: `collapsed` on the content types.
   `test/suite/documentation.jl`: every document keeps the rules; no line of the
   new text is in the report for a person.
2. [x] **The lazy table says which rows its view shows.** `WidgetTable.shown`, view
   state: the rows in view, counted from the head, as a range. The table writes it
   beside each scroll and each move of its head, when it changes, as it writes
   `top_row` now. The ten positional calls of `WidgetTable` follow the new field.
   Tests: `test_widget_table_list()`, `test_task_pages()`, `test_dataframes()`.

   Done 2026-10-17. `shown` sits right after `top_row`, beside the other view state
   of the table, so each positional call has one more `Cell(nothing)` before its
   20th argument; Julia's own parser placed it (`JuliaSyntax`), not a text
   substitution. The rows in view go from the row at the top to the last row that
   starts in the view of the cells; after a move of the head they count from the
   new head. A change of the height of the view writes no `shown`: only a scroll
   writes it, as for the tree. omnet-julia and inet-julia make no positional call
   of `WidgetTable`. Tests: a table whose rows are a list 253, task pages 47, cell
   table 11 + 4, roster table 24, tool themes 113, data frames 612, pivot 299,
   markdown 268; all pass.
3. [x] **The navigator shows the view of its page** (decisions 4 and 5). `make_document_view`
   in the domain slice; `Navigator.view` and `NavigatorVisit.view`; a visit makes
   the view of its page, and Back and Forward give back the view of their visit; the
   navigator holds the view in place of the page; the print draws the view, and a
   path in the page goes through `get_edited_field` of the view. Tests:
   `test_navigator_visits()`, `test_navigator_to_widget()`, `test_navigator()`,
   `test_document_tree()`.

   Done 2026-10-18. What it made:
   - `make_document_view` and `follow_content_selection!` in a fragment of the
     domain slice, `DocumentView.jl`. The second sets the selection cell and the
     pointer cell of a new view as computations: the step of its edited field, then
     the cell of its content, also for a selection that the content keeps while it
     is not live (`SelectionDocument`).
   - The field is `page_view`, because `NavigatorAddress.view` already names the
     kind of the address bar; the getter is `get_navigator_page_view`.
   - The view sits in a `NavigatorViewSlot`, a box that a walk does not enter
     (`is_walk_opaque`): a search walk of the navigator then makes no path through
     the view, and a selection path through it would clear its computed selection.
   - A visit makes the view of its page, in the reader that makes the visit. A
     method of `make_document_view` changes no state, because a reader also makes
     answers that it only describes, and their views are dropped.
   - The acquire makes a view when the navigator has none of its page, or when
     another holder holds its view. A duplicate keeps no view, also in its visits
     (`copy_document` of `Navigator`), so each tab keeps its own place.
   - The backward map takes the field step out of a path in the view, and a path in
     the view that does not go through the field names nothing.
   - Found at the omnet configuration view, 2026-10-18: a part that the view
     introduced, such as a link or a button of the page, has a path of the view, not
     of its document. With the rule above, the pointer could not light it and a
     press could not reach it. So an introduced path keeps its place after the page
     with no field, in both maps and in the computed cells of the view: a view draws
     its whole page with one projection. Branch `view-introduced-parts`; navigator
     visits 99, navigator view 68, document tree 102.
   - The review found the limit that stays: an edit that puts another document at
     the address of the page shows that page bare, which nothing holds, until the
     next acquire of the navigator; the old page and its view stay held until the
     navigator is released. The code before held the old page in the same way.
   - Tests: navigator visits 98, navigator view 66, choices 42, page open 92,
     gestures 24, document 32, address 40, document tree 102, task pages 47, task
     document 104, assistant work 100, agent plan 82; all pass. The naming and
     documentation guards pass; the exports and arguments guards report only the
     three violations that main has.
4. [x] **The guides.** `navigator.md`, `widget.md` (the table), `domain.md`
   (`make_document_view`); the plan moves to `plan/done/`.

   Done 2026-10-18. `navigator.md` has a section "The view of a page"; `widget.md`
   names `shown` of a lazy table; `domain.md` names the view of a page, and its
   example of a document that reads for the parts that a holder holds is the rows
   of a long table. The documentation guard passes, and no line of the new text is
   in the report for a person.

The explorer branch of another session uses the navigator. Step 3 tells that
session what changes before it lands.

## Not in this plan

The folds of the content types, a tree of node views, the omnet project page, and a
rename of the view documents that exist.
