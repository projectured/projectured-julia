"""
    ProjecturedPivotTest

The Pivot tier of the test-package DAG: the suites whose fixtures are pivot
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_pivot()`.
"""
module ProjecturedPivotTest

using Test
import ProjecturedPivot
import ProjecturedChart
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedPivotExample
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ProjecturedPlatformTest

const _SOURCES = (ProjecturedPivot, ProjecturedChart, ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

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

include("../../../test/domain/pivot/document/PivotCrossTableTest.jl")
include("../../../test/domain/pivot/document/PivotTotalsTest.jl")
include("../../../test/domain/pivot/projection/PivotTableToWidgetTest.jl")
include("../../../test/domain/pivot/projection/PivotZoneEditTest.jl")
include("../../../test/domain/pivot/projection/PivotCellViewTest.jl")
include("../../../test/domain/pivot/projection/PivotChartViewTest.jl")

include("../../../test/domain/pivot/PivotSuite.jl")

end # module ProjecturedPivotTest
