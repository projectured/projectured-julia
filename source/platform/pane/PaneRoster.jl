# Fragment of `PaneModule` — the documents that the tabs of a window show, as a
# source of a roster.

"""
    TabDocuments(type)

The documents of `type` that the tabs of a window show, one part for each tab: the
first layer of what a tab shows that is a `type`, from its content inward, such as
the file document that a tab holds in its history. The window is the one that
shows the roster, which its link names. A tab that opens, closes or comes back
with an undo changes the rows; an edit inside a document does not gather the tabs
again.

Use it to give a roster the documents that the tabs of the window show.

# Example

    Roster(TabDocuments(FileDocument); columns = ["name", "folder", "has_edits"])

See also `Roster` and `ItemsWithin`.
"""
struct TabDocuments
    type::Type
end

get_roster_item_type(source::TabDocuments) = source.type

# A source is data, so a file that keeps a roster writes it.
is_pred_constructible(::Type{TabDocuments}) = true

function collect_roster_parts(source::TabDocuments, link)
    tree = _find_link_pane_tree(link)
    tree === nothing && return Any[]
    Any[tab for group in get_pane_groups(tree) for tab in group.tabs]
end

function collect_roster_items(source::TabDocuments, link, tab)
    layer = find_pane_tab_layer(tab, layer -> layer isa source.type)
    layer === nothing ? RosterItem[] : RosterItem[RosterItem(layer)]
end

# The pane tree of the window whose document is `link`: the content of its first
# window, looked through the layers that wrap it, as `show_document!` finds it;
# `nothing` when the window shows no pane tree.
function _find_link_pane_tree(link)
    screen = get_wrapped_document(link)
    content = screen isa ScreenDocument && length(screen.windows) > 0 ? screen.windows[1].content : screen
    tree = get_wrapped_document(content)
    tree isa PaneTree ? tree : nothing
end
