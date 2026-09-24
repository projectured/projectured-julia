# ── CellVector ────────────────────────────────────────────────────────────
# A vector document where each slot is a reactive Cell.

# Storage convention by kind (cell-kinds Phase 4): the REACTIVE kind stores
# `Vector{Cell}` — one slot Cell per element, so a change to one element
# invalidates only that slot's dependents. The IMMUTABLE / MUTABLE kinds store a
# plain value `Vector` — without reactivity there is nothing for a slot cell to
# do, so elements live directly in the vector (frozen for I: any mutator dies at
# the `ImmutableCell` field write; write-through-no-invalidation for M). The
# declared type is therefore the loose `Vector`; accessors branch on the storage
# with a fully-typed fast path for the reactive convention.
"""
    CellVector(items)

A sequence of values, each in a cell of its own.

Use it for the children of a document: the rows of a table, the panes of a
window, the parts of a page. A write to one element tells what read that
element, and nothing else; adding or removing an element tells what read the
sequence. Most documents declare such a field simply as a `Vector`, and the
macro makes it one of these.

# Example

    rows = CellVector(["one", "two"])
    rows[2] = "three"          # only what read the second element hears
    push!(rows, "four")

See also `CellTable` and `CellMatrix` for two dimensions, `ListNode` for a
sequence read from the middle, and `get_cell_at`, which answers the cell rather
than the value.
"""
@document struct CellVector
    elements::Vector = Cell[]
end

# `CellVector` is the canonical 1-D positional collection: its children are
# addressed by `ElementReferenceStep` (`[i]`). Opt into the document-layer trait so
# reflection walkers emit `[i]` element paths instead of descending into
# `.elements`. See `is_element_collection` (DocumentModule) for the contract.
is_element_collection(::CellVector) = true

# Opt a `::CellVector` `@document` field into the collection-construction sugar
# (`Foo([a, b])` wraps the raw vector via `CellVector`). Keyed on the type's symbol
# so `@document` decides at expansion without naming `CellVector`.
is_collection_field_type(::Val{:CellVector}) = true

# **A field declared `Vector{T}` is a `CellVector` in the CELL layout.** That lets
# a document state the PLAIN type — `params::Vector{NedParam}` — and get a plain
# `Vector` in the native layout and one cell per element in the reactive one. A
# declaration naming `CellVector` cannot do that: the native layout takes the
# declared type as written, so it would carry cells it has no use for.
#
# Registered here rather than in the document layer for the same reason
# `is_collection_field_type` is: the kernel names no concrete collection type, and
# a collection says for itself what it stands in for. `CellVector(::AbstractVector)`
# is the constructor the contract requires, and it exists above.
get_cell_layout_field_type(::Val{:Vector}) = CellVector

# `CellVector()` is the macro's keyword constructor: `elements` defaults to an
# empty `Cell[]` and `selection` to `nothing`. Because *every* field defaults,
# Rule Y emits no positional constructor — which is what keeps the variadic below
# in charge of the 1-argument call (`CellVector(x)` is a one-*element* vector, not
# an elements vector).
CellVector(cells::Vector{Cell})     = CellVector(Cell(copy(cells)),      Cell(nothing))
CellVector(items::AbstractVector)   = CellVector(Cell[Cell(x) for x in items])
# `CellVector(undef, n)` — n empty (`nothing`) slots. Spelled with `undef` so it
# never collides with `CellVector(x)` / `CellVector(x, y, z)`, which build an element
# vector from their arguments (a bare integer is an *element*, not a slot count).
CellVector(::UndefInitializer, n::Integer) = CellVector(Cell([Cell(nothing) for _ in 1:n]), Cell(nothing))
# NOTE: the variadic builds an element vector for 1 or ≥3 args; a bare 2-arg call
# `CellVector(a, b)` resolves to the macro's 2-field inner ctor instead — i.e.
# `(elements, selection)`, not two elements. In practice the only 2-arg call sites
# pass *cells* (reusing an elements cell + a selection cell), which is exactly what
# that inner ctor wants; construct a 2-*element* vector with the bracket form
# `CellVector([a, b])`.
CellVector(items...)                = CellVector(Cell[Cell(x) for x in items])
"""
    CellVector(Computed(f)) -> CellVector

A `CellVector` whose elements are derived: `f` takes no argument and returns the
element list, and each element gets a slot cell of its own on every computation.
The counterpart of `Cell(Computed(f))` for a collection.
"""
function CellVector(computed::Computed)
    cv = CellVector(Cell(Cell[]), Cell(nothing))
    f = computed.thunk
    set_cell_function!(getfield(cv, :elements), () -> Cell[Cell(x) for x in f()])
    cv
