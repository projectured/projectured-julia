"""
    test_json_assistant_api()

Loading the JSON slice offers the shape of a JSON document to the model of an
assistant: the seven document types, by name, each one a name of the slice.
"""
function test_json_assistant_api()
    @testset "the JSON slice offers its document types to an assistant" begin
        entries = [e for e in get_registered_assistant_api() if e isa Pair && first(e) === JsonModule]
        @test length(entries) == 1
        offered = collect(last(only(entries)))
        @test Set(offered) == Set([:JsonArray, :JsonObject, :JsonObjectEntry, :JsonString,
                                   :JsonNumber, :JsonBool, :JsonNull])
        @test all(name -> isdefined(JsonModule, name), offered)
    end
end
