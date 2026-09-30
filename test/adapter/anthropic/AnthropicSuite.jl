"""
    test_anthropic_layering()

Static layered-architecture guard for `ProjecturedAnthropic`.
"""
function test_anthropic_layering()
    main = get_package_source_root(ProjecturedAnthropic)
    check_layering(main, pathof(ProjecturedAnthropic); name = "anthropic")
end

"""
    test_anthropic()

Run this package's whole suite: the layering guard, the choice of a model from a
recorded answer of the Models API, the alias a backend with no key names, the
factory registration, the tool schema, one live request that skips itself when
no key is exported, and the translation of a stream body into events.
"""
function test_anthropic()
    @testset "ProjecturedAnthropic" begin
        test_anthropic_layering()
        test_anthropic_model()
        test_anthropic_stream()
    end
end

export test_anthropic, test_anthropic_layering, test_anthropic_model
export test_anthropic_stream
