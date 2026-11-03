# Context menu

> **Kind:** design · **Status:** current · **Stands on:** [widget.md](widget.md), [tooltip.md](../tooltip/tooltip.md), [screen.md](../screen/screen.md)

The widget slice of `ProjecturedPlatform` opens the menu of the part under the pointer in a window of its own. The meaning is in the gesture table of the part: a part answers a right click with an operation, and each part around it adds its menu. This document says how a right click becomes a menu, how the window shows more and fewer menus, and why a right click moves no selection.

## How it works

### A part answers a right click

A type that has a menu declares a binding in its own gesture table:

```julia
get_document_gesture_bindings_own(::Type{DataFrameColumn}) =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the menu of the column")]
```

`make_context_menu_binding(compute; description)` binds `MouseClickPattern(:right)`. The binding answers `ReplaceViewStateOperation(OpenContextMenuOperation(layers, source, point))` when `compute(document)` returns a menu, and nothing when it returns `nothing`. The binding is `applicable` only where the document has a menu. `compute_context_menu` of the domain slice is the usual `compute`.

`OpenContextMenuOperation` holds:

- `layers`: the `(title, menu)` pairs, the nearest part first. The title is `get_document_title` of the part, or the name of its type;
- `source`: the path of the nearest part. A reader reroots it and retargets it on the way up, as it does any path;
- `point`: where the click was, or `nothing` when a command runs the binding;
- `placement`: `nothing`, or a function of the reference of the part from the screen that answers the placement function of the window ([screen.md](../screen/screen.md#the-placement-of-a-window)). `OpenContextMenuOperation(layers, source, point, placement = nothing)`.

`ReplaceViewStateOperation` marks the menu as not an edit, so a history does not record it.

These types have a binding:

| Type | Binding | Menu |
| --- | --- | --- |
| `WidgetContextMenu` | "Show the context menu" | its `menu`, while it is enabled |
| `WidgetShell` | "Show the window menu" | its `context_menu`, the menu of the window |
| `DataFrameColumn` | "Show the menu of the column" | filter the column by its values, hide it |
| `DataFrameView` | "Show the menu of the view" | show the hidden columns, while a column is hidden |
| `GraphLayout` | "Show the menu of the graph" | draw the edges as straight lines or as curves |

### The click goes to the part, and out through the parts around it

A right click goes by its position, as a dwell does ([tooltip.md](../tooltip/tooltip.md)). The screen gives it to the window of the pointer, and each container gives it to the child at its point, in the frame of that child. A child that answers nothing gets the click in its documents: the backward map of the point names the part inside it (`compute_part_at_point`), and the documents on that path read the click with their tables (`read_child_part_gesture`). So the header of a data frame column, which the data frame view maps back to a `DataFrameColumn`, answers with the menu of the column.

**The parts around add their menus.** `OpenContextMenuOperation` collects (`is_collecting_operation`). After the child at its point answered, each container reads the click with the tables of its own documents, out to its own input (`read_container_gesture`). An answer of the same kind is joined with `join_collected_operations`, which adds the outer menus after the nearer ones. `WidgetContextMenu` gives the click to its child and then reads its own table, so a nearer `WidgetContextMenu` gives the first menu. `WidgetShell` gives the click to the band at its point and then reads its own table, so the menu of the window, when the window has one, is the outermost layer.

### A right click moves no selection

Only a left click moves the selection. A row of a list, of a table or of a tree, a tab, a text field and the views of text, of a formula, of a sequence chart and of a conversation answer a selection to a left click only ([widget.md](widget.md)). A right click on a row goes on outward to the menus, and the selection stays where it was. The part under the pointer lights, so a person sees the part that the menu belongs to. The binding of a part computes the menu from that part, so each item of the menu acts on that part without the selection.

### The window

`ContextMenuWindowProjection` keeps the context menu window. It sits around the screen, inside the gesture tracker. `make_tracking_screen` puts it there when `inner_wrappers` holds `wrap_context_menu_window`. The `context_menu` wrapper of `build_editor`, on by default in the layer `:window => -10`, gives `wrap_context_menu_window` to the `window` wrapper through `EditorParts.window_wrappers`, outside the tooltip window, so every editor with a window has the context menu window, and `context_menu = false` leaves it out. A host that calls `make_tracking_screen` itself, as the gallery does, passes `wrap_context_menu_window` in `inner_wrappers`.

- **Opening.** The wrapper takes the `OpenContextMenuOperation` out of the answer of its content and opens a window. It looks into a `CompoundOperation` and into each `WrappingOperation`, and it keeps the rest of the answer in the same wrapper. So a key that edits a part and opens a list at the same time, such as a key in a `DocumentInsertion`, opens the list under an undo buffer too: the buffer wraps the two in one `RecordUndoOperation`, and the record keeps only the edit. The window opens with `style = :popup` and `auto_dismiss = true` at the point of the click, in screen coordinates. With a `placement` in the operation, the window finds where the screen starts on the path of the source, binds the part to the function, and opens with that placement. With `nothing`, the window opens as follows. The window of the pointer moves the point from its own frame to the screen. With no point, the window opens below the part, with the left edges aligned and 4 pixels between them (`find_part_place` of the screen slice). The window takes the extent of the menu, up to `maximum_size`, `(640, 800)` by default.
- **What it shows.** The window shows the menu of the nearest part, the first layer, as it is.
- **More and fewer.** F2 shows the menu of the next part outward, and Shift+F2 one fewer. While more than one menu shows, the window holds one `WidgetMenu`: each layer starts with a disabled item that names its part, and a `WidgetSeparator` stands between two layers. `ContextMenuWindowState` declares both keys in its gesture table while the window is open, so the gesture help lists them. The keys and the reopening of the window are the layer helper of the screen slice (`make_window_layer_bindings`, `show_window_layers`), which the tooltip window uses too.
- **Closing.** The window has the id of the popups of the widgets, `:widget_popup`. So the window manager closes it on a press in another window, on a bare Escape and on the loss of the focus. A choice of an item runs the action of the item and closes `:widget_popup`. The wrapper forgets its layers when the window is gone.
- **Keys.** The window is a `:popup`, so the window under it keeps the focus. While the window is open, a key of that window goes first to the content of the menu, after F2 and Shift+F2: a menu that answers a key takes it, and a key that the menu does not answer goes on as before. A vertical `WidgetMenu` takes Up, Down, Home, End and Return ([The keys of a menu](#the-keys-of-a-menu)); a `WidgetChoiceList`, such as the list of the navigator, the kinds of an element and the items that a link field of a study offers, takes the typed text, Up, Down, Backspace and Return. A key that closes the window, such as Escape, makes the wrapper forget its layers at once.
- **An item that edits its part.** A `WidgetMenuItem` can hold an `operation`, relative to the part that the menu belongs to. A choice of the item answers `EditMenuPartOperation` in place of its action. The wrapper lifts the operation from the part through the readers of its content, as `read_rooted_operation` lifts an operation that code made: from the part outward, the first place from which the readers carry it. So every reader around the part has its turn: an undo buffer records the edit as an edit of the person, and Ctrl+Z takes it back. The part is the nearest one, under the pointer, also for an item of the menu of a part around it, which F2 shows; such an item holds an operation that names its own document. An action with a callback runs outside the readers, and no history records it. The menus of a data frame view use operations so.

The state of the wrapper, `ContextMenuWindowState`, holds the layers, the count that shows, the source and the window operation. A view state operation writes each field.

### A button opens a menu under itself

`make_menu_button_binding(compute; description)` binds a left click to the menu that `compute(document)` returns, in the same window. The answer has no point, so the window opens below the part pressed, as a command opens it. The outline slice gives the "⋯" and the mark of a row such a press, and gives the row a right click and Shift+F10, so the three open one menu ([outline.md](../outline/outline.md)). `make_context_menu_operation` takes a `title`, which names the part in the window when F2 shows more than one menu.

### The keys of a menu

A vertical `WidgetMenu` answers the keys of a list. Down and Up light the next and the previous enabled item, Home and End the first and the last, and Return chooses the lit item as a click does. `highlighted`, the index of the lit item, is view state of the menu, so a key writes it with `ReplaceViewStateOperation` and a history does not record it. The lit item draws the hover layer behind it, as wide as the menu. A `WidgetMenuItem` draws its `keys` at its right edge, quiet, so the keys of a menu make a column and a person learns them from the menu.

### A list that a person types into

`WidgetChoiceList(; query, row, top, shown_rows, current, prompt, placeholder, empty, footer, fills_offer, find, choose, edit)` is a menu that a person types into: a line of the typed text over the choices that `find(query)` gives, each a `WidgetChoice` of a label, an icon, a note and a value. `make_choice_list_operation(title, list; point, placement)` opens it in the context menu window. The list reads a key before any widget of it: a typed character narrows it and goes back to the first row at the top, Backspace removes the last one, Up, Down, Page Up and Page Down move the row, and Return chooses it, so the window under it keeps the focus and a letter edits nothing there. A choice answers `EditMenuPartOperation` with the operation of `choose(value)`, as an item of a context menu does. With `edit`, a typed character and Backspace also answer `EditMenuPartOperation` with the operation of `edit(query)`, so the list writes the field that it opened under as the person types, as the list of the kinds of an insertion does ([syntax.md](../syntax/syntax.md)). `make_insertion_choice(type)` is the row of a kind of document: its shortest name or alias, its icon and the first sentence of its docstring. The navigator shows the choices at a step of its address so ([navigator.md](../navigator/navigator.md)).

**A long list builds only the rows that show.** `top` is the first row that shows, and `shown_rows` (12 by default) is how many rows show. The rows are a lazy list (`make_index_list`) with its head at `top`, and the menu walks only the rows that show (`take_first`). So a list of any length builds only the shown rows. `find` can answer any `AbstractVector` of `WidgetChoice`, also one that makes each choice when it is read. The shown rows follow `row` when a key moves it. The wheel moves `top` by three rows a step. `footer` is a line under the rows: `nothing`, a string, or a function of no arguments that answers either, which the view reads as it draws. With `fills_offer`, the list gives its menu the exact width that its window gives it, as `minimum_width` of the `WidgetMenu`, so a list in a window of a fixed width fills it and a row lights across it; with no `fills_offer`, the list is as wide as its rows, because a popup window offers its maximum width to every content.

**Where the list stands.** `placement` of `make_choice_list_operation` is a function of the reference of the part from the screen. `make_shell_top_placement(reference; keywords...)` of the widget slice answers the placement at the top center of what the `WidgetShell` of the window of the part holds: `gap` below the lowest of the menu bar and the toolbar, with a width that is a share of the width of the shell. It finds the shell by a search a few levels deep into the content of the window, and it reads the boxes of the shell and of its two bands, not the box of what the shell holds, so it places over a content of any kind. With no shell, it places the list at the part itself. The keywords are those of `make_part_top_placement`, and `make_top_center_place` of the screen slice makes the place from the box. The command palette and the search of a file by its name use it ([gesturehelp.md](../gesturehelp/gesturehelp.md#ctrlshiftp-the-command-palette), [filesystem.md](../filesystem/filesystem.md#the-files-of-the-workspace-folders)).

**Matching by letters.** `find_letter_match(query, text; name_start = 1)` answers an `Int` score, or `nothing` when the letters of the query do not come in order in the text. `find_letter_matches(query, texts; name_start = text -> 1)` answers the indices of the matching texts, the best first: a higher score, then a shorter text, then the given order. Both are in `LetterMatch.jl`. The letters of the query must come in order, in any case, and they need not touch. A letter at the start of a word counts most: the start of the text, a letter after `/`, `\`, `_`, `-`, `.`, a space or `:`, and a capital after a small letter. A letter in the name part of the text, from `name_start` on, counts more. A letter right after the letter before it counts more.

### A command runs the same binding

The command palette ([gesturehelp.md](../gesturehelp/gesturehelp.md#ctrlshiftp-the-command-palette)) lists a binding by its `description` on the selection, and greys it where the part has no menu. It runs the binding with no gesture, so the answer has no point, and the wrapper opens the window below the part. A command that an agent runs goes by route through the wrapper, and the wrapper takes the menu from that answer as well.

## How it fits

The operation, the binding and the wrapper are in the widget slice, because a menu is a `WidgetMenu`. The layer helper and `find_part_place` are in the screen slice, which the tooltip slice and the widget slice both use. The kernel holds the outward reading (`read_gesture_outward`), and the graphics slice holds the hand-off of a right click to the child at its point (`read_container_gesture`, `read_child_part_gesture`). A domain that has a menu depends on the widget slice for `make_context_menu_binding`.

## Design decisions

- **The meaning belongs to the part.** A part answers a right click from its own gesture table, and each projection on the way up can change or drop the answer. The command palette and an agent can run a binding, but not a central lookup of the document under the pointer.
- **A right click moves no selection.** The light shows the part under the pointer, and each layer carries the path of its part, so the menu needs no selection. So no selection is joined with a menu, and the outward reading has no exception.
- **The menus are collected at once.** F2 and Shift+F2 choose from what the click collected, so they read no part again.
- **The context menu has a wrapper of its own.** A tooltip and a menu are alike, but they close in other ways. The two wrappers share the layer helper of the screen slice.

## Usage

```julia
editor = build_editor(document, projection; backend = backend,
    window = (; title = "Title"))          # the tooltip and the context menu windows are on
```

A `WidgetContextMenu(child, menu)` gives a part of a widget tree a menu. The menu has no position of its own: it stands where its child stands, as a `LayoutConstraint` does, so a composite places it by the position of the child, and the box of the menu covers the child there. A domain type gives itself a menu with `make_context_menu_binding` in its gesture table.

- Tests: `test_widget_menu_keys()` for the keys of a menu, its column of keys and a button that opens a menu; `test_context_menu_window()` for the window, through a real editor; `test_widget_context_menu()` and `test_widget_popup_example()` for the binding of `WidgetContextMenu`; `test_data_frame_columns()` for the menus of a data frame.

## Limits

- A menu, a menu item, a dialog, a tooltip widget and a title pane do not read their own tables for a right click. None of them has a binding for one.
- An editor with `context_menu = false`, or a host that calls `make_tracking_screen` with no `wrap_context_menu_window`, opens no context menu: the operation reaches the editor, which does nothing with it.
