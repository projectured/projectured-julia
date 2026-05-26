function make_scrolling_document(document; width=nothing, height=nothing)
    size = (width !== nothing && height !== nothing) ? Point2D(width, height) : nothing
    WidgetScrollPane(document; size=size)
end

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
        WorkbenchAssistant(),
    ])
    WorkbenchWorkbench(WorkbenchPage([]), edit_page, info_page)
end
