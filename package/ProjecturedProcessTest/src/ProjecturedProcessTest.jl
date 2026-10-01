"""
    ProjecturedProcessTest

The Process tier of the test-package DAG: the suites whose fixtures are process
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_process()`.
"""
module ProjecturedProcessTest

using Test
import ProjecturedGraph
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedPlatform
import ProjecturedProcess
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedProcessExample
using ProjecturedPlatformExample
using ProjecturedPlatformTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedGraph, ProjecturedJulia, ProjecturedKernel, ProjecturedPdf, ProjecturedProcess)

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

include("../../../test/domain/process/document/ProcessDocumentTest.jl")
include("../../../test/domain/process/projection/ProcessDebugTest.jl")
include("../../../test/domain/process/projection/ProcessDiagramTest.jl")
include("../../../test/domain/process/projection/ProcessToJuliaCodeTest.jl")
include("../../../test/domain/process/projection/ProcessToSyntaxTest.jl")

include("../../../test/domain/process/ProcessSuite.jl")

end # module ProjecturedProcessTest
