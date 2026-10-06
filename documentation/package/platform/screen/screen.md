# Screen

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [graphics.md](../graphics/graphics.md)

The screen slice of `ProjecturedPlatform` holds the window model: a screen document with a list of windows, the projection that maps it, and the projection that opens, closes and resizes windows. A backend shows the output screen as native windows. [devices-and-backends.md](../../kernel/devices-and-backends.md) describes the backend side; this document describes the document side.

## How it works

`ScreenDocument` has one field, `windows`, a `CellVector` of `WindowDocument`. `OpenWindowOperation` and `OpenPopupOperation` request that a window opens, and their fields mirror those of `WindowDocument`. `OpenPopupOperation(; id, x, y, width, height, auto_dismiss, content)` carries `(x, y)`, the top left of the popup, in the frame of the reader that holds it. A reader on the way up moves that position into its own frame; [graphics.md](../graphics/graphics.md#moving-the-position-an-operation-carries) describes how. A `WindowDocument` has:

- `id`, a `Symbol`. The backend keeps one native window for each id, from frame to frame.
- `title`, `x`, `y`, `width`, `height`. A position of `-1` lets the backend choose, and a size of `0` sizes the window to its content.
- `minimum_size` and `maximum_size`, the bounds of a window that fits what it holds. A maximum of `(0, 0)`, the default, is a window of a fixed size. A tooltip and a popup fit what they hold.
- `style`: `:normal`, `:tooltip`, `:floating` or `:popup`. The backend applies the behaviour of each style. A `:popup` is a menu or a dropdown list, and it never takes the focus: the keyboard stays in the window under it. A `:floating` window, such as a dialog, takes the focus.
- `auto_dismiss`: the window is a transient popup, which closes when the pointer or the keyboard acts elsewhere, as a menu does. `WindowManagingProjection` lists the events that close it.
- `modal`: while the window is open, no other window gets input.
- `content`, any document. The projection chain goes into this field only.

The screen is data like any other document. To open a window, a program adds a `WindowDocument` to `windows`. To close one, it removes it. The backend compares the output screen with its native windows on each frame. No `open_window!` call exists.

### ScreenToScreen

`ScreenToScreen` maps the input screen to the output screen. It copies the metadata of each window and sends `content` through the projection of the caller. It sets the `width` and `height` of the window as the size available to the content, so a split pane or a scroll pane fills the window. **A window that fits is offered its `maximum_size` instead, always.** The backend gives such a window the extent of the canvas it printed, so an offer that followed that size would chase it: a text wraps at the maximum width, and the window ends as wide as the text needed. [sdl.md](../../backend/sdl/sdl.md) describes the backend half.

It keeps the IO map of each window by identity (`make_reconciled_child_iomaps_cell`). So a window that opens or closes does not rebuild the other windows, and a new content in a window with the same id replaces the old content in place.

**The canvas of a window.** When the content of a window draws a `GraphicsCanvas`, the output window holds a canvas of the window: the content as its first element, and over it the region of the shape of the pointer that the screen keeps ([below](#the-shape-of-the-pointer-during-a-drag)). So the path of the content in the output is `windows[i].content.elements[1]`. A content that draws no canvas is the content itself.

Its reference map gives a path of the content the prefix `windows[i].content`, in both directions, and the step `elements[1]` in the output when the window has its canvas; a path to the region maps to no part. A point reaches the content only after `windows[i].content`, in the frame of the window: the window takes off the place of the root canvas of its content, because a widget reads a point in the frame of its own canvas. A bare point, with no window, names no part and maps to `nothing`.

Its reader routes a `WindowInput` event by the window id, not by the position in the list. The window moves a pointer event into the frame of the root canvas of its content with `shift_event_position`, and moves a position in the answer back. It then adds the prefix `windows[i]` to the operation that comes back. When that operation is an `OpenPopupOperation` inside `ReplaceViewStateOperation`, it adds the window's own screen origin to the popup and turns it into an `OpenWindowOperation` with `style = :popup` and a `maximum_size` of the width and the height of the popup, and drops the mark. So the window takes the extent of what the popup draws, up to that bound, which is `(640, 800)` by default. The mark keeps a popup out of a history only above the window; below the window manager, a popup opens exactly as any other window does.

**The part under the pointer.** A move with no button held names the part under the pointer, and the screen holds the whole path. A window whose content names no part is the part itself. A move in another window, and the leave of the window that the pointer is in, give the old window a move to `(-1, -1)`, a point off it: the backend does not say where the pointer is after a leave, and a popup can lie over the old window. After the leave the screen answers the empty path, because the pointer is still on the screen. A leave of a window that the pointer is not in changes nothing. See [mouse-target.md](../../kernel/mouse-target.md) for how each window on the path keeps its own part of it.

### WindowManagingProjection

`WindowManagingProjection` wraps `ScreenToScreen` and applies the window operations:

- `OpenWindowOperation` and `CloseWindowOperation` from any reader below, also inside a `CompoundOperation`. So the choice of an item in a menu can set a value and close the menu in one operation. `CloseWindowOperation` names its window by the id, so it is self-contained (`is_self_contained_operation`): it passes up also through a projection that knows no window, such as a projection of a document whose view holds a menu. `ScreenToScreen` already turned a popup into such an operation before it reaches here.
- A native resize becomes a `ResizeWindowOperation`. It writes the `width` and `height` cells, and because those cells are the exact range of the content, the content lays out again with no new projection.
- A native close removes the window.
- A window with `auto_dismiss` closes on its own loss of focus, on a `MouseDown` in another window, and on a bare Escape. The press goes on to its window, so a press on another menu name closes the open menu and opens its own. The Escape goes no further: the answer is `DoNothingOperation`, because the editor quits on an Escape that no reader answers.
- A `:popup` never holds the focus, so it also closes when any other window loses the focus, for example when the person switches to another program.
- While a `modal` window is open, an event for another window stops here.

The projection changes only the input screen. `ScreenToScreen` then updates the output.

**A window operation that reaches the editor opens the window too.** A wrapper outside the screen projection, such as the ones that keep the tooltip window and the context menu window, and a verb, such as `open_file_dialog!`, answer an `OpenWindowOperation` or a `CloseWindowOperation` that passes no window manager. `evaluate_operation` applies it to the screen that the editor's document wraps (`get_wrapped_document`), with the same code as the window manager.

### The shape of the pointer during a drag

`ScreenDocument.pointer_shape` is the shape that the pointer keeps over every window while a part says one, or `nothing`. It is view state, so a history does not record it.

- A part says the shape of its drag with `ChangeScreenPointerShapeOperation(shape)` at the start of the drag, and gives it back with `ChangeScreenPointerShapeOperation(nothing)` at its `DragEnd` and its `DragCancel`. `make_screen_pointer_shape_operation(shape)` makes the operation marked with `ReplaceViewStateOperation`, so a history below the screen does not record it either.
- `WindowManagingProjection` takes the operation on the way up, bare or marked, also inside a `CompoundOperation`, and answers a view state write of `pointer_shape` of its input screen instead. One that reaches the editor applies to the screen that the editor's document wraps, as a window operation does.
- `ScreenToScreen` draws, in the canvas of each window, a `GraphicsPointerShape` of that shape after the content, far past the edges of the window. So it is the last region at every point of every window, also at a point outside a window that holds the pressed button, and a backend shows its shape there with no code of its own. While the screen keeps no shape, the region has no size.
- **The safety net.** A part that is gone before its drag ends, such as a slider in a window that closes during the drag, never answers its `DragEnd`. So the window manager also sets the shape back at a release, or at a move with no button held, while the screen keeps one.

The parts that say a shape are listed in [widget.md](../widget/widget.md#the-shape-of-the-pointer) and [pane.md](../pane/pane.md). No projection reads or changes the output of another one for it: the part says the shape, and the screen keeps it.

### The place of a part

`find_part_place(projection, iomap, source)` answers where a window that a command opens at a part stands: the bottom left corner of the box of the node that draws the part, in screen coordinates, or `nothing` when the part has no image. `source` is a reference from the input of `iomap`, a screen. The part is mapped forward with the type of each node on its reference, and the box is read from the printed output with `find_reference_box` ([reference.md](../../kernel/reference.md), "The place of a part"). The tooltip window and the context menu window open a window that has no point there, 4 pixels lower, so the window stands below the part and does not cover it.

### The layers of a window

A wrapper at the screen that keeps one window, such as the tooltip window and the context menu window, collects layers: what the part under the pointer and the parts around it answered, the nearest first. Its window shows the first ones. The state document of the wrapper has the fields `layers`, `shown` (how many layers show, `0` when the window is closed) and `window` (the `OpenWindowOperation` that opened the window last).

- `show_window_layers(state, count, make_content)` opens the window again in its place with the first `count` layers, when that is another count. `make_content(layers, shown)` makes what the window holds. A view state operation writes `shown` and `window`, so a history does not record it.
- `make_window_layer_bindings(make_content; domain)` gives the two keys of such a window: F2 shows one more layer, and Shift+F2 one fewer. A wrapper declares them in the gesture table of its state, so the gesture help lists them, and they apply only while the window is open.

### One window on one document

`make_window_scene(document, title)` makes a screen with one window. `make_window_scene_projection(projection)` makes the matching projection, and it decides by the place of the content before its type: the content of the first window always goes through `projection`, and only the content of a window opened later goes through the projection of its content type, from `opened_window_projections`. So an entry of `opened_window_projections` for a type that the first window's content also has, such as a widget, draws only the windows that open later.

`show_document!(document; title)` shows a document in the editor that runs the code, or in the editor that the keyword `editor` names. It asks the content of the first window, looked through with `get_wrapped_document`: the chrome of the `shell` wrapper, the clipboard of the `clipboard` wrapper and the history of the `undo` wrapper each wrap the pane tree and are looked through in turn, so a document opens in the tabs inside them. A package that gives a container adds a method of `show_document!(editor, content, document; title)` for the type of its container, as the pane package does for its tabs; the verb calls it with its editor. With no such method, the document opens in a window of its own, beside the first window and as large as it, and a document that a window shows already opens no second window.

The wrapper `window` of `build_editor` builds both. It is on by default, and it puts the root document in one window when the backend draws windows. It puts the functions of `EditorParts.window_wrappers` that the other wrappers give, such as the `tooltip` and `context_menu` wrappers, around the screen inside the trackers, before the `inner_wrappers` of its argument. Its argument `(; title, width, height, opened_window_projections, inner_wrappers)` names the window, gives its size, which defaults to the display, and adds rows for the windows that open later: `opened_window_projections` puts the host's own rows in front of the rows that the other wrappers of the same `build_editor` call already added, because a row matches by the first type that the document is, so the host decides first. It does nothing with no backend, such as the parts that `make_editor_parts` makes for a caller that gives none. It also does nothing when the root is a `ScreenDocument` already, or when the backend draws text. `window = false` turns it off, and `make_editor` applies no wrapper, so a caller that builds its own screen passes that screen.

## How it fits

The screen slice depends on the graphics slice for `PointReferenceStep` and on the collection slice. A `.pred` file builds `ScreenDocument` and `WindowDocument` by their names, so a saved user interface holds its windows. The slices that open a window of their own use it: tooltip, inspector, gesturehelp, and the popups, the context menu window and the dialogs of the widget slice. The SDL and web backends draw its output. See [popup-window.md](popup-window.md) for how a menu, a dropdown list, a dialog, a tooltip and a context menu each use this model to open a window of their own, beside or below the part they belong to.

## Design decisions

- **A window is a document.** The generic projections work on the window list, and only the window-specific parts are written by hand. See [plan/done/multiple-windows.md](../../../../plan/done/multiple-windows.md).
- **The window model is not in the kernel.** The kernel keeps the screen device, which is an input and output channel. The document of windows is drawing, so it is a package above graphics. See [plan/done/kernel-layered-architecture.md](../../../../plan/done/kernel-layered-architecture.md).
- **A resize writes cells.** The size cells are the available size of the content, so the write is the layout. See [plan/done/window-resize-relayout.md](../../../../plan/done/window-resize-relayout.md).
- **A popup is a real window, not a layer inside a window.** An overlay layer was the first design and was dropped. See [plan/done/widget-popup-overlay.md](../../../../plan/done/widget-popup-overlay.md).
- **Modality is routing.** A modal window stops input by the window id, so no widget needs a modal check.

## Usage

```julia
window = WindowDocument(; id = :main, title = "Demo", width = 800, height = 600, content = document)
screen = ScreenDocument([window])
run_editor!(document, projection; backend = SdlBackend(), window = (; title = "Demo"))
```

- Test: no package suite exists. The tooltip, popup, dialog, command palette, gesture help and native window tests use the package. `test_drag_pointer_shape()` (`test/platform/shell/DragPointerShapeTest.jl`) drives the drags of a divider, a slider and a tab through a real editor and checks the shape that each window shows, the safety net, the region in every window, and the step of the canvas of a window in the reference map.

## Limits

- `_prefix_op` in `source/platform/screen/ScreenToScreen.jl` lists the operation types that carry a path. A new operation type with a path must be added to that list, or its path stays relative to the window and is applied to the screen.
- The code expects at most one modal window at a time and does not check it.
