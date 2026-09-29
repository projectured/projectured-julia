"""
`FaultModule` — the barrier around one stage of work.

Confirms:
- a body that works answers its own value and resets its counter;
- a body that throws answers the fallback, and the fault is in the store with
  its count;
- a counter that is not the site counts on its own;
- an interrupt passes through, and a strict policy catches nothing;
- a barrier with no store still answers the fallback;
- a message with a multi-byte character at the cut is caught like any other.
"""

using Test
using ProjecturedKernel.FaultModule

function test_fault_barrier()
@testset "fault barrier" begin
    policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

    @testset "a body that works answers its value" begin
        store = FaultStore()
        @test run_fault_barrier!(() -> 42, store; policy, backend = nothing,
                                 site = :print) == 42
        @test isempty(get_fault_records(store))
    end

    @testset "a body that throws answers the fallback" begin
        store = FaultStore()
        for _ in 1:3
            answer = run_fault_barrier!(() -> error("broken"), store; policy,
                                        backend = nothing, site = :print,
                                        fallback = :fallback)
            @test answer === :fallback
        end
        records = get_fault_records(store)
        @test length(records) == 1
        @test records[1].site === :print
        @test records[1].count == 3
        @test get_consecutive_fault_count(store, :print) == 3
        run_fault_barrier!(() -> nothing, store; policy, backend = nothing,
                           site = :print)
        @test get_consecutive_fault_count(store, :print) == 0
    end

    @testset "a counter that is not the site counts on its own" begin
        store = FaultStore()
        run_fault_barrier!(() -> error("write"), store; policy, backend = nothing,
                           site = :device, counter = :device_write)
        run_fault_barrier!(() -> nothing, store; policy, backend = nothing,
                           site = :device, counter = :device_read)
        @test get_consecutive_fault_count(store, :device_write) == 1
        @test get_consecutive_fault_count(store, :device_read) == 0
        @test get_consecutive_fault_count(store, :device) == 0
    end

    @testset "an interrupt passes through" begin
        @test_throws InterruptException run_fault_barrier!(
            () -> throw(InterruptException()), FaultStore(); policy,
            backend = nothing, site = :print)
    end

    @testset "a strict policy catches nothing" begin
        @test_throws ErrorException run_fault_barrier!(
            () -> error("broken"), FaultStore(); policy = make_strict_fault_policy(),
            backend = nothing, site = :print)
    end

    @testset "a barrier with no store answers the fallback" begin
        @test run_fault_barrier!(() -> error("broken"), nothing; policy,
                                 backend = nothing, site = :print,
                                 fallback = :fallback) === :fallback
    end

    @testset "a multi-byte character at the cut of the message is caught" begin
        message = repeat("a", 398) * "∅" * repeat("b", 50)
        store = FaultStore()
        @test run_fault_barrier!(() -> error(message), store; policy,
                                 backend = nothing, site = :print,
                                 fallback = :fallback) === :fallback
        @test endswith(get_fault_records(store)[1].message, "∅b…")
    end

end
end
