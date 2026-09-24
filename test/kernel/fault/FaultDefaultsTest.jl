"""
`FaultModule` — what each seam of the fault layer answers when nothing above
the kernel answers it.

Confirms:
- a barrier lets an interrupt, a stack overflow and an out-of-memory error
  through, and catches an ordinary exception;
- a target of no known type keeps no fault store, and a record appended to it
  goes nowhere;
- the kernel makes no safe mode projection;
- the default sound is the BEL character on the global `stderr`, so a redirect
  of that stream takes it.
"""

using Test
using ProjecturedKernel.FaultModule

struct FaultDefaultsTarget end
struct FaultDefaultsBackend end

function test_fault_defaults()
@testset "fault defaults" begin

    @testset "the exceptions that mean stop pass through" begin
        @test is_passthrough_exception(InterruptException())
        @test is_passthrough_exception(StackOverflowError())
        @test is_passthrough_exception(OutOfMemoryError())
        @test !is_passthrough_exception(ErrorException("an ordinary fault"))
        @test !is_passthrough_exception(BoundsError([1], 2))
    end

    @testset "a target of no known type keeps no store" begin
        target = FaultDefaultsTarget()
        @test get_fault_store(target) === nothing
        record = make_fault_record(:tool; origin = :test,
                                   exception = ErrorException("x"))
        @test append_fault!(target, record) === nothing
    end

    @testset "the kernel makes no safe mode projection" begin
        @test make_safe_mode_projection(nothing) === nothing
    end

    @testset "the default sound goes to the global stderr" begin
        pipe = Pipe()
        value = redirect_stderr(pipe) do
            play_fault_sound!(FaultDefaultsBackend())
        end
        close(pipe.in)
        output = read(pipe.out, String)
        close(pipe.out)
        @test value === nothing
        @test '\a' in output
    end

end
end
