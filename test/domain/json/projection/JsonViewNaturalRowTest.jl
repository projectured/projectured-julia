# A view of a content in the general renderer. The rows of the syntax slice for a
# view print it in the stages of a view: the step of a view around the stage from
# any domain to syntax and around the stage from syntax to text, the fold stage of
# the text, and the stage that draws the view of the text. So a view keeps its caret
# and its fold in a place that gives it no chain of its own.

# Each text that a graphics output draws, with the place where it draws it.
function _vnr_drawn(node, found = Tuple{String,Int,Int}[], x = 0, y = 0)
    node isa Cell && return _vnr_drawn(node[], found, x, y)
    if node isa GraphicsCanvas
        foreach(element -> _vnr_drawn(element, found, x + Int(node.x), y + Int(node.y)), node.elements)
    elseif node isa GraphicsViewport
        _vnr_drawn(node.content, found, x + Int(node.x), y + Int(node.y))
    elseif node isa GraphicsText
        push!(found, (String(node.text), x + Int(node.x), y + Int(node.y)))
    end
    found
end

# The text of each drawn line, from left to right, with the lines from top to bottom.
function _vnr_lines(drawn)
    rows = sort(unique(text[3] for text in drawn))
    [join(text[1] for text in sort(filter(text -> text[3] == row, drawn); by = text -> text[2])) for row in rows]
end

_vnr_make_array() = JsonArray([JsonString("ab"), JsonNumber(7), JsonArray([JsonNull(), JsonBool(true)])])

# A layout that holds `document`, its print through the general renderer, and a
# function that reads an event and runs the answer.
function _vnr_show(document; measure = FixedMeasure(10, 18, 6, 0))
    root = VerticalLayout([document])
    projection = NaturalToGraphics(; measure)
    iomap = print_document(projection, root)
    editor = (; document = root)
    press!(event) = begin
        operation = read_intent(projection, nothing, Intent(event), iomap).operation
        operation === nothing || evaluate_operation(editor, operation)
        operation
    end
    (; root, projection, iomap, press!)
end

# The editor of the fault tests of the platform on `document`, with the general
# renderer, and its backend.
function _vnr_make_editor(document; measure = FixedMeasure(10, 18, 6, 0))
    ProjecturedPlatformTest.FaultTests._make_part_editor(document, NaturalToGraphics(; measure))
end

# The lines that the last frame of `backend` painted.
_vnr_painted_lines(backend) = _vnr_lines(_vnr_drawn(last(rendered_output(backend))))

function test_json_view_natural_row()
@testset "the rows of the general renderer for a view" begin

stored(document) = strip_reference_types(get_stored_selection(document))
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
click(x, y) = MouseClick(:left, x, y; time = 0.0)
open_lines = ["[", "\"ab\",", "7,", "[", "null,", "true", "]", "]"]

@testset "a view draws what an equal content draws" begin
    content = _vnr_show(_vnr_make_array())
    array = _vnr_make_array()
    view = JsonArrayView(array)
    shown = _vnr_show(view)
    drawn = _vnr_drawn(shown.iomap.output)
    # The same texts at the same places, so the indentation is the same too.
    @test drawn == _vnr_drawn(content.iomap.output)
    @test _vnr_lines(drawn) == open_lines
    # No struct is drawn by reflection.
    @test !any(text -> occursin("View", text[1]) || occursin("viewed", text[1]), drawn)
    # The view prints in the steps of a view, with the barrier of a fault inside each
    # step, and the step gives the view of each printed child.
    steps = _json_view_collect(shown.iomap, ViewingIoMap)
    json_step = only(filter(step -> step.input isa JsonArrayView, steps))
    @test json_step.content isa FaultCatchingIoMap
    @test json_step.output isa SyntaxNodeView
    @test [nameof(typeof(child)) for child in json_step.output.children] ==
          [:SyntaxLeafView, :SyntaxLeafView, :SyntaxNodeView]
    @test any(step -> step.input === json_step.output && step.output isa TextView, steps)
end

@testset "a click gives the caret that it gives on a content" begin
    content = _vnr_show(_vnr_make_array())
    array = _vnr_make_array()
    view = JsonArrayView(array)
    shown = _vnr_show(view)
    # In the string, on its first quote, in the number, and in the inner array.
    for (x, y) in ((55, 45), (25, 45), (25, 75), (45, 140))
        @test content.press!(click(x, y)) isa ReplaceSelectionOperation
        @test shown.press!(click(x, y)) isa ReplaceSelectionOperation
        @test _json_keys_caret_text(get_stored_selection(shown.root)) ==
              _json_keys_caret_text(get_stored_selection(content.root))
        @test _json_view_holds_no_caret(array)
    end
    shown.press!(click(55, 45))
    @test stored(view.elements[1]) == strip_reference_types(@reference(view.elements[1], value{2}))
