"""
    ProjecturedSdlTest

Test package for the opt-in `ProjecturedSdl` backend. Hosts the two SDL-coupled
suites moved down from the umbrella:

- `DirtyRectTest` — the `_compute_dirty_rect` diff over `SdlWindowResources`;
- `GraphicsToFileTest` — the `write_image` path (GraphicsCanvas → image file).

Needs native SDL2, so it precompiles and runs only where SDL is installed. Like
the umbrella and the opt-in example packages, it resolves through the root env
and uses the flat `Projectured` namespace plus `ProjecturedSdl` / the example
factories.
"""
module ProjecturedSdlTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedSdl

# The SDL backend must be live for the dirty-rect / write_image paths. Built in
# __init__ (runtime, after the extension loads) rather than at precompile time.
function __init__()
    initialize_backend!(SdlBackend())
end

include("backend/DirtyRectTest.jl")
include("backend/KeysymTest.jl")
include("backend/DeviceConfigTest.jl")
include("backend/InputCoalescingTest.jl")
include("projection/GraphicsToFileTest.jl")

"Run the whole SDL backend suite."
function test_sdl()
    @testset "ProjecturedSdl" begin
        test_dirty_rect()
        test_sdl_keysym()
        test_device_config()
        test_input_coalescing()
        test_write_image()
    end
end

export test_sdl, test_dirty_rect, test_sdl_keysym, test_device_config,
       test_input_coalescing, test_write_image

end # module ProjecturedSdlTest
