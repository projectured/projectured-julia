function test_syntax()
@testset "ReactiveSyntax" begin

leaf = SyntaxLeaf("hello"; open="(", close=")")
@test render(leaf) == "(hello)"

leaf2 = SyntaxLeaf("content")
@test render(leaf2) == "content"

node = SyntaxNode(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b"), SyntaxLeaf("c")]; open="[", close="]", sep=", ")
@test render(node) == "[a, b, c]"

# nested
inner = SyntaxNode(SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2")]; open="(", close=")", sep="+")
outer = SyntaxNode(SyntaxDocument[inner, SyntaxLeaf("x")]; open="{", close="}", sep="; ")
@test render(outer) == "{(1+2); x}"

# mutation
push!(node.children, SyntaxLeaf("d"))
@test render(node) == "[a, b, c, d]"

deleteat!(node.children, 1)
@test render(node) == "[b, c, d]"

# computed children
src = Cell(3)
dyn = SyntaxNode(() -> SyntaxDocument[SyntaxLeaf(string(i)) for i in 1:src[]]; open="<", close=">", sep=",")
@test render(dyn) == "<1,2,3>"
src[] = 5
@test render(dyn) == "<1,2,3,4,5>"

# computed leaf value
val = Cell("hi")
cl = SyntaxLeaf(() -> val[]; open="[", close="]")
@test render(cl) == "[hi]"
val[] = "bye"
@test render(cl) == "[bye]"

end # @testset "ReactiveSyntax"
end # test_syntax
