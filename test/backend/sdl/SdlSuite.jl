function __init__()
    initialize_backend!(SdlBackend())
end

include("backend/DirtyRectTest.jl")
include("backend/LaidOutCanvasTest.jl")
include("backend/PaintFaultTest.jl")
include("backend/KeysymTest.jl")
include("backend/DeviceConfigTest.jl")
include("backend/FontMetricsAgreementTest.jl")
include("backend/TextBaselineTest.jl")
include("backend/InputCoalescingTest.jl")
include("backend/PointerShapeTest.jl")
include("backend/WaitWakeTest.jl")
include("backend/SystemColorQueryTest.jl")
include("backend/NativeWindowTest.jl")
include("projection/GraphicsToFileTest.jl")
include("projection/TreeRenderTest.jl")

"""
    test_sdl_layering()

Static layered-architecture guard for `ProjecturedSDL`.
"""
function test_sdl_layering()
    main = get_package_source_root(ProjecturedSDL)
    check_layering(main, pathof(ProjecturedSDL);
                   name = "sdl",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSDL; all = true)
                         if isdefined(ProjecturedSDL, n) &&
                            getfield(ProjecturedSDL, n) isa Module &&
                            getfield(ProjecturedSDL, n) !== ProjecturedSDL &&
                            parentmodule(getfield(ProjecturedSDL, n)) !== ProjecturedSDL))
end

"Run the whole SDL backend suite."
function test_sdl()
    @testset "ProjecturedSDL" begin
        test_sdl_layering()
        test_dirty_rect()
        test_laid_out_canvas()
        test_paint_fault()
        test_sdl_keysym()
        test_device_config()
        test_sdl_font_metrics_agree()
        test_sdl_text_baseline_ink()
        test_sdl_text_pen_positions()
        test_input_coalescing()
        test_sdl_pointer_shape()
        test_sdl_wait_wake()
        test_sdl_system_colors()
        test_native_window()
        test_write_image()
        test_tree_render()
    end
end

export test_sdl, test_sdl_layering, test_dirty_rect, test_laid_out_canvas, test_paint_fault, test_sdl_keysym, test_device_config, test_sdl_font_metrics_agree, test_sdl_text_baseline_ink,
       test_sdl_text_pen_positions,
       test_input_coalescing, test_sdl_pointer_shape, test_sdl_wait_wake, test_sdl_system_colors, test_native_window, test_write_image, test_tree_render
