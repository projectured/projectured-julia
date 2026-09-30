"""
    ProjecturedShellTest

The Shell tier of the test-package DAG: the fold that stacks a window's wrappers,
and the wrap that puts the popup resolver on the window route.

Everything is aggregated by `test_shell()`.
"""
module ProjecturedShellTest

using Test
import ProjecturedPlatform
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedSubstrateExample
using ProjecturedSubstrateTest

const _SOURCES = (ProjecturedPlatform, ProjecturedJulia, ProjecturedConsole, ProjecturedKernel, ProjecturedPdf)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/platform/shell/WindowWrapTest.jl")
include("../../../test/platform/shell/WidgetTooltipTest.jl")
include("../../../test/platform/shell/JuliaTooltipTest.jl")
include("../../../test/platform/shell/TooltipWindowTest.jl")
include("../../../test/platform/shell/ContextMenuProbeTest.jl")
include("../../../test/platform/shell/WindowShellTest.jl")
include("../../../test/platform/shell/FileDialogTest.jl")
include("../../../test/platform/shell/TrackingScreenTest.jl")
include("../../../test/platform/shell/PointerLightTest.jl")

include("../../../test/platform/shell/ShellSuite.jl")

end # module ProjecturedShellTest
