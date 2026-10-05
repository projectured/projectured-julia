"""
`HeadlessBackend` — the dependency-free in-memory backend test double. Exercises
construction, the lifecycle no-ops, the write and read paths, and the defaults of
`get_display_size`, `get_pointer_position`, `find_system_colors`,
`configure_devices!` and `open_native_windows!`.
"""

using Test
using ProjecturedKernel.BackendModule
using ProjecturedKernelExample
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.EventModule: SystemColors

function test_headless_backend()
@testset "HeadlessBackend" begin

    @testset "HeadlessBackend() constructs a Backend" begin
        b = HeadlessBackend()
        @test b isa HeadlessBackend
        @test b isa Backend
    end

    @testset "lifecycle is a no-op" begin
        b = HeadlessBackend()
        @test initialize_backend!(b) === nothing
        @test quit_backend!(b) === nothing
    end

    @testset "write_to_devices! logs the document" begin
        b = HeadlessBackend()
        write_to_devices!(b, Any[], :first)
        write_to_devices!(b, Any[], :second)
        @test rendered_output(b) == [:first, :second]
    end

    @testset "take_from_devices! pops the scripted queue" begin
        b = HeadlessBackend()
        @test take_from_devices!(b, Any[]) === nothing
        push_event!(b, :ev1)
        push_event!(b, :ev2)
        @test take_from_devices!(b, Any[]) === :ev1
        @test take_from_devices!(b, Any[]) === :ev2
        @test take_from_devices!(b, Any[]) === nothing
    end

    @testset "get_display_size falls back to the display-free default" begin
        b = HeadlessBackend()
        @test get_display_size(b) == (1280, 800)
    end

    @testset "get_pointer_position falls back to (-1, -1)" begin
        @test get_pointer_position(HeadlessBackend()) == (-1, -1)
    end

    @testset "find_system_colors falls back to nothing, and the double answers its script" begin
        @test invoke(find_system_colors, Tuple{Backend}, HeadlessBackend()) === nothing
        @test find_system_colors(HeadlessBackend()) === nothing
        dark = SystemColors(; mode = :dark)
        @test find_system_colors(HeadlessBackend(; system_colors = dark)) === dark
    end

    @testset "open_native_windows! is a no-op for a backend with no windows" begin
        @test open_native_windows!(HeadlessBackend(), :document) === nothing
    end

    @testset "configure_devices! is a no-op for a backend that discovers nothing" begin
        b = HeadlessBackend()
        s = Display()
        @test configure_devices!(b, Device[s, Mouse(), Keyboard()]) === nothing
        @test (s.width, s.height, s.density) == (1280, 800, 1.0)   # unchanged
    end

end
end # test_headless_backend
