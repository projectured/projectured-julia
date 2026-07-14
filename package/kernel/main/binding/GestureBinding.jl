"""
    GestureBindingModule

Reified **gesture → operation** bindings. A `GestureBinding` is a piece of *data*
that can both **fire** an operation and be **inspected** (how the gesture is
written, what it does, whether it currently applies), so the very same declaration
that handles a key both edits the document and can be listed to a user.

The pieces:

- **`GestureBinding`** — an `EventPattern` (what input fires it, and how it is
  described) + `operation(document, event) -> Operation | Nothing` (build the edit)
  + `applicable(document, selection) -> Bool` (an *event-independent* state
  precondition) + a human `description` + a `domain` tag.
- **Registry** keyed by document type, with supertype inheritance:
  `get_document_gesture_bindings(T)` collects `T`'s own bindings plus every
  supertype's, so a declaration on an abstract document type covers its subtypes for
  free. The own bindings live in `get_document_gesture_bindings_own(::Type{T})`
  *methods* (not a mutable table) so they survive precompilation.
- **`@gestures DocumentType begin … end`** — the declarative authoring form
  ([`Gestures.jl`](Gestures.jl), a fragment of this module). It emits the
  `get_document_gesture_bindings_own` method holding the reified table. Firing is
  then a *single generic interpreter* ([`read_document_gesture`](@ref), wired into
  [`read_gesture`](@ref)) that walks that very table — so what *fires* is provably
  the set that is *shown*.
"""
module GestureBindingModule

using ..EventModule
using ..EventPatternModule
using ..DocumentModule

export GestureBinding,
       get_document_gesture_bindings, get_document_gesture_bindings_own,
       get_instance_gesture_bindings, get_applicable_gesture_bindings,
       read_gesture, read_document_gesture, read_node_gesture,
       is_help_gesture,
       var"@gestures", var"@gesture_set"

"""
    GestureBinding(pattern, operation, applicable, description, domain)

One reified gesture → operation rule.

- `pattern::EventPattern` — what input fires it (and how it is described).
- `operation::Function` — `(document, event) -> Operation | Nothing`, builds the edit
  in the document's own reference vocabulary. May return `nothing` for a finer,
  event-dependent guard that the precondition cannot express.
- `applicable::Function` — `(document, selection) -> Bool`, an *event-independent*
  state precondition. This is what greys a row out when the bindings are listed.
- `description::String` — human text for *what the binding does*.
- `domain::String` — a tag (usually the document type name) for grouping.
"""
struct GestureBinding
    pattern::EventPattern
    operation::Function
    applicable::Function
    description::String
    domain::String
end

# ─────────────────────────────────────────────────────────────────────────
# Registry (own bindings per type) + supertype inheritance
#
# Own bindings are held in `get_document_gesture_bindings_own(::Type{T})` *methods*
# (emitted by `@gestures`), not a mutable table, so they persist across
# precompilation — mutating a Dict at a module's load time would be lost.
# `get_document_gesture_bindings` walks the supertype chain over those methods,
# caching the merged result in a runtime Dict (caches repopulate at runtime, so they
# are precompile-safe).
# ─────────────────────────────────────────────────────────────────────────

"""
    get_document_gesture_bindings_own(::Type{T}) -> Vector{GestureBinding}

The bindings declared *directly* on type `T` by `@gestures T …` (default empty). Use
[`get_document_gesture_bindings`](@ref) to also collect inherited supertype bindings.
"""
get_document_gesture_bindings_own(::Type) = GestureBinding[]

const _GESTURE_CACHE = IdDict{Type,Vector{GestureBinding}}()

"""
    get_document_gesture_bindings(T::Type)  -> Vector{GestureBinding}
    get_document_gesture_bindings(document) -> Vector{GestureBinding}

Every binding that applies to document type `T`: `T`'s own bindings, most specific
first, followed by each supertype's, walking up the chain. The result is the reified
table the [`read_document_gesture`](@ref) interpreter fires and an inspector shows —
one source of truth.
"""
function get_document_gesture_bindings(T::Type)
    cached = get(_GESTURE_CACHE, T, nothing)
    cached === nothing || return cached
    result = GestureBinding[]
    S = T
    while true
        # Kind-parameterized document types carry their bindings on the bare stem —
        # the UnionAll the `@gestures` method dispatches on. The supertype walk never
        # visits that stem, so normalize each concrete level to its UnionAll base
        # before the registry lookup.
        base = S isa DataType ? S.name.wrapper : S
        append!(result, get_document_gesture_bindings_own(base))
        S === Any && break
        S = supertype(S)
    end
    _GESTURE_CACHE[T] = result
    return result
