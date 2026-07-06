module ProjecturedTest

using Test
using Projectured
using ProjecturedExample
# The generic test drivers ((label, document, projection) forms), the reflexive
# cell walker, the event battery, and the kernel unit suites live in
# ProjecturedKernelTest — the base of the test-package DAG. The umbrella keeps
# the `Example`-typed overloads and the all-examples sweeps (ExampleSweeps.jl),
# and extends the ground-truth selection enumerators for the domains it owns.
using ProjecturedKernelTest
import ProjecturedKernelTest: test_printer, test_reader, test_repl,
                              test_text_navigation, test_tree_navigation,
                              collect_text_selections, collect_tree_selections,
                              explore_text_selections, explore_tree_selections,
                              walk_printer_output, walk_reader_events, walk_repl_loop,
                              test_event_case, test_gesture_binding,
                              WalkStatus, _walk!, _WALK_MAX_DEPTH, _WALK_MAX_NODES,
                              _ALL_READER_EVENTS, _assert_reaches_all
# Opt into the SDL backend package so the test suite can drive rendering /
# write_image / click roundtrips (provides SdlBackend + GraphicsCanvasToImageFile).
# The library itself is SDL-optional; the test package opts in.
using ProjecturedSdl
# Opt into the video package so VideoTest can drive record_video (it provides the
# record_video method on the kernel seam; FFMPEG lives here, not in ProjecturedSdl).
using ProjecturedVideo
# Likewise opt into the Odbc package so the database tests can construct
# adapters/pools/projections and assert on their types (all exported by the package).
using ProjecturedOdbc
# Opt into the Tulip solver package so ConstraintSolverTest can construct a
# TulipConstraintSolver and exercise the LP-backed constraint layout.
using ProjecturedTulip
using Projectured: ElementReference, RangeReference, PositionReference, FieldReference, PointReference,
                   TextRectangularReference,
                   ConcreteReferencePath, EmptyReferencePath, ReferencePath,
                   map_reference_forward, map_reference_backward,
                   color_red, color_blue, color_green, color_white, color_default,
                   color_solarized_background_dark,
                   font_ubuntu_monospace_regular_20

# Built lazily in __init__ (runtime, after the SDL extension has loaded) rather
# than as a precompile-time const, so precompilation doesn't depend on the extension.
function __init__()
    initialize_backend!(make_backend(:sdl))
end

