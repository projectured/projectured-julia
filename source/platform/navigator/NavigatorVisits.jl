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
    get_navigator_address_steps(navigator) -> Vector

The steps that the bar of `navigator` shows: the steps of its address copy while a
person edits it, and the steps of its page address otherwise.
"""
get_navigator_address_steps(navigator::Navigator) =
    navigator.address_draft.edited ? collect(navigator.address_draft.steps) :
    get_reference_steps(get_navigator_page_address(navigator))

"""
    get_navigator_page(navigator) -> Any

The part of the content that `navigator` shows: the node at its page address.
"""
get_navigator_page(navigator::Navigator) =
    evaluate_reference(navigator.content, get_navigator_page_address(navigator))

"""
    find_navigator_parent_address(navigator) -> Reference or nothing

The address of the page that holds the page of `navigator`: the nearest document
above the page at which a navigator stops ([`is_navigator_stop`](@ref)), or the
root of the content. `nothing` at the root of the content.
"""
function find_navigator_parent_address(navigator::Navigator)
    content = navigator.content
    address = get_navigator_page_address(navigator)
    steps = get_reference_steps(address)
    isempty(steps) && return nothing
    for stop in (length(steps) - 1):-1:1
        prefix = extend_reference(EmptyReference(), steps[1:stop]...)
        node = try_evaluate_reference(content, prefix, _NOT_REACHED)
        node === _NOT_REACHED && return nothing
        is_navigator_stop(node) && return annotate_reference_types(content, prefix)
    end
    annotate_reference_types(content, EmptyReference())
end

"""
    is_navigator_stop(document) -> Bool

Whether a navigator stops at `document` when it goes up to the parent page, names
the items of the address, and opens the selected part or the part under the
pointer. A navigator passes over a document that answers `false`, and it can still
show that document as a page at its own address.

The default is `true` for a document, and `false` for a collection of the document
around it, the ones that `get_parent` looks past, and for a value that is no
document. A domain answers `false` for a container that holds the parts of the
document around it, such as the rows of the view of a data frame.
"""
is_navigator_stop(node) =
    node isa Document && !(is_element_collection(node) || node isa AbstractVector ||
                           node isa AbstractDict || node isa Tuple)

"""
    find_navigator_selected_address(navigator) -> Reference or nothing

The address of the innermost document on the selection inside the page of
`navigator`, below the page itself; `nothing` when the selection is not inside the
page, or when no document stands between the page and the selection.
"""
function find_navigator_selected_address(navigator::Navigator)
    _find_part_address(navigator, navigator.selection)
end

# The address of the innermost document on `path`, a path from `navigator`, inside
# its page and below the page itself; `nothing` when `path` is not inside the page,
# or when no document stands between the page and the end of `path`.
function _find_part_address(navigator::Navigator, path)
    path isa ConcreteReference || return nothing
    get_reference_head(path) == _CONTENT_STEP || return nothing
    page = get_reference_steps(get_navigator_page_address(navigator))
    steps = get_reference_steps(get_reference_tail(path))
    _starts_with(steps, page) || return nothing
    content = navigator.content
    for last_step in length(steps):-1:(length(page) + 1)
        address = extend_reference(EmptyReference(), steps[1:last_step]...)
        node = try_evaluate_reference(content, address, _NOT_REACHED)
        is_navigator_stop(node) && return address
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
    make_navigator_open_operation(navigator, document, reference) -> Operation or nothing

The operation that opens the node at `reference` from `document` as a new visit.
When `document` is the content of `navigator`, or a document on the address of its
page, the page is the path from the content. Otherwise `document` becomes the
content of the new visit, and Back returns to the content before it. `nothing`
when `reference` reaches no node, or when the node is the page that `navigator`
shows.

The navigator does not search its content for `document`: a search walks every
value of the content, which can be a frame of ten million rows.
"""
function make_navigator_open_operation(navigator::Navigator, document, reference::Reference)
    content = navigator.content
    reference = strip_reference_types(reference)
    page = get_reference_steps(get_navigator_page_address(navigator))
    for last_step in length(page):-1:0
        prefix = extend_reference(EmptyReference(), page[1:last_step]...)
        evaluate_reference(content, prefix) === document &&
            return make_navigator_open_operation(navigator, concat_references(prefix, reference))
    end
    try_evaluate_reference(document, reference, _NOT_REACHED) === _NOT_REACHED && return nothing
    address = annotate_reference_types(document, reference)
    _make_visit_operation(navigator, NavigatorVisit(document, address, address),
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
    # A visit gives the bar the new address: an edited copy goes back to it.
    draft = navigator.address_draft
    if draft.edited
        push!(writes, ReplaceReferencedValueOperation(draft, "edited", false))
        push!(writes, ReplaceReferencedValueOperation(draft, "steps", CellVector()))
    end
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

