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

# Leaf: pass through unchanged. Contract documented at `copy_document` in
# `DocumentInterface.jl`; the two arities are sketched in the file header above.
copy_document(value) = value

# Vector: struct-with-integer-fields. Recurse per element; a `Vector{Cell}`'s
# slot cells dispatch to the `AbstractCell` method and are cloned per-slot, so
# the caller-visible shape (per-slot cells vs. plain values) is preserved.
copy_document(v::AbstractVector) = [copy_document(x) for x in v]

# Cell: fresh cell of the same kind + declared value type, holding the copied
# inner value. Used by the Vector walk for slot cells; the Document walk
# handles struct-field cells directly so it can consult declared field types.
copy_document(c::AbstractCell) = copy_cell_as(c, copy_document(c[]))

function copy_document(doc::Document)
    T = typeof(doc)
    base = Base.typename(T).wrapper   # the UnionAll: its ctor accepts cells/values
    args = Any[]
    for nm in fieldnames(T)
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            push!(args, copy_cell_as(raw, copy_document(raw[])))
        else
            push!(args, copy_document(raw))
        end
    end
    base(args...)
end

# The kind-converting variant: every cell rebuilt as kind `K`. Cell value types:
# the reactive target uses `Any`; the mutable/immutable targets use each field's
# declared type when the value conforms, else the value's own type. That fallback
# is load-bearing — the reactive kind stores every field as `Any`, so a nominally
# typed field may actually hold `nothing`, and `ImmutableCell{SomeType}(nothing)`
# would be unconstructable; it lands on `ImmutableCell{Nothing}` instead (still
# type-stable, just off the alias). Contract at `copy_document` in `DocumentInterface.jl`.
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
