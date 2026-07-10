# Fragment of `ReferenceModule` — the reference-path *types* (steps, paths,
# their `@document`-generated struct forms) plus the value protocol on them
# (`append_reference`, `evaluate_reference`, `is_valid_reference`,
# `annotate_reference_types`, …). The DSL fragments `ReferenceCase.jl` and
# `ReferenceBuilder.jl` build on these; both are included by
# `ReferenceModule.jl` after this one.

# ── ReferenceStep ─────────────────────────────────────────────────────

"""
    ReferenceStep

Abstract base type for reference steps. Each subtype describes how to
descend one level into a document structure.
"""
abstract type ReferenceStep end

"""
    RangeReference(start, stop)

Unified sequence step.  Encodes:
- **Cursor position** (start == stop): a position between elements (0-based).
- **Single element**  (stop == start + 1): element at 1-based index `start + 1`.
- **Range**           (stop > start + 1): a multi-element selection.

All positions are 0-based boundaries.  For a collection with n elements,
valid boundaries are 0 to n.
"""
@document struct RangeReference <: ReferenceStep
    start::Int
    stop::Int
end

# `RangeReference(start, stop)` needs no explicit Int constructor: the `@document`
# inner constructor auto-wraps raw values into `Cell`s (and passes `Cell`s
# through). Same for `FieldReference`/`PointReference` below.

# ── Backward-compatible constructors ─────────────────────────────────────

"""
    ElementReference(index)

Construct a `RangeReference` representing the `index`-th element (1-based).
Equivalent to `RangeReference(index - 1, index)`.
"""
ElementReference(index::Int) = RangeReference(index - 1, index)

"""
    PositionReference(index)

Construct a `RangeReference` representing a cursor position (0-based).
Equivalent to `RangeReference(index, index)`.
"""
PositionReference(index::Int) = RangeReference(index, index)

# ── Predicates ────────────────────────────────────────────────────────────

"True when `r` encodes a single element (stop == start + 1)."
is_element_reference(r::RangeReference) = r.stop == r.start + 1

"True when `r` encodes a cursor position (start == stop)."
is_position_reference(r::RangeReference) = r.start == r.stop


"""
    FieldReference(name)

References a named field of an object/record.
"""
@document struct FieldReference <: ReferenceStep
    name::String
end

"""
    TypeReference(type)

A **non-navigating type checkpoint**: asserts that the node reached so far is a
`type`. Evaluation does not descend — it stays on the current node and continues
with the rest of the path. The point of the checkpoint is *validity*: when a
stored path is replayed against a document whose structure has changed, a
`TypeReference` whose recorded `type` no longer matches the actual node marks the
**remaining path as invalid** (see [`evaluate_reference`](@ref),
[`get_valid_reference_prefix`](@ref), [`annotate_reference_types`](@ref)).

The match rule is `node isa type`. Checkpoints are normally created from
`typeof(node)` by [`annotate_reference_types`](@ref), so on an unchanged document
the assertion holds exactly; recording an abstract supertype is also tolerated.
"""
@document struct TypeReference <: ReferenceStep
    type::Any
end

"""
    ReferenceTypeMismatch(expected, actual)

Thrown by [`evaluate_reference`](@ref) when a [`TypeReference`](@ref) checkpoint
does not hold: the node reached is an `actual` but the checkpoint expected an
`expected`. Callers that replay possibly-stale references catch this specifically
to distinguish a structural mismatch from a genuine bug.
"""
struct ReferenceTypeMismatch <: Exception
    expected::Any
    actual::Any
end

Base.showerror(io::IO, e::ReferenceTypeMismatch) =
    print(io, "ReferenceTypeMismatch: expected node of type ", e.expected,
          ", got ", e.actual)

# ── ReferencePath (immutable linked list) ────────────────────────────────

"""
    ReferencePath

Abstract base type for a path into a document. Implemented as an
immutable linked list so that extending a path (going deeper) reuses
the existing tail — no copying required.
"""
abstract type ReferencePath end

