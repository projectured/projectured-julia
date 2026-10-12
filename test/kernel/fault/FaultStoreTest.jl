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

using Test
using ProjecturedKernel.FaultModule

struct AngryTarget end
struct QuietTarget
    seen::Vector{Any}
end
FaultModule.append_fault!(target::QuietTarget, record) = push!(target.seen, record)
FaultModule.append_fault!(::AngryTarget, record) = error("this target refuses records")

# A target with no `append_fault!` of its own, so it shows nothing.
struct BlindTarget end

# A backend that counts the sounds that the drain plays.
mutable struct DrainSoundBackend
    sounds::Int
end
FaultModule.play_fault_sound!(backend::DrainSoundBackend) =
    (backend.sounds += 1; nothing)

# A target that a person stops when it takes the record of one origin.
mutable struct StoppingTarget
    stop_at::Symbol
    seen::Vector{Symbol}
end
function FaultModule.append_fault!(target::StoppingTarget, record)
    record.origin === target.stop_at && throw(InterruptException())
    push!(target.seen, record.origin)
end

# A target that a person stops while it takes a record.
struct InterruptedTarget end
FaultModule.append_fault!(::InterruptedTarget, record) = throw(InterruptException())

function test_fault_store()
@testset "the fault store" begin

    @testset "one bug at three thousand nodes is one record" begin
        store = FaultStore()
        for index in 1:3000
            record_fault!(store, :print; origin = :SyntaxToText,
                          exception = BoundsError([1], index))
        end
        records = get_fault_records(store)
        @test length(records) == 1
        @test records[1].count == 3000
        @test records[1].origin === :SyntaxToText
        @test records[1].exception_type === :BoundsError
    end

    @testset "a record keeps its first occurrence" begin
        store = FaultStore()
        record_fault!(store, :print; origin = :P, reference = 1,
                      exception = ErrorException("first"))
        record = record_fault!(store, :print; origin = :P, reference = 2,
                               exception = ErrorException("second"))
        @test (record.message, record.first_reference, record.count) == ("first", 1, 2)
    end

    @testset "a different exception in the same place is a different fault" begin
        store = FaultStore()
        record_fault!(store, :print; origin = :SyntaxToText,
                      exception = BoundsError([1], 1))
        record_fault!(store, :print; origin = :SyntaxToText,
                      exception = ErrorException("other"))
        @test length(get_fault_records(store)) == 2
    end

    @testset "the same exception in a different place is a different fault" begin
        store = FaultStore()
        record_fault!(store, :print; origin = :SyntaxToText,
                      exception = ErrorException("x"))
        record_fault!(store, :read; origin = :SyntaxToText,
                      exception = ErrorException("x"))
        @test length(get_fault_records(store)) == 2
    end

    @testset "a full store counts the faults that do not fit into one record" begin
        @test FaultStore().capacity == 64
        store = FaultStore(capacity = 3)
        answers = [record_fault!(store, :print; origin = Symbol("P", index),
                                 exception = ErrorException("e")) for index in 1:10]
        # Every key waits for the drain, so no key can make room.
        @test [record.origin for record in get_fault_records(store)] ==
              [:P1, :P2, :P3, :FaultStore]
        @test all(isnothing, answers[4:10])
        overflow = last(get_fault_records(store))
        @test (overflow.site, overflow.origin, overflow.count) == (:store, :FaultStore, 7)
        @test record_fault!(store, :print; origin = :P1,
                            exception = ErrorException("e")).count == 2
    end

    @testset "a full store forgets the oldest record that the drain handed over" begin
        quiet = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)
        store = FaultStore(capacity = 2)
        fail!(origin) = record_fault!(store, :print; origin, exception = ErrorException("e"))
        fail!(:A); fail!(:B)
        drain_faults!(store; policy = quiet)
        fail!(:C)
        @test [record.origin for record in get_fault_records(store)] == [:B, :C]
        fail!(:D)
        @test [record.origin for record in get_fault_records(store)] == [:C, :D]
        # C and D wait for the drain, so E and F count into the overflow record.
        @test (fail!(:E), fail!(:F)) === (nothing, nothing)
        @test last(get_fault_records(store)).count == 2
        @test [record.origin for record in drain_faults!(store; policy = quiet)] ==
              [:C, :D, :FaultStore]
        # A key that comes back after the store forgot it starts a new count.
        @test fail!(:A).count == 1
        @test [record.origin for record in get_fault_records(store)] ==
              [:D, :FaultStore, :A]
    end

    @testset "a store holds at least one fault" begin
        @test_throws ArgumentError FaultStore(capacity = 0)
    end

    @testset "one drain hands a record over once, with its last count" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        attach_fault_target!(store, target)
        for _ in 1:3000
            record_fault!(store, :print; origin = :SyntaxToText,
                          exception = ErrorException("e"))
        end
        # Counts 1, 10, 100 and 1000 each open a new bucket before the drain.
        drained = drain_faults!(store)
        @test length(drained) == 1
        @test drained[1].count == 3000
        @test length(target.seen) == 1
        @test isempty(drain_faults!(store))
        # The next bucket starts at 10000, and it queues the record again.
        for _ in 1:7000
            record_fault!(store, :print; origin = :SyntaxToText,
                          exception = ErrorException("e"))
        end
        @test [record.count for record in drain_faults!(store)] == [10000]
    end

    @testset "a drain with nothing new writes nothing" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        attach_fault_target!(store, target)
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
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
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        records = @test_logs((:error, "[fault] a fault target refused a record"),
                             drain_faults!(store))
        @test length(records) == 1
        @test length(good.seen) == 1
    end

    @testset "a policy with the console closed writes no line for a refusal" begin
        store = FaultStore()
        attach_fault_target!(store, AngryTarget())
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        quiet = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)
        records = @test_logs drain_faults!(store; policy = quiet)
        @test length(records) == 1
    end

    @testset "a target is attached once, and a detached target takes nothing" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        @test attach_fault_target!(store, target) === store
        attach_fault_target!(store, target)
        # A target that is not attached changes nothing.
        @test detach_fault_target!(store, QuietTarget(Any[])) === store
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        drain_faults!(store)
        @test length(target.seen) == 1
        @test detach_fault_target!(store, target) === store
        record_fault!(store, :print; origin = :Q, exception = ErrorException("e"))
        drain_faults!(store; policy = FaultPolicy(is_console_enabled = false,
                                                  is_sound_enabled = false))
        @test length(target.seen) == 1
    end

    @testset "the drain reports on the console only a record that no target took" begin
        policy = FaultPolicy(is_sound_enabled = false)
        shown = FaultStore()
        attach_fault_target!(shown, QuietTarget(Any[]))
        record_fault!(shown, :print; origin = :Shown, exception = ErrorException("e"))
        @test length(@test_logs(drain_faults!(shown; policy))) == 1
        alone = FaultStore()
        record_fault!(alone, :print; origin = :Alone, exception = ErrorException("e"))
        @test length(@test_logs((:error, r"^\[fault\] print in Alone: e$"),
                                drain_faults!(alone; policy))) == 1
    end

    @testset "the drain plays the sound of a device fault that a target took" begin
        store = FaultStore()
        attach_fault_target!(store, QuietTarget(Any[]))
        record_fault!(store, :device; origin = :Screen, exception = ErrorException("gone"))
        backend = DrainSoundBackend(0)
        @test length(@test_logs(drain_faults!(store; policy = FaultPolicy(), backend))) == 1
        @test backend.sounds == 1
    end

    @testset "a record that only a target with no method was given reaches the console" begin
        store = FaultStore()
        attach_fault_target!(store, BlindTarget())
        record_fault!(store, :print; origin = :Unshown, exception = ErrorException("e"))
        @test_logs((:error, r"^\[fault\] print in Unshown: e$"),
                   drain_faults!(store; policy = FaultPolicy(is_sound_enabled = false)))
    end

    @testset "a record whose only target refuses it reaches the console" begin
        store = FaultStore()
        attach_fault_target!(store, AngryTarget())
        record_fault!(store, :print; origin = :Refused, exception = ErrorException("e"))
        @test_logs((:error, "[fault] a fault target refused a record"),
                   (:error, r"^\[fault\] print in Refused: e$"),
                   drain_faults!(store; policy = FaultPolicy(is_sound_enabled = false)))
    end

    @testset "a stop exception in the drain leaves the records after it waiting" begin
        store = FaultStore()
        target = StoppingTarget(:B, Symbol[])
        attach_fault_target!(store, target)
        for origin in (:A, :B, :C)
            record_fault!(store, :print; origin, exception = ErrorException("e"))
        end
        @test_throws InterruptException drain_faults!(store)
        @test target.seen == [:A]
        target.stop_at = :nothing
        @test [record.origin for record in drain_faults!(store)] == [:B, :C]
        @test target.seen == [:A, :B, :C]
    end

    @testset "a policy that is not a FaultPolicy throws before the drain" begin
        store = FaultStore()
        target = QuietTarget(Any[])
        attach_fault_target!(store, target)
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        @test_throws ArgumentError drain_faults!(store; policy = :quiet)
        @test isempty(target.seen)
        # The record waits for the next drain.
        @test length(drain_faults!(store)) == 1
        @test length(target.seen) == 1
    end

    @testset "no store is a working store" begin
        @test record_fault!(nothing, :print; origin = :P,
                            exception = ErrorException("e")) === nothing
        @test isempty(drain_faults!(nothing))
        @test isempty(get_fault_records(nothing))
        @test get_consecutive_fault_count(nothing, :print) == 0
        @test attach_fault_wake!(nothing, () -> nothing) === nothing
        @test attach_fault_target!(nothing, QuietTarget(Any[])) === nothing
        @test detach_fault_target!(nothing, QuietTarget(Any[])) === nothing
    end

    @testset "a queued record wakes, a plain count bump does not" begin
        store = FaultStore()
        wakes = Ref(0)
        attach_fault_wake!(store, () -> wakes[] += 1)
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        @test wakes[] == 1                     # the new key woke
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        @test wakes[] == 1                     # count 2, same bucket: no wake
        for _ in 3:10
            record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        end
        @test wakes[] == 2                     # count 10, new bucket: one wake
    end

    @testset "a wake that throws is swallowed" begin
        store = FaultStore()
        attach_fault_wake!(store, () -> error("the wake is broken"))
        @test record_fault!(store, :print; origin = :P,
                            exception = ErrorException("e")).origin === :P
    end

    @testset "an exception that means stop goes through the drain and the wake" begin
        store = FaultStore()
        attach_fault_target!(store, InterruptedTarget())
        record_fault!(store, :print; origin = :P, exception = ErrorException("e"))
        @test_throws InterruptException drain_faults!(store)
        woken = FaultStore()
        attach_fault_wake!(woken, () -> throw(InterruptException()))
        @test_throws InterruptException record_fault!(woken, :print; origin = :P,
                                                      exception = ErrorException("e"))
    end
end
end
