# Fragment of `ShellModule` — Go to file: the search of a file of the folders of
# the Explorer by its name.
#
# The list of the files belongs to the editor, and the filesystem slice reads it
# and makes the search. The shell gives it the folders of the Explorer, because
# the filesystem slice does not depend on the explorer slice, and it opens the
# search in the context menu window at the top of the window, as the command
# palette opens.

"""
    open_file_search!(; editor = get_evaluation_editor()) -> Nothing

Open the search of a file by its name, as Ctrl+P does: a list at the top of the
window of the files below the folders of the Explorer, which the letters of a
query narrow. Return opens the chosen file in a tab, as the Explorer opens it. The
folders are read again on a task, and the list shows the files of the last read
until that read ends.
"""
function open_file_search!(; editor = get_evaluation_editor())
    run_on_editor_task!(() -> _open_file_search!(editor), editor; description = "open_file_search!")
    nothing
end

function _open_file_search!(editor)
    list = get_session_workspace_file_list(; editor)
    read_workspace_files_again!(list, _collect_explorer_folders(editor))
    search = make_workspace_file_search(list; open_files = collect_open_file_paths(; editor))
    _post_shell_content_operation!(editor,
                                   make_choice_list_operation("Go to file", search;
                                                              placement = make_shell_top_placement),
                                   "Go to file")
    nothing
end

# The folders of the workspaces that the Explorer of the window holds, in the order
# of its entries, the entries of its sections too.
function _collect_explorer_folders(editor)
    folders = String[]
    _collect_entry_folders!(folders, get_session_explorer_content(; editor))
    unique!(folders)
end

_collect_entry_folders!(folders, entry) = folders
_collect_entry_folders!(folders, section::ExplorerSection) =
    (foreach(entry -> _collect_entry_folders!(folders, entry), section.entries); folders)
_collect_entry_folders!(folders, workspace::Workspace) =
    (append!(folders, String[String(folder.pathname) for folder in workspace.folders]); folders)
_collect_entry_folders!(folders, explorer::WorkspaceExplorer) =
    _collect_entry_folders!(folders, explorer.workspace)

# The folder where the Open dialog starts: the folder of the file of the focused
# tab, else the first folder of the Explorer, else the current folder.
function _find_open_dialog_folder(editor)
    tree_reference = find_pane_tree_reference(; editor)
    if tree_reference !== nothing
        tree = evaluate_reference(editor.document, tree_reference)
        focus = get_pane_focus(tree)
        if focus !== nothing && last(focus) > 0
            group, index = focus
            path = find_shown_file_path(group.tabs[index].content)
            path === nothing || return dirname(path)
        end
    end
    folders = _collect_explorer_folders(editor)
    isempty(folders) ? pwd() : first(folders)
end
