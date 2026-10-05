# Pane

> **Kind:** design · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [reference.md](../../kernel/reference.md), [selection.md](../../kernel/selection.md)

The pane slice of `ProjecturedPlatform` holds the pane tree: tab groups, the splits between them, and the edits that rearrange them. It draws the tree with the split panes and tabbed panes of the widget slice, and it gives a program, such as a language model, a set of verbs over the tree. This document says how the focus, the edits, the drags and the verbs work, and how the whole editor saves to one file.

## How it works

### The documents

A fresh layout is one empty group. A person builds the rest with the keyboard and the mouse.

| Type | What it holds |
| --- | --- |
| `PaneTab(title, content[, icon])` | a `PaneTabTitle` and a content document of any domain; `PaneTab("name", doc)` makes a title with that name, and `icon` gives the title an icon |
| `PaneTabTitle(name; icon, icon_role, badges, tooltip)` | the name of a tab as a `PrimitiveString`, and an icon, the color role of the icon, a list of `WidgetBadge`s and a tooltip; each of the four is a value, a cell or a function of no arguments |
| `PaneGroup(tabs)` | a tab group, which can be empty: `PaneGroup(PaneTab[])` |
| `PaneSplit(orientation, elements; weights)` | two or more groups or splits, and one weight for each; an empty `weights` means equal weights |
| `PaneTree(root, drag)` | the whole layout, and `drag`, the state of a tab drag |

A `:vertical` split has a vertical divider, so its children are side by side. A `:horizontal` split stacks them. This is the meaning of the two words in Vim. The `orientation` of `WidgetSplitPane` names the axis that the children follow, which is the opposite word. `get_pane_split_axis` is the one translation, and `PaneToWidget` is its only caller.

### Focus is the selection

No node has a focus field or an active-tab field. The selection of the tree names the focused tab, for example `root.elements[2].tabs[3]`, or an empty group, `root.elements[2]`. The tab that a group shows is the tab that the `selection` of the group names. So every focus move and every tab switch is one `ReplaceSelectionOperation`. The part of the selection after `content` of the focused tab is the place in the document of that tab; `find_pane_content_selection(tree)` gives it, or `nothing` when the selection is not inside the document of a tab, and the status bar of the shell slice shows it.

`has_dormant_selection` is `true` for `PaneGroup`, `PaneTab` and `PaneSplit`. When the focus leaves a node, the node keeps its selection as a dormant one: stored and drawn, but not used for routing. So a group that loses the focus still shows its tab, a tab keeps its caret, and a nested split keeps the side that had the focus.

A new tab takes the focus. The focus goes on the content as a whole when the content is the empty placeholder, so a paste fills it. It goes along the content's own selection when the content holds one, such as the caret in the first form of a new evaluator, so the root holds the selection that the document had and a key or a paste reaches that place with no click. Otherwise it goes on the tab.

### The edits are generic operations

`PaneSurgery.jl` declares no operation type. Each builder returns a generic operation with `document` at `nothing`, so the reference re-roots as the operation goes up the chain. That is what lets a pane tree sit inside another document.

| Builder | Generic form |
| --- | --- |
| `make_pane_open_tab_operation` | `make_insert_elements_operation` and the focus move |
| `make_pane_duplicate_tab_operation` | the open of the duplicate, after the original |
| `make_pane_close_tab_operation` | `make_delete_elements_operation`, or a collapse write, and the focus move |
| `make_pane_split_operation` | `ReplaceReferencedValueOperation` of a new `PaneSplit` at the slot of the group |
| `make_pane_move_tab_operation` | `MoveRangeOperation` and the focus move |
| `make_pane_drop_split_operation` | the split write, the move, and the focus move |
| `make_pane_resize_operation` | one write of the weights |
| `make_pane_focus_operation` | `ReplaceSelectionOperation` |
| `make_pane_retarget_title_operation` | an edit of the name in the title, re-rooted |

Two rules hold for all of them:

- **The surgery reuses node objects.** A split puts the existing group into the new split, and a collapse writes the existing sibling into the slot of the parent. A rebuilt subtree drops the IO maps below it, and every tab prints again and loses its scroll position and its caret.
- **A path carries its node types as it is built.** Each `(node, step)` pair records the document that its step starts from. So a builder can name a slot that the edit is about to make, such as a fresh tab. `annotate_reference_types` can not do this, because it reads the tree as it is now.

