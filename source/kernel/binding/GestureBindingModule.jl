"""
    GestureBindingModule

Reified **gesture → operation** bindings. A `GestureBinding` is a piece of *data*
that can both **fire** an operation and be **inspected** (how the gesture is
written, what it does, whether it currently applies), so the very same declaration
that handles a key both edits the document and can be listed to a user.

The module has three fragments:

- `GestureBindingInterface.jl` — the contract: [`read_gesture`](@ref),
  [`get_document_gesture_bindings_own`](@ref) and
  [`get_instance_gesture_bindings`](@ref).
- `GestureBinding.jl` — the type, the registry, the firing loop and the defaults
  of the contract.
- `Gestures.jl` — the `@gestures` and `@gesture_set` authoring macros.

The pieces:

- **`GestureBinding`** — an `EventPattern` (what input fires it, and how it is
  described) + `operation(document, event) -> Operation | Nothing` (build the edit)
  + `applicable(document, selection) -> Bool` (an *event-independent* state
  precondition) + a human `description` + a `domain` tag + an optional `name`.
  The pattern is **optional**: a binding with no pattern has no gesture at all,
  and only its name reaches it — see [`fire_named_gesture_binding`](@ref).
- **Registry** keyed by document type, with supertype inheritance:
  `get_document_gesture_bindings(T)` collects `T`'s own bindings plus every
  supertype's, so a declaration on an abstract document type covers its subtypes.
  The own bindings live in `get_document_gesture_bindings_own(::Type{T})`
  *methods* (not a mutable table) so they survive precompilation.
  [`get_instance_gesture_bindings`](@ref) gives the bindings of one instance, which
  come before the table of its type.
- **Firing** — [`fire_gesture_bindings`](@ref) runs the first binding whose pattern
  matches an event, and [`fire_named_gesture_binding`](@ref) runs a binding by its
  name. For the event `CollectIntents`, `fire_gesture_bindings` returns a
  `CollectedIntentsOperation` with one `Intent` for each binding, so a listing reads
  the same table that fires.
- **`@gestures DocumentType begin … end`** — the declarative authoring form. It
  emits the `get_document_gesture_bindings_own` method holding the reified table.
  Firing is then a *single generic interpreter* ([`read_bound_gesture`](@ref), wired
  into [`read_gesture`](@ref)) that walks that very table — so the set that *fires*
  is the set that is *shown*.
"""
module GestureBindingModule

using ..DocumentModule
using ..EventModule
using ..IntentModule
using ..SelectionModule

export GestureBinding,
       get_document_gesture_bindings, get_document_gesture_bindings_own,
       get_instance_gesture_bindings, get_applicable_gesture_bindings,
       fire_gesture_bindings, fire_named_gesture_binding,
       read_gesture, read_bound_gesture,
       var"@gestures", var"@gesture_set"


include("GestureBindingInterface.jl")
include("GestureBinding.jl")
include("Gestures.jl")

end # module
