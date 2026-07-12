# Fragment of `ReferenceModule` — the reference-path *types* (steps, paths,
# their `@document`-generated struct forms) plus the value protocol on them
# (`append_reference`, `evaluate_reference`, `annotate_reference_types`, …).
# The DSL fragments `ReferenceCase.jl` and `ReferenceBuilder.jl` build on
# these; both are included by `ReferenceModule.jl` after this one.

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

# ── Convenience step constructors ───────────────────────────────────────

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
    Position(index)

The value a zero-width cursor step (`{k}`) evaluates to: a caret *between*
elements at 0-based `index`, not a document node. Every reference is
evaluatable (the types-always-present invariant), and a cursor's "empty
something" is a `Position`. A path terminating at a cursor therefore records
`Position` as its terminal type (`…{k}::Position`), and
`evaluate_reference` of such a path returns `Position(k)` — a signal that the
target is a caret, distinct from a document node reached by a structural step.
"""
struct Position
    index::Int
end

Base.:(==)(a::Position, b::Position) = a.index == b.index
Base.show(io::IO, p::Position) = print(io, "Position(", p.index, ")")


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

# Two-arg construction: type unknown (`nothing`). Fully
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

Classify a reference step: `:structural` (descends to a child or
synthetic value) or `:checkpoint` (stays on the current node, asserts an
invariant). The default is `:structural` — every step must be evaluatable
under the "types always present" invariant; a step type that doesn't opt
into `:checkpoint` is expected to implement `evaluate_step`.
"""
step_kind(::ReferenceStep) = :structural

"""
    evaluate_step(step, document) -> child

Navigate through `step`. For a `:structural` step, return the descended
value (throws on descent failure). Some step types descend to a document
child (`FieldReference`, `RangeReference`); others descend to a synthetic
value that stands in for the reference target (`PointReference` returns a
coordinate pair, `ProjectionReference` returns the projection's output
path, `TextRectangularReference` returns the character range). For a
`:checkpoint` step, return `document` unchanged after asserting the
invariant (throws on mismatch).
"""
function evaluate_step end

# ── Kernel step-type methods ─────────────────────────────────────────────

step_kind(::RangeReference) = :structural
step_kind(::FieldReference) = :structural
step_kind(::TypeReference)  = :checkpoint

# A zero-width cursor evaluates to a `Position` (a caret between elements); a
# single element / range descends into the item at start+1 (cell-transparent).
function evaluate_step(step::RangeReference, document)
    is_position_reference(step) && return Position(step.start)
    _deref_cell(document[step.start + 1])
end

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
    if step_kind(step) === :checkpoint
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
`get_valid_reference_prefix(document, path) == path`.
"""
is_valid_reference(document, path::ReferencePath) =
    get_valid_reference_prefix(document, path) == path

# ── Type-checkpoint annotation ───────────────────────────────────────────

"""
    reference_node_type(document) -> Type

The kind-agnostic type token a reference records for `document`: the UnionAll
wrapper of a kind-parameterized `@document` type
(`JsonString{ImmutableCell{String},…}` → `JsonString`), or the type itself for
a non-parametric (hand-written) document. Recording the wrapper makes the type
kind-agnostic — a reference typed on a reactive node still `isa`-matches its
immutable snapshot, and matches the bare names the `@reference` macro emits.

Generic reference-mapping code that constructs a typed reference against a
runtime document (rather than a statically named type) reads the type from
here — e.g. a whole-element selection mapped across a projection carries
`reference_node_type(output_document)`.
"""
reference_node_type(document) = Base.typename(typeof(document)).wrapper

# Internal alias kept for the annotation walkers below.
const _node_type = reference_node_type

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
    # Descend one step to type the rest. A zero-width cursor descends to a
    # `Position` (so its terminal records `::Position`); a structural step that
    # cannot be followed throws and leaves the rest untyped.
    child = try
        evaluate_step(step, document)
    catch
        nothing
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

# ── Strict-typing invariant ──────────────────────────────────────────────────
#
# Every `@reference` literal must carry a type on every folded node — and on the
# terminal: "types always present, period". `@reference` routes its result
# through `_strict_check`, which throws when any node is untyped, so a bare
# navigation skeleton is never a valid `@reference` result. (Skeletons still
# exist internally — `@reference(document, …)` builds one and annotates it, and
# `strip_reference_types` produces one — but they are never surfaced untyped.)

"""
    is_fully_typed(path::ReferencePath) -> Bool

