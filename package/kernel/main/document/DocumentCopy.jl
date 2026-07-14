# Fragment of `DocumentModule` — deep copy of document subtrees. The Julia
# counterpart of Lisp's `deep-copy`. Unlike `Base.deepcopy` it understands the
# Cell-wrapped field convention and allocates fresh `Cell`s, so the copy is
# independent of the original's reactive graph. Two arities:
#
#   copy_document(doc)     -> Document              # preserve every cell's kind
#   copy_document(K, doc)  -> Document              # rebuild every cell as kind K
#
# The walk is generic over structure — struct fields (`fieldnames`), Vector
# elements, and per-slot cells inside a Vector are all traversed uniformly.

"""
    copy_document(value)                     -> value
    copy_document(v::AbstractVector)         -> Vector
    copy_document(c::AbstractCell)           -> AbstractCell
    copy_document(doc::Document)             -> Document

Deep-copy `value`, allocating fresh `Cell`s and fresh containers so the result
shares no mutable state with the source. Cell kinds are preserved: each field
cell in a `@document` node is cloned as the same kind, and per-slot cells
inside a Vector are cloned as the same kind. Plain immutable leaves (strings,
numbers, symbols) pass through unchanged.
"""
copy_document(value) = value

# Vector: struct-with-integer-fields. Recurse per element; a `Vector{Cell}`'s
# slot cells dispatch to the `AbstractCell` method and are cloned per-slot, so
# the caller-visible shape (per-slot cells vs. plain values) is preserved.
copy_document(v::AbstractVector) = [copy_document(x) for x in v]

# Cell: fresh cell of the same kind + declared value type, holding the copied
# inner value. Used by the Vector walk for slot cells; the Document walk
# handles struct-field cells directly so it can consult declared field types.
copy_document(c::AbstractCell) = _same_cell(c, copy_document(c[]))

function copy_document(doc::Document)
    T = typeof(doc)
    base = Base.typename(T).wrapper   # the UnionAll: its ctor accepts cells/values
    args = Any[]
    for nm in fieldnames(T)
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            push!(args, _same_cell(raw, copy_document(raw[])))
        else
            push!(args, copy_document(raw))
        end
    end
    base(args...)
end

"""
    copy_document(K, value)                  -> value
    copy_document(K, v::AbstractVector)      -> Vector
    copy_document(K, c::AbstractCell)        -> K{…}
    copy_document(K, doc::Document)          -> Document

The kind-converting variant. Every cell in the copy is rebuilt as kind `K`
(`ReactiveCell` / `MutableCell` / `ImmutableCell`). Cell value types: the
reactive target uses `Any` (parity with the historic untyped `Cell`); the
mutable/immutable targets use each field's **declared** type when the value
conforms — so a fully-conforming node inhabits the `MFoo`/`IFoo` alias — and
fall back to the value's own type otherwise. The fallback is load-bearing:
the reactive kind stores every field as `Any`, so a nominally typed field
may actually hold `nothing`; a typed cell like `ImmutableCell{SomeType}(nothing)`
would be unconstructable, so that field lands on `ImmutableCell{Nothing}`
instead (still type-stable, just off the alias).
"""
copy_document(::Type{<:AbstractCell}, value) = value

copy_document(K::Type{<:AbstractCell}, v::AbstractVector) =
    [copy_document(K, x) for x in v]

function copy_document(K::Type{<:AbstractCell}, c::AbstractCell)
    v = copy_document(K, c[])
    Tv = K === ReactiveCell ? Any : typeof(v)
    K{Tv}(v)
end

function copy_document(K::Type{<:AbstractCell}, doc::Document)
    T = typeof(doc)
    base = Base.typename(T).wrapper
    Ts = _declared_value_types(base)
    args = Any[]
    for (i, nm) in enumerate(fieldnames(T))
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            v = copy_document(K, raw[])
            Tv = _kinded_value_type(K, Ts, i, v)
            push!(args, K{Tv}(v))
        else
            push!(args, copy_document(K, raw))
        end
    end
    base(args...)
end
