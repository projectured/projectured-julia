# Navigator

> **Kind:** design · **Status:** current · **Stands on:** [concepts.md](../../../design/concepts.md), [reference.md](../../kernel/reference.md), [selection.md](../../kernel/selection.md), [pane.md](../pane/pane.md), [context-menu.md](../widget/context-menu.md)

The navigator slice of `ProjecturedPlatform` shows one part of a document at a time, as a tab of a browser shows one page of a site, with Back, Forward, Parent, an address and links. This document says how the page, the visits and the open of a page work, how a link reaches the navigator around it, and why the navigator has no reference to the domain of its pages.

## How it works

### The document

`Navigator(content[, address])` is a document with five fields:

| Field | What it holds |
| --- | --- |
| `content` | the root that the pages are parts of: a document of any domain |
| `address` | the path of the page from `content`, a `Reference`; the empty path shows the whole content |
| `back` | the visits before the current one, the newest last |
| `forward` | the visits after the current one, the nearest last |
| `address_draft` | the address as the bar shows it and a person edits it, a `NavigatorAddress`: view state, which a save does not keep |

A `NavigatorVisit(content, address, selection)` is one page that a person saw: the content, the address of the page, and the selection in the page when the person left it, as a path from the content. A visit is a value and not a document. So a visit can hold another content, and the back list goes from one document to another, as a tab of a browser goes from one site to another.

The address is state of the document, not of the projection. A program and the assistant read it as any field, and no other projection reads it. `get_edited_field(::Navigator)` is `:content`, so `get_edited_document` reaches the content through a navigator.

### The page and the address

`get_navigator_page(navigator)` is the node at the address. An address records the types of its nodes when a navigator opens it. When an edit removes the page, or puts another kind of part on its path, `get_navigator_page_address` answers the longest prefix that still reaches a node of the recorded type (`get_valid_reference_prefix`). The navigator then shows that page, and Back and Forward still work.

### The visits

Every move to another page is one `CompoundOperation`:

1. a `ReplaceViewStateOperation` around the writes of `address`, `back`, `forward`, and `content` when it changes;
2. a `ReplaceSelectionOperation` with a path from the navigator, into the new page.

So an undo records no visit, and an edit on a page is an edit that undo takes back while the navigator stays on the page. The lists are written as new vectors.

