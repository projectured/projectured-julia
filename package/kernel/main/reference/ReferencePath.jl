# Fragment of `ReferenceModule` — the **path structure and its algebra**: the two
# concrete `ReferencePath` types (`EmptyReferencePath`, `ConcreteReferencePath`),
# their constructors/accessors/iteration, the `show` and equality/prefix
# predicates, and the pure path-building operations (`append_reference`,
# `concat_references`, `reference_steps`).
#
# Everything here is document-free: it is the shape of a path and the operations
# on that shape. Walking a path *against a document* (`evaluate_reference`,
# `get_valid_reference_prefix`, `annotate_reference_types`) lives in
# `ReferenceEvaluation.jl`; the steps threaded onto these nodes live in
# `ReferenceStep.jl`.

# ── ReferencePath (immutable linked list) ────────────────────────────────

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
@cell_struct struct EmptyReferencePath <: ReferencePath
    type::Any = nothing
end

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
@cell_struct struct ConcreteReferencePath <: ReferencePath
    type::Any
    head::ReferenceStep
    tail::ReferencePath
end

# Two-arg construction: type unknown (`nothing`). Fully
# untyped so it also catches the pre-wrapped `ConcreteReferencePath(Cell(h), Cell(t))`
# call sites; the `@cell_struct` inner constructor Cell-wraps each field as needed.
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
