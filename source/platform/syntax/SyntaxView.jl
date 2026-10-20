# Fragment of `SyntaxModule`.
#
# The views of the syntax. A view of a leaf holds its content and the state of one
# view: the caret, a path into the fields of the leaf such as `.value{3}`, which
# the view reads through its content. A view of a node also holds the views of the
# children of its node, at `children`, as its node holds the children, so a path
# such as `.children[2].value{3}` is a path of the view and of its node.

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

"""
    SyntaxNodeView(content::SyntaxNode)

A view of the syntax node `content`. `children` holds the view of each child of the
node, in the order of the children, and follows them by identity
(`make_child_views`). The caret of the view goes into the view of a child, as
`.children[2]` and the caret of that view, or ends at the view, as `∅` or a place
in a delimiter. A viewing step of `SyntaxToText` prints it as the `TextView` of the
text of the node.
"""
@document struct SyntaxNodeView <: ContentView
    content::SyntaxNode
    children::CellVector
end

SyntaxNodeView(content::SyntaxNode) = SyntaxNodeView(content, make_child_views(content, :children))

# The views that a parent view makes for its children, and that a viewing step prints.
make_content_view(content::SyntaxLeaf) = SyntaxLeafView(content)
make_content_view(content::SyntaxNode) = SyntaxNodeView(content)

# The caret of a view as a path of its content, which the key helpers of the
# syntax read; `nothing` when the view has no live caret.
function _get_view_caret(view::ContentView)
    selection = view.selection
    selection === nothing ? nothing : get_content_path(view, selection)
end

# The keys of a leaf, read against the caret of the view.
@gestures SyntaxLeafView begin
    KeyDown(:home; ctrl, alt) => "Select the whole leaf" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" =>
        _toggle_syntax_cursor(doc.content, _get_view_caret(doc))
end

# The keys of a node, read against the caret of the view: a view at the root of a
# stage answers them for the whole tree of its views, as a node does for its tree.
@gestures SyntaxNodeView begin
    KeyDown(:home; ctrl, alt) => "Select the root node" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" =>
        _toggle_syntax_cursor(doc.content, _get_view_caret(doc))
    when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => "Navigate the tree" =>
        _navigate_syntax_tree(doc.content, _get_view_caret(doc), k)
    when(KeyDown(k;), k in (:up, :down, :left, :right)) => "Navigate the tree" =>
        _is_tree_selection(_get_view_caret(doc)) ?
            _navigate_syntax_tree(doc.content, _get_view_caret(doc), k) : nothing
end
