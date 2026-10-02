# Popup window

> **Kind:** design · **Status:** current · **Stands on:** [screen.md](screen.md), [graphics.md](../graphics/graphics.md)

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

### Two ways to open one

- **Through `OpenPopupOperation(; id, x, y, width, height, auto_dismiss,
  content)`.** A reader inside a widget answers it relative to its own frame,
  wrapped in `ReplaceViewStateOperation` so a history does not record it. Each
  reader on the way up moves `(x, y)` into its own frame with
  `map_operation_position`, the mechanism every operation with a point uses
  ([graphics.md](../graphics/graphics.md#moving-the-position-an-operation-carries)).
  `ScreenToScreen` turns the result into an `OpenWindowOperation` with `style =
  :popup`, a `maximum_size` of the width and the height the popup asked for,
  and the window's own screen origin added, and drops the
  `ReplaceViewStateOperation` mark, which an `OpenWindowOperation` does not
  need. A submenu of a `WidgetMenuItem` and the dropdown list of a
  `WidgetSelect` both open this way.
- **Directly, with `OpenWindowOperation`.** A wrapper that already has the
  screen position builds it itself. The tooltip window and the context menu
  window are wrappers that sit around the whole screen, inside the gesture
  tracker ([gesturetracking.md](../gesturetracking/gesturetracking.md)), so
  they compute the position from the point of the gesture that opened them, or
  from [where it stands](#where-it-stands) when there is none. A `WidgetDialog`
  answers an `OpenWindowOperation` the same way, from the button that opens it,
  with `modal = true` and a fixed box.

### Where it stands

With a point, the window stands at that point (a right click), or offset from
it (a tooltip, by the `offset` keyword of `TooltipWindowProjection`). A
submenu and a select's dropdown list carry a position in the control's own
frame, and `map_operation_position` turns it into a screen position container
by container, on the way up, the same as any operation with a point
([screen.md](screen.md#screentoscreen)).

With no point, as when a command runs a binding with no pointer, the tooltip
window and the context menu window open below the part instead, a few pixels
lower, at [the place of a part](screen.md#the-place-of-a-part) that
`find_part_place` answers.

### How it closes

`auto_dismiss = true` makes `WindowManagingProjection` close a window: on its
own loss of focus, on a `MouseDown` in another window, and on a bare Escape,
whose answer is `DoNothingOperation`, so the editor itself does not quit on it.
A `:popup` window never takes the focus, so it also closes on the loss of the
focus of any window. A submenu, a select's dropdown list and the context menu
window all close this way. A choice in a menu closes the popup in the same
operation that runs the choice: a `CompoundOperation` of the action and
`CloseWindowOperation` of the popup's id, `:widget_popup`.

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

This document, `PartPlace.jl` and `WindowLayers.jl` are the screen slice,
beside `ScreenToScreen` and `WindowManagingProjection` of
[screen.md](screen.md). The widget slice answers `OpenPopupOperation` for a
menu's submenu and a select's dropdown list, and builds the `WidgetDialog`
window directly; the tooltip slice and the widget slice's context menu each
keep a wrapper around the screen that depends on `find_part_place` and the
layer helper here. To give a window to a part of its own, a package reuses one
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
    OpenPopupOperation(; id = :widget_popup, x = 0, y = control_height,
                       auto_dismiss = true, content = WidgetMenu(items)))

# Where a command with no pointer should open a window below a part:
below = find_part_place(projection, iomap, source)
x, y = below === nothing ? (0, 0) : (below[1], below[2] + 4)
```

- Tests: `test_widget_popup_example()` opens the dropdown list of a
  `WidgetSelect` through a real screen and checks the window's screen position;
  `test_tooltip_window()` and `test_context_menu_window()` cover the two
  wrappers through a real editor.

## Limits

- A `WidgetDialog` opens at a fixed box, `x = 80, y = 60, width = 480, height =
  320`; it is not placed in the middle of the real window, only the card
  inside it is centered in that box.
- An editor with `tooltip = false` or `context_menu = false`, or a host that
  calls `make_tracking_screen` with no wrapper for that window, gets no such
  window: the operation that would open one reaches the editor, which does
  nothing with it.