`MoveRangeOperation` of the dragging slice moves a tab between two `CellVector` fields. It moves the cell, so the tab keeps its identity and its IO map. This slice does not use `DraggingProjection`; see [dragging.md](../dragging/dragging.md).

### Geometry

`PaneGeometry.jl` gives each group a rectangle in the unit square. One walk of the tree divides the square by the normalized weights. No font, no measure and no backend takes part, so the functions are pure:

- `get_pane_rectangles(tree)`, `get_pane_rectangle(tree, group)` and `get_pane_group_at_point(tree, x, y)`;
- `get_pane_neighbour_group(tree, group, direction)`: a candidate is wholly past the edge and overlaps on the other axis. The nearest wins, then the one that overlaps most;
- `get_pane_next_group(tree, group; backward)`: the depth-first order, which wraps at both ends;
- `get_pane_drop_zone(tree, x, y; strip, band)`: the group under a point, and `:strip`, `:center` or one of four edge bands.

The rectangles ignore the pixels of a border and a divider. They are exact enough to find a direction, a drop zone, or the pane of a click.

### The projection

`PaneToWidget()` is the first stage of a chain of two:

```julia
ChainingProjection(RecursiveProjection(PaneToWidget(; new_tab = default_new_pane_tab)), renderer)
```

A tab content passes through the first stage unchanged, so `renderer` draws each content. `PaneTreeToWidget` prints the tree as a `WidgetComposite`: slot 1 holds the layout and slot 2 holds the drop indicator. `PaneSplitToWidgetSplitPane` wraps each element in a `LayoutConstraint` whose weight is the normalized weight of the element. When the parent gives an available extent, each slot also has a preferred extent of 0, so the allocator divides the extent by the weights only. `PaneGroupToWidgetTabbedPane` makes a `WidgetTabbedPane` with `closable`, `new_tab`, `draggable` and `duplicable` set, and sets the `duplicable` flag of each page from `has_document_duplicate` of the content.

Every edit reaches the screen through the IO maps that stand, with no new print of the tree. `test_pane_construct` checks this: after each structural edit, it compares the standing render with a fresh print of the same tree. A test that checks only the tree passes while the screen is stale.

**The widget layer reports; the pane makes the edit.** The tab strip returns `CloseTabOperation`, `OpenTabOperation`, `DragTabOperation` and `DuplicateTabOperation`, which say only that a button was pressed. The reader of `PaneTreeToWidget` has one method for each. It finds the pane node that printed the widget with `_pane_node_for` and calls a surgery builder. `_pane_node_for` looks at the children before the node, because a tree prints as its root and shares the widget of the root. A press that no widget answers focuses the group under the pointer, because most of a pane is empty space beside its content.

**The drag of a tab.** `DragTabOperation` keeps the tab and the point of the press in `PaneTree.drag`, `(group, index, target, zone, origin, started)`, with `started` false. A move of the pointer 5 pixels from the press starts the drag: the tree answers `StartDragOperation`, so the dragtracking slice keeps the path of the tree and sends it `DragMove`, `DragEnd` and `DragCancel` from then on, wherever the pointer is ([dragtracking.md](../dragtracking/dragtracking.md)). A release before that move is a plain click, and selects the tab as any other press does. `DragMove` sets `target` and `zone` with `find_drop_zone(tree, dragged, point)`, only when either changes; `DragEnd` drops the tab there and clears `drag`; `DragCancel` clears `drag` with no drop. The pointer is resolved against the unit square, with a tab strip of 32 pixels. A drop on the strip or the middle moves the tab to the end of the group. A drop on an edge band splits the group.

**Every drop lands.** The tab that moves may be the last tab of its group. That group then goes, and its parent split goes too when one element is left. So the drop is two structural writes, and each path must be named against the tree that the other write leaves. `make_pane_drop_split_operation` names them by the shape of the parent of the source:

| The parent of the source | The writes |
| --- | --- |
| none: the source keeps a tab | the split, at the slot of the target |
| holds the source and the target only | the new split replaces the parent |
| holds the source and one other element | the split first, then the sibling takes the slot of the parent |
| holds three or more | the split first, then the source and its weight are removed |

