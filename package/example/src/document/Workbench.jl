function make_workbench_document_example(; root=abspath(joinpath(@__DIR__, "../..")))
    workspace = Workspace([
        WorkspaceFolder(basename(root), root),
    ])

    nav_page = WorkbenchPage([
        WorkbenchNavigator(workspace),
    ])

    text_doc        = make_text_document_example()
    json_doc        = make_json_document_example()
    xml_doc         = make_xml_document_example()
    julia_doc       = make_julia_document_example()
    table_doc       = make_table_document_example()
    lazy_doc        = make_lazy_bidirectional_document_example()
    book_doc        = make_book_document_example()
    # collection_doc  = make_collection_document_example()
    # reversing_doc   = make_collection_document_example()
    # filtering_doc   = make_collection_document_example()
    # sorting_doc     = make_collection_document_example()
    # collections_doc = JsonObject(
    #     "original"  => collection_doc,
    #     "reversing" => reversing_doc,
    #     "filtering" => filtering_doc,
    #     "sorting"   => sorting_doc,
    # )

    # Two introspection pages: one for the editor's document, one for the
    # editor's projection. Bound lazily below — at this point the workbench
    # (which IS the editor's document) hasn't been constructed yet.
    editor_document_view   = WorkbenchEditor(EditorIntrospection(nothing);
                                             title="editor.document",   filename="editor.document")
    editor_projection_view = WorkbenchEditor(EditorIntrospection(make_workbench_projection_example());
                                             title="editor.projection", filename="editor.projection")

    edit_page = WorkbenchPage([
        WorkbenchEditor(book_doc;        title="book",              filename="book"),
        WorkbenchEditor(text_doc;        title="readme.txt",        filename="readme.txt"),
        WorkbenchEditor(json_doc;        title="contact-list.json", filename="contact-list.json"),
        WorkbenchEditor(xml_doc;         title="library.xml",       filename="library.xml"),
        WorkbenchEditor(julia_doc;       title="factorial.jl",      filename="factorial.jl"),
        WorkbenchEditor(table_doc;       title="table.pred",        filename="table.pred"),
        # WorkbenchEditor(collections_doc; title="collections.pred",  filename="collection.pred"),
        # WorkbenchEditor(lazy_doc;        title="lazyprimes.pred",   filename="lazyprimes.pred"),
        # editor_document_view,
        # editor_projection_view,
    ])

    descriptor = WorkbenchDescriptor(EmptyReferencePath())

    assistant = WorkbenchAssistant()
    # Place a zero-width cursor inside the input so the first KeyPress lands
    # there even before the user clicks. Once the input renders, the existing
    # mouse-click chain keeps focus in sync.
    assistant.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))

    info_page = WorkbenchPage([
        WorkbenchConsole(TextText(
            TextString("Welcome to ProjecturEd!", font_ubuntu_monospace_regular_24, color_default),
        )),
        descriptor,
        WorkbenchOperator(),
        WorkbenchSearcher(),
        WorkbenchEvaluator(),
    ])

    control_page = WorkbenchPage([
        assistant,
    ])

    workbench = WorkbenchWorkbench(nav_page, edit_page, info_page, control_page)
    setfn!(getfield(descriptor, :content), () -> workbench.selection)
    # Late-bind: the editor's `document` field is the workbench itself.
    setfn!(editor_document_view, () -> EditorIntrospection(workbench))
    workbench
end
