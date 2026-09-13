"""
    test_json_layering()

Static layered-architecture guard for `ProjecturedJson`.
"""
function test_json_layering()
    main = get_package_source_root(ProjecturedJson)
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