"""
    EmptyReferencePath([type])

The empty reference path — a path that terminates *at* a node. `type` records the
Julia type of the node the path lands on (the **terminal** node's type); it is
`nothing` for a plain/unknown path or for a cursor terminal (a `{k}` position
between items lands on no child node). A whole-element (`∅`) selection of a typed
node carries that node's type here.

The type is a field of the terminal node, not a separate trailing
`TypeReference` checkpoint step.
"""
@document struct EmptyReferencePath <: ReferencePath
    type::Any = nothing
end

"""
    Reference

Union type for document selection fields: either `nothing` (no selection)
or a `ReferencePath` describing the selected location.
"""
const Reference = Union{Nothing, ReferencePath}

"""
    ConcreteReferencePath([type], head, tail)

A non-empty path node. `head` is **always a navigation step** (never a
`TypeReference`); `tail` is the remaining `ReferencePath`. `type` records the
Julia type of the node you are standing on *at this node* — i.e. the type the
`head` step descends *from*. It is `nothing` when the type is unknown (a plain
`@reference` skeleton, or a generic two-arg construction); `annotate_reference_types`
fills it in against a document.

The node type is stored *on the node* rather than in a separate interleaved
`TypeReference` checkpoint step before `head`. A step's *end* type is its `tail`
node's `type`, so a `FieldReference` needs no second checkpoint — the boundary
type is stored once, on the downstream node, and serves both as this step's
result and the next step's source.

# Example

    path = ConcreteReferencePath(FieldReference("address"),
               ConcreteReferencePath(FieldReference("city"),
                   EmptyReferencePath()))
"""
@document struct ConcreteReferencePath <: ReferencePath
    type::Any
    head::ReferenceStep
    tail::ReferencePath
end

# Backward-compatible two-arg construction: type unknown (`nothing`). Fully
# untyped so it also catches the pre-wrapped `ConcreteReferencePath(Cell(h), Cell(t))`
# call sites; the `@document` inner constructor Cell-wraps each field as needed.
ConcreteReferencePath(head, tail) = ConcreteReferencePath(nothing, head, tail)

# Whole-element ("tree") selection is not a distinct reference step: it is just
# a path that terminates *at* the element, i.e. an `EmptyReferencePath`. The one
# node holding `∅` in its `selection` cell is the wholly-selected one; its
# ancestors hold a non-empty path routing down to it, and its descendants hold
# `nothing`. `evaluate_reference(document, EmptyReferencePath())` already returns
# the element itself, so no marker step is needed.

# ── Convenience constructors ─────────────────────────────────────────────

ConcreteReferencePath(head::ReferenceStep) = ConcreteReferencePath(nothing, head, EmptyReferencePath())

"""
    ReferencePath(steps::ReferenceStep...)

Build a `ReferencePath` from a sequence of reference steps (left = outermost).
"""
function ReferencePath(steps::ReferenceStep...)
    path = EmptyReferencePath()
    for i in length(steps):-1:1
        path = ConcreteReferencePath(steps[i], path)
    end
    path
end

# ── Accessors ────────────────────────────────────────────────────────────

Base.isempty(::EmptyReferencePath) = true
Base.isempty(::ConcreteReferencePath) = false

head(p::ConcreteReferencePath) = p.head
tail(p::ConcreteReferencePath) = p.tail

Base.length(::EmptyReferencePath) = 0
Base.length(p::ConcreteReferencePath) = 1 + length(tail(p))

# ── Iteration ────────────────────────────────────────────────────────────

Base.iterate(::EmptyReferencePath) = nothing
Base.iterate(p::ConcreteReferencePath) = (head(p), tail(p))
Base.iterate(::EmptyReferencePath, ::ReferencePath) = nothing
Base.iterate(::ConcreteReferencePath, rest::ReferencePath) = iterate(rest)

Base.eltype(::Type{<:ReferencePath}) = ReferenceStep

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, s::RangeReference)
    if is_element_reference(s)
        print(io, "[", s.start + 1, "]")
    elseif is_position_reference(s)
        print(io, "{", s.start, "}")
    else
        print(io, "{", s.start, ":", s.stop, "}")
    end
end

function Base.show(io::IO, s::FieldReference)
    print(io, ".", s.name)
end

function Base.show(io::IO, s::TypeReference)
    print(io, "::", s.type)
end

