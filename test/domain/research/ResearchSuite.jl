"""
    test_research_layering()

Static layered-architecture guard for `ProjecturedResearch`.
"""
function test_research_layering()
    main = get_package_source_root(ProjecturedResearch)
    check_layering(main, pathof(ProjecturedResearch);
                   name = "research",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedResearch; all = true)
                         if isdefined(ProjecturedResearch, n) &&
                            getfield(ProjecturedResearch, n) isa Module &&
                            getfield(ProjecturedResearch, n) !== ProjecturedResearch &&
                            parentmodule(getfield(ProjecturedResearch, n)) !== ProjecturedResearch))
end

"""
    test_research()

Run this package's whole suite: the layering guard and every research test.
"""
function test_research()
    @testset "ProjecturedResearch" begin
        test_research_layering()
        test_research_document()
        test_research_edits()
        test_research_to_widget()
        test_research_map_to_graph()
        test_research_roster()
        test_research_explorer()
        test_research_assistant_api()
    end
end

export test_research, test_research_layering, test_research_document, test_research_edits,
       test_research_to_widget, test_research_map_to_graph, test_research_roster,
       test_research_explorer, test_research_assistant_api
