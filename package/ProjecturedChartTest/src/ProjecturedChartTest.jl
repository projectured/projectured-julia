"""
    ProjecturedChartTest

The Chart tier of the test-package DAG: the suites whose fixtures are chart
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_chart()`.
"""
module ProjecturedChartTest

using Test
import ProjecturedChart
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedChartExample
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ProjecturedPlatformTest

const _SOURCES = (ProjecturedChart, ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

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

include("../../../test/domain/chart/projection/ChartProjectionTest.jl")
include("../../../test/domain/chart/projection/ChartThemeTest.jl")
include("../../../test/domain/chart/projection/ChartPieTest.jl")

include("../../../test/domain/chart/ChartSuite.jl")

end # module ProjecturedChartTest
