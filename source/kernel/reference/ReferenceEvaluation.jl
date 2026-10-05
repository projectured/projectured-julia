# Fragment of `ReferenceModule` — walking a path **against a document**, and the
# "types always present" invariant that walk maintains.
#
# The three walkers are structurally parallel and all descend through the
# `evaluate_reference_step` seam declared in `ReferenceInterface.jl`:
#
# - `evaluate_reference`        — follow the path, return the node it lands on
# - `get_valid_reference_prefix` — follow as far as the document still allows
# - `annotate_reference_types`   — follow, recording each node's type as it goes
#
# The type protocol around them (`get_reference_node_type`, `strip_reference_types`,
# `fold_reference_types`, `is_fully_typed_reference`) is the same concept from the other
# side: a path is *canonical at rest* when every node records the type of the
# document node it stands on. The path shape these walk lives in
# `ReferencePath.jl`; the steps they descend through in `ReferenceStep.jl`.

# ── Reference evaluation ─────────────────────────────────────────────────

"""
    evaluate_reference(document, path::Reference)

Navigate into `document` by following each step in `path` in order.
Returns the sub-document reached at the end of the path.
"""
function evaluate_reference(document, path::EmptyReference)
    # Folded terminal checkpoint: assert the landed node's recorded type.
    path.type === nothing || document isa path.type ||
        throw(ReferenceTypeMismatchException(path.type, typeof(document)))
    document
end

function evaluate_reference(document, path::ConcreteReference)
    step = path.head
    rest = path.tail
    # Folded checkpoint: this node records the type of the document it stands on.
    path.type === nothing || document isa path.type ||
        throw(ReferenceTypeMismatchException(path.type, typeof(document)))
    child = evaluate_reference_step(step, document)
    evaluate_reference(child, rest)
end

"""
    try_evaluate_reference(document, path::Reference, default = nothing) -> node | default

`evaluate_reference` for a path that may not resolve: `default` when the path does
not resolve.

A path is not a guarantee. It can name a node that no longer exists (the document
changed under a stale selection), or one that never existed in `document` at all (a
projection-introduced position with no input pre-image). A caller that is *asking
whether* the path resolves — a gesture precondition deciding whether it has a target —
wants an answer, not an exception.

Two exceptions still go to the caller, because neither says that the path does not
resolve: an exception that means stop (`is_passthrough_exception`), and a
`MethodError` of `evaluate_reference_step` itself, which comes from a step with no
method — a fault of the program. Every method of that function takes a document of
any type, so such an error names a missing step method. A `TypeReferenceStep` left
in a path is one: the path was never folded.
"""
function try_evaluate_reference(document, path::Reference, default = nothing)
    try
        evaluate_reference(document, path)
    catch exception
        _is_walk_passthrough(exception) && rethrow()
        default
    end
end

# Whether an exception of a step goes on to the caller of a walker that answers a
# default for a path that does not resolve: an exception that means stop, or a step
# with no method of `evaluate_reference_step`.
_is_walk_passthrough(exception) =
    is_passthrough_exception(exception) ||
    (exception isa MethodError && exception.f === evaluate_reference_step)

# A selection is `nothing` when there is none, and "no selection" resolves to no node —
# so callers asking about a document's current selection need no separate guard.
try_evaluate_reference(document, ::Nothing, default = nothing) = default

# ── Document-aware validity ──────────────────────────────────────────────

"""
    get_valid_reference_prefix(document, path::Reference) -> Reference

Walk `path` against `document` and return the **longest prefix that still
navigates cleanly**. Traversal stops — and the path is truncated — at the first
place that fails: a node whose recorded type no longer matches the node reached,
or a step that cannot be followed (missing field, out-of-range index, …). The
returned prefix is exactly the part that `evaluate_reference` can still resolve;
the discarded suffix is the part made invalid by a structural change to
`document`.
"""
function get_valid_reference_prefix(document, path::EmptyReference)
    # Folded terminal checkpoint: drop the recorded type if it no longer holds.
    (path.type === nothing || document isa path.type) ? path : EmptyReference()
