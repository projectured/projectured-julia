"""
    CollectionModule

Generic reactive collection document types. Two structural shapes: an indexed
growable vector (each slot is a reactive Cell), and a doubly-linked list with
a fixed head and two unlimited tails. Per-slot reactivity means a change to
one element invalidates only that slot's dependents, not the entire collection.
"""
module CollectionModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
export CellVector, ListNode, CollectionDocument, left_tail, right_tail, cell_at, take_first_n,
       ICellVector, IListNode

# ── CellVector ────────────────────────────────────────────────────────────
# A vector document where each slot is a reactive Cell.

@document struct CellVector <: Document
    elements::Vector{Cell}
    selection::Reference
end

CellVector()                        = CellVector(Cell(Cell[]),           Cell(nothing))
CellVector(cells::Vector{Cell})     = CellVector(Cell(copy(cells)),      Cell(nothing))
CellVector(items::AbstractVector)   = CellVector(Cell[Cell(x) for x in items])
CellVector(n::Integer)              = CellVector(Cell([Cell(nothing) for _ in 1:n]), Cell(nothing))
CellVector(items...)                = CellVector(Cell[Cell(x) for x in items])
function CellVector(f::Function)
    cv = CellVector(Cell(Cell[]), Cell(nothing))
    setfn!(getfield(cv, :elements), () -> Cell[Cell(x) for x in f()])
    cv
end

_elems(cv::CellVector) = cv.elements::Vector{Cell}

Base.length(cv::CellVector)            = length(_elems(cv))
Base.isempty(cv::CellVector)           = isempty(_elems(cv))
Base.firstindex(::CellVector)          = 1
Base.lastindex(cv::CellVector)         = length(cv)
Base.eachindex(cv::CellVector)         = Base.OneTo(length(cv))
function Base.iterate(cv::CellVector, s...)
    r = iterate(_elems(cv), s...)
    r === nothing && return nothing
    (cell, state) = r
    (cell[], state)
end

Base.getindex(cv::CellVector, i::Integer) = _elems(cv)[i][]  # returns the stored value
cell_at(cv::CellVector, i::Integer) = _elems(cv)[i]        # returns the raw Cell

function Base.setindex!(cv::CellVector, val, i::Integer)
    elems = _elems(cv)
    elems[i][] = val
    return val
end

function Base.setindex!(cv::CellVector, cell::Cell, i::Integer)
    elems = _elems(cv)
    elems[i] = cell
    cv.elements = elems
    return cell
end

function Base.push!(cv::CellVector, cells::Cell...)
    elems = _elems(cv)
    for c in cells; push!(elems, c) end
    cv.elements = elems
    return cv
end

function Base.pop!(cv::CellVector)
    elems = _elems(cv)
    c = pop!(elems)
    cv.elements = elems
    return c[]   # return stored value
end

function Base.insert!(cv::CellVector, i::Integer, cell::Cell)
    elems = _elems(cv)
    insert!(elems, i, cell)
    cv.elements = elems
    return cv
end

function Base.deleteat!(cv::CellVector, i)
    elems = _elems(cv)
    deleteat!(elems, i)
    cv.elements = elems
    return cv
end

Base.sort(cv::CellVector; by=identity, lt=isless, rev=false) = begin
    n = length(cv)
    perm = sortperm(1:n; by = i -> by(cv[i]), lt=lt, rev=rev)
    elems = _elems(cv)
    CellVector(Cell[elems[perm[i]] for i in 1:n])
end

Base.reverse(cv::CellVector) = begin
    elems = _elems(cv)
    CellVector(Cell[elems[i] for i in length(elems):-1:1])
end

Base.show(io::IO, cv::CellVector) =
    print(io, "CellVector(", length(cv), " slots)")

# ── ListNode ──────────────────────────────────────────────────────────────
# A doubly-linked list node. The node you hold IS the head (middle of the
# list). `prev` and `next` are the two tails growing in opposite directions.

