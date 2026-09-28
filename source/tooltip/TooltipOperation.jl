# Fragment of `TooltipModule` — what a part says about itself when the pointer
# rests on it: the operation that carries it up, and the binding that answers it.

"""
    OpenTooltipOperation(layers, source, point)

Show what the parts under the pointer say about themselves.

- `layers` — `(title, content)` pairs, the nearest part first: the title of each
  part (`get_document_title`) and the document it shows, which the natural
  projection draws;
- `source` — the path of the nearest part, from the input of the reader that
  holds the operation. It is rerooted and retargeted on the way up, as a path is,
  so the window knows which part it describes;
- `point` — where the pointer rested, in the frame of the reader that holds the
  operation, or `nothing` when a command runs the binding with no pointer. The
  window of the pointer moves it into the screen.

It collects (`is_collecting_operation`): each document around the part that
answered reads the dwell too, and its layer is added after the nearer ones. A
binding answers it inside `ReplaceViewStateOperation`, so a history does not record
it. [`TooltipWindowProjection`](@ref) takes it and opens the window.
"""
struct OpenTooltipOperation <: Operation
    layers::Vector{Tuple{String,Document}}
    source::Reference
    point::Union{Nothing,Tuple{Int,Int}}
end

is_collecting_operation(::OpenTooltipOperation) = true

join_collected_operations(inner::OpenTooltipOperation, outer::OpenTooltipOperation) =
    OpenTooltipOperation(vcat(inner.layers, outer.layers), inner.source,
                         inner.point === nothing ? outer.point : inner.point)

reroot_operation(operation::OpenTooltipOperation, steps::Tuple) =
    OpenTooltipOperation(operation.layers, reroot_reference(operation.source, steps), operation.point)

operation_reference(operation::OpenTooltipOperation) = operation.source

retarget_operation(operation::OpenTooltipOperation, reference) =
    OpenTooltipOperation(operation.layers, reference, operation.point)

function map_operation_position(operation::OpenTooltipOperation, move)
    operation.point === nothing && return operation
    x, y = move(operation.point...)
    OpenTooltipOperation(operation.layers, operation.source, (Int(x), Int(y)))
end

"""
    make_tooltip_operation(document, content, gesture) -> Operation | Nothing

The answer of a tooltip binding: `content` is what `document` says about itself,
or `nothing` when it says nothing. `gesture` is the dwell, whose point places the
window, or `nothing` when a command runs the binding.
"""
function make_tooltip_operation(document, content, gesture)
    content === nothing && return nothing
    point = gesture isa MouseDwell ? (gesture.x, gesture.y) : nothing
    title = something(get_document_title(document), String(nameof(typeof(document))))
    ReplaceViewStateOperation(
        OpenTooltipOperation(Tuple{String,Document}[(String(title), content)], EmptyReference(), point))
end

"""
    make_tooltip_binding(compute; description = "Show the tooltip") -> GestureBinding

The binding that shows a tooltip when the pointer rests on a document: a
`MouseDwell` answers what `compute(document)` says, a document, or nothing when it
has nothing to say. A document type puts it in its own gesture table, so the
meaning belongs to the thing, and the command palette and an agent can run it by
its name on the selection, with no pointer. It stands only where the document
has something to say, so a listing greys it elsewhere.
"""
make_tooltip_binding(compute::Function; description::AbstractString = "Show the tooltip") =
    GestureBinding(MouseDwellPattern(),
                   (document, gesture) -> make_tooltip_operation(document, compute(document), gesture);
                   applicable = (document, selection) -> compute(document) !== nothing,
                   description = description, domain = "tooltip", name = String(description))
