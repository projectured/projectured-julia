# Fragment of `EventModule` — the mouse events, and the set of mouse buttons that a
# pointer event holds.
#
# An event source that reads the pointer reports `MouseDown`, `MouseUp`, `MouseMove`
# and `MouseScroll`. `MousePress`, a completed click, comes from a down and up pair,
# and `MouseEnter` and `MouseLeave` come from motion across the edge of a region.

"""
    MouseButtons(left, middle, right)
    MouseButtons(; left = false, middle = false, right = false)
    MouseButtons(names::Symbol...)

The mouse buttons that are held: one flag for each of `left`, `middle` and `right`.
A person can hold more than one button at the same time.

Use it to state or test which buttons a pointer event holds.

# Example

    MouseButtons()                  # no button
    MouseButtons(:left)             # the left button
    MouseButtons(:left, :right)     # the left and the right button
    MouseMove(10, 20, MouseButtons(:left), ModifierKeys()).buttons.left   # true

See also `MouseMove`, `MouseEnter` and `MouseLeave`, which hold one.
"""
struct MouseButtons
    left::Bool
    middle::Bool
    right::Bool
end

MouseButtons(; left::Bool = false, middle::Bool = false, right::Bool = false) =
    MouseButtons(left, middle, right)

function MouseButtons(names::Symbol...)
    for name in names
        name in (:left, :middle, :right) || throw(ArgumentError(
            "a mouse button is :left, :middle or :right, got :$name"))
    end
    MouseButtons(:left in names, :middle in names, :right in names)
end

"""
    MouseDown(button, x, y[, modifiers])

A mouse button went down. `button` is `:left`, `:middle` or `:right`, and `x` and
`y` are the pixel coordinates in the window.
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

A mouse button went up. It has the fields of `MouseDown`.
"""
struct MouseUp <: DeviceEvent
    button::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
end

MouseUp(button::Symbol, x::Int, y::Int) = MouseUp(button, x, y, ModifierKeys())

"""
    MousePress(button, x, y)
    MousePress(button, x, y, modifiers)
    MousePress(button, x, y, count, modifiers)

A click: a `MouseUp` near the position of the `MouseDown` before it, for the same
button, within a short time. A pattern that must fire on a click matches
`MousePress`, not `MouseDown`.

`count` is the number of clicks in a row: `1` for a single click, `2` for a double
click, `3` for a triple click. The forms without `count` give `1`, so a pattern
that does not name `count` matches every click.
"""
struct MousePress <: SyntheticEvent
    button::Symbol
    x::Int
    y::Int
    count::Int
    modifiers::ModifierKeys
end

# @positional: the four of a mouse event, in the order every backend sends them.
MousePress(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys) =
    MousePress(button, x, y, 1, modifiers)
MousePress(button::Symbol, x::Int, y::Int) =
    MousePress(button, x, y, 1, ModifierKeys())

"""
    MouseMove(x, y[, buttons, modifiers])

The pointer moved. `x` and `y` are the pixel coordinates in the window, and
`buttons` is the `MouseButtons` that are held.
"""
struct MouseMove <: DeviceEvent
    x::Int
    y::Int
    buttons::MouseButtons
    modifiers::ModifierKeys
end

MouseMove(x::Int, y::Int) = MouseMove(x, y, MouseButtons(), ModifierKeys())

"""
    MouseEnter(x, y[, buttons, modifiers])

The pointer crossed into a region. It has the fields of `MouseMove`. The code that
tracks the region makes it from the motion; an event source does not report it.
"""
struct MouseEnter <: SyntheticEvent
    x::Int
    y::Int
    buttons::MouseButtons
    modifiers::ModifierKeys
end

MouseEnter(x::Int, y::Int) = MouseEnter(x, y, MouseButtons(), ModifierKeys())

"""
    MouseLeave(x, y[, buttons, modifiers])

The pointer crossed out of a region. It has the fields of `MouseMove`, and `x` and
`y` are the last position inside the region.
"""
struct MouseLeave <: SyntheticEvent
    x::Int
    y::Int
    buttons::MouseButtons
    modifiers::ModifierKeys
end

MouseLeave(x::Int, y::Int) = MouseLeave(x, y, MouseButtons(), ModifierKeys())

"""
    MouseScroll(dx, dy, x, y[, modifiers])

The mouse wheel turned. `dx` and `dy` are the amounts, positive to the right and
down, and `x` and `y` are the position of the pointer.
"""
struct MouseScroll <: DeviceEvent
    dx::Int
    dy::Int
    x::Int
    y::Int
    modifiers::ModifierKeys
end

# @positional: the four of a scroll event, in the order every backend sends them.
MouseScroll(dx::Int, dy::Int, x::Int, y::Int) = MouseScroll(dx, dy, x, y, ModifierKeys())

get_modifier_keys(event::Union{MouseDown,MouseUp,MousePress,MouseMove,
                               MouseEnter,MouseLeave,MouseScroll}) = event.modifiers
