function test_syntax_to_text()
@testset "SyntaxToText" begin

s2st = RecursiveProjection(SyntaxToText())
stree = SyntaxLeaf("val"; open="[", close="]")
sst = print_document(s2st, stree).output
@test length(sst.elements) == 3
@test sst.elements[1].content == "["
@test sst.elements[2].content == "val"
@test sst.elements[3].content == "]"
@test sst.elements[1].font == font_ubuntu_monospace_regular_20   # style comes from tree node (plain string = no style)
@test sst.elements[2].font == font_ubuntu_monospace_regular_20   # style comes from tree node

# node flattening
sn = SyntaxNode(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")]; open="(", close=")", sep=", ")
sst2 = print_document(s2st, sn).output
texts = [s.content for s in sst2.elements]
@test join(texts) == "(a, b)"

# value-level incrementality
lv = Cell("X")
sl = SyntaxLeaf(() -> lv[]; open="[", close="]")
sst3 = print_document(s2st, sl).output
@test sst3.elements[2].content == "X"
@test is_cell_up_to_date(getfield(sst3.elements, :elements))  # spans structure still valid
lv[] = "Y"
@test is_cell_up_to_date(getfield(sst3.elements, :elements))  # still valid! only the text cell changed
@test sst3.elements[2].content == "Y"

# structural incrementality
src2 = Cell(2)
sn2 = SyntaxNode(() -> SyntaxDocument[SyntaxLeaf(string(i)) for i in 1:src2[]]; open="<", close=">", sep=",")
sst4 = print_document(s2st, sn2).output
_ = [s.content for s in sst4.elements]  # force eval
@test is_cell_up_to_date(getfield(sst4.elements, :elements))
src2[] = 3
@test !is_cell_up_to_date(getfield(sst4.elements, :elements))  # children changed → spans rebuild

end # @testset "SyntaxToText"

@testset "SyntaxToText flat-position round-trip" begin

# Walk every flat character offset of a hand-built SyntaxNode and verify that
# mapping the corresponding text-domain flat reference back through
# `map_reference_backward` yields a selection whose forward map (`_syntax_to_flat`)
# lands back on the same character. This guarantees that clicking on any
# character of the rendered text resolves to a selection whose forward map
# lands back on the same character. (The delegation refactor removed the
# self-contained `_pos_to_selection` helper; its job now lives inside
# `map_reference_backward`, which reads flat positions as a bare `{k}` ref.)
let
_S2T = SyntaxToTextModule

_pos_to_selection(iomap, k::Int) = map_reference_backward(iomap.projection, iomap,
    ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))

_check_roundtrip = function (label, node, p)
    iomap = print_document(RecursiveProjection(SyntaxToText()), node)
    flat_len = _S2T._subtree_len(node, p, 0)
    @testset "$label" begin
        for k in 0:flat_len
            sel = _pos_to_selection(iomap, k)
            flat_back = _S2T._syntax_to_flat(node, sel, p, 0)
            @test flat_back == k
        end
    end
end

# A two-leaf array with separator and indented children, mirroring the
# `syntax` example.
node = SyntaxNode(
    SyntaxDocument[
        SyntaxLeaf("hello"; open="\"", close="\""),
        SyntaxLeaf("world"; open="\"", close="\""),
    ]; open="[", close="]", sep=", ", indentation=1)
_check_roundtrip("indented array", node, _S2T.SyntaxCompoundToText())

