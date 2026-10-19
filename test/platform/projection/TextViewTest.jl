# One text in two views, and one view at two places: each view keeps a caret of its
# own, the places of one view share its caret, and the text holds no caret. The
# places are three groups of one pane split, printed with one IO map and read with
# real keys, as the editor reads them.

# Every value of type `T` that the cells, the vectors and the fields of `x` reach.
function _text_view_collect(x, T, found = Any[], seen = Set{UInt64}())
    x isa Union{Number, AbstractString, Symbol, Nothing, Function, Module, Type, Char, Task} &&
        return found
    id = objectid(x)
    id in seen && return found
    push!(seen, id)
    x isa T && push!(found, x)
    if x isa Cell
        _text_view_collect(x[], T, found, seen)
    elseif x isa Union{AbstractVector, Tuple, CellVector}
        foreach(element -> _text_view_collect(element, T, found, seen), x)
    else
        for name in fieldnames(typeof(x))
            isdefined(x, name) && _text_view_collect(getfield(x, name), T, found, seen)
        end
    end
    found
end

# The cells of a drawn place: every cell that its graphics reach, short of the
# documents that it draws.
function _text_view_cells(x, found = Cell[], seen = Set{UInt64}())
    x isa Union{Number, AbstractString, Symbol, Nothing, Function, Module, Type, Char, Task,
                TextDocument, TextView, PaneDocument} && return found
    id = objectid(x)
    id in seen && return found
    push!(seen, id)
    if x isa Cell
        push!(found, x)
        _text_view_cells(x[], found, seen)
    elseif x isa Union{AbstractVector, Tuple, CellVector}
        foreach(element -> _text_view_cells(element, found, seen), x)
    else
        for name in fieldnames(typeof(x))
            isdefined(x, name) && _text_view_cells(getfield(x, name), found, seen)
        end
    end
    found
end

# The count of the cells of each place that `change!` makes stale.
function _text_view_stale_counts(places, change!)
    cells = [_text_view_cells(place) for place in places]
    change!()
    [count(cell -> !is_cell_valid(cell), place_cells) for place_cells in cells]
end

_text_view_texts(graphics) =
    [element.text for element in _text_view_collect(graphics, GraphicsText) if !isempty(element.text)]

function test_text_view()
@testset "TextView" begin

measure = FixedMeasure(10, 18, 6, 0)
style = StyleText(StyleFont("Ubuntu Mono", 20), color_white)
content = make_text_block("first line\nsecond line", style)
view_a = TextView(content)
view_b = TextView(content)
tree = PaneTree(PaneSplit(:horizontal, [PaneGroup([PaneTab("A", view_a)]),
                                        PaneGroup([PaneTab("B", view_b)]),
                                        PaneGroup([PaneTab("A again", view_a)])]))
text = ChainingProjection(TextViewToText(), TextToGraphics(measure = measure))
widget = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = measure)
renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
    Pair{Type,Any}[TextView => text], LayoutToGraphics().dispatch, widget.dispatch)))
projection = ChainingProjection(RecursiveProjection(PaneToWidget()), renderer)
iomap = print_document(projection, nothing, tree,
                       PrinterContext(EmptyReference(), Cell(900), Cell(300), Dict{Symbol,Any}()))
editor = (; document = tree)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
key(name) = KeyDown(name, ModifierKeys(); time = 0.0)
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)

places = [@reference(tree, root.elements[1].tabs[1].content),
          @reference(tree, root.elements[2].tabs[1].content),
          @reference(tree, root.elements[3].tabs[1].content)]
caret_at(place, k) = concat_references(places[place], make_flat_caret_reference(k))
stored(document) = strip_reference_types(get_stored_selection(document))
caret(k) = make_flat_caret_reference(k)

