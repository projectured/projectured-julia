"""
`ProjectionModule` — the fallback method of each generic, for a projection with
no method of its own.

Confirms that:
- the default backward map of a place that the projection printed answers the
  canonical introduced caret: the caret that `make_introduced_reference` builds,
  whose terminal records `Position`;
- the default 4-argument reader and the reader of a template keep the
  description and the domain of the change, and answer no operation for a change
  whose route names a place below the input;
- the default forward and backward maps answer the whole element, a printed
  place, and a reference that has no image;
- the default 3-argument reader gives a gesture to the gesture table of its
  input, and maps each operation that names a place, each member of a compound,
  the operation that a wrapper holds and each row of a collection;
- the bridge reads the gesture of a change with no operation, and
  `read_routed_intent` does not read a child that is the place;
- `read_projection_gesture` fires the first rule that makes an operation.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.EventModule: KeyDown, ModifierKeys
using ProjecturedKernel.GestureModule: KeyDownPattern
using ProjecturedKernel.GestureBindingModule: GestureBinding, @gestures
using ProjecturedKernel.IntentModule: Intent, CollectIntents, CollectedIntentsOperation
using ProjecturedKernel.IoMapModule: SimpleIoMap
using ProjecturedKernel.OperationModule: Operation, DoNothingOperation,
    ReplaceSelectionOperation, ReplaceReferencedValueOperation, CompoundOperation,
    ReplaceViewStateOperation, ToggleCollapseOperation
using ProjecturedKernel.ProjectionModule: Projection, make_introduced_reference,
    map_reference_forward, map_reference_backward, read_intent, read_template_intent,
    read_routed_intent, get_projection_gesture_bindings, read_projection_gesture
using ProjecturedKernel.ReferenceModule: Reference, EmptyReference, FieldReferenceStep,
    RangeReferenceStep, Position, get_reference_steps, strip_reference_types,
    get_reference_node_type, is_fully_typed_reference

# A test-local projection with no method of its own: it answers what the defaults
# of the kernel answer.
struct DefaultsProbeProjection <: Projection end

@document struct DefaultsProbeLeaf
    text::String
end

# A test-local projection whose backward map puts `.inner` in front of a
# reference, and answers no pre-image for a reference that starts at `.blocked`.
# The default reader maps each operation through it.
struct DefaultsPrefixProjection <: Projection end
function ProjecturedKernel.ProjectionModule.map_reference_backward(
        ::DefaultsPrefixProjection, iomap, reference::Reference)
    steps = get_reference_steps(strip_reference_types(reference))
    !isempty(steps) && steps[1] == FieldReferenceStep("blocked") && return nothing
    Reference(FieldReferenceStep("inner"), steps...)
end

# A test-local leaf with a gesture table of its own.
@document struct DefaultsKeyedLeaf
    text::String
end
@gestures DefaultsKeyedLeaf begin
    KeyDown(:x) => "Flip the probe" => ToggleCollapseOperation()
end

# A test-local operation that the kernel does not name, with a reference that
# the seams of the operation layer report and replace.
struct DefaultsMoveOperation <: Operation
    reference::Reference
end
ProjecturedKernel.OperationModule.operation_reference(operation::DefaultsMoveOperation) =
    operation.reference
ProjecturedKernel.OperationModule.retarget_operation(::DefaultsMoveOperation,
                                                     reference::Reference) =
    DefaultsMoveOperation(reference)

# A test-local operation that names no place and does not travel.
struct DefaultsStuckOperation <: Operation end

# A test-local projection with a gesture table: a rule that makes nothing, then two
# rules for the same key.
struct DefaultsTableProjection <: Projection end
ProjecturedKernel.ProjectionModule.get_projection_gesture_bindings(
        ::DefaultsTableProjection, iomap) = GestureBinding[
    GestureBinding(KeyDownPattern(:x), (document, event) -> nothing;
                   description = "Make nothing", domain = "Probe"),
    GestureBinding(KeyDownPattern(:x), (document, event) -> ToggleCollapseOperation();
                   description = "Flip", domain = "Probe"),
    GestureBinding(KeyDownPattern(:x), (document, event) -> DoNothingOperation();
                   description = "Stop", domain = "Probe")]

_make_defaults_key(key) = KeyDown(key, ModifierKeys(); time = 0.0)

# The steps of `reference`, with no type checkpoints.
_get_defaults_steps(reference) = get_reference_steps(strip_reference_types(reference))

function test_projection_defaults()
@testset "Projection defaults" begin

    @testset "the backward map of a printed place is the canonical introduced caret" begin
        projection = DefaultsProbeProjection()
        leaf = DefaultsProbeLeaf("text", nothing)
        iomap = SimpleIoMap(projection, leaf, nothing)
        printed = Reference(FieldReferenceStep("close"), RangeReferenceStep(0, 0))
        caret = map_reference_backward(projection, iomap, printed)
        @test caret == make_introduced_reference(projection, leaf, printed)
        @test caret.tail.type === Position
    end

    # Rerooting changes where an operation points, never what it is called.
    @testset "a reader keeps the labels of the change" begin
        change = Intent(nothing, DoNothingOperation(), "Do nothing", "Probe")
        for reader in (read_intent, read_template_intent)
            answer = reader(DefaultsProbeProjection(), nothing, change, nothing)
            @test answer.operation isa DoNothingOperation
            @test (answer.description, answer.domain) == ("Do nothing", "Probe")
        end
    end

    # These readers read an operation as one of their own output domain, so an
    # operation for a place below the input is not theirs to read.
    @testset "a reader that follows no route answers nothing for a route" begin
        route = Reference(FieldReferenceStep("items"))
        change = Intent(nothing, DoNothingOperation(), "Do nothing", "Probe", route)
        for reader in (read_intent, read_template_intent)
            answer = reader(DefaultsProbeProjection(), nothing, change, nothing)
            @test answer.operation === nothing
        end
    end

    # The kernel maps only the whole element and a place that the projection
    # printed; a projection that maps more adds its own method.
    @testset "the default forward map answers the whole element and a printed place" begin
        projection = DefaultsProbeProjection()
        input = DefaultsProbeLeaf("in", nothing)
        output = DefaultsProbeLeaf("out", nothing)
        iomap = SimpleIoMap(projection, input, output)
        @test map_reference_forward(projection, nothing, EmptyReference()) ==
              EmptyReference()
        @test map_reference_forward(projection, iomap, EmptyReference()) ==
              EmptyReference(get_reference_node_type(output))
        printed = Reference(FieldReferenceStep("text"), RangeReferenceStep(1, 1))
        caret = make_introduced_reference(projection, input, printed)
        shown = map_reference_forward(projection, iomap, caret)
        @test _get_defaults_steps(shown) == _get_defaults_steps(printed)
        @test is_fully_typed_reference(shown)
        # A place that this projection did not print has no image here.
        @test map_reference_forward(projection, iomap, printed) === nothing
        other = make_introduced_reference(DefaultsPrefixProjection(), input, printed)
        @test map_reference_forward(projection, iomap, other) === nothing
    end

    @testset "the default backward map answers the whole element of the input" begin
        projection = DefaultsProbeProjection()
        input = DefaultsProbeLeaf("in", nothing)
        iomap = SimpleIoMap(projection, input, DefaultsProbeLeaf("out", nothing))
        @test map_reference_backward(projection, iomap, EmptyReference()) ==
              EmptyReference(get_reference_node_type(input))
        @test map_reference_backward(projection, nothing, EmptyReference()) ==
              EmptyReference()
        # With no input there is no pre-image to wrap against.
        printed = Reference(FieldReferenceStep("text"))
        @test map_reference_backward(projection, nothing, printed) === printed
    end

    @testset "the default reader gives a gesture to the table of its input" begin
        projection = DefaultsProbeProjection()
        iomap = SimpleIoMap(projection, DefaultsKeyedLeaf("text", nothing), nothing)
        @test read_intent(projection, iomap, _make_defaults_key(:x)) isa
              ToggleCollapseOperation
        @test read_intent(projection, iomap, _make_defaults_key(:y)) === nothing
        # An input that is not a document, or no IoMap, has no table.
        text_iomap = SimpleIoMap(projection, "text", nothing)
        @test read_intent(projection, text_iomap, _make_defaults_key(:x)) === nothing
        @test read_intent(projection, nothing, _make_defaults_key(:x)) === nothing
        collected = read_intent(projection, iomap, CollectIntents())
        @test collected isa CollectedIntentsOperation
        @test [intent.description for intent in collected.intents] == ["Flip the probe"]
    end

    @testset "the default reader maps each operation that names a place" begin
        projection = DefaultsPrefixProjection()
        path = Reference(FieldReferenceStep("text"))
        blocked = Reference(FieldReferenceStep("blocked"))
        inner = [FieldReferenceStep("inner"), FieldReferenceStep("text")]
        read_back(operation) = read_intent(projection, nothing, operation)

        selection = read_back(ReplaceSelectionOperation(path))
        @test _get_defaults_steps(selection.path) == inner
        @test read_back(ReplaceSelectionOperation(blocked)) === nothing

        write = read_back(ReplaceReferencedValueOperation(nothing, path, "value"))
        @test write.document === nothing && write.value == "value"
        @test _get_defaults_steps(write.reference) == inner
        @test read_back(ReplaceReferencedValueOperation(nothing, blocked, 1)) === nothing
        # A write that carries its root goes on as it is.
        root = DefaultsProbeLeaf("a", nothing)
        carried = ReplaceReferencedValueOperation(root, path, 1)
        @test read_back(carried) === carried

        # An operation that the kernel does not name maps through its seams.
        moved = read_back(DefaultsMoveOperation(path))
        @test moved isa DefaultsMoveOperation
        @test _get_defaults_steps(moved.reference) == inner
        @test read_back(DefaultsMoveOperation(blocked)) === nothing
        @test read_back(DefaultsStuckOperation()) === nothing
        @test read_back(DoNothingOperation()) isa DoNothingOperation
    end

    @testset "the default reader maps each member and each operation that it holds" begin
        projection = DefaultsPrefixProjection()
        path = Reference(FieldReferenceStep("text"))
        blocked = Reference(FieldReferenceStep("blocked"))
        inner = [FieldReferenceStep("inner"), FieldReferenceStep("text")]
        read_back(operation) = read_intent(projection, nothing, operation)

        compound = read_back(CompoundOperation(Any[ReplaceSelectionOperation(path),
                                              DoNothingOperation()]))
        @test compound isa CompoundOperation
        @test _get_defaults_steps(compound.operations[1].path) == inner
        @test compound.operations[2] isa DoNothingOperation
        # A compound with a member that does not map does not map.
        @test read_back(CompoundOperation(Any[ReplaceSelectionOperation(path),
                                         ReplaceSelectionOperation(blocked)])) === nothing

        hover = read_back(ReplaceViewStateOperation(ReplaceSelectionOperation(path)))
        @test hover isa ReplaceViewStateOperation
        @test _get_defaults_steps(hover.operation.path) == inner
        @test read_back(ReplaceViewStateOperation(ReplaceSelectionOperation(blocked))) ===
              nothing

        # A collection keeps each row: a row that does not map keeps no operation.
        collected = read_back(CollectedIntentsOperation([
            Intent(nothing, ReplaceSelectionOperation(path), "Select", "Probe"),
            Intent(nothing, ReplaceSelectionOperation(blocked), "Blocked", "Probe"),
            Intent(nothing, nothing, "Declined", "Probe")]))
        @test [intent.description for intent in collected.intents] ==
              ["Select", "Blocked", "Declined"]
        @test _get_defaults_steps(collected.intents[1].operation.path) == inner
        @test collected.intents[2].operation === nothing
        @test collected.intents[3].operation === nothing
    end

    # The bridge reads the operation of a change when there is one, and the
    # gesture otherwise.
    @testset "the reader bridge reads the gesture of a change with no operation" begin
        projection = DefaultsPrefixProjection()
        gesture = ReplaceSelectionOperation(Reference(FieldReferenceStep("text")))
        answer = read_intent(projection, nothing, Intent(gesture), nothing)
        @test answer.gesture === gesture
        @test _get_defaults_steps(answer.operation.path) ==
              [FieldReferenceStep("inner"), FieldReferenceStep("text")]
    end

    @testset "a routed change reads the child, unless the child is the place" begin
        projection = DefaultsPrefixProjection()
        operation = ReplaceSelectionOperation(Reference(FieldReferenceStep("text")))
        # No route remains: the child is the place, so it is not read.
        here = Intent(:gesture, operation, "Select", "Probe", EmptyReference())
        answer = read_routed_intent(projection, nothing, here, nothing)
        @test answer.operation === operation
        @test answer.route === nothing
        @test (answer.gesture, answer.description, answer.domain) ==
              (:gesture, "Select", "Probe")
        # A route below the child goes to its reader, which follows no route.
        below = Intent(:gesture, operation, "Select", "Probe",
                       Reference(FieldReferenceStep("text")))
        answer_below = read_routed_intent(projection, nothing, below, nothing)
        @test answer_below.operation === nothing
        # A change with no route is read.
        unrouted = Intent(:gesture, operation)
        answer_read = read_routed_intent(projection, nothing, unrouted, nothing)
        @test _get_defaults_steps(answer_read.operation.path) ==
              [FieldReferenceStep("inner"), FieldReferenceStep("text")]
    end

    @testset "a projection with no gesture table reads no gesture" begin
        projection = DefaultsProbeProjection()
        iomap = SimpleIoMap(projection, DefaultsProbeLeaf("text", nothing), nothing)
        @test isempty(get_projection_gesture_bindings(projection, iomap))
        key = _make_defaults_key(:x)
        @test read_projection_gesture(projection, iomap, key) === nothing
    end

    # A rule whose operation makes nothing is skipped, so a later rule fires.
    @testset "read_projection_gesture fires the first rule that makes an operation" begin
        projection = DefaultsTableProjection()
        iomap = SimpleIoMap(projection, DefaultsProbeLeaf("text", nothing), nothing)
        @test read_projection_gesture(projection, iomap, _make_defaults_key(:x)) isa
              ToggleCollapseOperation
        other_key = _make_defaults_key(:y)
        @test read_projection_gesture(projection, iomap, other_key) === nothing
        collected = read_projection_gesture(projection, iomap, CollectIntents())
        @test [intent.description for intent in collected.intents] ==
              ["Make nothing", "Flip", "Stop"]
    end

end
end # test_projection_defaults
