# Fragment of `GestureModule` — the gestures of the mouse: `MouseClick`, a completed
# click, from a down and an up; `MouseDwell`, from a pointer that does not move.

"""
    MouseClick(button, x, y[, modifiers]; time)
    MouseClick(button, x, y, count, modifiers; time)
    MouseClick(button, x, y, count, modifiers, time)

A click: a `MouseUp` near the position of the `MouseDown` before it, for the same
button, within a short time. A pattern that must fire on a click matches
`MouseClick`, not `MouseDown`. `time` is the time of the `MouseUp`.

`count` is the number of clicks in a row: `1` for a single click, `2` for a double
click, `3` for a triple click. The forms without `count` give `1`, so a pattern
that does not name `count` matches every click.
"""
struct MouseClick <: Gesture
    button::Symbol
    x::Int
    y::Int
    count::Int
    modifiers::ModifierKeys
    time::Float64
end

MouseClick(button::Symbol, x::Int, y::Int; time::Real) =
    MouseClick(button, x, y, 1, ModifierKeys(), Float64(time))
# @positional: the four of a mouse event, in the order every backend sends them.
MouseClick(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseClick(button, x, y, 1, modifiers, Float64(time))
# @positional: the fields of a click, in the order of the struct.
MouseClick(button::Symbol, x::Int, y::Int, count::Int, modifiers::ModifierKeys;
           time::Real) =
    MouseClick(button, x, y, count, modifiers, Float64(time))

"""
    MouseDwell(x, y[, modifiers]; time)
    MouseDwell(x, y, modifiers, time)

The pointer did not move for a short time. `x` and `y` are its position in the
window, `modifiers` are the keys held at its last motion, and `time` is when the
wait ended. A dwell does not depend on what is drawn under the pointer: a reader
finds the part at the position. The code that tracks the motion makes it; an
event source does not report it.
"""
struct MouseDwell <: Gesture
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

MouseDwell(x::Int, y::Int; time::Real) = MouseDwell(x, y, ModifierKeys(), Float64(time))
# @positional: the position and the keys of a pointer event.
MouseDwell(x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseDwell(x, y, modifiers, Float64(time))

get_modifier_keys(gesture::Union{MouseClick,MouseDwell}) = gesture.modifiers
