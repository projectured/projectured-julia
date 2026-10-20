# Fragment of `SyntaxModule`.
#
# The view of a syntax leaf. A leaf has no child document of its own, so its view
# holds only its content and the state of one view: the caret, a path into the
# fields of the leaf such as `.value{3}`, which the view reads through its content.

"""
    SyntaxLeafView(content::SyntaxLeaf)

A view of the syntax leaf `content`. Its caret is a path of the leaf, such as
`.value{3}` or the whole leaf `∅`, and it ends at the view, so another view of the
same leaf keeps a caret of its own. A viewing step of `SyntaxToText` prints it as
the `TextView` of the text of the leaf.
"""
@document struct SyntaxLeafView <: ContentView
    content::SyntaxLeaf
end

# The view of a leaf that a viewing step prints.
make_content_view(content::SyntaxLeaf) = SyntaxLeafView(content)

# The keys of a leaf, read against the caret of the view.
@gestures SyntaxLeafView begin
    KeyDown(:home; ctrl, alt) => "Select the whole leaf" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" =>
        _toggle_leaf_cursor(doc.content, doc.selection)
end