# An inline (non-indented) node: child₁ sep child₂.
inline_node = SyntaxNode(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b"), SyntaxLeaf("c")]; sep=" | ")
_check_roundtrip("inline node", inline_node, _S2T.SyntaxCompoundToText())

# Nested: an outer array whose child is itself an inline pair node.
inner_pair = SyntaxNode(
    SyntaxDocument[SyntaxLeaf("key"; open="\"", close="\""),
                    SyntaxLeaf("value"; open="\"", close="\"")]; sep=": ")
outer = SyntaxNode(SyntaxDocument[inner_pair]; open="{", close="}", sep=", ", indentation=1)
_check_roundtrip("nested key/value", outer, _S2T.SyntaxCompoundToText())
end # let

end # @testset "SyntaxToText flat-position round-trip"

@testset "SyntaxToText collapse/expand marker" begin

# The inline expand/collapse marker is an optional projection-introduced span
# rendered before the open delimiter in both states. Which glyph shows depends
# on `node.collapsed`; an empty configured marker (the default) emits nothing.
let
_S2T = SyntaxToTextModule
mk(s) = TextString(s)

node = SyntaxNode(SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2"), SyntaxLeaf("3")]; open="[", close="]", sep=", ")

p_off = _S2T.SyntaxCompoundToText()
p_on  = _S2T.SyntaxCompoundToText(expanded_marker=mk("▾"), collapsed_marker=mk("▸"))

pipe_off = RecursiveProjection(SyntaxToText())
pipe_on  = RecursiveProjection(SyntaxToText(expanded_marker=mk("▾"), collapsed_marker=mk("▸")))

# Marker off (default): byte-for-byte unchanged, no marker recorded.
iomap_off = print_document(pipe_off, node)
@test join(s.content for s in iomap_off.output.elements) == "[1, 2, 3]"
@test iomap_off.marker_index[] == 0

# Marker on, expanded: leading ▾ as element 1.
node.collapsed = false
iomap_x = print_document(pipe_on, node)
spans_x = [s.content for s in iomap_x.output.elements]
@test spans_x[1] == "▾"
@test join(spans_x) == "▾[1, 2, 3]"
@test iomap_x.marker_index[] == 1

# Marker on, collapsed: the glyph swaps to ▸ and the body folds to a single
# ellipsis between the delimiters — the children are not laid out.
node.collapsed = true
iomap_c = print_document(pipe_on, node)
spans_c = [s.content for s in iomap_c.output.elements]
@test spans_c[1] == "▸"
@test join(spans_c) == "▸[…]"
@test iomap_c.marker_index[] == 1
node.collapsed = false

# Empty node: no marker even when configured (nothing to fold).
empty_node = SyntaxNode(SyntaxDocument[]; open="[", close="]", sep=", ")
iomap_e = print_document(pipe_on, empty_node)
@test join(s.content for s in iomap_e.output.elements) == "[]"
@test iomap_e.marker_index[] == 0

# Offset shift: the marker adds exactly its length to the subtree, the marker
# range maps to a projection-introduced position, and the round-trip identity
# `map_reference_backward ∘ _syntax_to_flat` still holds with the marker on.
@test _S2T._subtree_len(node, p_on, 0) == _S2T._subtree_len(node, p_off, 0) + 1

_pos_to_selection(iomap, k::Int) = map_reference_backward(iomap.projection, iomap,
    ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))

iomap_pon = print_document(pipe_on, node)

sel0 = _pos_to_selection(iomap_pon, 0)
@test sel0.head isa ProjectionReference

# Position 1 (just past the one-char marker) is the open delimiter.
sel1 = _pos_to_selection(iomap_pon, 1)
@test sel1.head isa FieldReference && sel1.head.name == "open"

flat_len = _S2T._subtree_len(node, p_on, 0)
for k in 0:flat_len
    sel = _pos_to_selection(iomap_pon, k)
    @test _S2T._syntax_to_flat(node, sel, p_on, 0) == k
end
end # let

end # @testset "SyntaxToText collapse/expand marker"

@testset "SyntaxToText collapsed body" begin

# A collapsed SyntaxNode renders <marker?><open><ellipsis><close> with its
# children pruned. The flat-position round-trip must still hold in the
# collapsed state, and toggling back must restore the expanded output exactly.
let
_S2T = SyntaxToTextModule
mk(s) = TextString(s)

node = SyntaxNode(SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2"), SyntaxLeaf("3")]; open="[", close="]", sep=", ")
pipe = RecursiveProjection(SyntaxToText())
p    = _S2T.SyntaxCompoundToText()

# Expanded output, captured for the restoration check below.
expanded = join(s.content for s in print_document(pipe, node).output.elements)
@test expanded == "[1, 2, 3]"

# Collapsed (no marker configured): open + ellipsis + close.
node.collapsed = true
collapsed = join(s.content for s in print_document(pipe, node).output.elements)
@test collapsed == "[…]"

# Flat-position round-trip holds while collapsed.
_pos_to_selection(iomap, k::Int) = map_reference_backward(iomap.projection, iomap,
    ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))

iomap_c = print_document(pipe, node)   # node.collapsed = true above
flat_len = _S2T._subtree_len(node, p, 0)
for k in 0:flat_len
    sel = _pos_to_selection(iomap_c, k)
    @test _S2T._syntax_to_flat(node, sel, p, 0) == k
end
# The ellipsis (position after the open delimiter) has no source coordinate.
@test _pos_to_selection(iomap_c, 1).head isa ProjectionReference
# `.children[i]…` input references have no image while collapsed.
@test _S2T._syntax_to_flat(node, (@reference(node, children[1].value{0})), p, 0) == -1

# Toggling back restores the expanded output byte-for-byte.
node.collapsed = false
@test join(s.content for s in print_document(pipe, node).output.elements) == expanded

# Empty node: collapsing adds no ellipsis (nothing to fold).
empty_node = SyntaxNode(SyntaxDocument[]; open="[", close="]", sep=", ")
empty_node.collapsed = true
@test join(s.content for s in print_document(pipe, empty_node).output.elements) == "[]"

# Reactivity: toggling `collapsed` invalidates the output spans cell.
react_node = SyntaxNode(SyntaxDocument[SyntaxLeaf("x")]; open="[", close="]", sep=", ")
out = print_document(pipe, react_node).output
_ = [s.content for s in out.elements]                       # force the spans cell
@test is_cell_up_to_date(getfield(out.elements, :elements))
react_node.collapsed = true
@test !is_cell_up_to_date(getfield(out.elements, :elements))
@test join(s.content for s in out.elements) == "[…]"
end # let

end # @testset "SyntaxToText collapsed body"

@testset "SyntaxToText plain-arrow navigation & Ctrl+Space toggle" begin
let
s2st = RecursiveProjection(SyntaxToText())
# Two leaves under an indented array, mirroring the `syntax` example.
node = SyntaxNode(
    SyntaxDocument[
        SyntaxLeaf("hello"; open="\"", close="\""),
        SyntaxLeaf("world"; open="\"", close="\""),
    ]; open="[", close="]", sep=", ", indentation=1)

# Drive the SyntaxCompoundToText reader with `sel` as the current selection.
read_key(sel, key, mods=Modifiers()) = begin
    clear_selection!(node)
    set_selection!(node, sel)
    io = print_document(s2st, node)
    read_intent(s2st, io, KeyDown(key, mods))
end
op_path(sel, key, mods=Modifiers()) = begin
    op = read_key(sel, key, mods)
    op isa ReplaceSelectionOperation ? op.path : op
end

root   = EmptyReferencePath()
child1 = @reference(node, children[1])            # .children[1]∅
child2 = @reference(node, children[2])            # .children[2]∅

@testset "plain arrows drive the tree once a whole element is selected" begin
    @test is_reference_equal(op_path(root,   :down),  child1)   # root → first child
    @test is_reference_equal(op_path(child1, :right), child2)   # next sibling
    @test is_reference_equal(op_path(child2, :left),  child1)   # previous sibling
    @test is_reference_equal(op_path(child1, :up),    root)     # child → parent
end

@testset "plain arrows match their Alt counterparts in structural mode" begin
    alt = Modifiers(alt=true)
    for (sel, key) in ((root, :down), (child1, :right), (child2, :left), (child1, :up))
        @test is_reference_equal(op_path(sel, key), op_path(sel, key, alt))
    end
end

@testset "edges no-op" begin
    # :up at the root has no parent → the reader declines (nothing).
    @test read_key(root, :up) === nothing
    # :left at the first sibling / :right at the last stay put (same path).
    @test is_reference_equal(op_path(child1, :left),  child1)
    @test is_reference_equal(op_path(child2, :right), child2)
end

@testset "plain arrows with a character cursor are not tree navigation" begin
    # A character cursor inside a leaf must not do tree navigation.
    # :down has no text-domain meaning at console level → declines.
    # :right is handled by the console fallback (read_gesture on output TextBlock)
    # and returns a character-level cursor move, not a tree step.
    cursor = @reference(node, children[1].value{2})
    @test read_key(cursor, :down) === nothing
    right_op = read_key(cursor, :right)
    @test right_op isa ReplaceSelectionOperation
    @test is_reference_equal(right_op.path, (@reference(node, children[1].value{3})))
end

@testset "Ctrl+Space toggles structural ⇄ text" begin
    ctrl = Modifiers(ctrl=true)
    # text → structural: promote a leaf cursor to the whole leaf.
    cursor = @reference(node, children[1].value{2})
    promoted = op_path(cursor, :space, ctrl)
    @test is_reference_equal(strip_reference_types(promoted), strip_reference_types(child1))
    # structural → text: descend to the first leaf's value start.
    descended = op_path(child1, :space, ctrl)
    @test is_reference_equal(strip_reference_types(descended),
                             strip_reference_types(@reference(node, children[1].value{0})))
    # round-trip lands back in the same leaf (at its start — stateless).
    @test is_reference_equal(op_path(promoted, :space, ctrl), descended)
end
end # let
end # @testset "SyntaxToText plain-arrow navigation & Ctrl+Space toggle"

@testset "SyntaxConcatenation" begin

# A concatenation sequences its children and emits nothing of its own: no
# delimiters, no separator, no indent chrome, no fold marker — and so no caret
# that is not one of its children's.
let
_S2T = SyntaxToTextModule
s2st = RecursiveProjection(SyntaxToText())

@testset "renders as its children, end to end" begin
    c = SyntaxConcatenation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")])
    out = print_document(s2st, c).output
    @test [s.content for s in out.elements] == ["a", "b"]   # exactly two spans: no chrome
    @test render(c) == "ab"

    # An empty concatenation renders nothing at all.
    @test isempty(print_document(s2st, SyntaxConcatenation()).output.elements)
end

@testset "a concatenation is a compound, a leaf is not" begin
    c = SyntaxConcatenation(SyntaxDocument[SyntaxLeaf("a")])
    @test c isa SyntaxCompound
    @test !(SyntaxLeaf("a") isa SyntaxCompound)
    # It answers the compound contract with the defaults throughout.
    @test syntax_opening(c) === nothing
    @test syntax_closing(c) === nothing
    @test syntax_separator(c) === nothing
    @test syntax_indentation(c) == 0
    @test syntax_collapsed(c) == false
    @test syntax_collapsible(c) == false     # so it is never given a (dead) fold marker
end

@testset "a marker is never emitted for a concatenation" begin
    # Markers are configured on the projection, so a concatenation would be handed
    # one too if collapsibility were not part of the contract — a glyph that does
    # nothing when clicked.
    p_on = _S2T.SyntaxCompoundToText(expanded_marker=TextString("▾"),
                                     collapsed_marker=TextString("▸"))
    @test _S2T._active_marker(p_on, SyntaxConcatenation(SyntaxDocument[SyntaxLeaf("a")])) === nothing
    @test _S2T._active_marker(p_on, SyntaxNode(SyntaxDocument[SyntaxLeaf("a")])) !== nothing
end

@testset "nested in a node: every caret round-trips" begin
    # The flat round-trip harness, but with a concatenation between the node and
    # its leaves — every character offset must still map back to a selection that
    # forward-maps onto the same character.
    inner = SyntaxConcatenation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")])
    node = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="(", close=")", sep=",")
    p = _S2T.SyntaxCompoundToText()
    iomap = print_document(s2st, node)
    @test join(s.content for s in iomap.output.elements) == "(x,ab)"
    for k in 0:_S2T._subtree_len(node, p, 0)
        sel = map_reference_backward(iomap.projection, iomap,
                  ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))
        @test _S2T._syntax_to_flat(node, sel, p, 0) == k
    end
