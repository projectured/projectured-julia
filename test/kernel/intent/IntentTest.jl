"""
`IntentModule` — the carrier of the reader pipeline. Verifies the labels that
each constructor of `Intent` keeps, the route that `follow_intent_route` gives a
child, `ClaimedGesture`, and the collection of intents: its reroot, its way
back, and `merge_collected_intents`.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.ProjectionModule: Projection, read_intent

# A test-local projection with no reader of its own: it answers what the default
# reader of the kernel answers.
struct IntentProbeProjection <: Projection end

# The steps from a root to the value of its second item.
const _INTENT_ROUTE_STEPS = (FieldReferenceStep("items"), RangeReferenceStep(1, 2),
                             FieldReferenceStep("value"))

_make_routed_intent(route) =
    Intent(:gesture, DoNothingOperation(), "Do nothing", "Probe", route)

function test_intent()
@testset "Intent" begin

    @testset "each constructor keeps the labels that it gets" begin
        bare = Intent(:gesture)
        @test bare.gesture === :gesture
        @test bare.operation === nothing
        @test (bare.description, bare.domain, bare.route) == ("", "", nothing)

        carried = Intent(:gesture, DoNothingOperation())
        @test carried.operation isa DoNothingOperation
        @test (carried.description, carried.domain, carried.route) == ("", "", nothing)

        labelled = Intent(:gesture, DoNothingOperation(), SubString("Do nothing", 1),
                          "Probe")
        @test labelled.description isa String
        @test (labelled.description, labelled.domain) == ("Do nothing", "Probe")
        @test labelled.route === nothing

        route = Reference(_INTENT_ROUTE_STEPS...)
        @test _make_routed_intent(route).route === route
    end

    @testset "a route that starts with the steps gives the rest of the route" begin
        change = _make_routed_intent(Reference(_INTENT_ROUTE_STEPS...))
        items, second, _ = _INTENT_ROUTE_STEPS
        child = follow_intent_route(change, items, second)
        @test child isa Intent
        @test child.route == Reference(FieldReferenceStep("value"))
        @test child.gesture === :gesture
        @test child.operation === change.operation
        @test (child.description, child.domain) == ("Do nothing", "Probe")
        # All the steps leave the empty route: the child is the place.
        @test follow_intent_route(change, _INTENT_ROUTE_STEPS...).route isa EmptyReference
    end

    @testset "a route that does not start with the steps gives nothing" begin
        change = _make_routed_intent(Reference(_INTENT_ROUTE_STEPS...))
        @test follow_intent_route(change, FieldReferenceStep("other")) === nothing
        @test follow_intent_route(change, _INTENT_ROUTE_STEPS[1],
                                  RangeReferenceStep(0, 1)) === nothing
        # A route shorter than the steps does not start with them.
        short = _make_routed_intent(Reference(FieldReferenceStep("items")))
        @test follow_intent_route(short, _INTENT_ROUTE_STEPS...) === nothing
    end

    # A change that a gesture starts has no route, so no child is on its way.
    @testset "a route of nothing gives nothing for a step" begin
        change = Intent(:gesture, DoNothingOperation(), "Do nothing", "Probe")
        @test follow_intent_route(change, FieldReferenceStep("items")) === nothing
    end

    # A projection with nothing to say about a claimed gesture answers nothing, so
    # the claimed operation goes on as it is.
    @testset "a claimed gesture holds the gesture and the operation" begin
        claimed = ClaimedGesture(:gesture, DoNothingOperation())
        @test claimed.gesture === :gesture
        @test claimed.operation isa DoNothingOperation
        @test read_intent(IntentProbeProjection(), nothing, claimed) === nothing
    end

    # A collection travels home the same way a compound does, and for the same
    # reason: the operations inside must arrive rooted where the caller can apply
    # them. The labels are not touched — rerooting moves an operation, it does not
    # rename it.
    @testset "CollectedIntentsOperation reroots every carried operation" begin
        steps = (FieldReferenceStep("outer"), FieldReferenceStep("inner"))
        path = Reference(FieldReferenceStep("leaf"))
        collected = CollectedIntentsOperation([
            Intent(nothing, ReplaceSelectionOperation(path), "Do the thing", "Probe"),
            Intent(nothing, nothing, "Cannot right now", "Probe")])
        rc = reroot_operation(collected, steps)
        @test rc isa CollectedIntentsOperation
        @test length(rc.intents) == 2
        # The one that carries an operation is rerooted, exactly as a bare one is.
        @test rc.intents[1].operation isa ReplaceSelectionOperation
        @test rc.intents[1].operation.path ==
              reroot_operation(ReplaceSelectionOperation(path), steps).path
        # The one that declined stays declined.
        @test rc.intents[2].operation === nothing
        # Labels survive.
        @test [i.description for i in rc.intents] == ["Do the thing", "Cannot right now"]
        @test all(i -> i.domain == "Probe", rc.intents)
        # A carrier changes no document, so its way back is to do nothing.
        @test make_inverse_operation(nothing, collected) isa DoNothingOperation
    end

    @testset "merge_collected_intents takes both answers, in order" begin
        a = CollectedIntentsOperation([Intent(nothing, nothing, "a", "A")])
        b = CollectedIntentsOperation([Intent(nothing, nothing, "b", "B")])
        @test [i.description for i in merge_collected_intents(a, b).intents] == ["a", "b"]
        @test merge_collected_intents(a, nothing) === a
        @test merge_collected_intents(nothing, b) === b
        @test merge_collected_intents(nothing, nothing) === nothing
    end

end
end # test_intent
