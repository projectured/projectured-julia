# Fragment of `NavigatorModule` — the page of a navigator, and the operations that
# move it to another page: open, Back, Forward and Parent. Each operation writes
# the address and the two lists of visits as view state, and moves the selection
# into the page that it opens, with a path from the navigator.

"""
    get_navigator_page_address(navigator) -> Reference

The path of the page that `navigator` shows, from its content: the `address`, or
the longest prefix of it that still reaches a node of the type that the address
records, when an edit removed the page or put another kind of part on its way.
"""
get_navigator_page_address(navigator::Navigator) =
    get_valid_reference_prefix(navigator.content, navigator.address)

"""
    get_navigator_page(navigator) -> Any

The part of the content that `navigator` shows: the node at its page address.
"""
get_navigator_page(navigator::Navigator) =
    evaluate_reference(navigator.content, get_navigator_page_address(navigator))

"""
    find_navigator_parent_address(navigator) -> Reference or nothing

The address of the page that holds the page of `navigator`: one step up, and past
each collection on the way, as `get_parent` reads it. `nothing` at the root of the
content.
"""
function find_navigator_parent_address(navigator::Navigator)
    address = get_navigator_page_address(navigator)
    address isa EmptyReference && return nothing
    parent = get_parent(navigator.content, address)
    parent === nothing ? nothing : get_reference(parent)
end

"""
    find_navigator_selected_address(navigator) -> Reference or nothing

The address of the innermost document on the selection inside the page of
`navigator`, below the page itself; `nothing` when the selection is not inside the
page, or when no document stands between the page and the selection.
"""
function find_navigator_selected_address(navigator::Navigator)
    selection = _find_content_selection(navigator)
    selection === nothing && return nothing
    page = get_reference_steps(get_navigator_page_address(navigator))
    steps = get_reference_steps(selection)
    _starts_with(steps, page) || return nothing
    content = navigator.content
    for last_step in length(steps):-1:(length(page) + 1)
        address = extend_reference(EmptyReference(), steps[1:last_step]...)
        node = try_evaluate_reference(content, address, _NOT_REACHED)
        _is_page_node(node) && return address
    end
    nothing
end

"""
    make_navigator_open_operation(navigator, address; selection = address) -> Operation or nothing

The operation that opens the page at `address`, a path from the content of
`navigator`, as a new visit: the current visit goes on the back list, and the
forward list is cleared. The selection goes to `selection`, a path from the
content, when it reaches a node inside the new page, and to the page itself
otherwise. `nothing` when the page at `address` is the page that `navigator`
shows.
"""
function make_navigator_open_operation(navigator::Navigator, address::Reference;
                                       selection::Union{Reference, Nothing} = address)
    # The address records the types that its nodes have now, so a later edit that
    # puts another kind of part on its way cuts it there.
    address = annotate_reference_types(navigator.content, strip_reference_types(address))
    get_reference_steps(address) == get_reference_steps(get_navigator_page_address(navigator)) &&
        return nothing
    _make_visit_operation(navigator, NavigatorVisit(navigator.content, address, selection),
                          vcat(navigator.back, _make_current_visit(navigator)), NavigatorVisit[])
end

"""
    make_navigator_back_operation(navigator) -> Operation or nothing

The operation that returns to the newest visit of the back list, with the
selection that the visit holds. The current visit goes on the forward list.
`nothing` when the back list is empty.
"""
function make_navigator_back_operation(navigator::Navigator)
    back = navigator.back
    isempty(back) && return nothing
    _make_visit_operation(navigator, back[end], back[1:(end - 1)],
                          vcat(navigator.forward, _make_current_visit(navigator)))
end

"""
    make_navigator_forward_operation(navigator) -> Operation or nothing

The operation that goes to the nearest visit of the forward list, the mirror of
[`make_navigator_back_operation`](@ref). `nothing` when the forward list is empty.
"""
function make_navigator_forward_operation(navigator::Navigator)
    forward = navigator.forward
    isempty(forward) && return nothing
    _make_visit_operation(navigator, forward[end], vcat(navigator.back, _make_current_visit(navigator)),
                          forward[1:(end - 1)])
end

"""
    make_navigator_parent_operation(navigator) -> Operation or nothing

The operation that opens the page that holds the page of `navigator` as a new
visit, with the page that the person leaves selected, so Back returns to it.
`nothing` at the root of the content.
"""
function make_navigator_parent_operation(navigator::Navigator)
    address = find_navigator_parent_address(navigator)
    address === nothing && return nothing
    make_navigator_open_operation(navigator, address; selection = get_navigator_page_address(navigator))
end

# ── The visits ────────────────────────────────────────────────────────────────

# What `try_evaluate_reference` answers for a path that reaches no node.
struct _NotReached end
const _NOT_REACHED = _NotReached()

# The page that the person leaves, with the selection in it.
_make_current_visit(navigator::Navigator) =
    NavigatorVisit(navigator.content, get_navigator_page_address(navigator),
                   _find_content_selection(navigator))

# The writes that make `visit` the current one, with `back` and `forward` as the
# lists, as view state; then the move of the selection into its page.
function _make_visit_operation(navigator::Navigator, visit::NavigatorVisit, back, forward)
    writes = Any[ReplaceReferencedValueOperation(navigator, "address", visit.address),
                 ReplaceReferencedValueOperation(navigator, "back", back),
                 ReplaceReferencedValueOperation(navigator, "forward", forward)]
    visit.content === navigator.content ||
        pushfirst!(writes, ReplaceReferencedValueOperation(navigator, "content", visit.content))
    selection = _find_visit_selection(visit)
    path = ConcreteReference(get_reference_node_type(navigator), _CONTENT_STEP,
                             annotate_reference_types(visit.content, selection))
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(writes)),
                          ReplaceSelectionOperation(path)])
end

# The selection of a visit when it reaches a node inside the page of the visit,
# and the page itself otherwise.
function _find_visit_selection(visit::NavigatorVisit)
    selection = visit.selection
    selection === nothing && return visit.address
    _starts_with(get_reference_steps(selection), get_reference_steps(visit.address)) &&
        is_valid_reference(visit.content, selection) ? selection : visit.address
end

const _CONTENT_STEP = FieldReferenceStep("content")

# The selection of `navigator` as a path from its content, or `nothing` when the
# selection is not inside the content.
function _find_content_selection(navigator::Navigator)
    selection = navigator.selection
    selection isa ConcreteReference || return nothing
    get_reference_head(selection) == _CONTENT_STEP || return nothing
    get_reference_tail(selection)
end

_starts_with(steps, prefix) =
    length(steps) >= length(prefix) && all(k -> steps[k] == prefix[k], eachindex(prefix))

# A node that can be a page: a document that is not a collection of the document
# around it. The collections are the ones that `get_parent` looks past.
_is_page_node(node) =
    node isa Document && !(is_element_collection(node) || node isa AbstractVector ||
                           node isa AbstractDict || node isa Tuple)
