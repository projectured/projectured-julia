module ProjecturedTest

using Test
using Projectured
using ProjecturedExample
using Projectured: ElementReference, RangeReference, PositionReference, FieldReference, PointReference,
                   TextRectangularReference,
                   ConcreteReferencePath, EmptyReferencePath,
                   color_red, color_blue, color_white, color_default, font_ubuntu_monospace_regular_24

const _test_backend = SdlBackend()

function __init__()
    init!(_test_backend)
end

include("common/CellTest.jl")
include("reference/ReferenceBuilderTest.jl")
include("device/EventCaseTest.jl")
include("document/JsonTest.jl")
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/LayoutAllocatorTest.jl")
include("document/CollectionTest.jl")
include("document/TabularTest.jl")
include("document/PrimitiveTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("projection/SyntaxToTextTest.jl")
include("projection/SyntaxTreeSelectionTest.jl")
include("projection/FileSystemToSyntaxTest.jl")
include("projection/PrimitiveToTextTest.jl")
include("projection/TextToGraphicsTest.jl")
include("projection/WordWrappingTest.jl")
include("projection/CopyingProjectionTest.jl")
include("projection/TooltipTest.jl")
include("projection/GraphicsToFileTest.jl")
include("editor/PrinterTest.jl")
include("editor/ExampleTest.jl")
include("editor/SelectionTest.jl")
include("editor/ReaderTest.jl")
include("editor/ReplTest.jl")
include("editor/TypeinTest.jl")
include("editor/McpTest.jl")
include("editor/MouseClickTest.jl")
include("editor/ClickRoundtripTest.jl")
include("editor/CollapseRoundtripTest.jl")
include("editor/SyntaxTreeNavigationTest.jl")
include("editor/AssistantMvpTest.jl")

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
    end
end

function test_projections()
    @testset "Projections" begin
        test_json_to_syntax()
        test_syntax_to_text()
        test_syntax_tree_selection()
        test_primitive_to_text()
        test_text_to_graphics()
        test_word_wrapping()
        test_copying_projection()
        test_tooltip()
        test_write_image()
    end
end

function test_all()
    @testset "Projectured" begin
    test_cell()
    test_reference_builder()
    test_event_case()
    test_documents()
    test_projections()
    test_printers()
    test_readers()
    test_selections()
    test_repls()
    test_typeins()
    test_mcp_tools()
    test_assistant_mvp()
    test_mouse_clicks()
    test_click_roundtrips()
    test_text_nav_invariants_all()
    test_json_content_clicks_clean_all()
    test_collapse_roundtrip()
    test_tree_navigations()
    end
end

export test_all
export test_cell, test_reference_builder, test_event_case
export test_json, test_syntax, test_text, test_graphics, test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers, test_collection, test_tabular, test_primitive
export test_json_to_syntax, test_syntax_to_text, test_syntax_tree_selection, test_primitive_to_text, test_text_to_graphics, test_word_wrapping, test_copying_projection, test_write_image, test_tooltip
export test_examples, test_selections
export test_printer, test_printers, test_example, test_selection
export explore_selections
export test_reader, test_readers, walk_reader_events
export test_repl, test_repls, walk_repl_loop
export test_typein, test_typeins, walk_typein
export test_mouse_click_roundtrip, test_mouse_clicks
export test_click_roundtrip, test_click_roundtrips, test_text_nav_invariants, test_text_nav_invariants_all
export test_json_content_clicks_clean, test_json_content_clicks_clean_all
export test_collapse_roundtrip
export test_tree_navigation, test_tree_navigations, explore_tree_selections
export test_assistant_mvp, make_assistant_mvp_setup, make_assistant_mvp_projection

end # module ProjecturedTest
