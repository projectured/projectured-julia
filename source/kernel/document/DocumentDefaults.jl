# Fragment of `DocumentModule` — the default behaviours every document inherits
# unless it overrides them: the two walk-steering traits (`is_element_collection`
# / `is_walk_opaque`, declared in `DocumentInterface.jl`), the unbounded default
# for the three sync policy hooks, the defaults of the `CopyPolicy` hooks and of
# `has_document_duplicate`, and the depth-limited debug `show`. The trait defaults keep the walk from ever naming a concrete
# collection type — a document opts into a shape by overriding one, and the walk
# reads the shape off the trait, so it sits below every collection it descends.

is_element_collection(value) = false
is_walk_opaque(value) = false
is_collection_field_type(::Val) = false
# No substitution: a declared type is what the cell layout holds, unchanged.
get_cell_layout_field_type(::Val) = nothing

"""
    HiddenElements(source, from, to)

The elements a bounded walk is *not* keeping, handed to `make_unsynced_placeholder`
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
function Base.getindex(h::HiddenElements, i::Int)
    @boundscheck checkbounds(h, i)
    h.source[h.from + i - 1]
end

# The unbounded default: descend everywhere, keep every element, and so never
# reach the third. A policy overriding these is what bounds a sync or a copy —
# the walks in `DocumentSync.jl` / `DocumentCopy.jl` consult them at every child.
is_descendable_for_sync(policy, depth::Int, slot) = true
compute_sync_element_limit(policy, source, shadow) = length(source)
make_unsynced_placeholder(policy, source, current) =
    error("make_unsynced_placeholder: policy $(typeof(policy)) stopped the walk but supplies no marker")

# The copy policy's defaults: descend everywhere, keep a moment of a computed
# cell, and record nothing.
is_descendable_for_copy(policy::CopyPolicy, document) = true
make_copy_placeholder(policy::CopyPolicy, document) =
    error("make_copy_placeholder: policy $(typeof(policy)) stopped the walk but supplies no marker")
copy_computed_cell(policy::CopyPolicy, cell) =
    copy_cell_as(cell, copy_document(policy, cell[]))
get_copy_memo(policy::CopyPolicy) = nothing
copy_selection_cell(policy::CopyPolicy, cell) =
    copy_cell_as(cell, copy_document(policy, cell[]))

# Any name, because a walk asks it of every field name, and the fields of a tuple
# are numbers.
is_view_state_field(name) = name === :selection || name === :mouse_target

# A kind has no duplicate until it declares one.
has_document_duplicate(document) = false

# A plain type is its own family — its type-name wrapper. `@document` overrides this
# per schema so all variant layouts of one schema (the isbits stem, the native
# mutable struct) answer the same abstract family type.
get_document_family(x) = get_document_family(typeof(x))
get_document_family(::Type{T}) where {T} = Base.typename(T).wrapper

# The layout registry. A plain type is its own cell layout and has no native one,
# so a hand-written document copies into exactly what it was. `@document` overrides
# both per schema, on the family, so either accessor takes any variant. The
# `::Type{<:AFoo}` methods the macro emits are more specific than these, and
# so win for every variant of a schema.
get_document_cell_type(x) = get_document_cell_type(typeof(x))
get_document_cell_type(::Type{T}) where {T} = Base.typename(T).wrapper

get_document_native_type(x) = get_document_native_type(typeof(x))
get_document_native_type(::Type{T}) where {T} = nothing

get_document_schema_name(x) = get_document_schema_name(typeof(x))
get_document_schema_name(::Type{T}) where {T} = nameof(T)

# A document that carries no name of its own. The argument is untyped on purpose:
# a slice writes a method for its own type, and a default of the same signature
# would be overwritten rather than added to.
get_document_title(document) = nothing

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
nested documents do not explode. A view state field (`is_view_state_field`), the
selection and the mouse target, is skipped as noise. A debug aid only: a domain that wants a *presentable* rendering
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
            is_view_state_field(f) && continue
            first || print(io, ", ")
            show(inner, getproperty(x, f))
            first = false
        end
    end
    print(io, ")")
end

# The document a node stands for: itself, unless a wrapper says otherwise.
get_wrapped_document(node) = node

# A node is what a person edits, unless it names the field that holds that.
get_edited_field(node) = nothing

# Replacing a plain document is storing the new one in its place.
replace_wrapped_document!(node, document) = document
