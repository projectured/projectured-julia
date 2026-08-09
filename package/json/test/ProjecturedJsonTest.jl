"""
    ProjecturedJsonTest

The Json tier of the test-package DAG: the suites whose fixtures are json
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_json()`.
"""
module ProjecturedJsonTest

using Test
import ProjecturedBase
import ProjecturedJson
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedJsonExample

const _SOURCES = (ProjecturedBase, ProjecturedJson, ProjecturedKernel, ProjecturedVisual)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/JsonParserTest.jl")
include("document/JsonTest.jl")
include("editor/JsonContentClicksTest.jl")
include("editor/JsonPlaceholderNavTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("serializer/JsonFileTest.jl")

"""
    test_json_layering()

Static layered-architecture guard for `ProjecturedJson`.
"""
function test_json_layering()
    main = normpath(dirname(pathof(ProjecturedJson)))
    check_layering(main, joinpath(main, "ProjecturedJson.jl");
                   name = "json",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedJson; all = true)
                         if isdefined(ProjecturedJson, n) &&
                            getfield(ProjecturedJson, n) isa Module &&
                            getfield(ProjecturedJson, n) !== ProjecturedJson &&
                            parentmodule(getfield(ProjecturedJson, n)) !== ProjecturedJson))
end

"""
    test_json()

Run this package's whole suite: the layering guard and every json test.
"""
function test_json()
    @testset "ProjecturedJson" begin
        test_json_layering()
        test_json_parser()
        test_json_document()
        test_json_placeholder_navigation()
        test_json_to_syntax()
        test_json_to_syntax_reader()
        test_json_gesture_collection()
        test_json_file()
    end
end

export test_json, test_json_layering, test_json_document
export test_json_parser
export test_json_placeholder_navigation, test_json_to_syntax
export test_json_to_syntax_reader, test_json_gesture_collection, test_json_file

end # module ProjecturedJsonTest
