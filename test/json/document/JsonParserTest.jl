# Tests for the small recursive-descent JSON/XML parsers (jsonparse / xmlparse):
# enough basic coverage to trust turning typed source into a real document.


function test_json_parser()
    @testset "jsonparse" begin
        @test jsonparse("null")  isa JsonNull
        @test jsonparse("true").value == true
        @test jsonparse("false").value == false
        @test jsonparse("42").value == 42
        @test jsonparse("-3.5").value == -3.5
        @test jsonparse("\"hi\\n\"").value == "hi\n"

        arr = jsonparse("[1, 2, 3]")
        @test arr isa JsonArray
        @test length(arr.elements) == 3

        obj = jsonparse("""{"a": 1, "b": [true, null], "c": "x"}""")
        @test obj isa JsonObject
        @test length(obj.entries) == 3

        # Nested + whitespace.
        nested = jsonparse("""  { "outer" : { "inner" : [ 1 ] } }  """)
        @test nested isa JsonObject

        # Malformed input errors rather than guessing.
        @test_throws Exception jsonparse("{")
        @test_throws Exception jsonparse("[1 2]")
        @test_throws Exception jsonparse("1 2")
    end
end