end

function get_valid_reference_prefix(document, path::ConcreteReference)
    # Folded node checkpoint: truncate here if this node's recorded type no longer
    # matches the document reached.
    path.type === nothing || document isa path.type || return EmptyReference()
    step = path.head
    rest = path.tail
    # Descend one level. `getindex` on a range step is allowed to throw
    # (out-of-range, non-indexable container without a length method) and simply
    # truncates.
    child = try
        evaluate_reference_step(step, document)
    catch exception
        _is_walk_passthrough(exception) && rethrow()
        return EmptyReference()
    end
    ConcreteReference(path.type, step, get_valid_reference_prefix(child, rest))
end

"""
    is_valid_reference(document, path::Reference) -> Bool

Document-aware validity: `true` iff every step of `path` resolves against
`document` and every node type that it records holds there. Equivalent to
`get_valid_reference_prefix(document, path) == path`.
"""
is_valid_reference(document, path::Reference) =
    get_valid_reference_prefix(document, path) == path

# ── Type-checkpoint annotation ───────────────────────────────────────────

"""
    get_reference_node_type(document) -> Type

The kind-agnostic and layout-agnostic type token a reference records for
`document`: the schema's **cell layout**, which is the UnionAll wrapper of a
kind-parameterized `@document` type (`JsonString{ImmutableCell{String},…}` →
`JsonString`), or the type itself for a hand-written document.

Recording the cell layout makes the token agnostic on both axes. A reference typed
on a reactive node still `isa`-matches its immutable snapshot, which is the kind
axis. A reference built on a native node records the same token as one built on
the node's cell twin, which is the layout axis — so a path built while a hot path
mutates a native tree still names each node by the type that its cell-backed
twin — the shadow — carries, and resolves unchanged against that twin. And the
token stays the bare name the `@reference` macro emits, which the pattern matcher
compares with `<:`.

The family would be the obvious token and is the wrong one: it is a *supertype* of
the cell layout, so `AJsonString <: JsonString` is false and every `::T`
pattern arm would stop matching.

Validation is `document isa path.type`, so a **native** document does not validate
against this token — it is not `isa` its cell layout. A caller validates against
the shadow, the cell-backed twin, instead.

Generic reference-mapping code that constructs a typed reference against a
runtime document (rather than a statically named type) reads the type from
here — e.g. a whole-element selection mapped across a projection carries
`get_reference_node_type(output_document)`.
"""
get_reference_node_type(document) = get_document_cell_type(document)

"""
    annotate_reference_types(document, path::Reference) -> Reference

Return `path` with each node's `type` field **filled in** against `document`: a
`ConcreteReference` records [`get_reference_node_type`](@ref) of the document it
stands on, the cell layout of its schema, and the terminal `EmptyReference`
records it for the node the path lands on.
This is the *folded* canonical form — the type lives on each node, not as a
separate interleaved `TypeReferenceStep` step. The result can be persisted and later
re-checked with [`get_valid_reference_prefix`](@ref) / the document-aware
[`is_valid_reference`](@ref) to detect structural changes. Inverse of
[`strip_reference_types`](@ref).

A zero-width position (`{k}`) is a cursor *between* items — it lands on no child
node. It evaluates to a `Position`, so the terminal after it records `Position`.
"""
function annotate_reference_types(document, ::EmptyReference)
    # Whole-element / terminal node: record the type of the node it lands on.
    EmptyReference(get_reference_node_type(document))
end

function annotate_reference_types(document, path::ConcreteReference)
    step = path.head
    rest = path.tail
    nodetype = get_reference_node_type(document)
    # Descend one step to type the rest. A zero-width cursor descends to a
    # `Position` (so its terminal records `::Position`); a structural step that
    # cannot be followed throws and leaves the rest untyped.
    child = try
        evaluate_reference_step(step, document)
    catch exception
        _is_walk_passthrough(exception) && rethrow()
        nothing
    end
    annotated_rest = child === nothing ? rest : annotate_reference_types(child, rest)
    ConcreteReference(nodetype, step, annotated_rest)
