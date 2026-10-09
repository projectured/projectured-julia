# Fragment of `WidgetModule` — the menu of a part on a right click: the operation
# that carries the menu up, and the binding that answers the click.

"""
    OpenContextMenuOperation(layers, source, point)

Open the menus of the parts under the pointer.

- `layers` — `(title, menu, below)` triples, the nearest part first: the title of
  each part (`get_document_title`), its menu, usually a `WidgetMenu`, and how
  many steps of `source` are below the part, `0` for the nearest one. An item
  of a menu acts on the part of its layer;
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
    layers::Vector{Tuple{String,Document,Int}}
    source::Reference
    point::Union{Nothing,Tuple{Int,Int}}
end

is_collecting_operation(::OpenContextMenuOperation) = true

# The layers of `outer`, a part around the part of `inner`, count the steps of the
# source of `inner` below their parts. The steps below a part stay as they are on
# the way up, because a reader above the part maps the steps above it, so the
# count stays right as the source is rerooted and mapped.
function join_collected_operations(inner::OpenContextMenuOperation, outer::OpenContextMenuOperation)
    more = _count_steps_after(inner.source, outer.source)
    layers = Tuple{String,Document,Int}[(title, menu, more === nothing ? 0 : below + more)
                                        for (title, menu, below) in outer.layers]
    OpenContextMenuOperation(vcat(inner.layers, layers), inner.source,
                             inner.point === nothing ? outer.point : inner.point)
end

# How many steps of `path` come after `prefix`, or `nothing` when `path` does not
# start with `prefix`; then the item acts on the part of `path`, as a menu with
# one source does.
function _count_steps_after(path::Reference, prefix::Reference)
    steps = get_reference_steps(strip_reference_types(path))
    head = get_reference_steps(strip_reference_types(prefix))
    length(steps) >= length(head) || return nothing
    all(steps[i] == head[i] for i in eachindex(head)) || return nothing
    length(steps) - length(head)
end

operation_reference(operation::OpenContextMenuOperation) = operation.source

retarget_operation(operation::OpenContextMenuOperation, reference) =
    OpenContextMenuOperation(operation.layers, reference, operation.point)

function map_operation_position(operation::OpenContextMenuOperation, move)
    operation.point === nothing && return operation
    x, y = move(operation.point...)
    OpenContextMenuOperation(operation.layers, operation.source, (Int(x), Int(y)))
end

"""
    find_menu_item_part(menu, operation) -> Reference

The path of the part whose menu in `menu`, an `OpenContextMenuOperation`, holds the
item that holds `operation`, from where `menu.source` starts: the source without
the steps below the part of that layer, or the source itself when no layer holds
the item. The context menu window lifts the edit of the item from that part; a
test that takes the menu from the answer of a click does the same.
"""
function find_menu_item_part(menu::OpenContextMenuOperation, operation)
    steps = get_reference_steps(strip_reference_types(menu.source))
    below = _find_item_layer_below(menu.layers, operation)
    extend_reference(EmptyReference(), steps[1:(length(steps) - below)]...)
end

# How many steps of the source are below the part of the layer whose menu holds
# the item of `operation`, found by the operation that the item holds; `0`, the
# part under the pointer, when no layer holds it.
function _find_item_layer_below(layers, operation)
    for (_, menu, below) in layers
        _has_item_operation(menu, operation) && return below
    end
    0
end

_has_item_operation(menu::WidgetMenu, operation) =
    any(element -> _has_item_operation(element, operation), menu.elements)
_has_item_operation(item::WidgetMenuItem, operation) =
    item.operation === operation || (item.submenu !== nothing && _has_item_operation(item.submenu, operation))
_has_item_operation(element, operation) = false

"""
    EditMenuPartOperation(operation, description)

The edit that an item of a context menu makes on the part that its menu belongs
to: `operation`, relative to that part, which the item holds
(`WidgetMenuItem(…; operation)`), and `description`, the label of the item. The
context menu window lifts it from that part through every reader around the
part, as [`read_rooted_operation`](@ref) lifts an operation that code made, so a
history records it as an edit of the person, and a reader that maps a path, such
as a sorted view, maps it. The part of an item of a menu of a part around the
part under the pointer, which F2 shows, is that part around it, so its item can
name a path in it, such as the caret in a field that the item makes. An
operation that names its own document, as a write of a field of a document does,
acts the same from any part. One that reaches the root found no context menu
window, and does nothing.
"""
struct EditMenuPartOperation <: Operation
    operation::Operation
    description::String
end

is_self_contained_operation(::EditMenuPartOperation) = true
evaluate_operation(editor, ::EditMenuPartOperation) = nothing

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
        OpenContextMenuOperation(Tuple{String,Document,Int}[(String(title), menu, 0)],
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
