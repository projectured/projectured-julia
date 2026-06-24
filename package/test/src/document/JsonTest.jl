function test_json()
@testset "ReactiveJSON" begin

# primitives
jn = JsonNull()
@test jn[] === nothing

jb = JsonBool(true)
@test jb[] == true
jb[] = false
@test jb[] == false

jnum = JsonNumber(42)
@test jnum[] == 42
jnum[] = 3.14
@test jnum[] ≈ 3.14

js = JsonString("hello")
@test js[] == "hello"
js[] = "world"
@test js[] == "world"

# array
arr = JsonArray([JsonNumber(1), JsonNumber(2), JsonNumber(3)])
@test length(arr.elements) == 3
@test arr.elements[1][] == 1
@test arr.elements[3][] == 3

push!(arr.elements, JsonNumber(4))
@test length(arr.elements) == 4
@test arr.elements[4][] == 4

deleteat!(arr.elements, 2)
@test length(arr.elements) == 3
@test arr.elements[2][] == 3  # was index 3, now shifted

# object
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))
@test obj["name"][] == "Alice"
@test obj["age"][] == 30
@test haskey(obj, "name")
@test length(obj.entries) == 2

obj["email"] = JsonString("a@b.com")
@test obj["email"][] == "a@b.com"
@test length(obj.entries) == 3

delete!(obj, "email")
@test !haskey(obj, "email")
@test length(obj.entries) == 2

# computed JsonNumber
base = Cell(100)
comp_num = JsonNumber(() -> base[] * 2)
@test comp_num[] == 200
base[] = 50
@test comp_num[] == 100

end # @testset "ReactiveJSON"
end # test_json
