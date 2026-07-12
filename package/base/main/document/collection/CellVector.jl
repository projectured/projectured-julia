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
@document struct CellVector
    elements::Vector
    selection::Reference
end

"""
    is_element_collection(document) -> Bool

`true` when a document's children are addressed **by position** (an
`ElementReference`, i.e. `[i]`) rather than by named field. A reflection walker
(e.g. `search_references`) keys off this trait to emit `[i]` element paths for a
collection instead of descending into its internal storage fields — so it never
has to name a concrete collection type. Default `false`; `CellVector`, the
canonical sequence document, is the primary `true`. Other positional-collection
documents (e.g. a `@forward_vector` wrapper) can opt in with their own method.
"""
is_element_collection(::Any) = false
is_element_collection(::CellVector) = true

CellVector()                        = CellVector(Cell(Cell[]),           Cell(nothing))
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
function CellVector(f::Function)
    cv = CellVector(Cell(Cell[]), Cell(nothing))
    set_function!(getfield(cv, :elements), () -> Cell[Cell(x) for x in f()])
    cv
end

# Value-vector conveniences for the non-reactive kinds (the macro-emitted 2-arg
# kind ctors remain the general form).
ICellVector(items::AbstractVector) = ICellVector(collect(Any, items), nothing)
MCellVector(items::AbstractVector) = MCellVector(collect(Any, items), nothing)

# The protocol dispatches on the STRUCT PARAMETER (the `elements` field cell's
# kind), not on runtime storage checks: `RCV` — a CellVector whose elements field
# is reactive — keeps the pre-kind typed hot path byte-for-byte (`Vector{Cell}`
# assert, slot-cell wrapping), measured to matter (runtime storage branches cost
# the reactive read path ~2×). The non-reactive instantiations take the generic
# plain-storage methods below. Convention: a reactive elements field always holds
# `Vector{Cell}` slots; hand-built exceptions are unsupported.
const RCV = CellVector{<:ReactiveCell}

_elems(cv::RCV) = cv.elements::Vector{Cell}
_plain(cv::CellVector) = cv.elements::Vector
# Mutator entry guard for the plain-storage kinds: an immutable-kind collection
# must not be touched at all — without this, the backing vector would mutate
# before the `ImmutableCell` field write raised, leaving a half-applied change.
function _mutable_plain(cv::CellVector)
    getfield(cv, :elements) isa ImmutableCell &&
        throw(ArgumentError("CellVector: immutable-kind collection cannot be mutated"))
    _plain(cv)
end
# Unwrap one slot: a reactive slot is a Cell, a non-reactive slot is the value.
_slotval(x) = x isa AbstractCell ? x[] : x

Base.size(cv::CellVector)              = (length(cv),)
# The pure structural queries delegate straight to the backing vector.
# (`getindex`/`iterate`/the mutators are NOT forwarded — they un/rewrap Cells and
# reassign `.elements` for reactivity, below.)
@forward CellVector elements [Base.length, Base.isempty, Base.firstindex,
                              Base.lastindex, Base.eachindex]
function Base.iterate(cv::RCV, s...)
    r = iterate(_elems(cv), s...)
    r === nothing && return nothing
    (cell, state) = r
    (cell[], state)
end
function Base.iterate(cv::CellVector, s...)
    r = iterate(_plain(cv), s...)
    r === nothing && return nothing
    (x, state) = r
    (_slotval(x), state)
end

Base.getindex(cv::RCV, i::Integer)        = _elems(cv)[i][]      # the stored value
Base.getindex(cv::CellVector, i::Integer) = _slotval(_plain(cv)[i])
# The raw slot Cell — reactive instantiations only.
get_cell_at(cv::RCV, i::Integer) = _elems(cv)[i]

function Base.setindex!(cv::RCV, val, i::Integer)
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

function Base.setindex!(cv::RCV, cell::Cell, i::Integer)
    elems = _elems(cv)
    elems[i] = cell                 # replace the slot Cell (structural change)
    cv.elements = elems
    return cell
end

# A plain value is wrapped in a fresh Cell; an existing Cell is appended as-is so
# identity-preserving moves still work. A Cell is never stored *as a value* in this
# codebase, so the single method is unambiguous.
_wrap_cell(x) = x isa AbstractCell ? x : Cell(x)

