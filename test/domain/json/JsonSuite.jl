"""
    test_json_layering()

Static layered-architecture guard for `ProjecturedJSON`.
"""
function test_json_layering()
    main = get_package_source_root(ProjecturedJSON)
    check_layering(main, pathof(ProjecturedJSON);
                   name = "json",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedJSON; all = true)
                         if isdefined(ProjecturedJSON, n) &&
                            getfield(ProjecturedJSON, n) isa Module &&
                            getfield(ProjecturedJSON, n) !== ProjecturedJSON &&
                            parentmodule(getfield(ProjecturedJSON, n)) !== ProjecturedJSON))
end

"""
    test_json()

Run this package's whole suite: the layering guard and every json test.
"""
function test_json()
    @testset "ProjecturedJSON" begin
        test_json_layering()
        test_json_parser()
        test_json_document()
        test_json_assistant_api()
        test_json_placeholder_navigation()
        test_json_mouse_target()
        test_json_to_syntax()
        test_json_to_syntax_reader()
        test_json_gesture_collection()
    end
end

export test_json, test_json_layering, test_json_document
export test_json_parser, test_json_assistant_api
export test_json_placeholder_navigation, test_json_to_syntax, test_json_mouse_target
export test_json_to_syntax_reader, test_json_gesture_collection