@document struct ListNode <: Document
    value::Any
    prev::Union{ListNode, Nothing}
    next::Union{ListNode, Nothing}
    selection::Reference
end

ListNode(value) =
    ListNode(Cell(value), Cell(nothing), Cell(nothing), Cell(nothing))

Base.getindex(n::ListNode)      = n.value
Base.setindex!(n::ListNode, v)  = (n.value = v; v)

"""
    getindex(head::ListNode, i::Integer)

Access the value at index `i` relative to `head`:
- 1 = head, 2 = head.next, 3 = head.next.next, ...
- 0 = head.prev, -1 = head.prev.prev, ...
"""
function Base.getindex(head::ListNode, i::Integer)
    if i >= 1
        node = head
        for _ in 1:(i - 1)
            node.next === nothing && throw(BoundsError(head, i))
            node = node.next::ListNode
        end
        return node.value
    else
        node = head
        for _ in 1:(1 - i)
            node.prev === nothing && throw(BoundsError(head, i))
            node = node.prev::ListNode
        end
        return node.value
    end
end

# Append a new node at the end of the right (next) tail.
function Base.push!(head::ListNode, value)
    node = ListNode(value)
    cur = head
    while cur.next !== nothing
        cur = cur.next::ListNode
    end
    cur.next = node
    node.prev = cur
    return head
end

# Prepend a new node at the end of the left (prev) tail.
function Base.pushfirst!(head::ListNode, value)
    node = ListNode(value)
    cur = head
    while cur.prev !== nothing
        cur = cur.prev::ListNode
    end
    cur.prev = node
    node.next = cur
    return head
end

# Walk to the leftmost node (far end of the prev tail).
function left_tail(n::ListNode)
    cur = n
    while cur.prev !== nothing; cur = cur.prev::ListNode end
    return cur
end

# Walk to the rightmost node (far end of the next tail).
function right_tail(n::ListNode)
    cur = n
    while cur.next !== nothing; cur = cur.next::ListNode end
    return cur
end

Base.IteratorSize(::Type{ListNode}) = Base.SizeUnknown()
Base.eltype(::Type{ListNode})       = ListNode

# Iterate from left_tail through to right_tail.
function Base.iterate(n::ListNode, cur::Union{ListNode,Nothing} = left_tail(n))
    cur === nothing && return nothing
    return (cur, cur.next)
end

Base.show(io::IO, n::ListNode) = print(io, "ListNode(", n.value, ")")

# Take first n elements from a ListNode in specified direction
# direction = :next for forward, :prev for backward
function take_first_n(node::ListNode, n::Int, direction::Symbol=:next)
    result = []
    current = node
    for i in 1:n
        if current === nothing
            break
        end
        push!(result, current.value)
        next_node = direction == :next ? current.next : current.prev
        if next_node === nothing
            break
        end
        current = next_node
    end
    result
end

# Take n elements in prev direction and m elements in next direction from center node
# Returns a vector with prev elements first (in reverse order), then center, then next elements
function take_first_n(node::ListNode, n_prev::Int, n_next::Int)
    result = []
    # Collect prev elements (in reverse order since we traverse from center outward)
    prev_elements = []
    current = node
    for i in 1:n_prev
        if current === nothing
            break
        end
        prev_node = current.prev
        if prev_node === nothing
            break
        end
        push!(prev_elements, prev_node.value)
        current = prev_node
    end
    # Reverse prev elements to get correct order (farthest first)
    for i in length(prev_elements):-1:1
        push!(result, prev_elements[i])
    end
    # Add center
    push!(result, node.value)
    # Collect next elements
    current = node
    for i in 1:n_next
        if current === nothing
            break
        end
        next_node = current.next
        if next_node === nothing
            break
        end
        push!(result, next_node.value)
        current = next_node
    end
    result
end

"""
    CollectionDocument

Type alias representing the union of supported collection types.
Documents use either `CellVector` (finite, eager) or `ListNode`
(potentially infinite, lazy).
"""
const CollectionDocument = Union{CellVector, ListNode}

end # module
