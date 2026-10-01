# Fragment of `FocusModule` — Tab starts over at the ends of a document.
#
# The parts move Tab inside themselves: a container gives Tab to the selected
# child, and when that child declines, it goes to the next child that holds a
# stop. A part that has nothing selected chooses its own first stop. At the end
# of the whole document every part declines, and only this wrapper answers.

"""
    FocusCyclingProjection(; inner)

Wrap `inner`, and answer a Tab that nothing inside answered with the first stop
of the input document, and a Shift+Tab with the last stop
([`get_first_focusable_path`](@ref), [`get_last_focusable_path`](@ref)). So Tab
cycles through the stops, and starts over at the ends.

The wrapper is transparent: it prints as `inner`, and it maps references as
`inner` does.
"""
struct FocusCyclingProjection <: Projection
    inner::Projection
end

FocusCyclingProjection(; inner::Projection) = FocusCyclingProjection(inner)

@iomap struct FocusCyclingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

function print_document(p::FocusCyclingProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    FocusCyclingIoMap(p, input, Cell(@computation child_iomap.output), child_iomap)
end

function read_intent(p::FocusCyclingProjection, recursion, change::Intent,
                     iomap::FocusCyclingIoMap)
    child = iomap.child_iomap
    answer = read_intent(child.projection, recursion, change, child)
    event = change.gesture
    (event isa KeyDown && event.key === :tab) || return answer
    operation = answer isa Intent ? answer.operation : answer
    operation === nothing || return answer
    document = iomap.input
    path = event.modifiers.shift ? get_last_focusable_path(document) :
                                   get_first_focusable_path(document)
    Intent(event, path === nothing ? nothing : ReplaceSelectionOperation(path))
end

read_intent(p::FocusCyclingProjection, iomap::FocusCyclingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(::FocusCyclingProjection, iomap::FocusCyclingIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::FocusCyclingProjection, iomap::FocusCyclingIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

"""
    focus_cycling = true

The wrapper of `build_editor` that wraps the projection of a window in a
[`FocusCyclingProjection`](@ref), so Tab and Shift+Tab start over at the ends of
the window. It is on by default, in every window, and a caller turns it off with
`focus_cycling = false`. It acts around the chrome of the `shell` wrapper, so the
cycle goes through the bands and the panes.
"""
# @positional: the arity of the wrapper seam of the kernel.
function wrap_editor!(::Val{:focus_cycling}, layer::Symbol, setting, parts::EditorParts)
    parts.projection = FocusCyclingProjection(inner = parts.projection)
    parts
end

get_wrapper_layers(::Val{:focus_cycling}) = (:container => 20,)
is_wrapper_default(::Val{:focus_cycling}) = true
