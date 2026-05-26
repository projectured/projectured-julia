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
@test length(arr) == 3
@test arr[1][] == 1
@test arr[3][] == 3

push!(arr, JsonNumber(4))
@test length(arr) == 4
@test arr[4][] == 4

deleteat!(arr, 2)
@test length(arr) == 3
@test arr[2][] == 3  # was index 3, now shifted

# object
obj = JsonObject("name" => "Alice", "age" => 30)
@test obj["name"][] == "Alice"
@test obj["age"][] == 30
@test haskey(obj, "name")
@test length(obj) == 2

obj["email"] = "a@b.com"
@test obj["email"][] == "a@b.com"
@test length(obj) == 3

delete!(obj, "email")
@test !haskey(obj, "email")
@test length(obj) == 2

# jsonvalue auto-conversion
doc = jsonvalue(Dict("x" => 1, "list" => [true, "hi", nothing]))
@test doc isa JsonObject
@test doc["x"][] == 1
@test doc["list"][1][] == true
@test doc["list"][2][] == "hi"
@test doc["list"][3][] === nothing

# computed JsonNumber
base = Cell(100)
comp_num = JsonNumber(() -> base[] * 2)
@test comp_num[] == 200
base[] = 50
@test comp_num[] == 100

end # @testset "ReactiveJSON"
end # test_json
