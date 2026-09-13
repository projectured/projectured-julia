"""
    test_xml_layering()

Static layered-architecture guard for `ProjecturedXml`.
"""
function test_xml_layering()
    main = get_package_source_root(ProjecturedXml)
    check_layering(main, pathof(ProjecturedXml);
                   name = "xml",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["XmlDocument.jl"]),
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
