# Fragment of `ReferenceModule` — walking a path **against a document**, and the
# "types always present" invariant that walk maintains.
#
# The three walkers are structurally parallel and all descend through the
# `evaluate_step` / `step_kind` seam declared in `Interface.jl`:
#
# - `evaluate_reference`        — follow the path, return the node it lands on
# - `get_valid_reference_prefix` — follow as far as the document still allows
# - `annotate_reference_types`   — follow, recording each node's type as it goes
#
# The type protocol around them (`reference_node_type`, `strip_reference_types`,
# `fold_reference_types`, `is_fully_typed`) is the same concept from the other
# side: a path is *canonical at rest* when every node records the type of the
# document node it stands on. The path shape these walk lives in
# `ReferencePath.jl`; the steps they descend through in `ReferenceStep.jl`.

# ── Reference evaluation ─────────────────────────────────────────────────

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

"""
    try_evaluate_reference(document, path::ReferencePath, default = nothing) -> node | default

`evaluate_reference` for a path that may not resolve: `default` instead of a throw.

A path is not a guarantee. It can name a node that no longer exists (the document
changed under a stale selection), or one that never existed in `document` at all (a
projection-introduced position, whose head is a `ProjectionReference` with no input
pre-image). A caller that is *asking whether* the path resolves — a gesture
precondition deciding whether it has a target — wants an answer, not an exception.
"""
function try_evaluate_reference(document, path::ReferencePath, default = nothing)
    try
        evaluate_reference(document, path)
    catch
        default
    end
end

# A selection is `nothing` when there is none, and "no selection" resolves to no node —
# so callers asking about a document's current selection need no separate guard.
try_evaluate_reference(document, ::Nothing, default = nothing) = default

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
boundaries that re-annotate a path against a fresh document.
"""
strip_reference_types(::EmptyReferencePath) = EmptyReferencePath()

function strip_reference_types(path::ConcreteReferencePath)
    step = path.head
    rest = strip_reference_types(path.tail)
    step isa TypeReference ? rest : ConcreteReferencePath(nothing, step, rest)
end

# Permissive fallback: callers may apply this to a non-path (e.g. `nothing` when
# there is no selection); pass it through unchanged so the structural reads
# downstream handle the absence themselves.
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
