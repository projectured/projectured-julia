# The wrapper `window` of the screen package: `build_editor` puts the root
# document in one window, and leaves a screen, or a backend that draws text,
# alone.

import ProjecturedKernel.BackendModule: Backend, initialize_backend!, quit_backend!,
                                        read_from_devices, write_to_devices,
                                        get_display_size
import ProjecturedKernel.EditorModule: get_backend_output, build_editor
import ProjecturedKernel.DeviceModule: Device
import ProjecturedScreen.ScreenModule: ScreenDocument, make_window_scene,
                                       make_window_scene_projection

# A backend that declares no output, as a recorder and a test double do, and one
# whose output is not windows. The output is a name that no backend uses, so the
# double never joins the choice of a backend in another test.
struct WindowWrapperProbeBackend <: Backend end
struct WindowWrapperTextBackend <: Backend end
initialize_backend!(::Union{WindowWrapperProbeBackend,WindowWrapperTextBackend}) = nothing
quit_backend!(::Union{WindowWrapperProbeBackend,WindowWrapperTextBackend}) = nothing
read_from_devices(::Union{WindowWrapperProbeBackend,WindowWrapperTextBackend}, devices) = nothing
write_to_devices(::Union{WindowWrapperProbeBackend,WindowWrapperTextBackend}, devices,
                 output) = nothing
get_backend_output(::Type{WindowWrapperTextBackend}) = :window_wrapper_text

function test_window_wrapper()
@testset "the window wrapper" begin
    @testset "the document goes into one window of the given title and size" begin
        editor = build_editor(PrimitiveString("x"), IdentityProjection();
                              backend = WindowWrapperProbeBackend(), devices = Device[], tabs = false,
                              window = (; title = "Probe", width = 320, height = 200))
        screen = editor.document
        @test screen isa ScreenDocument && length(screen.windows) == 1
        window = screen.windows[1]
        @test (window.id, window.title, window.width, window.height) ==
              (:Probe, "Probe", 320, 200)
        @test window.content isa PrimitiveString
    end

    @testset "with no setting, the size is the display's" begin
        editor = build_editor(PrimitiveString("x"), IdentityProjection();
                              backend = WindowWrapperProbeBackend(), devices = Device[], tabs = false)
        window = editor.document.windows[1]
        @test (window.width, window.height) == get_display_size(WindowWrapperProbeBackend())
        @test window.title == "ProjecturEd"
    end

    @testset "window = false, a screen, and a backend that draws text keep the root" begin
        @test build_editor(PrimitiveString("x"), IdentityProjection();
                           backend = WindowWrapperProbeBackend(), devices = Device[], tabs = false,
                           window = false).document isa PrimitiveString
        screen = make_window_scene(PrimitiveString("x"), "Own"; width = 100, height = 100)
        @test build_editor(screen, make_window_scene_projection(IdentityProjection());
                           backend = WindowWrapperProbeBackend(),
                           devices = Device[], tabs = false).document === screen
        @test build_editor(PrimitiveString("x"), IdentityProjection();
                           backend = WindowWrapperTextBackend(),
                           devices = Device[], tabs = false).document isa PrimitiveString
    end
end
end
