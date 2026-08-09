"""
    ProjecturedXmlTest

The Xml tier of the test-package DAG: the suites whose fixtures are xml
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_xml()`.
"""
module ProjecturedXmlTest

using Test
import ProjecturedBase
import ProjecturedKernel
import ProjecturedVisual
import ProjecturedXml
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedXmlExample

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedVisual, ProjecturedXml)

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

include("document/XmlParserTest.jl")
include("projection/XmlToSyntaxTest.jl")
include("serializer/XmlFileTest.jl")

"""
    test_xml_layering()

Static layered-architecture guard for `ProjecturedXml`.
"""
function test_xml_layering()
    main = normpath(dirname(pathof(ProjecturedXml)))
    check_layering(main, joinpath(main, "ProjecturedXml.jl");
                   name = "xml",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedXml; all = true)
                         if isdefined(ProjecturedXml, n) &&
                            getfield(ProjecturedXml, n) isa Module &&
                            getfield(ProjecturedXml, n) !== ProjecturedXml &&
                            parentmodule(getfield(ProjecturedXml, n)) !== ProjecturedXml))
end

"""
    test_xml()

Run this package's whole suite: the layering guard and every xml test.
"""
function test_xml()
    @testset "ProjecturedXml" begin
        test_xml_layering()
        test_xml_parser()
        test_xml_to_syntax()
        test_xml_to_syntax_reader()
        test_xml_override_gestures()
        test_xml_file()
    end
end

export test_xml, test_xml_layering, test_xml_parser, test_xml_to_syntax
export test_xml_to_syntax_reader, test_xml_override_gestures, test_xml_file

end # module ProjecturedXmlTest
