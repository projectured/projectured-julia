# Tests for the small recursive-descent JSON/XML parsers (parse_json / xmlparse):
# enough basic coverage to trust turning typed source into a real document.


function test_json_parser()
    @testset "parse_json" begin
        @test parse_json("null")  isa JsonNull
        @test parse_json("true").value == true
        @test parse_json("false").value == false
        @test parse_json("42").value == 42
        @test parse_json("-3.5").value == -3.5
        @test parse_json("\"hi\\n\"").value == "hi\n"

        arr = parse_json("[1, 2, 3]")
        @test arr isa JsonArray
        @test length(arr.elements) == 3

        obj = parse_json("""{"a": 1, "b": [true, null], "c": "x"}""")
        @test obj isa JsonObject
        @test length(obj.entries) == 3

        # Nested + whitespace.
        nested = parse_json("""  { "outer" : { "inner" : [ 1 ] } }  """)
        @test nested isa JsonObject

        # Malformed input errors rather than guessing.
        @test_throws Exception parse_json("{")
        @test_throws Exception parse_json("[1 2]")
        @test_throws Exception parse_json("1 2")
    end
end
