"""
    ProjecturedVideoTest

Test package for the opt-in `ProjecturedVideo` package. Hosts `VideoTest`
(`record_video` over an example timeline), moved down from the umbrella. Needs
FFMPEG, so it precompiles and runs only where that is installed. Resolves through
the root env and uses the flat `Projectured` namespace, `ProjecturedVideo`, the
example factories, and `ProjecturedSubstrateTest` for the selection enumerators.
"""
module ProjecturedVideoTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedVideo
using ProjecturedKernelTest
using ProjecturedSubstrateTest    # collect_position_selections (caret seeds)

include("../../../test/video/editor/VideoTest.jl")

include("../../../test/video/VideoSuite.jl")

end # module ProjecturedVideoTest