# Short name of a recorded node type, e.g. `Foo` rather than the fully-qualified
# `SomeModule.Foo`; falls back to `string` for non-types.
_show_node_type(io::IO, t) = print(io, "::", t isa Type ? nameof(t) : t)

function Base.show(io::IO, e::EmptyReferencePath)
    e.type === nothing ? print(io, "∅") : _show_node_type(io, e.type)
end

function Base.show(io::IO, p::ConcreteReferencePath)
    # Folded: print this node's recorded type (if any) before its navigation step.
    p.type === nothing || _show_node_type(io, p.type)
    show(io, head(p))
    t = tail(p)
    if t isa EmptyReferencePath
        t.type === nothing || _show_node_type(io, t.type)
    else
        show(io, t)
    end
end


# ── Equality ─────────────────────────────────────────────────────────────

Base.:(==)(a::RangeReference,      b::RangeReference)      = a.start  == b.start  && a.stop == b.stop
Base.:(==)(a::FieldReference,      b::FieldReference)      = a.name   == b.name
Base.:(==)(a::TypeReference,       b::TypeReference)       = a.type     === b.type
Base.:(==)(::ReferenceStep,        ::ReferenceStep)        = false

# Strict equality: the folded node `type` fields are significant, so an
# annotated (canonical) path is not `==` its stripped skeleton. Callers that
# want a shape-only comparison strip both sides first
# (`strip_reference_types(a) == strip_reference_types(b)`).
Base.:(==)(a::EmptyReferencePath,   b::EmptyReferencePath)   = a.type === b.type
Base.:(==)(::EmptyReferencePath,   ::ConcreteReferencePath) = false
Base.:(==)(::ConcreteReferencePath, ::EmptyReferencePath)  = false
Base.:(==)(a::ConcreteReferencePath, b::ConcreteReferencePath) =
    a.type === b.type && head(a) == head(b) && tail(a) == tail(b)

"""
    is_reference_equal(a, b)

Structural equality of two reference paths. **Strict**: node type fields are
significant, so an annotated path is not equal to its stripped form.
"""
is_reference_equal(a::ReferencePath, b::ReferencePath) = a == b

"""
    is_prefix_of(a, b)

Return `true` if reference path `a` is a proper prefix of `b` (i.e. `a` is
strictly shorter and matches the leading steps of `b`).
"""
is_prefix_of(::EmptyReferencePath, ::EmptyReferencePath) = false
is_prefix_of(::EmptyReferencePath, ::ConcreteReferencePath) = true
is_prefix_of(::ConcreteReferencePath, ::EmptyReferencePath) = false
is_prefix_of(a::ConcreteReferencePath, b::ConcreteReferencePath) =
    a.type === b.type && head(a) == head(b) && is_prefix_of(tail(a), tail(b))

# ── Path construction helpers ────────────────────────────────────────────

"""
    append_reference(base::ReferencePath, steps::ReferenceStep...) -> ReferencePath

Return a new `ReferencePath` formed by appending `steps` to the end of
`base`. The first step in `steps` becomes the direct successor of the last
step already in `base`.

Folded node types are preserved: every node of `base` keeps its recorded `type`,
and `base`'s terminal type — the type of the node the first appended step descends
*from* — is carried onto that first new node. Later appended nodes are untyped
(`nothing`), since the types they would stand on are not yet known. For an untyped
`base` this is a plain skeleton, exactly as before.
"""
function append_reference(base::EmptyReferencePath, steps...)
    isempty(steps) && return base
    # `base.type` is the type of the node the first appended step descends from.
    ConcreteReferencePath(base.type, steps[1], append_reference(EmptyReferencePath(), steps[2:end]...))
end

function append_reference(base::ConcreteReferencePath, steps...)
    ConcreteReferencePath(base.type, base.head, append_reference(tail(base), steps...))
end