**The drop indicator** is one `WidgetHighlight` in slot 2 of the composite. Its position, size and `visible` are cells that read `drag` and the geometry, so the widget tree has the same shape during a drag. The composite sets `child_width` and `child_height` to `Fill`, so it gives each child its whole extent, and the panes divide the whole window. The indicator authors its size, which wins over the fill. A `StackLayout` withholds the available size from its children, so the split panes shrink to their own size.

**A splitter drag, twice.** `WidgetSplitPane` anchors a drag on its `sizes` and fills them only when they are empty. The pane answers each `ResizeSplitPaneOperation` with a write of the weights and never writes `sizes`. So `sizes` still holds the extents of the first grab. The reader answers `StartSplitterDragOperation` of a split of the tree with a `CompoundOperation` that clears `sizes` first, and the widget measures again. A split that a tab content made is not a split of the tree, and it keeps its own `sizes`. The reader writes no weights equal to the weights of the split, so a move to the point of the last move writes no cell. The widget marks the three operations of a drag as view state. The reader reads the operation inside the mark, and its answer keeps the mark, so a history records no part of a drag.

### Keyboard and mouse

The `@gestures PaneTree` table is in `PaneGestures.jl`:

| Gesture | Effect |
| --- | --- |
| `Ctrl+T` | open a new tab in the focused group, and select its empty content |
| `Ctrl+W` | close the focused tab |
| `Ctrl+Shift+D` | duplicate the focused tab |
| `Ctrl+\` and `Ctrl+Shift+\` | split vertically, the new pane on the right; split horizontally, the new pane below |
| `Ctrl+Alt+Left/Right/Up/Down` | move the focus to the group in that direction |
| `Ctrl+Tab` and `Ctrl+Shift+Tab` | focus the next or the previous group |
| `Ctrl+PageDown` and `Ctrl+PageUp` | focus the next or the previous tab |
| `Alt+Left` and `Alt+Right` | from a whole tab, select the tab beside it |
| `Alt+Down` | from a whole tab, select its content as a whole |
| `F2` and `Escape` | put the caret in the tab name, and take it out |

Every chord has a modifier, because a plain key belongs to the content of the focused tab. Plain Alt and an arrow walk the structure of a document, so the moves between groups take Ctrl+Alt. Ctrl+Tab is an `override`, because the widget split pane answers every Tab with its own focus traversal.

With the mouse, a click on a tab focuses it. The `x` of a tab closes it, and the `+` above the `x` duplicates it. The button after the last tab opens a tab. A drag of a divider writes the weights of that split, at any depth. A drag of a tab onto a strip or a middle moves it, and onto an edge band splits the group.

### Selecting inside a page

A click on the content of a tab gives the press to the page, and the tabbed pane adds the tab to the path that comes back. So the path runs `tabs[i].content` and then into the domain of the content.

An Alt+click inside a page selects the object under the pointer. [widget.md](../widget/widget.md#selecting-a-whole-widget) describes the rule. When the content projection maps the object back to a whole document, the selection is that document. When it maps back a caret or a place that it introduced, `_select_page_content` selects the innermost document on that path. When it maps back nothing, the selection is the whole content of the tab. So the content of any tab can be selected, whatever its projection maps.

The pane answers the Alt arrows at a tab itself. The generic walk steps from the content of a tab to its title, and a title is not an object of the content. A whole tab is the top of the walk, and the root of a content has no sibling.

### A new tab is filled by a paste

A new tab holds `DocumentNothing`, and Ctrl+T, the new-tab button and a split select it as a whole. A paste writes where the selection is, so Ctrl+V fills the tab. A new tab has an empty name, and `get_pane_tab_title_string` then uses the `get_document_title` of the content, or "untitled".

A paste never replaces a pane node, and a pane node is never pasted: `accepts_pasted_replacement` is `false` for them. `find_clipboard_document` of a `PaneTab` is its content, so Ctrl+C on a focused tab copies what the tab shows. See [clipboard.md](../clipboard/clipboard.md).

### Renaming is not a mode

The name in a tab title is a text document. A caret in the name is the edit state, so F2 and Escape only move the selection. The table gives each typed key, Backspace and Delete to `read_gesture` of the name, and the `@gestures` table of `PrimitiveString` makes the edit. `make_pane_retarget_title_operation` roots the answer at the tree, at `get_pane_tab_name_path`. The package has no code that edits text and no rename operation.

A rename edits the name only. The icon, its role, the badges and the tooltip of the title stay, and a title whose parts are cells or functions follows the state they read with no write. The group draws each tab as a `WidgetTabLabel` whose icon, badges and tooltip read the title, so a change of them redraws the strip and builds no page again. A caret in the name, `tabs[i].title.name.value{k}`, maps to `selector_element_pairs[i].selector.text{k}` of the strip, and back.

A file of a layout writes the name and the values that the four parts hold at the save. It builds a tab from a `PaneTabTitle`, or from a name with an `icon` beside it.

### A duplicate is a pane of its own

A duplicate of a tab is a second pane that the person controls alone. `make_document_duplicate` of the content makes it, by three rules:

1. The duplicate owns what the person controls in the pane: the form fields, a transcript, the title of a plot.
2. The duplicate shares what the pane reads: the project, the result files, the model backend.
3. The duplicate does not copy a process. A run or a stream stays with the original, and the duplicate starts idle.

A tab whose content has no duplicate shows no `+`, and Ctrl+Shift+D on it logs the reason with `@warn`. The duplicate is the next tab of the group and takes the focus. Its name gets a number: "Plot" becomes "Plot (2)", and "Plot (2)" becomes "Plot (3)". It keeps the icon that the title shows, and it has no badges and no tooltip, because those say what the original content does. [document.md](../../kernel/document.md#the-duplicate) describes the copy.

A duplicate is not a mirror. Each node stores its own `selection`, so two panes that hold one document share one caret.

### The verbs of a program

`PaneProgram.jl` gives a program the layout as references into the tree, and a verb for each common change to it. Every reference a verb takes or answers is complete: it starts at the root of the editor's document, not at a tree object. A verb finds its own tree from the reference it is given — the longest prefix that ends at a `PaneTree` — so no verb assumes one window or one tree. `get_window_tree(editor)` stays for code that already holds one window and needs the tree object itself; a verb does not use it.

| Verb | What it does | Returns |
| --- | --- | --- |
| `show_layout(editor)` | prints the layout as a tree of reference steps | a `Text` |
| `get_referenced_value(editor, reference)` | reads the node at a reference | the node, or an `ArgumentError` that names the path |
| `replace_referenced_value!(editor, reference, value)` | writes a value at a reference, as one undo step | the new layout |
| `focus_pane!(editor, reference)` | shows a tab and gives it the focus | the new layout |
| `open_pane!(editor, document; title, group, target, side)` | puts a document in a new tab | the new tab, as a `ReferencedDocument` |
| `duplicate_pane!(editor, reference)` | duplicates a tab | the duplicate, as a `ReferencedDocument` |
| `close_pane!(editor, reference)` | closes a tab | the new layout |
| `move_pane!(editor, reference, target; side)` | moves a tab to a group, before a tab, or beside a group in a new split | the new layout |

Each verb makes its edit at the pane tree and carries it to the root through the readers of the editor (`read_rooted_operation`; see [editor.md](../../kernel/editor.md#an-operation-from-a-place-not-a-gesture)), then evaluates it at once, so every document on the path of the selection holds its part of the new state. Each verb but `replace_referenced_value!` has a `make_…_operation` companion — `make_open_pane_operation`, `make_focus_pane_operation`, `make_close_pane_operation`, `make_duplicate_pane_operation`, `make_move_pane_operation` — that reads the same edit and evaluates nothing, for a caller that already runs inside another evaluation and posts the result with `post_pane_operation!(editor, operation)`. The menu and toolbar actions, and `OpenFileOperation`, post this way. `post_pane_operation!` applies the operation at once instead when `editor` is not a running `Editor`, such as a test that holds the tree.

`find_pane_reference(editor, title)` answers the complete reference of the pane whose title is `title`, in any window, and `nothing` when no pane has it; when two panes have it, an `ArgumentError` names both. It descends only into the documents that can hold a pane (`is_pane_search_step`, the default of its `descend` keyword). `find_pane_tree_reference(editor)` answers the complete reference of the pane tree that holds the focus — the nearest tree on the path of the root's selection, else the one tree of the window, else `nothing`.

**The level is the reference, not the verb.** A change with no verb of its own is one write: a value at `root` rearranges the window, a value at `root.elements[1]` moves one side of a split, a value at `root.weights` resizes a split, and a value at `tabs[i].content` changes what a pane holds. A range splices, so `[]` at `tabs[2, 3]` closes two tabs at once. A move and a close have their own verbs too, `move_pane!` and `close_pane!`. Focus is the selection and not a value, and a correct duplicate can share a live action with its original, so a caller can not make either as a value: each has its own verb, `focus_pane!` and `duplicate_pane!`.

`show_layout` prints the layout as a tree of reference steps, one line for each window, pane tree, split, group and tab it descends into:

```
(root)                                          ::GestureTrackingState  # the editor's document
  .content                                      ::ScreenDocument
    .windows[1]                                 ::WindowDocument        # title "ProjecturEd"
      .content.content.content.content          ::PaneTree              # inside ClipboardSlice › WidgetShell › UndoBuffer
        .root                                   ::PaneSplit             # side by side: 20% | 80%
          .elements[1]                          ::PaneGroup             # 1 tab
            .tabs[1]                            ::PaneTab               # title "Files", shows Workspace (focused)
          .elements[2]                          ::PaneGroup             # 1 tab
            .tabs[1]                            ::PaneTab               # title "a.json", shows JsonFile
