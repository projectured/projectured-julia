# Fragment of `EventModule` — the mouse events, and the set of mouse buttons that a
# pointer event holds.
#
# An event source that reads the pointer reports the events `MouseDown`, `MouseUp`,
# `MouseMove` and `MouseScroll`. The gesture layer finds the gestures of the mouse
# in them.

"""
    MouseButtons(; left = false, middle = false, right = false)
    MouseButtons(names::Symbol...)

The mouse buttons that are held: one flag for each of `left`, `middle` and `right`.
A person can hold more than one button at the same time.

Use it to state or test which buttons a pointer event holds.

# Example

    MouseButtons()                  # no button
    MouseButtons(:left)             # the left button
    MouseButtons(:left, :right)     # the left and the right button
    move = MouseMove(10, 20, MouseButtons(:left), ModifierKeys(); time = 0.0)
    move.buttons.left               # true

See also `MouseMove`, which holds one.
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
    MouseDown(button, x, y[, modifiers]; time)
    MouseDown(button, x, y, modifiers, time)

A mouse button went down. `button` is `:left`, `:middle` or `:right`, `x` and `y`
are the coordinates in the window in logical pixels, and `time` is the time of the
input (see `Event`).

A backend reports no `MouseDown` and no `MouseUp` for a button that has no name here,
such as a side button of the mouse.
"""
struct MouseDown <: Event
    button::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

MouseDown(button::Symbol, x::Int, y::Int; time::Real) =
    MouseDown(button, x, y, ModifierKeys(), Float64(time))
# @positional: the four of a mouse event, in the order every backend sends them.
MouseDown(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseDown(button, x, y, modifiers, Float64(time))

"""
    MouseUp(button, x, y[, modifiers]; time)
    MouseUp(button, x, y, modifiers, time)

A mouse button went up. It has the fields of `MouseDown`.
"""
struct MouseUp <: Event
    button::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

MouseUp(button::Symbol, x::Int, y::Int; time::Real) =
    MouseUp(button, x, y, ModifierKeys(), Float64(time))
# @positional: the four of a mouse event, in the order every backend sends them.
MouseUp(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseUp(button, x, y, modifiers, Float64(time))

"""
    MouseMove(x, y[, buttons, modifiers]; time)
    MouseMove(x, y, buttons, modifiers, time)

The pointer moved. `x` and `y` are the coordinates in the window in logical pixels,
`buttons` is the `MouseButtons` that are held, and `time` is the time of the input.
"""
struct MouseMove <: Event
    x::Int
    y::Int
    buttons::MouseButtons
    modifiers::ModifierKeys
    time::Float64
end

MouseMove(x::Int, y::Int; time::Real) =
    MouseMove(x, y, MouseButtons(), ModifierKeys(), Float64(time))
# @positional: the fields of a pointer event, in the order every backend sends them.
MouseMove(x::Int, y::Int, buttons::MouseButtons, modifiers::ModifierKeys; time::Real) =
    MouseMove(x, y, buttons, modifiers, Float64(time))

"""
    is_move_without_button(event) -> Bool

Whether `event` is a move of the pointer with no button held. While a drag is on,
such a move shows a release that the window did not get, so the drag ends with no
change.
"""
is_move_without_button(event) = event isa MouseMove && event.buttons == MouseButtons()

"""
    MouseScroll(dx, dy, x, y[, modifiers]; time)
    MouseScroll(dx, dy, x, y, modifiers, time)

The mouse wheel turned. `dx` and `dy` are the amounts of the turn. A positive `dy` is
a turn of the wheel away from the user, which scrolls up, and a positive `dx` is a
scroll to the right, as SDL and the web page send them. `x` and `y` are the position
of the pointer, and `time` is the time of the input.
"""
struct MouseScroll <: Event
    dx::Int
    dy::Int
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

# @positional: the four of a scroll event, in the order every backend sends them.
MouseScroll(dx::Int, dy::Int, x::Int, y::Int; time::Real) =
    MouseScroll(dx, dy, x, y, ModifierKeys(), Float64(time))
# @positional: the fields of a scroll event, in the order of the struct.
MouseScroll(dx::Int, dy::Int, x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseScroll(dx, dy, x, y, modifiers, Float64(time))

get_modifier_keys(event::Union{MouseDown,MouseUp,MouseMove,MouseScroll}) = event.modifiers
