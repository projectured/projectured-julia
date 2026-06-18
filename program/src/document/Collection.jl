"""
    CollectionModule

Generic reactive collection document types. Four structural shapes: an indexed
growable vector (each slot is a reactive Cell), a dense rectangular matrix of
reactive Cells, a table (CellVector of CellVector rows) optimised for row
insert/delete, and a doubly-linked list with a fixed head and two unlimited
tails. Per-slot reactivity means a change to one element invalidates only that
slot's dependents, not the entire collection.

# Invariants
- **Value change vs. structural change.** `cv[i] = val` writes *into* slot `i`'s
  existing Cell — a value change that keeps the slot's dependents wired.
  `cv[i] = cell::Cell` *replaces* the slot's Cell — a structural change that
  drops the old cell's dependents (they will not be notified again).
- **Structural mutators must reassign `.elements`.** `push!`, `pop!`, `insert!`,
  `deleteat!`, and the `Cell`-replacing `setindex!` all mutate the underlying
  `Vector{Cell}` in place *and then* reassign `cv.elements = elems`. That
  reassignment (of the same object) is what fires the structure Cell and
  invalidates dependents that track the vector's shape; omitting it leaves
  structural observers stale. Any new structural mutator must do the same.
"""
module CollectionModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
export CellVector, CellMatrix, CellTable, ListNode, CollectionDocument,
       left_tail, right_tail, cell_at, take_first_n,
       insertrow!, insertcol!, deleterow!, deletecol!, insertrow, deleterow,
       ICellVector, ICellMatrix, ICellTable, IListNode

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

# ── CellMatrix ────────────────────────────────────────────────────────────
# A dense rectangular matrix where each slot is a reactive Cell.
# Structural mutations (insert/delete row/column) reallocate the underlying
# Matrix{Cell}, but Cell references remain stable.

@document struct CellMatrix <: Document
    elements::Matrix{Cell}
    selection::Reference
end

CellMatrix() =
    CellMatrix(Cell(Matrix{Cell}(undef, 0, 0)), Cell(nothing))

CellMatrix(cells::Matrix{Cell}) =
    CellMatrix(Cell(copy(cells)), Cell(nothing))

CellMatrix(nrows::Integer, ncols::Integer) =
    CellMatrix(Cell([Cell(nothing) for _ in 1:nrows, _ in 1:ncols]), Cell(nothing))

CellMatrix(items::AbstractMatrix) =
    CellMatrix(Cell([Cell(items[r, c]) for r in 1:size(items, 1), c in 1:size(items, 2)]), Cell(nothing))

function CellMatrix(f::Function)
    cm = CellMatrix(Cell(Matrix{Cell}(undef, 0, 0)), Cell(nothing))
    setfn!(getfield(cm, :elements), () -> [Cell(x) for x in f()])
    cm
end

_elems(cm::CellMatrix) = cm.elements::Matrix{Cell}

Base.size(cm::CellMatrix)                        = size(_elems(cm))
Base.size(cm::CellMatrix, d::Integer)            = size(_elems(cm), d)
Base.length(cm::CellMatrix)                      = length(_elems(cm))
Base.isempty(cm::CellMatrix)                     = isempty(_elems(cm))
Base.eachindex(cm::CellMatrix)                   = CartesianIndices(_elems(cm))

function Base.iterate(cm::CellMatrix, s...)
    r = iterate(_elems(cm), s...)
    r === nothing && return nothing
    (cell, state) = r
    (cell[], state)
end

Base.getindex(cm::CellMatrix, r::Integer, c::Integer) = _elems(cm)[r, c][]
cell_at(cm::CellMatrix, r::Integer, c::Integer)       = _elems(cm)[r, c]

function Base.setindex!(cm::CellMatrix, val, r::Integer, c::Integer)
    _elems(cm)[r, c][] = val
    return val
end

function Base.setindex!(cm::CellMatrix, cell::Cell, r::Integer, c::Integer)
    elems = _elems(cm)
    elems[r, c] = cell
    cm.elements = elems
    return cell
end