end

@testset "a typed character and a key of a view" begin
    array = _vnr_make_array()
    view = JsonArrayView(array)
    shown = _vnr_show(view)
    in_string(k) = strip_reference_types(@reference(shown.root, children[1].elements[1].value{k}))
    replace_selection!(shown.root, in_string(1))
    @test shown.press!(typed('X')) isa ReplaceStringRangeOperation
    @test array.elements[1].value == "aXb"
    @test stored(shown.root) == in_string(2)
    @test _vnr_lines(_vnr_drawn(shown.iomap.output))[2] == "\"aXb\","
    # A comma in the number is a key of the view of the array: it appends the place
    # for a new value, and the caret goes to the view of that place.
    replace_selection!(shown.root, strip_reference_types(@reference(shown.root, children[1].elements[2].value{1})))
    @test shown.press!(typed(',')) isa Operation
    @test length(array.elements) == 4 && array.elements[4] isa JsonInsertion
    @test view.elements[4] isa JsonInsertionView && get_stored_selection(view.elements[4]) !== nothing
    @test _json_view_holds_no_caret(array)
end

@testset "the fold of a view hides the lines of its node" begin
    array = _vnr_make_array()
    view = JsonArrayView(array)
    shown = _vnr_show(view)
    view.elements[3].collapsed = true
    @test _vnr_lines(_vnr_drawn(shown.iomap.output)) == ["[", "\"ab\",", "7,", "[…]", "]"]
    # The fold is state of the view: the array keeps its elements, and a second view
    # of it is open.
    @test length(array.elements[3].elements) == 2
    @test _vnr_lines(_vnr_drawn(_vnr_show(JsonArrayView(array)).iomap.output)) == open_lines
    view.elements[3].collapsed = false
    @test _vnr_lines(_vnr_drawn(shown.iomap.output)) == open_lines
end

@testset "a JSON content has no fold" begin
    # The fold is new with the views: no JSON content type keeps one, so a tab of a
    # JSON file with no view shows each node open.
    @test !any(type -> :collapsed in fieldnames(type), (JsonArray, JsonObject, JsonObjectEntry))
    @test :collapsed in fieldnames(JsonArrayView) && :collapsed in fieldnames(JsonObjectView)
end

@testset "a fault in the print of one node costs that node" begin
    faults = ProjecturedPlatformTest.FaultTests
    # A value that throws when a frame reads it, after the print.
    broken, runs = Cell(true), Ref(0)
    array = JsonArray([JsonString("first"), faults._make_breakable_string(broken, runs), JsonString("third")])
    editor, backend = _vnr_make_editor(JsonArrayView(array))
    faults._run_frames!(editor, 2)
    records = faults._get_print_records(editor)
    @test length(records) == 1
    label = faults._get_mark_label(only(records))
    @test _vnr_painted_lines(backend) == ["[", "\"first\",", label * ",", "\"third\"", "]"]
    # After an operation the editor prints the node again.
    broken[] = false
    post_operation!(editor, DoNothingOperation())
    drain_operations!(editor)
    run_frame!(editor)
    @test _vnr_painted_lines(backend) == ["[", "\"first\",", "\"repaired\",", "\"third\"", "]"]
end

@testset "the view of a syntax tree starts at the stage from syntax to text" begin
    font = StyleFont("Ubuntu Mono", 20)
    text(s) = TextString(s, font, color_white)
    node = SyntaxNode([SyntaxLeaf(text("ab")), SyntaxLeaf(text("cde"))];
                      open = text("["), close = text("]"), sep = text(", "))
    shown = _vnr_show(SyntaxNodeView(node))
    @test _vnr_lines(_vnr_drawn(shown.iomap.output)) == ["[ab, cde]"]
    steps = _json_view_collect(shown.iomap, ViewingIoMap)
    @test any(step -> step.input isa SyntaxNodeView && step.output isa TextView, steps)
    @test !any(step -> step.output isa SyntaxNodeView, steps)
end

@testset "the view of a text keeps the row of the widgets" begin
    block = TextBlock(TextLine(TextString("plain", StyleFont("Ubuntu Mono", 20), color_white)))
    shown = _vnr_show(TextView(block))
    @test _vnr_lines(_vnr_drawn(shown.iomap.output)) == ["plain"]
    @test isempty(_json_view_collect(shown.iomap, ViewingIoMap))
    @test length(_json_view_collect(shown.iomap, TextViewToGraphicsCanvasIoMap)) == 1
end

end
end
