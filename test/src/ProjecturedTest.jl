module ProjecturedTest

using Test
using Projectured
using ProjecturedExample
using Projectured: ElementReference, RangeReference, PositionReference, FieldReference, PointReference,
                   TextRectangularReference,
                   ConcreteReferencePath, EmptyReferencePath, ReferencePath,
                   map_reference_forward, map_reference_backward,
                   color_red, color_blue, color_green, color_white, color_default,
                   color_solarized_background_dark,
                   font_ubuntu_monospace_regular_24

const _test_backend = make_backend(:sdl)

function __init__()
    init!(_test_backend)
end

include("common/CellTest.jl")
include("reference/ReferenceBuilderTest.jl")
include("reference/TypeReferenceTest.jl")
include("device/EventCaseTest.jl")
include("backend/ConsoleBackendTest.jl")
include("document/JsonTest.jl")
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/LayoutAllocatorTest.jl")
include("document/CollectionTest.jl")
include("document/TabularTest.jl")
include("document/PrimitiveTest.jl")
include("document/JsonParserTest.jl")
include("document/SqlParserTest.jl")
include("document/SqlDocumentTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("projection/FormulaToSyntaxTest.jl")
include("projection/SqlToSyntaxTest.jl")
include("projection/XmlToSyntaxTest.jl")
include("projection/SyntaxToTextTest.jl")
include("projection/SyntaxTreeSelectionTest.jl")
include("projection/TableSelectionTest.jl")
include("projection/TableNavigationTest.jl")
include("projection/GraphTest.jl")
include("projection/FileSystemToSyntaxTest.jl")
include("projection/PrimitiveToTextTest.jl")
include("projection/TextToGraphicsTest.jl")
include("projection/WordWrappingTest.jl")
include("projection/TextFilteringTest.jl")
include("projection/TextHighlightingTest.jl")
include("projection/SelectionInvertingTest.jl")
include("projection/ObjectToWidgetTest.jl")
include("projection/SyntaxToWidgetTest.jl")
include("projection/ProjectionConfiguringTest.jl")
include("projection/WidgetTextEditTest.jl")
include("projection/DocumentInsertionTest.jl")
include("projection/ConversationEditorTest.jl")
include("projection/CopyingProjectionTest.jl")
include("projection/ClipboardToAnyTest.jl")
include("projection/VersioningToAnyTest.jl")
include("projection/TooltipTest.jl")
include("projection/SplitPaneDragTest.jl")
include("projection/DraggingTest.jl")
include("projection/GraphicsToFileTest.jl")
include("backend/PdfTest.jl")
include("backend/DirtyRectTest.jl")
include("editor/PrinterTest.jl")
include("editor/ExampleTest.jl")
include("editor/SelectionEnumeration.jl")
include("editor/TextNavigationTest.jl")
include("editor/ReaderTest.jl")
include("editor/ReplTest.jl")
include("editor/TypeinTest.jl")
include("editor/McpTest.jl")
include("editor/ConversationSerializationTest.jl")
include("editor/ConversationParsingTest.jl")
include("editor/GestureRecognizerTest.jl")
include("editor/MouseClickTest.jl")
include("editor/ClickRoundtripTest.jl")
include("editor/CollapseRoundtripTest.jl")
include("editor/SyntaxTreeNavigationTest.jl")
include("editor/AssistantMvpTest.jl")
include("editor/ConversationPanelTest.jl")
include("editor/VideoTest.jl")
include("external/DatabaseTest.jl")
include("external/DatabaseTabularTest.jl")
include("external/DbCatalogTest.jl")
include("external/DbCatalogTabularTest.jl")
include("external/DbCatalogJsonTest.jl")
include("external/DbCatalogSqlTest.jl")
include("external/DbCatalogSyntaxTest.jl")

function test_documents()
    @testset "Documents" begin
        test_json()
        test_syntax()
        test_text()
        test_graphics()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_collection()
        test_tabular()
        test_primitive()
        test_json_parser()
        test_xml_parser()
        test_sql_parser()
        test_sql_document()
    end
end

function test_projections()
    @testset "Projections" begin
        test_json_to_syntax()
        test_json_to_syntax_reader()
        test_formula_to_syntax()
        test_sql_to_syntax()
        test_sql_to_syntax_selection()
        test_sql_insert_update_selection()
        test_sql_ddl()
        test_sql_ddl_selection()
        test_db_catalog_sql()
        test_xml_to_syntax()
        test_xml_to_syntax_reader()
        test_syntax_to_text()
        test_syntax_tree_selection()
        test_filesystem_to_syntax()
        test_table_selection()
        test_graph()
        test_primitive_to_text()
        test_text_to_graphics()
        test_word_wrapping()
        test_text_filtering()
        test_text_highlighting()
        test_selection_inverting()
        test_object_to_widget()
        test_syntax_to_widget()
        test_projection_configuring()
        test_widget_text_editing()
        test_copying_projection()
        test_clipboard_to_any()
        test_versioning_to_any()
        test_tooltip()
        test_split_pane_drag()
        test_dragging()
        test_write_image()
        test_record_video()
        test_write_pdf()
        test_dirty_rect()
    end
end

function test_all()
    @testset "Projectured" begin
    test_cell()
    test_reference_builder()
    test_type_reference()
    test_event_case()
    test_console_backend()
    test_gesture_recognizer()
    test_documents()
    test_projections()
    test_printers()
    test_readers()
    test_text_navigations()
    test_text_navigations_complete()
    test_repls()
    test_typeins()
    test_mcp_tools()
    test_conversation_serialization()
    test_parse_markdown_blocks()
    test_document_insertion()
    test_conversation_editor()
    test_assistant_mvp()
    test_mouse_clicks()
    test_click_roundtrips()
    test_text_nav_invariants_all()
    test_json_content_clicks_clean_all()
    test_collapse_roundtrip()
    test_tree_navigations()
    test_tree_navigations_complete()
    test_table_navigation()
    test_database_no_db()
    end
end

"""
    test_table()

Narrow runner for the table selection + grid-navigation suites
(`test_table_selection` and `test_table_navigation`).
"""
function test_table()
    @testset "Table" begin
        test_table_selection()
        test_table_navigation()
    end
end

export test_all
export test_cell, test_reference_builder, test_type_reference, test_event_case, test_console_backend, test_gesture_recognizer
export test_json, test_syntax, test_text, test_graphics, test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers, test_collection, test_tabular, test_primitive, test_json_parser, test_xml_parser, test_sql_parser
export test_formula_to_syntax
export test_json_to_syntax, test_json_to_syntax_reader, test_syntax_to_text, test_syntax_tree_selection, test_filesystem_to_syntax, test_primitive_to_text, test_text_to_graphics, test_word_wrapping, test_text_filtering, test_text_highlighting, test_selection_inverting, test_object_to_widget, test_syntax_to_widget, test_projection_configuring, test_widget_text_editing, test_copying_projection, test_clipboard_to_any, test_versioning_to_any, test_write_image, test_record_video, test_tooltip, test_split_pane_drag, test_dragging, test_write_pdf, test_dirty_rect
export test_table, test_table_selection, test_table_navigation, explore_table_selections
export test_graph
export test_examples, test_text_navigations, test_text_navigations_complete
export test_printer, test_printers, test_example, test_text_navigation
export explore_text_selections, collect_text_selections, collect_tree_selections, collect_json_tree_selections
export test_reader, test_readers, walk_reader_events
export test_repl, test_repls, walk_repl_loop
export test_typein, test_typeins, walk_typein
export test_mouse_click_roundtrip, test_mouse_clicks
export test_click_roundtrip, test_click_roundtrips, test_text_nav_invariants, test_text_nav_invariants_all
export test_json_content_clicks_clean, test_json_content_clicks_clean_all
export test_collapse_roundtrip
export test_tree_navigation, test_tree_navigations, test_tree_navigations_complete, explore_tree_selections
export test_assistant_mvp, make_assistant_mvp_setup, make_assistant_mvp_projection
export test_conversation_editor, test_conversation_serialization, test_parse_markdown_blocks
export test_database_connection, test_database, test_database_no_db, test_database_tabular
export test_db_catalog, test_db_catalog_tabular, test_db_catalog_json, test_db_catalog_syntax, test_db_catalog_sql

end # module ProjecturedTest