# Live-DB fixture helpers used by the opt-in `external/` catalog tests. Defined
# here directly (rather than re-exported from the example package) to keep
# ProjecturedTest free of the `ProjecturedExtrasExample` / native-shim
# dependency. `db_execute_raw` / `db_insert!` / `RawDatabaseResult` come from
# `using ProjecturedOdbc` above.
function setup_persons_table(adapter)
    db_execute_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    db_execute_raw(adapter, "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    db_insert!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function teardown_persons_table(adapter)
    db_execute_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end

include("reference/TypeReferenceTest.jl")
include("backend/ConsoleBackendTest.jl")
include("document/JsonTest.jl")
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GeometryTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/LayoutAllocatorTest.jl")
include("document/ConstraintSolverTest.jl")
include("document/CollectionTest.jl")
include("document/TabularTest.jl")
include("document/PrimitiveTest.jl")
include("document/JsonParserTest.jl")
include("document/SqlParserTest.jl")
include("document/SqlDocumentTest.jl")
include("projection/ProjectionTemplateTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("projection/AtomicFixtureTest.jl")
include("projection/GestureMapTest.jl")
include("projection/GestureHelpTest.jl")
include("projection/FocusingTest.jl")
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
include("projection/ProjectionConfiguringTest.jl")
include("projection/WidgetTextEditTest.jl")
include("projection/WidgetButtonTest.jl")
include("projection/WidgetGestureTest.jl")
include("projection/WidgetSelectTest.jl")
include("projection/WidgetMenuTest.jl")
include("projection/WidgetContextMenuTest.jl")
include("projection/WidgetDialogTest.jl")
include("projection/WidgetActionTest.jl")
include("projection/WidgetIconTest.jl")
include("projection/WidgetTreeTest.jl")
include("projection/WidgetToolbarTest.jl")
include("projection/WidgetTableTest.jl")
include("projection/LayoutCloseoutTest.jl")
include("projection/WidgetFormsTest.jl")
include("projection/WidgetPopupExampleTest.jl")
include("projection/DocumentInsertionTest.jl")
include("projection/ConversationEditorTest.jl")
include("projection/CopyingProjectionTest.jl")
include("projection/ClipboardToAnyTest.jl")
include("projection/VersioningToAnyTest.jl")
include("projection/TooltipTest.jl")
include("projection/HoverProbeTest.jl")
include("projection/SplitPaneDragTest.jl")
include("projection/WorkbenchTabClickTest.jl")
include("projection/WidgetTransformPaneTest.jl")
include("projection/DraggingTest.jl")
include("projection/AnchorPointTest.jl")
include("projection/GraphicsToFileTest.jl")
include("backend/PdfTest.jl")
include("backend/DirtyRectTest.jl")
include("editor/ExampleTest.jl")
include("editor/ExampleSweeps.jl")
include("editor/SelectionEnumeration.jl")
include("editor/PrinterLocalityTest.jl")
include("editor/RecursionContractTest.jl")
include("editor/TypeinTest.jl")
include("editor/JuliaTypeinTest.jl")
include("editor/McpTest.jl")
include("editor/ConversationSerializationTest.jl")
include("editor/ConversationParsingTest.jl")
include("editor/GestureRecognizerTest.jl")
include("editor/MouseClickTest.jl")
include("editor/ClickRoundtripTest.jl")
include("editor/CollapseRoundtripTest.jl")
include("editor/AssistantMvpTest.jl")
include("editor/ConversationPanelTest.jl")
include("editor/VideoTest.jl")
include("editor/WorkbenchFileTest.jl")
include("projection/CatalogTest.jl")
include("external/DatabaseTest.jl")
include("external/DatabaseTabularTest.jl")
include("external/DbCatalogTest.jl")
include("external/DbCatalogTabularTest.jl")
include("external/DbCatalogSqlTest.jl")
include("external/DbCatalogSyntaxTest.jl")
include("serializer/SerializationTest.jl")

function test_documents()
    @testset "Documents" begin
        test_json()
        test_syntax()
        test_text()
        test_graphics()
        test_affine_transform()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_constraint_solver()
        test_collection()
        test_tabular()
        test_primitive()
        test_json_parser()
        test_xml_parser()
        test_sql_parser()
        test_sql_document()
        test_serialization()
    end
end

function test_projections()
    @testset "Projections" begin
        test_projection_template_hygiene()
        test_template_structural_locality()
        test_graphics_structural_locality()
        test_json_to_syntax()
        test_json_to_syntax_reader()
        test_json_gesture_collection()
        test_gesture_map()
        test_gesture_help()
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
        test_widget_button_behavior()
        test_widget_gestures()
        test_widget_select_dropdown()
        test_widget_menu()
        test_widget_context_menu()
        test_widget_dialog()
        test_widget_action()
        test_widget_icon()
        test_widget_tree()
        test_widget_toolbar()
        test_widget_table()
        test_layout_closeout()
        test_widget_forms()
        test_widget_popup_example()
        test_copying_projection()
        test_clipboard_to_any()
        test_versioning_to_any()
        test_tooltip()
        test_reference_inspector_text()
        test_hover_probe()
        test_hover_probe_pipeline()
        test_split_pane_drag()
        test_workbench_tab_click()
        test_widget_transform_pane()
        test_dragging()
        test_anchor_point()
        test_write_image()
        test_record_video()
        test_write_pdf()
        test_dirty_rect()
    end
end

function test_all()
    @testset "Projectured" begin
    # test_cell + test_reference_builder live in package/kernel/test/; run
    # with `Pkg.test("ProjecturedKernel"; test_args=["cell","reference"])`.
    test_type_reference()
    test_event_case()
    test_gesture_binding()
    test_focusing()
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
    test_julia_typein()
    test_conversation_editor()
    test_assistant_mvp()
    test_workbench_file_keys()
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
export test_type_reference, test_event_case, test_gesture_binding, test_focusing, test_console_backend, test_gesture_recognizer
export test_json, test_syntax, test_text, test_graphics, test_affine_transform, test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers, test_constraint_solver, test_collection, test_tabular, test_primitive, test_json_parser, test_xml_parser, test_sql_parser, test_serialization
export test_formula_to_syntax, test_projection_template_hygiene
export AtomicFixture, test_atomic_render, test_atomic_fixtures
export test_json_to_syntax, test_json_to_syntax_reader, test_json_gesture_collection, test_gesture_map, test_gesture_help, test_syntax_to_text, test_syntax_tree_selection, test_filesystem_to_syntax, test_primitive_to_text, test_text_to_graphics, test_word_wrapping, test_text_filtering, test_text_highlighting, test_selection_inverting, test_object_to_widget, test_syntax_to_widget, test_projection_configuring, test_widget_text_editing, test_widget_button_behavior, test_widget_gestures, test_widget_select_dropdown, test_widget_menu, test_widget_context_menu, test_widget_dialog, test_widget_action, test_widget_icon, test_widget_tree, test_widget_toolbar, test_widget_table, test_layout_closeout, test_widget_forms, test_widget_popup_example, test_copying_projection, test_clipboard_to_any, test_versioning_to_any, test_write_image, test_record_video, test_tooltip, test_reference_inspector_text, test_hover_probe, test_hover_probe_pipeline, test_split_pane_drag, test_workbench_tab_click, test_widget_transform_pane, test_dragging, test_anchor_point, test_write_pdf, test_dirty_rect
export test_table, test_table_selection, test_table_navigation, explore_table_selections
export test_graph
export test_examples, test_text_navigations, test_text_navigations_complete
export test_printer, test_printers, test_example, test_text_navigation
export printer_locality_report, explore_selection_locality, test_selection_locality, test_selection_localities, LocalityReport, LocalityCell, is_selection_cell
export explore_structural_locality, report_structural_locality, test_template_structural_locality, test_graphics_structural_locality
export explore_value_locality, test_value_locality, test_value_localities
export explore_text_selections, collect_text_selections, collect_tree_selections, collect_json_tree_selections
export test_recursion_contract, test_recursion_contracts, walk_recursion_contract, walk_reference_roundtrip, probe_delegation
export test_reader, test_readers, walk_reader_events
export test_repl, test_repls, walk_repl_loop
export test_catalog
export test_typein, test_typeins, walk_typein
export test_julia_typein
export test_mouse_click_roundtrip, test_mouse_clicks
export test_click_roundtrip, test_click_roundtrips, test_text_nav_invariants, test_text_nav_invariants_all
export test_json_content_clicks_clean, test_json_content_clicks_clean_all
export test_collapse_roundtrip
export test_tree_navigation, test_tree_navigations, test_tree_navigations_complete, explore_tree_selections
export test_assistant_mvp, make_assistant_mvp_setup, make_assistant_mvp_projection
export test_conversation_editor, test_conversation_serialization, test_parse_markdown_blocks
export test_workbench_file_keys
export test_database_connection, test_database, test_database_no_db, test_database_tabular
export test_db_catalog, test_db_catalog_tabular, test_db_catalog_syntax, test_db_catalog_sql

end # module ProjecturedTest
