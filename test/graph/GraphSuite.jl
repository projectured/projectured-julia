"""
    test_graph_layering()

Static layered-architecture guard for `ProjecturedGraph`.
"""
function test_graph_layering()
    main = get_package_source_root(ProjecturedGraph)
    check_layering(main, pathof(ProjecturedGraph);
                   name = "graph",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedGraph; all = true)
                         if isdefined(ProjecturedGraph, n) &&
                            getfield(ProjecturedGraph, n) isa Module &&
                            getfield(ProjecturedGraph, n) !== ProjecturedGraph &&
                            parentmodule(getfield(ProjecturedGraph, n)) !== ProjecturedGraph))
end

"""
    test_graph()

Run this package's whole suite: the layering guard and every graph test.
"""
function test_graph()
    @testset "ProjecturedGraph" begin
        test_graph_layering()
        test_graph_projection()
    end
end

export test_graph, test_graph_layering, test_graph_projection, test_graph
