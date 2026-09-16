function __init__()
    initialize_backend!(SdlBackend())
end

include("backend/DirtyRectTest.jl")
include("backend/KeysymTest.jl")
include("backend/DeviceConfigTest.jl")
include("backend/FontFallbackTest.jl")
include("backend/InputCoalescingTest.jl")
include("backend/NativeWindowTest.jl")
include("projection/GraphicsToFileTest.jl")

"""
    test_sdl_layering()

Static layered-architecture guard for `ProjecturedSdl`.
"""
function test_sdl_layering()
    main = get_package_source_root(ProjecturedSdl)
    check_layering(main, pathof(ProjecturedSdl);
                   name = "sdl",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSdl; all = true)
                         if isdefined(ProjecturedSdl, n) &&
                            getfield(ProjecturedSdl, n) isa Module &&
                            getfield(ProjecturedSdl, n) !== ProjecturedSdl &&
                            parentmodule(getfield(ProjecturedSdl, n)) !== ProjecturedSdl))
end

"Run the whole SDL backend suite."
function test_sdl()
    @testset "ProjecturedSdl" begin
        test_dirty_rect()
        test_sdl_keysym()
        test_device_config()
        test_sdl_font_fallback()
        test_input_coalescing()
        test_native_window()
        test_write_image()
    end
end

export test_sdl, test_sdl_layering, test_dirty_rect, test_sdl_keysym, test_device_config, test_sdl_font_fallback,
       test_input_coalescing, test_native_window, test_write_image
