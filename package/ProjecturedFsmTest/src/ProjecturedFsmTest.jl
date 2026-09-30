"""
    ProjecturedFsmTest

The Fsm tier of the test-package DAG: the suites whose fixtures are fsm
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_fsm()`.
"""
module ProjecturedFsmTest

using Test
import ProjecturedFsm
import ProjecturedGraph
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedGraphExample
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedXmlExample
import ProjecturedJson
import ProjecturedXml
using ProjecturedFsmExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedFsm, ProjecturedGraph, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedPdf, ProjecturedXml)

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

include("../../../test/domain/fsm/document/FsmDocumentTest.jl")
include("../../../test/domain/fsm/projection/FsmDiagramTest.jl")
include("../../../test/domain/fsm/projection/FsmToJuliaCodeTest.jl")
include("../../../test/domain/fsm/projection/FsmToSyntaxTest.jl")

include("../../../test/domain/fsm/FsmSuite.jl")

end # module ProjecturedFsmTest
