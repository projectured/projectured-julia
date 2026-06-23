module ProjecturedExample

using Projectured
using Profile

# Live database examples use the opt-in Odbc package, which exports
# OdbcConnectionPool / OdbcDatabaseAdapter / DatabaseInstanceToDbCatalog /
# SqlToCellTable. ProjecturEd itself is database-optional; the example opts in.
using ProjecturedOdbc

const _EXAMPLE_DIR = @__DIR__

include(joinpath(_EXAMPLE_DIR, "document", "Json.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Xml.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Mixed.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Syntax.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Text.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Object.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "ObjectToWidget.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "LineNumbering.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "TextToString.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "WordWrapping.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "TextFiltering.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "TextHighlighting.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Widget.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Layout.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Book.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "FileSystem.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Navigator.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Collection.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Focusing.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Workbench.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Assistant.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Conversation.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Table.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Graph.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Lazy.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Math.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Julia.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Formula.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Wrapper.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Primitive.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "DbCatalog.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Database.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "DatabaseInstance.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Sql.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Clipboard.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Versioning.jl"))
include(joinpath(_EXAMPLE_DIR, "document", "Dragging.jl"))

include(joinpath(_EXAMPLE_DIR, "projection", "Json.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Table.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Graph.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Xml.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Mixed.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Syntax.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Text.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Object.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "ObjectToWidget.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "LineNumbering.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "TextToString.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "WordWrapping.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "TextFiltering.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "TextHighlighting.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Widget.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Layout.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Book.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "FileSystem.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Navigator.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Collection.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Reversing.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Filtering.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Searching.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Sorting.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Focusing.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Workbench.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Assistant.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Conversation.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Lazy.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Math.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Julia.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Formula.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Wrapper.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Graphics.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Primitive.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "DbCatalog.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Sql.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Clipboard.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Versioning.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Dragging.jl"))

include(joinpath(_EXAMPLE_DIR, "Examples.jl"))
include(joinpath(_EXAMPLE_DIR, "LiveExamples.jl"))

export make_json_document_example, make_json_projection_example
export make_json_sorted_projection_example
export make_json_null_document_example, make_json_null_projection_example
export make_json_string_document_example, make_json_string_projection_example
export make_xml_document_example, make_xml_projection_example, make_xml_widget_projection_example
export make_json_widget_projection_example, make_syntax_widget_graphics
export make_mixed_document_example, make_mixed_projection_example
export make_syntax_document_example, make_syntax_projection_example
export make_text_document_example, make_text_projection_example, make_text_with_image_example
export make_plain_text_document_example, make_plain_text_projection_example
export make_object_document_example, make_object_projection_example
export make_object_to_widget_document_example, make_object_to_widget_projection_example
export make_nested_object_to_widget_document_example
export make_line_numbering_document_example, make_line_numbering_projection_example
export make_text_to_string_document_example, make_text_to_string_projection_example
export make_word_wrapping_document_example, make_word_wrapping_projection_example
export make_text_filtering_document_example, make_text_filtering_projection_example
export make_text_highlighting_document_example, make_text_highlighting_projection_example
export make_widget_document_example, make_widget_projection_example
export make_widget_text_projection_example
export make_widget_label_document_example, make_widget_text_document_example
export make_widget_checkbox_document_example, make_widget_button_document_example
export make_widget_tooltip_document_example, make_widget_menu_item_document_example
export make_widget_menu_document_example, make_widget_toolbar_document_example
export make_widget_composite_document_example, make_widget_title_pane_document_example
export make_widget_split_pane_document_example, make_widget_scroll_bar_document_example
export make_widget_scroll_pane_document_example, make_widget_shell_document_example
export make_widget_tabbed_pane_document_example
export make_widget_badge_document_example, make_widget_separator_document_example
export make_widget_card_document_example, make_widget_switch_document_example
export make_widget_progress_document_example, make_widget_slider_document_example
export make_widget_radio_group_document_example, make_widget_avatar_document_example
export make_widget_alert_document_example, make_widget_skeleton_document_example
export make_widget_toggle_document_example, make_widget_toggle_group_document_example
export make_widget_select_document_example, make_widget_textarea_document_example
export make_widget_accordion_document_example, make_widget_table_document_example
export make_widget_tree_document_example
export make_layout_document_example, make_layout_projection_example
export make_book_document_example, make_book_projection_example
export make_filesystem_document_example, make_filesystem_projection_example, make_filesystem_widget_projection_example
export make_navigator_document_example, make_navigator_projection_example
export make_collection_document_example, make_collection_projection_example
export make_reversing_projection_example
export make_filtering_projection_example
export make_searching_projection_example
export make_sorting_projection_example
export make_focusing_document_example, make_focusing_projection_example
export make_workbench_document_example, make_workbench_projection_example
export make_assistant_document_example, make_assistant_projection_example
export make_table_document_example, make_table_projection_example
export make_graph_document_example, make_graph_projection_example
export make_math_table_document_example, make_math_table_projection_example
export make_lazy_document_example, make_lazy_projection_example
export make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example
export make_math_document_example, make_math_projection_example
export make_julia_document_example, make_julia_projection_example
export make_formula_document_example, make_formula_projection_example
export make_graphics_image_projection_example
export make_primitive_string_document_example, make_primitive_string_projection_example
export make_dbcatalog_document_example, make_dbcatalog_projection_example
export make_dvdrental_catalog_document_example
export make_dvdrental_dbcatalog_document_example, make_dvdrental_dbcatalog_projection_example, explore_dbcatalog!
export make_dvdrental_object_projection_example, dvdrental_object_example
export make_dvdrental_object_json_projection_example, dvdrental_object_json_example
export make_dvdrental_catalog_json_projection_example, dvdrental_catalog_json_example
export make_database_adapter_example, setup_persons_table, teardown_persons_table
export make_database_instance_document_example
export make_sql_document_example, make_sql_syntax_projection_example, make_sql_table_projection_example
export make_sql_nested_document_example, make_sql_nested_syntax_projection_example

export make_graphics_caching
export make_scrolling_document, make_scrolling_projection
export make_workbench_document, make_workbench_projection
export make_introspection_document, make_introspection_projection, EditorIntrospection
export make_text_configuring_projection
export Example, examples, run_example, run_console_example, run_web_example, print_example, write_example_image, write_example_pdf, record_example_video, make_typein_gestures
export make_json_console_projection_example
export record_assistant_conversation_video
export LiveExample, live_examples, play_live_example, record_live_example, timed_event, timed_operation
export json_typein_live, json_select_and_edit_live
export generate_example_screenshots, update_guide_screenshots
export json_example, json_sorted_example, json_null_example, json_string_example
export json_widget_example, xml_widget_example
export xml_example, mixed_example, syntax_example, text_example, plain_text_example, text_with_image_example
export object_example, object_to_widget_example, nested_object_to_widget_example, line_numbering_example, word_wrapping_example, text_filtering_example, text_highlighting_example
export widget_example, widget_tabbed_pane_example, widget_text_example
export widget_label_example, widget_checkbox_example, widget_button_example
export widget_tooltip_example, widget_menu_item_example, widget_menu_example
export widget_toolbar_example, widget_composite_example, widget_title_pane_example
export widget_split_pane_example, widget_scroll_bar_example, widget_scroll_pane_example
export widget_shell_example
export widget_badge_example, widget_separator_example, widget_card_example, widget_switch_example
export widget_progress_example, widget_slider_example, widget_radio_group_example
export widget_avatar_example, widget_alert_example, widget_skeleton_example
export widget_toggle_example, widget_toggle_group_example, widget_select_example
export widget_textarea_example, widget_accordion_example, widget_table_example, widget_tree_example
export layout_example, book_example, filesystem_example, navigator_example
export collection_example, reversing_example, filtering_example, searching_example, sorting_example, focusing_example, table_example, math_table_example, graph_example, workbench_example
export lazy_example, lazy_bidirectional_example
export math_example
export julia_example
export graphics_image_example
export primitive_string_example
export assistant_example
export conversation_example
export conversation_widget_example
export conversation_editor_example
export dbcatalog_example
export dvdrental_catalog_example
export dbcatalog_widget_example
export dvdrental_catalog_widget_example
export sql_syntax_example
export sql_insert_syntax_example
export sql_update_syntax_example
export sql_nested_syntax_example
export sql_table_example
export make_clipboard_document_example, make_clipboard_projection_example
export clipboard_example
export make_versioning_document_example, make_versioning_projection_example
export versioning_example
export make_dragging_document_example, make_dragging_projection_example
export dragging_example

end
