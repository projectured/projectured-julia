# Fragment of `DocumentModule` — deep copy of document subtrees. The Julia
# counterpart of Lisp's `deep-copy`. Unlike `Base.deepcopy` it understands the
# Cell-wrapped field convention and allocates fresh `Cell`s, so the copy is
# independent of the original's reactive graph. Two forms:
#
#   copy_document(policy, doc) -> Document          # preserve every cell's kind
#   copy_document(K, doc)      -> Document          # rebuild every cell as kind K
#
# `copy_document(doc)` is the first form under `PlainCopyPolicy`.
#
# The two forms also differ in **layout**. The form with a policy preserves it: a
# native document copies into a native one. The kinded form targets the schema's
# cell layout, read from `get_document_cell_type`, because a kind is a property of
# a cell and a native tree has none. So a native source converts, which is what a
# shadow needs.
#
# The form with a policy is steered by the `CopyPolicy` hooks and by the methods
# a policy or a kind adds on the pair (see `copy_document` in
# `DocumentInterface.jl`). The kinded form is optionally **bounded** by a sync
# `policy`, which is what lets a shadow be *born* stopping short of a large
# subtree rather than copied whole and cut back. Its default policy (`nothing`)
# descends everywhere, so an un-policed copy is the whole copy.
#
# The walk is generic over structure — struct fields (`fieldnames`), Vector
# elements, and per-slot cells inside a Vector are all traversed uniformly.

"""
    DocumentCopyException(value, reason)

A copy refused `value`, for `reason`: a sentence that says what `value` holds
that the copy can not own. A hook throws it, and the walk lets it through at
any depth.
"""
struct DocumentCopyException <: Exception
    value::Any
    reason::String
end

"""
    PlainCopyPolicy()

The policy of `copy_document(value)`. Every hook answers its default: the walk
descends into every document, a cell that computes becomes a cell that stores
its value, and nothing is recorded, so a document met twice is copied twice.
"""
struct PlainCopyPolicy <: CopyPolicy end

copy_document(value) = copy_document(PlainCopyPolicy(), value)

# Leaf: shared. Contract documented at `copy_document` in `DocumentInterface.jl`.
copy_document(policy::CopyPolicy, value) = value

# Vector: struct-with-integer-fields. Recurse per element; a `Vector{Cell}`'s
# slot cells dispatch to the `AbstractCell` method and are cloned per-slot, so
# the caller-visible shape (per-slot cells vs. plain values) is preserved.
copy_document(policy::CopyPolicy, v::AbstractVector) = [copy_document(policy, x) for x in v]

# A list of slot cells stays a `Vector{Cell}` even when it is empty, which the
# comprehension above can not promise: a collection keys its storage on that type.
copy_document(policy::CopyPolicy, v::Vector{Cell}) = Cell[copy_document(policy, c) for c in v]

# Cell: a fresh cell of the same kind and value type, holding the copied inner
# value. A cell that computes is the policy's to copy.
copy_document(policy::CopyPolicy, cell::AbstractCell) =
    is_computed_cell(cell) ? copy_computed_cell(policy, cell) :
                             copy_cell_as(cell, copy_document(policy, cell[]))

# Document: rebuilt, unless the policy stops here.
copy_document(policy::CopyPolicy, document::Document) =
    is_descendable_for_copy(policy, document) ? copy_document_fields(policy, document) :
                                                make_copy_placeholder(policy, document)

# What a memo holds for a document whose copy is not finished yet.
struct _CopyInProgress end

function copy_document_fields(policy::CopyPolicy, document::Document; replacements...)
    T = typeof(document)
    field_names = fieldnames(T)
    for name in keys(replacements)
        name in field_names ||
            throw(ArgumentError("copy_document_fields: $(T) has no field `$(name)`"))
    end
    memo = get_copy_memo(policy)
    if memo !== nothing
        earlier = get(memo, document, nothing)
        earlier isa _CopyInProgress &&
            throw(DocumentCopyException(document, "it holds itself through a back-link"))
        earlier === nothing || return earlier
        memo[document] = _CopyInProgress()
    end
    base = Base.typename(T).wrapper   # the UnionAll: its ctor accepts cells/values
    arguments = Any[]
    for name in field_names
        raw = getfield(document, name)
        push!(arguments, haskey(replacements, name) ?
                             _get_replacement_field(raw, replacements[name]) :
                         name === :selection && raw isa AbstractCell ?
                             copy_selection_cell(policy, raw) :
                             copy_document(policy, raw))
    end
    result = base(arguments...)
    memo === nothing || (memo[document] = result)
    result
end

# A replacement for a field that holds a cell goes in a new cell of the same
# kind; a cell given as the replacement is used as it is.
_get_replacement_field(raw, value) =
    value isa AbstractCell ? value :
    raw isa AbstractCell   ? copy_cell_as(raw, value) :
                             value

Base.showerror(io::IO, e::DocumentCopyException) =
    print(io, "DocumentCopyException: a copy of a ", nameof(typeof(e.value)),
          " is refused: ", e.reason)

# ── The duplicate ──────────────────────────────────────────────────────────

"""
    DuplicatePolicy()

The policy of [`make_document_duplicate`](@ref). Made for one duplicate, because
it records every document it copies.

- It descends into a document whose kind declares a duplicate, and shares every
  other document: what the duplicate does not own, it reads.
- It refuses a cell that computes, because a copy of its value looks live and is
  not. A selection is not refused: it is view state, and the duplicate takes the
  selection as it is now (see [`copy_selection_cell`](@ref)).
- It refuses a function, a `Ref` and a `Task`, because the walk can not know
  what they capture, and an action that captures the original acts on it.
- It refuses a document that holds itself, unless the kind makes its own copy.
"""
struct DuplicatePolicy <: CopyPolicy
    copies::IdDict{Any,Any}
