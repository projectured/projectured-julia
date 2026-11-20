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
MouseClick(button::Symbol, x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseClick(button, x, y, 1, modifiers, Float64(time))
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
MouseDwell(x::Int, y::Int, modifiers::ModifierKeys; time::Real) =
    MouseDwell(x, y, modifiers, Float64(time))

get_modifier_keys(gesture::Union{MouseClick,MouseDwell}) = gesture.modifiers

"""
    DragMove(x, y[, modifiers]; time, outside = false)
    DragMove(x, y, modifiers, time[, outside])

A move of the pointer with a button held, for the part whose drag is on. The code
that tracks a drag makes it from a `MouseMove` and sends it by the path of that
part, wherever the pointer is, so `x` and `y` are in the frame of the part. A part
reads its drag only from `DragMove`, `DragEnd` and `DragCancel`; the `MouseMove`
goes by position, as for every part.

`outside` is `true` when the pointer is outside every window of the editor, so a
part can show what a release there would do.
"""
struct DragMove <: Gesture
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
    outside::Bool
end

DragMove(x::Int, y::Int, modifiers::ModifierKeys, time::Real) =
    DragMove(x, y, modifiers, Float64(time), false)
DragMove(x::Int, y::Int; time::Real, outside::Bool = false) =
    DragMove(x, y, ModifierKeys(), Float64(time), outside)
DragMove(x::Int, y::Int, modifiers::ModifierKeys; time::Real, outside::Bool = false) =
    DragMove(x, y, modifiers, Float64(time), outside)

"""
    DragEnd(x, y[, modifiers]; time, outside = false)
    DragEnd(x, y, modifiers, time[, outside])

The release of the button of a drag, for the part whose drag is on, with `x` and
`y` in the frame of the part. The drag ends, and the part keeps what the drag did.
The code that tracks a drag makes it from the `MouseUp` and sends it by the path
of the part, as a `DragMove`.

`outside` is `true` when the release is outside every window of the editor, where
no window got a [`DragDrop`](@ref).
"""
struct DragEnd <: Gesture
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
    outside::Bool
end

DragEnd(x::Int, y::Int, modifiers::ModifierKeys, time::Real) =
    DragEnd(x, y, modifiers, Float64(time), false)
DragEnd(x::Int, y::Int; time::Real, outside::Bool = false) =
    DragEnd(x, y, ModifierKeys(), Float64(time), outside)
DragEnd(x::Int, y::Int, modifiers::ModifierKeys; time::Real, outside::Bool = false) =
    DragEnd(x, y, modifiers, Float64(time), outside)

get_modifier_keys(gesture::Union{DragMove,DragEnd}) = gesture.modifiers

"""
    DragOver(x, y, dragged; time)
    DragOver(x, y, dragged, time)

The pointer of a drag that carries `dragged` is at `(x, y)`, for the parts under
the pointer. The code that tracks a drag makes it from a `MouseMove` and sends it
by position to the window under the pointer, so it reaches the parts there as a
move does, with `x` and `y` in the frame of each part. A part that takes `dragged`
keeps where it would land and shows it; the others ignore it.

`DragOver(-1, -1, dragged)` says that the pointer left: the window that got the
last `DragOver` gets it when the pointer goes to another window or outside, and
when the drag ends, so a part puts away what it showed.
"""
struct DragOver <: Gesture
    x::Int
    y::Int
    dragged::Any
    time::Float64
end

DragOver(x::Int, y::Int, dragged; time::Real) = DragOver(x, y, dragged, Float64(time))

"""
    DragDrop(x, y, dragged[, modifiers]; time)
    DragDrop(x, y, dragged, modifiers, time)

The release of a drag that carries `dragged`, at `(x, y)`, for the parts under the
pointer. The code that tracks a drag makes it from the `MouseUp` and sends it by
position to the window under the pointer, as a [`DragOver`](@ref). A part that
takes `dragged` answers with what the drop does there. The part whose drag it is
gets `DragEnd` too.
"""
struct DragDrop <: Gesture
    x::Int
    y::Int
    dragged::Any
    modifiers::ModifierKeys
    time::Float64
end

DragDrop(x::Int, y::Int, dragged; time::Real) =
    DragDrop(x, y, dragged, ModifierKeys(), Float64(time))
DragDrop(x::Int, y::Int, dragged, modifiers::ModifierKeys; time::Real) =
    DragDrop(x, y, dragged, modifiers, Float64(time))

get_modifier_keys(gesture::DragDrop) = gesture.modifiers

"""
    is_drag_leave(gesture) -> Bool

Whether `gesture` is the [`DragOver`](@ref) that says that the pointer left, at
`(-1, -1)`.
"""
is_drag_leave(gesture) = false
is_drag_leave(gesture::DragOver) = gesture.x == -1 && gesture.y == -1

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
