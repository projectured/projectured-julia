function __init__()
    initialize_backend!(SdlBackend())
end

include("backend/DirtyRectTest.jl")
include("backend/KeysymTest.jl")
include("backend/DeviceConfigTest.jl")
include("backend/InputCoalescingTest.jl")
include("backend/NativeWindowTest.jl")
include("projection/GraphicsToFileTest.jl")

"Run the whole SDL backend suite."
function test_sdl()
    @testset "ProjecturedSdl" begin
        test_dirty_rect()
        test_sdl_keysym()
        test_device_config()
        test_input_coalescing()
        test_native_window()
        test_write_image()
    end
end

export test_sdl, test_dirty_rect, test_sdl_keysym, test_device_config,
       test_input_coalescing, test_native_window, test_write_image
