# Tests for the small recursive-descent JSON parser (parse_json): enough basic
# coverage to trust turning typed source into a real document.


function test_json_parser()
    @testset "parse_json" begin
        @test parse_json("null")  isa JsonNull
        @test parse_json("true").value == true
        @test parse_json("false").value == false
        @test parse_json("42").value == 42
        @test parse_json("-3.5").value == -3.5
        @test parse_json("\"hi\\n\"").value == "hi\n"

        # A `\u` escape is one UTF-16 code unit. A high and a low surrogate read
        # together as one character, and a lone surrogate is malformed input.
        @test parse_json("\"\\u0041\"").value == "A"
        @test parse_json("\"\\ud83d\\ude00\"").value == "😀"
        @test parse_json("\"\\uD83D\\uDE00!\"").value == "😀!"
        @test_throws ErrorException parse_json("\"\\ud83d\"")
        @test_throws ErrorException parse_json("\"\\ud83dx\"")
        @test_throws ErrorException parse_json("\"\\ud83d\\u0041\"")
        @test_throws ErrorException parse_json("\"\\ude00\"")
        # A `\u` escape with a character that is not a hex digit is a parser error.
        for text in ("\"\\u00zz\"", "\"\\u+123\"", "\"\\u 123\"", "\"\\ud83d\\u12g4\"")
            error = try
                parse_json(text)
                nothing
            catch caught
                caught
            end
            @test error isa ErrorException
            @test error isa ErrorException && startswith(error.msg, "JSON: ")
        end

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
