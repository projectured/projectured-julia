"""
`FaultModule` — the report cascade.

Confirms:
- `report_fault!` never throws, also when the store and the backend throw, and
  a store that throws does not close the console tier;
- with the console open, a report reaches the console and plays no sound;
- with the console closed, a report plays the sound;
- a fault of a device plays the sound also when the console took it;
- a report inside a report goes to the console alone, and the depth of the
  store goes back to zero.

A test that opens the console sends it to a `Test.TestLogger`, so the log of the
suite gets no error block.
"""

using Test
using ProjecturedKernel.FaultModule

struct AngryBackend end
FaultModule.play_fault_sound!(::AngryBackend) = error("this backend has no sound")

# A store that throws at its first use, because it has no method of a store.
struct AngryStore end

# A backend that counts the sounds that it plays.
mutable struct CountingSoundBackend
    sounds::Int
end
CountingSoundBackend() = CountingSoundBackend(0)
FaultModule.play_fault_sound!(backend::CountingSoundBackend) =
    (backend.sounds += 1; nothing)

# A backend whose sound reports the same record again, while the first report
# runs.
mutable struct NestedReportBackend
    store::FaultStore
    record::FaultRecord
    sounds::Int
    nested_tiers::Vector{Symbol}
end
function FaultModule.play_fault_sound!(backend::NestedReportBackend)
    backend.sounds += 1
    tier = report_fault!(backend.store, backend.record; policy = FaultPolicy(),
                         backend)
    push!(backend.nested_tiers, tier)
    nothing
end

# A backend whose sound is stopped by a person.
struct InterruptedSoundBackend end
FaultModule.play_fault_sound!(::InterruptedSoundBackend) = throw(InterruptException())

# Run `body` with the log sent to a test logger. Answer the value of `body` and
# the number of error lines.
function _run_with_test_logger(body)
    logger = Test.TestLogger()
    value = Base.CoreLogging.with_logger(body, logger)
    value, count(log -> log.level == Base.CoreLogging.Error, logger.logs)
end

_record_cascade_fault!(store, site) =
    record_fault!(store, site; origin = :CascadeProbe, exception = ErrorException("x"))

function test_fault_cascade()
@testset "the report cascade" begin

    @testset "report_fault! never throws, whatever is broken" begin
        store = FaultStore()
        record = record_fault!(store, :device; origin = :AngryBackend,
                               exception = ErrorException("the screen is gone"))
        # Every tier above tier 5 is broken at once: the store throws and the
        # backend throws. The cascade must still answer a tier.
        tiers, _ = _run_with_test_logger() do
            (report_fault!(AngryStore(), record; policy = FaultPolicy(),
                           backend = AngryBackend()),
             report_fault!(store, record; policy = FaultPolicy(),
                           backend = AngryBackend()))
        end
        @test tiers[1] === :console
        @test tiers[2] isa Symbol
        quiet = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)
        @test report_fault!(store, record; policy = quiet,
                            backend = AngryBackend()) === :swallowed
        @test store.depth == 0
    end

    @testset "with the console open, a report reaches the console" begin
        store = FaultStore()
        record = _record_cascade_fault!(store, :print)
        backend = CountingSoundBackend()
        tier, errors = _run_with_test_logger() do
            report_fault!(store, record; policy = FaultPolicy(), backend)
        end
        @test tier === :console
        @test errors == 1
        @test backend.sounds == 0
    end

    @testset "with the console closed, a report plays the sound" begin
        store = FaultStore()
        record = _record_cascade_fault!(store, :print)
        backend = CountingSoundBackend()
        policy = FaultPolicy(is_console_enabled = false)
        tier, errors = _run_with_test_logger() do
            report_fault!(store, record; policy, backend)
        end
        @test tier === :sound
        @test errors == 0
        @test backend.sounds == 1
    end

    @testset "a fault of a device plays the sound also after the console" begin
        store = FaultStore()
        record = _record_cascade_fault!(store, :device)
        backend = CountingSoundBackend()
        tier, errors = _run_with_test_logger() do
            report_fault!(store, record; policy = FaultPolicy(), backend)
        end
        @test tier === :console
        @test errors == 1
        @test backend.sounds == 1
    end

    @testset "a report inside a report goes to the console alone" begin
        store = FaultStore()
        record = _record_cascade_fault!(store, :device)
        backend = NestedReportBackend(store, record, 0, Symbol[])
        tier, errors = _run_with_test_logger() do
            report_fault!(store, record; policy = FaultPolicy(), backend)
        end
        # The outer report writes one line and plays the sound. The sound starts
        # the inner report, which writes the second line and plays no sound.
        @test tier === :console
        @test backend.nested_tiers == [:console]
        @test backend.sounds == 1
        @test errors == 2
        @test store.depth == 0
    end

    @testset "an exception that means stop goes through the report" begin
        store = FaultStore()
        record = _record_cascade_fault!(store, :device)
        quiet = FaultPolicy(is_console_enabled = false)
        @test_throws InterruptException report_fault!(store, record; policy = quiet,
                                                      backend = InterruptedSoundBackend())
        @test store.depth == 0
    end
end
end
