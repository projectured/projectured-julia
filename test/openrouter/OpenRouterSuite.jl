"""
    test_openrouter_layering()

Static layered-architecture guard for `ProjecturedOpenRouter`.
"""
function test_openrouter_layering()
    main = get_package_source_root(ProjecturedOpenRouter)
    check_layering(main, pathof(ProjecturedOpenRouter); name = "openrouter")
end

"""
    test_openrouter()

Run this package's whole suite: the layering guard, the requests and answers of
the relevance model with a stand-in for the network, and one live request that
skips itself when no key is exported.
"""
function test_openrouter()
    @testset "ProjecturedOpenRouter" begin
        test_openrouter_layering()
        test_openrouter_relevance()
        test_openrouter_live()
    end
end

export test_openrouter, test_openrouter_layering, test_openrouter_relevance, test_openrouter_live
