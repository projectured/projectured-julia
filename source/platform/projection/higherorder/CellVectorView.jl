# Fragment of `ProjectionAlgebraModule`.
#
# The view of a list. A list view is a list of the views of the elements of its
# content, so the step `[3]` of a path of a view names the view of element 3, as
# the same step names element 3 in the content. A list view makes the view of an
# element when something reads that element, so a long list has only the views
# that something reached.

"""
    CellVectorView(viewed::CellVector)

The view of the list `viewed`: a list of the views of its elements, in the order
of the elements. `length(view)` is the length of `viewed`, and `view[3]` is the
view of element 3 of `viewed`, or `nothing` when that element has no view type
(`make_content_view`).

The list view makes the view of an element at the first read of that element. A
read of the length makes no view. The view of an element follows its element:
after an insert before the element, the same view is at the next index.

The list view keeps a view while something reaches it, and
[`drop_unreached_views!`](@ref) drops the others. So a long list has only the views
that a person changed and the views that a print shows.

`given` is the list of the views that a viewing step gives for the elements, in
their order, or `nothing`. A list view with a `given` list answers that list, and
it makes and drops no view. `kept` holds the views that the list view made, by
their elements.

# Example

    leaves = CellVector(Document[SyntaxLeaf(TextString("a")), SyntaxLeaf(TextString("b"))])
    view = CellVectorView(leaves)
    length(view)                  # 2, and no view of a leaf exists
    view[2]                       # the SyntaxLeafView of the second leaf, made now
    view[2] === view[2]           # true
"""
# A view that a list view keeps for an element: `index` is the index at which the
# list view saw the element last, and `asked` says that something asked for the view
# after the last drop.
mutable struct _KeptView
    view::Any
    index::Int
    asked::Bool
end

@document struct CellVectorView <: ContentView
    viewed::CellVector
    given::Union{CellVector, Nothing} = nothing
    kept::IdDict{Any,Any} = IdDict{Any,Any}()
end

# A list is a document, and `@document` gives a type whose first field is a list a
# constructor that takes documents as the items of that list. These two take a list
# as the content of the view.
CellVectorView(list::CellVector) = CellVectorView(Cell(list))
CellVectorView(list::CellVector, given::Union{CellVector, Nothing}) = CellVectorView(Cell(list), Cell(given))

make_content_view(list::CellVector) = CellVectorView(list)

DocumentModule.is_element_collection(::CellVectorView) = true

# A save, a search and a list of the fields of a document leave out the views that a
# list view holds for its elements.
DocumentModule.get_view_state_fields(::Type{<:CellVectorView}) = (:given, :kept)

# The list whose places are the places of `view`: the views that a step gave, or
# the content.
_get_place_list(view::CellVectorView) = something(view.given, view.viewed)

Base.length(view::CellVectorView) = length(_get_place_list(view))
Base.isempty(view::CellVectorView) = isempty(_get_place_list(view))
Base.firstindex(::CellVectorView) = 1
Base.lastindex(view::CellVectorView) = length(view)
Base.eachindex(view::CellVectorView) = Base.OneTo(length(view))
Base.keys(view::CellVectorView) = eachindex(view)
Base.eltype(::Type{<:CellVectorView}) = Any

function Base.getindex(view::CellVectorView, index::Integer)
    given = view.given
    given === nothing || return given[index]
    _get_element_view(view, view.viewed[index], index)
end

Base.getindex(view::CellVectorView, indices::AbstractVector{<:Integer}) = Any[view[index] for index in indices]

function Base.iterate(view::CellVectorView, index::Int = 1)
    index > length(view) && return nothing
    (view[index], index + 1)
end

# The view of `element`, the element at `index` of the content of `view`: the view
# that the list view keeps for it, or a new one, which it then keeps. An element
# has one view while the list view keeps it, at any index. An element that has no
# view type has `nothing`, and the list view keeps nothing for it.
function _get_element_view(view::CellVectorView, element, index::Integer)
    kept = view.kept
    found = get(kept, element, nothing)
    if found !== nothing
        found.index = index
        found.asked = true
        return found.view
    end
    made = make_content_view(element)
    made === nothing || (kept[element] = _KeptView(made, index, true))
    made
end

