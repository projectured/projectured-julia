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

@testset "SyntaxToText collapse/expand marker" begin

# The inline expand/collapse marker is an optional projection-introduced span
# rendered before the open delimiter in both states. Which glyph shows depends
# on `node.collapsed`; an empty configured marker (the default) emits nothing.
let
_S2T = Projectured.SyntaxToTextModule
mk(s) = TextString(s)

node = SyntaxNode("[", "]", ", ",
    SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2"), SyntaxLeaf("3")])

p_off = _S2T.SyntaxNodeToText()
p_on  = _S2T.SyntaxNodeToText(expanded_marker=mk("▾"), collapsed_marker=mk("▸"))

pipe_off = RecursiveProjection(SyntaxToText())
pipe_on  = RecursiveProjection(SyntaxToText(expanded_marker=mk("▾"), collapsed_marker=mk("▸")))

# Marker off (default): byte-for-byte unchanged, no marker recorded.
iomap_off = projection_print(pipe_off, node)
@test join(s.content for s in iomap_off.output) == "[1, 2, 3]"
@test iomap_off.marker_index[] == 0

# Marker on, expanded: leading ▾ as element 1.
node.collapsed = false
iomap_x = projection_print(pipe_on, node)
spans_x = [s.content for s in iomap_x.output]
@test spans_x[1] == "▾"
@test join(spans_x) == "▾[1, 2, 3]"
@test iomap_x.marker_index[] == 1

# Marker on, collapsed: the glyph swaps to ▸ and the body folds to a single
# ellipsis between the delimiters — the children are not laid out.
node.collapsed = true
iomap_c = projection_print(pipe_on, node)
spans_c = [s.content for s in iomap_c.output]
@test spans_c[1] == "▸"
@test join(spans_c) == "▸[…]"
@test iomap_c.marker_index[] == 1
node.collapsed = false

# Empty node: no marker even when configured (nothing to fold).
empty_node = SyntaxNode("[", "]", ", ", SyntaxDocument[])
iomap_e = projection_print(pipe_on, empty_node)
@test join(s.content for s in iomap_e.output) == "[]"
@test iomap_e.marker_index[] == 0

# Offset shift: the marker adds exactly its length to the subtree, the marker
# range maps to a projection-introduced position, and the round-trip identity
# `_pos_to_selection ∘ _syntax_to_flat` still holds with the marker on.
@test _S2T._subtree_len(node, p_on, 0) == _S2T._subtree_len(node, p_off, 0) + 1

sel0 = _S2T._pos_to_selection(node, 0, p_on, 0)
@test sel0.head isa _S2T.ProjectionReference

# Position 1 (just past the one-char marker) is the open delimiter.
sel1 = _S2T._pos_to_selection(node, 1, p_on, 0)
@test sel1.head isa _S2T.FieldReference && sel1.head.name == "open"

flat_len = _S2T._subtree_len(node, p_on, 0)
for k in 0:flat_len
    sel = _S2T._pos_to_selection(node, k, p_on, 0)
    @test _S2T._syntax_to_flat(node, sel, p_on, 0) == k
end
end # let

end # @testset "SyntaxToText collapse/expand marker"

@testset "SyntaxToText collapsed body" begin

# A collapsed SyntaxNode renders <marker?><open><ellipsis><close> with its
# children pruned. The flat-position round-trip must still hold in the
# collapsed state, and toggling back must restore the expanded output exactly.
let
_S2T = Projectured.SyntaxToTextModule
mk(s) = TextString(s)

node = SyntaxNode("[", "]", ", ",
    SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2"), SyntaxLeaf("3")])
pipe = RecursiveProjection(SyntaxToText())
p    = _S2T.SyntaxNodeToText()

# Expanded output, captured for the restoration check below.
expanded = join(s.content for s in projection_print(pipe, node).output)
@test expanded == "[1, 2, 3]"

# Collapsed (no marker configured): open + ellipsis + close.
node.collapsed = true
collapsed = join(s.content for s in projection_print(pipe, node).output)
@test collapsed == "[…]"

# Flat-position round-trip holds while collapsed.
flat_len = _S2T._subtree_len(node, p, 0)
for k in 0:flat_len
    sel = _S2T._pos_to_selection(node, k, p, 0)
    @test _S2T._syntax_to_flat(node, sel, p, 0) == k
end
# The ellipsis (position after the open delimiter) has no source coordinate.
@test _S2T._pos_to_selection(node, 1, p, 0).head isa _S2T.ProjectionReference
# `.children[i]…` input references have no image while collapsed.
@test _S2T._syntax_to_flat(node, (@reference children[1].value{0}), p, 0) == -1

# Toggling back restores the expanded output byte-for-byte.
node.collapsed = false
@test join(s.content for s in projection_print(pipe, node).output) == expanded

# Empty node: collapsing adds no ellipsis (nothing to fold).
empty_node = SyntaxNode("[", "]", ", ", SyntaxDocument[])
empty_node.collapsed = true
@test join(s.content for s in projection_print(pipe, empty_node).output) == "[]"

# Reactivity: toggling `collapsed` invalidates the output spans cell.
react_node = SyntaxNode("[", "]", ", ", SyntaxDocument[SyntaxLeaf("x")])
out = projection_print(pipe, react_node).output
_ = [s.content for s in out]                       # force the spans cell
@test isuptodate(getfield(out.elements, :elements))
react_node.collapsed = true
@test !isuptodate(getfield(out.elements, :elements))
@test join(s.content for s in out) == "[…]"
end # let

end # @testset "SyntaxToText collapsed body"

end # test_syntax_to_text
