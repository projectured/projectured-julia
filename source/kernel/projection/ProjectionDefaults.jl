# Fragment of `ProjectionModule` — the fallback method of each generic the
# contract declares. They work for a projection whose output structure mirrors
# its input: forward mapping strips the projection wrapper from a reference,
# backward mapping adds it, and the default reader retargets an operation
# through the backward mapper. A projection overrides only what it must change.

function print_document(projection, input)
    print_document(projection, nothing, input, PrinterContext())
end

# Recursing into a child means re-entering the whole pipeline, so `recursion` is
# passed twice — as the projection to invoke and as that call's own `recursion`.
# The doubling lives here, in the one helper every node printer recurses through,
# and nowhere else.
print_child(recursion, input, ctx) =
    print_document(recursion, recursion, input, ctx)

print_child_pure(recursion, input, ctx) =
    print_document_pure(recursion, recursion, input, ctx)

"""
    print_pure(projection, input) -> immutable output tree

Entry point for the pure batch printer (see
[`print_document_pure`](@ref)): project `input` to a fully-built, immutable
output tree with no iomap / reactive / selection machinery.
"""
print_pure(projection, input) =
    print_document_pure(projection, nothing, input, PrinterContext())

# Snapshot the forced output of a projection to the immutable kind, when it is a
# document; non-document outputs (a String, a graphics value) pass through.
_pure_snapshot(x) = x isa Document ? copy_document(ImmutableCell, x) : x

# Total fallback for any projection without a specialized pure interpreter: run
# the reactive printer once and snapshot its output. Slower than a real pure
# interpreter (it builds the reactive machinery first), but it makes the pure
# pipeline total — a chain can mix stages that have a pure interpreter with stages
# that use this fallback.
print_document_pure(p::Projection, recursion, input, ctx) =
    _pure_snapshot(unwrap_cell(print_document(p, recursion, input, ctx).output))

"""
    map_reference_forward(projection::Projection, iomap, reference)

Default implementation for forward reference mapping. Strips the projection
wrapper from a reference, returning the inner reference path. This works
for simple projections where output elements directly correspond to input elements.
"""
function map_reference_forward(projection::Projection, iomap, reference)
    r = @reference_case reference begin
        # Whole-element selection maps by identity, but the *output* whole
        # element has the output document's type, not the input's — so the
        # empty path is retyped against `iomap.output`. A caller with no iomap
        # yet (the deferred-iomap trick some selection cells use, e.g.
        # `map_reference_forward(p, nothing, sel)`) can't supply that type here,
        # so the empty path stays untyped — a whole-element selection is stripped
        # to its skeleton before use anyway.
        ∅ => iomap === nothing ? EmptyReference() :
             EmptyReference(get_reference_node_type(iomap.output))
        proj(^(projection), inner) => inner
    end
    # Self-type the result (the unwrapped `proj` inner may be a bare path) against
    # the output document, so the strict-typing invariant holds at the source. With
    # no iomap the output document is unknown, so the result is left as mapped.
    (r === nothing || iomap === nothing || is_fully_typed_reference(r)) ? r :
        annotate_reference_types(iomap.output, r)
end

"""
    map_reference_backward(projection::Projection, iomap, reference)

Default implementation for backward reference mapping. Wraps a reference
with the projection to create a reference that points to the output of
the projection. This works for simple projections where input elements
directly correspond to output elements.
"""
function map_reference_backward(projection::Projection, iomap, reference)
    # A whole-element output selection maps back to a whole-element input
    # selection, typed against the input document (untyped when no iomap is
    # available yet — the deferred-iomap trick, mirroring the forward mapper).
    reference isa EmptyReference &&
        return iomap === nothing ? EmptyReference() :
               EmptyReference(get_reference_node_type(iomap.input))
    # Without the input document there is no pre-image to wrap against, so the
    # reference is returned unchanged.
    iomap === nothing && return reference
    # The projection-introduced element has no input pre-image, so the answer is the
    # canonical caret on it: its node carries the type of the input document, and its
    # terminal records `Position`.
    make_introduced_reference(projection, iomap.input, reference)
end

