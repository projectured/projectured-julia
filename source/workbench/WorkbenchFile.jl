# ──────────────────────────────────────────────────────────────────────────
# Folded in from WorkbenchFile.jl.
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