function insertrow!(cm::CellMatrix, r::Integer, cells::Vector{Cell})
    elems = _elems(cm)
    nrows, ncols = size(elems)
    length(cells) == ncols || throw(DimensionMismatch("expected $ncols cells, got $(length(cells))"))
    new_elems = Matrix{Cell}(undef, nrows + 1, ncols)
    new_elems[1:r-1, :]   = @view elems[1:r-1, :]
    new_elems[r, :]        = cells
    new_elems[r+1:end, :]  = @view elems[r:end, :]
    cm.elements = new_elems
    return cm
end

function insertcol!(cm::CellMatrix, c::Integer, cells::Vector{Cell})
    elems = _elems(cm)
    nrows, ncols = size(elems)
    length(cells) == nrows || throw(DimensionMismatch("expected $nrows cells, got $(length(cells))"))
    new_elems = Matrix{Cell}(undef, nrows, ncols + 1)
    new_elems[:, 1:c-1]   = @view elems[:, 1:c-1]
    new_elems[:, c]        = cells
    new_elems[:, c+1:end]  = @view elems[:, c:end]
    cm.elements = new_elems
    return cm
end

function deleterow!(cm::CellMatrix, r::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows - 1, ncols)
    new_elems[1:r-1, :]  = @view elems[1:r-1, :]
    new_elems[r:end, :]   = @view elems[r+1:end, :]
    cm.elements = new_elems
    return cm
end

function deletecol!(cm::CellMatrix, c::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows, ncols - 1)
    new_elems[:, 1:c-1]  = @view elems[:, 1:c-1]
    new_elems[:, c:end]   = @view elems[:, c+1:end]
    cm.elements = new_elems
    return cm
end

Base.show(io::IO, cm::CellMatrix) =
    print(io, "CellMatrix(", size(cm, 1), "×", size(cm, 2), " slots)")

# ── CellTable ─────────────────────────────────────────────────────────────
# A table stored as a CellVector of CellVector rows. Row insert/delete is
# O(nrows) — the same cost as CellVector.insert! — without copying every
# cell in the matrix. Column access requires iterating rows.

@document struct CellTable <: Document
    rows::CellVector
    selection::Reference
end

CellTable() = CellTable(Cell(CellVector()), Cell(nothing))

CellTable(nrows::Integer, ncols::Integer) =
    CellTable(Cell(CellVector(Cell[Cell(CellVector(ncols)) for _ in 1:nrows])), Cell(nothing))

function CellTable(items::AbstractMatrix)
    nr, nc = size(items)
    rows = CellVector(Cell[Cell(CellVector([items[r, c] for c in 1:nc])) for r in 1:nr])
    CellTable(Cell(rows), Cell(nothing))
end

Base.size(ct::CellTable) = (length(ct.rows), isempty(ct.rows) ? 0 : length(ct.rows[1]::CellVector))
Base.size(ct::CellTable, d::Integer) = size(ct)[d]
Base.length(ct::CellTable) = length(ct.rows)
Base.isempty(ct::CellTable) = isempty(ct.rows)

Base.getindex(ct::CellTable, r::Integer, c::Integer) = (ct.rows[r]::CellVector)[c]
cell_at(ct::CellTable, r::Integer, c::Integer) = cell_at(ct.rows[r]::CellVector, c)

function Base.setindex!(ct::CellTable, val, r::Integer, c::Integer)
    (ct.rows[r]::CellVector)[c] = val
    return val
end

function insertrow(ct::CellTable, r::Integer, row::CellVector)
    insert!(ct.rows, r, Cell(row))
    return ct
end

function insertrow(ct::CellTable, r::Integer, items::AbstractVector)
    insert!(ct.rows, r, Cell(CellVector(items)))
    return ct
end

function deleterow(ct::CellTable, r::Integer)
    deleteat!(ct.rows, r)
    return ct
end

function Base.iterate(ct::CellTable, s...)
    r = iterate(ct.rows, s...)
    r === nothing && return nothing
    (row, state) = r
    (row::CellVector, state)
end

Base.show(io::IO, ct::CellTable) = begin
    nr, nc = size(ct)
    print(io, "CellTable(", nr, "×", nc, " slots)")
end

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
const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}

end # module
