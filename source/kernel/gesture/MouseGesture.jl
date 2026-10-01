# Fragment of `GestureModule` — the gestures of the mouse: `MouseClick`, a completed
# click, from a down and an up; `MouseDwell`, from a pointer that does not move;
# and `DragMove`, `DragEnd` and `DragCancel`, the parts of a drag that the part
# whose drag is on reads.

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

"""
    DragMove(x, y[, modifiers]; time)
    DragMove(x, y, modifiers, time)

A move of the pointer with a button held, for the part whose drag is on. The code
that tracks a drag makes it from a `MouseMove` and sends it by the path of that
part, wherever the pointer is, so `x` and `y` are in the frame of the part. A part
reads its drag only from `DragMove`, `DragEnd` and `DragCancel`; the `MouseMove`
goes by position, as for every part.
"""
struct DragMove <: Gesture
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

DragMove(x::Int, y::Int; time::Real) = DragMove(x, y, ModifierKeys(), Float64(time))
# @positional: the position and the keys of a pointer event.
DragMove(x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    DragMove(x, y, modifiers, Float64(time))

"""
    DragEnd(x, y[, modifiers]; time)
    DragEnd(x, y, modifiers, time)

The release of the button of a drag, for the part whose drag is on, with `x` and
`y` in the frame of the part. The drag ends, and the part keeps what the drag did.
The code that tracks a drag makes it from the `MouseUp` and sends it by the path
of the part, as a `DragMove`.
"""
struct DragEnd <: Gesture
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

DragEnd(x::Int, y::Int; time::Real) = DragEnd(x, y, ModifierKeys(), Float64(time))
# @positional: the position and the keys of a pointer event.
DragEnd(x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    DragEnd(x, y, modifiers, Float64(time))

get_modifier_keys(gesture::Union{DragMove,DragEnd}) = gesture.modifiers

"""
    DragCancel(; time)
    DragCancel(time)

The end of a drag with no change, for the part whose drag is on. The code that
tracks a drag makes it from Escape, from the loss of the focus of the window, and
from a move with no button held, which shows a release that the window did not
get. The part puts back what it kept at the start of the drag.
"""
struct DragCancel <: Gesture
    time::Float64
end

DragCancel(; time::Real) = DragCancel(Float64(time))
