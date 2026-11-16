# One text in two views at three places of a vertical layout: each view keeps a
# caret of its own, the places of one view share its caret, and the text holds no
# caret. The content prints with `TextBlockToGraphicsCanvas`, and each view draws
# its caret over that drawing with `TextViewToGraphicsCanvas`. The places are
# printed with one IO map and read with real keys and a real click, as the editor
# reads them.

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
    elseif x isa AbstractDict
        # A dictionary is a cache of a print, such as the blocks of the places of
        # the lines. It can hold a cell of a place that is gone, which no drawing
        # reads.
    elseif x isa Union{AbstractVector, Tuple, CellVector}
        foreach(element -> _text_view_collect(element, T, found, seen), x)
    else
        for name in fieldnames(typeof(x))
            isdefined(x, name) && _text_view_collect(getfield(x, name), T, found, seen)
        end
    end
    found
end

# The cells that a drawing reaches, short of the documents that it draws.
function _text_view_cells(x, found = Cell[], seen = Set{UInt64}())
    x isa Union{Number, AbstractString, Symbol, Nothing, Function, Module, Type, Char, Task,
                TextDocument, TextView, LayoutDocument} && return found
    id = objectid(x)
    id in seen && return found
    push!(seen, id)
    if x isa Cell
        push!(found, x)
        _text_view_cells(x[], found, seen)
    elseif x isa AbstractDict
        # A cache of a print, as in `_text_view_collect`.
    elseif x isa Union{AbstractVector, Tuple, CellVector}
        foreach(element -> _text_view_cells(element, found, seen), x)
    else
        for name in fieldnames(typeof(x))
            isdefined(x, name) && _text_view_cells(getfield(x, name), found, seen)
        end
    end
    found
end

# The count of the cells of each drawing that are stale.
_text_view_stale_counts(cells) = [count(cell -> !is_cell_valid(cell), drawing_cells) for drawing_cells in cells]

_text_view_texts(graphics) =
    [element.text for element in _text_view_collect(graphics, GraphicsText) if !isempty(element.text)]

# The caret that a view draws, the third element of its canvas: its x, or
# `nothing` when it draws none.
function _text_view_caret_x(view_iomap)
    caret = view_iomap.output.elements[3]
    caret.w == 0 ? nothing : Int(caret.x)
end

# Whether the caret that a view draws has the color of a live caret.
_text_view_is_caret_live(view_iomap) =
    view_iomap.output.elements[3].color == view_iomap.projection.caret_color

# A content with a field of the name `viewed`, the field in which a view keeps what
# it shows, and a view of that content.
@document struct TextViewClashContent
    viewed::String
end

@document struct TextViewClashView <: ContentView
    viewed::TextViewClashContent
end

function test_text_view()
@testset "TextView" begin

measure = FixedMeasure(10, 18, 6, 0)
style = StyleText(StyleFont("Ubuntu Mono", 20), color_white)
content = make_text_block("first line\nsecond line", style)
view_a = TextView(content)
view_b = TextView(content)
root = VerticalLayout([view_a, view_b, view_a])
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    TextView       => TextViewToGraphicsCanvas(),
    TextBlock      => TextBlockToGraphicsCanvas(; measure),
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
key(name) = KeyDown(name, ModifierKeys(); time = 0.0)
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
caret_at(place, k) = concat_references(places[place], make_flat_caret_reference(k))
stored(document) = strip_reference_types(get_stored_selection(document))
caret(k) = make_flat_caret_reference(k)

view_iomaps = _text_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
content_iomaps = [view_iomap.content for view_iomap in view_iomaps]

@testset "Each place draws its view over a drawing of the text" begin
    @test length(view_iomaps) == 3
    @test all(map(===, [m.input for m in view_iomaps], [view_a, view_b, view_a]))
    @test all(m -> m isa TextBlockToGraphicsCanvasIoMap && m.input === content, content_iomaps)
    @test all(m -> m.output.elements[2] === m.content.output, view_iomaps)
    # The drawing of the text draws no caret: only its lines and their pointer regions.
    @test isempty(_text_view_collect(content_iomaps[1].output, GraphicsRect))