view_iomaps = _text_view_collect(iomap, TextViewToTextIoMap)
graphics_iomaps = _text_view_collect(iomap, TextToGraphicsIoMap)
drawn = [only(filter(g -> g.input === m.output, graphics_iomaps)).output for m in view_iomaps]

@testset "Each place prints its view over the lines of the text" begin
    @test length(view_iomaps) == 3
    @test all(map(===, [m.input for m in view_iomaps], [view_a, view_b, view_a]))
    @test all(m -> m.output.elements === content.elements, view_iomaps)
end

@testset "Two views keep two carets, and the text keeps none" begin
    replace_selection!(tree, caret_at(1, 3))
    @test stored(view_a) == caret(3) && is_live_selection(view_a)
    @test get_stored_selection(content) === nothing

    replace_selection!(tree, caret_at(2, 5))
    @test stored(view_b) == caret(5) && is_live_selection(view_b)
    @test stored(view_a) == caret(3) && !is_live_selection(view_a)
    @test get_stored_selection(content) === nothing
end

@testset "Two places of one view share its caret" begin
    replace_selection!(tree, caret_at(3, 7))
    @test stored(view_a) == caret(7) && is_live_selection(view_a)
    @test stored(view_b) == caret(5) && !is_live_selection(view_b)
    @test [stored(m.output) for m in view_iomaps] == [caret(7), caret(5), caret(7)]
    @test [is_live_selection(m.output) for m in view_iomaps] == [true, false, true]
end

@testset "A key moves the caret of the view" begin
    @test press!(key(:right)) isa ReplaceSelectionOperation
    @test stored(view_a) == caret(8)
    @test stored(view_b) == caret(5)
    @test get_stored_selection(content) === nothing
end

@testset "A typed character edits the text and moves the caret of the view" begin
    @test press!(typed('X')) isa ReplaceTextRangeOperation
    @test get_flat_string(content) == "first liXne\nsecond line"
    @test stored(view_a) == caret(9)
    @test stored(view_b) == caret(5)
    @test get_stored_selection(content) === nothing
    press!(typed('\n'))
    @test get_flat_string(content) == "first liX\nne\nsecond line"
    @test stored(view_a) == caret(10)
    @test get_stored_selection(content) === nothing
    @test _text_view_texts(drawn[1]) == _text_view_texts(drawn[2]) ==
          _text_view_texts(drawn[3]) == ["first liX", "ne", "second line"]
end

@testset "The edit of a run goes back as a flat edit of the view" begin
    # The characters 0 to 2 of the run of the second line, "ne".
    run_edit = Reference(FieldReferenceStep("elements"), RangeReferenceStep(1, 2),
                         FieldReferenceStep("elements"), RangeReferenceStep(0, 1),
                         FieldReferenceStep("content"), RangeReferenceStep(0, 2))
    operation = read_intent(TextViewToText(), view_iomaps[1], ReplaceStringRangeOperation(run_edit, "Z"))
    # The second line starts at 10, after "first liX" and its break.
    @test operation isa ReplaceTextRangeOperation
    @test strip_reference_types(operation.reference) == make_flat_range_reference(10, 12)
    @test operation.replacement == "Z"
end

@testset "A caret move recomputes only the places of its view" begin
    plain = make_text_block("first line\nsecond line", style)
    plain_drawn = print_document(TextToGraphics(measure = measure), plain).output
    replace_selection!(plain, caret(7))
    plain_stale = only(_text_view_stale_counts([plain_drawn], () -> replace_selection!(plain, caret(2))))
    @test plain_stale > 0

    stale = _text_view_stale_counts(drawn, () -> replace_selection!(tree, caret_at(3, 2)))
    # The view costs a caret move no cell more than one text in one place.
    @test stale == [plain_stale, 0, plain_stale]
    replace_selection!(tree, caret_at(2, 6))
    stale = _text_view_stale_counts(drawn, () -> replace_selection!(tree, caret_at(2, 7)))
    @test stale == [0, plain_stale, 0]
end

end
end
