# One JSON string in two views at three places of a vertical layout, printed by one
# recursion over the views at each stage: JSON to syntax, syntax to text, and text
# to graphics. Each view keeps a caret of its own, the places of one view share its
# caret, and no content holds a caret. The helpers are those of the platform tests.

const _json_view_collect = ProjecturedPlatformTest._text_view_collect
const _json_view_caret_x = ProjecturedPlatformTest._text_view_caret_x

function test_json_string_view()
@testset "JsonStringView" begin

measure = FixedMeasure(10, 18, 6, 0)
json_string = JsonString("abcd")
view_a = JsonStringView(json_string)
view_b = JsonStringView(json_string)
root = VerticalLayout([view_a, view_b, view_a])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(JsonToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText())),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonStringView => stages,
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
value_caret(k) = strip_reference_types(@reference(view_a, value{k}))
caret_at(place, k) = concat_references(places[place], value_caret(k))
stored(document) = strip_reference_types(get_stored_selection(document))

steps = _json_view_collect(iomap, ViewingIoMap)
json_steps = filter(m -> m.input isa JsonStringView, steps)
drawn = _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)

@testset "Each place prints its view through the three stages" begin
    @test all(map(===, [m.input for m in json_steps], [view_a, view_b, view_a]))
    # JSON to syntax: the view of the leaf that the string printed to.
    @test all(m -> m.output isa SyntaxLeafView && m.output.content === m.content.output, json_steps)
    # Syntax to text: the view of the text of that leaf.
    leaf_steps = filter(m -> m.input isa SyntaxLeafView, steps)
    @test all(map(===, [m.input for m in leaf_steps], [m.output for m in json_steps]))
    @test all(m -> m.output isa TextView && get_flat_string(m.output.content) == "\"abcd\"", leaf_steps)
    @test length(drawn) == 3
end

@testset "Two views keep two carets, and no content holds one" begin
    replace_selection!(root, caret_at(2, 3))
    replace_selection!(root, caret_at(1, 1))
    @test stored(view_a) == value_caret(1) && is_live_selection(view_a)
    @test stored(view_b) == value_caret(3) && !is_live_selection(view_b)
    @test get_stored_selection(json_string) === nothing
    @test all(m -> get_stored_selection(m.content.output) === nothing, json_steps)
    # The open quote is one character: `.value{1}` is drawn at 20 and `.value{3}` at 40.
    @test _json_view_caret_x.(drawn) == [20, 40, 20]
end

@testset "A key moves the caret of the view" begin
    @test press!(KeyDown(:right, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_a) == value_caret(2)
    @test stored(view_b) == value_caret(3)
    @test _json_view_caret_x.(drawn) == [30, 40, 30]
end

@testset "A typed character edits the string and moves the caret of the view" begin
    @test press!(KeyPress('X', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test json_string.value == "abXcd"
    @test stored(view_a) == value_caret(3)
    @test stored(view_b) == value_caret(3)
    @test get_stored_selection(json_string) === nothing
    @test all(m -> get_flat_string(m.content.output) == "\"abXcd\"",
              filter(m -> m.input isa SyntaxLeafView, _json_view_collect(iomap, ViewingIoMap)))
end

@testset "A click puts the caret of the view that it hits" begin
    place_y = Int(iomap.output.elements[2].y)
    # x = 25 is between the caret 2 and the caret 3 of `"abXcd"`: `.value{1}`.
    @test press!(MouseClick(:left, 25, place_y + 5; time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == value_caret(1) && is_live_selection(view_b)
    @test stored(view_a) == value_caret(3) && !is_live_selection(view_a)
end

@testset "A string with no view prints as content" begin
    output = print_document(RecursiveProjection(ViewingProjection(JsonToSyntax())), json_string).output
    @test output isa SyntaxLeaf
end

end
end
