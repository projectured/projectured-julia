# Fragment of `EventModule` — the mouse events.
#
# `MouseDown`, `MouseUp`, `MouseMove` and `MouseScroll` are reported by a
# backend polling the pointer. `MousePress` (a completed click) is synthesised
# from a down/up pair, and `MouseEnter`/`MouseLeave` from motion crossing a
# region boundary; both kinds are matched the same way by whoever reads them.

"""
    MouseDown(button, x, y[, modifiers])

Raw button-down event. `button` is `:left`, `:middle`, or `:right`.
`x`/`y` are pixel coordinates relative to the window.
"""
struct MouseDown <: DeviceEvent
    button::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
end

MouseDown(button::Symbol, x::Int, y::Int) = MouseDown(button, x, y, ModifierKeys())

"""
    MouseUp(button, x, y[, modifiers])

Raw button-up event. Same fields as `MouseDown`.
"""
struct MouseUp <: DeviceEvent
    button::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
end

MouseUp(button::Symbol, x::Int, y::Int) = MouseUp(button, x, y, ModifierKeys())

"""
    MousePress(button, x, y[, count][, modifiers])

Synthesised click event: a `MouseUp` that landed at approximately the same
position as the preceding `MouseDown` for the same button, within a short time
window. A consumer that wants "select on click" semantics matches `MousePress`
rather than `MouseDown`.

`count` is the consecutive-click count for multi-click recognition: `1` for a
single click, `2` for a double-click, `3` for a triple-click, … It defaults to
`1`, so a plain `MousePress(:left, x, y)` is an ordinary single click and a
consumer that ignores `count` matches every click.
"""
struct MousePress <: SyntheticEvent
    button::Symbol
    x::Int
    y::Int
    count::Int
    modifiers::ModifierKeys
end

# Convenience constructors default the multi-click count to 1. The `::ModifierKeys`
# form disambiguates from the 5-arg primary by argument type.
MousePress(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys) =
    MousePress(button, x, y, 1, modifiers)
MousePress(button::Symbol, x::Int, y::Int) =
    MousePress(button, x, y, 1, ModifierKeys())

"""
    MouseMove(x, y[, buttons, modifiers])

Cursor-motion event. `buttons` is the currently-held button (`:none`, `:left`,
`:middle`, or `:right`; first held button wins when several are pressed).
`x`/`y` are pixel coordinates relative to the window.
"""
struct MouseMove <: DeviceEvent
    x::Int
    y::Int
    buttons::Symbol
    modifiers::ModifierKeys
end

MouseMove(x::Int, y::Int) = MouseMove(x, y, :none, ModifierKeys())

"""
    MouseEnter(x, y[, buttons, modifiers])

Pointer-enter event: the pointer crossed into a region. Same fields as
`MouseMove`. Synthesised from motion by whoever tracks the region, not reported
by a backend.
"""
struct MouseEnter <: SyntheticEvent
    x::Int
    y::Int
    buttons::Symbol
    modifiers::ModifierKeys
end

MouseEnter(x::Int, y::Int) = MouseEnter(x, y, :none, ModifierKeys())

"""
    MouseLeave(x, y[, buttons, modifiers])

Pointer-leave event: the pointer crossed out of a region. Same fields as
`MouseMove`; `x`/`y` are the last position that was inside the region being left.
"""
struct MouseLeave <: SyntheticEvent
    x::Int
    y::Int
    buttons::Symbol
    modifiers::ModifierKeys
end

MouseLeave(x::Int, y::Int) = MouseLeave(x, y, :none, ModifierKeys())

"""
    MouseScroll(dx, dy, x, y[, modifiers])

Mouse-wheel event. `dx`/`dy` are scroll deltas (positive = right/down).
`x`/`y` are the cursor position at the time of the scroll.
"""
struct MouseScroll <: DeviceEvent
    dx::Int
    dy::Int
    x::Int
    y::Int
    modifiers::ModifierKeys
end

MouseScroll(dx::Int, dy::Int, x::Int, y::Int) = MouseScroll(dx, dy, x, y, ModifierKeys())

get_modifiers(event::Union{MouseDown,MouseUp,MousePress,MouseMove,
                           MouseEnter,MouseLeave,MouseScroll}) = event.modifiers
