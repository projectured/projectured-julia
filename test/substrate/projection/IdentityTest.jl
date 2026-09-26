# The identity projection: its output is its input, and its reader passes an
# operation through but never answers with a raw gesture.

function test_identity()
@testset "IdentityProjection" begin

    number = PrimitiveNumber(1)
    iomap = print_document(IdentityProjection(), number)
    @test iomap.output === number

    @testset "an operation passes through unchanged" begin
        operation = ReplaceSelectionOperation(EmptyReference())
        @test read_intent(IdentityProjection(), iomap, operation) === operation
    end

    @testset "a gesture that the input does not answer gives no operation" begin
        @test read_intent(IdentityProjection(), iomap, MouseClick(:left, 1, 1, ModifierKeys(); time = 0.0)) === nothing
        @test read_intent(IdentityProjection(), iomap, MouseClick(:right, 1, 1, ModifierKeys(); time = 0.0)) === nothing
        @test read_intent(IdentityProjection(), iomap, MouseMove(1, 1; time = 0.0)) === nothing
    end

    @testset "a chain with an identity stage answers nothing to an unclaimed press" begin
        # A chain asks its first stage last, with the raw gesture, when no later
        # stage answered. An identity that gave the gesture back made the event
        # itself the operation of the whole read.
        chain = ChainingProjection(IdentityProjection(), IdentityProjection())
        chain_iomap = print_document(chain, number)
        change = read_intent(chain, nothing, Intent(MouseClick(:right, 1, 1, ModifierKeys(); time = 0.0)), chain_iomap)
        @test change.operation === nothing
    end

end
end
