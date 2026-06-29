# Lightweight wrapper that escapes the surrounding projection's type-dispatch
# path so an arbitrary Julia value (the editor's document, projection, …) can
# be embedded in a widget tree without the widget projection trying to render
# it as one of its known node types. Routed to the ObjectToSyntax chain.
struct EditorIntrospection
    value::Any
end

function make_scrolling_document(document; width=nothing, height=nothing)
    size = (width !== nothing && height !== nothing) ? Point2D(width, height) : nothing
    WidgetScrollPane(document; size=size)
end

function make_introspection_document(document, projection; title="content")
    WidgetTabbedPane(Any[
        (title,              document),
        ("editor.document",   EditorIntrospection(document)),
        ("editor.projection", EditorIntrospection(projection)),
    ])
end

# Wrap any example document in a clipboard so the copy/cut/paste flow can operate
# over it. `collection=true` uses a ClipboardCollection (the elements view), else a
# ClipboardSlice (the single-slice view). Pairs with `make_clipboard_projection`.
make_clipboard_document(document; collection=false) =
    collection ? ClipboardCollection(document) : ClipboardSlice(document)

function make_workbench_document(document; title="untitled", filename=title)
    edit_page = WorkbenchPage([
        WorkbenchEditor(document; title=title, filename=filename),
    ])
    info_page = WorkbenchPage([
        WorkbenchConsole(),
        WorkbenchDescriptor(EmptyReferencePath()),
        WorkbenchOperator(),
        WorkbenchSearcher(),
        WorkbenchEvaluator(),
    ])
    control_page = WorkbenchPage([
        WorkbenchAssistant(),
    ])
    WorkbenchWorkbench(WorkbenchPage([]), edit_page, info_page, control_page)
end
