# Fragment of `DocumentModule` — the default behaviours every document inherits
# unless it overrides them: the two walk-steering traits (`is_element_collection`
# / `is_walk_opaque`, declared in `DocumentInterface.jl`), the unbounded default
# for the three sync/copy policy hooks, and the depth-limited debug `show`. The trait defaults keep the walk from ever naming a concrete
# collection type — a document opts into a shape by overriding one, and the walk
# reads the shape off the trait, so it sits below every collection it descends.

is_element_collection(value) = false
is_walk_opaque(value) = false
is_collection_field_type(::Val) = false

"""
    HiddenElements(source, from, to)

The elements a bounded walk is *not* keeping, handed to `unsynced_placeholder`
without copying them. An `AbstractVector`, so a policy can `length` it and look
at one element for a label; a positional collection document is not `view`-able,
which is why this exists rather than a `SubArray`.
"""
struct HiddenElements{S} <: AbstractVector{Any}
    source::S
    from::Int
    to::Int
end
Base.size(h::HiddenElements) = (max(0, h.to - h.from + 1),)
Base.getindex(h::HiddenElements, i::Int) = h.source[h.from + i - 1]

# The unbounded default: descend everywhere, keep every element, and so never
# reach the third. A policy overriding these is what bounds a sync or a copy —
# the walks in `DocumentSync.jl` / `DocumentCopy.jl` consult them at every child.
should_descend_sync(policy, depth::Int, slot) = true
sync_element_limit(policy, source, shadow) = length(source)
unsynced_placeholder(policy, source, current) =
    error("unsynced_placeholder: policy $(typeof(policy)) stopped the walk but supplies no marker")

# A plain type is its own family — its type-name wrapper. `@document` overrides this
# per schema so all variant layouts of one schema (the isbits stem, the native
# mutable struct) answer the same abstract family type.
document_family(x) = document_family(typeof(x))
document_family(::Type{T}) where {T} = Base.typename(T).wrapper

# The layout registry. A plain type is its own cell layout and has no native one,
# so a hand-written document copies into exactly what it was. `@document` overrides
# both per schema, on the family, so either accessor takes any variant. The
# `::Type{<:AFoo}` methods the macro emits are more specific than these, and
# so win for every variant of a schema.
document_cell_type(x) = document_cell_type(typeof(x))
document_cell_type(::Type{T}) where {T} = Base.typename(T).wrapper

document_native_type(x) = document_native_type(typeof(x))
document_native_type(::Type{T}) where {T} = nothing

"""
Maximum nesting depth printed by the generic document `show` before child
documents are abbreviated to `…`. Bounds debug output for deeply nested trees.
"""
const DOCUMENT_SHOW_MAX_DEPTH = 3

"""
    show(io::IO, x::Document)

Default depth-limited debug rendering for documents. Prints constructor-style
`TypeName(field, field, …)`, reading each field through `getproperty` so the
underlying reactive `Cell`s are unwrapped. Recursion is bounded by the
`:document_depth` IOContext key (see [`DOCUMENT_SHOW_MAX_DEPTH`]) so deeply
nested documents do not explode. A field named `selection`, when present, is
skipped as noise. A debug aid only: a domain that wants a *presentable* rendering
writes a projection, not a `show` method.
"""
function Base.show(io::IO, x::Document)
    depth = get(io, :document_depth, 0)
    print(io, nameof(typeof(x)), "(")
    if depth ≥ DOCUMENT_SHOW_MAX_DEPTH
        print(io, "…")
    else
        inner = IOContext(io, :document_depth => depth + 1)
        first = true
        for f in fieldnames(typeof(x))
            f === :selection && continue
            first || print(io, ", ")
            show(inner, getproperty(x, f))
            first = false
        end
    end
    print(io, ")")
end
