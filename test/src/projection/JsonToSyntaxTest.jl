function test_json_to_syntax()
@testset "JsonToSyntax" begin

j2s = RecursiveProjection(JsonToSyntax())
@test render(projection_print(j2s, JsonNull()).output) == "null"
@test render(projection_print(j2s, JsonBool(true)).output) == "true"
@test render(projection_print(j2s, JsonBool(false)).output) == "false"
@test render(projection_print(j2s, JsonNumber(42)).output) == "42"
@test render(projection_print(j2s, JsonString("hi")).output) == "\"hi\""
@test render(projection_print(j2s, JsonString("a\"b")).output) == "\"a\\\"b\""

# array
ja = JsonArray([JsonNumber(1), JsonNumber(2)])
@test render(projection_print(j2s, ja).output) == "[1, 2]"

# object (order-independent check)
jo = JsonObject("a" => 1)
rendered_obj = render(projection_print(j2s, jo).output)
@test occursin("\"a\": 1", rendered_obj)

# incremental: value change propagates through syntax tree
jdoc = JsonObject("x" => 10)
jtree = projection_print(j2s, jdoc).output
jout = Cell(() -> render(jtree))
@test occursin("10", jout[])

jdoc["x"][] = 99
@test !isuptodate(jout)
@test occursin("99", jout[])

# structural change
push!(JsonArray([JsonNumber(1)]), JsonNumber(2))

end # @testset "JsonToSyntax"
end # test_json_to_syntax