```

A line's steps are those after the nearest printed line whose path is a prefix of its own, so the path of a part is the steps of the lines on its branch, joined in order: `@reference(editor.document, content.windows[1].content.content.content.content.root.elements[2].tabs[1])`. To name a pane there is a shorter way: `find_pane_reference` answers the reference of a pane by its title. The type on each line is `nameof(typeof(node))`; the note gives the node's title after `title`, quoted as `find_pane` takes it (`get_document_title`), what it shows after `shows` (`describe_document`) when that says more than the type, the wrappers a line's steps pass through, and the deepest focused tab. `include(node)` says which nodes get a line and `descend(parent, child)` where the walk goes; the defaults show the windows, the pane trees, the splits, the groups and the tabs, and a pane tree inside a tab below that tab. It answers a `Text` and not a `String`, so the tree arrives as the lines it is and not as one line of `\n` escapes.

A path written by hand is typed against the tree it names a part of, then set after the path to that tree: resolve `find_pane_tree_reference(editor)` to the tree object with `evaluate_reference`, type the rest with `@reference(tree, …)`, and join the two with `concat_references`:

```julia
tree_reference = find_pane_tree_reference(editor)
tree = evaluate_reference(editor.document, tree_reference)
reference = concat_references(tree_reference, @reference(tree, root.elements[1].tabs[1]))
```

A path to a node that the tree does not hold is not fully typed, and every verb throws an `ArgumentError` for it. `replace_referenced_value!` also throws for an empty reference, for a range outside its collection, and for a value that its slot can not hold. `tabs` holds `PaneTab`, and `elements` and `root` hold `PaneGroup` and `PaneSplit`. After the write, it finds the focused tab and the shown tab of each group again by object identity, wherever they are now.

`open_pane!` puts the tab in the focused group. When that is the group that `pane_group_to_avoid(tree)` names and another group exists, it takes the first other group. The default is `nothing`, and an application adds a method, so that a new pane does not cover a conversation. Of the groups that remain, `open_pane!` takes only a group in which every tab content answers `true` to `accepts_opened_file`, while such a group exists. `get_pane_file_group` uses the same test. So a tool that opens while the focus is in an explorer or an assistant goes beside the files, and not into the group of the explorer. A title that another tab has gets a number. `duplicate_pane!` puts the duplicate after the original, or where `open_pane!` would put it when the original is in the group to avoid. `move_pane!` takes a reference and a `target`: a target that names a group puts the pane at its end, a target that names a tab puts it before that tab, and `side` (`:left`, `:right`, `:above` or `:below`) puts it beside the target's group in a new split.

`open_pane!` takes the same `target` and `side` as `move_pane!`, in place of the focused group: a group as `target` sends the tab to its end, a tab as `target` puts the new tab before it, and `side` puts the tab in a new group beside the target's group, as `make_pane_split_operation` splits a group: in a new split that takes the place of the target's group, or in the parent split when it already has that orientation; the new tab gets the focus. `open_pane!` throws an `ArgumentError` for a call that gives both `group` and `target`, and for a `side` that is not one of the four.

`find_pane(editor, title)` answers the tab of that title as a `ReferencedDocument` that acts like the tab, or `nothing` when no tab has that title; two tabs of that title raise the same `ArgumentError` as `find_pane_reference`. Every verb that takes a reference, or a document to place, also takes a `ReferencedDocument` in its stead: `focus_pane!`, `close_pane!`, `duplicate_pane!`, `move_pane!` for either its reference or its target, `get_referenced_value`, `replace_referenced_value!` for the reference or the value it writes, `describe_document`, and `open_pane!` for the document it opens and for its `target` — such as the tab `find_pane` answers. `open_pane!` and `duplicate_pane!` answer the tab they made as a `ReferencedDocument` too; `get_reference` gives its reference. `get_parent(editor, x)` answers the group that holds a tab, or the document around any other part, one step up `x`'s reference and past every collection on the way: `get_parent(editor, find_pane(editor, "items.json"))` answers the group of the tab named `"items.json"`.

To find a tab again after the layout changes, keep a `DocumentLocator` instead of a `ReferencedDocument`: `DocumentLocator(editor, find_pane_reference(editor, "items.json"))` is not resolved yet, and `find_referenced_document` resolves it again at each call, so it still finds the tab after a pane moves, after an unrelated sibling closes, or after `replace_referenced_value!` replaces the tab itself.

`make_pane_api()` and `make_interface_api()` return the names that a model may write, by module: the verbs, the pane types, the layouts, `@reference`, and the widgets that a person names in a request. A declaration of a whole module adds about thirty generated schema variants for each document type. Declared whole, `PaneModule` and `ReferenceModule` take the surface from 10 names to 122, and a search for "what panes are open" then finds those variants before `show_layout`.

### The shape of the pointer during the drag of a tab

A tab of the tree is an open hand under the pointer, because a press there can drag it. When the drag starts, after the small move, the tree says the shape of the drag to the screen with `make_screen_pointer_shape_operation`: the closed hand while a group takes the tab at the pointer, and the crossed circle while none does. It says it again at a `DragMove` only when the kind of the landing changes, and gives the shape back at its `DragEnd` and its `DragCancel`. See [screen.md](../screen/screen.md#the-shape-of-the-pointer-during-a-drag).

### The tabs of an editor

The wrapper `tabs` of `build_editor` puts the root document in the one tab of a pane tree. It is on by default, so an editor that is built with this package loaded shows its documents as tabs, and `tabs = false` turns it off. A root that is a `PaneTree` or a `ScreenDocument` already is left as it is. Its argument `(; title, appearance, measure)` names the tab and gives the `Appearance` whose widget theme the pane's widgets draw with, and their measure.

`make_tabs_projection(projection)` draws the tree. `PaneToWidget` makes the widgets and leaves the content of each tab as it is. The stage after it draws every widget and layout with the widget renderer, and every other document with `projection`. So the tabs work with a projection that draws no widget, and a content that is itself a widget draws as a widget. A content can not be told by its place, because the widget printers hand their own context to a child.

`show_document!(editor, document; title)` of the screen package shows a later document. For a window whose content is a `PaneTree`, this package's method opens a tab named `title`, or focuses the tab that shows `document` already.

### Save and load of the whole editor

`save_user_interface(editor, path)` saves the document of the editor, with every window, split, group and tab, as one `.pred` file. The cut writes a `FileDocument` child as a reference, `file("a.json")`, only when that file is a file of the project, and it aborts on any other. So the function finds each reachable file tab with `search_documents(document, is_file_document)` and adds it to the `FileProject` beside the `.pred` file. `load_user_interface(path)` returns the document, with each file tab read back from its file.

`pred_arguments` of `PaneTree` writes only `root`, because a drag is not layout. A `.pred` file builds `PaneTree`, `PaneSplit`, `PaneGroup` and `PaneTab` by their names, as it builds any loaded document type. The functions name no screen type, so an editor that holds a bare `PaneTree` saves and loads the same way.

`get_pane_file_group(editor)` returns the group for a newly opened file: a group that holds a file already, as the content of a tab or through a layer that `get_edited_field` names, such as the scroll pane of a file tab, else a group whose tabs all answer `accepts_opened_file`, the focused one first. The file-system package pairs its `OpenFileOperation` with this answer, because this package can not name a type of a package that it does not depend on.

## How it fits

The pane slice depends on the kernel and on the widget, layout, clipboard, domain, dragging, focus, primitive, collection, projection and serialization slices. It adds methods to `find_clipboard_document`, `accepts_pasted_replacement`, `has_dormant_selection`, `pred_arguments` and `make_pred_document`.

The shell slice puts a pane tree in the content of a window; see [shell.md](../shell/shell.md). The file-system slice opens a newly read file with `make_open_pane_operation` and `get_pane_file_group`, posted with `post_pane_operation!`, because it runs inside the evaluation of `OpenFileOperation`. An application adds methods to `describe_document` and `pane_group_to_avoid`, and declares `make_pane_api()` and `make_interface_api()` for its assistant.

## Design decisions

- **No node stores the focus.** The selection names the focused tab, and a dormant selection keeps the tab of each group. A second field would have to agree with the selection after every edit. See [plan/done/pane-layout.md](../../../../plan/done/pane-layout.md).
- **The surgery returns generic operations.** A pane tree then works inside any other document, and no projection above it needs a pane operation type. See [plan/done/pane-layout.md](../../../../plan/done/pane-layout.md).
- **The widget layer reports; the pane makes the edit.** A tab strip holds no data about what a close means for the document behind it. Any other owner of tabs can answer the same reports.
- **A program writes values at references.** A layout is a document, and a reference names any part of it, so one write verb covers every level. `source/platform/pane/PaneProgram.jl` states the rule in its header.
- **A model sees a list of names, not whole modules.** The measured surface of 10 names against 122 is the reason. See [plan/done/declared-api-is-a-list-of-names.md](../../../../plan/done/declared-api-is-a-list-of-names.md).
- **A duplicate follows three ownership rules.** A copy that shares a running process gives two panes one process, and a copy that owns what it reads multiplies the data. See [plan/done/duplicate-a-pane.md](../../../../plan/done/duplicate-a-pane.md).
- **A new tab is filled by a paste.** The placeholder is selected as a whole, so the paste of the clipboard package fills it. The package needs no fill operation of its own. See [plan/pending/select-a-widget-and-paste-it-into-a-tab.md](../../../../plan/pending/select-a-widget-and-paste-it-into-a-tab.md).

## Usage

```julia
run_example(pane_example)         # three groups, four tabs
run_example(empty_pane_example)   # one empty group

