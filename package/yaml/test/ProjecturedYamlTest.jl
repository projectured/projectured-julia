"""
    ProjecturedYamlTest

The Yaml tier of the test-package DAG: the suites whose fixtures are yaml
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_yaml()`.
"""
module ProjecturedYamlTest

using Test
import ProjecturedBase
import ProjecturedKernel
import ProjecturedVisual
import ProjecturedYaml
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedYamlExample

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedVisual, ProjecturedYaml)

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


include("document/YamlParserTest.jl")

"""
    test_yaml_layering()

Static layered-architecture guard for `ProjecturedYaml`.
"""
function test_yaml_layering()
    main = normpath(dirname(pathof(ProjecturedYaml)))
    check_layering(main, joinpath(main, "ProjecturedYaml.jl");
                   name = "yaml",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedYaml; all = true)
                         if isdefined(ProjecturedYaml, n) &&
                            getfield(ProjecturedYaml, n) isa Module &&
                            getfield(ProjecturedYaml, n) !== ProjecturedYaml &&
                            parentmodule(getfield(ProjecturedYaml, n)) !== ProjecturedYaml))
end

"""
    test_yaml()

Run this package's whole suite: the layering guard and every yaml test.
"""
function test_yaml()
    @testset "ProjecturedYaml" begin
        test_yaml_layering()
        test_yaml_parser()
    end
end

export test_yaml, test_yaml_layering, test_yaml_parser

end # module ProjecturedYamlTest
