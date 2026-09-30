"""
The playback layer: the bootstrap form of `play_live!` starts a backend with the
calls and the order of `make_editor`, and quits the backend at the end.
"""

using Test
using ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.ProjectionModule: Projection
using ProjecturedKernel.PlaybackModule: play_live!

# A document for the editor of the playback.
@document struct PbProbe
    value::Int = 0
end

# The playback reads a quit before its first print, so the projection prints nothing.
struct PbUnusedProjection <: Projection end

# A backend that records each call of the start and the end, and answers a quit to
# the first read, so that the loop of the playback ends at once.
struct PbRecordingBackend <: Backend
    calls::Vector{Symbol}
end

BackendModule.initialize_backend!(b::PbRecordingBackend) =
    (push!(b.calls, :initialize_backend!); nothing)
BackendModule.configure_devices!(b::PbRecordingBackend, devices) =
    (push!(b.calls, :configure_devices!); nothing)
BackendModule.open_native_windows!(b::PbRecordingBackend, document) =
    (push!(b.calls, :open_native_windows!); nothing)
BackendModule.quit_backend!(b::PbRecordingBackend) =
    (push!(b.calls, :quit_backend!); nothing)
BackendModule.read_from_devices(b::PbRecordingBackend, devices) =
    WindowInput(:probe, WindowQuit(; time = 0.0))
BackendModule.write_to_devices(b::PbRecordingBackend, devices, document) = nothing

function test_playback()
@testset "PlaybackModule" begin

    @testset "play_live! starts the backend in the order of make_editor" begin
        backend = PbRecordingBackend(Symbol[])
        @test (play_live!(PbProbe(), PbUnusedProjection(), NamedTuple[];
                          backend = backend, window_id = :probe,
                          initial_hold = 0.0); true)
        # The backend starts before the loop and quits after it, also when the
        # loop throws.
        @test backend.calls == [:initialize_backend!, :configure_devices!,
                                :open_native_windows!, :quit_backend!]
    end

end
end # test_playback