end

"""
    strip_reference_types(path::Reference) -> Reference

Return `path` reduced to its plain navigation skeleton: every node's recorded
`type` is blanked to `nothing`. Inverse of [`annotate_reference_types`](@ref) —
used at boundaries that re-annotate a path against a fresh document.
"""
strip_reference_types(::EmptyReference) = EmptyReference()

strip_reference_types(path::ConcreteReference) =
    ConcreteReference(nothing, path.head, strip_reference_types(path.tail))

# Permissive fallback: callers may apply this to a non-path (e.g. `nothing` when
# there is no selection); pass it through unchanged so the structural reads
# downstream handle the absence themselves.
strip_reference_types(other) = other

"""
    copy_reference(reference) -> reference

A reference that does not change when the one it was made from changes.

Use it to keep a path past the moment you read it. A stored selection is a LIVE
value: as the caret moves, the start and the stop of its last range step are
rewritten in place, so a path that is merely held follows the caret instead of
remembering where it was. A copy reads the numbers now and keeps them.

Anything that is not a reference is answered unchanged, so a caller that may hold
`nothing` needs no guard.

# Example

    before = copy_reference(get_selection(document))

See also `get_selection`, which answers the live path, and
`strip_reference_types`, which rebuilds a path without its type checkpoints.
"""
copy_reference(reference::ConcreteReference) =
    ConcreteReference(reference.type, _copy_reference_step(get_reference_head(reference)),
                      copy_reference(get_reference_tail(reference)))
copy_reference(reference) = reference

# A range step is the one step that is written in place, so it is the one that is
# rebuilt, in its own layout. Every other step is answered as it is.
_copy_reference_step(step::RangeReferenceStep) = RangeReferenceStep(step.start, step.stop)
_copy_reference_step(step::MRangeReferenceStep) =
    MRangeReferenceStep(step.start, step.stop)
_copy_reference_step(step) = step

"""
    fold_reference_types(path::Reference) -> Reference

Convert a flat path that may carry interleaved `TypeReferenceStep` *steps* into the
folded form where the type lives on each node. A `TypeReferenceStep(T)` step sets the
`type` of the node built from the **following** navigation step (or the terminal
node, if it is the last step). Nodes that already carry a folded `type` keep it
(so concatenating an already-folded sub-path is preserved). Used by the
`@reference` builder to fold the `::T` checkpoints it emits as steps.
"""
fold_reference_types(path::Reference) = _fold_reference_types(path, nothing)

_fold_reference_types(p::EmptyReference, pending) =
    EmptyReference(pending === nothing ? p.type : pending)

function _fold_reference_types(p::ConcreteReference, pending)
    if p.head isa ATypeReferenceStep
        # A checkpoint step types the *next* navigation node — carry it forward.
        return _fold_reference_types(p.tail, p.head.type)
    end
    ConcreteReference(pending === nothing ? p.type : pending, p.head,
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
    is_fully_typed_reference(path::Reference) -> Bool

`true` when every node of `path` (each `ConcreteReference` and the terminal
`EmptyReference`) records a non-`nothing` `type`. This is the strict-typing
invariant `@reference` enforces: a path built from a fully-typed `@reference`
literal (or annotated against a document) is fully typed; a path with any bare
navigation node is not.
"""
is_fully_typed_reference(p::ConcreteReference) = p.type !== nothing && is_fully_typed_reference(p.tail)
is_fully_typed_reference(p::EmptyReference)    = p.type !== nothing
is_fully_typed_reference(::Nothing)                = true   # no-selection sentinel: not our concern

# Enforce the strict-typing invariant on a freshly built `@reference` path.
# `src` is the macro-call `LineNumberNode`, so a violation names its file:line.
function _strict_check(path, src)
    is_fully_typed_reference(path) && return path
    error("under-typed @reference (missing node types) at $(src.file):$(src.line)")
end
