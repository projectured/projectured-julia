# A navigator shows one page of any document, with back, forward, parent, an address and links

> **Kind:** plan · **Status:** pending, 2026-10-06. The owner decided D1 to D9
> on 2026-10-06 (§8); D7 waits for step 6. No step has started. ·
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
- [ ] **5. A table and its detail page.** The page view of a data frame row, a
  form of its columns. The "Open" item of a row and a press on a row header.
  The case of the owner: the table, a row, Back to the table with the row
  selected. An example, a test, and a check in a live window.
- [ ] **6. Links in the data.** Markdown and rst links that a press follows,
  drawn as links. A file reference. A named target after D7.
- [ ] **7. Panes and files.** The tab title follows the page. A duplicate copies
  the lists. A save keeps the address only (D6).
- [ ] **8. A typed address.** Field and index steps, read as
  `_evaluate_path_text` reads them.
- [ ] **9. Master and detail.** `ComponentToWidget` on two navigators.
- [ ] **10. The side buttons of the mouse** (D5): `MouseButtons`, the SDL
  backend and the web backend.
- [ ] **11. Documentation.** A design document for the slice, the keys in
  [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md),
  and the example in
  [examples-tour.md](../../documentation/guide/examples-tour.md).
  - [x] The design document
    [navigator.md](../../documentation/package/platform/navigator/navigator.md),
    its row in the package index, and the keys in the keyboard guide, for steps
    1 to 4 (2026-10-06). Each later step updates the document.
  - [ ] The example in the examples tour, after step 5.

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
- **D7. A named target. Decided by the owner, 2026-10-06: open until step 6.**
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

## 9. Risks

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
