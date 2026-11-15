# A picture (`ImageDocument`) draws as the label that shows it: its pixels at their
# natural size, or smaller in their shape to fit the slot that the place gives. An
# `Image` with no answer yet draws a box with its path, and one whose read failed
# draws the path and the reason. The scroll pane of a place keeps the choice of the
# natural size (Ctrl+1) and gives it back to its rule (Ctrl+0), for every content.

using Test
using ProjecturedKernel.CellModule
import ProjecturedKernel.EditorModule: BackgroundSource

const _ITW_MEASURE = FixedMeasure(10, 18, 6, 0)
const _ITW_PROJECTION = NaturalToGraphics(; measure = _ITW_MEASURE)

# A picture of `width` by `height` pixels whose work runs nowhere. With `answered`
# false it has no natural size yet.
function _itw_make_picture(width, height; answered = true)
    source = BackgroundSource(inputs -> Any[nothing for _ in inputs]; description = "the pixels of a test picture")
    size_source = BackgroundSource(inputs -> Any[nothing for _ in inputs]; description = "the sizes of test pictures")
    picture = ProjecturedPlatform.StyleModule._make_image("chart.png", source, size_source)
    answered && (picture.natural_size = (Int(width), Int(height)))
    picture
end

# What a canvas draws, with the place of each element in the coordinates of the
# canvas: `(:image, x, y, width, height)`, `(:rect, x, y, width, height)` and
# `(:text, x, y, text)`.
function _itw_collect(node, ox = 0, oy = 0, found = Any[])
    if node isa GraphicsCanvas
        for element in node.elements
            _itw_collect(element, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _itw_collect(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsImage
        push!(found, (:image, ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h)))
    elseif node isa GraphicsRect
        push!(found, (:rect, ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h)))
    elseif node isa GraphicsText
        push!(found, (:text, ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end

# The context of a slot `width` wide, and `height` high when it has a height.
_itw_make_slot(width; height = nothing) = height === nothing ?
    with_exact_size(PrinterContext(); width = Cell(Int32(width))) :
    with_exact_size(PrinterContext(); width = Cell(Int32(width)), height = Cell(Int32(height)))

_itw_print(document, width; height = nothing) =
    print_document(_ITW_PROJECTION, nothing, document, _itw_make_slot(width; height))

_itw_draw(document, width; height = nothing) = _itw_collect(_itw_print(document, width; height).output)

_itw_find(drawn, kind) = [element for element in drawn if first(element) === kind]

# The editor an operation is evaluated against.
function _itw_evaluate!(operation)
    editor = Editor(PrimitiveString("picture"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
    EditorModule.run_print_stage!(editor)
    evaluate_operation(editor, operation)
end

_itw_ctrl(key) = KeyDown(key, ModifierKeys(ctrl = true); time = 0.0)

function test_image_to_widget()
@testset "a picture draws as the label that shows it" begin

    @testset "before the first answer a slot 200 wide draws a box 200 by 150 with the path" begin
        drawn = _itw_draw(_itw_make_picture(400, 300; answered = false), 200)
        @test (:image, 0, 0, 200, 150) in drawn
        @test (:rect, 0, 0, 200, 150) in drawn
        @test any(element -> element[1] === :text && occursin("chart.png", element[4]), drawn)
    end

    @testset "after the answer the picture fits the slot and never draws larger" begin
        picture = _itw_make_picture(400, 300)
        @test _itw_find(_itw_draw(picture, 200), :image) == [(:image, 0, 0, 200, 150)]
        @test isempty(_itw_find(_itw_draw(picture, 200), :text))
        @test _itw_find(_itw_draw(picture, 800), :image) == [(:image, 0, 0, 400, 300)]
        # A scroll pane that grows on both axes gives no limit.
        pane = WidgetScrollPane(picture; grows = (width = true, height = true))
        @test _itw_find(_itw_draw(pane, 200; height = 300), :image) == [(:image, 0, 0, 400, 300)]
    end

    @testset "three pictures in a layout 600 wide draw 200 wide each" begin
        pictures = Any[_itw_make_picture(400, 300) for _ in 1:3]
        drawn = _itw_draw(HorizontalLayout(pictures; child_width = Fill), 600)
        @test _itw_find(drawn, :image) == [(:image, 0, 0, 200, 150), (:image, 200, 0, 200, 150),
                                           (:image, 400, 0, 200, 150)]
    end

    @testset "a failed read draws the path and the reason" begin
        picture = _itw_make_picture(400, 300; answered = false)
        picture.failure = ErrorException("no such file")
        drawn = _itw_draw(picture, 200)
        @test isempty(_itw_find(drawn, :image))
        said = join((element[4] for element in _itw_find(drawn, :text)), " ")
        @test occursin("chart.png", said) && occursin("no such file", said)
    end

    @testset "a card of a dashboard draws the picture at the width of the card" begin
        # The card of a dashboard is a `WidgetCard` over the view of its content.
        file = ImageFile("card.png", _itw_make_picture(400, 300))
        card() = WidgetCard(; title = "Chart", content = make_document_view(file))
        # A card 300 wide has 9 px of padding on each side.
        @test _itw_find(_itw_draw(card(), 300; height = 600), :image) == [(:image, 9, 35, 282, 212)]
        @test _itw_find(_itw_draw(card(), 600; height = 600), :image) == [(:image, 9, 35, 400, 300)]
    end

    @testset "Ctrl+1 in a tab 200 wide draws the picture 400 by 300 and Ctrl+0 fits it again" begin
        file = ImageFile("tab.png", _itw_make_picture(400, 300))
        tab_view = make_file_view(file)
        card_view = make_document_view(file)
        draw(view) = _itw_find(_itw_draw(view, 200; height = 300), :image)
        @test only(draw(tab_view))[4:5] == (200, 150)
        @test only(draw(card_view))[4:5] == (200, 150)
        # The tab has its caret in the file, so the layout of the view passes a key on.
        for view in (tab_view, card_view)
            view.selection = annotate_reference_types(view, ConcreteReference(FieldReferenceStep("file"), EmptyReference()))
        end
        # Ctrl+0 at the fit changes nothing, so it goes on to the zoom of the window.
        iomap = _itw_print(tab_view, 200; height = 300)
        @test read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:zero)) === nothing
        operation = read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:one))
        @test operation isa ReplaceViewStateOperation
        _itw_evaluate!(operation)
        @test tab_view.scroll.at_natural_size && !card_view.scroll.at_natural_size
        @test only(draw(tab_view))[4:5] == (400, 300)
        @test only(draw(card_view))[4:5] == (200, 150)
        # At the natural size Ctrl+1 changes nothing, and Ctrl+0 gives the fit back.
        iomap = _itw_print(tab_view, 200; height = 300)
        @test read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:one)) === nothing
        operation = read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:zero))
        @test operation isa ReplaceViewStateOperation
        _itw_evaluate!(operation)
        @test !tab_view.scroll.at_natural_size
        @test only(draw(tab_view))[4:5] == (200, 150)
    end

    @testset "a picture in a label has no scroll pane and no Ctrl+1" begin
        iomap = _itw_print(WidgetLabel(_itw_make_picture(400, 300)), 200)
        @test read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:one)) === nothing
        @test read_intent(_ITW_PROJECTION, iomap, _itw_ctrl(:zero)) === nothing
    end

    @testset "Ctrl+1 takes the limit off any content: a text in a scroll pane stops wrapping" begin
        words = join(fill("word", 20), " ")
        pane = WidgetScrollPane(WidgetLabel(words))
        lines(document) = length(unique(element[3] for element in _itw_find(_itw_draw(document, 100; height = 200), :text)))
        @test lines(pane) > 1
        operation = read_intent(_ITW_PROJECTION, _itw_print(pane, 100; height = 200), _itw_ctrl(:one))
        @test operation isa ReplaceViewStateOperation
        _itw_evaluate!(operation)
        @test lines(pane) == 1
        operation = read_intent(_ITW_PROJECTION, _itw_print(pane, 100; height = 200), _itw_ctrl(:zero))
        _itw_evaluate!(operation)
        @test lines(pane) > 1
    end

    @testset "a save does not write the choice" begin
        pane = WidgetScrollPane(WidgetLabel("x"))
        pane.at_natural_size = true
        positional, keywords = pred_arguments(pane)
        @test !any(keyword -> first(keyword) === :at_natural_size, keywords)
        @test :at_natural_size in get_view_state_fields(WidgetScrollPane)
    end
end
end # test_image_to_widget
