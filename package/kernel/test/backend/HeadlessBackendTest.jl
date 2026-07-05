"""
`HeadlessBackendModule` — the dependency-free in-memory backend introduced by
kernel plan P6. Exercises the `make_backend` factory registration, the
lifecycle no-ops, and the write/read/measure I/O paths.
"""

using Test
using ProjecturedKernel.BackendModule
using ProjecturedKernel.HeadlessBackendModule
using ProjecturedKernel.DeviceModule

@testset "HeadlessBackend" begin

    @testset "make_backend(:headless) returns a HeadlessBackend" begin
        b = make_backend(:headless)
        @test b isa HeadlessBackend
        @test b isa Backend
        # Unknown kinds raise a helpful error.
        @test_throws ErrorException make_backend(:definitely_not_registered)
    end

    @testset "lifecycle is a no-op" begin
        b = HeadlessBackend()
        @test initialize_backend!(b) === nothing
        @test quit_backend!(b) === nothing
    end

    @testset "write_to_devices logs the document" begin
        b = HeadlessBackend()
        write_to_devices(b, Any[], :first)
        write_to_devices(b, Any[], :second)
        @test rendered_output(b) == [:first, :second]
    end

    @testset "read_from_devices pops the scripted queue" begin
        b = HeadlessBackend()
        @test read_from_devices(b, Any[]) === nothing
        push_event!(b, :ev1)
        push_event!(b, :ev2)
        @test read_from_devices(b, Any[]) === :ev1
        @test read_from_devices(b, Any[]) === :ev2
        @test read_from_devices(b, Any[]) === nothing
    end

    @testset "measure_text returns a fixed geometry" begin
        b = HeadlessBackend()
        @test measure_text(b, "abc", nothing) == (24, 16)
        @test measure_text(b, "", nothing) == (0, 16)
    end

end
