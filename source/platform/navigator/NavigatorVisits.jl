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
    get_navigator_page_view(navigator) -> Any

What `navigator` draws as its page: the view of its page
([`make_document_view`](@ref)) while the view that the navigator keeps is a view of
that page, and the page itself otherwise.
"""
function get_navigator_page_view(navigator::Navigator)
    page = get_navigator_page(navigator)
    slot = navigator.page_view
    _is_page_view_slot(slot, page) ? slot.view : page
end

# The view of the page of `navigator` when that view keeps a selection of its own,
# as the view of a file that shows the file through views does, and `nothing`
# otherwise. The selection of the navigator then goes through the view, so each
# navigator has a caret of its own in the page.
function _get_page_own_view(navigator::Navigator)
    view = get_navigator_page_view(navigator)
    (view === get_navigator_page(navigator) || is_following_content_selection(view)) ? nothing : view
end

const _PAGE_VIEW_STEPS = (FieldReferenceStep("page_view"), FieldReferenceStep("view"))

# A navigator whose page view keeps a selection of its own has the page in its content,
# at its address, and the view at `page_view.view`: a path of the content inside the
# page is a path of the view there, and a path through the view names a place of the
# content.
function get_view_path(navigator::Navigator, path)
    view = _get_page_own_view(navigator)
    view === nothing && return invoke(get_view_path, Tuple{Any, Any}, navigator, path)
    page = get_reference_steps(strip_reference_types(get_navigator_page_address(navigator)))
    steps = path isa ConcreteReference ? get_reference_steps(strip_reference_types(path)) : ()
    _starts_with(steps, page) || return invoke(get_view_path, Tuple{Any, Any}, navigator, path)
    below = steps[(length(page) + 1):end]
    shown = get_view_path(view, isempty(below) ? EmptyReference() : Reference(below...))
    shown isa ConcreteReference ?
        Reference(_PAGE_VIEW_STEPS..., get_reference_steps(strip_reference_types(shown))...) :
        Reference(_PAGE_VIEW_STEPS...)
end

function get_content_path(navigator::Navigator, path)
    view = _get_page_own_view(navigator)
    (view !== nothing && path isa ConcreteReference) ||
        return invoke(get_content_path, Tuple{Any, Any}, navigator, path)
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) >= 2 && steps[1] == _PAGE_VIEW_STEPS[1] && steps[2] == _PAGE_VIEW_STEPS[2]) ||
        return invoke(get_content_path, Tuple{Any, Any}, navigator, path)
    below = get_content_path(view, length(steps) == 2 ? EmptyReference() : Reference(steps[3:end]...))
    below === nothing && return nothing
    place = Any[get_reference_steps(strip_reference_types(get_navigator_page_address(navigator)))...]
    below isa ConcreteReference && append!(place, get_reference_steps(strip_reference_types(below)))
    isempty(place) ? EmptyReference() : Reference(place...)
end

# Whether `slot` holds a view document of `page`: the field that the view edits
# holds `page`.
function _is_page_view_slot(slot, page)
    slot === nothing && return false
    field = get_edited_field(slot.view)
    field !== nothing && getfield(slot.view, field)[] === page
end

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
    below = get_content_path(navigator, path)
    below isa Reference || return nothing
    page = get_reference_steps(strip_reference_types(get_navigator_page_address(navigator)))
    steps = below isa ConcreteReference ? get_reference_steps(strip_reference_types(below)) : ()
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
    make_navigator_open_operation(navigator, address; selection = address, selects = true) -> Operation or nothing

The operation that opens the page at `address`, a path from the content of
`navigator`, as a new visit: the current visit goes on the back list, and the
forward list is cleared. The selection goes to `selection`, a path from the
content, when it reaches a node inside the new page, and to the page itself
otherwise. With `selects = false` the visit shows the page and the selection
stays where it is, as after a click on a link. `nothing` when the page at
`address` is the page that `navigator` shows.
"""
function make_navigator_open_operation(navigator::Navigator, address::Reference;
                                       selection::Union{Reference, Nothing} = address, selects::Bool = true)
    # The address records the types that its nodes have now, so a later edit that
    # puts another kind of part on its way cuts it there.
    address = annotate_reference_types(navigator.content, strip_reference_types(address))
    get_reference_steps(address) == get_reference_steps(get_navigator_page_address(navigator)) &&
        return nothing
    _make_visit_operation(navigator, NavigatorVisit(navigator.content, address, selection),
                          vcat(navigator.back, _make_current_visit(navigator)), NavigatorVisit[]; selects)
end

