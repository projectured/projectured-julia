struct Example
    name::String
    make_document
    make_projection
    document
    projection
    Example(name, make_document, make_projection) =
        new(name, make_document, make_projection, make_document(), make_projection())
end

const json_example           = Example("json",           make_json_document_example,           make_json_projection_example)
const json_sorted_example    = Example("json_sorted",    make_json_document_example,           make_json_sorted_projection_example)
const json_null_example      = Example("json_null",      make_json_null_document_example,      make_json_null_projection_example)
const json_string_example    = Example("json_string",    make_json_string_document_example,    make_json_string_projection_example)
const xml_example            = Example("xml",            make_xml_document_example,            make_xml_projection_example)
const mixed_example          = Example("mixed",          make_mixed_document_example,          make_mixed_projection_example)
const syntax_example         = Example("syntax",         make_syntax_document_example,         make_syntax_projection_example)
const text_example           = Example("text",           make_text_document_example,           make_text_projection_example)
const object_example         = Example("object",         make_object_document_example,         make_object_projection_example)
const line_numbering_example = Example("line_numbering", make_line_numbering_document_example, make_line_numbering_projection_example)
const word_wrapping_example  = Example("word_wrapping",  make_word_wrapping_document_example,  make_word_wrapping_projection_example)
const widget_example         = Example("widget",         make_widget_document_example,         make_widget_projection_example)
const widget_tabbed_pane_example = Example("widget_tabbed_pane", make_widget_tabbed_pane_document_example, make_widget_projection_example)
const book_example           = Example("book",           make_book_document_example,           make_book_projection_example)
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
const sorting_example        = Example("sorting",        make_collection_document_example,     make_sorting_projection_example)
const focusing_example       = Example("focusing",       make_focusing_document_example,       make_focusing_projection_example)
const table_example          = Example("table",          make_table_document_example,          make_table_projection_example)
const math_table_example     = Example("math_table",     make_math_table_document_example,     make_math_table_projection_example)
const workbench_example      = Example("workbench",      make_workbench_document_example,      make_workbench_projection_example)
const lazy_example           = Example("lazy",           make_lazy_document_example,           make_lazy_projection_example)
const lazy_bidirectional_example = Example("lazy_bidirectional", make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example)
const math_example           = Example("math",           make_math_document_example,           make_math_projection_example)
const julia_example          = Example("julia",          make_julia_document_example,          make_julia_projection_example)
const graphics_image_example = Example("graphics_image", make_json_document_example,           make_graphics_image_projection_example)

const examples = [
    json_example, json_sorted_example, json_null_example, json_string_example,
    xml_example, mixed_example, syntax_example, text_example,
    object_example, line_numbering_example, word_wrapping_example,
    widget_example, widget_tabbed_pane_example, book_example, filesystem_example,
    collection_example, reversing_example, filtering_example, sorting_example, focusing_example, table_example, math_table_example, workbench_example,
    math_example,
    julia_example,
    graphics_image_example,
]

function run_example(example::Example; width=2400, height=1600,
                     caching=false, scrolling=false, workbench=false, reset=false)
    document = reset ? example.make_document() : example.document
    projection = reset ? example.make_projection() : example.projection
    if workbench
        document = make_workbench_document(document; title=example.name)
        projection = make_workbench_projection()
    elseif scrolling
        document = make_scrolling_document(document; width=width, height=height)
        projection = make_scrolling_projection(projection)
    end
    if caching
        projection = make_graphics_caching(projection)
    end
    application(SdlBackend(), projection, document,
                title = example.name,
                width = width, height = height)
end

function run_example(name="json"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    run_example(examples[idx]; kwargs...)
end

function print_example(example::Example)
    iomap = projection_print(example.projection, example.document)
    output = iomap.output
    println(print_object(output isa Cell ? output[] : output; open_delimiter="{", close_delimiter="}"))
end

function print_example(name="json")
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    print_example(examples[idx])
end

function write_image_example(example::Example, filename;
                              width=1200, height=800, kwargs...)
    write_image(example.document, example.projection, filename;
                width=width, height=height, kwargs...)
end

function write_image_example(name="json", filename=tempname()*".bmp"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_image_example(examples[idx], filename; kwargs...)
end

