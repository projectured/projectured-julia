# Fragment of `ApplicationModule` — the first content of the explorer of a window:
# what the host gives, such as the folder of the window, then the work of the
# session, and the tools of the editor in sections. A person changes it from there.

"""
    make_editor_explorer_content(; editor, entries = Any[], mcp_log = false) -> ExplorerSection

The first content of the explorer of a window of `editor`: `entries`, which the
host gives, such as the folder of the window or the projects of a simulator; the
open files, the task list and the assistant list of the editor; the session
document of each kind for which `is_session_explorer_entry_type` answers `true`,
in the order of the names of their types; a section of evaluators with one
evaluator; an empty section of dashboards; a section of what the editor does now,
with its logs, its statistics, the selection and the processes of the system; a
section of the settings; and a section of the help. `mcp_log` adds the log of the
calls of a client to the section of the editor, for a window that serves MCP.

Each document of a session is the one of `editor`, so a Tasks tab and the
explorer show the same list. A list of the session that `entries` holds already,
such as the task list that a host puts after its projects, is not added again. The host calls it once the editor exists, and makes
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
    lists = Any[get_session_open_file_list(; editor), get_session_task_group_list(; editor),
                get_session_assistant_list(; editor),
                (get_session_document!(() -> run_with_evaluation_editor(() -> Base.invokelatest(type), editor),
                                       editor, type)
                 for type in _collect_session_explorer_entry_types())...]
    ExplorerSection("Explorer", Any[
        entries...,
        (list for list in lists if !any(entry -> entry === list, entries))...,
        ExplorerSection("Evaluators", Any[EvaluatorToplevel()]),
        ExplorerSection("Dashboards"),
        ExplorerSection("Editor", Any[logs...,
                                      get_session_frame_statistics(; editor), get_session_frame_time_series(; editor),
                                      get_session_background_work_log(; editor),
                                      SelectionInspector(),
                                      SystemProcessTree([getpid()]; title = "System processes")]),
        ExplorerSection("Settings", settings),
        ExplorerSection("Help", Any[DocumentTypeList(), ProjectionList(), AboutPage()])])
end

# The kinds whose session document the first content holds: each type with a
# method of `is_session_explorer_entry_type` that answers `true`, in the order of
# their names. The method table is the list, so a package that loads adds its kind,
# and the call reads the newest methods, as the table does.
function _collect_session_explorer_entry_types()
    types = Type[]
    for method in methods(is_session_explorer_entry_type)
        argument = Base.unwrap_unionall(method.sig).parameters[2]
        (argument isa DataType && argument <: Type && length(argument.parameters) == 1) || continue
        type = argument.parameters[1]
        type isa Type && Base.invokelatest(is_session_explorer_entry_type, type) && push!(types, type)
    end
    sort!(unique!(types); by = type -> String(nameof(type)))
end

# The first content of the explorer of the window of `editor`: the entries that
# the window brought, such as its folder, then the work of the session and the
# tools of the editor.
function _fill_explorer_content!(editor)
    content = get_session_explorer_content(; editor)
    filled = make_editor_explorer_content(; editor, entries = Any[entry for entry in content.entries])
    content.entries = filled.entries
    nothing
end

# The content that the file `path` keeps, in the place of the first content, when
# the file reads; the first content stays when there is no file or it does not
# read.
function _restore_explorer_content!(editor, path::AbstractString)
    loaded = load_explorer_content(path; editor)
    loaded === nothing && return nothing
    content = get_session_explorer_content(; editor)
    content.title = loaded.title
    content.entries = loaded.entries
    nothing
end
