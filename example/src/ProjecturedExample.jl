module ProjecturedExample

using Projectured

const _EXAMPLE_DIR = @__DIR__

include(joinpath(_EXAMPLE_DIR, "document", "Json.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Xml.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Mixed.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Syntax.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Text.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Object.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "LineNumbering.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "TextToString.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "WordWrapping.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Widget.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Book.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "FileSystem.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Collection.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Focusing.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Workbench.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Assistant.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Table.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Lazy.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Math.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Julia.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Wrapper.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Primitive.jl"))

include(joinpath(_EXAMPLE_DIR, "projection", "Json.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Table.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Xml.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Mixed.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Syntax.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Text.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Object.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "LineNumbering.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "TextToString.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "WordWrapping.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Widget.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Book.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "FileSystem.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Collection.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Reversing.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Filtering.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Sorting.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Focusing.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Workbench.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Assistant.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Lazy.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Math.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Julia.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Wrapper.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Graphics.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Primitive.jl"))

include(joinpath(_EXAMPLE_DIR, "Examples.jl"))

export make_json_document_example, make_json_projection_example
export make_json_sorted_projection_example
export make_json_null_document_example, make_json_null_projection_example
export make_json_string_document_example, make_json_string_projection_example
export make_xml_document_example, make_xml_projection_example
export make_mixed_document_example, make_mixed_projection_example
export make_syntax_document_example, make_syntax_projection_example
export make_text_document_example, make_text_projection_example
export make_object_document_example, make_object_projection_example
export make_line_numbering_document_example, make_line_numbering_projection_example
export make_text_to_string_document_example, make_text_to_string_projection_example
export make_word_wrapping_document_example, make_word_wrapping_projection_example
export make_widget_document_example, make_widget_projection_example
export make_widget_tabbed_pane_document_example
export make_book_document_example, make_book_projection_example
export make_filesystem_document_example, make_filesystem_projection_example
export make_collection_document_example, make_collection_projection_example
export make_reversing_projection_example
export make_filtering_projection_example
export make_sorting_projection_example
export make_focusing_document_example, make_focusing_projection_example
export make_workbench_document_example, make_workbench_projection_example
export make_assistant_document_example, make_assistant_projection_example
export make_table_document_example, make_table_projection_example
export make_math_table_document_example, make_math_table_projection_example
export make_lazy_document_example, make_lazy_projection_example
export make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example
export make_math_document_example, make_math_projection_example
export make_julia_document_example, make_julia_projection_example
export make_graphics_image_projection_example
export make_primitive_string_document_example, make_primitive_string_projection_example

export make_graphics_caching
export make_scrolling_document, make_scrolling_projection
export make_workbench_document, make_workbench_projection
export Example, examples, run_example, print_example, write_image_example
export json_example, json_sorted_example, json_null_example, json_string_example
export xml_example, mixed_example, syntax_example, text_example
export object_example, line_numbering_example, word_wrapping_example
export widget_example, widget_tabbed_pane_example, book_example, filesystem_example
export collection_example, reversing_example, filtering_example, sorting_example, focusing_example, table_example, math_table_example, workbench_example
export lazy_example, lazy_bidirectional_example
export math_example
export julia_example
export graphics_image_example
export primitive_string_example
export assistant_example

end
