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
  then a *single generic interpreter* ([`read_bound_gesture`](@ref), wired into
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
       fire_gesture_bindings, read_gesture, read_bound_gesture,
       var"@gestures", var"@gesture_set"

"""
    GestureBinding(pattern, operation, applicable, description, domain, override = false)

One reified gesture → operation rule.

- `pattern::EventPattern` — what input fires it (and how it is described).
- `operation::Function` — `(document, event) -> Operation | Nothing`, builds the edit
  in the document's own reference vocabulary. May return `nothing` for a finer,
  event-dependent guard that the precondition cannot express.
- `applicable::Function` — `(document, selection) -> Bool`, an *event-independent*
  state precondition. This is what greys a row out when the bindings are listed.
- `description::String` — human text for *what the binding does*.
- `domain::String` — a tag (usually the document type name) for grouping.
- `override::Bool` — whether the binding claims its key even when an *output* layer
  has already turned it into an operation. The reader runs last-to-first, so by
  default a printable key the text layer absorbed as a character edit never reaches
  the document's gestures — which is what makes JSON's `,` a literal comma inside a
  string without a guard. A binding whose key can never be text in its own context
  sets this (XML's `<` inside a tag name inserts a child element). See
  [`fire_gesture_bindings`](@ref).
"""
struct GestureBinding
    pattern::EventPattern
    operation::Function
    applicable::Function
    description::String
    domain::String
    override::Bool
end

GestureBinding(pattern, operation, applicable, description, domain) =
    GestureBinding(pattern, operation, applicable, description, domain, false)

# ─────────────────────────────────────────────────────────────────────────
# Registry (own bindings per type) + supertype inheritance
#
# Own bindings are held in `get_document_gesture_bindings_own(::Type{T})` *methods*
# (emitted by `@gestures`), not a mutable table, so they persist across
# precompilation — mutating a Dict at a module's load time would be lost.
# `get_document_gesture_bindings` walks the supertype chain over those methods.
# ─────────────────────────────────────────────────────────────────────────

"""
    get_document_gesture_bindings_own(::Type{T}) -> Vector{GestureBinding}

The bindings declared *directly* on type `T` by `@gestures T …` (default empty). Use
[`get_document_gesture_bindings`](@ref) to also collect inherited supertype bindings.
"""
get_document_gesture_bindings_own(::Type) = GestureBinding[]

"""
    get_document_gesture_bindings(T::Type)  -> Vector{GestureBinding}
    get_document_gesture_bindings(document) -> Vector{GestureBinding}

Every binding that applies to document type `T`: `T`'s own bindings, most specific
first, followed by each supertype's, walking up the chain. The result is the reified
table the [`read_bound_gesture`](@ref) interpreter fires and an inspector shows —
one source of truth.

The walk is recomputed per call rather than memoised: a process-wide cache keyed by
type is exactly the kind of module-level mutable state that ties independent
editors together (AR-NO-PROJECTION-GLOBALS, AR-PER-EDITOR-STATE), and appending a
handful of vectors costs nothing next to the event that provoked it.
"""
function get_document_gesture_bindings(T::Type)
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
values that are not `Document`s — pass such a target's selection to
[`read_bound_gesture`](@ref) explicitly.
"""
get_instance_gesture_bindings(document) = GestureBinding[]

"""
    fire_gesture_bindings(bindings, target, selection, event, claimed = nothing) -> Operation | Nothing

The firing loop: the first binding whose pattern `matches` the event, whose
`applicable` precondition holds for `target` + `selection`, and whose `operation`
returns non-`nothing`, wins. A binding whose operation returns `nothing` is a finer
event-dependent decline and is skipped, so a later binding may still fire.

`claimed` is the operation an *output* layer has already produced for this event, or
`nothing` when the event is unclaimed. A claimed event only fires bindings marked
`override`: the reader runs last-to-first, so anything the output layers understood
they have already done, and a document gesture that is not an explicit override has
nothing to add. This is why a structural gesture needs no guard against firing
mid-text — a key that could be text never arrives unclaimed.

This is the one place a table of bindings becomes an operation. Anything holding
bindings — a document, an instance, a projection — fires them through here rather
than walking them itself, so *what fires* cannot drift from what a listing shows.
"""
function fire_gesture_bindings(bindings, target, selection, event, claimed = nothing)
    for binding in bindings
        claimed === nothing || binding.override || continue
        if matches(binding.pattern, event) && binding.applicable(target, selection)
            operation = binding.operation(target, event)
            operation === nothing || return operation
        end
    end
    return nothing
end

"""
    read_bound_gesture(target, event; claimed = nothing) -> Operation | Nothing
    read_bound_gesture(target, event, selection; claimed = nothing) -> Operation | Nothing

Fire the first matching binding for `target`, checking its per-instance
[`get_instance_gesture_bindings`](@ref) ahead of its per-type
[`get_document_gesture_bindings`](@ref) table (which walks the supertype chain), so
an instance can add to, shadow, or suppress the type's defaults.

`selection` defaults to `target`'s own — pass it explicitly for a target that has
none of its own, such as a node whose identity is its path inside an enclosing tree
(then it is usually the enclosing document's). A target with neither instance nor
type bindings yields `nothing`. `claimed` restricts firing to `override` bindings —
see [`fire_gesture_bindings`](@ref).
"""
function read_bound_gesture(target, event, selection; claimed = nothing)
    bindings = _gesture_bindings(target)
    isempty(bindings) && return nothing
    return fire_gesture_bindings(bindings, target, selection, event, claimed)
end

function read_bound_gesture(target, event; claimed = nothing)
    bindings = _gesture_bindings(target)
    # Read the selection only once a binding could fire: reading a cell to answer
    # "no bindings" would register a dependency on it for nothing.
    isempty(bindings) && return nothing
    return fire_gesture_bindings(bindings, target, getfield(target, :selection)[], event, claimed)
end

# The instance's own bindings ahead of its type's, so an instance shadows a
# same-pattern default.
function _gesture_bindings(target)
    instance = get_instance_gesture_bindings(target)
    type = get_document_gesture_bindings(typeof(target))
    isempty(instance) ? type : (isempty(type) ? instance : vcat(instance, type))
end

"""
    read_gesture(document, gesture; claimed = nothing) -> Union{Operation, Nothing}

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
# table interpreter. Documents with no registered gestures get `nothing`. `claimed`
# (an operation an output layer already produced for this event) restricts firing to
# `override` bindings — see `fire_gesture_bindings`.
read_gesture(document::Document, event; claimed = nothing) =
    read_bound_gesture(document, event; claimed)

"""
    get_applicable_gesture_bindings(document, bindings) -> Vector{GestureBinding}

The subset of `bindings` whose `applicable` precondition holds for `document`'s
current selection — the ones that would fire in the state the document is in.
"""
function get_applicable_gesture_bindings(document, bindings)
    selection = getfield(document, :selection)[]
    GestureBinding[b for b in bindings if b.applicable(document, selection)]
end

include("Gestures.jl")   # the @gestures / @gesture_set authoring DSL

end # module
