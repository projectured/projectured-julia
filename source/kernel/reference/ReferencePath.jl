# Fragment of `ReferenceModule` — the **path structure and its algebra**: the two
# concrete `Reference` types (`EmptyReference`, `ConcreteReference`),
# their constructors/accessors/iteration, the `show` and equality/prefix
# predicates, and the pure path-building operations (`extend_reference`,
# `concat_references`, `get_reference_steps`).
#
# Everything here is document-free: it is the shape of a path and the operations
# on that shape. Walking a path *against a document* (`evaluate_reference`,
# `get_valid_reference_prefix`, `annotate_reference_types`) lives in
# `ReferenceEvaluation.jl`; the steps threaded onto these nodes live in
# `ReferenceStep.jl`.

# ── Reference (immutable linked list) ────────────────────────────────

"""
    EmptyReference([type])

The empty reference path — a path that terminates *at* a node. `type` records the
Julia type of the node the path lands on (the **terminal** node's type); it is
`nothing` for a plain/unknown path or for a cursor terminal (a `{k}` position
between items lands on no child node). A whole-element (`∅`) selection of a typed
node carries that node's type here.

The type is a field of the terminal node, not a separate trailing
`TypeReferenceStep` checkpoint step.
"""
@cell_struct struct EmptyReference <: Reference
    type::Any = nothing
end

"""
    ConcreteReference([type], head, tail)

A non-empty path node. `head` is **always a navigation step** (never a
`TypeReferenceStep`); `tail` is the remaining `Reference`. `type` records the
Julia type of the node you are standing on *at this node* — i.e. the type the
`head` step descends *from*. It is `nothing` when the type is unknown (a plain
`@reference` skeleton, or a generic two-arg construction); `annotate_reference_types`
fills it in against a document.

The node type is stored *on the node* rather than in a separate interleaved
`TypeReferenceStep` checkpoint step before `head`. A step's *end* type is its `tail`
node's `type`, so a `FieldReferenceStep` needs no second checkpoint — the boundary
type is stored once, on the downstream node, and serves both as this step's
result and the next step's source.

# Example

    path = ConcreteReference(FieldReferenceStep("address"),
               ConcreteReference(FieldReferenceStep("city"),
                   EmptyReference()))
"""
@cell_struct struct ConcreteReference <: Reference
    type::Any
    head::ReferenceStep
    tail::Reference
end

# Two-arg construction: type unknown (`nothing`). Fully
# untyped so it also catches the pre-wrapped `ConcreteReference(Cell(h), Cell(t))`
# call sites; the `@cell_struct` inner constructor Cell-wraps each field as needed.
ConcreteReference(head, tail) = ConcreteReference(nothing, head, tail)

# Whole-element ("tree") selection is not a distinct reference step: it is just
# a path that terminates *at* the element, i.e. an `EmptyReference`. The one
# node holding `∅` in its `selection` cell is the wholly-selected one; its
# ancestors hold a non-empty path routing down to it, and its descendants hold
# `nothing`. `evaluate_reference(document, EmptyReference())` already returns
# the element itself, so no marker step is needed.

# ── Convenience constructors ─────────────────────────────────────────────

ConcreteReference(head::ReferenceStep) = ConcreteReference(nothing, head, EmptyReference())

"""
    Reference(steps::ReferenceStep...)

Build a `Reference` from a sequence of reference steps (left = outermost).
"""
function Reference(steps::ReferenceStep...)
    path = EmptyReference()
    for i in length(steps):-1:1
        path = ConcreteReference(steps[i], path)
    end
    path
end

# ── Accessors ────────────────────────────────────────────────────────────

Base.isempty(::EmptyReference) = true
Base.isempty(::ConcreteReference) = false

get_reference_head(p::ConcreteReference) = p.head
get_reference_tail(p::ConcreteReference) = p.tail

Base.length(::EmptyReference) = 0
Base.length(p::ConcreteReference) = 1 + length(get_reference_tail(p))

# ── Iteration ────────────────────────────────────────────────────────────

Base.iterate(::EmptyReference) = nothing
Base.iterate(p::ConcreteReference) = (get_reference_head(p), get_reference_tail(p))
Base.iterate(::EmptyReference, ::Reference) = nothing
Base.iterate(::ConcreteReference, rest::Reference) = iterate(rest)

Base.eltype(::Type{<:Reference}) = ReferenceStep

# ── Display ──────────────────────────────────────────────────────────────

# Short name of a recorded node type, e.g. `Foo` rather than the fully-qualified
# `SomeModule.Foo`; falls back to `string` for non-types.
_show_node_type(io::IO, t) = print(io, "::", t isa Type ? nameof(t) : t)

function Base.show(io::IO, e::EmptyReference)
    e.type === nothing ? print(io, "∅") : _show_node_type(io, e.type)
end

function Base.show(io::IO, p::ConcreteReference)
    p.type === nothing || _show_node_type(io, p.type)
    show(io, get_reference_head(p))
    t = get_reference_tail(p)
    if t isa EmptyReference
        t.type === nothing || _show_node_type(io, t.type)
    else
        show(io, t)
    end