# The views that `view` keeps for elements that are in its list now: the index of
# the element, the element and what the list view keeps for it, in the order of
# the indexes. Each element is looked for at the index where the list view saw it
# last. One walk of the list finds the elements when one of them moved.
function _find_kept_places(view::CellVectorView)
    kept = view.kept
    places = Tuple{Int, Any, _KeptView}[]
    isempty(kept) && return places
    list = view.viewed
    count = length(list)
    moved = false
    for (element, entry) in kept
        if 1 <= entry.index <= count && list[entry.index] === element
            push!(places, (entry.index, element, entry))
        else
            moved = true
        end
    end
    if moved
        empty!(places)
        found = Base.IdSet{Any}()
        for (index, element) in enumerate(list)
            entry = get(kept, element, nothing)
            (entry === nothing || element in found) && continue
            push!(found, element)
            entry.index = index
            push!(places, (index, element, entry))
        end
    end
    sort!(places; by = first)
end

"""
    drop_unreached_views!(view::CellVectorView) -> view

Drop each view that `view` keeps for an element and that nothing reaches, and each
view of an element that left the list. The next read of such an element makes a
new view, which is equal to the view that went.

Something reaches the view of an element when one of these is true:

- the view holds a caret, live or dormant, or the part under the pointer;
- a field of its state does not have the default value
  ([`has_default_view_state`](@ref));
- a computation reads one of its cells, as a print that shows the view does;
- a list view below it keeps a view;
- something asked the list view for it after the last drop, so code that gets a
  view and then writes its state keeps that view.

The print of a view calls it for each list view of that view. A list view with
given views drops nothing.
"""
function drop_unreached_views!(view::CellVectorView)
    run_without_cell_tracking() do
        (view.given === nothing && !isempty(view.kept)) || return
        kept = view.kept
        present = Base.IdSet{Any}()
        for (_, element, entry) in _find_kept_places(view)
            push!(present, element)
            if entry.asked
                entry.asked = false
            elseif !_is_view_reached(entry.view)
                delete!(kept, element)
            end
        end
        for element in collect(keys(kept))
            element in present || delete!(kept, element)
        end
    end
    view
end

# Whether something other than a read of its list reaches `view`, the view of an
# element.
function _is_view_reached(view::ContentView)
    (_has_view_path(view) || _has_view_reader(view) || !has_default_view_state(view)) && return true
    for name in fieldnames(typeof(view))
        is_view_state_field(name) && continue
        value = getproperty(view, name)
        value isa CellVectorView && _is_view_reached(value) && return true
    end
    false
end

# A list view has no state of its own: something reaches it when it holds a caret,
# when a computation reads it, or when it keeps a view after its own drop.
function _is_view_reached(view::CellVectorView)
    (_has_view_path(view) || _has_view_reader(view)) && return true
    drop_unreached_views!(view)
    !isempty(view.kept)
end

_is_view_reached(view) = true

# Whether `view` holds a caret or the part under the pointer.
function _has_view_path(view::ContentView)
    get_stored_selection(view) === nothing || return true
    target = getfield(view, :mouse_target)
    target isa AbstractCell && target[] !== nothing
end

# Whether a computation reads a cell of `view`.
function _has_view_reader(view::ContentView)
    for name in fieldnames(typeof(view))
        cell = getfield(view, name)
        (cell isa AbstractCell && has_dependent_cells(cell)) && return true
    end
    false
end

# The views that `view` has take their state to the views of the same places of
# `copy`, and no other view is made.
function _copy_view_state!(copy::CellVectorView, view::CellVectorView)
    for (step, child) in child_reference_steps(view)
        child isa ContentView || continue
        child_copy = copy[step.stop]
        child_copy isa ContentView && _copy_view_state!(child_copy, child)
    end
    _copy_stored_caret!(copy, view)
end

# The child documents of a list view are the views that exist: the views that a
# step gave, or the views that the list view keeps, each with the index step of its
# element. A walk through them makes no view.
function OperationModule.child_reference_steps(view::CellVectorView)
    pairs = Tuple{Any, Any}[]
    given = view.given
    if given !== nothing
        for index in 1:length(given)
            child = given[index]
            child === nothing || push!(pairs, (RangeReferenceStep(index - 1, index), child))
        end
        return pairs
    end
    for (index, _, entry) in _find_kept_places(view)
        push!(pairs, (RangeReferenceStep(index - 1, index), entry.view))
    end
    pairs
end
