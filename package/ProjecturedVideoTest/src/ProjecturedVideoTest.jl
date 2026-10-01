"""
    ProjecturedVideoTest

Test package for the opt-in `ProjecturedVideo` package. Hosts `VideoTest`
(`record_video` over an example timeline) and `ApplicationVideoTest`
(`record_application_video`, `ProjecturedSDLExample`'s `VideoBackend`-driven
recording of the whole application window), moved down from the umbrella. Needs
FFMPEG, so it precompiles and runs only where that is installed. Its fixture is a
JSON document, and `ProjecturedPlatformTest` gives the selection enumerators.
"""
module ProjecturedVideoTest

using Test
import ProjecturedConsole
import ProjecturedJSON
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedPlatform
import ProjecturedVideo
using ProjecturedKernelExample
using ProjecturedPlatformExample
using ProjecturedJSONExample
using ProjecturedSDLExample
using ProjecturedKernelTest
using ProjecturedPlatformTest    # collect_position_selections (caret seeds)

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedJSON, ProjecturedKernel, ProjecturedPDF,
                  ProjecturedVideo)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/backend/video/editor/VideoTest.jl")
include("../../../test/backend/video/editor/ApplicationVideoTest.jl")

include("../../../test/backend/video/VideoSuite.jl")

end # module ProjecturedVideoTest