"""
    concat_references(a::ReferencePath, b::ReferencePath) -> ReferencePath

Concatenate two reference paths, **preserving folded node types** on both. Every
node of `a` and of `b` keeps its own recorded `type`. The single junction boundary
— where `a`'s terminal meets `b`'s first node — takes `b`'s type, or, when `b`'s
first node has none, `a`'s terminal type, so an annotated prefix is not silently
de-annotated. It never invents a type. For untyped inputs the result is a plain
skeleton, identical to a naive rebuild.

This is the one canonical path-concatenation (vs `append_reference`, which appends
raw *steps*); readers/builders that splice whole paths route through it.
"""
concat_references(a::ConcreteReferencePath, b::ReferencePath) =
    ConcreteReferencePath(a.type, a.head, concat_references(tail(a), b))
concat_references(a::EmptyReferencePath, b::ConcreteReferencePath) =
    b.type === nothing ? ConcreteReferencePath(a.type, b.head, tail(b)) : b
concat_references(a::EmptyReferencePath, b::EmptyReferencePath) =
    EmptyReferencePath(b.type === nothing ? a.type : b.type)

"""
    reference_steps(path::ReferencePath) -> Vector{ReferenceStep}

Unroll `path` into its ordered vector of navigation steps (heads), dropping the
terminal type/`EmptyReferencePath`. The inverse is `ReferencePath(steps...)`, which
rebuilds a plain (untyped) skeleton — so this pair is the shared "path ↔ steps
vector" conversion used by callers that need to inspect or rewrite a path's tail
(e.g. splitting off the terminal step). Type checkpoints are read as steps; strip
first (`strip_reference_types`) when a pure navigation skeleton is wanted.
"""
function reference_steps(path::ReferencePath)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    steps
end

# ── Reference validation ─────────────────────────────────────────────────

"""
    is_valid_reference(obj)

Check if `obj` is a valid reference step or reference path.

Returns `true` if `obj` is a subtype of `Reference` or `ReferencePath`,
and for `ConcreteReferencePath`, recursively validates that the head and
tail cells contain valid reference steps and paths.

# Examples

```julia
is_valid_reference(PositionReference(1))  # true
is_valid_reference(FieldReference("name"))  # true
is_valid_reference(EmptyReferencePath())  # true
is_valid_reference("not a reference")  # false
is_valid_reference(42)  # false
```
"""
is_valid_reference(::ReferenceStep) = true
is_valid_reference(::EmptyReferencePath) = true

function is_valid_reference(obj::ConcreteReferencePath)
    # Recursively validate head and tail
    try
        head_step = obj.head
        tail_path = obj.tail
        return is_valid_reference(head_step) && is_valid_reference(tail_path)
    catch
        return false  # Cell evaluation failed or contains invalid data
    end
end

is_valid_reference(::Any) = false

# ── Reference evaluation ─────────────────────────────────────────────────

# Cells are transparent to reference navigation: a step that lands on a `Cell`
# descends into its value. Field access already unwraps inline (`f isa Cell ?
# f[] : f`); element/range access must do the same, otherwise a step into a plain
# `Vector{Cell}` would stop on the raw `Cell` and the rest of the path — recorded
# against the *unwrapped* value — would fail to resolve (and
# `annotate_reference_types` would stop adding type checkpoints there).
# `CellVector` already unwraps on `getindex`, so this is a no-op for it.
_deref_cell(x) = x isa AbstractCell ? x[] : x

# A `FieldReference` addresses a struct field by name — OR, when the document is
# an `AbstractDict`, a dict entry by key. A reference into a dict records the
# entry this way (the reference grammar has no dedicated key step), so navigation
# must follow it back. Dict keys may be stored as `String` or `Symbol`; the
# recorded name is the `string(key)`, so try it as both. Results are cell-unwrapped.
_has_field(document::AbstractDict, name) = haskey(document, name) || haskey(document, Symbol(name))
_has_field(document, name) = hasproperty(document, Symbol(name))

function _get_field(document::AbstractDict, name)
    haskey(document, name) && return _deref_cell(document[name])
    _deref_cell(document[Symbol(name)])
end
_get_field(document, name) = _deref_cell(getfield(document, Symbol(name)))

# ── Step navigation seam ──────────────────────────────────────────────────
# Each step type registers its own behaviour by adding methods on
# `step_kind` (classification) and `evaluate_step` (one-level navigation).
# The three path walkers (`evaluate_reference`,
# `get_valid_reference_prefix`, `annotate_reference_types`) all dispatch
# through this seam — a new step type living in a higher package registers
# its methods at its own definition site and needs no edits here.

