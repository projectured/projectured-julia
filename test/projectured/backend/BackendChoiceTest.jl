# The backends declare what they draw. With every backend package loaded, two
# backends draw windows, so an editor that draws windows must name its backend,
# and the console is the one backend that draws text.

import ProjecturedKernel.EditorModule: get_backend_name, get_backend_output,
                                       collect_backend_types, make_default_backend

function test_backend_choice()
@testset "the choice of a backend" begin
    @testset "each backend declares its name and its output" begin
        @test (get_backend_name(SdlBackend), get_backend_output(SdlBackend)) == (:sdl, :windows)
        @test (get_backend_name(WebBackend), get_backend_output(WebBackend)) == (:web, :windows)
        @test (get_backend_name(ConsoleBackend), get_backend_output(ConsoleBackend)) ==
              (:console, :text)
    end

    @testset "the loaded backends, and none that needs settings" begin
        loaded = collect_backend_types()
        @test SdlBackend in loaded && WebBackend in loaded && ConsoleBackend in loaded
        # A recorder and a test double are always named by the caller.
        @test !(HeadlessBackend in loaded)
    end

    @testset "SDL and Web both draw windows, so a caller must name one" begin
        @test_throws "More than one loaded backend draws windows: SdlBackend and WebBackend" make_default_backend(:windows)
    end

    @testset "the console is the one backend that draws text" begin
        @test make_default_backend(:text) isa ConsoleBackend
    end
end
end