end
# A `Function` needs no method of its own: it is an element like any other value, and the
# variadic above makes it a one-element vector. Only a `Computed` derives the element list.

# Value-vector conveniences for the non-reactive kinds (the macro-emitted 2-arg
# kind ctors remain the general form).
ICCellVector(items::AbstractVector) = ICCellVector(collect(Any, items), nothing)
MCCellVector(items::AbstractVector) = MCCellVector(collect(Any, items), nothing)

# The protocol dispatches on the STRUCT PARAMETER (the `elements` field cell's
# kind), not on runtime storage checks: `ReactiveCellVector` — a CellVector whose elements field
# is reactive — keeps the pre-kind typed hot path byte-for-byte (`Vector{Cell}`
# assert, slot-cell wrapping), measured to matter (runtime storage branches cost
# the reactive read path ~2×). The non-reactive instantiations take the generic
# plain-storage methods below. Convention: a reactive elements field always holds
# `Vector{Cell}` slots; hand-built exceptions are unsupported.
const ReactiveCellVector = CellVector{<:ReactiveCell}

_elems(cv::ReactiveCellVector) = cv.elements::Vector{Cell}
_plain(cv::CellVector) = cv.elements::Vector
# Mutator entry guard for the plain-storage kinds: an immutable-kind collection
# must not be touched at all — without this, the backing vector would mutate
# before the `ImmutableCell` field write raised, leaving a half-applied change.
function _mutable_plain(cv::CellVector)
    getfield(cv, :elements) isa ImmutableCell &&
        throw(ArgumentError("CellVector: immutable-kind collection cannot be mutated"))
    _plain(cv)
end

Base.size(cv::CellVector)              = (length(cv),)
# The pure structural queries delegate straight to the backing vector.
# (`getindex`/`iterate`/the mutators are NOT forwarded — they un/rewrap Cells and
# reassign `.elements` for reactivity, below.)
@forward_protocol [Base.length, Base.isempty, Base.firstindex,
                   Base.lastindex, Base.eachindex] on CellVector to elements
function Base.iterate(cv::ReactiveCellVector, s...)
    r = iterate(_elems(cv), s...)
    r === nothing && return nothing
    (cell, state) = r
    (cell[], state)
end
function Base.iterate(cv::CellVector, s...)
    r = iterate(_plain(cv), s...)
    r === nothing && return nothing
    (x, state) = r
    (unwrap_cell(x), state)
end

Base.getindex(cv::ReactiveCellVector, i::Integer)        = _elems(cv)[i][]      # the stored value
Base.getindex(cv::CellVector, i::Integer) = unwrap_cell(_plain(cv)[i])
# The raw slot Cell — reactive instantiations only.
"""
    get_cell_at(collection, index...) -> cell

The cell at a place, rather than the value in it.

Use it to hand one element of a collection to something that must follow it: a
projection that draws that element, a computation that reads it, a widget that
writes it. Reading the collection with `[]` answers the value and forgets where
it came from.

# Example

    cell = get_cell_at(rows, 2)
    set_cell_function!(cell, () -> uppercase(title[]))

See also `CellVector`, `CellTable` and `CellMatrix`.
"""
get_cell_at(cv::ReactiveCellVector, i::Integer) = _elems(cv)[i]

# The operation layer asks for the slot when it must put an element back. It can
# not name a cell collection, so it asks through this seam and a reactive
# collection answers the cell: a restored element is then the object it was, and
# whatever followed that cell follows it still.
get_slot_at(cv::ReactiveCellVector, i::Integer) = get_cell_at(cv, i)

function Base.setindex!(cv::ReactiveCellVector, val, i::Integer)
    elems = _elems(cv)
    elems[i][] = val                # value change inside the slot Cell
    return val
end
function Base.setindex!(cv::CellVector, val, i::Integer)
    elems = _mutable_plain(cv)
    elems[i] = val
    cv.elements = elems             # write-through (MutableCell field)
    return val
end

function Base.setindex!(cv::ReactiveCellVector, cell::Cell, i::Integer)
    elems = _elems(cv)
    elems[i] = cell                 # replace the slot Cell (structural change)
    cv.elements = elems
    return cell
end

# A plain value is wrapped in a fresh Cell; an existing Cell is appended as-is so
# identity-preserving moves still work. A Cell is never stored *as a value* in this
# codebase, so the single method is unambiguous.
_wrap_cell(x) = x isa AbstractCell ? x : Cell(x)

