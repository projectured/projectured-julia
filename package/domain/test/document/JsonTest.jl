function test_json()
@testset "ReactiveJSON" begin

# primitives
@test JsonNull() isa JsonNull

jb = JsonBool(true)
@test jb.value == true
jb.value = false
@test jb.value == false

jnum = JsonNumber(42)
@test jnum.value == 42
jnum.value = 3.14
@test jnum.value ≈ 3.14

js = JsonString("hello")
@test js.value == "hello"
js.value = "world"
@test js.value == "world"

# array
arr = JsonArray([JsonNumber(1), JsonNumber(2), JsonNumber(3)])
@test length(arr.elements) == 3
@test arr.elements[1].value == 1
@test arr.elements[3].value == 3

push!(arr.elements, JsonNumber(4))
@test length(arr.elements) == 4
@test arr.elements[4].value == 4

deleteat!(arr.elements, 2)
@test length(arr.elements) == 3
@test arr.elements[2].value == 3  # was index 3, now shifted

# object
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))
@test obj["name"].value == "Alice"
@test obj["age"].value == 30
@test haskey(obj, "name")
@test length(obj.entries) == 2

obj["email"] = JsonString("a@b.com")
@test obj["email"].value == "a@b.com"
@test length(obj.entries) == 3

delete!(obj, "email")
@test !haskey(obj, "email")
@test length(obj.entries) == 2

# computed JsonNumber
base = Cell(100)
comp_num = JsonNumber(ComputedCell(() -> base[] * 2))
@test comp_num.value == 200
base[] = 50
@test comp_num.value == 100

end # @testset "ReactiveJSON"
end # test_json
