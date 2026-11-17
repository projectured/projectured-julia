# Fragment of `SyntaxModule`.
#
# The views of the syntax. A view of a leaf holds its content and the state of one
# view: the caret, a path into the fields of the leaf such as `.value{3}`, which
# the view reads through its content. A view of a node also holds the views of the
# children of its node, at `children`, as its node holds the children, so a path
# such as `.children[2].value{3}` is a path of the view and of its node.

"""
    SyntaxLeafView(viewed::SyntaxLeaf)

A view of the syntax leaf `viewed`. Its caret is a path of the leaf, such as
`.value{3}` or the whole leaf `∅`, and it ends at the view, so another view of the
same leaf keeps a caret of its own. A viewing step of `SyntaxToText` prints it as
the `TextView` of the text of the leaf.
"""
@document struct SyntaxLeafView <: ContentView
    viewed::SyntaxLeaf
end

"""
    SyntaxNodeView(viewed::SyntaxNode)

A view of the syntax node `viewed`. `children` holds the view of the list of the
children of the node (`CellVectorView`), which gives the view of each child at the
index of the child. `collapsed` is the fold of this view: a closed view shows the
first line of its node and the placeholder of its fold, and another view of the
same node keeps a fold of its own. The caret of the view goes into the view of a
child, as `.children[2]` and the caret of that view, or ends at the view, as `∅` or
a place in a delimiter. A viewing step of `SyntaxToText` prints it as the
`TextView` of the text of the node, whose closed folds are the folds of the views
that are closed.
"""
@document struct SyntaxNodeView <: ContentView
    viewed::SyntaxNode
    children::CellVectorView
    collapsed::Bool = false
end

SyntaxNodeView(content::SyntaxNode) =
    SyntaxNodeView(content, CellVectorView(Cell(Computation(() -> content.children))))

# The views that a parent view makes for its children, and that a viewing step prints.
make_content_view(content::SyntaxLeaf) = SyntaxLeafView(content)
make_content_view(content::SyntaxNode) = SyntaxNodeView(content)

# The view of a node that a viewing step gives over the views of its children, as
# the step of a JSON array gives over the steps of its elements.
make_content_view(content::SyntaxNode, children) =
    SyntaxNodeView(content, CellVectorView(Cell(Computation(() -> content.children)), children))

# The fold of that view is the fold of the view that the step printed.
function map_view_state!(output::SyntaxNodeView, view::ContentView, iomap)
    hasproperty(view, :collapsed) &&
        set_cell_computation!(getfield(output, :collapsed), () -> view.collapsed)
    output
end

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
    KeyDown(:a; ctrl) => "Select all" => ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" =>
        _toggle_syntax_cursor(doc.viewed, _get_view_caret(doc))
end

# The keys of a node, read against the caret of the view. A view answers them for
# the tree of views below it, as a node does for its tree; a view deeper on the
# caret reads a key before it.
@gestures SyntaxNodeView begin
    KeyDown(:home; ctrl, alt) => "Select the root node" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:a; ctrl) => "Select all" => ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" =>
        _toggle_syntax_cursor(doc.viewed, _get_view_caret(doc))
    when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => "Navigate the tree" =>
        _navigate_syntax_tree(doc.viewed, _get_view_caret(doc), k)
    when(KeyDown(k;), k in (:up, :down, :left, :right)) => "Navigate the tree" =>
        _navigate_selected_syntax_node(doc.viewed, _get_view_caret(doc), k)
end

# The closed folds of the text of a node view: the fold that the print of each node
# made, for each view of a node that is closed. The walk goes only through the views
# that the text shows, so it stops at a closed view and asks for no print inside it.
function map_view_state!(output::TextView, view::SyntaxNodeView, iomap::SyntaxCompoundToTextIoMap)
    set_cell_computation!(getfield(output, :closed_folds), () -> _find_closed_folds(view, iomap))
    output
end

function _find_closed_folds(view::SyntaxNodeView, iomap::SyntaxCompoundToTextIoMap)
    if view.collapsed
        fold = iomap.fold
        return fold === nothing ? Any[] : Any[fold]
    end
    folds = Any[]
    for (child_view, child_iomap) in _zip_child_views(view, iomap)
        append!(folds, _find_closed_folds(child_view, child_iomap))
    end
    folds
end

# The views of the children of a node view, each with the content IO map of the
# print of its child, for the children that are nodes with a view.
function _zip_child_views(view::SyntaxNodeView, iomap::SyntaxCompoundToTextIoMap)
    pairs = Tuple{SyntaxNodeView, SyntaxCompoundToTextIoMap}[]
    child_views = view.children
    child_iomaps = iomap.child_iomaps
    for i in 1:min(length(child_views), length(child_iomaps))
        child_view = child_views[i]
        child_iomap = get_content_iomap(child_iomaps[i])
        (child_view isa SyntaxNodeView && child_iomap isa SyntaxCompoundToTextIoMap) &&
            push!(pairs, (child_view, child_iomap))
    end
    pairs
end

# A toggle of a fold of the text of a node view is a toggle of the view of the node
# whose print made that fold, at the path of that view.
function read_view_operation(view::SyntaxNodeView, iomap::SyntaxCompoundToTextIoMap,
                             operation::ToggleCollapseOperation)
    operation.target isa TextFold || return nothing
    path = _find_fold_path(view, iomap, operation.target)
    path === nothing ? nothing : ToggleFoldOperation(path)
end

# The path of the view, from `view`, of the node whose print made `fold`, or
# `nothing`.
function _find_fold_path(view::SyntaxNodeView, iomap::SyntaxCompoundToTextIoMap, fold)
    iomap.fold === fold && return EmptyReference()
    for (i, child_view) in enumerate(view.children)
        child_iomaps = iomap.child_iomaps
        (child_view isa SyntaxNodeView && i <= length(child_iomaps)) || continue
        child_iomap = get_content_iomap(child_iomaps[i])
        child_iomap isa SyntaxCompoundToTextIoMap || continue
        tail = _find_fold_path(child_view, child_iomap, fold)
        tail === nothing && continue
        return ConcreteReference(FieldReferenceStep("children"),
                                 ConcreteReference(RangeReferenceStep(i - 1, i), tail))
    end
    nothing
end