function Base.push!(cv::ReactiveCellVector, xs...)
    elems = _elems(cv)
    for x in xs; push!(elems, _wrap_cell(x)) end
    cv.elements = elems
    return cv
end
function Base.push!(cv::CellVector, xs...)
    elems = _mutable_plain(cv)
    for x in xs; push!(elems, x) end
    cv.elements = elems
    return cv
end

function Base.pop!(cv::ReactiveCellVector)
    elems = _elems(cv)
    c = pop!(elems)
    cv.elements = elems
    return c[]   # return stored value
end
function Base.pop!(cv::CellVector)
    elems = _mutable_plain(cv)
    x = pop!(elems)
    cv.elements = elems
    return x
end

function Base.insert!(cv::ReactiveCellVector, i::Integer, x)
    elems = _elems(cv)
    insert!(elems, i, _wrap_cell(x))
    cv.elements = elems
    return cv
end
function Base.insert!(cv::CellVector, i::Integer, x)
    elems = _mutable_plain(cv)
    insert!(elems, i, x)
    cv.elements = elems
    return cv
end

function Base.deleteat!(cv::ReactiveCellVector, i)
    elems = _elems(cv)
    deleteat!(elems, i)
    cv.elements = elems
    return cv
end
function Base.deleteat!(cv::CellVector, i)
    elems = _mutable_plain(cv)
    deleteat!(elems, i)
    cv.elements = elems
    return cv
end

# Fresh CellVector with the same field-cell kinds as `cv`, holding `slots`
# (already in cv's storage convention); selection reset.
_rebuild_with(cv::CellVector, slots::Vector) =
    CellVector(copy_cell_as(getfield(cv, :elements), slots),
               copy_cell_as(getfield(cv, :selection), nothing))

Base.sort(cv::CellVector; by=identity, lt=isless, rev=false) = begin
    n = length(cv)
    perm = sortperm(1:n; by = i -> by(cv[i]), lt=lt, rev=rev)
    elems = _plain(cv)
    slots = elems isa Vector{Cell} ? Cell[elems[perm[i]] for i in 1:n] :
                                     Any[elems[perm[i]] for i in 1:n]
    _rebuild_with(cv, slots)
end

Base.reverse(cv::CellVector) = begin
    elems = _plain(cv)
    slots = elems isa Vector{Cell} ? Cell[elems[i] for i in length(elems):-1:1] :
                                     Any[elems[i] for i in length(elems):-1:1]
    _rebuild_with(cv, slots)
end

# ── CellVector: deep copy / sync / reference steps ────────────────────────
# ── Deep copy ──────────────────────────────────────────────────────────────
# `CellVector`-specific cases of `DocumentModule.copy_document`. The walk that
# keeps the cell kind copies a list as it copies any document: the `elements`
# cell and each slot cell in it are rebuilt of their own kind.

# The plain copy starts the list with no selection. Every other policy keeps it,
# because a selection is a path relative to the list and is valid in the copy.
copy_document(policy::PlainCopyPolicy, cv::CellVector) =
    copy_document_fields(policy, cv; selection = nothing)

# Kind-converting deep copy: the target storage follows the kind convention —
# reactive → per-element slot Cells (via `CellVector(items)`), immutable/mutable
# → plain value vector wrapped in an outer typed cell.
function copy_document(::Type{K}, cv::CellVector) where {K<:AbstractCell}
    vals = Any[copy_document(K, x) for x in cv]
    K === ReactiveCell ? CellVector(vals) :
        CellVector(K{Vector}(vals), K{Union{Nothing, Reference}}(nothing))
end

# The CellVector method for `child_reference_steps`:
# elements are addressed by `RangeReferenceStep(i-1, i)`, so the pre-order
# document walk driving `SelectNextInsertionOperation` picks them up. The
# default fieldnames-walk (in `operation/Operations.jl`) still applies to
# non-CellVector documents.

function child_reference_steps(node::CellVector)
    pairs = Tuple{Any, Any}[]
    for i in 1:length(node)
        push!(pairs, (RangeReferenceStep(i - 1, i), node[i]))
    end
    pairs
end

# CellVector methods for the kernel's children-container generics. The
# kernel's `ProjectionTemplate` uses these instead of naming `CellVector`
# directly so its file can live at the kernel projection layer without
# importing a base document type.

make_children_container(cells::Vector) = CellVector(cells)
make_children_container(thunk::Function) = CellVector(Computed(thunk))
get_children_container_type() = CellVector

