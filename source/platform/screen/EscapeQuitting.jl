# Fragment of `ScreenModule` — a bare Escape that nothing took quits the editor.
#
# The editor does not quit on Escape, so a program that wants the key to quit
# says so. An example window of the REPL does; the window of a program does not,
# because a person presses Escape to cancel, and it must not close the program.

"""
    EscapeQuittingProjection(; inner)

Wrap `inner`, and answer a bare Escape that nothing inside answered with
`QuitEditorOperation()`, so the editor quits. A modified Escape and every other
gesture pass on as `inner` answers them. The gesture is an Escape alone or in a
`WindowInput`.

Put it around everything else: a reader outside it can not take the Escape
before the quit does. So a popup, a tooltip, a dialog, a drag and the command
palette close on Escape, and the editor does not quit.

The wrapper is transparent: it prints as `inner`, and it maps references as
`inner` does.
"""
struct EscapeQuittingProjection <: Projection
    inner::Projection
end

EscapeQuittingProjection(; inner::Projection) = EscapeQuittingProjection(inner)

@iomap struct EscapeQuittingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

function print_document(p::EscapeQuittingProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    EscapeQuittingIoMap(p, input, Cell(@computation child_iomap.output), child_iomap)
end

function read_intent(p::EscapeQuittingProjection, recursion, change::Intent,
                     iomap::EscapeQuittingIoMap)
    child = iomap.child_iomap
    answer = read_intent(child.projection, recursion, change, child)
    gesture = change.gesture
    _is_bare_escape(gesture isa WindowInput ? gesture.event : gesture) || return answer
    operation = answer isa Intent ? answer.operation : answer
    operation isa Operation && return answer
    Intent(change.gesture, QuitEditorOperation())
end

read_intent(p::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

"""
    quit_on_escape = true

The wrapper of `build_editor` that wraps the projection in an
[`EscapeQuittingProjection`](@ref), so a bare Escape that nothing took quits the
editor. It acts last, around every other wrapper, so each of them takes the
Escape first. It is off by default: the window of a program closes from its menu
or its frame, and an example window of the REPL turns it on.
"""
function wrap_editor!(::Val{:quit_on_escape}, layer::Symbol, argument, parts::EditorParts)
    parts.projection = EscapeQuittingProjection(inner = parts.projection)
    parts
end

get_wrapper_layers(::Val{:quit_on_escape}) = (:screen => 100,)