function Base.push!(cv::RCV, xs...)
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

function Base.pop!(cv::RCV)
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

function Base.insert!(cv::RCV, i::Integer, x)
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

function Base.deleteat!(cv::RCV, i)
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
    CellVector(_same_cell(getfield(cv, :elements), slots),
               _same_cell(getfield(cv, :selection), nothing))

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
# `CellVector`-specific cases of `DocumentModule.copy_document`. The generic
# `Document` path would share the `elements`' inner slot `Cell`s (the fallback
# `copy_document(::Vector) = [copy_document(x) for x in v]` returns each cell
# unchanged when the vector is non-`Vector{Cell}`, and slot-cell kind against
# the enclosing CellVector's kind convention is the storage decision this
# override makes explicit).

# Same-kind deep copy: preserve the storage shape of the source's `elements`
# field, cloning each slot cell (reactive convention) or each raw value
# (immutable/mutable convention) into a fresh Cell/value; the outer field cells
# are rebuilt of the same kind by `_rebuild_with`.
function copy_document(cv::CellVector)
    elems = _plain(cv)
    slots = elems isa Vector{Cell} ? Cell[Cell(copy_document(c[])) for c in elems] :
                                     Any[copy_document(x) for x in elems]
    _rebuild_with(cv, slots)   # same field-cell kinds
end

# Kind-converting deep copy: the target storage follows the kind convention —
# reactive → per-element slot Cells (via `CellVector(items)`), immutable/mutable
# → plain value vector wrapped in an outer typed cell.
function copy_document(::Type{K}, cv::CellVector) where {K<:AbstractCell}
    vals = Any[copy_document(K, x) for x in cv]
    K === ReactiveCell ? CellVector(vals) :
        CellVector(K{Vector}(vals), K{Reference}(nothing))
end

# `CellVector`-specific case of `DocumentModule.sync_document!`: reconcile the
# writable `shadow`'s elements against `source` positionally. A slot whose source
# element is the same document type is synced *in place* (its own inner cells,
# minimally); a changed-type or changed-value slot is rewritten; a longer source
# appends (fires the structure cell once), a shorter one trims from the end.
#
# Positional matching is minimal for the dominant simulation edits — in-place
# value change, enqueue (append), dequeue-from-end. A front-shift re-syncs the
# shifted tail; keying by source-element identity (an `IdDict` persisted across
# syncs) would make that minimal too, and is the natural refinement if profiling a
# front-heavy queue demands it.
function sync_document!(shadow::CellVector, source::CellVector)
    K = _document_cell_kind(shadow)
    ns, nc = length(source), length(shadow)
    for i in 1:min(ns, nc)
        s, c = source[i], shadow[i]
        if s isa Document && c isa Document && _same_wrapper(c, s)
            sync_document!(c, s)                      # recurse into the slot's document
        else
            isequal(c, s) || (shadow[i] = _shadow_elem(K, s))   # value/type change ⇒ rewrite slot
        end
    end
    for i in (nc + 1):ns
        push!(shadow, _shadow_elem(K, source[i]))     # enqueue
    end
    for _ in 1:(nc - ns)
        pop!(shadow)                                  # trim surplus
    end
    shadow
end

# The CellVector method for `child_reference_steps`:
# elements are addressed by `RangeReference(i-1, i)`, so the pre-order
# document walk driving `SelectNextInsertionOperation` picks them up. The
# default fieldnames-walk (in `operation/Operations.jl`) still applies to
# non-CellVector documents.

function child_reference_steps(node::CellVector)
    pairs = Tuple{Any, Any}[]
    for i in 1:length(node)
        push!(pairs, (RangeReference(i - 1, i), node[i]))
    end
    pairs
end

# CellVector methods for the kernel's children-container generics. The
# kernel's `ProjectionTemplate` uses these instead of naming `CellVector`
# directly so its file can live at the kernel projection layer without
# importing a base document type.

make_children_container(cells::Vector) = CellVector(cells)
make_children_container(thunk::Function) = CellVector(thunk)
children_container_type() = CellVector

