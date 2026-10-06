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
- `point`: where the click was, or `nothing` when a command runs the binding.

`ReplaceViewStateOperation` marks the menu as not an edit, so a history does not record it.

These types have a binding:

| Type | Binding | Menu |
| --- | --- | --- |
| `WidgetContextMenu` | "Show the context menu" | its `menu`, while it is enabled |
| `WidgetShell` | "Show the window menu" | its `context_menu`, the menu of the window |
| `DataFrameColumn` | "Show the menu of the column" | filter the column by its values, hide it |
| `DataFrameView` | "Show the menu of the view" | show the hidden columns, while a column is hidden |

### The click goes to the part, and out through the parts around it

A right click goes by its position, as a dwell does ([tooltip.md](../tooltip/tooltip.md)). The screen gives it to the window of the pointer, and each container gives it to the child at its point, in the frame of that child. A child that answers nothing gets the click in its documents: the backward map of the point names the part inside it (`compute_part_at_point`), and the documents on that path read the click with their tables (`read_child_part_gesture`). So the header of a data frame column, which the data frame view maps back to a `DataFrameColumn`, answers with the menu of the column.

**The parts around add their menus.** `OpenContextMenuOperation` collects (`is_collecting_operation`). After the child at its point answered, each container reads the click with the tables of its own documents, out to its own input (`read_container_gesture`). An answer of the same kind is joined with `join_collected_operations`, which adds the outer menus after the nearer ones. `WidgetContextMenu` gives the click to its child and then reads its own table, so a nearer `WidgetContextMenu` gives the first menu. `WidgetShell` gives the click to the band at its point and then reads its own table, so the menu of the window, when the window has one, is the outermost layer.

### A right click moves no selection

Only a left click moves the selection. A row of a list, of a table or of a tree, a tab, a text field and the views of text, of a formula, of a sequence chart and of a conversation answer a selection to a left click only ([widget.md](widget.md)). A right click on a row goes on outward to the menus, and the selection stays where it was. The part under the pointer lights, so a person sees the part that the menu belongs to. The binding of a part computes the menu from that part, so each item of the menu acts on that part without the selection.

### The window

`ContextMenuWindowProjection` keeps the context menu window. It sits around the screen, inside the gesture tracker. `make_tracking_screen` puts it there when `inner_wrappers` holds `wrap_context_menu_window`. The `context_menu` wrapper of `build_editor`, on by default in the layer `:window => -10`, gives `wrap_context_menu_window` to the `window` wrapper through `EditorParts.window_wrappers`, outside the tooltip window, so every editor with a window has the context menu window, and `context_menu = false` leaves it out. A host that calls `make_tracking_screen` itself, as the gallery does, passes `wrap_context_menu_window` in `inner_wrappers`.

- **Opening.** The wrapper takes the `OpenContextMenuOperation` out of the answer of its content and opens a window with `style = :popup` and `auto_dismiss = true` at the point of the click, in screen coordinates. The window of the pointer moves the point from its own frame to the screen. With no point, the window opens below the part, with the left edges aligned and 4 pixels between them (`find_part_place` of the screen slice). The window takes the extent of the menu, up to `maximum_size`, `(640, 800)` by default.
- **What it shows.** The window shows the menu of the nearest part, the first layer, as it is.
- **More and fewer.** F2 shows the menu of the next part outward, and Shift+F2 one fewer. While more than one menu shows, the window holds one `WidgetMenu`: each layer starts with a disabled item that names its part, and a `WidgetSeparator` stands between two layers. `ContextMenuWindowState` declares both keys in its gesture table while the window is open, so the gesture help lists them. The keys and the reopening of the window are the layer helper of the screen slice (`make_window_layer_bindings`, `show_window_layers`), which the tooltip window uses too.
- **Closing.** The window has the id of the popups of the widgets, `:widget_popup`. So the window manager closes it on a press in another window, on a bare Escape and on the loss of the focus. A choice of an item runs the action of the item and closes `:widget_popup`. The wrapper forgets its layers when the window is gone.
- **Keys.** The window is a `:popup`, so the window under it keeps the focus. While the window is open, a key of that window goes first to the content of the menu, after F2 and Shift+F2: a menu that answers a key takes it, and a key that the menu does not answer goes on as before. A `WidgetMenu` answers no key, so its keys go on; the list of choices of the navigator takes the typed text, Up, Down and Return. A key that closes the window, such as Escape, makes the wrapper forget its layers at once.
- **An item that edits its part.** A `WidgetMenuItem` can hold an `operation`, relative to the part that the menu belongs to. A choice of the item answers `EditMenuPartOperation` in place of its action. The wrapper lifts the operation from the part through the readers of its content, as `read_rooted_operation` lifts an operation that code made: from the part outward, the first place from which the readers carry it. So every reader around the part has its turn: an undo buffer records the edit as an edit of the person, and Ctrl+Z takes it back. The part is the nearest one, under the pointer, also for an item of the menu of a part around it, which F2 shows; such an item holds an operation that names its own document. An action with a callback runs outside the readers, and no history records it. The menus of a data frame view use operations so.

The state of the wrapper, `ContextMenuWindowState`, holds the layers, the count that shows, the source and the window operation. A view state operation writes each field.

### A command runs the same binding

The command palette lists a binding by its `description` on the selection, and greys it where the part has no menu. It runs the binding with no gesture, so the answer has no point, and the wrapper opens the window below the part. A command that an agent runs goes by route through the wrapper, and the wrapper takes the menu from that answer as well.

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

- Tests: `test_context_menu_window()` for the window, through a real editor; `test_widget_context_menu()` and `test_widget_popup_example()` for the binding of `WidgetContextMenu`; `test_data_frame_columns()` for the menus of a data frame.

## Limits

- A menu, a menu item, a dialog, a tooltip widget and a title pane do not read their own tables for a right click. None of them has a binding for one.
- An editor with `context_menu = false`, or a host that calls `make_tracking_screen` with no `wrap_context_menu_window`, opens no context menu: the operation reaches the editor, which does nothing with it.