`true` when every node of `path` (each `ConcreteReferencePath` and the terminal
`EmptyReferencePath`) records a non-`nothing` `type`. This is the strict-typing
invariant `@reference` enforces: a path built from a fully-typed `@reference`
literal (or annotated against a document) is fully typed; a path with any bare
navigation node is not.
"""
is_fully_typed(p::ConcreteReferencePath) = p.type !== nothing && is_fully_typed(p.tail)
is_fully_typed(p::EmptyReferencePath)    = p.type !== nothing
is_fully_typed(::Nothing)                = true   # no-selection sentinel: not our concern

# Enforce the strict-typing invariant on a freshly built `@reference` path.
# `src` is the macro-call `LineNumberNode`, so a violation names its file:line.
function _strict_check(path, src)
    is_fully_typed(path) && return path
    error("under-typed @reference (missing node types) at $(src.file):$(src.line)")
end

# ── Reflection search: matching paths ───────────────────────────────────────
# `search_references` reports *where* each matching node lives, as an annotated
# `ReferencePath`. Like `search_documents` (the value-collecting counterpart one
# layer down in the document layer) it is document-scoped by default — a raw
# scalar match folds to the path of its nearest enclosing `Document`, so the path
# is selectable — with a `raw=true` opt-out. The two walks are structurally
# parallel; keep them in sync. The small query / leaf helpers below duplicate the
# document layer's one-liners (as `_deref_cell` above already does) rather than
# importing them across the layer boundary; they key off the exported `is_opaque`
# / `is_element_collection` document traits.

# A node is a search leaf — nothing to descend into — when it is a scalar Julia
# value or an opaque document (see `is_opaque`).
_is_search_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                     x isa Symbol || x isa Char || is_opaque(x)

# A search query is either a predicate (called on each node) or a String / Regex.
# A String/Regex is turned into a predicate matching any *leaf* node whose textual
# form (the string / symbol / number / char rendered) contains the substring /
# matches the regex. Struct and collection nodes have no textual form, so they
# never match a String/Regex query — pass a predicate to match on type or shape.
_search_text(x::AbstractString) = x
_search_text(x::Symbol)         = string(x)
_search_text(x::Number)         = string(x)
_search_text(x::Char)           = string(x)
_search_text(::Any)             = nothing

_text_query(q::AbstractString) = x -> (t = _search_text(x); t !== nothing && occursin(q, t))
_text_query(q::Regex)          = x -> (t = _search_text(x); t !== nothing && occursin(q, t))

"""
    search_references(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector{ReferencePath}
    search_references(obj, query::Union{AbstractString,Regex}; …)                      -> Vector{ReferencePath}

Walk any object and return a `ReferencePath` to every match. Pass a predicate, or
a `String` (substring) / `Regex` that matches leaf nodes by their textual form,
e.g. `search_references(editor.document, "Alice")` or `search_references(doc, r"TODO|FIXME")`.
Cells are unwrapped transparently (no path step); struct fields contribute a
`FieldReference`, and array / `CellVector` elements an `ElementReference`.

By default the paths are **document-scoped**: a match on a raw scalar folds to
the path of its nearest enclosing `Document`, so every returned path addresses a
selectable node and can be handed to `set_selection!` / `replace_selection!`.
Pass `raw=true` to get the path to the **exact matched node** instead (scalar
leaves included) — the path-valued counterpart to `search_documents(...; raw=true)`.

The returned paths are **canonical at rest**: each navigation step is preceded by
a `TypeReference(typeof(node))` checkpoint (via [`annotate_reference_types`](@ref)),
so results are self-describing and carry replay-validation checkpoints.
`evaluate_reference` honours the checkpoints; pass a result through
`strip_reference_types` first if a consumer needs the plain navigation-only path.

```julia
for ref in search_references(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    replace_selection!(editor.document, ref)
end
```

`include_selection` includes `selection` fields in the walk. Every distinct path
to a matching node is returned — a shared object reachable by several paths is a
different *location* (hence a different selection) each time, so all of them are
reported (document-scoped folding still reports each enclosing-document location
once). Only paths that loop back through an object already on the current path are
dropped, which keeps cyclic graphs (e.g. a doubly-linked list's `prev`/`next`)
finite. `maxdepth` separately bounds recursion depth for structures that are never
the *same* object, e.g. an infinite lazy list whose nodes are generated fresh on
demand. See [`search_documents`](@ref) for the matching nodes themselves (each once).

`obj` need not be a document: passing an **iomap** (`print_document(proj, doc)`)
walks the whole projection pipeline — every stage's input and output — so you can
find where a value lives across all stages. Paths rooted at an iomap are for
inspection only (not selectable); see the debugging guide's
"Searching the pipeline state".
"""
function search_references(obj, predicate; include_selection::Bool=false, maxdepth::Int=64, raw::Bool=false)
    results = ReferencePath[]
    root = _deref_cell(obj)
    _search_references!(results, IdDict{Any,Bool}(), root, predicate,
                        EmptyReferencePath(), nothing, IdDict{Any,Bool}(), include_selection, maxdepth, raw)
    # Leave search results in canonical form: annotate each plain navigation path
    # with `TypeReference(typeof(node))` checkpoints against `obj`, so the
    # references are self-describing and carry replay-validation checkpoints
    # (see annotate_reference_types).
    ReferencePath[annotate_reference_types(root, p) for p in results]
end

search_references(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_references(obj, _text_query(query); kwargs...)

# `enclosing_path` is the path to the nearest enclosing document (this node's own
# `path` when it is a document); a folded (`raw=false`) scalar match reports it.
# The walk-wide `reported` set dedups targets by identity: sibling scalars under
# one document share the same `enclosing_path` object, so that document's path is
# reported once, while distinct locations (distinct path objects) are all kept.
function _search_references!(results, reported, obj, predicate, path, enclosing_path, seen, include_selection, depth, raw)
    # Drop only paths that loop back through an object already on *this* path:
    # `seen` holds the current path's ancestors (copied per level), so distinct
    # paths to a shared object are all reported while a path returning to one of
    # its own ancestors is neither recorded nor descended (cyclic graphs stay finite).
    if ismutable(obj)
        haskey(seen, obj) && return
        seen = copy(seen); seen[obj] = true
    end
    here = obj isa Document ? path : enclosing_path
    if (try predicate(obj) catch; false end)
        target = raw ? path : here
        if target !== nothing && !haskey(reported, target)
            push!(results, target); reported[target] = true
        end
    end
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if is_element_collection(obj)
        for i in 1:length(obj)
            _search_references!(results, reported, _deref_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractDict
        # Walk a Dict by its values, not its `fieldnames` (which would descend into
        # the hash-table internals — `.keys`/`.vals` `Memory` buffers whose unused
        # slots are undefined references). Use the key as the field step so the
        # reference is meaningful (matches how a JSON object field is addressed).
        for (k, v) in obj
            _search_references!(results, reported, _deref_cell(v), predicate,
                            append_reference(path, FieldReference(string(k))), here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            _search_references!(results, reported, _deref_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), here, seen, include_selection, depth - 1, raw)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_references!(results, reported, _deref_cell(getfield(obj, fn)), predicate,
                            append_reference(path, FieldReference(string(fn))), here, seen, include_selection, depth - 1, raw)
        end
    end
end
