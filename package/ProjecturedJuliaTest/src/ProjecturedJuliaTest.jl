"""
    ProjecturedJuliaTest

The Julia tier of the test-package DAG: the suites whose fixtures are julia
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_julia()`.
"""
module ProjecturedJuliaTest

using Test
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
import ProjecturedPlatform
using ProjecturedJuliaExample
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ProjecturedPlatformTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedJulia, ProjecturedKernel, ProjecturedPDF)

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

include("../../../test/domain/julia/document/JuliaParserTest.jl")
include("../../../test/domain/julia/document/JuliaExpressionTest.jl")
include("../../../test/domain/julia/document/JuliaDefinitionTest.jl")
include("../../../test/domain/julia/document/JuliaDuplicateTest.jl")
include("../../../test/domain/julia/projection/JuliaToSyntaxTest.jl")
include("../../../test/domain/julia/projection/JuliaThemeTest.jl")
include("../../../test/domain/julia/projection/JuliaCodePiecesTest.jl")
include("../../../test/domain/julia/projection/JuliaFileViewTest.jl")
include("../../../test/domain/julia/editor/JuliaTypeinTest.jl")
include("../../../test/domain/julia/editor/ConversationEditorTest.jl")
include("../../../test/domain/julia/editor/JuliaTooltipTest.jl")
include("../../../test/domain/julia/editor/TooltipWindowTest.jl")

include("../../../test/domain/julia/JuliaSuite.jl")

end # module ProjecturedJuliaTest