end
DuplicatePolicy() = DuplicatePolicy(IdDict{Any,Any}())

is_descendable_for_copy(::DuplicatePolicy, document) = has_document_duplicate(document)
make_copy_placeholder(::DuplicatePolicy, document) = document
copy_computed_cell(::DuplicatePolicy, cell) =
    throw(DocumentCopyException(cell, "it computes its value, and a copy would not follow what it reads"))
get_copy_memo(policy::DuplicatePolicy) = policy.copies
copy_document(::DuplicatePolicy, value::Union{Function, Base.RefValue, Task}) =
    throw(DocumentCopyException(value, "it holds an action, and a copy of it would act on the original"))

function make_document_duplicate(document)
    has_document_duplicate(document) ||
        throw(DocumentCopyException(document, "its kind declares no duplicate"))
    copy_document(DuplicatePolicy(), document)
end

# The kind-converting variant: every cell rebuilt as kind `K`. Cell value types:
# the reactive target uses `Any`; the mutable/immutable targets use each field's
# declared type when the value conforms, else the value's own type. That fallback
# is load-bearing — the reactive kind stores every field as `Any`, so a nominally
# typed field may actually hold `nothing`, and `ImmutableCell{SomeType}(nothing)`
# would be unconstructable; it lands on `ImmutableCell{Nothing}` instead (still
# type-stable, just off the alias). Contract at `copy_document` in `DocumentInterface.jl`.
copy_document(::Type{<:AbstractCell}, value, policy = nothing, depth::Int = 0) = value

copy_document(K::Type{<:AbstractCell}, v::AbstractVector, policy = nothing, depth::Int = 0) =
    _copy_elements(K, v, policy, depth)

# A bounded element copy has to preserve the source vector's element type (a
# collection document declares `Vector{Cell}`), so it builds with `similar`
# rather than a comprehension, and stops after `sync_element_limit` with one
# placeholder standing for the tail.
function _copy_elements(K, v::AbstractVector, policy, depth)
    policy === nothing && return [copy_document(K, x) for x in v]
    n = length(v)
    limit = sync_element_limit(policy, v, ())
    out = similar(v, 0)
    for i in 1:min(limit, n)
        push!(out, copy_document(K, v[i], policy, depth))
    end
    if limit < n
        m = make_unsynced_placeholder(policy, HiddenElements(v, limit + 1, n), nothing)
        # Wrapped exactly as a copied element would be — a slot-celled vector
        # (`Vector{Cell}`) cannot hold a bare document.
        push!(out, v[limit + 1] isa AbstractCell ?
                   K{K === ReactiveCell ? Any : typeof(m)}(m) : m)
    end
    out
end

function copy_document(K::Type{<:AbstractCell}, c::AbstractCell, policy = nothing, depth::Int = 0)
    v = copy_document(K, c[], policy, depth)
    Tv = K === ReactiveCell ? Any : typeof(v)
    K{Tv}(v)
end

# The declared field value types of a `@document` type (emitted by the macro); the
# fallback covers hand-written documents, whose kind-converting copy then falls back
# to each source cell's own value type.
_declared_value_types(::Type) = nothing

# The value type for a rebuilt kinded field cell: `Any` for the reactive kind
# (parity with the untyped `Cell`); otherwise the declared type when `v` conforms,
# else `v`'s own concrete type.
function _kinded_value_type(::Type{K}, Ts, i, v) where {K<:AbstractCell}
    K === ReactiveCell && return Any
    Ts === nothing && return typeof(v)
    Td = Ts[i]
    v isa Td ? Td : typeof(v)
end

function copy_document(K::Type{<:AbstractCell}, doc::Document, policy = nothing, depth::Int = 0)
    T = typeof(doc)
    # The target is the schema's **cell layout**, not the source's own layout. A kind
    # is a property of a cell, so a kinded copy only means something in a tree that
    # has cells; a native source therefore converts here rather than rebuilding
    # itself. Building through `Base.typename(T).wrapper` instead is what let a
    # native child land in a reactive shadow, where nothing could invalidate it.
    base = get_document_cell_type(T)
    base === nothing &&
        error("copy_document: $(T) has no cell layout, so a $(K) copy of it is not a thing")
    Ts = _declared_value_types(base)
    # Every field of a macro-emitted cell layout is a cell slot, whatever the source
    # held; `_declared_value_types` is emitted for exactly those types, so its
    # presence is the test. A hand-written document is its own cell layout, so there
    # the source's own field shape is the truth and a raw field stays raw.
    all_cells = Ts !== nothing
    args = Any[]
    for (i, nm) in enumerate(fieldnames(T))
        raw = getfield(doc, nm)
        inner = raw isa AbstractCell ? raw[] : raw
        # A document-valued child faces the bound; anything else is a leaf or a
        # container the walk copies through.
        v = inner isa Document && !is_descendable_for_sync(policy, depth + 1, nothing) ?
            make_unsynced_placeholder(policy, inner, nothing) :
            copy_document(K, inner, policy, depth + 1)
        push!(args, all_cells || raw isa AbstractCell ?
                    K{_kinded_value_type(K, Ts, i, v)}(v) : v)
    end
    base(args...)
end
