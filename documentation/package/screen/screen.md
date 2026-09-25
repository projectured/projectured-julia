# Screen

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../kernel/devices-and-backends.md), [graphics.md](../graphics/graphics.md)

`ProjecturedScreen` holds the window model: a screen document with a list of windows, the projection that maps it, and the projection that opens, closes and resizes windows. A backend shows the output screen as native windows. [devices-and-backends.md](../kernel/devices-and-backends.md) describes the backend side; this document describes the document side.

## How it works

`ScreenDocument` has one field, `windows`, a `CellVector` of `WindowDocument`. `OpenWindowOperation` and `OpenPopupOperation` request that a window opens, and their fields mirror those of `WindowDocument`. `OpenPopupOperation(; id, x, y, width, height, auto_dismiss, content)` carries `(x, y)`, the top left of the popup, in the frame of the reader that holds it. A reader on the way up moves that position into its own frame; [graphics.md](../graphics/graphics.md#moving-the-position-an-operation-carries) describes how. A `WindowDocument` has:

- `id`, a `Symbol`. The backend keeps one native window for each id, from frame to frame.
- `title`, `x`, `y`, `width`, `height`. A position of `-1` lets the backend choose, and a size of `0` sizes the window to its content.
- `minimum_size` and `maximum_size`, the bounds of a window that fits what it holds. A maximum of `(0, 0)`, the default, is a window of a fixed size, and that is every window but a tooltip today.
- `style`: `:normal`, `:tooltip`, `:floating` or `:popup`. The backend applies the behaviour of each style. A `:popup` is a menu or a dropdown list, and it never takes the focus: the keyboard stays in the window under it. A `:floating` window, such as a dialog, takes the focus.
- `auto_dismiss`: the window is a transient popup, which closes when the pointer or the keyboard acts elsewhere, as a menu does. `WindowManagingProjection` lists the events that close it.
- `modal`: while the window is open, no other window gets input.
- `content`, any document. The projection chain goes into this field only.

The screen is data like any other document. To open a window, a program adds a `WindowDocument` to `windows`. To close one, it removes it. The backend compares the output screen with its native windows on each frame. No `open_window!` call exists.

### ScreenToScreen

`ScreenToScreen` maps the input screen to the output screen. It copies the metadata of each window and sends `content` through the projection of the caller. It sets the `width` and `height` of the window as the size available to the content, so a split pane or a scroll pane fills the window. **A window that fits is offered its `maximum_size` instead, always.** The backend gives such a window the extent of the canvas it printed, so an offer that followed that size would chase it: a text wraps at the maximum width, and the window ends as wide as the text needed. [sdl.md](../sdl/sdl.md) describes the backend half.

It keeps the IO map of each window by identity (`reconcile_child_iomaps`). So a window that opens or closes does not rebuild the other windows, and a new content in a window with the same id replaces the old content in place.

Its reference map is where a window position becomes a screen position. A structural path gets the prefix `windows[i].content`. A `PointReferenceStep`, a pixel position inside the content, also gets the `x` and `y` of the window added.

Its reader routes a `WindowInput` event by the window id, not by the position in the list. It then adds the prefix `windows[i]` to the operation that comes back. When that operation is an `OpenPopupOperation` inside `ReplaceViewStateOperation`, it adds the window's own screen origin to the popup and turns it into an `OpenWindowOperation` with `style = :popup`, and drops the mark. The mark keeps a popup out of a history only above the window; below the window manager, a popup opens exactly as any other window does.

### WindowManagingProjection

`WindowManagingProjection` wraps `ScreenToScreen` and applies the window operations:

- `OpenWindowOperation` and `CloseWindowOperation` from any reader below, also inside a `CompoundOperation`. So the choice of an item in a menu can set a value and close the menu in one operation. `ScreenToScreen` already turned a popup into such an operation before it reaches here.
- A native resize becomes a `ResizeWindowOperation`. It writes the `width` and `height` cells, and because those cells are the exact range of the content, the content lays out again with no new projection.
- A native close removes the window.
- A window with `auto_dismiss` closes on its own loss of focus, on a `MouseDown` in another window, and on a bare Escape. The press goes on to its window, so a press on another menu name closes the open menu and opens its own. The Escape goes no further: the answer is `DoNothingOperation`, because the editor quits on an Escape that no reader answers.
- A `:popup` never holds the focus, so it also closes when any other window loses the focus, for example when the person switches to another program.
- While a `modal` window is open, an event for another window stops here.

The projection changes only the input screen. `ScreenToScreen` then updates the output.

### One window on one document

`make_window_scene(document, title)` makes a screen with one window. `make_window_scene_projection(projection)` makes the matching projection, and it decides by the place of the content before its type: the content of the first window always goes through `projection`, and only the content of a window opened later goes through the projection of its content type, from `opened_window_projections`. So an entry of `opened_window_projections` for a type that the first window's content also has, such as a widget, draws only the windows that open later.

`make_editor(document, projection, title; backend)` builds both, makes the editor and prints it once. `run_window_editor(document, projection, title; backend)` is `make_editor` and then `run_editor!(editor)`. A caller with work to do before the loop, such as a driver to start or a pane to focus, calls the two itself and does its work between them.

## How it fits

`ProjecturedScreen` depends on `ProjecturedGraphics` for `PointReferenceStep` and on `ProjecturedCollection`. Its `__init__` registers `ScreenDocument` and `WindowDocument` as `.pred` types. The packages that open a window of their own use it: `ProjecturedTooltip`, `ProjecturedInspector`, `ProjecturedGestureHelp`, and the popups and dialogs of `ProjecturedWidget`. The SDL and web backends draw its output.

## Design decisions

- **A window is a document.** The generic projections work on the window list, and only the window-specific parts are written by hand. See [plan/done/multiple-windows.md](../../../plan/done/multiple-windows.md).
- **The window model is not in the kernel.** The kernel keeps the screen device, which is an input and output channel. The document of windows is drawing, so it is a package above graphics. See [plan/done/kernel-layered-architecture.md](../../../plan/done/kernel-layered-architecture.md).
- **A resize writes cells.** The size cells are the available size of the content, so the write is the layout. See [plan/done/window-resize-relayout.md](../../../plan/done/window-resize-relayout.md).
- **A popup is a real window, not a layer inside a window.** An overlay layer was the first design and was dropped. See [plan/done/widget-popup-overlay.md](../../../plan/done/widget-popup-overlay.md).
- **Modality is routing.** A modal window stops input by the window id, so no widget needs a modal check.

## Usage

```julia
window = WindowDocument(; id = :main, title = "Demo", width = 800, height = 600, content = document)
screen = ScreenDocument([window])
run_window_editor(document, projection, "Demo"; backend = SdlBackend())
```

- Test: no package suite exists. The tooltip, popup, dialog, command palette, gesture help and native window tests use the package.

## Limits

- `_prefix_op` in `source/screen/ScreenToScreen.jl` lists the operation types that carry a path. A new operation type with a path must be added to that list, or its path stays relative to the window and is applied to the screen.
- The code expects at most one modal window at a time and does not check it.