"""
    step_kind(step) -> Symbol

Classify a reference step: `:structural` (descends into a child),
`:checkpoint` (stays on the current node, asserts an invariant), or
`:terminal` (identifies a location but does not participate in navigation).
The default is `:terminal` — a step type that doesn't opt in explicitly is
treated as terminal, matching the pre-seam behaviour that non-navigating
steps error under `evaluate_reference` and only survive
`get_valid_reference_prefix` when they end the path.
"""
step_kind(::ReferenceStep) = :terminal

"""
    evaluate_step(step, document) -> child

Navigate through `step`. For a `:structural` step, return the child
document (throws on descent failure). For a `:checkpoint` step, return
`document` unchanged after asserting the invariant (throws on mismatch).
Not called for `:terminal` steps.
"""
function evaluate_step end

# ── Kernel step-type methods ─────────────────────────────────────────────

step_kind(::RangeReference) = :structural
step_kind(::FieldReference) = :structural
step_kind(::TypeReference)  = :checkpoint

# element / cursor / range — element access at start+1 (cell-transparent).
evaluate_step(step::RangeReference, document) =
    _deref_cell(document[step.start + 1])

evaluate_step(step::FieldReference, document) =
    _get_field(document, step.name)

function evaluate_step(step::TypeReference, document)
    document isa step.type ||
        throw(ReferenceTypeMismatch(step.type, typeof(document)))
    document
end

"""
    evaluate_reference(document, path::ReferencePath)

Navigate into `document` by following each step in `path` in order.
Returns the sub-document reached at the end of the path.
"""
function evaluate_reference(document, path::EmptyReferencePath)
    # Folded terminal checkpoint: assert the landed node's recorded type.
    path.type === nothing || document isa path.type ||
        throw(ReferenceTypeMismatch(path.type, typeof(document)))
    document
end

function evaluate_reference(document, path::ConcreteReferencePath)
    step = path.head
    rest = path.tail
    # Folded checkpoint: this node records the type of the document it stands on.
    path.type === nothing || document isa path.type ||
        throw(ReferenceTypeMismatch(path.type, typeof(document)))
    kind = step_kind(step)
    kind === :terminal &&
        error("Cannot evaluate through terminal-only reference step: $(typeof(step))")
    child = evaluate_step(step, document)
    evaluate_reference(child, rest)
end

# ── Document-aware validity ──────────────────────────────────────────────

"""
    get_valid_reference_prefix(document, path::ReferencePath) -> ReferencePath

Walk `path` against `document` and return the **longest prefix that still
navigates cleanly**. Traversal stops — and the path is truncated — at the first
step that fails: a [`TypeReference`](@ref) checkpoint whose recorded type no
longer matches the node reached, or a structural step that cannot be followed
(missing field, out-of-range index, …). The returned prefix is exactly the part
that `evaluate_reference` can still resolve; the discarded suffix is the part
made invalid by a structural change to `document`.
"""
function get_valid_reference_prefix(document, path::EmptyReferencePath)
    # Folded terminal checkpoint: drop the recorded type if it no longer holds.
    (path.type === nothing || document isa path.type) ? path : EmptyReferencePath()
end

function get_valid_reference_prefix(document, path::ConcreteReferencePath)
    # Folded node checkpoint: truncate here if this node's recorded type no longer
    # matches the document reached.
    path.type === nothing || document isa path.type || return EmptyReferencePath()
    step = path.head
    rest = path.tail
    kind = step_kind(step)
    if kind === :terminal
        # Terminal-only steps (no document navigation) survive only when this is
        # the last step of the path; otherwise the trailing structure has no
        # meaning to walk further and is truncated.
        return rest isa EmptyReferencePath ? path :
               ConcreteReferencePath(path.type, step, EmptyReferencePath())
    end
    if kind === :checkpoint
        # Assert on the current node; a mismatch truncates.
        try
            evaluate_step(step, document)
        catch
            return EmptyReferencePath()
        end
        return get_valid_reference_prefix(document, rest)
    end
    # :structural — try to descend one level. `getindex` on a range step is
    # allowed to throw (out-of-range, non-indexable container without a length
    # method) and simply truncates.
    child = try
        evaluate_step(step, document)
    catch
        return EmptyReferencePath()
    end
    ConcreteReferencePath(path.type, step, get_valid_reference_prefix(child, rest))
