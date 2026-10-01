"""
    test_assistant_api()

A package offers names to the model of an assistant with
`register_assistant_api!`, and `get_registered_assistant_api` answers every entry once, in
the order of the registrations, whether the package registered it once or again.
"""
function test_assistant_api()
    @testset "a loaded package offers names to the assistant" begin
        offered = Module(:AssistantApiFixture)
        before = length(get_registered_assistant_api())
        try
            register_assistant_api!(offered => (:first_name,))
            register_assistant_api!([offered => (:first_name,), offered])
            entries = get_registered_assistant_api()
            @test length(entries) == before + 2
            @test entries[end - 1] == (offered => (:first_name,))
            @test entries[end] === offered
            # The answer is a copy: a caller that changes it changes no registry.
            push!(entries, :unrelated)
            @test length(get_registered_assistant_api()) == before + 2
        finally
            filter!(e -> !(e === offered || (e isa Pair && first(e) === offered)),
                    AssistantModule._ASSISTANT_API)
        end
        @test length(get_registered_assistant_api()) == before
    end
end
