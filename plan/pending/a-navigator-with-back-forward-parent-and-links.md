# A navigator shows one page of any document, with back, forward, parent, an address and links

> **Kind:** plan · **Status:** pending, 2026-10-06. The owner decided D1 to D9
> on 2026-10-06 (§8); D7 waits for step 6. Steps 1 to 5, 7 and 10 are done on the
> branch `navigator`; §9 holds the questions that they raised. ·
> **Stands on:** [concepts.md](../../documentation/design/concepts.md),
> [pane.md](../../documentation/package/platform/pane/pane.md),
> [generic-projections.md](../../documentation/package/platform/projection/generic-projections.md),
> [reference.md](../../documentation/package/kernel/reference.md),
> [selection.md](../../documentation/package/kernel/selection.md),
> [undo.md](../../documentation/package/platform/undo/undo.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)

## 1. The goal

The owner's words (2026-10-06): "a navigator something which allows browser like
forward/backward navigation and perhaps even parent (if it's meaningful) […] the
case when a user clicks for example a link or a row on a table which brings up a
detail page and then navigate back. Perhaps even showing an address bar, which is
the location of the component that is being shown. […] in a general way so it
combines with many other aspects of the user interface and mostly independent of
what is shown and being navigated. links would also be great, which can be
followed like in HTML".

So:

- A navigator shows one part of a document at a time: the **page**.
- A press on a link, or on a row of a table, opens another page in the same
  navigator. **Back** returns to the page before, and **Forward** goes again.
- **Parent** opens the page that holds the current page, when one exists.
- An **address bar** shows where the page is.
- The navigator knows nothing of the domain of the page, and the page knows
  nothing of the navigator.

The requirements that this serves:
[PR-FOCUS-AND-REORGANIZE](../../documentation/requirement/accepted-requirements.md#pr-focus-and-reorganize)
(narrow the view to a part and widen it back),
[PR-SEARCH-AND-JUMP](../../documentation/requirement/accepted-requirements.md#pr-search-and-jump)
and [PR-REACH-ANY-PART](../../documentation/requirement/accepted-requirements.md#pr-reach-any-part).

## 2. The words of this plan

| Word | What it is |
| --- | --- |
| page | the part of the content that the navigator shows now |
| content | the root document that the navigator shows a part of; any domain |
| address | the path from the content to the page, a `Reference` |
| visit | one page that a person saw: the content, the address, and the selection in the page when the person left it |
| back list, forward list | the visits before and after the current visit, as in a browser tab |
| link | a part that opens a page when a person presses it |
| open | the request of a link: "show this page" |

## 3. What exists

What the plan can use:

- `FocusingProjection` shows the part at the path `part`, and Ctrl+, and Ctrl+.
  zoom out and in ([Focusing.jl](../../source/platform/projection/generic/Focusing.jl)).
  Its maps put `part` before a path and take it off. It keeps `part` in the
  projection, so nothing saves it, and it has no back list and no bar.
- `get_parent(root, x)` gives the document that holds `x`, one step up the path
  and past each collection
  ([ReferencedDocument.jl:309](../../source/kernel/reference/ReferencedDocument.jl#L309)).
  This is the parent page.
- `DocumentLocator(start, reference)` and `find_referenced_document(locator)`
  find a document again after the tree changed, and answer `nothing` when the
  path reaches no node
  ([ReferencedDocument.jl:253](../../source/kernel/reference/ReferencedDocument.jl#L253)).
  `get_valid_reference_prefix` cuts a path at the first node whose type changed
  ([ReferenceEvaluation.jl:94](../../source/kernel/reference/ReferenceEvaluation.jl#L94)).
- `ReferenceToText` and `ReferenceToHumanReadableText` draw a path as text
  ([ReferenceToText.jl](../../source/platform/text/ReferenceToText.jl)).
- `get_document_title(document)` gives the title of a document, and a tab with
  an empty name shows the title of its content (pane.md).
- `ReplaceViewStateOperation(operation)` marks a write as view state, so undo
  records none of it
  ([Operations.jl:309](../../source/kernel/operation/Operations.jl#L309)).
- An operation that carries a path goes up the readers, and each reader maps the
  path backward. A new kind registers with `operation_reference` and
  `retarget_operation`. An operation that carries its own root goes up unchanged
  (PAR-REGISTER-NEW-OPERATION). The family `ReplacePathOperation` holds the
  selection, the part under the pointer and the start of a drag
  ([OperationInterface.jl:85](../../source/kernel/operation/OperationInterface.jl#L85)).
- A part answers `StartDragOperation`, and the drag wrapper above it takes the
  operation out of the answer
  ([DragTracking.jl](../../source/platform/dragtracking/DragTracking.jl)). The tab
  strip answers `CloseTabOperation`, and the reader of the pane tree makes the
  edit. These are the precedents for a part that asks and a document above it
  that acts.
- `OpenFileOperation` opens a tab with `open_pane!` when the editor evaluates it
  ([FileSystemDocument.jl:81](../../source/platform/filesystem/FileSystemDocument.jl#L81)).
- A row of a data frame is a document, `DataFrameViewRow`, at the path
  `rows[r]` of a `DataFrameView`. It has a title and a context menu
  ([DataFrameView.jl:123](../../source/adapter/dataframes/DataFrameView.jl#L123),
  [DataFrameRowEdit.jl:162](../../source/adapter/dataframes/DataFrameRowEdit.jl#L162)).
- A context menu collects the answers of the parts around the part under the
  pointer (`is_collecting_operation`), so a document around a part can add
  items to its menu.
- Links in the data: `MarkdownLink(content, url)`, `RstReference(text, target)`
  and `RstTarget(name)`
  ([MarkdownDocument.jl:65](../../source/domain/markdown/MarkdownDocument.jl#L65),
  [RstDocument.jl:82](../../source/domain/rst/RstDocument.jl#L82)). Each is drawn
  as coloured text, and a press on it only moves the caret.
- A file names a node of another file as `node(file("a.json"), "children[1]")`,
  and `_evaluate_path_text` reads such a path, with field and index steps only
  ([FileSplice.jl:275](../../source/platform/serialization/FileSplice.jl#L275)).
- The icon table has `:arrow_up` and `:chevron_right`, and no left or right
  arrow (`LUCIDE_ICON_GLYPHS`,
  [WidgetToGraphics.jl:7788](../../source/platform/widget/WidgetToGraphics.jl#L7788)).

What does not exist:

- No back and forward of a view, no address bar and no breadcrumb.
- No part that follows a link. No row of a table opens a detail.
- `ComponentMasterDetail` is a document with no projection
  ([component.md](../../documentation/package/platform/component/component.md)).
- No side button of the mouse: `MouseButtons` names left, middle and right, and
  a backend sends no event for another button
  ([MouseEvent.jl:27](../../source/kernel/event/MouseEvent.jl#L27),
  [SdlBackend.jl:552](../../source/backend/sdl/SdlBackend.jl#L552)).
- Alt+Left, Alt+Right, Alt+Up and Alt+Down walk the structure of a document and
  of the pane tree
  ([PaneGestures.jl:160](../../source/platform/pane/PaneGestures.jl#L160)). The
  keys of a browser are not free.
- No parser from any text to a `Reference`.

## 4. The model (tentative)

### 4.1 The navigator is a document

```julia
@document struct Navigator <: Document
    content::Document                 # the root that the pages are parts of, any domain
    address::Reference                # the path of the page, from `content`
    back::Vector{NavigatorVisit}      # the visits before this one, the newest last
    forward::Vector{NavigatorVisit}   # the visits after this one, the nearest last
end

struct NavigatorVisit
    content::Document
    address::Reference
    selection::Union{Reference, Nothing}  # the selection in the page when the person left it
end
```

- The address is **state of a document**, not of a projection (D3). So it is
  saved (the address only, D6), duplicated with a tab, edited by the assistant, and read by no other
  projection. `FocusingProjection` keeps its path in the projection, which
  suits a focus that a program sets; both can stay, as the filter plan keeps a
  parameter and a query document
  ([filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md) §2).
- The address is **not the selection**. A pane group shows the tab that its
  selection names, but the caret of a page moves inside the page, and the page
  must stay.
- A visit holds its content, so the back list can go from one document to
  another, as a browser tab goes from one site to another.
- A `NavigatorVisit` is a value, not a document, as `DocumentLocator` is.

### 4.2 The page

The page is `find_referenced_document(DocumentLocator(content, address))`. When
an edit removes the page, for example a delete of the row, the address reaches no
node. The navigator then shows the page at the longest valid prefix, with a line
that says that the part no longer exists. Back and Forward still work.

### 4.3 The view: `NavigatorToWidget`

The view is a bar above the page.

- **The bar** holds the Back, Forward and Parent buttons, and the address. A
  button is off when its list is empty, or when `get_parent` finds no parent.
- **The address** is a breadcrumb: one item for each document on the path from
  the content to the page. It skips each collection, as `get_parent` does. An
  item shows the `get_document_title` of its document, or the step when the
  document has no title. A press on an item opens that page. The tooltip of the
  address shows the path as `ReferenceToText` draws it.
- **The page** is the document at the address, which the grid of the view holds
  itself; the layout stage after the view prints it through the recursion (step
  1 found this pattern in `EvaluatorToWidget`). The recursion picks the view
  of the page by its type. So a kind adds a page view only where its page must
  look different from its part in the view of its parent: a row of a data frame
  is a row in the table and a form of its columns as a page.
- **The maps**: the path `.content` + address + rest maps to the page slot +
  rest, and back. Any other path under `.content` has no image, because it is not
  on the page. These are the maps of `FocusingProjection`, rooted at `.content`.
- **The reader** gives a key to the page first, and the `@gestures Navigator`
  table answers a key that the page declines (PAR-DELEGATE-AND-LIFT). A press on
  a button answers the operation of the button. An open from inside the page is
  §4.4.

### 4.4 Open a page: one operation

One new operation, `OpenPageOperation(document, reference, place)` (the owner
accepted the operation and its two forms on 2026-10-06, D2):

- With `document === nothing`, `reference` is a path from the part that
  answered. Each reader on the way up maps it, as any path. This form opens the
  part itself or a part under it: a row of a table, a field of a form, an element
  of a list.
- With `document !== nothing`, the operation carries its own root and goes up
  unchanged. This form opens any object: a node of another file, or an object of
  the program.
- `place` is `:here`, or `:new_tab` for Ctrl+click and the middle button, as in
  a browser.

The navigator takes an `OpenPageOperation` with `place = :here` from the answer
of its page:

1. A path under `.content` becomes the new address.
2. For an operation with its own root, the navigator searches its content for
   that document (bounded, PAR-SEARCH-DONT-WALK). If it finds it, the path is
   the new address. If not, the document becomes the content of a new visit.
3. The write is one `CompoundOperation` inside a `ReplaceViewStateOperation`:
   push the current visit on the back list, clear the forward list, write the
   address (and the content), and move the selection into the new page.

An `OpenPageOperation` that no navigator takes reaches the editor. Its
evaluation opens a new tab that holds a navigator on that page (D4), with
`open_pane!`, as `OpenFileOperation` opens a file. For `place = :new_tab` the
navigator turns the path into an operation with its own root, the content of
the navigator, and lets it go up.

### 4.5 Back, Forward and Parent

- **Back** takes the newest visit from the back list, puts the current visit on
  the forward list, and writes the content and the address of the visit. It
  puts back the selection that the visit holds. When the visit holds no
  selection and the page that the person leaves is under the new page, the
  selection goes to the page that the person leaves. A file manager does the
  same with the folder that the person came from.
- **Forward** is the mirror of Back.
- **Parent** opens `get_parent(content, address)` as a new visit, so Back
  returns to the child. Parent is off at the root of the content.
- Each is view state. Undo records none of them, and an edit on a page is an
  edit that undo takes back while the navigator stays on the page.

### 4.6 Where links come from

From the nearest to the farthest:

1. **A part opens itself, or a part under it.** The part that owns the gesture
   answers `OpenPageOperation` with a path. The row of a data frame gets an
   "Open" item in its context menu, and a press on the row header opens the row.
2. **Any part, with no code in its domain.** The navigator adds "Open as a page"
   and "Open in a new tab" to the context menu of each part on its page, for the
   part under the pointer, and a key opens the selected part. So any value can
   be opened as an inspector opens a field.
3. **A link in the data.** A markdown link, an rst reference, a JSON `$ref`, a
   foreign key of a database row, a file reference. Only the domain knows what
   its names mean, so the domain gives the path or the object. A link is drawn
   as a link: the link colour, the hand pointer, and its address in a tooltip.

How a domain finds a named target that is not under the link, such as an rst
target in another section, is open (§8, D7).

### 4.7 Keys, buttons and the palette (D5)

| Action | Proposal | Why not the key of a browser |
| --- | --- | --- |
| Back | Ctrl+[ | Alt+Left walks the structure and the pane |
| Forward | Ctrl+] | Alt+Right, the same |
| Parent | Ctrl+Up | Alt+Up walks the structure |
| Open the selected part as a page | Ctrl+Return | Return commits a cell and opens a file |
| Back and Forward on the side buttons of the mouse | step 10 | the event layer has no side button |

A search of the `@gestures` tables found no use of these four chords. The
gesture help must confirm it before a step lands. The palette names are "Go
back", "Go forward", "Go to the parent page", "Open as a page" and "Open in a
new tab".

## 5. How it combines

- **Panes.** A tab holds a navigator. A tab with an empty name shows the title
  of the page. "Open in a new tab" opens a tab beside it. A duplicate of the tab
  copies the back and forward lists, as a browser does.
- **Master and detail.** A link in the master opens its page in a navigator
  beside it, as the `target` of an HTML frame. The component that holds both
  takes the open answer of the master and writes the address of the detail.
  The decision stays in the component, which is local
  (PAR-DECIDE-LOCALLY). `ComponentMasterDetail` gets its projection in that step.
- **Undo.** Navigation is view state. An edit on a detail page is an edit.
- **Selection.** There is one selection from the root (PAR-SELECTION-WRITTEN-AT-ROOT).
  The selection in the page is part of it, and a visit keeps the part of it in
  the page.
- **Filter and sort.** A path from a filtered or sorted table maps back to the
  row of the source, so the detail page is the row of the source.
- **Large and lazy data.** The navigator prints only the page. The address of
  row 10,000,000 is one path.
- **The assistant and MCP.** Open, Back, Forward and Parent are operations, with
  a verb pair such as `make_open_page_operation(editor, place, address)` and
  `open_page!(editor, place, address)` through `read_rooted_operation`.
- **Faults.** A page that fails to print shows the fault in the page area, and
  the bar still works.
- **Files.** A navigator on a folder of the file system is a file browser, and
  Parent opens the folder above.
- **The view on demand.** A navigator on an object of the program, with "Open
  as a page" on a field, is an inspector with a way back.

## 6. Considered and not proposed

- **The address as the selection**, as a pane group shows its selected tab. The
  caret moves inside a page, and the page must not follow it.
- **The address in the projection**, as `FocusingProjection` keeps it. Nothing
  saves it, the assistant can not see it, and PAR-WIDGETS-ARE-PRESENTATION and
  the owner's rule of 2026-10-02 prefer an operation that writes document state.
- **A reference step for "up"**, for a link such as `../sibling`. A new step
  comes only when the steps that exist can not say the place. An object with
  its own root, or the resolver of the domain, says it.
- **A new event or a new payload for the reader.** None is in this plan. The
  open request goes up as the answer to the press, on the path that every press
  takes.
- **One history of the selection for the window**, as the Go Back of an IDE
  over the places of the caret in all files. It is a different feature. It can
  come later and use the same visit lists.

## 7. Steps (tentative)

- [x] **1. The navigator.** `Navigator`, `NavigatorVisit` and `NavigatorToWidget`
  in a new slice of `ProjecturedPlatform`, with the bar, the page and the maps.
  Back, Forward and Parent as view state, and the `@gestures` table. The
  selection comes back; undo records nothing; the IO map of the navigator keeps
  its identity (PAR-STABLE-IOMAP-IDENTITY). Done, 2026-10-06. What the work
  found and decided:
  - The slice is `source/platform/navigator/`: `NavigatorDocument.jl`,
    `NavigatorVisits.jl` (the page and the operation builders),
    `NavigatorGestures.jl` and `NavigatorToWidget.jl`. Its row of the renderer
    is `ChainingProjection(NavigatorToWidget, GridLayoutToGraphicsCanvas())`.
  - **The view prints no child.** The grid holds the page document itself in
    `children[2]`, as a computed cell, and the layout stage prints it through the
    recursion, so the row of the type of the page draws it (D9). This is the
    pattern of `EvaluatorToWidget`. The maps are `content.<address>.<rest>` ↔
    `children[2].<rest>`; a path into the bar maps back to nothing.
  - **A button reports, the view acts.** A press answers `InvokeActionOperation`,
    which goes up the chain unchanged, and the reader turns the action of a
    button into the operation of the navigator, as the appearance tab does. The
    operation needs the path of the selection from the navigator, which only the
    view knows, so the button can not build it itself.
  - **An operation** is a `CompoundOperation` of a `ReplaceViewStateOperation`
    around the writes of `address`, `back`, `forward` (and `content` when it
    changes), and a `ReplaceSelectionOperation` with a path from the navigator.
    The lists are written as new vectors.
  - The constructor is positional, `Navigator(content[, address])`: the
    `@document` macro gives a keyword constructor only with every field as a
    keyword.
  - Ctrl+Return, "Open as a page", came into this step from step 4, because it
    needs no `OpenPageOperation`: it opens the innermost document on the
    selection below the page.
  - The address is one line of titles from the content to the page; step 3 makes
    it a breadcrumb. The buttons have text labels until step 3 adds the icons.
  - The tests are in the platform test package, which can not load the JSON
    domain, so they use a shelf of books and chapters declared in the test:
    `test_navigator()`, 97 tests, `NavigatorVisitsTest.jl` and
    `NavigatorToWidgetTest.jl`. The editor test presses Ctrl+Return, Ctrl+Up,
    Ctrl+[, Ctrl+] and the Back button, and checks that undo records nothing.
- [x] **1b. The Files pane is not called a navigator (D1).** The word named the
  Files pane in about 25 lines of source, 40 lines of tests, twenty documents,
  the help text of the binary and its build command, and the example that a
  person ran as `run_example("navigator")`. The owner chose the whole rename on
  2026-10-06. Done, 2026-10-06: the Files pane is "the Files pane",
  `_make_application_workspace` makes it, the example is `run_example("files")`
  (`files_example`, `FilesDocumentExample.jl`, `FilesProjectionExample.jl`,
  `asset/image/example/files.png`), and the noun "navigator" for the caret motion
  in the testing guide and a catalog comment is "the caret motion".
  `test_application()`: 344 pass, the 2 known broken, no fail.
- [x] **2. Open.** `OpenPageOperation` (D2), with the path form and the form
  with its own root. The navigator takes it, and the editor opens a navigator
  tab for one that no navigator takes. Ctrl+click opens a new tab. Done,
  2026-10-06. What the work found and decided:
  - `OpenPageOperation(document, reference[, place])` is in the navigator slice,
    in `OpenPageOperation.jl`. It registers with `operation_reference`,
    `retarget_operation` and `is_self_contained_operation`, so every reader
    maps the path form and passes the other form up unchanged. No reader of
    another slice changed.
  - The reader of `NavigatorToWidget` takes an open after the generic bridge
    mapped it: a path under `content` becomes a visit; with `:new_tab` it
    becomes an open with the content as its root, which goes on up.
  - **No search.** An open with its own root is a path from the content when its
    document is the content or a document on the address. Any other document
    becomes the content of a new visit, with no parent. `search_references`
    walks every value of the content down to a depth of 64, so over a frame of
    ten million rows it would read every value.
  - An open that no navigator takes posts the opening of a tab, as the open of
    a file does (`post_pane_operation!`). For the path form, the content of the
    new navigator is the document of the tab that holds the part, past the
    layers that `get_edited_field` names (an undo, a file), so Parent reaches
    the rest of it. So the navigator slice uses the pane slice.
  - A test drains the inbox with `drain_operations!` after the open, because
    the posted opening of the tab waits there.
  - The view on demand, which draws a document that has no view of its own,
    does not pass an operation with a fixed place (`read_rooted_operation`) to a
    place inside it. The tests send such an open to a place that a layout holds.
    A verb of the assistant at a place inside such a page has the same limit.
  - No generic link widget: a link is the part of a domain or a view that
    answers `OpenPageOperation`. The test link is a `WidgetButton` whose
    gesture bindings answer it, with `:new_tab` for Ctrl+press. A widget slice
    below the navigator can not name the operation; a `WidgetLink` would need
    the operation in a lower slice.
  - `test_open_page_operation()`, 37 tests; `test_navigator()` now runs 138.
- [x] **3. The address.** The breadcrumb with titles, the tooltip with the path,
  and the left and right arrows in `LUCIDE_ICON_GLYPHS`. Done, 2026-10-06:
  - Back, Forward and Parent are `WidgetToolbarItem`s, which show the icon of
    their action alone and are flat at rest, as a toolbar is. The label of the
    action is the tooltip; the tooltip of an item adds its key.
  - The address is one item for each document from the content to the page,
    with "›" between two items. An item is a `WidgetToolbarItem` with the name
    of its document; a press opens its page, with the page that the person
    leaves selected, as Parent does. The page is the last item, a plain label.
    The tooltip of an item is its path from the content.
  - A name is the title of the document, or the steps that reach it from the
    item before (`entries[2]`, `value`), or at the root the name of its type.
  - `:arrow_left` (`0xe048`) and `:arrow_right` (`0xe049`) are in the icon
    table; the code points are read from the cmap of `asset/font/lucide.ttf`.
  - The items follow the address through a computed cell in the IO map, which
    the reader reads to find the item that a press names.
  - Open: a JSON part has no title, so the address of a JSON page names the
    steps (`JsonObject › entries[2] › value`). A title for a JSON entry, such as
    its key, is a change of the JSON domain, and `get_document_title` has other
    readers, such as the name of a tab; it waits for the owner.
- [x] **4. Open any part.** "Open as a page" and "Open in a new tab" in the
  context menu of each part on a page. The key for the selected part came with
  step 1. Done, 2026-10-06:
  - The `@gestures` table of `Navigator` splices a right-click binding. Its menu
    belongs to the innermost document under the pointer, below the page (or the
    selected one, for a command with no pointer), read from the `mouse_target`
    of the navigator. The source of the menu is the path of that part, with its
    types, so the context menu window lifts an item from the part up through the
    reader of the navigator. A source at the navigator itself would skip that
    reader, because a routed operation is not read at its own place.
  - Each item holds an `OpenPageOperation` rooted at the content, so it opens the
    same page from the outer layer (F2) of a part that has a menu of its own.
  - The reader joins the menu of the navigator after the answer of the page with
    `read_gesture_outward`, as a container does for a document around a part.
  - The gesture help collection (`CollectIntents`) is no collecting operation,
    so the reader merges the table of the navigator into the answer of the page
    with `merge_collected_intents`, as `FileToContent` does. Without it, the
    gesture help lists no key of the navigator while the selection is in a page.
  - The forward map of the view keeps the types of the path inside the page and
    types the two steps of the grid, because the pane splices the image of a tab
    into its own path and needs a type on every node.
  - `test_navigator_gestures()`, 20 tests; `test_navigator()` runs 166.
- [x] **5. A table and its detail page.** The page view of a data frame row, a
  form of its columns. The "Open" item of a row and a press on a row header.
  The case of the owner: the table, a row, Back to the table with the row
  selected. An example, a test, and a check in a live window. Done 2026-10-06.
  The example is `make_data_frame_navigator_example(; rows)` of
  `ProjecturedDataFramesExample`, a navigator on the view of
  `make_data_frame_example`; the example registry has no data frame, so it is a
  factory and no `run_example` entry. The live check drove that example in a
  real SDL window with pushed events from the main task, 11 of 11: a double click
  on the number of row 3 opens the row, the arrow before "row 3" opens the list
  of rows in a window of its own, typing 5 and Return open row 5, Ctrl+[ goes
  back, Ctrl+Up goes to the table, and Ctrl+L, `.rows[7]` and Return open row 7.
  A pushed double click needs two press pairs, as SDL makes one from two
  presses. What the work found and decided:
  - `DataFrameViewRowToWidget` draws a row as a form of the name and the value of
    each column, in a scroll pane, read-only. A value shows as a cell of the
    table shows it. The form reads `frame_version`, so it follows a write of the
    frame. `make_graphics_projection(::Type{DataFrameViewRow})` registers it.
    An edit on the detail page is not in this step: a cell of a frame takes an
    edit only through the open cell of the table.
  - The menu of a row starts with "Open as a page" and "Open in a new tab": an
    `OpenPageOperation` of the row itself. With no navigator, it opens a tab with
    a navigator on the row, whose content is the view of the frame.
  - A double click on a row header opens the row. The view of the frame maps it,
    because the view owns the headers: after its own selection of the whole row
    it adds the open. A binding of the row itself never fires: the press on a
    header answers a selection first.
  - Enter on a selected row does not open it: the table takes Return with any
    modifier, and moves into the first cell. So the four keys of the navigator
    became `override` rules, which take their chord also after the page
    answered it, and the reader of the navigator gives a key that the page
    answered to its table as a claimed key, as the evaluator does. Ctrl+Return
    opens a selected row.
  - **A bug of step 1, found here:** the grid of the view printed the page once,
    so a new address changed the bar and not the page. A grid prints its
    children once; a `VerticalLayout` prints its children again when its list
    changes. The page now stands in a vertical layout of one child, whose list is
    computed from the address: `children[2].children[1]`. The tests of the
    platform now count the drawn texts of the page.
  - **A bug of the pane, found here, outside the navigator:** an item of the menu
    of a frame row in a tab failed with `under-typed @reference` at
    `PaneToWidget.jl:430`, for "Insert row above" too. The pane typed only the
    head of the image of a tab content, and the view of a frame gives an image
    of several steps without types. The pane now types the whole image against
    the document that the tab draws when the image is not fully typed. A test
    chooses "Insert row above" from a frame in a tab.
  - **Parent of a row.** The parent of `rows[2]` is the `DataFrameViewRows`
    that holds the rows, a document that `get_parent` does not look past, so
    Parent opened it and not the table. `is_element_collection(::DataFrameViewRows)
    = true` would fix it, but the search, the view on demand, the file cut and
    the sync iterate an element collection, which over a frame of ten million
    rows makes ten million row documents. Decided by the owner (Q1, 2026-10-06):
    a trait of the navigator, `is_navigator_stop`, which the adapter answers
    `false` for the rows; Parent of a row is the table.
  - **Open: a tall page.** The navigator puts no scroll pane around its page, by
    the owner's rule that a part scrolls where it is made. A page whose view has
    no scroll pane, such as JSON, is cut at the bottom of the navigator.
  - `test_data_frame_row_page()`, 31 tests after A5 and A6.
- [x] **6. Links in the data.** Markdown and rst links that a press follows,
  drawn as links. A file reference. A named target after D7.
  **Decided (owner, 2026-10-06):**
  - The gesture: in a source view, Ctrl+click follows a link in the navigator,
    as in an IDE, and Ctrl+Shift+click opens it in a new tab; in the rendered
    markdown view, a plain click follows it and Ctrl+click opens a new tab, as
    in a browser. A plain click in a source view edits the text of the link.
    The option not chosen: Ctrl+click in every view, with "Open in a new tab"
    in the menu of the link.
  - What a link names: `#anchor` and an rst reference go to the target in the
    same content, through the function of D7 that the domain answers (a
    markdown heading by its slug, an rst `.. _name:`); a relative file path
    opens that file in a new tab with a navigator, as the open of a file does;
    a web URL does nothing in this step, and its tooltip shows it. The option
    not chosen for a URL: the system browser, a side effect outside the editor.
  - **Q4, decided (owner, 2026-10-07):** a link answers a third form of
    `OpenPageOperation`: the path of the link, as the path form has it, and
    `target`, the text of the target as the domain writes it (`#install`,
    `guide.md`, an rst name). The nearest navigator resolves the target on its
    content; with no navigator, the editor resolves it against the document of
    the tab that holds the link, and opens a navigator tab. The option not
    chosen: a new operation type with the same flow.
  - **Q5, decided (owner, 2026-10-07):** the function of D7 is
    `find_navigator_target(root, target)`: a `Reference` to a part of `root`,
    the absolute path of a file, or `nothing` for a web URL or an unknown name.
    A navigator that an open makes from a file tab keeps the file document as
    its content root, past the history only, so the file is its first page and a
    relative file name is read against the name of that file. The option not
    chosen: the content past the file, and a file name read against the folder
    of the Files pane.
  - **Q6, decided (owner, 2026-10-07):** the application gives its history to
    every file that is opened when the open is evaluated, not only through the
    Files pane, so the navigator tab of a linked file has undo too. Facts: only
    the application knows the history wrap (`make_history_wrap(settings)`); the
    menu Open (`FileDialog.jl`) opens a file with no history today. The options
    not chosen: a navigator tab with no history, or a file link that opens the
    file as the Files pane does, with no navigator.
  - **Q10, decided (owner, 2026-10-07):** Q9 changes, because of two facts found
    while building it. The `wrap` of the open of a file goes around the content
    inside the file (`make_file_tab`), so a navigator in `wrap` would not have the
    file as its root. And a history records only the edits that pass through its
    own projection; a navigator prints a page directly, so a page below the root
    of the content bypasses a history inside it. For step 6, option (a):
    `OpenFileOperation` gets a second hook for what goes around the file
    document; a link gives a navigator, and the evaluation builds a history
    around the navigator around the file. A plain file keeps its history inside
    the file. Option (c), a history that records every edit of its document from
    any view, is its own plan:
    [a-history-records-every-edit-of-its-document.md](a-history-records-every-edit-of-its-document.md).
    The option not chosen: (b), the history around the file for every file tab.
  The parts:
  - [x] 6a. The target form of `OpenPageOperation`, `find_navigator_target`
    with a default of `nothing`, the resolution by the navigator and by the
    editor, and the content root of a navigator made from a file tab (Q5). Done
    2026-10-07: the field `target` and the keyword of the constructor; the
    navigator answers a target that names nothing here with
    `DoNothingOperation`, so the press does nothing else; a file path that the
    function answers opens nothing until 6d.
  - [x] 6b. Markdown: the target of an anchor (a heading by its slug) and of a
    relative file; the gestures of a link in the source view and in the rendered
    view; the look of a link (its colour, the hand pointer, its address in a
    tooltip). The targets are done, 2026-10-07 (`MarkdownLinkTarget.jl`):
    `compute_markdown_heading_slug` as GitHub writes an anchor; a relative file
    must exist, because the open of a missing file makes an empty one; a URL with
    a scheme names nothing.
  - [x] 6c. rst: the target of a reference (an `.. _name:` target), and the same
    gestures and look. The targets are done, 2026-10-07 (`RstLinkTarget.jl`):
    the part after a target of the name, or a section whose title reads it, as
    rst compares names; then a relative file that exists.
  - Facts found 2026-10-07 for the gestures and the look, which wait for the
    owner: in a text view the text layer answers every click with a caret, and an
    `override` rule takes a claimed gesture only for a key, along the selection
    (`_read_override_gesture` in `ProjectionTemplate.jl`); the outward read of a
    click stops at the first answer (`_read_outward`). So no table of a link can
    take a Ctrl+click in the source view, and no projection can take a plain
    click in the rendered view. The text layer draws one I-beam region over a
    whole text (`TextToGraphics.jl`), and a span has no pointer shape. A tooltip
    needs nothing new: `make_tooltip_binding` in the table of the link.
  - **Q7, decided (owner, 2026-10-07):** the template reads a claimed click as it
    reads a claimed key, but along the path of the part that the click selected,
    innermost first. A link binds `override(Ctrl+click)` and
    `override(Ctrl+Shift+click)` in its gesture table, and the rendered view
    `override(click)` on its link. The option not chosen: the navigator asks the
    domain whether a selected part is a link, inside a navigator only.
  - **Q8, decided (owner, 2026-10-07):** a text span gets a pointer shape, which
    the syntax of a link sets, and the text layer draws a region for it. The
    option not chosen: no hand pointer in this step.
  - **Q9, decided (owner, 2026-10-07):** the evaluation of an open gives the file
    a history when the editor has settings: `make_history_wrap` moves to the undo
    slice, and the file system slice gets the edges `undo` and
    `settingsmanaging`. An opener passes only its own wrap; a link passes a
    navigator, so its tab is a history around a navigator around the file. The
    option not chosen: a reader of the application that gives a history to each
    open that passes it.
  - [x] 6d. A file link opens the file in a new tab with a navigator, and the
    application gives every opened file its history (Q6). The mechanism goes to
    the owner before it is built. Done 2026-10-07, by Q10 (a):
    `OpenFileOperation(path; wrap, file_wrap)`, and the evaluation puts a history
    around the part of `file_wrap`, or around the content inside the file.
    `make_history_wrap` is in the undo slice; the Files pane passes no history of
    its own, and the menu Open gets one too.
  - [x] 6e. Tests, the design document, and the keyboard guide. Done 2026-10-07:
    the tests of the open, of markdown and of rst links, of the text layer; the
    documents of the navigator, markdown, rst, text, undo, file system, the
    claimed click in devices-and-backends.md, and the keyboard guide.
  What was built and decided on the way, 2026-10-07:
  - The claimed click (Q7) is in `ProjectionTemplate.jl`: it reads the path of
    the claimed selection, maps it into the input of the node, and goes along
    it, innermost first, through template nodes and through other parts child by
    child, as a route does; each part answers with its projection bindings, then
    with its table, and only `override` bindings fire.
  - The source view keeps the I-beam over a link (my decision): a plain click
    there puts the caret, and a hand would promise a click that does not follow.
    The rendered views show the hand (Q8), which is the view that a navigator and
    the application draw: markdown and rst register their rendered rows with the
    natural renderer.
  - The rendered rst section had no maps of its own, so a click inside it
    selected the section and the reference got no click. It maps its title and
    each block now; the type-in sweep of the `rst_rendered` example drops from
    2520 to 630 failures against the baseline at the branch point, and the
    `rst` and `markdown_rendered` sweeps stay as they were (240 and 8).
  - `TextString` has the field `pointer_shape`; the constructor of the fields
    that `@document` makes takes it in the seventh place, so a call with six
    values and `Cell(nothing)` for the selection now gives no shape and the
    default selection, which is the same span.
  - A relative file that does not exist names nothing, because the open of a
    missing file makes an empty one.
- [x] **7. Panes and files.** The tab title follows the page. A duplicate copies
  the lists. A save keeps the address only (D6). Done, 2026-10-06, with one
  change of the plan:
  - **The name of a tab does not follow the page; its tooltip does.** The pane
    gives an opened tab a fixed name, and its code says that a tab must not
    rename itself (`_make_open_pane`); `find_pane` finds a tab by that name. A
    label follows a state through its icon, badges and tooltip, so
    `make_pane_tab_title(::Navigator, name)` gives the tab a tooltip that reads
    the address of the page. A name that follows the page is a question for the
    owner.
  - `has_document_duplicate(::Navigator) = true`: the copy descends into the
    navigator, copies the address and the lists, and shares a content that
    declares no duplicate, as a browser duplicates a tab.
  - **A save failed before this step:** the `.pred` notation writes no
    `Reference` value and no `NavigatorVisit`, so a window with a navigator tab
    could not save. `pred_arguments(::Navigator)` writes the content and the
    address as the text of a path (`books[2]`), and `make_pred_document` reads
    it back with empty lists (D6).
  - The file layer had the writer and the reader of such a text as private
    helpers of its `node(file(…), "children[1]")` form. They are public now, as
    `print_path_text` and `parse_path_text` of the serialization slice, beside
    `print_pred_text` and `parse_pred_text`; step 8 reads a typed address with
    the same reader.
  - `test_navigator_document()`, 27 tests; `test_navigator()` runs 196.
- [x] **8. A typed address.** Field and index steps, read as
  `_evaluate_path_text` reads them. Done as the edit of the path view of §10
  (A3 and A4, 2026-10-06): a person types `.name` and `[i]` steps in place, and
  Enter reads them.
- [ ] **9. Master and detail.** `ComponentToWidget` on two navigators. Moved out
  of this plan by the owner (Q7, 2026-10-06), to
  [component-document.md](component-document.md).
- [x] **10. The side buttons of the mouse** (D5): `MouseButtons`, the SDL
  backend and the web backend. Done, 2026-10-06:
  - The event layer names the side buttons `:back` and `:forward`, by what a
    person sees on the mouse; SDL calls them `X1` and `X2`. `MouseButtons` holds
    two more flags, `back` and `forward`, so a move with a side button held says
    so too. Every build of `MouseButtons` outside its own file uses keywords.
  - SDL maps the buttons 4 and 5, and the bits `0x08` and `0x10` of a motion. The
    web client maps the buttons 3 and 4, and the bits 8 and 16, and stops the
    default of a side button, so the browser does not leave the page.
  - The `@gestures` table of `Navigator` binds a click of `:back` and `:forward`
    with any modifier; a part on the page answers no such click.
- [x] **11. Documentation.** A design document for the slice, the keys in
  [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md),
  and the example in
  [examples-tour.md](../../documentation/guide/examples-tour.md).
  - [x] The design document
    [navigator.md](../../documentation/package/platform/navigator/navigator.md),
    its row in the package index, and the keys in the keyboard guide, for steps
    1 to 4 (2026-10-06). Each later step updates the document.
  - [x] The example in the examples tour, after step 5. Done 2026-10-06: the
    section "A table and its detail page" opens the data frame example from the
    evaluator of the application, because the gallery of `run_example` draws no
    popup. A headless check of the editor that `run_application` builds, with the
    example opened by `open_pane!`, passed the 11 checks of the live run. A fact found on the way
    (2026-10-06): a host gives an opened window only the rows that it names, so
    the list of choices opened an empty window in the application and in the
    gallery; the tests gave popups the natural renderer. **Decided (owner,
    2026-10-06):** `make_opened_window_projections` ends with the natural
    renderer, so a popup with a document that no row names draws through the
    rows that the slices register. The options not chosen: a row for the list in
    each host, or a list of widgets only.

## 8. Decisions for the owner

- **D1. The name. Decided by the owner, 2026-10-06: `Navigator`.** The words
  are the navigator, the page, the address, the visit, the back list and the
  forward list, the link, and open, go back, go forward and go to the parent
  page. The code names are `Navigator`, `NavigatorVisit`, `NavigatorToWidget`
  and `OpenPageOperation`, in the slice `source/platform/navigator/`
  (`NavigatorModule`).
  - "The navigator" now names the Files pane in the text of the application
    ([Application.jl:4](../../source/platform/application/Application.jl#L4)),
    and `_make_application_navigator` makes it. Step 1 calls it "the Files
    pane", which is the title of its tab, and renames the function
    `_make_application_workspace`.
  - "Page" keeps the meaning that the tabbed pane gives it: the content that a
    container shows, one at a time.
  - "Navigation" also means a move of the caret in source, for example tree
    navigation and `test_position_navigation`. This plan says "navigate" only
    for pages, and "move" or "walk" for the caret. A rename of the uses for the
    caret is not part of this plan.
  - The names that were not chosen: `Browser`, because "a browser" is where the
    web backend runs; `PageNavigator`; `Explorer` and `Inspector`, which name
    two tools; `Pager`.
- **D2. The operation `OpenPageOperation`. Decided by the owner, 2026-10-06:
  yes.** It is a new operation that a document above the part takes from the
  answer, as the drag wrapper takes `StartDragOperation`, with the two forms of
  §4.4: a path from the part that answers, and an object with its own root. The
  form that was not chosen is a new member of the `ReplacePathOperation` family,
  which can carry only a path under the link, so no link to another file.
- **D3. Where the address is. Decided by the owner, 2026-10-06: in the data.**
  The address is a field of the `Navigator` document. The option that was not
  chosen keeps it in the projection, as `FocusingProjection` keeps its path.
- **D4. A link with no navigator around it. Decided by the owner, 2026-10-06:
  it opens a new navigator tab on the target.** The options that were not
  chosen: move the selection to the target, or do nothing.
- **D5. The keys. Decided by the owner, 2026-10-06: as §4.7 proposes.** Ctrl+[
  goes back, Ctrl+] goes forward, Ctrl+Up opens the parent, and Ctrl+Return
  opens the selected part. The side buttons of the mouse are a later step of
  their own (step 10), because they change `MouseButtons` in the kernel, the
  SDL backend and the web backend.
- **D6. What a save keeps. Decided by the owner, 2026-10-06: the address
  only.** A window that opens again shows the same page, with empty back and
  forward lists. The options that were not chosen: the address and the lists,
  or nothing.
- **D7. A named target. Decided by the owner, 2026-10-06 (with Q4): a function
  on the content root that a domain answers.** It was open until step 6 first.
  Paths and objects with their own root cover the case of a table and its
  detail page. The two options for step 6: a function that the navigator calls
  on its content root and that a domain answers, which is a new generic
  function, or a resolver in the projection of the domain.
- **D8. Parent. Decided by the owner, 2026-10-06: a new visit.** Back then
  returns to the child, as in a file manager. The option that was not chosen
  changes the current visit.
- **D9. The view of a page. Decided by the owner, 2026-10-06: by the type of
  the page.** The recursion picks it, so a kind adds its page view once and
  every navigator uses it. A page projection as a parameter of the navigator
  can come later, if a case needs it.

## 9. Questions that the implementation raised (2026-10-06)

The owner answered Q1 to Q4 and Q7 on 2026-10-06; Q5 and Q6 wait for the
answer to a proposal. Each answer is under its question.

- **Q1. Parent of a row of a data frame.** `rows[r]` lies in
  `DataFrameViewRows`, a document that `get_parent` does not look past, so
  Parent opens it and the address shows "rows". Options:
  (a) `is_element_collection(::DataFrameViewRows) = true`, with a check of every
  walker that iterates an element collection: the search, the view on demand,
  the file cut, the sync; over ten million rows each would make ten million row
  documents;
  (b) a trait of the navigator, such as `is_navigator_page(document)`, that a
  domain answers: a new generic function;
  (c) leave it.
  Recommendation: (b), because it changes no walker, and the meaning (a part
  that is no page of its own) belongs to the navigator.
  - **Owner, 2026-10-06:** "a container may also be the part that is shown in a
    navigator but having a trait seems reasonable". **Done:**
    `is_navigator_stop(document)` says where a navigator stops when it goes up,
    names the address, and opens the selected part or the part under the
    pointer; the navigator can still show a container as a page at its own
    address. The data frame adapter answers `false` for `DataFrameViewRows`, so
    Parent goes from a row to the table. The test that was marked broken
    passes.
- **Q2. The name of a navigator tab.** It keeps the name that it opened with, and
  its tooltip follows the page, because the pane says that a tab must not rename
  itself. Options: as now; or the name follows the title of the page, as in a
  browser, which changes the name that `find_pane` reads. Recommendation: as
  now.
  - **Owner, 2026-10-06:** agreed, as now.
- **Q3. A tall page.** The navigator adds no scroll pane, by the owner's rule
  that a part scrolls where it is made, so a tall JSON page is cut. Options: as
  now; a scroll pane around a page whose view has none, which needs a way to know
  that (a trait, a new generic function); or each domain view that can be tall
  makes its own scroll pane. Recommendation: the last, one view at a time.
  - **Owner, 2026-10-06:** yes, each view that can be tall makes its own
    scroll pane.
- **Q4. D7, a named target**, for step 6: markdown and rst links name an anchor,
  a file or a URL. Options as in §8, D7. Recommendation: a function on the
  content root that a domain answers, after Q1 settles whether the navigator
  takes domain traits.
  - **Owner, 2026-10-06:** agreed: a function on the content root that a domain
    answers. D7 is decided with it.
- **Q5. The typed address (step 8).** Where the text lives while a person types
  it (a field of the navigator, as view state), which key starts it (Ctrl+L, as
  in a browser, is free), and whether the bar shows a text field or the
  breadcrumb turns into one. Recommendation: Ctrl+L turns the breadcrumb into a
  text field over a view-state field of the navigator; Enter opens the path,
  Escape returns.
  - **Owner, 2026-10-06:** "the address bar can be edited in place without
    turning it into a text field". With Q6, the proposal to the owner: the bar
    shows the text of the reference and a caret edits it in place, as the name
    of a tab is edited; Enter opens the path, Escape puts back the address; the
    items of names go away. Waits for the owner.
- **Q6. The names of JSON parts.** A JSON entry has no title, so the address of a
  JSON page names steps (`entries[2]`, `value`). A `get_document_title` of an
  entry that is its key changes the JSON domain, and other readers of the title,
  such as the name of a tab. Recommendation: the key, with a check of those
  readers.
  - **Owner, 2026-10-06:** "the address could be a reference, no? what is it
    now? a reference could address anything". The answer: the address is a
    `Reference` (the field `address`), and the bar shows the titles of the
    documents on it. The proposal under Q5 shows the reference itself.
  - **Owner, 2026-10-06, after a discussion of the forms:** "we should think more
    about the address, what it should be and how it should be edited", with
    three parts to it: the titles, the path without types, and the types along
    the path. **Decided: the address becomes a document**, with three views
    that a switch in the bar changes: the titles (the default), the path, and
    the path with its types. The titles and the path take edits; the types are
    shown and not edited. The design continues in §10, one decision at a time;
    Q5 and Q6 close into it.
- **Q7. Step 9, master and detail.** It needs `ComponentToWidget`, which
  [component-document.md](component-document.md) also plans. Recommendation: do
  it in that plan, on two navigators, after this branch lands.
  - **Owner, 2026-10-06:** yes, master and detail separately. Step 9 leaves this
    plan.

## 10. The address as a document (design in progress)

**Decided (owner, 2026-10-06):** the address is a document, shown in three views
that a switch in the bar changes: the titles, the path, and the path with its
types. The titles and the path take edits; the types are shown, not edited.

The edits that the discussion named, each still to decide:

1. **Jump up:** a press on a name opens that page (exists).
2. **Choose a sibling:** each name lists the other choices at its place, the
   other fields of the document above or the other elements of the collection,
   by their titles, lazily and searchable for a large collection; a choice
   replaces that step.
3. **Keep or cut the rest** after a replaced step: keep it when it still reaches
   a node of the recorded types, cut it otherwise.
4. **Type** in the path view, in place, with the choices of edit 2 as completion;
   Enter opens the path.
5. **Types** are shown in the third view and mark the place where an edit cut
   the address.

**Decided (owner, 2026-10-06): the document is an editable copy beside the
committed address.** The `address` field of `Navigator` stays a `Reference`, and
the back and forward lists and a save keep `Reference`s. Each visit writes the
copy from the address. An edit changes only the copy; Enter, or a choice from the
list of a name, opens it as a visit; Escape writes the copy back from the
address. The copy is view state, and a save does not keep it. The option not
chosen made the document the address itself, so the page followed every key of a
path that a person types.

**Decided (owner, 2026-10-06): the document holds the steps of the kernel, and
the code dispatches on their types.** The steps are `FieldReferenceStep` and
`RangeReferenceStep` values, in a list; each behavior (the name in the titles
view, the text in the path view, the list of choices, the edit) has one method
for each of the two types. Another kind of step has no method, so it can not
enter the address, and a `RangeReferenceStep` enters only in its element form,
`[i]`: a position, a range, a made part and a point name a place in a page, not a
page. The option not chosen gave each kind a step document of its own, a mirror
of the step types of the kernel that a new kind of step would have to repeat
(the owner: "shadowing the reference types which is unbounded").

**Decided (owner, 2026-10-06): the list of choices has a general rule and a
function that a domain answers.** The general rule lists, for a field step, the
other fields of the document above that hold a document (not `selection`,
`mouse_target` or a field of view state), and for an element step the other
elements of the collection by title or number, lazily from the current element,
with no count of the whole collection. A function that a domain answers, such as
`find_navigator_choices(document, step)`, dispatches on the type of the document
and on the two step types: JSON can list its entries by key, and the data frame
its columns by name and its rows from the current row. The options not chosen:
the general rule alone, or a domain alone.

**Decided (owner, 2026-10-06): the list is a popup under the name, with a
type-in field over the list, as the command palette is.** Typing narrows the list
by title; for an element step, a number goes to that element even when it is far,
so a long list needs no count; the function of the domain answers the narrowed
list lazily. The options not chosen: a dropdown with no search, as `WidgetSelect`
shows its options, or no popup, with the choices as completions of a name.

**Decided (owner, 2026-10-06): a choice keeps the rest of the address as far as
it still reaches nodes of the recorded types, and cuts it at the first place
where it does not.** On the page `persons[3].address.city`, the choice of
`persons[4]` at the name of person 3 opens the city of person 4, or the address
of person 4 when it has no city. So a person compares one field across
siblings, one choice at a time; one press on the name of person 4 then shows the
person. The options not chosen: always cut the rest, as file managers and the
breadcrumbs of an IDE do; or keep the rest only when all of it reaches.

**Decided (owner, 2026-10-06): one control in the bar steps through the three
views, and it is a form of `WidgetToggleGroup`.** The control shows the current
view; a press goes to the next view, and Shift+press to the one before; its
tooltip lists the three. No widget of the editor steps through its states (the
sort mark of a data frame column does it with its own gesture bindings), and a
control that steps is the same choice as a toggle group (the options, the
selected one, what each means, what a choice writes), so it is one more field of
`WidgetToggleGroup` that chooses the look and the press: the row, as now, or the
step. A widget of its own would repeat the five fields of the choice. Ctrl+L, which
nothing binds, switches to the path view with the caret at its end, as a browser
does with its address bar. The view is kept in the address document, per
navigator, as view state; a save does not keep it. The options not chosen: three
toggles in a row, a key with no control, and a setting for all navigators.

**Decided (owner, 2026-10-06): the in-between state of a step is a
`ReferenceInsertion`, as `JsonInsertion` is for a JSON value** ("ReferenceInsertion
it is, just like JsonInsertion, no?"). Typing passes through states that are no
step: after `rows[` there is no number, and a `RangeReferenceStep` holds none. A
`ReferenceInsertion` is a document with the typed text, in the list of steps; the
list holds `FieldReferenceStep`, `RangeReferenceStep` and `ReferenceInsertion`,
and the code dispatches on the three. The path view is a syntax view of the
address, and an insertion is drawn by `InsertionToSyntaxLeaf` with a commit and a
completion of the navigator, as the SQL domain builds its own leaf: the
completions are the list of choices of A5, and the insertion commits to a field
step or an element step when its text names one. Escape drops it. An edit inside
a committed step turns the step back into an insertion with its text, because a
kernel step is a value, not a document. The options not chosen: a text of the
whole path beside the steps, and placeholders such as `[1]` with its number
selected.

**Decided (owner, 2026-10-06): the navigator view builds the address part of the
bar itself.** The views need the content (the titles and the types of the nodes,
the fields and the elements above an insertion), which the navigator holds and the
address document does not. The address document stays in the bar as a part, so a
click and the keys reach its steps along the selection. The options not chosen:
the address document holds a reference to the content root, which puts the
content in two places of the tree; or it holds functions that the navigator sets.

The design of the address is complete. The steps to build it:

- [x] **A1. The step form of `WidgetToggleGroup`.** A field that chooses the look
  and the press: the row (the default) or the step. Its view, its reader, and
  its keys (Space and Return step, as a press does). The sort mark of a data
  frame column can use it later, in a change of its own. Done, 2026-10-06: the
  field is `look`, `:row` or `:step`. The step look draws the selected option in
  one raised segment as wide as the widest option; a left press picks the next
  option, Shift+press the one before, around the ends; Return and Space with no
  modifier pick the next. `test_widget_forms()` checks it.
- [x] **A2. The address document.** A document of the navigator slice that holds
  the steps of the address, `FieldReferenceStep` and `RangeReferenceStep`
  values in their element form, and the view: titles, path or types. The
  navigator holds it as view state beside `address`; each visit writes it from
  the address, and a save does not keep it. Done, 2026-10-06:
  `NavigatorAddress(steps, view, edited)` and `ReferenceInsertion(value)` in
  `NavigatorDocument.jl`; the field `address_draft` of `Navigator`. The copy is
  lazy: while `edited` is `false` the views show the steps of the page address
  (`get_navigator_address_steps`), and the first edit writes the steps; a visit
  sets `edited` back to `false` and empties the steps. So a navigator needs no
  copy when it is built. `has_document_duplicate(::NavigatorAddress)` keeps a
  copy for each duplicate tab.
- [x] **A3. The three views and the control.** The views and the control are
  done (2026-10-06); the edit of the path view is done with A4. The control is a
  `WidgetToggleGroup` of the step look before the address, "Names", "Path",
  "Types", whose write of `view` the reader marks as view state. The path view
  shows `.books[2]`, with the dot of a field step in front; the types view
  shows the address with the type of each node, and `✗` before the part that
  an edit cut. The titles view: one name for
  each stop, with the arrow of its list, and a press on a name opens its page,
  as the items of the address do now, which the view replaces. The path view:
  a syntax view of the steps, edited in place; `.` and `[` start a
  `ReferenceInsertion`, a key inside a committed step turns it into one, and an
  insertion commits to a step when its text names one. **Decided (owner,
  2026-10-06):** `make_replace_document_operation` takes a value with no
  `selection` field, such as a kernel step, and selects the value itself, so the
  generic `InsertionToSyntaxLeaf` commits a step; the option not chosen was a leaf
  of the navigator with its own commit, as the SQL domain builds. The types view: the path with the type of each
  node, which takes no edit, and a mark at the place where the address was cut.
  The control of A1 writes the view. Each behavior dispatches on the two step
  types.
- [x] **A4. The keys.** Ctrl+L switches to the path view with the caret at its
  end. Enter opens the path of the steps as a visit; a path that reaches no node
  stays in the document, with a mark at the first step that reaches none.
  Escape writes the document back from the address and returns to the view
  before. Done 2026-10-06, with the edit of A3, in `NavigatorAddressEdits.jl`
  and `NavigatorAddressToSyntax.jl`. What was built and decided on the way:
  - The navigator view prints the address copy with
    `make_navigator_address_projection(navigator)`, a `RecursiveProjection`
    over a template node of the steps, a leaf for a committed step, and
    `InsertionToSyntaxLeaf` for an insertion, and keeps its IO map. The bar holds
    the syntax output at `children[1].children[5]` while an edit is on; the maps
    pass `address_draft.<rest>` through it, and the reader passes an answer of
    the path view, and a key that no part answered (Tab), through it.
  - An insertion holds the text of any number of steps, and Enter reads the
    whole path (my decision; the design said an insertion commits when its text
    names a step). The leaf can replace an insertion with one value only, so a
    split at `.` or `[` while typing would need a reader of its own. A committed
    step is a value and holds no caret: a press selects it, a key on it turns it
    into an insertion with its text and the key, Backspace with its text less
    the last character. Ctrl+L puts an empty insertion after the steps, which
    holds the caret.
  - Enter shows the view before the edit again, as Escape does (my decision):
    Ctrl+L is a switch to type a path, and a person who chose the path view with
    the control keeps it, because `view_before` is then the path view.
  - The copy has two more fields: `view_before`, and `unreached_step`, the step
    that the mark in the bar names.
  - The hint completes the name of a field of the node before the last step;
    Tab takes it. An element has no hint.
  - Facts found: the natural renderer had no row for a syntax document that a
    view puts among its parts, and reflected it as a struct; the syntax slice
    has the row `SyntaxDocument` now. A layout passes a key to the child that
    its own selection names, and the bar and the holder of the page had no
    selection: so a key never reached a page of a navigator since step 4 put the
    page in a vertical layout, a fault on main. The printer wires both now
    (`set_output_path_computations!`), and a test types into a page.
  - The navigator slice has the edges `primitive`, `syntax` and `text` now.
- [x] **A5. The list of choices.** The generic function
  `find_navigator_choices(document, step)`, with the general rule: the fields of
  the document above that hold a document, and the elements of a collection by
  title or number, lazily from the current element. The JSON domain lists its
  entries by key, and the data frame adapter lists its columns by name and its
  rows from the current row. The popup under a name, a window of its own, with a
  type-in field over the list: typing narrows the list by title, and a number
  goes to that element of a collection.
  - [x] The function, done 2026-10-06, in `NavigatorChoices.jl`:
    `find_navigator_choices(document, step; query = "", limit = 50)` gives
    `label => step` pairs. `document` is the node that `step` applies to. A field
    step lists the fields that hold a document, by title or field name, never a
    field of view state. An element step lists the elements from `limit ÷ 2`
    before the current one, up to the first index that reaches no element; words
    search from the first element, up to 1000 elements; a number gives that
    element alone. A range is no page and has no choices.
  - [x] The data frame adapter lists the cells of a row by the names of their
    columns (`find_navigator_choices(::DataFrameViewRow, ::RangeReferenceStep)`).
    Its rows need no method: the general rule gives "row r" from the current row,
    and `rows[r]` past the frame throws, which ends the walk.
  - [ ] JSON: a method can not dispatch on the entries, because the node above
    `[i]` of an object is its `CellVector`, not a JSON type. A JSON entry has no
    title, so the general rule shows `[2]`, as the address does. **Decided
    (owner, 2026-10-06):** a title for `JsonObjectEntry`, its key, is a change of
    its own after the navigator; it names the entry in the address, in the list,
    and in the header of its context menu.
  - [x] The popup. Facts found 2026-10-06 that the design did not know: a
    `:popup` window never takes the keyboard focus, so a type-in field in it gets
    no key; and an answer of a popup goes up through the screen, not through the
    navigator, so it can not write the selection, whose path starts at the root.
    The context menu solves the second with its `source` path and a lift through
    the readers (`EditMenuPartOperation`). **Decided (owner, 2026-10-06): the
    list is the context menu of the name.** The arrow of a name answers
    `OpenContextMenuOperation` with the list as its one menu and the navigator as
    its source; each row is a menu item that holds the choice operation, which the
    menu window lifts through the reader of the navigator. While a menu window is
    open, the context menu window gives a key of the window under it first to the
    content of the menu; a key that the menu does not answer goes on as before.
    So other menus can take keys later. The options not chosen: a window of the
    navigator that takes the focus, with a new operation that carries the path of
    the navigator and a second lift; and the field in the bar, the step itself as
    an insertion, with a list that takes no key.
    Done 2026-10-06. An arrow (`:chevron_right`) stands before each name but the
    root, in place of the "›" mark; a press on it opens a `NavigatorChoiceList`
    at the point of the press. `NavigatorChoiceListToWidget` draws a line "Find:
    …" over a `WidgetMenu` of the choices; the row of Return shows a chevron, the
    current step a check. The list reads a key before its widgets, so the widget
    stage takes no arrow key from it; it takes the typed text, Backspace, Up,
    Down and Return, swallows any other key with no modifier but Shift, and
    leaves a key with Ctrl, Alt or Meta to the window under it. Facts found on
    the way: a generic projection dropped `CloseWindowOperation`, and with it the
    whole compound of a press on a menu item, because the operation was not
    self-contained; it is now (`is_self_contained_operation`), as
    `ChangeScreenPointerShapeOperation` is, so a menu inside the view of a
    document closes too. A key that closes the menu window, such as Escape,
    must make the context menu window forget its layers at once, because the
    key no longer reaches the step that forgets them. The list holds closures
    that capture the navigator, so it is `is_walk_opaque`. The navigator slice
    has the edge `screen` now.
- [x] **A6. A choice.** The step is replaced, and the rest of the address is kept
  as far as it reaches nodes of the recorded types, and cut at the first that it
  does not. The result opens as a visit. Done 2026-10-06:
  `make_navigator_choice_operation(navigator, index, step)`. The steps up to the
  choice take the types that they have now, and the rest keeps the types that
  the address records, also at the node of the choice: so a choice of a node of
  another type cuts the rest right after it. The address keeps the steps that
  reach no node, and the types view marks them with `✗`. A visit now selects the
  part of its address that reaches (`_find_visit_selection`), because a stored
  address can hold steps that reach no node.
- [x] **A7. Tests and documents.** The platform tests with the shelf, the data
  frame case (the list of rows from the current row, the choice of a row that
  keeps a column), and the design document and the keyboard guide. Done
  2026-10-06: `test_navigator_choices()`, `test_navigator_address()`, the data
  frame case in `test_data_frame_row_page()`, navigator.md, the keyboard guide,
  context-menu.md, screen.md and syntax.md. The catalog has atoms for
  `Navigator`, `NavigatorAddress` and `NavigatorChoiceList`; `DataFrameViewRow`
  is in `_NO_ATOM` beside `DataFrameView`, because an adapter has no atoms.

D7 (named targets, step 6) can use the same function for the names that a domain
gives to a target.

## 11. Risks

- **One document in two places.** A navigator that opens a node of a file that
  is also open in a file tab holds the same document. Both views then write one
  selection field. Two views of one document have this problem now; a test must
  show what the person sees.
- **A search for an object in a large content.** The search is bounded. When it
  does not find the object, the object becomes a new content with no parent.
- **The scroll on Back.** The page prints again, so a table loses its scroll
  position. The selection that comes back must bring the row into view. A cache
  of the IO maps of the recent visits can keep the scroll later.
- **A page that an edit removes.** §4.2 shows the longest valid prefix.
- **The keys.** Each proposed chord must be free in every domain and in the
  pane, or the page takes it first and the navigator never sees it.