end

"""
    is_valid_reference(document, path::ReferencePath) -> Bool

Document-aware validity: `true` iff every step of `path` — in particular every
[`TypeReference`](@ref) checkpoint — resolves against `document`. Equivalent to
`get_valid_reference_prefix(document, path) == path`. This is distinct from the
single-argument [`is_valid_reference`](@ref) which only checks *structural*
well-formedness of the reference object itself.
"""
is_valid_reference(document, path::ReferencePath) =
    get_valid_reference_prefix(document, path) == path

# ── Type-checkpoint annotation ───────────────────────────────────────────

"""
    annotate_reference_types(document, path::ReferencePath) -> ReferencePath

Return `path` with each node's `type` field **filled in** against `document`: a
`ConcreteReferencePath` records `typeof(node)` of the document it stands on, and
the terminal `EmptyReferencePath` records the type of the node the path lands on.
This is the *folded* canonical form — the type lives on each node, not as a
separate interleaved `TypeReference` step. The result can be persisted and later
re-checked with [`get_valid_reference_prefix`](@ref) / the document-aware
[`is_valid_reference`](@ref) to detect structural changes. Inverse of
[`strip_reference_types`](@ref).

A zero-width position (`{k}`) is a cursor *between* items — it lands on no child
node, so the terminal after it keeps `type === nothing`.
"""
# The kind-agnostic name of a node's type: the UnionAll wrapper of a
# kind-parameterized `@document` type (`JsonString{ImmutableCell{String},…}` →
# `JsonString`), or the type itself for a non-parametric (hand-written) document.
# Recording the wrapper makes type checkpoints kind-agnostic: a path annotated on
# a reactive node still `isa`-matches its immutable snapshot, and matches the bare
# names the `@reference` macro emits. `typename(T).wrapper` handles both cases.
_node_type(document) = Base.typename(typeof(document)).wrapper

function annotate_reference_types(document, ::EmptyReferencePath)
    # Whole-element / terminal node: record the type of the node it lands on.
    EmptyReferencePath(_node_type(document))
end

function annotate_reference_types(document, path::ConcreteReferencePath)
    step = path.head
    rest = path.tail
    # Checkpoint steps get folded away — this node's type replaces the
    # standalone assertion.
    step_kind(step) === :checkpoint && return annotate_reference_types(document, rest)
    nodetype = _node_type(document)
    # A zero-width position is a cursor *between* items, not a descent into
    # one — leave the node it would reach untyped. Otherwise, ask the step
    # to descend; a throw or `nothing` means no child to annotate.
    child = if step isa RangeReference && is_position_reference(step)
        nothing
    else
        try
            evaluate_step(step, document)
        catch
            nothing
        end
    end
    annotated_rest = child === nothing ? rest : annotate_reference_types(child, rest)
    ConcreteReferencePath(nodetype, step, annotated_rest)
end

"""
    strip_reference_types(path::ReferencePath) -> ReferencePath

Return `path` reduced to its plain navigation skeleton: every node's recorded
`type` is blanked to `nothing` and any leftover (transitional) `TypeReference`
*step* is dropped. Inverse of [`annotate_reference_types`](@ref) — used at
boundaries that re-annotate against a fresh document (e.g. `set_selection!`).
"""
strip_reference_types(::EmptyReferencePath) = EmptyReferencePath()

function strip_reference_types(path::ConcreteReferencePath)
    step = path.head
    rest = strip_reference_types(path.tail)
    step isa TypeReference ? rest : ConcreteReferencePath(nothing, step, rest)
end

# Permissive fallback, mirroring `skip_type_checkpoints`: callers may apply this
# to a non-path (e.g. `nothing` when there is no selection); pass it through
# unchanged so the structural reads downstream handle the absence themselves.
strip_reference_types(other) = other

