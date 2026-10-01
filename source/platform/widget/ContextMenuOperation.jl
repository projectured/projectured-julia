# Fragment of `WidgetModule` — the menu of a part on a right click: the operation
# that carries the menu up, and the binding that answers the click.

"""
    OpenContextMenuOperation(layers, source, point)

Open the menus of the parts under the pointer.

- `layers` — `(title, menu)` pairs, the nearest part first: the title of each
  part (`get_document_title`) and its menu, usually a `WidgetMenu`;
- `source` — the path of the nearest part, from the input of the reader that
  holds the operation. It is rerooted and retargeted on the way up, as a path is;
- `point` — where the click was, in the frame of the reader that holds the
  operation, or `nothing` when a command runs the binding with no pointer. The
  window of the pointer moves it into the screen.

It collects (`is_collecting_operation`): each document around the part that
answered reads the click too, and its menu is added after the nearer ones. A
binding answers it inside `ReplaceViewStateOperation`, so a history does not
record it. [`ContextMenuWindowProjection`](@ref) takes it and opens the window.
The binding of a part computes the menu from that part, so each item acts on
that part, and a menu needs no selection.
"""
struct OpenContextMenuOperation <: Operation
    layers::Vector{Tuple{String,Document}}
    source::Reference
    point::Union{Nothing,Tuple{Int,Int}}
end

is_collecting_operation(::OpenContextMenuOperation) = true

join_collected_operations(inner::OpenContextMenuOperation,
                          outer::OpenContextMenuOperation) =
    OpenContextMenuOperation(vcat(inner.layers, outer.layers), inner.source,
                             inner.point === nothing ? outer.point : inner.point)

reroot_operation(operation::OpenContextMenuOperation, steps::Tuple) =
    OpenContextMenuOperation(operation.layers, reroot_reference(operation.source, steps),
                             operation.point)

operation_reference(operation::OpenContextMenuOperation) = operation.source

retarget_operation(operation::OpenContextMenuOperation, reference) =
    OpenContextMenuOperation(operation.layers, reference, operation.point)

function map_operation_position(operation::OpenContextMenuOperation, move)
    operation.point === nothing && return operation
    x, y = move(operation.point...)
    OpenContextMenuOperation(operation.layers, operation.source, (Int(x), Int(y)))
end

"""
    make_context_menu_operation(document, menu, gesture) -> Operation | Nothing

The answer of a context menu binding: `menu` is the menu of `document`, or
`nothing` when it has none. `gesture` is the right click, whose point
places the window, or `nothing` when a command runs the binding.
"""
function make_context_menu_operation(document, menu, gesture)
    menu === nothing && return nothing
    point = gesture isa MouseClick ? (gesture.x, gesture.y) : nothing
    title = something(get_document_title(document), String(nameof(typeof(document))))
    ReplaceViewStateOperation(
        OpenContextMenuOperation(Tuple{String,Document}[(String(title), menu)],
                                 EmptyReference(), point))
end

"""
    make_context_menu_binding(compute; description = "Show the context menu")
        -> GestureBinding

The binding that opens a context menu on a right click: the click answers the
menu that `compute(document)` returns, usually a `WidgetMenu`, or nothing when
`compute` returns `nothing`. A document type puts it in its own gesture table, so
the meaning belongs to the thing, and the command palette and an agent can run it
by its name, with no pointer. It applies only where the document has a menu, so a
listing greys it elsewhere.

Use it to give a document type a menu of its own on a right click.

# Example

    get_document_gesture_bindings_own(::Type{WidgetShell}) =
        GestureBinding[make_context_menu_binding(shell -> shell.context_menu;
                                                 description = "Show the window menu")]

See also `make_tooltip_binding`, which answers a dwell the same way.
"""
make_context_menu_binding(compute::Function;
                          description::AbstractString = "Show the context menu") =
    GestureBinding(MouseClickPattern(:right),
                   (document, gesture) ->
                       make_context_menu_operation(document, compute(document), gesture);
                   applicable = (document, selection) -> compute(document) !== nothing,
                   description = description, domain = "context menu",
                   name = String(description))