end
get_document_gesture_bindings(document::Document) =
    get_document_gesture_bindings(typeof(document))

"""
    get_instance_gesture_bindings(document) -> Vector{GestureBinding}

Per-*instance* gesture bindings carried by `document` itself, checked ahead of the
per-type table so an instance can add, override (by shadowing a same-pattern
default), or suppress behavior. Default empty, so any object that does not opt in
behaves as if it had none. Because the default is empty and untyped it also serves
values that are not `Document`s — see [`read_node_gesture`](@ref).
"""
get_instance_gesture_bindings(document) = GestureBinding[]

# Shared firing loop: the first binding whose pattern `matches` and whose
# `applicable` precondition holds (for `document` + `selection`) and whose
# `operation` returns non-`nothing` wins. A binding whose operation returns `nothing`
# is a finer event-dependent decline and is skipped so a later binding may still fire.
function _fire_gestures(bindings, document, selection, event)
    for b in bindings
        if matches(b.pattern, event) && b.applicable(document, selection)
            operation = b.operation(document, event)
            operation === nothing || return operation
        end
    end
    return nothing
end

"""
    read_document_gesture(document, event) -> Operation | Nothing

Fire the first matching binding for `document`, checking its per-instance
[`get_instance_gesture_bindings`](@ref) first and then its per-type
[`get_document_gesture_bindings`](@ref) table (walking the supertype chain),
evaluated against the current selection. Instance bindings therefore shadow
same-pattern type defaults. This is the single interpreter that backs
[`read_gesture`](@ref) for every `@gestures`-declared type; an object with neither
instance nor type bindings yields `nothing`.
"""
function read_document_gesture(document, event)
    instance = get_instance_gesture_bindings(document)
    type = get_document_gesture_bindings(typeof(document))
    (isempty(instance) && isempty(type)) && return nothing
    selection = getfield(document, :selection)[]
    bindings = isempty(instance) ? type : (isempty(type) ? instance : vcat(instance, type))
    return _fire_gestures(bindings, document, selection, event)
end

"""
    read_node_gesture(node, event, selection) -> Operation | Nothing

The selection-agnostic sibling of [`read_document_gesture`](@ref) for values that are
not `Document`s and so carry no `selection` field of their own — a node whose
identity is its path inside an enclosing tree. Fires `node`'s
[`get_instance_gesture_bindings`](@ref) against the explicitly supplied `selection`
(usually the enclosing document's).
"""
function read_node_gesture(node, event, selection)
    bindings = get_instance_gesture_bindings(node)
    isempty(bindings) && return nothing
    return _fire_gestures(bindings, node, selection, event)
end

"""
    read_gesture(document, gesture) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an `Operation` expressed against `document`
itself (i.e. against `document`'s own reference vocabulary, reading only
`document`'s structure and `document.selection`). Returns `nothing` when the document
does not handle the gesture, so a caller can fall back to its own geometry-dependent
handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any consumer whose
input (or output) is `document` can obtain navigation/editing operations without
re-implementing them, and a backend that renders the domain directly (without a
projection pipeline) gets them for free.

The catch-all `read_gesture(::Document, gesture)` below reads the reified
[`get_document_gesture_bindings`](@ref) table for the document's type — so a domain
authored with [`@gestures`](@ref) needs no hand-written reader. A concrete
`read_gesture(::SomeDocument, …)` method is more specific and still takes precedence;
a document type with neither a method nor any registered gestures yields `nothing`.
"""
function read_gesture end

# The projection-independent reader for any `@gestures`-declared document is the
# table interpreter. Documents with no registered gestures get `nothing`.
read_gesture(document::Document, event) = read_document_gesture(document, event)

"""
    get_applicable_gesture_bindings(document, bindings) -> Vector{GestureBinding}

The subset of `bindings` whose `applicable` precondition holds for `document`'s
current selection — the ones that would fire in the state the document is in.
"""
function get_applicable_gesture_bindings(document, bindings)
    selection = getfield(document, :selection)[]
    GestureBinding[b for b in bindings if b.applicable(document, selection)]
end

"""
    is_help_gesture(event) -> Bool

True when `event` is the gesture that summons the gesture-help window (F1).
"""
is_help_gesture(event) = event isa KeyDown && event.key === :f1

include("Gestures.jl")   # the @gestures / @gesture_set authoring DSL

end # module
