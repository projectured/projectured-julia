"""
    MouseModule

Backend-agnostic mouse event types. Projection readers work with these
structs and remain independent of any particular backend.

Five event types cover all mouse interactions:
- `MouseDown`   — raw button-press (fired immediately on button-down).
- `MouseUp`     — raw button-release.
- `MousePress`  — synthesised click: emitted when a `MouseUp` occurs at
                  approximately the same position as the preceding `MouseDown`
                  for the same button within a short time window. Synthesised by
                  the editor's `GestureRecognizer` (not the backend); carries a
                  multi-click `count` (1 = single, 2 = double, …). Projections
                  that want click-selection semantics dispatch on `MousePress`.
- `MouseMove`   — cursor motion, including the currently-held button (if any).
- `MouseScroll` — mouse-wheel event.

Two further events are **synthesised from motion** (not produced by the backend)
to express the pointer crossing a projection boundary — see
`WidgetHoverTrackingProjection`, which derives them from `MouseMove`:
- `MouseEnter`  — the pointer entered a region (a widget got the pointer).
- `MouseLeave`  — the pointer left a region (a widget lost the pointer).

All carry a `Modifiers` struct for the Ctrl/Shift/Alt state.
"""
module MouseModule

import ..DeviceModule: Device
import ..ModifiersModule: Modifiers

export Mouse, MouseDown, MouseUp, MousePress, MouseMove, MouseScroll, MouseEnter, MouseLeave

"""
    Mouse()

A mouse input device. Included among the `devices` passed to
`read_from_devices(backend, devices)` to poll for mouse events.
"""
struct Mouse <: Device end

"""
    MouseDown(button, x, y[, modifiers])

Raw button-down event. `button` is `:left`, `:middle`, or `:right`.
`x`/`y` are pixel coordinates relative to the window.
"""
struct MouseDown
    button::Symbol
    x::Int
    y::Int
    modifiers::Modifiers
end

MouseDown(button::Symbol, x::Int, y::Int) = MouseDown(button, x, y, Modifiers())

"""
    MouseUp(button, x, y[, modifiers])

Raw button-up event. Same fields as `MouseDown`.
"""
struct MouseUp
    button::Symbol
    x::Int
    y::Int
    modifiers::Modifiers
end

MouseUp(button::Symbol, x::Int, y::Int) = MouseUp(button, x, y, Modifiers())

"""
    MousePress(button, x, y[, count][, modifiers])

Synthesised click event. Emitted by the editor's `GestureRecognizer` when a
`MouseUp` occurs at approximately the same position as the preceding `MouseDown`
for the same button within a short time window (≤ 300 ms, ≤ 5 px displacement).
Projections that want "select on click" semantics should dispatch on
`MousePress` rather than `MouseDown`.

`count` is the consecutive-click count for multi-click recognition: `1` for a
single click, `2` for a double-click, `3` for a triple-click, … (a click counts
as a continuation of the previous one when it lands within the same short
window/displacement of the same button). It defaults to `1`, so a plain
`MousePress(:left, x, y)` is an ordinary single click and existing readers that
ignore `count` keep matching every click.
"""
struct MousePress
    button::Symbol
    x::Int
    y::Int
    count::Int
    modifiers::Modifiers
end

# Back-compat / convenience constructors default the multi-click count to 1.
# The `::Modifiers` form disambiguates from the 5-arg primary by argument type,
# so the many existing `MousePress(button, x, y, modifiers)` call sites are
# unaffected.
MousePress(button::Symbol, x::Int, y::Int, modifiers::Modifiers) =
    MousePress(button, x, y, 1, modifiers)
MousePress(button::Symbol, x::Int, y::Int) =
    MousePress(button, x, y, 1, Modifiers())

"""
    MouseMove(x, y[, buttons, modifiers])

Cursor-motion event. `buttons` is the currently-held button (`:none`,
`:left`, `:middle`, or `:right`; first held button wins when multiple
are pressed). `x`/`y` are pixel coordinates relative to the window.
"""
struct MouseMove
    x::Int
    y::Int
    buttons::Symbol
    modifiers::Modifiers
end

MouseMove(x::Int, y::Int) = MouseMove(x, y, :none, Modifiers())

"""
    MouseEnter(x, y[, buttons, modifiers])

Pointer-enter event: the pointer crossed into a region (e.g. a widget). Same
fields as `MouseMove`. Synthesised from motion by a hover tracker, not by the
backend; a widget reader translates it into its own hover state change.
"""
struct MouseEnter
    x::Int
    y::Int
    buttons::Symbol
    modifiers::Modifiers
end

MouseEnter(x::Int, y::Int) = MouseEnter(x, y, :none, Modifiers())

"""
    MouseLeave(x, y[, buttons, modifiers])

Pointer-leave event: the pointer crossed out of a region. Same fields as
`MouseMove`. Synthesised from motion by a hover tracker, not by the backend;
`x`/`y` are the last position that was inside the region being left.
"""
struct MouseLeave
    x::Int
    y::Int
    buttons::Symbol
    modifiers::Modifiers
end

MouseLeave(x::Int, y::Int) = MouseLeave(x, y, :none, Modifiers())

"""
    MouseScroll(dx, dy, x, y[, modifiers])

Mouse-wheel event. `dx`/`dy` are scroll deltas (positive = right/down).
`x`/`y` are the cursor position at the time of the scroll.
"""
struct MouseScroll
    dx::Int
    dy::Int
    x::Int
    y::Int
    modifiers::Modifiers
end

MouseScroll(dx::Int, dy::Int, x::Int, y::Int) = MouseScroll(dx, dy, x, y, Modifiers())

end # module
