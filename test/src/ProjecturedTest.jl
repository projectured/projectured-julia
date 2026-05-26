module ProjecturedTest

using Test
using Projectured
using ProjecturedExample
using Projectured: ElementReference, RangeReference, color_red, color_blue, color_white, color_default, font_ubuntu_monospace_regular_24

const _test_backend = SdlBackend()

function __init__()
    init!(_test_backend)
end

include("common/CellTest.jl")
include("document/JsonTest.jl")
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/CollectionTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("projection/SyntaxToTextTest.jl")
include("projection/TextToGraphicsTest.jl")
include("projection/CopyingProjectionTest.jl")
include("editor/PrinterTest.jl")
include("editor/ExampleTest.jl")
include("editor/SelectionTest.jl")
include("editor/ReaderTest.jl")
include("editor/ReplTest.jl")
include("editor/McpTest.jl")
include("editor/MouseClickTest.jl")

function test_documents()
    @testset "Documents" begin
        test_json()
        test_syntax()
        test_text()
        test_graphics()
        test_graphics_layout()
        test_collection()
    end
end

function test_projections()
    @testset "Projections" begin
        test_json_to_syntax()
        test_syntax_to_text()
        test_text_to_graphics()
        test_copying_projection()
    end
end

function test_all()
    @testset "Projectured" begin
    test_cell()
    test_documents()
    test_projections()
    test_printers()
    test_readers()
    test_selections()
    test_repls()
    test_mcp_tools()
    # TODO: re-enable when mouse click tests are fixed
    #test_mouse_clicks()
    end
end

export test_all
export test_cell, test_json, test_syntax, test_text, test_graphics, test_graphics_layout, test_collection
export test_json_to_syntax, test_syntax_to_text, test_text_to_graphics, test_copying_projection
export test_examples, test_selections
export test_printer, test_printers, test_example, test_selection
export explore_selections
export test_reader, test_readers, walk_reader_events
export test_repl, test_repls, walk_repl_loop
export test_mouse_click_roundtrip, test_mouse_clicks

end # module ProjecturedTest
