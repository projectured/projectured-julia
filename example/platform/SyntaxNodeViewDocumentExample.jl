# One syntax node in two views at three places of a vertical layout. The first and
# the third place show view A, which is folded; the second place shows view B,
# which is open and has its caret in the second child. The node holds no caret
# and no fold.
function make_syntax_node_view_document_example()
    font = StyleFont("Ubuntu Mono", 20)
    text(s) = TextString(s, font, color_default)
    node = SyntaxNode([SyntaxLeaf(text("one node")), SyntaxLeaf(text("two views")),
                       SyntaxLeaf(text("a fold of its own"))];
                      open = "[\n", close = "\n]", sep = ",\n", indentation = 1)
    view_a = SyntaxNodeView(node)
    view_b = SyntaxNodeView(node)
    view_a.collapsed = true
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    replace_selection!(layout, concat_references(@reference(layout, children[2]),
                                                 @reference(view_b, children[2].value{3})))
    layout
end