"""
    fold_reference_types(path::ReferencePath) -> ReferencePath

Convert a flat path that may carry interleaved `TypeReference` *steps* into the
folded form where the type lives on each node. A `TypeReference(T)` step sets the
`type` of the node built from the **following** navigation step (or the terminal
node, if it is the last step). Nodes that already carry a folded `type` keep it
(so concatenating an already-folded sub-path is preserved). Used by the
`@reference` builder to fold the `::T` checkpoints it emits as steps.
"""
fold_reference_types(path::ReferencePath) = _fold_reference_types(path, nothing)

_fold_reference_types(p::EmptyReferencePath, pending) =
    EmptyReferencePath(pending === nothing ? p.type : pending)

function _fold_reference_types(p::ConcreteReferencePath, pending)
    if p.head isa TypeReference
        # A checkpoint step types the *next* navigation node — carry it forward.
        return _fold_reference_types(p.tail, p.head.type)
    end
    ConcreteReferencePath(pending === nothing ? p.type : pending, p.head,
                          _fold_reference_types(p.tail, nothing))
end

fold_reference_types(other) = other

# ── Reference collection ─────────────────────────────────────────────────────

"""
    collect_references(document, search_value) -> Vector{ReferencePath}

Search the document tree for all occurrences of `search_value` and return their
reference paths. This is useful for finding all locations where a specific value
appears in the document.

The function recursively traverses the document structure, handling both Cell-wrapped
and unwrapped values, and collects reference paths for all matches.

Returns a vector of `ReferencePath` objects for all matches, or an empty vector if
no matches are found.
"""
function collect_references(document, search_value)
    try
        results = ReferencePath[]
        _search_document(document, EmptyReferencePath(), search_value, results)
        # Produced references leave this function in canonical form: annotate each
        # plain path against the document it points into, so search results are
        # self-describing (every step records the type it descends from) and carry
        # replay-validation checkpoints.
        return ReferencePath[annotate_reference_types(document, p) for p in results]
    catch e
        @error "Error collecting references" exception = e
        return ReferencePath[]
    end
end

# Best-effort reflection walk over arbitrary values, so each probe below tolerates
# a throw rather than aborting the whole search. The swallows are intentional but
# no longer silent: they surface under `@debug` logging (compiled out otherwise).
function _search_document(node, current_path, search_value, results)
    # Match check: a user-defined `==` or a `.value` access may throw; a throw here
    # just means "not a match at this node", so fall through to the field walk.
    try
        if hasfield(typeof(node), :value) && getfield(node, :value) isa AbstractCell
            if getfield(node, :value)[] == search_value
                push!(results, current_path)
                return
            end
        elseif node == search_value
            push!(results, current_path)
            return
        end
    catch e
        @debug "collect_references: match check threw; treating as non-match" exception = e
    end

    # Skip non-document types
    node isa Union{AbstractString, Number, Bool, Nothing, Symbol} && return
    node isa ReferencePath && return

    # Use reflection to recursively search all fields
    T = typeof(node)
    isstructtype(T) || return
    for fname in fieldnames(T)
        fval = getfield(node, fname)
        field_path = append_reference(current_path, FieldReference(string(fname)))
        if fval isa AbstractCell
            # An error deep in one field's subtree drops that branch, not the rest.
            try
                _search_document(fval[], field_path, search_value, results)
            catch e
                @debug "collect_references: recursion into $fname threw" exception = e
            end
        elseif !(fval isa Union{AbstractString, Number, Bool, Nothing, Symbol}) && !(fval isa ReferencePath)
            # Probe whether the field is iterable; a non-iterable throws from
            # `iterate` and we fall back to a struct recursion below.
            iterated = false
            try
                r = iterate(fval)
                if r !== nothing
                    iterated = true
                    idx = 1
                    while r !== nothing
                        (elem, state) = r
                        elem_path = append_reference(field_path, RangeReference(idx - 1, idx))
                        _search_document(elem, elem_path, search_value, results)
                        idx += 1
                        r = iterate(fval, state)
                    end
                end
            catch e
                @debug "collect_references: iteration probe on $fname threw" exception = e
            end
            # If not iterable, recurse as struct
            if !iterated && isstructtype(typeof(fval))
                _search_document(fval, field_path, search_value, results)
            end
        end
    end
end
