function test_syntax_to_text()
@testset "SyntaxToText" begin

s2st = RecursiveProjection(SyntaxToText())
stree = SyntaxLeaf("[", "]", "val")
sst = projection_print(s2st, stree).output
@test length(sst) == 3
@test sst[1].content == "["
@test sst[2].content == "val"
@test sst[3].content == "]"
@test sst[1].font == font_ubuntu_monospace_regular_24   # style comes from tree node (plain string = no style)
@test sst[2].font == font_ubuntu_monospace_regular_24   # style comes from tree node

# node flattening
sn = SyntaxNode("(", ")", ", ", SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")])
sst2 = projection_print(s2st, sn).output
texts = [s.content for s in sst2]
@test join(texts) == "(a, b)"

# value-level incrementality
lv = Cell("X")
sl = SyntaxLeaf("[", "]", () -> lv[])
sst3 = projection_print(s2st, sl).output
@test sst3[2].content == "X"
@test isuptodate(getfield(sst3.elements, :elements))  # spans structure still valid
lv[] = "Y"
@test isuptodate(getfield(sst3.elements, :elements))  # still valid! only the text cell changed
@test sst3[2].content == "Y"

# structural incrementality
src2 = Cell(2)
sn2 = SyntaxNode("<", ">", ",", () -> SyntaxDocument[SyntaxLeaf(string(i)) for i in 1:src2[]])
sst4 = projection_print(s2st, sn2).output
_ = [s.content for s in sst4]  # force eval
@test isuptodate(getfield(sst4.elements, :elements))
src2[] = 3
@test !isuptodate(getfield(sst4.elements, :elements))  # children changed → spans rebuild

end # @testset "SyntaxToText"
end # test_syntax_to_text
