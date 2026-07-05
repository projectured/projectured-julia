"""
`TimeModule` — the one global editor clock. New in kernel plan P1 (Time.jl
lived under editor/ before; there was no dedicated test).

Confirms the sample/subscribe split: `get_editor_time()` reads without
registering a dependency, `get_reactive_editor_time()` registers and re-runs
when the clock ticks.
"""

using Test
using ProjecturedKernel.TimeModule
using ProjecturedKernel.CellModule: Cell, is_up_to_date

@testset "Time" begin
    tick_editor_time!(0.0)
    @test get_editor_time() == 0.0
    @test get_reactive_editor_time() == 0.0

    # SUBSCRIBE: reading via get_reactive_editor_time makes the calling cell a
    # dependent, so the tick invalidates it.
    subscribed = Cell(() -> get_reactive_editor_time() * 2)
    @test subscribed[] == 0.0
    tick_editor_time!(1.5)
    @test !is_up_to_date(subscribed)
    @test subscribed[] == 3.0

    # SAMPLE: reading via get_editor_time registers nothing, so the tick
    # leaves the cell valid.
    sampled = Cell(() -> get_editor_time() + 10.0)
    @test sampled[] == 11.5
    tick_editor_time!(2.0)
    @test is_up_to_date(sampled)
    @test sampled[] == 11.5           # still the cached value
end