end

@testset "indentation is widened through a concatenation" begin
    # The parent widens every line-start indent its child reported, reading them
    # off the child's IoMap. A concatenation in between must still report them, or
    # everything beneath it silently stops being re-indented on splice.
    leaf   = SyntaxLeaf("k")
    inner  = SyntaxNode(SyntaxDocument[leaf]; open="[", close="]", indentation=1)
    outer  = SyntaxNode(SyntaxDocument[SyntaxConcatenation(SyntaxDocument[inner])];
                        open="{", close="}", indentation=1)
    through = join(s.content for s in print_document(s2st, outer).output.elements)
    # The same tree with the concatenation removed must render identically —
    # a concatenation contributes no characters of its own.
    direct = SyntaxNode(SyntaxDocument[inner]; open="{", close="}", indentation=1)
    @test through == join(s.content for s in print_document(s2st, direct).output.elements)
    @test occursin("\n    k", through)   # k is indented twice: once per indenting node
end

@testset "tree navigation walks into and out of a concatenation" begin
    # Tree navigation is registered on SyntaxCompound, so a concatenation is an
    # ordinary interior node: it can be selected, entered, and stepped past.
    inner = SyntaxConcatenation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")])
    node  = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="(", close=")", sep=",")

    read_key(sel, key, mods=Modifiers()) = begin
        clear_selection!(node)
        set_selection!(node, sel)
        read_intent(s2st, print_document(s2st, node), KeyDown(key, mods))
    end
    op_path(sel, key, mods=Modifiers()) = begin
        op = read_key(sel, key, mods)
        op isa ReplaceSelectionOperation ? op.path : op
    end

    root   = EmptyReferencePath()
    child1 = @reference(node, children[1])                 # the leaf "x"
    concat = @reference(node, children[2])                 # the concatenation
    inner1 = @reference(node, children[2].children[1])     # the leaf "a" inside it

    @test is_reference_equal(op_path(root,   :down),  child1)   # root → first child
    @test is_reference_equal(op_path(child1, :right), concat)   # step onto the concatenation
    @test is_reference_equal(op_path(concat, :down),  inner1)   # descend INTO it
    @test is_reference_equal(op_path(inner1, :up),    concat)   # and back out
    @test is_reference_equal(op_path(concat, :left),  child1)   # step back off it