"""
    read_intent(projection::Projection, iomap, operation)

Default implementation for projection operation reading. Re-targets any
operation that carries a reference from output space to input space using
`map_reference_backward`: the path/reference of `ReplaceSelectionOperation` and
the text- and number-range replace operations, plus each member
of a `CompoundOperation` recursively (so edits flow back through
structure-preserving generic projections without a bespoke reader), and the one
operation a `WrappingOperation` holds. A
`document === nothing` (`editor.document`-rooted)
`ReplaceReferencedValueOperation` has its `reference` re-targeted — this covers
document-replace and sequence-insert/delete, which are
`ReplaceReferencedValueOperation`s with a terminal `RangeReferenceStep`; a self-contained one
(carrying its own root) is forwarded unchanged.

An operation type the kernel cannot name re-targets through the open
`operation_reference` / `retarget_operation` seam — this is how the
`Replace*RangeOperation`s of the package above travel back. An operation that
reports no reference is forwarded unchanged when `operation_travels_unchanged`
answers `true` for it, as for `DoNothingOperation` and `ToggleCollapseOperation`,
and returns `nothing` otherwise.
"""
function read_intent(projection::Projection, iomap, operation)
    # INVARIANT: the set of reference-carrying operation types handled here must
    # stay in sync with `reroot_operation` (OperationModule, operation/Rerooting.jl).
    # A new path-bearing operation missing from either is silently passed through
    # with its reference left in the wrong domain. See
    # documentation/package/kernel/operation.md.
    if operation isa Union{KeyPress, KeyDown, MousePress, CollectIntents}
        # Generic event fallback: a leaf projection with no authoring reader of
        # its own delegates a raw input gesture to the projection-independent
        # `read_gesture` of its input document. `CollectIntents` rides the same
        # route, so every leaf contributes its document's whole table to a
        # collection without a line of its own. This generalizes the per-projection
        # delegation that render-stage projections already do by hand, so any
        # `@gestures`-declared domain is reachable through any projection with no
        # bespoke reader. (Higher-order projections route events through their own
        # 4-arg readers and never reach this leaf default.)
        input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
        return input isa Document ? read_gesture(input, operation) : nothing
    elseif operation isa ReplaceReferencedValueOperation
        # Self-contained (carries its own root): forward unchanged — this is the
        # path identity-rooted controls (widgets, rendered controls) take
        # back through any generic projection. Document-rooted (`document === nothing`):
        # re-target the reference, like the dedicated path-bearing ops below.
        operation.document === nothing || return operation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        input_ref === nothing && return nothing
        return ReplaceReferencedValueOperation(nothing, input_ref, operation.value)
    elseif operation isa ReplaceSelectionOperation
        input_selection = map_reference_backward(projection, iomap, operation.path)
        input_selection === nothing && return nothing
        return ReplaceSelectionOperation(input_selection)
    # The text-/number-range replace operations live in a higher package, so the
    # kernel cannot name them. They reach the `operation_reference` /
    # `retarget_operation` seam in the `else` branch below.
    elseif operation isa CompoundOperation
        mapped = Any[read_intent(projection, iomap, o) for o in operation.operations]
        any(isnothing, mapped) && return nothing
        return CompoundOperation(mapped)
    elseif operation isa WrappingOperation
        # A wrapper holds one operation, so it maps like a compound of one. A
        # wrapper whose inner operation does not map has nothing left to carry.
        inner = read_intent(projection, iomap, get_wrapped_operation(operation))
        inner === nothing && return nothing
        return rewrap_operation(operation, inner)
    elseif operation isa CollectedIntentsOperation
        # A collection maps like a compound: every carried operation into this
        # projection's input domain. Unlike a compound it never fails as a whole —
        # an intent whose operation does not map keeps its row with no operation,
        # because a row that cannot be run is still worth showing.
        return CollectedIntentsOperation([
            Intent(i.gesture,
                   i.operation === nothing ? nothing : read_intent(projection, iomap, i.operation),
                   i.description, i.domain)
            for i in operation.intents])
    else
        # An operation type the kernel does not name: ask the open seam for the
        # reference it targets. An operation that reports one is re-targeted like
        # the branches above; every other operation returns `nothing`. This keeps
        # the default open over new operation types without a
        # `read_intent(::Projection, iomap, ::TheOperation)` method, which would
        # collide with the catch-all reader of every concrete projection.
        reference = operation_reference(operation)
        # An operation that names no reference either carries its own subject —
        # and travels — or is one this level cannot place, and is dropped.
        # `DoNothingOperation`, `ToggleCollapseOperation` and the other kernel
        # operations that name no place in a document are of the first kind.
        reference === nothing &&
            return operation_travels_unchanged(operation) ? operation : nothing
        input_reference = map_reference_backward(projection, iomap, reference)
        input_reference === nothing && return nothing
        return retarget_operation(operation, input_reference)
    end
end

"""
    read_intent(p::Projection, recursion, change::Intent, iomap)

Generic bridge from the symmetric 4-arg `Intent` interface to the 3-arg
reader. For any projection without its own 4-arg method, unwrap the `Intent` and
dispatch `read_intent(p, iomap, payload)` on the operation (when one
has already been produced) or otherwise the gesture (the gesture→operation stage),
then re-wrap the result as a `Intent` with the gesture, the description and the
domain preserved. Compound
projections that must thread the change to their children override this with a
4-arg method of their own.

The 3-arg reader follows no route, so a change whose route names a place below
the input answers no operation.
"""
function read_intent(p::Projection, recursion, change::Intent, iomap)
    change.route isa ConcreteReference && return Intent(change.gesture, nothing)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = read_intent(p, iomap, payload)
    return Intent(change.gesture, op, change.description, change.domain)
end

# @positional: the arity of the reader of the projection protocol, which it calls.
"""
    read_routed_intent(projection, recursion, change, iomap) -> Intent

What a reader gets back from a child that `change` goes to, where `change` is
what [`follow_intent_route`](@ref) gave for that child. When no route remains,
the child's input is the place of the operation: the child is not read, and the
answer is the operation that `change` carries, with no route. Otherwise the
child reads `change` with `read_intent`.

Use it to pass an operation with a route to one child from a 4-arg reader: it
reads the child, or it answers the operation when the child is its place.

# Example

    routed = follow_intent_route(change, FieldReferenceStep("content"))
    routed === nothing && return Intent(change.gesture, nothing)
    answer = read_routed_intent(child.projection, recursion, routed, child)

See also `follow_intent_route`, which gives the route that remains for the child,
and `read_intent`, which it calls.
"""
function read_routed_intent(projection, recursion, change::Intent, iomap)
    change.route isa EmptyReference || return read_intent(projection, recursion, change, iomap)
    Intent(change.gesture, change.operation, change.description, change.domain)
end
