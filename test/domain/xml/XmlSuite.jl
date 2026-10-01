"""
    test_xml_layering()

Static layered-architecture guard for `ProjecturedXML`.
"""
function test_xml_layering()
    main = get_package_source_root(ProjecturedXML)
    check_layering(main, pathof(ProjecturedXML);
                   name = "xml",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedXML; all = true)
                         if isdefined(ProjecturedXML, n) &&
                            getfield(ProjecturedXML, n) isa Module &&
                            getfield(ProjecturedXML, n) !== ProjecturedXML &&
                            parentmodule(getfield(ProjecturedXML, n)) !== ProjecturedXML))
end

"""
    test_xml()

Run this package's whole suite: the layering guard and every xml test.
"""
function test_xml()
    @testset "ProjecturedXML" begin
        test_xml_layering()
        test_xml_parser()
        test_xml_to_syntax()
        test_xml_to_syntax_reader()
        test_xml_override_gestures()
    end
end

export test_xml, test_xml_layering, test_xml_parser, test_xml_to_syntax
export test_xml_to_syntax_reader, test_xml_override_gestures
