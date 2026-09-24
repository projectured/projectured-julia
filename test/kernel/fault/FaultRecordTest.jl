"""
`FaultModule` — one fault as a value.

Confirms:
- a long message is cut by characters, not by bytes, so a multi-byte character
  at the cut does not make the formatting throw;
- a short message is kept whole, as one line.
"""

using Test
using ProjecturedKernel.FaultModule

function test_fault_record()
@testset "fault record" begin

    @testset "a multi-byte character at the cut does not throw" begin
        # `∅` takes bytes 399 to 401, so a cut at byte 400 falls inside it.
        text = repeat("a", 398) * "∅" * repeat("b", 50)
        message = format_fault_message(ErrorException(text))
        @test length(message) == 401
        @test endswith(message, "∅b…")
    end

    @testset "a short message is kept whole, as one line" begin
        @test format_fault_message(ErrorException("one\ntwo")) == "one two"
    end

end
end
