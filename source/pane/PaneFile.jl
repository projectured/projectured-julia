# Fragment of `PaneModule`.
#
# Where a newly opened file goes. `OpenFileOperation` is the file-system slice's
# intent — it names a path and nothing about a destination, because that slice
# draws a file tree and does not know what holds it. The pane tree is one
# destination, so this is the pane's half of the seam: the group a file belongs
# in. `evaluate_operation(editor, ::OpenFileOperation)`, which pairs the intent
# with this answer, lives beside the operation in `FileSystemDocument.jl` — a
# pane cannot name a type its own package does not depend on.

"""
    get_pane_file_group(editor) -> PaneGroup or nothing

The group a newly opened file belongs in, in the pane tree that holds the focus
([`find_pane_tree_reference`](@ref)): a group that already holds a file — any
tab whose content [`is_file_document`](@ref) answers `true` for — else a group
every one of whose tabs [`accepts_opened_file`](@ref), focused first. `nothing`
leaves the choice to [`open_pane!`](@ref). A file must not cover the explorer it
was opened from, nor a running conversation.
"""
function get_pane_file_group(editor)
    found = _find_focused_tree_route(editor)
    found === nothing && return nothing
    tree = last(found)
    groups = get_pane_groups(tree)
    for group in groups
        any(tab -> is_file_document(tab.content), group.tabs) && return group
    end
    free = [group for group in groups if _is_free_group(group)]
    isempty(free) && return nothing
    focused = get_pane_focused_group(tree)
    focused in free ? focused : first(free)
end

# Whether a new tab may go in beside every tab of `group`: each content
# `accepts_opened_file`. A group with no tab is free.
_is_free_group(group::PaneGroup) = all(tab -> accepts_opened_file(tab.content), group.tabs)
