# Fragment of `ApplicationModule` — the first content of the explorer of a window:
# what the host gives, such as the folder of the window, then the work of the
# session, and the tools of the editor in sections. A person changes it from there.

"""
    make_editor_explorer_content(; editor, entries = Any[], mcp_log = false) -> ExplorerSection

The first content of the explorer of a window of `editor`: `entries`, which the
host gives, such as the folder of the window or the projects of a simulator; the
task list and the assistant list of the editor; a section of evaluators with one
evaluator; an empty section of dashboards; a section of what the editor does now,
with its logs, its statistics, the selection and the processes of the system; a
section of the settings; and a section of the help. `mcp_log` adds the log of the
calls of a client to the section of the editor, for a window that serves MCP.

Each document of a session is the one of `editor`, so a Tasks tab and the
explorer show the same list. The host calls it once the editor exists, and makes
it the root section of the editor ([`get_session_explorer_content`](@ref)).

Use it to give a new window its explorer.

# Example

    content_1 = make_editor_explorer_content(; editor = get_evaluation_editor(),
                                             entries = Any[Workspace([WorkspaceFolder("work", pwd())])])

See also `Explorer` and `ExplorerSection`.
"""
function make_editor_explorer_content end

function make_editor_explorer_content(; editor, entries::AbstractVector = Any[], mcp_log::Bool = false)
    logs = Any[get_session_message_log(; editor), get_session_gesture_log(; editor), get_session_fault_log(; editor)]
    mcp_log && push!(logs, get_session_mcp_log(; editor))
    settings = Any[document for document in (find_editor_settings(; editor), find_editor_appearance(; editor))
                   if document !== nothing]
    ExplorerSection("Explorer", Any[
        entries...,
        get_session_task_group_list(; editor),
        get_session_assistant_list(; editor),
        ExplorerSection("Evaluators", Any[EvaluatorToplevel()]),
        ExplorerSection("Dashboards"),
        ExplorerSection("Editor", Any[logs...,
                                      get_session_frame_statistics(; editor), get_session_frame_time_series(; editor),
                                      SelectionInspector(),
                                      SystemProcessTree([getpid()]; title = "System processes")]),
        ExplorerSection("Settings", settings),
        ExplorerSection("Help", Any[DocumentTypeList(), ProjectionList(), AboutPage()])])
end
