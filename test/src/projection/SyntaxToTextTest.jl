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

@testset "SyntaxToText flat-position round-trip" begin

# Walk every flat character offset of a hand-built SyntaxNode and verify
# that _pos_to_selection ∘ _syntax_to_flat = identity. This guarantees that
# clicking on any character of the rendered text resolves to a selection
# whose forward map lands back on the same character.
let
_S2T = Projectured.SyntaxToTextModule

_check_roundtrip = function (label, node, p)
    flat_len = _S2T._subtree_len(node, p, 0)
    @testset "$label" begin
        for k in 0:flat_len
            sel = _S2T._pos_to_selection(node, k, p, 0)
            flat_back = _S2T._syntax_to_flat(node, sel, p, 0)
            @test flat_back == k
        end
    end
end

# A two-leaf array with separator and indented children, mirroring the
# `syntax` example.
node = SyntaxNode("[", "]", ", ",
    SyntaxDocument[
        SyntaxLeaf("\"", "\"", "hello"),
        SyntaxLeaf("\"", "\"", "world"),
    ]; indentation=1)
_check_roundtrip("indented array", node, _S2T.SyntaxNodeToText())

# An inline (non-indented) node: child₁ sep child₂.
inline_node = SyntaxNode("", "", " | ",
    SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b"), SyntaxLeaf("c")])
_check_roundtrip("inline node", inline_node, _S2T.SyntaxNodeToText())

# Nested: an outer array whose child is itself an inline pair node.
inner_pair = SyntaxNode("", "", ": ",
    SyntaxDocument[SyntaxLeaf("\"", "\"", "key"),
                    SyntaxLeaf("\"", "\"", "value")])
outer = SyntaxNode("{", "}", ", ", SyntaxDocument[inner_pair]; indentation=1)
_check_roundtrip("nested key/value", outer, _S2T.SyntaxNodeToText())
end # let

end # @testset "SyntaxToText flat-position round-trip"

end # test_syntax_to_text
