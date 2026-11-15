# Popup window

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [screen.md](screen.md), [graphics.md](../graphics/graphics.md)

A popup window is a window that is not the main view of the editor: a menu, the
list of a select, a dialog, a tooltip and a context menu each open in one,
beside or below the part they belong to. This document describes how such a
window opens, where it stands, how it closes, and the layer mechanism that the
tooltip window and the context menu window share.

## How it works

### A popup is a real window

[`PAR-MANY-WINDOWS`](../../../rule/architecture-invariants.md#par-many-windows)
requires every backend to open every window the screen holds, so a popup is
never a layer drawn over the window underneath it. Each kind opens with its
own `style`, a field of `WindowDocument` ([screen.md](screen.md)):

| Window | Opened by | `style` |
| --- | --- | --- |
| A submenu of a menu item | `WidgetMenuItem`'s own reader | `:popup` |
| The list of a `WidgetSelect` | `WidgetSelect`'s own reader | `:popup` |
| A context menu | `ContextMenuWindowProjection` | `:popup` |
| A tooltip | `TooltipWindowProjection` | `:tooltip` |
| A `WidgetDialog` | the dialog's own button | `:dialog` |

### Three ways to open one

- **Through `OpenPopupOperation(; id, x, y, anchor_size, gap, width,
  height, auto_dismiss, content)`.** A reader inside a widget answers it with
  the box of its control, `(x, y)` at `(0, 0)` in its own frame and
  `anchor_size` its size, and the `gap` below it. The reader wraps it
  in `ReplaceViewStateOperation` so a history does not record it. Each
  reader on the way up moves the box into its own frame with
  `map_operation_position`, the mechanism every operation with a point uses
  ([graphics.md](../graphics/graphics.md#moving-the-position-an-operation-carries)).
  It moves both corners, so a zoomed pane gives the box its drawn size; the
  gap stays in window pixels. The operation stays self-contained on purpose, so
  it passes through every view, also one that makes the part.
  `ScreenToScreen` turns the result into an `OpenWindowOperation` with `style =
  :popup`, a `maximum_size` of the width and the height the popup asked for,
  and a placement, and drops the `ReplaceViewStateOperation` mark, which an
  `OpenWindowOperation` does not need. The placement reads the place of the
  window where the screen prints it, so the popup follows its window. A submenu of a `WidgetMenuItem` and the dropdown list of a
  `WidgetSelect` both open this way.
- **Directly, with `OpenWindowOperation`.** A wrapper that already has the
  screen position builds it itself. The tooltip window and the context menu
  window are wrappers that sit around the whole screen, inside the gesture
  tracker ([gesturetracking.md](../gesturetracking/gesturetracking.md)), so
  they give the window a placement that reads the point of the gesture that
  opened them, or [where the part stands](#where-it-stands) when there is no
  point. A `WidgetDialog` answers an `OpenWindowOperation` the same way, from
  the button that opens it, with `modal = true` and the automatic place.
- **With a `placement`.** A window that carries a `placement` function takes
  its place from it, and follows what the function reads
  ([screen.md](screen.md#the-placement-of-a-window)).

### Where it stands

Every popup window stands where a placement puts it, and follows what the
placement reads when that moves. The command palette and the search of a file by
its name open at the top center of the window
([context-menu.md](../widget/context-menu.md#a-list-that-a-person-types-into)).
The other windows use one helper of the screen slice,
`compute_anchored_place(context, anchor; side, gap)`
([screen.md](screen.md#the-placement-of-a-window)):

| Window | Its place |
| --- | --- |
| Tooltip | `offset` below and right of the point, above the point when there is no room below, so it never covers the point; with no point, below the part, `part_gap` under it |
| Right-click menu | below and right of the point; with no point, below the part, `item_gap` under it; a placement of its own operation, such as the top placement of the palette, wins |
| Submenu of a menu item, list of a `WidgetSelect` | below the box of the control, with the left edges aligned |
| Dialog at the automatic place | at the center of the window whose content opened it |

The helper reads the usable area of each display from `display_areas` of the
screen, which the backend writes, and the size that the backend fitted to the
content. The backend fits the size before it reads the place, so the place is
right in the first frame. A window below its box that crosses the bottom edge of
the area flips above the box; when the top has no room either, it slides inside
the area. On every other edge it slides inside the area. A backend that writes
no areas, such as the headless backend and the web backend, leaves
`display_areas` empty, and then a placement keeps its place.

A dialog is a window of the style `:floating` or `:dialog`. A dialog at the
automatic place `(-1, -1)` with no placement stands at the center of the window
whose content opened it (`make_window_center_placement`). A dialog that a callback opens, such
as the Open file dialog and the "Filter by values" lists, stands at the center of
the first window of the screen. A normal window at the automatic place, as the
main window, stays the backend's to place.

A person who moves or resizes a placed window with a frame
(`has_window_frame`: every style except `:popup` and `:tooltip`) gives it
`make_fixed_placement` at the place where it stands, so it stays there.

### How it closes

`auto_dismiss = true` makes `WindowManagingProjection` close a window: on its
own loss of focus, on a `MouseDown` in another window, and on a bare Escape,
whose answer is `DoNothingOperation`, so the editor itself does not quit on it.
A `:popup` window never takes the focus, so it also closes on the loss of the
focus of any window. A submenu, a select's dropdown list and the context menu
window all close this way. A choice in a menu closes the popup in the same
operation that runs the choice: a `CompoundOperation` of the action and
`CloseWindowOperation` of the popup's id, `:widget_popup`.

A window that opens with a `selection`, a place in its content
(`OpenWindowOperation`), takes the selection there, and keeps the selection that
the screen had before (`selection_before`). The command palette opens so, with the
selection at the end of its typed text. When the window closes while it holds the
selection, the window manager gives the kept selection back, in every way that a
popup closes. The give-back comes first in the answer, so a selection that the
same answer makes, such as the one of a press in another window or of a choice,
comes after it and wins.

The tooltip window carries no `auto_dismiss`; it closes by its own rule
instead, inside the reader of `TooltipWindowProjection`: a move whose point
leaves the part, Escape, a press, a scroll, and the leave of a window each
close it directly with `CloseWindowOperation`. See
[tooltip.md](../tooltip/tooltip.md).

A `WidgetDialog` is `modal = true`: while it is open,
`WindowManagingProjection` stops an event meant for another window before it
reaches one. A button of the dialog closes it, in the same `CompoundOperation`
as the action the button runs; a click on the backdrop around the card closes
it the same way.

### The layers a wrapper keeps

The tooltip window and the context menu window both collect layers, the
nearest part first, and show the first few, through
[the layer helper of the screen slice](screen.md#the-layers-of-a-window):
`show_window_layers` reopens the window where it already stands with another
count of layers, and `make_window_layer_bindings` gives it F2 and Shift+F2,
each declared in the gesture table of the wrapper's own state, so the gesture
help lists them only while the window is open. Both functions live in
`source/platform/screen/WindowLayers.jl`, which this slice owns so that two
otherwise unrelated wrappers, one for a dwell and one for a right click, grow
and shrink their window the same way.

## How it fits

This document, `WindowPlacement.jl` and `WindowLayers.jl` are the screen slice,
beside `ScreenToScreen` and `WindowManagingProjection` of
[screen.md](screen.md). The widget slice answers `OpenPopupOperation` for a
menu's submenu and a select's dropdown list, and builds the `WidgetDialog`
window directly; the tooltip slice and the widget slice's context menu each
keep a wrapper around the screen that depends on `find_window_part_box`,
`compute_anchored_place` and the layer helper here. To give a window to a part of its own, a package reuses one
of the same two paths: answer `OpenPopupOperation` from a reader inside the
part, or build an `OpenWindowOperation` from a wrapper that already holds the
screen position.

## Design decisions

- **A popup is a window, not a layer drawn over one.** `PAR-MANY-WINDOWS`
  requires every backend to open every window the screen holds, so a tooltip or
  a menu can extend past the edge of the window it describes, which a layer
  drawn inside that window could not do.
- **`OpenPopupOperation` carries a position relative to its own reader, not the
  screen.** A reader inside a widget has no reference to the screen or to where
  its own canvas ends up on it. Each reader on the way up moves the position
  into its own frame, with the mechanism that every operation with a point has.
- **The tooltip window and the context menu window are wrappers at the screen,
  not readers inside it.** A part cannot close its own tooltip once the pointer
  leaves it, and a window belongs to the screen. A wrapper outside the document
  tree, inside the gesture tracker, serves every window that the screen holds.
- **F2 and Shift+F2 are one mechanism, shared by both windows.** The two
  wrappers are alike enough — a list of layers, a count that is shown, a window
  that must reopen with new content at the same place — that `WindowLayers.jl`
  is the one place that grows or shrinks such a window.

## Usage

```julia
# Open a popup relative to a widget's own canvas:
ReplaceViewStateOperation(
    OpenPopupOperation(; id = :widget_popup, x = 0, y = 0,
                       anchor_size = (control_width, control_height),
                       gap = 0,
                       auto_dismiss = true, content = WidgetMenu(items)))

# A placement that puts a window below the box of a part:
context -> (box = find_window_part_box(context, part);
            box === nothing ? nothing : compute_anchored_place(context, box; gap = 4))
```

- Tests: `test_widget_popup_example()` opens the dropdown list of a
  `WidgetSelect` through a real screen and checks the window's screen position;
  `test_tooltip_window()` and `test_context_menu_window()` cover the two
  wrappers through a real editor.

## Limits

- A dialog that a callback opens stands over the first window of the screen,
  also when a person works in another window. The screen does not record which
  window has the focus.
- The web backend writes no areas, so it keeps each place that a placement asks
  for.
- A popup that is taller than the area of its display slides to the top of the
  area, and the part below the area is cut. A popup does not get smaller to fit.
- An editor with `tooltip = false` or `context_menu = false`, or a host that
  calls `make_tracking_screen` with no wrapper for that window, gets no such
  window: the operation that would open one reaches the editor, which does
  nothing with it.
