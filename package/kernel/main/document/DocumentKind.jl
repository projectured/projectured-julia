# Fragment of `DocumentModule` — the cell-kind vocabulary the value protocol is
# written against. A document's kind (reactive / mutable / immutable) lives in
# its field cells, not in its type name, so copying and syncing a document both
# need to ask a cell what kind it is and to rebuild a cell in a chosen kind.
# `DocumentCopy.jl` and `DocumentSync.jl` are the two consumers.

# The kind constructor behind a cell's concrete type.
_cell_kind_of(::Type{<:ReactiveCell})  = ReactiveCell
_cell_kind_of(::Type{<:MutableCell})   = MutableCell
_cell_kind_of(::Type{<:ImmutableCell}) = ImmutableCell

# A fresh cell of the same kind and value type as `c`, holding `v`.
_same_cell(c::AbstractCell{T}, v) where {T} = _cell_kind_of(typeof(c)){T}(v)

# Read a document's cell kind off its first Cell-backed field. Hand-written
# documents with plain fields report `nothing`.
function _document_cell_kind(doc::Document)
    isempty(fieldnames(typeof(doc))) && return nothing
    c = getfield(doc, 1)
    c isa AbstractCell ? _cell_kind_of(typeof(c)) : nothing
end

# Declared field value types of a `@document` type, emitted by the macro; the
# fallback covers hand-written documents (the kind-variant of `copy_document`
# then falls back to each source cell's own value type).
_declared_value_types(::Type) = nothing

# The value type for a kinded field cell: `Any` for the reactive kind (parity
# with the untyped `Cell`); otherwise the declared type when `v` conforms,
# else `v`'s own concrete type.
function _kinded_value_type(::Type{K}, Ts, i, v) where {K<:AbstractCell}
    K === ReactiveCell && return Any
    Ts === nothing && return typeof(v)
    Td = Ts[i]
    v isa Td ? Td : typeof(v)
end

_value_type(::AbstractCell{T}) where {T} = T
