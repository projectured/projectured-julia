"""
    ProjecturedSDLTest

Test package for the opt-in `ProjecturedSDL` backend. Hosts the two SDL-coupled
suites moved down from the umbrella:

- `DirtyRectTest` — the `_compute_dirty_rect` diff over `SdlWindowResources`;
- `GraphicsToFileTest` — the `write_image` path (GraphicsCanvas → image file).

Needs native SDL2, so it precompiles and runs only where SDL is installed. Its
fixture is a JSON document.
"""
module ProjecturedSDLTest

using Test
using ProjecturedKernel
using ProjecturedPlatform
using ProjecturedJSON
using ProjecturedJSONExample
using ProjecturedSDL
using ProjecturedKernelTest

# The SDL backend must be live for the dirty-rect / write_image paths. Built in
# __init__ (runtime, after the extension loads) rather than at precompile time.
include("../../../test/backend/sdl/SdlSuite.jl")

end # module ProjecturedSDLTest
