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
    read_move_answer(projection, iomap, answer::CompoundOperation) -> operation or nothing

The answer to a move, which holds a `ReplaceMouseTargetOperation`, as `projection`
reads it: each member alone, through the reader of `projection`, and a member with
no image left out. A reader that passes every other operation on unchanged calls
it for a move, so the part under the pointer still maps back:

    read_intent(p::MyView, iomap, op::CompoundOperation) =
        has_mouse_target(op) ? read_move_answer(p, iomap, op) : op
"""
read_move_answer(projection, iomap, answer::CompoundOperation) =
    join_move_answers((read_intent(projection, iomap, member) for member in answer.operations)...)

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
    # terminal records `Position`. A bare step, such as a point, is the path of one
    # step.
    output_path = reference isa Reference ? reference :
                  ConcreteReference(reference, EmptyReference())
    make_introduced_reference(projection, iomap.input, output_path)
end

"""
    read_intent(projection::Projection, iomap, operation)

Default implementation for projection operation reading. Re-targets any
operation that carries a reference from output space to input space using
`map_reference_backward`: the path of a `ReplacePathOperation` (the selection,
the part under the pointer), the reference of
the text- and number-range replace operations, plus each member
of a `CompoundOperation` recursively (so edits flow back through
structure-preserving generic projections without a bespoke reader), and the one
operation a `WrappingOperation` holds. A compound goes back whole or not at all,
except the answer to a move, which holds a `ReplaceMouseTargetOperation`: each of
its members goes back alone, and a member with no image is left out. A
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
    if operation isa Union{KeyPress, KeyDown, Gesture, CollectIntents}
        # Generic event fallback: a leaf projection with no authoring reader of
        # its own delegates a key and every gesture to the projection-independent
        # `read_gesture` of its input document, so a document's own table gives
        # the meaning of a click, a chord or a dwell on it. `CollectIntents` rides
        # the same route, so every leaf contributes its document's whole table to
        # a collection without a line of its own. So any `@gestures`-declared
        # domain is reachable through any projection with no bespoke reader.
        # (Higher-order projections route events through their own 4-arg readers
        # and never reach this leaf default.)
        input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
        return input isa Document ? read_gesture(input, operation) : nothing
    elseif operation isa ReplaceReferencedValueOperation
        # Self-contained (carries its own root): forward unchanged — this is the
        # path identity-rooted controls (widgets, rendered controls) take
        # back through any generic projection. Document-rooted (`document === nothing`):
        # re-target the reference, like the dedicated path-bearing ops below.
        operation.document === nothing || return operation
        input_ref = map_reference_backward(projection, iomap, operation.reference)
        (input_ref === nothing || has_introduced_step(input_ref)) && return nothing
        return ReplaceReferencedValueOperation(nothing, input_ref, operation.value)
    elseif operation isa ReplacePathOperation
        # The selection, the part under the pointer, and any later kind of path.
        input_path = map_reference_backward(projection, iomap, get_operation_path(operation))
        input_path === nothing && return nothing
        return make_path_operation(operation, input_path)
    # The text-/number-range replace operations live in a higher package, so the
    # kernel cannot name them. They reach the `operation_reference` /
    # `retarget_operation` seam in the `else` branch below.
    elseif operation isa CompoundOperation
        mapped = Any[read_intent(projection, iomap, o) for o in operation.operations]
        # A move answers every part that it reached, the part under the pointer
        # with them: each goes back alone, and a part with no image here is left
        # out. Any other compound goes back whole or not at all.
        has_mouse_target(operation) && return join_move_answers(mapped...)
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
        # A write to a part that a projection printed has no input pre-image.
        (input_reference === nothing || has_introduced_step(input_reference)) && return nothing
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

A change with a route goes on to the child that the route names, when `iomap`
holds children ([`get_child_iomaps`](@ref)), through
[`read_routed_child`](@ref). A container is then not asked where the change goes,
so it needs no code of its own for a route. Where `iomap` holds no children, a
gesture is read as every gesture is, with the rest of the route as the part. The
3-arg reader follows no route, so an operation whose route names a place below
the input answers no operation.
"""
function read_intent(p::Projection, recursion, change::Intent, iomap)
    change.route === nothing || get_child_iomaps(iomap) === nothing ||
        return read_routed_child(recursion, change, iomap)
    change.route isa ConcreteReference && change.operation !== nothing &&
        return Intent(change.gesture, nothing)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = read_intent(p, iomap, payload)
    return Intent(change.gesture, op, change.description, change.domain)
end

# @positional: the arity of the reader of the projection protocol, which it calls.
"""
    read_routed_intent(projection, recursion, change, iomap) -> Intent

What a reader gets back from a child that `change` goes to, where `change` is
what [`follow_intent_route`](@ref) gave for that child. When no route remains,
the child's input is the place of the change. For an operation, the child is not
read, and the answer is the operation that `change` carries, with no route. For a
gesture, the child is the part that the gesture is for, and it reads the gesture.
Otherwise the child reads `change` with `read_intent`.

Use it to pass a change with a route to one child from a 4-arg reader: it reads
the child, or it answers the operation when the child is its place.

# Example

    routed = follow_intent_route(change, FieldReferenceStep("content"))
    routed === nothing && return Intent(change.gesture, nothing)
    answer = read_routed_intent(child.projection, recursion, routed, child)

