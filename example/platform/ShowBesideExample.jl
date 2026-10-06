"""
    show_beside!(editor, document, title; side = :right, share = 0.6) -> ReferencedDocument

Opens `document` in a pane beside the evaluator, and gives the focus back to the
evaluator, so the next form can be typed. The first document opens on the `side`
of the evaluator that is named (`:right`, `:left`, `:above` or `:below`) and takes
the `share` of the width or of the height; each later one opens as a tab in the
group of the one before it, so it has the same place.

# Example

    show_beside!(editor, DataFrameView(df), "Products"; side = :above)
"""
function show_beside!(editor, document, title::AbstractString; side::Symbol = :right,
                      share::Real = 0.6)
    shown = filter(t -> find_pane(t; editor) !== nothing,
                   get!(() -> String[], _BESIDE_TITLES, editor.tools))
    pane = if isempty(shown)
        opened = open_pane!(document; title = title,
                            target = find_pane("Evaluator"; editor), side = side, editor)
        _give_share!(editor, title, share)
        opened
    else
        open_pane!(document; title = title, target = find_pane(shown[end]; editor), editor)
    end
    _BESIDE_TITLES[editor.tools] = push!(shown, title)
    # The new split moved the evaluator, so it is found again by its title.
    evaluator = find_pane("Evaluator"; editor)
    evaluator === nothing || focus_pane!(evaluator; editor)
    pane
end

# Gives the group of the tab `title` the share `share` of the split that holds it,
# and the other group the rest.
function _give_share!(editor, title::AbstractString, share::Real)
    tree = get_window_tree(; editor)
    group = only(g for g in get_pane_groups(tree)
                 if any(tab -> get_pane_tab_title_string(tab) == title, g.tabs))
    split, index = get_pane_parent(tree, group)
    split isa PaneSplit && length(split.elements) == 2 || return nothing
    split.weights = index == 2 ? [1 - share, share] : [share, 1 - share]
    nothing
end

# The titles of the documents that `show_beside!` opened, for each editor, in the
# order that they were opened. The table is weak, so an editor that is gone takes
# its list with it.
const _BESIDE_TITLES = WeakKeyDict{Any,Vector{String}}()
