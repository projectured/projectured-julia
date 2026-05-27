function make_workbench_document_example(; root=abspath(joinpath(@__DIR__, "../..")))
    fs_root = make_filesystem_pathname(root)

    nav_page = WorkbenchPage([
        WorkbenchNavigator([fs_root]),
    ])

    text_doc        = make_text_document_example()
    json_doc        = make_json_document_example()
    xml_doc         = make_xml_document_example()
    julia_doc       = make_julia_document_example()
    table_doc       = make_table_document_example()
    lazy_doc        = make_lazy_document_example()
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

    edit_page = WorkbenchPage([
        WorkbenchEditor(book_doc;        title="book",              filename="book"),
        WorkbenchEditor(text_doc;        title="readme.txt",        filename="readme.txt"),
        WorkbenchEditor(json_doc;        title="contact-list.json", filename="contact-list.json"),
        WorkbenchEditor(xml_doc;         title="library.xml",       filename="library.xml"),
        WorkbenchEditor(julia_doc;       title="factorial.jl",      filename="factorial.jl"),
        WorkbenchEditor(table_doc;       title="table.pred",        filename="table.pred"),
        # WorkbenchEditor(collections_doc; title="collections.pred",  filename="collection.pred"),
        WorkbenchEditor(lazy_doc;        title="lazyprimes.pred",   filename="lazyprimes.pred"),
    ])

    descriptor = WorkbenchDescriptor(EmptyReferencePath())

    info_page = WorkbenchPage([
        WorkbenchAssistant(),
        WorkbenchConsole(TextText(
            TextString("Welcome to ProjecturEd!", font_ubuntu_monospace_regular_24, color_default),
        )),
        descriptor,
        WorkbenchOperator(),
        WorkbenchSearcher(),
        WorkbenchEvaluator(),
    ])

    workbench = WorkbenchWorkbench(nav_page, edit_page, info_page)
    setfn!(getfield(descriptor, :content), () -> workbench.selection)
    workbench
end
