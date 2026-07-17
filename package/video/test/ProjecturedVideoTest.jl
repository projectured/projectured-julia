"""
    ProjecturedVideoTest

Test package for the opt-in `ProjecturedVideo` package. Hosts `VideoTest`
(`record_video` over an example timeline), moved down from the umbrella. Needs
FFMPEG, so it precompiles and runs only where that is installed. Resolves through
the root env and uses the flat `Projectured` namespace, `ProjecturedVideo`, the
example factories, and `ProjecturedBaseTest` for the selection enumerators.
"""
module ProjecturedVideoTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedVideo
using ProjecturedBaseTest    # collect_position_selections (caret seeds)

include("editor/VideoTest.jl")

"Run the video-recording suite."
function test_video()
    @testset "ProjecturedVideo" begin
        test_record_video()
    end
end

export test_video, test_record_video

end # module ProjecturedVideoTest