end
end # let

end # @testset "SyntaxConcatenation"

@testset "SyntaxSeparation" begin

# A separation is a concatenation that also puts something between the children.
let
_S2T = SyntaxToTextModule
s2st = RecursiveProjection(SyntaxToText())

@testset "joins its children with the separator" begin
    s = SyntaxSeparation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b"), SyntaxLeaf("c")];
                         separator=", ")
    out = print_document(s2st, s).output
    @test join(x.content for x in out.elements) == "a, b, c"
    @test render(s) == "a, b, c"
    # n children, n-1 separators, and nothing else.
    @test length(out.elements) == 5
    @test syntax_separator(s).first === :separator      # its own field name, not `sep`
end

@testset "an absent separator is a concatenation" begin
    # The separator is the whole difference between the two types, so without one
    # they must render identically.
    kids() = SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")]
    bare = SyntaxSeparation(kids())
    @test syntax_separator(bare) === nothing
    @test render(bare) == render(SyntaxConcatenation(kids()))
    @test [x.content for x in print_document(s2st, bare).output.elements] == ["a", "b"]
    # An empty separator string means the same thing as none.
    @test syntax_separator(SyntaxSeparation(kids(); separator="")) === nothing
end

@testset "a cursor maps onto the separator, an edit does not map back to it" begin
    # One `separator` field renders n-1 spans. Forward, `.separator{k}` is placed on
    # the FIRST occurrence. Backward, no span maps to `.separator` at all — no single
    # one of them *is* the separator, and an edit there would change them all.
    s = SyntaxSeparation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b"), SyntaxLeaf("c")];
                         separator=", ")
    iomap = print_document(s2st, s)

    fwd = map_reference_forward(iomap.projection, iomap,
              @reference(s, separator{0}))
    # The forward image is a flat TextRangeReference; resolve it back to the span
    # it lands on to assert it is the first separator (element 2).
    flat = _S2T._text_side_flat(fwd)
    span_idx, _ = _S2T._flat_to_span_char(iomap.output.elements, flat)
    @test span_idx == 2                       # the first separator, right after child 1

    # Backward from inside that first separator: projection-introduced chrome, NOT
    # `.separator{k}` — the same treatment SyntaxNode's `sep` already gets.
    back = map_reference_backward(iomap.projection, iomap, _S2T._text_elem_path(2, 1))
    @test back !== nothing
    @test strip_reference_types(back).head isa ProjectionReference