| Builder | What it does |
| --- | --- |
| `make_navigator_open_operation(navigator, address; selection)` | opens the page at `address` as a new visit: the current visit goes on the back list, and the forward list is cleared; `nothing` for the page that the navigator shows |
| `make_navigator_open_operation(navigator, document, reference)` | opens the node at `reference` from `document`; see [The open of a page](#the-open-of-a-page) |
| `make_navigator_back_operation(navigator)` | returns to the newest visit of the back list, with the selection that the visit holds |
| `make_navigator_forward_operation(navigator)` | the mirror of Back |
| `make_navigator_parent_operation(navigator)` | opens the page that holds the page as a new visit, with the page that the person leaves selected |

`find_navigator_parent_address` gives the nearest document above the page at which a navigator stops, or the root of the content, so the parent of a chapter in the vector `chapters` of a book is the book. Parent answers `nothing` at the root of the content. `find_navigator_selected_address` gives the innermost document on the selection, below the page, at which a navigator stops.

`is_navigator_stop(document)` says where a navigator stops when it goes up, names the items of the address, and opens the selected part or the part under the pointer. It is `true` for a document, and `false` for a collection that `get_parent` looks past and for a value that is no document. A domain answers `false` for a container that holds the parts of the document around it: the data frame adapter does for `DataFrameViewRows`, so Parent goes from a row to the table. A navigator can still show such a container as a page at its own address.

A visit puts back the selection that it holds when that selection still reaches a node inside its page, and selects the page itself otherwise. Parent and a press on a name of the address select the page that the person leaves, as a file manager selects the folder that a person comes from.

### The view

`NavigatorToWidget` draws a navigator as a `GridLayout` of one column:

```
children[1]                       the bar: Back, Forward, Parent and the items of the address
children[2].children[1].<rest>    the page; <rest> is a path in the page
```

The printer prints no child but the address copy in the path view. The page document itself stands in a `VerticalLayout` of one child, whose list of children is computed from the address, and the layout stage after the view prints it through the recursion. A vertical layout prints its children again when its list changes; a grid prints its children once, when it prints. So the page is drawn with the row of the renderer for its own type, and a domain gives its page a view of its own only where the page must look different from the part in the view of its parent. The renderer row is `ChainingProjection(NavigatorToWidget, GridLayoutToGraphicsCanvas())`.

The maps put `content` and the address before a path in the page, and take them off: `content.<address>.<rest>` and `children[2].children[1].<rest>`. A layout passes a key to the child that its own selection names, so the printer wires the bar and the holder of the page to carry the part of the selection of the grid below them; the page is a document of the content and holds its own. A path in the content that is not on the page has no image, and a path into the bar maps back to nothing. The forward map keeps the types of the path inside the page and gives the steps of the grid and of the layout their types, because a tab splices the image into its own path and needs a type on every node.

**The bar.** Back, Forward and Parent are `WidgetToolbarItem`s with the icons `:arrow_left`, `:arrow_right` and `:arrow_up`. A button is off when its list is empty, or when the page has no parent. Then a control shows the address in one of three views, and the address follows it.

**The address.** `NavigatorAddress(steps, view, edited)` holds the address as the bar shows it: an editable copy beside the committed `address`. Its steps are `FieldReferenceStep`s and element `RangeReferenceStep`s, and `ReferenceInsertion`s while a person types a step. While `edited` is `false`, the copy is the address, and the views show the steps of the page address (`get_navigator_address_steps`). Each visit makes `edited` `false` again. The control is a `WidgetToggleGroup` of the step look, "Names", "Path" and "Types", which writes `view`; a press shows the next view, and Shift+press the one before. The reader marks a write of the copy as view state.

- **Names** (`:titles`): one item for each document from the content to the page. An item shows the title of its document, or the steps that reach it from the item before, or at the root the name of its type. Its tooltip is its path from the content. A press on an item opens its page. The page itself is the last item, a plain label. Before each item but the root stands an arrow (`:chevron_right`), which opens the list of the choices at the place of the item.
- **Path** (`:path`): the path of the steps, such as `.books[2]`. A press on it, or Ctrl+L, starts an edit; see [The edit of the path](#the-edit-of-the-path).
- **Types** (`:types`): the path with the type of each node. When an edit or a choice cut the address, `✗` stands before the steps that reach no node.

### The edit of the path

The path view is edited in place, as the address bar of a browser is. Ctrl+L (`make_navigator_address_edit_operation`) writes the steps of the page into the address copy, with an empty `ReferenceInsertion` after them that holds the caret, shows the path view, and keeps the view before in `view_before`.

While an edit is on, the bar holds the syntax of the address copy: the navigator view prints the copy with a projection of its own, `make_navigator_address_projection(navigator)`, and keeps its IO map. That projection holds the navigator, because a hint needs the content, which the copy does not hold. The view maps a path in the copy, `address_draft.<rest>`, to `children[1].children[5].<rest>` in the bar and back, and its reader passes an answer of the path view, and a key that no part of it answered, such as Tab, through that projection. A committed step, `.name` or `[i]`, is a value and holds no caret: a press in it selects the step, and a key on it turns it into an insertion with its text and the key, Backspace with its text less the last character. An insertion holds the text of any number of steps; its hint completes the name of a field of the node before it, and Tab takes the hint.

- **Enter** (`make_navigator_address_commit_operation`) reads the text of each insertion as steps. A path that reaches opens as a visit, and the view before the edit shows again. A path that does not reach to its end stays in the copy, with its insertions as steps, the selection on the first step that reaches no node, and a mark in the bar that names it (`unreached_step`). A text that is no path stays, and Enter does nothing.
- **Escape** (`make_navigator_address_reset_operation`) makes the copy the address again, shows the view before, and selects the page.

The reader of the view takes Return and Escape with no modifier while the selection is in the copy (`is_navigator_address_selected`), whatever the path view answered.

### The choices of a name

`find_navigator_choices(document, step; query, limit)` gives the choices at a step of an address, as `label => step` pairs, where `document` is the node that the step applies to:

- for a field step, the fields of `document` that hold a document, by title or by field name, never a field of view state;
- for an element step, the elements from `limit ÷ 2` before the current one, up to the first index that reaches no element, so no collection is counted to its end. Words in `query` search the elements from the first, up to 1000 of them; a number gives that element alone.

A domain adds a method for its own type of `document`. The data frame adapter names the cells of a row by their columns (`find_navigator_choices(::DataFrameViewRow, ::RangeReferenceStep)`); its rows need no method.

`make_navigator_choice_operation(navigator, index, step)` opens the page with `step` in place of step `index` of the page address, as a new visit. The steps after it keep the types that the address records, also at the node of the choice, and the page is the longest prefix that still reaches nodes of those types. So on the page `persons[3].address.city`, the choice of `persons[4]` opens the city of person 4, or the address of person 4 when it has no city, and a choice of a node of another type cuts the rest right after it. The address keeps the steps that reach no node, and the types view marks them.

A press on the arrow before an item answers `OpenContextMenuOperation` with one menu, a `NavigatorChoiceList`, and the navigator as its source, at the point of the press. The context menu window shows the list in a window of its own: a line of the typed text over a menu of the choices that it narrows to. The row that Return chooses shows a chevron, and the current step a check. Each row is a `WidgetMenuItem` that holds the choice operation, so a press on a row answers `EditMenuPartOperation`, and the context menu window lifts it to the navigator through the readers of the content. The window is a popup, which never takes the focus; while it is open, the context menu window gives a key of the window under it to the list first. The list takes the typed text, Backspace, Up, Down and Return, and does nothing for any other key with no modifier but Shift, so a letter does not edit the page; a key with Ctrl, Alt or Meta goes on to the window under it. The list is view state of the popup, and a walk of the documents does not go into it (`is_walk_opaque`).

**The reader.** The generic bridge reads first: it maps a path of the page back, and it reads the `@gestures` table of the navigator for a key that the page does not answer. Then the reader of the view takes three kinds of answer:

- a press on a button or on an item of the address answers `InvokeActionOperation`, which goes up unchanged, and becomes the operation of the button or the open of the page of the item;
- an `OpenPageOperation` from the page becomes a visit;
- an answer of the page that collects, such as the menu of a part, gets the answer of the table of the navigator joined after it (`read_gesture_outward`), and the collection of the gesture help gets the keys of the navigator (`merge_collected_intents`).

The actions of the buttons have no callback: the press always comes back through the reader of the view, and a callback at the editor can not root the selection, whose path starts at the navigator.

### Keys and the menu of a part

Alt and an arrow walk the structure of a document, so the navigator takes Ctrl.

| Gesture | Effect |
| --- | --- |
| `Ctrl+[` | go back |
| `Ctrl+]` | go forward |
| `Ctrl+Up` | go to the parent page |
| `Ctrl+Return` | open the selected part as a page |
| `Ctrl+L` | edit the path of the address |

Each key is an `override` rule: it takes its chord also after the page answered it, as Back in a browser works on every page. The reader gives a key that the page answered to the table of the navigator as a claimed key, which only an `override` rule takes. A table of rows answers Return with any modifier, for one.
| right click on a part of the page | the menu of the part: "Open as a page" and "Open in a new tab" |
| a press on the arrow before a name of the address | the list of the choices at the place of the name |
| the back and the forward side button of the mouse | go back, go forward |

The menu belongs to the innermost document under the pointer, below the page, which the navigator reads from its own `mouse_target`. A command with no pointer reads the selection. The source of the menu is the path of that part, with its types, so the context menu window lifts an item from the part through the reader of the navigator. Each item holds an `OpenPageOperation` rooted at the content, so it opens the same page also from the outer layer of a part that has a menu of its own (F2).

### The open of a page

A link is the part of a domain or of a view that answers `OpenPageOperation(document, reference[, place])` to a press:

- With `document === nothing`, `reference` is a path from the part that answers. Every reader on the way up maps it, as any path. This form opens the part itself or a part under it.
- With a `document`, the operation carries its own root and goes up unchanged. This form opens any object.
- With a `target`, the path form names the link, and `target` is the text of what it names, as its domain writes it: `#install`, `guide.md`, an rst name.
- `place` is `:here`, the default, or `:new_tab`, as Ctrl+click does in a browser.

The operation registers with `operation_reference`, `retarget_operation` and `is_self_contained_operation`, so no reader of another slice names it. The nearest navigator around the part takes an open with `:here`. A path under its content becomes the address. An object that is the content, or a document on the address, becomes the path from the content. Any other object becomes the content of a new visit, with no parent: the navigator does not search its content, because a search walks every value of the content. With `:new_tab`, the navigator passes up an open rooted at its content.

A target is resolved by the domain of the content: `find_navigator_target(content, target)` answers a `Reference` to a part, the absolute path of a file, or `nothing`. A part opens as a visit, or in a new tab; a file opens in a new tab with a navigator around it (`OpenFileOperation` with `file_wrap`), with a history around the navigator when the editor has settings, so the history records the edits of every page; a target that names nothing is answered and does nothing. A navigator that an open makes from a file tab keeps the file document as its content, so a relative link is read against the name of the file. The markdown and the rst domains answer the function ([markdown.md](../../domain/markdown/markdown.md), [rst.md](../../domain/rst/rst.md)).

An open that no navigator takes reaches the editor. Its evaluation posts the opening of a new tab with a navigator on the page (`post_pane_operation!`), as the open of a file does. For the path form, the content of that navigator is the document of the tab that holds the part, past the layers that `get_edited_field` names, such as an undo and a file, so Parent reaches the rest of it.

### Tabs and files

- **A tab** keeps the name that it got when it opened, as every tab does. Its tooltip reads the address of the page (`make_pane_tab_title(::Navigator, name)`).
- **A duplicate** of a navigator tab has its own address and its own visits, and shares the content (`has_document_duplicate(::Navigator)`).
- **A save** keeps the content and the address, as the text of a path, such as `books[2]`, and no visit (`pred_arguments`, `make_pred_document`). `print_path_text` and `parse_path_text` of the serialization slice write and read that text.

## How it fits

The slice uses the collection, layout, natural, pane, primitive, projection, screen, serialization, style, syntax, text and widget slices of the platform, and the kernel. It uses the pane slice for the tab that an open with no navigator posts, the screen slice for the close of the window of the list of choices, and the syntax, text and primitive slices for the path view. The syntax slice draws a syntax document that a view puts among its parts, such as the path view in the bar, from the stage from syntax to text. It names no domain, and no domain names it except to answer `OpenPageOperation`.

A domain gives a part a page of its own where the part must look different as a page. The data frame adapter draws a row of a frame, `rows[r]` of a `DataFrameView`, as a form of the name and the value of each column (`DataFrameViewRowToWidget`). The menu of a row opens it, and a double click on the number of a row opens it: the view of the frame maps that double click, because the view owns the numbers.

A navigator is a document like any other, so it nests: a tab holds it, a page can hold another navigator, and the nearest navigator around a link takes the open.

## Design decisions

- **The address is in the data.** The owner chose it on 2026-10-06. A projection that holds its state, as `FocusingProjection` holds its part, is not saved and the assistant can not read it. `FocusingProjection` stays for a focus that a program sets.
- **The address is not the selection.** A pane group shows the tab that its selection names, but the caret of a page moves inside the page, and the page must not follow it.
- **A link answers an operation, and the nearest navigator takes it.** The owner accepted `OpenPageOperation` on 2026-10-06. It goes up as an answer to a press, on the path that every press takes, as `StartDragOperation` does to the drag wrapper. No event and no payload of the reader is new.
- **Parent is a new visit.** Back then returns to the child, as in a file manager.
- **The view of a page is the view of its type.** The recursion picks it, so a domain adds a page view once and every navigator uses it.
- **A trait says where a navigator stops.** The owner chose a trait of the navigator on 2026-10-06, over `is_element_collection`, which the search, the view on demand, the file cut and the sync iterate; over a frame of ten million rows each would make ten million row documents.
- **The address is a document beside the committed address.** The owner chose it on 2026-10-06. An edit changes only the copy, and Enter or a choice opens it as a visit, so the page does not follow each key of a path that a person types. The copy holds the steps of the kernel, and the code dispatches on their types; a document for each kind of step would repeat the step types of the kernel.
- **A choice keeps the rest of the address where it still reaches.** The owner chose it on 2026-10-06, over a cut of the rest, as file managers do. So a person compares one part across siblings, one choice at a time.
- **The list of choices is the context menu of a name.** The owner chose it on 2026-10-06. A popup takes no focus and its answer passes no navigator, and the context menu already carries the path of its part up and lifts the edit of an item to it. The options not chosen: a window of the navigator that takes the focus, with a new operation and a second lift; and the field in the bar, with a list that takes no key.
- **No search for an object.** An open of an object that is not on the address makes the object a new content. A search over a frame of ten million rows reads every value.

The plan with the alternatives is [plan/pending/a-navigator-with-back-forward-parent-and-links.md](../../../../plan/pending/a-navigator-with-back-forward-parent-and-links.md).

## Usage

```julia
using ProjecturedPlatform
navigator = Navigator(document)                       # the whole document is the page
open_pane!(navigator)                                 # a tab with a navigator
evaluate_operation(editor, make_navigator_open_operation(navigator, @reference(document, entries[2])))
```

A part that opens a page answers `OpenPageOperation(nothing, EmptyReference())` to its own press, and `OpenPageOperation(nothing, EmptyReference(), :new_tab)` to Ctrl+press.

- Tests: `test_navigator()` in `ProjecturedPlatformTest`: `test_navigator_visits()`, `test_navigator_choices()`, `test_navigator_to_widget()`, `test_open_page_operation()`, `test_navigator_gestures()`, `test_navigator_document()` and `test_navigator_address()`. The data frame case is `test_data_frame_row_page()` in `ProjecturedDataFramesTest`.

## Limits

- The navigator puts no scroll pane around its page: a part scrolls where it is made. A page whose view has no scroll pane, such as a JSON document, is cut at the bottom of the navigator.

- A JSON part has no title, so the address of a JSON page names its steps, for example `entries[2]` and `value`, and the list of choices of an entry names it `[2]`.
- The list of choices opens at the point of the press, and no key opens it.
- The hint of an insertion completes the name of a field, not an element.
- The view on demand, which draws a document that has no view of its own, does not pass an operation with a fixed place (`read_rooted_operation`) into itself. A verb of the assistant at a place inside such a page reaches no part.
- A history inside the content of a navigator does not record an edit on a page below the root ([undo.md](../undo/undo.md)).
