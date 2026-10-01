"""
    ProjecturedVideoTest

Test package for the opt-in `ProjecturedVideo` package. Hosts `VideoTest`
(`record_video` over an example timeline) and `ApplicationVideoTest`
(`record_application_video`, `ProjecturedSdlExample`'s `VideoBackend`-driven
recording of the whole application window), moved down from the umbrella. Needs
FFMPEG, so it precompiles and runs only where that is installed. Resolves through
the root env and uses the flat `Projectured` namespace, `ProjecturedVideo`,
`ProjecturedSdlExample`, the example factories, and `ProjecturedPlatformTest`
for the selection enumerators.
"""
module ProjecturedVideoTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedVideo
using ProjecturedSdlExample
using ProjecturedKernelTest
using ProjecturedPlatformTest    # collect_position_selections (caret seeds)

include("../../../test/backend/video/editor/VideoTest.jl")
include("../../../test/backend/video/editor/ApplicationVideoTest.jl")

include("../../../test/backend/video/VideoSuite.jl")

end # module ProjecturedVideoTest
