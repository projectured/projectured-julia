"""
`FaultModule` — one fault as a value.

Confirms:
- a long message is cut by characters, not by bytes, so a multi-byte character
  at the cut does not make the formatting throw;
- a short message is kept whole, as one line;
- an origin that is a Union type gets a name, so the record does not throw, and
  a type, a value and `nothing` give their names;
- an exception whose own `showerror` throws gives its type name, and no
  traceback;
- a record with no backtrace has no traceback, and a long one is cut to twelve
  lines.
"""

using Test
using ProjecturedKernel.FaultModule

# An exception whose own `showerror` is broken.
struct BrokenShowException <: Exception end
Base.showerror(::IO, ::BrokenShowException) = error("showerror is broken")
Base.showerror(::IO, ::BrokenShowException, traceback) = error("showerror is broken")

# An exception whose message a person stops while it is written.
struct InterruptedShowException <: Exception end
Base.showerror(::IO, ::InterruptedShowException) = throw(InterruptException())
Base.showerror(::IO, ::InterruptedShowException, traceback) = throw(InterruptException())

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

    @testset "a type, a value and nothing give the name of the origin" begin
        exception = ErrorException("x")
        @test make_fault_record(:print; origin = String, exception).origin === :String
        @test make_fault_record(:print; origin = FaultStore(), exception).origin ===
              :FaultStore
        @test make_fault_record(:print; origin = nothing, exception).origin === :unknown
    end

    @testset "an exception whose showerror throws gives its type name" begin
        record = make_fault_record(:print; origin = :test,
                                   exception = BrokenShowException(),
                                   traceback = backtrace())
        @test (record.message, record.traceback) == ("BrokenShowException", "")
    end

    @testset "a traceback is empty with no backtrace, and a long one is cut" begin
        exception = ErrorException("x")
        @test make_fault_record(:print; origin = :test, exception).traceback == ""
        traceback = make_fault_record(:print; origin = :test, exception,
                                      traceback = backtrace()).traceback
        lines = split(traceback, '\n')
        @test (length(lines), lines[end]) == (13, "  …")
    end

    @testset "an exception that means stop goes through the formatting" begin
        exception = InterruptedShowException()
        @test_throws InterruptException FaultModule._format_fault_message(exception)
        @test_throws InterruptException FaultModule._format_fault_traceback(exception,
                                                                           backtrace())
    end

end
end
