# One syntax leaf in two views at three places of a vertical layout, printed by one
# recursion over the views: a viewing step prints the leaf with `SyntaxToText` and
# gives the `TextView` of its text, and the text stage draws that view. Each view
# keeps a caret of its own, the places of one view share its caret, and the leaf
# and its text hold no caret. The helpers are those of `TextViewTest.jl`.

function test_syntax_leaf_view()
@testset "SyntaxLeafView" begin

measure = FixedMeasure(10, 18, 6, 0)
font = StyleFont("Ubuntu Mono", 20)
leaf = SyntaxLeaf(TextString("abcdef", font, color_white);
                  open = TextString("\"", font, color_white), close = TextString("\"", font, color_white))
view_a = SyntaxLeafView(leaf)
view_b = SyntaxLeafView(leaf)
root = VerticalLayout([view_a, view_b, view_a])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(SyntaxToText())),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    SyntaxLeafView => stages,
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

viewing = _text_view_collect(iomap, ViewingIoMap)
drawn = _text_view_collect(iomap, TextViewToGraphicsCanvasIoMap)

@testset "Each place prints its leaf view as the view of a text" begin
    @test length(viewing) == 3
    @test all(map(===, [m.input for m in viewing], [view_a, view_b, view_a]))
    @test all(m -> m.content.input === leaf, viewing)
    @test all(m -> m.output isa TextView && m.output.viewed === m.content.output, viewing)
    @test all(map(===, [m.input for m in drawn], [m.output for m in viewing]))
end

@testset "Two views keep two carets, and the leaf keeps none" begin
    replace_selection!(root, caret_at(2, 4))
    replace_selection!(root, caret_at(1, 2))
    @test stored(view_a) == value_caret(2) && is_live_selection(view_a)
    @test stored(view_b) == value_caret(4) && !is_live_selection(view_b)
    @test get_stored_selection(leaf) === nothing
    @test get_stored_selection(leaf.value) === nothing
end

@testset "The caret of a leaf view is the caret of its text view" begin
    # The open quote is one character, so `.value{2}` is the caret 3 of the text,
    # 30 pixels from the left.
    @test [stored(m.output) for m in viewing] ==
          [make_flat_caret_reference(3), make_flat_caret_reference(5), make_flat_caret_reference(3)]
    @test _text_view_caret_x.(drawn) == [30, 50, 30]
end

@testset "A key moves the caret of the view" begin
    replace_selection!(root, caret_at(2, 1))
    replace_selection!(root, caret_at(3, 2))
    @test press!(KeyDown(:right, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_a) == value_caret(3)
    @test stored(view_b) == value_caret(1)
end

@testset "A typed character edits the leaf and moves the caret of the view" begin
    @test press!(KeyPress('X', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test leaf.value.content == "abcXdef"
    @test stored(view_a) == value_caret(4)
    @test stored(view_b) == value_caret(1)
    @test get_stored_selection(leaf) === nothing
    @test get_stored_selection(leaf.value) === nothing
    @test all(m -> get_flat_string(m.output.viewed) == "\"abcXdef\"", viewing)
end

@testset "A click puts the caret of the view that it hits" begin
    place_y = Int(iomap.output.elements[2].y)
    # x = 25 is between the caret 2 and the caret 3 of the text: `.value{1}`.
    @test press!(MouseClick(:left, 25, place_y + 5; time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == value_caret(1) && is_live_selection(view_b)
    @test stored(view_a) == value_caret(4) && !is_live_selection(view_a)
end

@testset "Ctrl+Space selects the whole leaf in the view" begin
    @test press!(KeyDown(:space, ModifierKeys(ctrl = true); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == EmptyReference()
    @test stored(view_a) == value_caret(4)
    @test get_stored_selection(leaf) === nothing
end

@testset "A caret move recomputes only the places of its view" begin
    replace_selection!(root, caret_at(1, 1))
    cells = [_text_view_cells(m.output) for m in drawn]
    replace_selection!(root, caret_at(1, 2))
    stale = _text_view_stale_counts(cells)
    @test stale[1] > 0 && stale[2] == 0 && stale[3] == stale[1]
end

@testset "A leaf with no view prints as content" begin
    output = print_document(RecursiveProjection(ViewingProjection(SyntaxToText())), leaf).output
    @test output isa TextBlock
    @test get_flat_string(output) == "\"abcXdef\""
end

end
end
