"""
    ProjecturedJsonTest

The Json tier of the test-package DAG: the suites whose fixtures are json
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_json()`.
"""
module ProjecturedJsonTest

using Test
import ProjecturedJson
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNatural
import ProjecturedFileFormat
import ProjecturedGestureLog
import ProjecturedGestureHelp
import ProjecturedInspector
import ProjecturedTooltip
import ProjecturedClipboard
import ProjecturedPane
import ProjecturedSyntax
import ProjecturedWidget
import ProjecturedText
import ProjecturedLayout
import ProjecturedScreen
import ProjecturedGraphics
import ProjecturedPlot
import ProjecturedVersioning
import ProjecturedFocus
import ProjecturedDragging
import ProjecturedReflection
import ProjecturedProjection
import ProjecturedComponent
import ProjecturedStyle
import ProjecturedSerialization
import ProjecturedDomain
import ProjecturedPrimitive
import ProjecturedCollection
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedJsonExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedJson, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("../../../test/json/document/JsonParserTest.jl")
include("../../../test/json/document/JsonTest.jl")
include("../../../test/json/editor/JsonContentClicksTest.jl")
include("../../../test/json/editor/JsonPlaceholderNavTest.jl")
include("../../../test/json/projection/JsonToSyntaxTest.jl")
include("../../../test/json/serializer/JsonFileTest.jl")

"""
    test_json_layering()

Static layered-architecture guard for `ProjecturedJson`.
"""
function test_json_layering()
    main = package_source_root(ProjecturedJson)
    check_layering(main, pathof(ProjecturedJson);
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
