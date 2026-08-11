"""
    ProjecturedFormulaTest

The Formula tier of the test-package DAG: the suites whose fixtures are formula
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_formula()`.
"""
module ProjecturedFormulaTest

using Test
import ProjecturedBase
import ProjecturedFormula
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedFormulaExample

const _SOURCES = (ProjecturedBase, ProjecturedFormula, ProjecturedJulia, ProjecturedKernel, ProjecturedVisual)

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

include("projection/FormulaToSyntaxTest.jl")

"""
    test_formula_layering()

Static layered-architecture guard for `ProjecturedFormula`.
"""
function test_formula_layering()
    main = normpath(dirname(pathof(ProjecturedFormula)))
    check_layering(main, joinpath(main, "ProjecturedFormula.jl");
                   name = "formula",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFormula; all = true)
                         if isdefined(ProjecturedFormula, n) &&
                            getfield(ProjecturedFormula, n) isa Module &&
                            getfield(ProjecturedFormula, n) !== ProjecturedFormula &&
                            parentmodule(getfield(ProjecturedFormula, n)) !== ProjecturedFormula))
end

"""
    test_formula()

Run this package's whole suite: the layering guard and every formula test.
"""
function test_formula()
    @testset "ProjecturedFormula" begin
        test_formula_layering()
        test_formula_to_syntax()
    end
end

export test_formula, test_formula_layering, test_formula_to_syntax

end # module ProjecturedFormulaTest