end

@testset "nested in a node: every caret round-trips" begin
    inner = SyntaxSeparation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")]; separator="|")
    node  = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="(", close=")", sep=",")
    p = _S2T.SyntaxCompoundToText()
    iomap = print_document(s2st, node)
    @test join(x.content for x in iomap.output.elements) == "(x,a|b)"
    for k in 0:_S2T._subtree_len(node, p, 0)
        sel = map_reference_backward(iomap.projection, iomap,
                  ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))
        @test _S2T._syntax_to_flat(node, sel, p, 0) == k
    end
end

@testset "separation inside an indentation-bearing node" begin
    # SQL's `_comma_body` shape: a separated list laid out on indented lines.
    body = SyntaxSeparation(SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2")]; separator=",")
    node = SyntaxNode(SyntaxDocument[body]; open="[", close="]", indentation=1)
    @test occursin("\n  1,2", join(x.content for x in print_document(s2st, node).output.elements))
end

@testset "tree navigation walks into and out of a separation" begin
    inner = SyntaxSeparation(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")]; separator="|")
    node  = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="(", close=")", sep=",")
    op_path(sel, key) = begin
        clear_selection!(node)
        set_selection!(node, sel)
        op = read_intent(s2st, print_document(s2st, node), KeyDown(key, Modifiers()))
        op isa ReplaceSelectionOperation ? op.path : op
    end
    sep_el = @reference(node, children[2])
    inner1 = @reference(node, children[2].children[1])
    @test is_reference_equal(op_path(sep_el, :down), inner1)   # descend into it
    @test is_reference_equal(op_path(inner1, :up),   sep_el)   # and back out
end
end # let

end # @testset "SyntaxSeparation"

@testset "Syntax wrappers" begin

# The four single-child wrappers are compounds like any other: they have a child, they
# lay out their own spans around it, and they are a level of the tree. The only thing
# that distinguishes them is how they address that child — `.content`, not `.children[i]`.
let
_S2T = SyntaxToTextModule
s2st = RecursiveProjection(SyntaxToText())

@testset "a wrapper is a compound with exactly one child" begin
    d = SyntaxDelimitation(SyntaxLeaf("x"); opening_delimiter="(", closing_delimiter=")")
    @test d isa SyntaxWrapper
    @test d isa SyntaxCompound
    @test !(d isa SyntaxSequence)
    @test length(syntax_children(d)) == 1
    @test syntax_opening(d).first === :opening_delimiter   # its own field name
    @test syntax_closing(d).first === :closing_delimiter
end

@testset "each wrapper lays out the one job it owns" begin
    leaf = SyntaxLeaf("x")
    @test render(SyntaxDelimitation(leaf; opening_delimiter="(", closing_delimiter=")")) == "(x)"
    @test render(SyntaxNavigation(leaf)) == "x"          # an anchor, no spans of its own
    @test render(SyntaxCollapsible(leaf)) == "x"
    @test render(SyntaxIndentation(leaf; indentation=1)) == "x"   # chrome is not in `render`

    # Delimiters are independently optional — an opener with no closer is a real thing.
    @test render(SyntaxDelimitation(leaf; opening_delimiter="#")) == "#x"
    @test render(SyntaxDelimitation(leaf; closing_delimiter=";")) == "x;"
    # And an absent delimiter emits NO span, so it offers no caret.
    bare = print_document(s2st, SyntaxDelimitation(leaf)).output
    @test [x.content for x in bare.elements] == ["x"]

    # The indentation wrapper puts its child on its own indented line.
    ind = print_document(s2st, SyntaxIndentation(leaf; indentation=1)).output
    @test occursin("\n  x", join(x.content for x in ind.elements))
end

@testset "only a collapsible wrapper can collapse" begin
    leaf = SyntaxLeaf("x")
    @test syntax_collapsible(SyntaxCollapsible(leaf))
    @test !syntax_collapsible(SyntaxDelimitation(leaf))
    @test !syntax_collapsible(SyntaxIndentation(leaf))
    # A non-collapsible wrapper is never handed a fold marker (it would be a dead glyph).
    p_on = _S2T.SyntaxCompoundToText(expanded_marker=TextString("▾"),
                                     collapsed_marker=TextString("▸"))
    @test _S2T._active_marker(p_on, SyntaxIndentation(leaf)) === nothing
    @test _S2T._active_marker(p_on, SyntaxCollapsible(leaf)) !== nothing
    # Collapsed, the child is replaced by the ellipsis.
    folded = print_document(s2st, SyntaxCollapsible(leaf; collapsed=true)).output
    @test !occursin("x", join(c.content for c in folded.elements))
end

@testset "a caret round-trips through a .content hop" begin
    # The whole point: a wrapper adds a `.content` step to every path beneath it, and
    # every caret must still map back to a selection that forward-maps onto the same
    # character. This is what would break if the mappers still matched `.children[i]`.
    inner = SyntaxDelimitation(SyntaxLeaf("ab"); opening_delimiter="(", closing_delimiter=")")
    node  = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="[", close="]", sep=",")
    p = _S2T.SyntaxCompoundToText()
    iomap = print_document(s2st, node)
    @test join(c.content for c in iomap.output.elements) == "[x,(ab)]"
    for k in 0:_S2T._subtree_len(node, p, 0)
        sel = map_reference_backward(iomap.projection, iomap,
                  ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))
        @test _S2T._syntax_to_flat(node, sel, p, 0) == k
    end
