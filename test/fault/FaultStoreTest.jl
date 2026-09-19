# The kernel's fault store — the object a reactive thunk may write.
#
# The properties under test are the two that make it safe to write from inside a
# thunk, and the one that keeps its report readable:
#
#   • a key the store already holds takes a count, not a second record, so a
#     thunk that runs many times for one logical fault leaves one entry;
#   • the key holds no reference, so one bug at three thousand nodes is one line
#     with a number rather than three thousand lines that fill the store;
#   • the drain hands a record over once per power of ten, so a fault that
#     repeats every frame does not rewrite the log every frame.


struct AngryTarget end
struct QuietTarget
    seen::Vector{Any}
end
FaultModule.append_fault!(target::QuietTarget, record) = push!(target.seen, record)
FaultModule.append_fault!(::AngryTarget, record) = error("this target refuses records")

struct AngryBackend end
FaultModule.play_fault_sound!(::AngryBackend) = error("this backend has no sound")

_quiet_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

function test_fault_store()
@testset "the fault store" begin

    @testset "one bug at three thousand nodes is one record" begin
        store = FaultStore()
        for index in 1:3000
            record_fault!(store, :print, :SyntaxToText, nothing, BoundsError([1], index))
        end
        records = get_fault_records(store)
        @test length(records) == 1
        @test records[1].count == 3000
        @test records[1].origin === :SyntaxToText
        @test records[1].exception_type === :BoundsError
        @test store.dropped == 0
    end

    @testset "a different exception in the same place is a different fault" begin
        store = FaultStore()
        record_fault!(store, :print, :SyntaxToText, nothing, BoundsError([1], 1))
        record_fault!(store, :print, :SyntaxToText, nothing, ErrorException("other"))
        @test length(get_fault_records(store)) == 2
    end

    @testset "the same exception in a different place is a different fault" begin
        store = FaultStore()
        record_fault!(store, :print, :SyntaxToText, nothing, ErrorException("x"))
        record_fault!(store, :read, :SyntaxToText, nothing, ErrorException("x"))
        @test length(get_fault_records(store)) == 2
    end

    @testset "the store is bounded and says what it dropped" begin
        store = FaultStore(capacity = 3)
        for index in 1:10
            record_fault!(store, :print, Symbol("P", index), nothing, ErrorException("e"))
        end
        @test length(get_fault_records(store)) == 3
        @test store.dropped == 7
    end

    @testset "the drain hands a record over once per power of ten" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        attach_fault_target!(store, target)
        for _ in 1:3000
            record_fault!(store, :print, :SyntaxToText, nothing, ErrorException("e"))
        end
        # Counts 1, 10, 100 and 1000 each open a new bucket; 3000 does not.
        @test length(drain_faults!(store)) == 4
        @test length(target.seen) == 4
        @test isempty(drain_faults!(store))
    end

    @testset "a drain with nothing new writes nothing" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        attach_fault_target!(store, target)
        record_fault!(store, :print, :P, nothing, ErrorException("e"))
        drain_faults!(store)
        before = length(target.seen)
        @test isempty(drain_faults!(store))
        @test length(target.seen) == before
    end

    @testset "a target that refuses a record does not stop the drain" begin
        store = FaultStore()
        good = QuietTarget(Any[])
        attach_fault_target!(store, AngryTarget())
        attach_fault_target!(store, good)
        record_fault!(store, :print, :P, nothing, ErrorException("e"))
        @test length(drain_faults!(store)) == 1
        @test length(good.seen) == 1
    end

    @testset "no store is a working store" begin
        @test record_fault!(nothing, :print, :P, nothing, ErrorException("e")) === nothing
        @test isempty(drain_faults!(nothing))
        @test isempty(get_fault_records(nothing))
        @test get_consecutive_fault_count(nothing, :print) == 0
        @test attach_fault_wake!(nothing, () -> nothing) === nothing
    end

    @testset "a queued record wakes, a plain count bump does not" begin
        store = FaultStore()
        wakes = Ref(0)
        attach_fault_wake!(store, () -> wakes[] += 1)
        record_fault!(store, :print, :P, nothing, ErrorException("e"))
        @test wakes[] == 1                     # the new key woke
        record_fault!(store, :print, :P, nothing, ErrorException("e"))
        @test wakes[] == 1                     # count 2, same bucket: no wake
        for _ in 3:10
            record_fault!(store, :print, :P, nothing, ErrorException("e"))
        end
        @test wakes[] == 2                     # count 10, new bucket: one wake
    end

    @testset "a wake that throws is swallowed" begin
        store = FaultStore()
        attach_fault_wake!(store, () -> error("the wake is broken"))
        @test record_fault!(store, :print, :P, nothing, ErrorException("e")) !== nothing
    end
end
end

function test_fault_report()
@testset "the report cascade" begin

    @testset "report_fault! never throws, whatever is broken" begin
        store = FaultStore()
        attach_fault_target!(store, AngryTarget())
        record = record_fault!(store, :device, :AngryBackend, nothing,
                               ErrorException("the screen is gone"))
        # Every tier above tier 5 is broken at once: the target throws and the
        # backend throws. The cascade must still answer a tier.
        @test report_fault!(store, FaultPolicy(), AngryBackend(), record) isa Symbol
        @test report_fault!(store, _quiet_policy(), AngryBackend(), record) === :swallowed
        @test report_fault!(store, FaultPolicy(), AngryBackend(), nothing) === :swallowed
        @test store.depth == 0
    end
end
end
