"""
`FaultModule` — one fault as a value.

Confirms:
- a long message is cut by characters, not by bytes, so a multi-byte character
  at the cut does not make the formatting throw;
- a short message is kept whole, as one line;
- an origin that is a Union type gets a name, so the record does not throw.
"""

using Test
using ProjecturedKernel.FaultModule

function test_fault_record()
@testset "fault record" begin

    @testset "a multi-byte character at the cut does not throw" begin
        # `∅` takes bytes 399 to 401, so a cut at byte 400 falls inside it.
        text = repeat("a", 398) * "∅" * repeat("b", 50)
        message = make_fault_record(:print; origin = :test,
                                    exception = ErrorException(text)).message
        @test length(message) == 401
        @test endswith(message, "∅b…")
    end

    @testset "a short message is kept whole, as one line" begin
        record = make_fault_record(:print; origin = :test,
                                   exception = ErrorException("one\ntwo"))
        @test record.message == "one two"
    end

    @testset "an origin that is a Union type gets a name" begin
        exception = ErrorException("x")
        union_record = make_fault_record(:print; origin = Union{Int, String}, exception)
        @test union_record.origin === Symbol(string(Union{Int, String}))
        bottom_record = make_fault_record(:print; origin = Union{}, exception)
        @test bottom_record.origin === Symbol("Union{}")
    end

end
end
