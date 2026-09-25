# Fragment of `WidgetModule` — the probe that opens what the document under the
# pointer offers on a right press.
#
# It asks the same question as the tooltip probe and differs in two ways: the
# gesture is a right press rather than a pointer resting, and what comes back
# opens through `OpenPopupOperation`, the route `WidgetContextMenu` already
# takes. A menu is opened by a click, so it needs no window kept in reserve —
# the click is the user activation a browser asks for.
#
# **Printer** — transparent: it projects through `inner` and answers that output.

struct ContextMenuProbeProjection <: Projection
    inner::Projection
    compute_context_menu::Function  # (document) -> Document | Nothing
    width::Int                      # the popup's width
    row_height::Int                 # and one row of it, which sets the height
end

"""
    ContextMenuProbeProjection(; inner, compute_context_menu, width = 220,
                                 row_height = 24)

Wrap `inner`, the content projection of the window whose documents should offer
their own menus.

`compute_context_menu` is `(document) -> Document | Nothing`. A host passes the
generic of that name, which every document answers: a widget reads a field
somebody set, and every other document computes what it offers, which is what
makes the menu worth having.

`width` and `row_height` size the popup. They are given rather than measured
because this probe takes no `measure`: a `WidgetContextMenu`, which has one,
measures its own and answers before this probe is asked.

**The menu opens at the pointer.** The probe has the press point in its own
frame, and each reader above it moves that point into its own frame, up to the
window, which opens the menu there.
"""
ContextMenuProbeProjection(; inner::Projection, compute_context_menu::Function,
                             width::Integer = 220, row_height::Integer = 24) =
    ContextMenuProbeProjection(inner, compute_context_menu, Int(width), Int(row_height))

@iomap struct ContextMenuProbeIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

function print_document(p::ContextMenuProbeProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    ContextMenuProbeIoMap(p, input, Cell(@computation child_iomap.output), child_iomap)
end

function read_intent(p::ContextMenuProbeProjection, recursion, change::Intent,
                     iomap::ContextMenuProbeIoMap)
    event = change.gesture
    inner_answer = read_intent(iomap.child_iomap.projection, recursion, change,
                               iomap.child_iomap)
    # A widget closer to the pointer answers first: a `WidgetContextMenu` gives
    # one subtree a menu, and it wins over what the document says. A selection
    # alone is not such an answer: a right press on a row selects the row and
    # opens the menu, in one operation.
    operation = inner_answer isa Intent ? inner_answer.operation : inner_answer
    is_right = event isa MousePress && event.button === :right
    selection = is_right && _is_selection_only(operation) ? operation : nothing
    operation === nothing || selection !== nothing || return inner_answer
    is_right || return inner_answer
    # The same Alt press the tooltip probe uses, so both find the same document.
    press = MousePress(:left, event.x, event.y, ModifierKeys(alt = true);
                       time = event.time)
    probe = read_intent(iomap.child_iomap.projection, recursion,
                        Intent(press, nothing), iomap.child_iomap)
    probed = probe isa Intent ? probe.operation : probe
    path = probed isa ReplaceSelectionOperation ? probed.path : nothing
    node = path === nothing ? nothing : try_evaluate_reference(iomap.input, path, nothing)
    menu = node === nothing ? nothing : p.compute_context_menu(node)
    # What the window itself offers, where the document under the pointer offers
    # nothing. A press on empty space finds no document at all, which is the
    # same case.
    menu === nothing && (menu = p.compute_context_menu(iomap.input))
    menu === nothing && return inner_answer
    rows = menu isa WidgetMenu ? max(1, length(menu.elements)) : 1
    popup = ReplaceViewStateOperation(
        OpenPopupOperation(; id = :widget_popup, x = event.x, y = event.y,
                             width = p.width, height = rows * p.row_height, content = menu))
    Intent(event, selection === nothing ? popup : CompoundOperation(Any[selection, popup]))
end

# Whether `operation` does nothing but move the selection, such as the answer a
# row gives to a press.
_is_selection_only(operation) = operation isa ReplaceSelectionOperation
_is_selection_only(operation::WrappingOperation) = _is_selection_only(get_wrapped_operation(operation))
_is_selection_only(operation::CompoundOperation) =
    !isempty(operation.operations) && all(_is_selection_only, operation.operations)

read_intent(p::ContextMenuProbeProjection, iomap::ContextMenuProbeIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(::ContextMenuProbeProjection, iomap::ContextMenuProbeIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::ContextMenuProbeProjection, iomap::ContextMenuProbeIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