"""
    make_navigator_open_operation(navigator, document, reference; selects = true) -> Operation or nothing

The operation that opens the node at `reference` from `document` as a new visit.
When `document` is the content of `navigator`, or a document on the address of its
page, the page is the path from the content. When the content answers the path of
`document` in it ([`find_navigator_address`](@ref)), the page is that path.
Otherwise `document` becomes the content of the new visit, and Back returns to the
content before it. `nothing` when `reference` reaches no node, or when the node is
the page that `navigator` shows.

The navigator does not search its content for `document`: a search walks every
value of the content, which can be a frame of ten million rows. Only the domain of
the content knows where its parts are.
"""
function make_navigator_open_operation(navigator::Navigator, document, reference::Reference; selects::Bool = true)
    content = navigator.content
    reference = strip_reference_types(reference)
    page = get_reference_steps(get_navigator_page_address(navigator))
    for last_step in length(page):-1:0
        prefix = extend_reference(EmptyReference(), page[1:last_step]...)
        evaluate_reference(content, prefix) === document &&
            return make_navigator_open_operation(navigator, concat_references(prefix, reference); selects)
    end
    held = find_navigator_address(content, document)
    held === nothing ||
        return make_navigator_open_operation(navigator, concat_references(strip_reference_types(held), reference);
                                             selects)
    try_evaluate_reference(document, reference, _NOT_REACHED) === _NOT_REACHED && return nothing
    address = annotate_reference_types(document, reference)
    _make_visit_operation(navigator, NavigatorVisit(document, address, address),
                          vcat(navigator.back, _make_current_visit(navigator)), NavigatorVisit[]; selects)
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

# The page that the person leaves, with the selection in it and its view.
_make_current_visit(navigator::Navigator) =
    NavigatorVisit(navigator.content, get_navigator_page_address(navigator),
                   _find_content_selection(navigator), navigator.page_view)

# The writes that make `visit` the current one, with `back` and `forward` as the
# lists, the view of its page, and the move of the hold of the navigator from the
# view that it shows to that view, as view state; then, when `selects`, the move of
# the selection into its page. A visit that kept a view of its page shows that view
# again, and any other visit makes the view of its page.
function _make_visit_operation(navigator::Navigator, visit::NavigatorVisit, back, forward; selects::Bool = true)
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
        push!(writes, ReplaceReferencedValueOperation(draft, "unreached_step", 0))
    end
    page = evaluate_reference(visit.content, get_valid_reference_prefix(visit.content, visit.address))
    slot = _is_page_view_slot(visit.page_view, page) ? visit.page_view : _make_page_view_slot(page)
    slot === navigator.page_view || push!(writes, ReplaceReferencedValueOperation(navigator, "page_view", slot))
    view = slot === nothing ? page : slot.view
    shown = get_navigator_page_view(navigator)
    view === shown || push!(writes, ChangeHeldDocumentsOperation(navigator, Any[shown], Any[view]))
    selects || return ReplaceViewStateOperation(CompoundOperation(writes))
    selection = _find_visit_selection(visit)
    path = ConcreteReference(get_reference_node_type(navigator), _CONTENT_STEP,
                             annotate_reference_types(visit.content, selection))
    # A view that keeps a selection of its own takes the selection through its slot.
    if slot !== nothing && !is_following_content_selection(view)
        place = get_reference_steps(strip_reference_types(selection))
        inside = place[(length(get_reference_steps(strip_reference_types(
            get_valid_reference_prefix(visit.content, visit.address)))) + 1):end]
        shown = get_view_path(view, isempty(inside) ? EmptyReference() : Reference(inside...))
        below = shown isa ConcreteReference ? get_reference_steps(strip_reference_types(shown)) : ()
        path = ConcreteReference(get_reference_node_type(navigator), _PAGE_VIEW_STEPS[1],
                                 annotate_reference_types(slot, Reference(_PAGE_VIEW_STEPS[2], below...)))
    end
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(writes)),
                          ReplaceSelectionOperation(path)])
end

# The view of `page` that a new visit shows: a new view document, whose selection
# follows the page, in its slot, or `nothing` for a page that shows as itself.
function _make_page_view_slot(page)
    view = make_document_view(page)
    view === page ? nothing : NavigatorViewSlot(follow_content_selection!(view))
end

# The selection of a visit when it reaches a node inside the page of the visit,
# and the page itself otherwise. The page is the part of the address that reaches.
function _find_visit_selection(visit::NavigatorVisit)
    page = get_valid_reference_prefix(visit.content, visit.address)
    selection = visit.selection
    selection === nothing && return page
    _starts_with(get_reference_steps(selection), get_reference_steps(page)) &&
        is_valid_reference(visit.content, selection) ? selection : page
end

const _CONTENT_STEP = FieldReferenceStep("content")

# The selection of `navigator` as a path from its content, or `nothing` when the
# selection is not inside the content.
function _find_content_selection(navigator::Navigator)
    selection = navigator.selection
    selection isa ConcreteReference || return nothing
    get_content_path(navigator, selection)
end

_starts_with(steps, prefix) =
    length(steps) >= length(prefix) && all(k -> steps[k] == prefix[k], eachindex(prefix))

# `prefix` with `rest` in place of its terminal.
_attach_rest(prefix::ConcreteReference, rest) =
    ConcreteReference(prefix.type, prefix.head, _attach_rest(prefix.tail, rest))
_attach_rest(::EmptyReference, rest) = rest