end

@testset "wrappers stack" begin
    text(d) = join(c.content for c in print_document(s2st, d).output.elements)
    kids() = SyntaxDocument[SyntaxLeaf("1"), SyntaxLeaf("2")]

    # A delimited, indented, separated list, stacked out of three wrappers.
    stacked = SyntaxDelimitation(
                  SyntaxIndentation(
                      SyntaxSeparation(kids(); separator=","),
                      indentation = 1);
                  opening_delimiter = "[", closing_delimiter = "]")
    @test text(stacked) == "[\n  1,2\n]"

    # ── The stack is NOT a decomposition of the combined node ────────────────────
    #
    # `SyntaxNode`'s indentation puts EACH CHILD on its own indented line, emitting
    # `sep, newline, indent, child` — separator and line chrome interleaved, by one
    # node. `SyntaxIndentation` has exactly one child and indents THAT ONE THING.
    # Split across two nodes the two spans cannot interleave: whichever wrapper is
    # outer emits its spans outside the other's. So neither stacking order reproduces
    # it, and that is inherent, not a bug.
    #
    # Which is the whole point of keeping the combined type: a per-child indented,
    # separated list IS the combination fitting, and `SyntaxNode` is the right tool
    # for it. The wrappers are for where it does not fit.
    combined = SyntaxNode(kids(); open="[", close="]", sep=",", indentation=1)
    @test text(combined) == "[\n  1,\n  2\n]"
    @test text(stacked) != text(combined)

    # The other stacking order puts the separator on a line of its own — also not it.
    other = SyntaxDelimitation(
                SyntaxSeparation(SyntaxDocument[SyntaxIndentation(SyntaxLeaf("1"); indentation=1),
                                                SyntaxIndentation(SyntaxLeaf("2"); indentation=1)];
                                 separator=",");
                opening_delimiter="[", closing_delimiter="]")
    @test text(other) == "[\n  1\n,\n  2\n]"
end

@testset "tree navigation walks into and out of a wrapper" begin
    # A wrapper IS a level of the tree: selecting a SyntaxDelimitation means "the
    # parenthesised thing, including its parens", which is a different selection from
    # selecting its content.
    inner = SyntaxDelimitation(SyntaxLeaf("a"); opening_delimiter="(", closing_delimiter=")")
    node  = SyntaxNode(SyntaxDocument[SyntaxLeaf("x"), inner]; open="[", close="]", sep=",")
    op_path(sel, key) = begin
        clear_selection!(node)
        set_selection!(node, sel)
        op = read_intent(s2st, print_document(s2st, node), KeyDown(key, Modifiers()))
        op isa ReplaceSelectionOperation ? op.path : op
    end
    wrapper = @reference(node, children[2])            # the delimitation
    content = @reference(node, children[2].content)    # the leaf inside it

    @test is_reference_equal(op_path(wrapper, :down), content)   # descend through .content
    @test is_reference_equal(op_path(content, :up),   wrapper)   # and back out
    @test SyntaxModule._is_tree_selection(content)               # a .content step is a tree step
end
end # let

end # @testset "Syntax wrappers"

end # test_syntax_to_text