end

@testset "Two views keep two carets, and the text keeps none" begin
    replace_selection!(root, caret_at(2, 5))
    replace_selection!(root, caret_at(1, 3))
    @test stored(view_a) == caret(3) && is_live_selection(view_a)
    @test stored(view_b) == caret(5) && !is_live_selection(view_b)
    @test get_stored_selection(content) === nothing
end

@testset "Two places of one view share its caret" begin
    replace_selection!(root, caret_at(3, 7))
    @test stored(view_a) == caret(7)
    # A character is 10 pixels wide, so the caret at 7 is at x = 70.
    @test _text_view_caret_x.(view_iomaps) == [70, 50, 70]
end

@testset "Only the place on the path from the root draws a live caret" begin
    # The path goes through the third place: the first place draws the same caret
    # of view A as a dormant one, and the caret of view B is dormant.
    @test _text_view_is_caret_live.(view_iomaps) == [false, false, true]
    replace_selection!(root, caret_at(1, 7))
    @test _text_view_is_caret_live.(view_iomaps) == [true, false, false]
    @test _text_view_caret_x.(view_iomaps) == [70, 50, 70]
    replace_selection!(root, caret_at(2, 5))
    @test _text_view_is_caret_live.(view_iomaps) == [false, true, false]
    replace_selection!(root, caret_at(3, 7))
    @test _text_view_is_caret_live.(view_iomaps) == [false, false, true]
end

@testset "A key moves the caret of the view" begin
    @test press!(key(:right)) isa ReplaceSelectionOperation
    @test stored(view_a) == caret(8)
    @test stored(view_b) == caret(5)
    @test _text_view_caret_x.(view_iomaps) == [80, 50, 80]
    @test press!(key(:down)) isa ReplaceSelectionOperation
    # Down keeps the x: offset 8 of the second line, which starts at 11.
    @test stored(view_a) == caret(19)
    press!(key(:up))
    @test stored(view_a) == caret(8)
end

@testset "A typed character edits the text and moves the caret of the view" begin
    @test press!(typed('X')) isa ReplaceTextRangeOperation
    @test get_flat_string(content) == "first liXne\nsecond line"
    @test stored(view_a) == caret(9)
    @test stored(view_b) == caret(5)
    press!(typed('\n'))
    @test get_flat_string(content) == "first liX\nne\nsecond line"
    @test stored(view_a) == caret(10)
    @test get_stored_selection(content) === nothing
    @test _text_view_texts(view_iomaps[1].output) == _text_view_texts(view_iomaps[2].output) ==
          _text_view_texts(view_iomaps[3].output) == ["first liX", "ne", "second line"]
end

@testset "A click puts the caret of the view that it hits" begin
    place_y = Int(iomap.output.elements[1].elements[2].y)
    @test press!(MouseClick(:left, 25, place_y + 5; time = 0.0)) isa ReplaceSelectionOperation
    # The click hits the first line of the second place, between "fi" and "rst".
    @test stored(view_b) == caret(2) && is_live_selection(view_b)
    @test stored(view_a) == caret(10) && !is_live_selection(view_a)
end

@testset "A caret move recomputes only the marks of the places of its view" begin
    replace_selection!(root, caret_at(1, 1))
    view_cells = [_text_view_cells(m.output) for m in view_iomaps]
    text_cells = [_text_view_cells(m.output) for m in content_iomaps]
    replace_selection!(root, caret_at(1, 4))
    # No cell of the drawings of the text: only the band and the caret of view A.
    @test _text_view_stale_counts(text_cells) == [0, 0, 0]
    stale = _text_view_stale_counts(view_cells)
    @test stale[1] > 0 && stale[2] == 0 && stale[3] == stale[1]
end

@testset "A viewing step refuses a content that has a field with the name viewed" begin
    # A path of the view can not name that field of the content: the field of the
    # view has the same name.
    clash = TextViewClashView(TextViewClashContent("x"))
    @test_throws ArgumentError print_document(ViewingProjection(nothing), nothing, clash, nothing)
end

end
end
