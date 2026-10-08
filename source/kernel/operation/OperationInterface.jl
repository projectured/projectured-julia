# Fragment of `OperationModule` — the contract: the abstract types and the open generics.

"""
    Operation

One change of a document, as a value: what is changed, where, and to what.

Use it as the type of anything a person's act means for a document. A reader
answers one of these instead of changing the document itself, so the change can
be inspected, refused, logged, undone, or sent somewhere else before it happens.

# Example

    struct ResizeBoxOperation <: Operation
        box::Any
        delta::Int
    end
    evaluate_operation(editor, o::ResizeBoxOperation) = (o.box.width += o.delta)
    make_inverse_operation(document, o::ResizeBoxOperation) =
        ResizeBoxOperation(o.box, -o.delta)

See also `evaluate_operation`, which applies one, and `read_intent`, which
answers one.
"""
abstract type Operation end

"""
    WrappingOperation

An operation that holds one other operation and does something around it.

Use it as the supertype when a change is another change plus an effect: a record
of the way back, a transaction, a trace. A subtype answers
`get_wrapped_operation` and `rewrap_operation`, and every seam that maps a
`CompoundOperation` member by member then maps the operation inside it too, so
the inner reference reaches the editor in the frame it must be applied in.

# Example

    struct TraceOperation <: WrappingOperation
        operation::Any
    end
    get_wrapped_operation(o::TraceOperation) = o.operation
    rewrap_operation(::TraceOperation, inner) = TraceOperation(inner)

See also `CompoundOperation`, which holds many operations rather than one, and
`reroot_operation`, the seam this supertype serves.
"""
abstract type WrappingOperation <: Operation end

"""
    get_wrapped_operation(operation::WrappingOperation)

The operation that `operation` holds.

See also `WrappingOperation` and `rewrap_operation`.
"""
function get_wrapped_operation end

"""
    rewrap_operation(operation::WrappingOperation, inner)

`operation` with `inner` in place of the operation it holds.

Use it to rebuild a wrapper once its inner operation is mapped or rerooted. It
is the inverse of `get_wrapped_operation`, so declare the two methods together
or declare neither.

See also `WrappingOperation` and `reroot_operation`.
"""
function rewrap_operation end

"""
    ReplacePathOperation

An operation that replaces a kind of path of the documents on it: the selection
(`ReplaceSelectionOperation`), the part under the pointer
(`ReplaceMouseTargetOperation`), or the part whose drag is on
(`StartDragOperation`). `get_operation_path` reads its path, and
`make_path_operation` makes the same kind of operation with another path, so a
container that puts its own steps before the answer of a child, and a projection
that maps the answer backward, handle every kind in one method, and a later kind
needs no code there. Each kind evaluates in its own way.
"""
abstract type ReplacePathOperation <: Operation end

"""
    get_operation_path(operation::ReplacePathOperation) -> Reference

The path that `operation` writes.
"""
function get_operation_path end

"""
    make_path_operation(operation::ReplacePathOperation, path) -> ReplacePathOperation

An operation of the same kind as `operation` that writes `path`.
"""
function make_path_operation end

"""
    is_collecting_operation(operation) -> Bool

Whether `operation` collects: whether the parts around the part that gave it
may add their own answers to it. A gesture that goes out from the part it lands
on reads each enclosing document in turn; after an answer that collects, the next
document reads the gesture too, and an answer of the same kind is joined with
[`join_collected_operations`](@ref). Any other answer ends the search, so the
nearest part that answers wins. A tooltip collects the tooltip of each part
around the one under the pointer, which a person then shows one layer at a time.

The default is `false`. A package answers `true` for an operation type of its own.
"""
function is_collecting_operation end

"""
    join_collected_operations(inner, outer) -> Operation

One operation that holds what the collecting operations `inner` and `outer` hold,
`inner` first: `inner` comes from a part, `outer` from a document around it. A
package declares it for its own collecting operation type, with
[`is_collecting_operation`](@ref).
"""
function join_collected_operations end

"""
    evaluate_operation(editor, operation::Operation)

Carry out a change: the one place where a document is written.

Use it to apply what a reader answered. Every concrete operation adds a method
of its own, which reaches for what it needs on the editor, most often the
document it holds. Nothing else writes a document, so what happened to one is
what was evaluated on it.

# Example

    change = read_intent(projection, iomap, event)
    change === nothing || evaluate_operation(editor, change)

See also `Operation`, `read_intent`, and `invalidate_projection!`.

Apply `operation` against `editor`. The `editor` is whatever object holds the
mutable runtime state the operation needs, with `editor.document` carrying the
root document. Concrete operations add methods reaching for whatever editor
fields they need (`editor.document` is the most common). The caller invokes this
after the reader pipeline produces an operation.
"""
function evaluate_operation end

"""
    invalidate_projection!(editor)

Ask `editor` to drop any cached projection/IoMap so the next print rebuilds from
scratch. An operation that changes the document in a way the reactive pipeline
cannot propagate incrementally (e.g. a whole-root swap) calls this. Answering is
optional — a caller that keeps no cache does nothing — so an `evaluate_operation`
method can call it without knowing the concrete type of the object it is handed.
"""
function invalidate_projection! end

# ── The splice and traversal seams (methods in Operations.jl) ──────────