reference = open_pane!(editor, WidgetLabel("The delay of every run"); title = "Note")
focus_pane!(editor, reference)
show_layout(editor)
tree_reference = find_pane_tree_reference(editor)
tree = evaluate_reference(editor.document, tree_reference)
replace_referenced_value!(editor, concat_references(tree_reference, @reference(tree, root.elements[1].tabs[2, 2])), [])
duplicate_pane!(editor, reference)
close_pane!(editor, find_pane_reference(editor, "Note"))
save_user_interface(editor, "session.pred")
```

`editor` is a running editor whose document holds a pane tree.

- Examples: `pane_example` and `empty_pane_example`, built by `make_pane_projection_example` in `example/platform/PaneProjectionExample.jl`.
- Tests: `test_pane_surgery()`, `test_pane_geometry()`, `test_pane_to_widget()`, `test_pane_reader()`, `test_pane_gestures()`, `test_pane_drag()`, `test_split_pane_drag()`, `test_pane_rename()` and `test_pane_construct()` under `test/platform/`, and `test_user_interface_file()` in `test/projectured/editor/`. The package has no suite of its own.

## Limits

- The strip prints a title as a label, so the name changes as a person types it, but the strip draws no caret.
- An Alt+click on the tab title of a group without the focus brings back the selection that the tab kept. The kernel revives a dormant selection on a write that ends at its keeper. The fix needs a change of a sealed kernel file. [plan/pending/select-a-widget-and-paste-it-into-a-tab.md](../../../../plan/pending/select-a-widget-and-paste-it-into-a-tab.md) holds the item.
- The geometry is proportional. It is not a model of the pixels of the drawing.