See also `follow_intent_route`, which gives the route that remains for the child,
and `read_intent`, which it calls.
"""
function read_routed_intent(projection, recursion, change::Intent, iomap)
    change.route isa EmptyReference || return read_intent(projection, recursion, change, iomap)
    change.operation === nothing && change.gesture !== nothing &&
        return read_intent(projection, recursion, change, iomap)
    Intent(change.gesture, change.operation, change.description, change.domain)
end

get_child_iomaps(iomap) = nothing
get_child_iomaps(iomap::ContentIoMap) = Any[iomap.inner_iomap]
get_child_iomaps(iomap::ChildrenIoMap) = _find_entry_iomaps(iomap.child_iomaps)

# The IoMaps among the entries of a container: an entry is an IoMap, a tuple whose
# last member is one (a place and the IoMap of what is there), or empty.
function _find_entry_iomaps(entries)
    found = Any[]
    for entry in entries
        entry isa Tuple && !isempty(entry) && (entry = last(entry))
        entry isa IoMap && push!(found, entry)
    end
    found
end

"""
    read_routed_child(recursion, change, iomap) -> Intent

The answer of the child that the route of `change` reaches, for a container whose
IoMap holds its children ([`get_child_iomaps`](@ref)). The route is read from the
input of `iomap` one step at a time, until the node it reaches is the input of a
child. That child gets `change` with the rest of the route
([`read_routed_intent`](@ref)), and its answer comes back rerooted by the steps
taken, as the answer to a gesture does. A container can hold a child through a
node that has no IoMap of its own, as a split pane holds each pane in a
`LayoutConstraint`, so the walk goes on until it reaches a child; a child whose
input is the input of the container gets the whole route.

**A gesture goes out from its part.** When the route reaches no child, the deepest
node it reached is the part, and it may be the container itself. Then, and after
a child answers, the documents that the walk passed read the gesture with their
own tables (`read_gesture`), the deepest first, up to the input of the container.
The input of a child that answered nothing reads too, because the reader of a
projection need not ask that table. The answer decides how far this goes: a
document reads when nothing deeper answered, and the nearest that answers wins;
after an answer that collects ([`is_collecting_operation`](@ref)), it reads too,
and an answer of the same kind is joined ([`join_collected_operations`](@ref));
any other answer ends it. The tables of the documents are asked, not the readers of
the projections: a projection changes an answer on its way up. A change that
already carries an operation goes to its place and is not read.
"""
function read_routed_child(recursion, change::Intent, iomap)
    children = something(get_child_iomaps(iomap), Any[])
    node, route = get_iomap_input(iomap), change.route
    taken = ReferenceStep[]
    nodes = Any[node]
    while true
        for child in children
            get_iomap_input(child) === node || continue
            steps = Tuple(taken)
            inner = read_routed_intent(get_iomap_projection(child), recursion,
                                       follow_intent_route(change, steps...), child)
            answer = reroot_operation(inner.operation, steps)
            return Intent(change.gesture,
                          _read_outward(change, answer, nodes, taken, !(answer isa Operation)))
        end
        route isa ConcreteReference || break
        step = get_reference_head(route)
        node = try
            evaluate_reference_step(step, node)
        catch
            break
        end
        push!(taken, step)
        push!(nodes, node)
        route = get_reference_tail(route)
    end
    Intent(change.gesture, _read_outward(change, nothing, nodes, taken, true))
end

"""
    read_gesture_outward(answer, gesture, document; steps, with_part = false) -> operation or answer

The answer to a pointer `gesture` that a container gave by position to the child
at its point, read outward over the container's own stretch. `document` is the
input of the container, `steps` lead from it to the input of the child, and
`answer` is the child's answer in the frame of the container. The documents on
the steps above the child's input read the gesture with their own tables
(`read_gesture`), the deepest first, up to `document`, by the rule of
[`read_routed_child`](@ref): a document reads when nothing deeper answered, and
after an answer that collects; an answer of the same kind is joined, and any
other answer ends the walk. The child's input does not read here: the hand-off to
the child (`read_child_event`) reads the documents inside the child when the
child answers nothing. With `with_part`, the document at the end of `steps` reads
too, as the part itself.

Use it in a container that gives a pointer gesture to a child at its point, as a
click and a dwell, after it put the child's answer in its own frame.
"""
function read_gesture_outward(answer, gesture, document; steps, with_part::Bool = false)
    nodes = Any[document]
    taken = ReferenceStep[]
    node = document
    for step in steps
        node = try
            evaluate_reference_step(step, node)
        catch
            break
        end
        push!(taken, step)
        push!(nodes, node)
    end
    _read_outward(Intent(gesture), answer, nodes, taken, with_part)
end

# The documents of a walk read the gesture of `change`, from the deepest out to
# the input of the container: `nodes[i]` is reached by `taken[1:i-1]`. The last
# node reads only `with_last`: when no child took the route, or when the child
# that took it answered nothing, because the reader of a projection need not ask
# the table of its input. An answer that is no operation, such as the gesture
# that a reader hands back when it declines, counts as none, and comes back when
# no document answers.
function _read_outward(change::Intent, answer, nodes, taken, with_last::Bool)
    change.operation === nothing && change.gesture !== nothing || return answer
    found = answer isa Operation ? answer : nothing
    for index in (with_last ? length(nodes) : length(nodes) - 1):-1:1
        found === nothing || is_collecting_operation(found) || return found
        document = nodes[index]
        document isa Document || continue
        own = reroot_operation(read_gesture(document, change.gesture), Tuple(taken[1:(index - 1)]))
        own isa Operation || continue
        found = found === nothing ? own :
                is_collecting_operation(own) ? join_collected_operations(found, own) : found
    end
    found === nothing ? answer : found
end