"""
    splice_value!(owner, field, value, s, e, replacement)

Apply a text-replace edit to `owner.<field>` between 0-based boundaries `[s, e]`.
Dispatch is on the *representation* of the current `value` (read from the field
by the caller), not on the document type — so a single small set of methods
covers every domain:

- `AbstractString` — write the spliced string back through the field.
- `Nothing`        — a cleared text field; splice against the empty string.
- `Number`         — splice the textual form and reparse (editing a number's text
                     means "reparse it"; see [`splice_number`](@ref)).

A domain whose field holds a richer text representation (a styled span, a
sequence of spans) adds its own method for it.
"""
function splice_value! end

# ── The copy seam of a plain value (methods in OperationDefaults.jl) ───────

"""
    with_object_field(object, name::Symbol, value) -> copy

A copy of the plain immutable `object` in which the field `name` holds `value`.
`ReplaceReferencedValueOperation` uses it to write a field of a value that can
not change in place: it writes the copy into the slot one level up, until a slot
that a cell holds takes it.

The default calls the constructor of `typeof(object)` with every field, the one
field replaced, so the copy has the type of `object`. A `NamedTuple` merges.
A type whose constructor does not take all of its fields adds a method.
"""
function with_object_field end

"""
    child_reference_steps(node) -> iterable of (step, child) pairs

Open traversal seam. The default enumerates struct fields as
`FieldReferenceStep` steps, skipping `selection` and any field whose (unwrapped)
value is not a `Document`. Override for container documents whose children
are addressed by index (an element collection), by position, etc.
"""
function child_reference_steps end

# ── The rerooting protocol (methods in Rerooting.jl) ───────────────────

"""
    reroot_operation(op, steps::Tuple) -> op

Prepend `steps` to the reference inside a path-bearing operation. The catch-all
reroots the reference that [`operation_reference`](@ref) reports and rebuilds the
operation with [`retarget_operation`](@ref), so a path-bearing type registers with
that pair and adds no method here. An operation that reports no reference comes
back unchanged.
"""
function reroot_operation end

"""
    operation_reference(op) -> Reference or nothing

The reference that `op` targets, or `nothing` when `op` carries none. Open
generic: a path-bearing operation type defined in a higher package adds a method
for itself, with [`retarget_operation`](@ref). The pair registers the operation:
the catch-all `reroot_operation` reroots the reference, and the default
`read_intent` maps it back through a projection, so a projection stays generic
over operation types the kernel cannot enumerate.
"""
function operation_reference end

"""
    retarget_operation(op, reference) -> op

`op` rebuilt against `reference`, which replaces the reference that
`operation_reference` reports. Open generic, and the inverse of
`operation_reference`: define both methods together or neither.
"""
function retarget_operation end

"""
    is_self_contained_operation(op) -> Bool

Whether `op` should be passed up the chain as it is, rather than dropped, when it
names no reference.

An operation either says WHERE it acts or says WHAT it acts on. One that names a
reference is re-targeted at every level, through `operation_reference` and
`retarget_operation`. One that names its subject — the widget it toggles, the
draft it types into — has nothing to re-target, and the only two useful answers
are to forward it or to drop it. Forwarding is right whenever the subject is the
operation's own and not something a projection could have re-rooted.

The default is `false`, because a projection that answers an operation it does
not understand is worse than one that declines: the kernel drops what it cannot
place. A package whose operations carry their subject says so with one method,
and the kernel names none of them.
"""
function is_self_contained_operation end

# ── The inversion protocol (methods in Inversion.jl) ───────────────────

"""
    make_inverse_operation(document, operation) -> operation or nothing

The operation that takes `document` back to the state it is in now, once
`operation` has been applied to it.

Use it before you apply a change you may have to take back. It reads the
document, so call it while the document still holds what the change is about to
overwrite. `nothing` means this operation has no way back, which is a truthful
answer and not an error: a caller that keeps a history records a point it can
not undo past.

An operation that changes no document — a file that is written, a zoom — answers
`DoNothingOperation()` rather than `nothing`. There is nothing to take back, so
taking it back is doing nothing.

# Example

    inverse = make_inverse_operation(editor.document, operation)
    evaluate_operation(editor, operation)
    inverse === nothing || push!(history, inverse)

See also `evaluate_invertible_operation!`, which does the two in the right
order, and `reroot_operation`, the other open seam every operation may extend.
"""
function make_inverse_operation end

"""
    evaluate_invertible_operation!(editor, operation) -> operation or nothing

Apply `operation` against `editor` and answer the way back.

Use it wherever a change must be remembered as well as made. The default takes
the inverse first and applies second, because an inverse reads the state the
change starts from.

A container operation needs its own method, because the inverse of its second
member depends on what its first member did. `CompoundOperation` has one below.

# Example

    inverse = evaluate_invertible_operation!(editor, operation)

See also `make_inverse_operation`, which answers the way back without applying.
"""
function evaluate_invertible_operation! end

"""
    get_slot_at(container, index)

What the element at `index` of a sequence container is, as a write would put it
back.

Use it to read an element you intend to restore. The default answers the value.
A container whose elements live in cells answers the cell, so a restored element
is the same object it was and whatever followed that cell follows it still.

This layer can not name a cell collection, so it asks through this seam, and a
package that defines a cell collection adds a method for it.

# Example

    old = [get_slot_at(elements, i) for i in 1:3]

See also `make_inverse_operation`, which is what needs it.
"""
function get_slot_at end
