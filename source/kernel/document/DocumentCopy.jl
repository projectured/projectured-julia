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

Thrown when a copy can not own `value`. `reason` is a sentence that says what
`value` holds that the copy can not own. A hook throws it, and the walk does not
catch it at any depth.
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
copy_document(policy::CopyPolicy, v::AbstractVector) =
    _make_vector_copy(v, Any[copy_document(policy, x) for x in v])

# The copy of `v` that holds `copies`. It has the type of `v` when each copy is an
# instance of the element type of `v`, so it accepts every value that `v` accepts:
# a vector of an abstract type that holds one subtype takes a `push!` of another,
# and a list of slot cells stays a `Vector{Cell}` when it is empty. A copy of
# another type does not fit: a native element that a kinded copy converts, or the
# placeholder of a policy. The copy then takes the types of the values it holds.
function _make_vector_copy(v::AbstractVector, copies::Vector{Any})
    all(x -> x isa eltype(v), copies) || return [x for x in copies]
    out = similar(v, length(copies))
    for i in eachindex(copies)
        out[i] = copies[i]
    end
    out
end

# Cell: a fresh cell of the same kind and value type, holding the copied inner
# value. A cell that computes is the policy's to copy.
copy_document(policy::CopyPolicy, cell::AbstractCell) =
    is_computed_cell(cell) ? copy_computed_cell(policy, cell) :
                             make_similar_cell(cell, copy_document(policy, cell[]))

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
    # The UnionAll, with the parameters of the source: its ctor accepts cells/values.
    base = _apply_schema_parameters(Base.typename(T).wrapper, T)
    arguments = Any[]
    for name in field_names
        raw = getfield(document, name)
        push!(arguments, haskey(replacements, name) ?
                             _make_replacement_field(raw, _wrap_replacement_list(T, name, raw, replacements[name])) :
                         name === :selection && raw isa AbstractCell ?
                             copy_selection_cell(policy, raw) :
                         name === :mouse_target && raw isa AbstractCell ?
                             make_similar_cell(raw, nothing) :
                             copy_document(policy, raw))
    end
    result = base(arguments...)
    memo === nothing || (memo[document] = result)
    result
end

# `base` with the type parameters that the programmer declared on the schema of
# `T`, so that a copy keeps them. The bare name binds a parameter from a cell of
# `Any` as `Any`, and it can not bind one that no field is. A cell layout carries
# one more parameter for each field after them, and a native layout carries only
# them. A hand-written document is its own family, and `base` stays as it is.
function _apply_schema_parameters(base, T::DataType)
    wrapper = Base.typename(T).wrapper
    get_document_family(T) === wrapper && return base
    cells = wrapper === get_document_native_type(T) ? 0 : fieldcount(T)
    count = length(T.parameters) - cells
    count == 0 ? base : base{Tuple(T.parameters)[1:count]...}
end

# A plain vector that replaces a list field becomes the list of the field, in the
# kind of the cell that the field holds, as a constructor makes it.
function _wrap_replacement_list(T, name, raw, value)
    value isa AbstractVector || return value
    declared_type = find_declared_field_type(T, name)
    declared_type === nothing && return value
    list = _wrap_list_value_of(declared_type, value)
    list === value && return value
    raw isa ImmutableCell ? copy_document(ImmutableCell, list) :
    raw isa MutableCell   ? copy_document(MutableCell, list) : list
end

# A replacement for a field that holds a cell goes in a new cell of the same
# kind; a cell given as the replacement is used as it is.
_make_replacement_field(raw, value) =
    value isa AbstractCell ? value :
    raw isa AbstractCell   ? make_similar_cell(raw, value) :
                             value

Base.showerror(io::IO, e::DocumentCopyException) =
    print(io, "DocumentCopyException: a copy of a ", _get_refused_value_word(e.value),
          " is refused: ", e.reason)

# A word for what was refused. A closure's type has no name a person can read.
_get_refused_value_word(value::Function) = "function"
_get_refused_value_word(value::AbstractCell) = "cell"
_get_refused_value_word(value) = String(nameof(typeof(value)))

# ── The duplicate ──────────────────────────────────────────────────────────

"""
    DuplicatePolicy()

The policy of [`make_document_duplicate`](@ref). Made for one duplicate, because
it records every document it copies.

- The walk descends into a document whose kind declares a duplicate, and shares
  every other document: what the duplicate does not own, it reads.
- A cell that computes stops the copy, because a copy of its value looks live
  and is not. A selection does not stop it: it is view state, and the duplicate
  takes the selection as it is now (see [`copy_selection_cell`](@ref)).
- A function, a `Ref` and a `Task` stop the copy, because the walk can not read
  what they capture, and an action that captures the original acts on it.
- A document that holds itself stops the copy, unless the kind makes its own
  copy.

The copy stops with a [`DocumentCopyException`](@ref).
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
copy_document(::Type{<:AbstractCell}, value, policy, depth::Int) = value

# The short form: no bound, at the root of the copy.
copy_document(K::Type{<:AbstractCell}, value) = copy_document(K, value, nothing, 0)

copy_document(K::Type{<:AbstractCell}, v::AbstractVector, policy, depth::Int) =
    _copy_elements(K, v, policy, depth)

# The elements of `v`, which stand at `depth`, each copied as kind `K`. The copy
# stops after `compute_sync_element_limit`, with one placeholder that stands for the tail,
# and it keeps the element type of `v` as `_make_vector_copy` says.
function _copy_elements(K, v::AbstractVector, policy, depth)
    n = length(v)
    copies = Any[]
    limit = min(compute_sync_element_limit(policy, v, copies), n)
    for i in 1:limit
        push!(copies, _copy_element(K, v[i], policy, depth))
    end
    if limit < n
        m = make_unsynced_placeholder(policy, HiddenElements(v, limit + 1, n), nothing)
        push!(copies, _wrap_placeholder(K, v[limit + 1], m))
    end
    _make_vector_copy(v, copies)
end

# One element of a kinded copy. An element document faces the bound at `depth`,
# which is the depth at which `_sync_elements!` asks the bound for it.
function _copy_element(K, x, policy, depth::Int)
    inner = unwrap_cell(x)
    (inner isa Document && !is_descendable_for_sync(policy, depth, nothing)) ||
        return copy_document(K, x, policy, depth)
    _wrap_placeholder(K, x, make_unsynced_placeholder(policy, inner, nothing))
end

# The placeholder `m` wrapped exactly as a copy of the element `x` would be: a
# slot-celled vector (`Vector{Cell}`) cannot hold a bare document.
_wrap_placeholder(K, x, m) =
    x isa AbstractCell ? K{K === ReactiveCell ? Any : typeof(m)}(m) : m

function copy_document(K::Type{<:AbstractCell}, c::AbstractCell, policy, depth::Int)
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

function copy_document(K::Type{<:AbstractCell}, doc::Document, policy, depth::Int)
    T = typeof(doc)
    # The target is the schema's **cell layout**, not the source's own layout. A kind
    # is a property of a cell, so a kinded copy only means something in a tree that
    # has cells; a native source therefore converts here rather than rebuilding
    # itself. A native child in a reactive shadow could never invalidate a reader.
    base = _apply_schema_parameters(get_document_cell_type(T), T)
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
    # A native layout holds no mouse target, and the cell layout starts with none.
    names = fieldnames(base)
    length(args) < length(names) && names[length(args) + 1] === :mouse_target &&
        push!(args, K{_kinded_value_type(K, Ts, length(args) + 1, nothing)}(nothing))
    base(args...)
end
