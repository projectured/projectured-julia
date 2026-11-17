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

`given` is the list of the views that a viewing step gives for the elements, in
their order, or `nothing`. A list view with a `given` list answers that list and
makes no view. `kept` holds the views that the list view made, by their elements.

# Example

    leaves = CellVector(Document[SyntaxLeaf(TextString("a")), SyntaxLeaf(TextString("b"))])
    view = CellVectorView(leaves)
    length(view)                  # 2, and no view of a leaf exists
    view[2]                       # the SyntaxLeafView of the second leaf, made now
    view[2] === view[2]           # true
"""
@document struct CellVectorView <: ContentView
    viewed::CellVector
    given::Union{CellVector, Nothing} = nothing
    kept::IdDict{Any,Any} = IdDict{Any,Any}()
end

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
    _get_element_view(view, view.viewed[index])
end

Base.getindex(view::CellVectorView, indices::AbstractVector{<:Integer}) = Any[view[index] for index in indices]

function Base.iterate(view::CellVectorView, index::Int = 1)
    index > length(view) && return nothing
    (view[index], index + 1)
end

# The view of `element`, an element of the content of `view`: the view that the
# list view keeps for it, or a new one, which it then keeps. An element has one
# view while the list view keeps it, at any index. An element that has no view
# type has `nothing`, and the list view keeps nothing for it.
function _get_element_view(view::CellVectorView, element)
    kept = view.kept
    found = get(kept, element, nothing)
    found === nothing || return found
    made = make_content_view(element)
    made === nothing || (kept[element] = made)
    made
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
    kept = view.kept
    isempty(kept) && return pairs
    for (index, element) in enumerate(view.viewed)
        child = get(kept, element, nothing)
        child === nothing || push!(pairs, (RangeReferenceStep(index - 1, index), child))
    end
    pairs
end
