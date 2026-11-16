# One syntax leaf in two views at three places of a vertical layout. The first and
# the third place show view A, so they share its caret; the second place shows
# view B, with a caret of its own. The leaf and its text hold no caret.
function make_syntax_leaf_view_document_example()
    font = StyleFont("Ubuntu Mono", 20)
    leaf = SyntaxLeaf(TextString("one leaf, two views", font, color_default);
                      open = TextString("\"", font, color_solarized_gray),
                      close = TextString("\"", font, color_solarized_gray))
    view_a = SyntaxLeafView(leaf)
    view_b = SyntaxLeafView(leaf)
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    # The caret of view B first, so it stays when the focus goes to view A.
    replace_selection!(layout, concat_references(@reference(layout, children[2]), @reference(view_b, value{4})))
    replace_selection!(layout, concat_references(@reference(layout, children[1]), @reference(view_a, value{8})))
    layout
end
