"""
    ProjecturedMathTest

The Math tier of the test-package DAG: the suites whose fixtures are math
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_math()`.
"""
module ProjecturedMathTest

using Test
import ProjecturedBase
import ProjecturedKernel
import ProjecturedMath
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedMathExample

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedMath, ProjecturedVisual)

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

include("projection/MathToGraphicsTest.jl")

"""
    test_math_layering()

Static layered-architecture guard for `ProjecturedMath`.
"""
function test_math_layering()
    main = normpath(dirname(pathof(ProjecturedMath)))
    check_layering(main, joinpath(main, "ProjecturedMath.jl");
                   name = "math",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedMath; all = true)
                         if isdefined(ProjecturedMath, n) &&
                            getfield(ProjecturedMath, n) isa Module &&
                            getfield(ProjecturedMath, n) !== ProjecturedMath &&
                            parentmodule(getfield(ProjecturedMath, n)) !== ProjecturedMath))
end

"""
    test_math()

Run this package's whole suite: the layering guard and every math test.
"""
function test_math()
    @testset "ProjecturedMath" begin
        test_math_layering()
        test_math_to_graphics()
    end
end

export test_math, test_math_layering, test_math_to_graphics

end # module ProjecturedMathTest
