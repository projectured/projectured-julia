# Fragment of `WorkbenchModule`.
#
# File keybindings for a `WorkbenchEditor` tab: **Ctrl+S** saves the tab's
# `content` to its `filename`, **Ctrl+O** reloads it. The on-disk format is chosen
# by the file extension (see `FileFormatModule`): binary for `.pdoc`, natural
# text for `.json`/`.xml`/`.sql`/`.jl`.
#
# The gestures are a reified `@gestures WorkbenchEditor` table. They fire because
# `WorkbenchEditorToWidgetScrollPane.read_intent` delegates a raw
# `KeyDown`/`KeyPress` to `read_gesture` of its `WorkbenchEditor` input before the
# event descends into the tab's content (see `WorkbenchToWidget.jl`). Each gesture
# emits a **self-contained** operation carrying the `WorkbenchEditor`, so it bubbles
# up through every wrapping reader (page → workbench → window → screen) unchanged
# and is applied by `evaluate_operation`.
"""
    SaveWorkbenchEditorOperation(editor)

Write the tab's current `content` to its `filename` (format by extension). A pure
side effect; the document is not mutated.
"""
struct SaveWorkbenchEditorOperation <: Operation
    editor::WorkbenchEditor
end

function evaluate_operation(editor, op::SaveWorkbenchEditorOperation)
    tab = op.editor
    write_document_file(tab.content, tab.filename)
end

"""
    ReloadWorkbenchEditorOperation(editor)

Re-read the tab's `filename` from disk and swap it into `content` (a reactive
write, so the projection re-renders). The tab's selection is cleared since the
old selection pointed into the replaced content. A non-existent file re-seeds the
extension's insertion placeholder.
"""
struct ReloadWorkbenchEditorOperation <: Operation
    editor::WorkbenchEditor
end

function evaluate_operation(editor, op::ReloadWorkbenchEditorOperation)
    tab = op.editor
    tab.content = read_document_file(tab.filename)
    tab.selection = nothing
end

# Both commands need a filename; decline (no binding fires) when the tab has none
# — a "Save As" path picker for unnamed tabs is future work.
_save(doc::WorkbenchEditor)   = isempty(doc.filename) ? nothing : SaveWorkbenchEditorOperation(doc)
_reload(doc::WorkbenchEditor) = isempty(doc.filename) ? nothing : ReloadWorkbenchEditorOperation(doc)

@gestures WorkbenchEditor begin
    KeyDown(:s; ctrl) => "Save file to disk"     => _save(doc)
    KeyDown(:o; ctrl) => "Reload file from disk" => _reload(doc)
end

# ── Opening a file ───────────────────────────────────────────────────────────

"""
    make_workbench_file_editor(path) -> WorkbenchEditor

A file tab for the file at `path`: the document read in the format that the
extension names, the base name as the title, and the absolute path as the file
name. A path that does not exist opens as the empty seed of its extension, and
`Ctrl+S` creates the file.
"""
function make_workbench_file_editor(path::AbstractString)
    filename = abspath(path)
    WorkbenchEditor(read_document_file(filename);
                    title = basename(filename), filename = filename)
end

"""
    OpenWorkspaceFileOperation(path)

Open the file at `path` in a new tab of the window. In a workbench, the tab goes
to the editing page. In a pane tree, the tab goes to a new pane of the group
that `open_pane!` chooses. The file is read when the editor evaluates the
operation, not when a gesture makes it.
"""
struct OpenWorkspaceFileOperation <: Operation
    path::String
end

OpenWorkspaceFileOperation(path::AbstractString) = OpenWorkspaceFileOperation(String(path))

function evaluate_operation(editor, op::OpenWorkspaceFileOperation)
    tab = make_workbench_file_editor(op.path)
    window = _get_window_content(editor)
    if window isa PaneTree
        open_pane!(editor, tab; title = tab.title, group = _find_file_group(window))
    else
        workbench = _find_workbench(window)
        workbench === nothing &&
            error("OpenWorkspaceFileOperation: the window holds no workbench and no pane tree")
        evaluate_operation(editor, WorkbenchOpenDocumentOperation(workbench.editing_page, tab))
    end
    nothing
end

# What the first window of the editor shows. A caller without a screen, a test
# for example, holds the window's document itself.
function _get_window_content(editor)
    document = getfield(editor, :document)
    hasproperty(document, :windows) || return document
    windows = document.windows
    isempty(windows) ? document : first(windows).content
end

# The group a file opens in: the group that holds a file already, else a group
# that holds neither the navigator nor the assistant, focused first. `nothing`
# leaves the choice to `open_pane!`. A file must not cover the navigator it was
# opened from, nor the conversation.
function _find_file_group(tree::PaneTree)
    groups = get_pane_groups(tree)
    holds(group, kind) = any(tab -> tab.content isa kind, group.tabs)
    for group in groups
        holds(group, WorkbenchEditor) && return group
    end
    free = [group for group in groups
            if !holds(group, WorkbenchNavigator) && !holds(group, Assistant)]
    isempty(free) && return nothing
    focused = get_pane_focused_group(tree)
    focused in free ? focused : first(free)
end

function _find_workbench(document)
    document isa WorkbenchWorkbench && return document
    found = search_documents(document, node -> node isa WorkbenchWorkbench)
    isempty(found) ? nothing : first(found)
end

# Each of the three carries its own subject, a tab or a path, and names no
# reference. So every reader between the gesture and the editor passes it up
# unchanged, in a workbench and in a pane tree alike.
OperationModule.operation_travels_unchanged(::Union{
    SaveWorkbenchEditorOperation, ReloadWorkbenchEditorOperation,
    OpenWorkspaceFileOperation}) = true
