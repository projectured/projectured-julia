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

The group a newly opened file belongs in: a group that already holds a file —
any tab whose content [`is_file_document`](@ref) answers `true` for — else a
group every one of whose tabs [`accepts_opened_file`](@ref), focused first.
`nothing` leaves the choice to [`open_pane!`](@ref). A file must not cover the
explorer it was opened from, nor a running conversation.
"""
function get_pane_file_group(editor)
    window = _get_window_content(editor)
    window isa PaneTree || return nothing
    groups = get_pane_groups(window)
    for group in groups
        any(tab -> is_file_document(tab.content), group.tabs) && return group
    end
    free = [group for group in groups
            if all(tab -> accepts_opened_file(tab.content), group.tabs)]
    isempty(free) && return nothing
    focused = get_pane_focused_group(window)
    focused in free ? focused : first(free)
end

# What the first window of the editor shows. A caller without a screen, a test
# for example, holds the window's document itself.
function _get_window_content(editor)
    document = getfield(editor, :document)
    hasproperty(document, :windows) || return document
    windows = document.windows
    isempty(windows) ? document : first(windows).content
end