end

# ── Equality ─────────────────────────────────────────────────────────────
# Strict: the folded node `type` fields are significant (see `is_reference_equal`),
# so shape-only callers strip both sides first.
Base.:(==)(a::EmptyReference,   b::EmptyReference)   = a.type === b.type
Base.:(==)(::EmptyReference,   ::ConcreteReference) = false
Base.:(==)(::ConcreteReference, ::EmptyReference)  = false
Base.:(==)(a::ConcreteReference, b::ConcreteReference) =
    a.type === b.type && get_reference_head(a) == get_reference_head(b) && get_reference_tail(a) == get_reference_tail(b)

# A reference compares by value, so it hashes by value — which is what lets one
# key a table. A record of what a build resolved, and a rule that names its
# sources, both want that; without it every lookup of a rebuilt reference misses,
# because a `@cell_struct` hashes by identity unless it says otherwise.
#
# It mixes exactly what `==` reads, the node `type` included, so the strictness
# of the two agrees.
Base.hash(r::EmptyReference, h::UInt) = hash(r.type, hash(:EmptyReference, h))
Base.hash(r::ConcreteReference, h::UInt) =
    hash(get_reference_tail(r), hash(get_reference_head(r), hash(r.type, hash(:ConcreteReference, h))))

"""
    is_reference_equal(a, b)

Structural equality of two reference paths. **Strict**: node type fields are
significant, so an annotated path is not equal to its stripped form.
"""
is_reference_equal(a::Reference, b::Reference) = a == b

"""
    is_reference_prefix(a, b)

Return `true` if reference path `a` is a proper prefix of `b` (i.e. `a` is
strictly shorter and matches the leading steps of `b`).
"""
is_reference_prefix(::EmptyReference, ::EmptyReference) = false
is_reference_prefix(::EmptyReference, ::ConcreteReference) = true
is_reference_prefix(::ConcreteReference, ::EmptyReference) = false
is_reference_prefix(a::ConcreteReference, b::ConcreteReference) =
    a.type === b.type && get_reference_head(a) == get_reference_head(b) && is_reference_prefix(get_reference_tail(a), get_reference_tail(b))

# ── Path construction helpers ────────────────────────────────────────────

"""
    extend_reference(base::Reference, steps::ReferenceStep...) -> Reference

Return a new `Reference` formed by appending `steps` to the end of
`base`. The first step in `steps` becomes the direct successor of the last
step already in `base`.

Folded node types are preserved: every node of `base` keeps its recorded `type`,
and `base`'s terminal type — the type of the node the first appended step descends
*from* — is carried onto that first new node. Later appended nodes are untyped
(`nothing`), since the types they would stand on are not yet known. For an untyped
`base` this is a plain skeleton, exactly as before.
"""
function extend_reference(base::EmptyReference, steps...)
    isempty(steps) && return base
    # `base.type` is the type of the node the first appended step descends from.
    ConcreteReference(base.type, steps[1], extend_reference(EmptyReference(), steps[2:end]...))
end

function extend_reference(base::ConcreteReference, steps...)
    ConcreteReference(base.type, base.head, extend_reference(get_reference_tail(base), steps...))
end

"""
    concat_references(a::Reference, b::Reference) -> Reference

Concatenate two reference paths, **preserving folded node types** on both. Every
node of `a` and of `b` keeps its own recorded `type`. The single junction boundary
— where `a`'s terminal meets `b`'s first node — takes `b`'s type, or, when `b`'s
first node has none, `a`'s terminal type, so an annotated prefix is not silently
de-annotated. It never invents a type. For untyped inputs the result is a plain
skeleton, identical to a naive rebuild.

This is the one canonical path-concatenation (vs `extend_reference`, which appends
raw *steps*); readers/builders that splice whole paths route through it.
"""
concat_references(a::ConcreteReference, b::Reference) =
    ConcreteReference(a.type, a.head, concat_references(get_reference_tail(a), b))
concat_references(a::EmptyReference, b::ConcreteReference) =
    b.type === nothing ? ConcreteReference(a.type, b.head, get_reference_tail(b)) : b
concat_references(a::EmptyReference, b::EmptyReference) =
    EmptyReference(b.type === nothing ? a.type : b.type)

"""
    get_reference_steps(path::Reference) -> Vector{ReferenceStep}

Unroll `path` into its ordered vector of navigation steps (heads), dropping the
terminal type/`EmptyReference`. The inverse is `Reference(steps...)`, which
rebuilds a plain (untyped) skeleton — so this pair is the shared "path ↔ steps
vector" conversion used by callers that need to inspect or rewrite a path's tail
(e.g. splitting off the terminal step). Type checkpoints are read as steps; strip
first (`strip_reference_types`) when a pure navigation skeleton is wanted.
"""
function get_reference_steps(path::Reference)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReference
        push!(steps, cur.head)
        cur = cur.tail
    end
    steps
end
