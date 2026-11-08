# The picture of a file (`Image`): its pixels are a background cell that a task
# fills after the frame in which a paint asked for them. The make of a picture and
# the print of a label or of a text span with it run no work. A read of the `data`
# of their `GraphicsImage` in a frame of an editor records a demand, and the work
# runs once after that frame. The work answers an exception as a value, and the
# `apply` of the answer writes the natural size or the failure, and no cell whose
# value stays the same.

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, BackgroundSource, wait_for_cell!, start_background_cell_work!,
                                       drain_operations!
import ProjecturedKernel.ToolModule: run_with_evaluation_editor

# A source whose work records the inputs of each run and answers pixels of the
# size that `size` holds at that time.
function _make_image_test_source(calls, size)
    calls_lock = ReentrantLock()
    BackgroundSource(; description = "the pixels of a test picture") do inputs
        lock(() -> push!(calls, copy(inputs)), calls_lock)
        width, height = size[]
        Any[(fill(0xff, 4 * width * height), width, height) for _ in inputs]
    end
end

# An editor that draws nothing, with an IoMap, so that a read in a frame records a
# demand.
function _make_image_test_editor()
    editor = Editor(PrimitiveString("picture"), IdentityProjection(); backend = HeadlessBackend(),
                    devices = Device[])
    EditorModule.run_print_stage!(editor)
    editor
end

# The `GraphicsImage` elements of a canvas, at any depth.
function _collect_image_test_images(canvas, images = GraphicsImage[])
    for element in canvas.elements
        element isa GraphicsImage && push!(images, element)
        element isa GraphicsCanvas && _collect_image_test_images(element, images)
    end
    images
end

_print_image_test_label(picture) = _collect_image_test_images(print_document(
    RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(; measure = FixedMeasure(10, 18, 6, 0)).dispatch)),
    nothing, WidgetLabel(picture), PrinterContext()).output)

_print_image_test_span(picture) = _collect_image_test_images(print_document(
    TextToGraphics(measure = FixedMeasure(10, 18, 6, 0)),
    TextBlock(TextLine(TextGraphics(picture, 64, 48)))).output)

# Apply what the tasks posted to `editor`, until `cell` is final, for at most ten
# seconds.
function _wait_until_image_test_final(editor, cell)
    deadline = time() + 10
    while time() < deadline
        drain_operations!(editor)
        run_with_evaluation_editor(() -> cell[], editor)
        is_cell_provisional(cell) || return true
        sleep(0.01)
    end
    false
end

function test_image()
@testset "Image" begin

    @testset "the make of a picture and a print of a label or a span run no work" begin
        calls = Vector{Any}[]
        picture = ProjecturedPlatform.StyleModule._make_image("a.png", _make_image_test_source(calls, Ref((4, 3))))
        @test picture.filename == "a.png" && picture.read_count == 0
        @test picture.natural_size === nothing && picture.failure === nothing
        label_images = _print_image_test_label(picture)
        span_images = _print_image_test_span(picture)
        @test length(label_images) == 1 && length(span_images) == 1
        @test isempty(calls)
        # Both put the pixel cell itself into the image; a box measures 320 by 240
        # until the size is known.
        pixels = getfield(picture, :pixels)
        @test getfield(label_images[1], :data) === pixels && getfield(span_images[1], :data) === pixels
        @test (Int(label_images[1].w), Int(label_images[1].h)) == (320, 240)
        @test isempty(calls)
    end

    @testset "a read of the data in a frame records a demand, and the work runs once after it" begin
        calls = Vector{Any}[]
        size = Ref((4, 3))
        picture = ProjecturedPlatform.StyleModule._make_image("a.png", _make_image_test_source(calls, size))
        image = only(_print_image_test_label(picture))
        editor = _make_image_test_editor()
        pixels = getfield(picture, :pixels)
        @test run_with_evaluation_editor(() -> image.data, editor) === nothing
        @test isempty(calls)
        start_background_cell_work!(editor)
        @test _wait_until_image_test_final(editor, pixels)
        @test calls == [[("a.png", 0)]]
        @test picture.natural_size == (4, 3) && picture.failure === nothing
        # The label draws the natural size.
        @test (Int(only(_print_image_test_label(picture)).w), Int(only(_print_image_test_label(picture)).h)) == (4, 3)

        # One more read count is a new input: the next read in a frame runs the work again.
        runs = Ref(0)
        watcher = Cell(@computation (runs[] += 1; picture.natural_size))
        @test watcher[] == (4, 3) && runs[] == 1
        picture.read_count = 1
        @test run_with_evaluation_editor(() -> image.data, editor) isa Tuple
        start_background_cell_work!(editor)
        @test _wait_until_image_test_final(editor, pixels)
        @test calls == [[("a.png", 0)], [("a.png", 1)]]
        # An answer of the same size writes no cell.
        @test watcher[] == (4, 3) && runs[] == 1
        # An answer of another size writes the natural size.
        size[] = (6, 5)
        picture.read_count = 2
        run_with_evaluation_editor(() -> image.data, editor)
        start_background_cell_work!(editor)
        @test _wait_until_image_test_final(editor, pixels)
        @test picture.natural_size == (6, 5) && watcher[] == (6, 5) && runs[] == 2
    end

    @testset "with no editor, wait_for_cell! answers the pixels of the work" begin
        calls = Vector{Any}[]
        picture = ProjecturedPlatform.StyleModule._make_image("b.png", _make_image_test_source(calls, Ref((2, 2))))
        answer = wait_for_cell!(getfield(picture, :pixels); editor = nothing)
        @test answer[2:3] == (2, 2) && length(answer[1]) == 16
        @test picture.natural_size == (2, 2)
    end

    @testset "a path that does not exist answers its exception as a value" begin
        picture = Image(joinpath(mktempdir(), "missing.png"))
        answer = wait_for_cell!(getfield(picture, :pixels); editor = nothing)
        @test answer isa Exception
        @test picture.failure isa Exception && picture.natural_size === nothing
        # The label of a failed picture shows a box under its pixels.
        elements = print_document(
            RecursiveProjection(TypeDispatchingProjection(
                WidgetToGraphics(; measure = FixedMeasure(10, 18, 6, 0)).dispatch)),
            nothing, WidgetLabel(picture), PrinterContext()).output.elements
        @test any(element -> element isa GraphicsRect, elements)
    end

    @testset "a save writes the path of a picture and a load makes a picture that reads nothing" begin
        picture = Image("c.png")
        positional, keywords = pred_arguments(picture)
        @test positional == ("c.png",) && isempty(keywords)
        loaded = make_pred_document(Image, positional, keywords)
        @test loaded isa Image && loaded.filename == "c.png" && loaded.natural_size === nothing
        @test get_view_state_fields(Image) ==
              (:read_count, :pixels, :natural_size, :failure, :source)
    end

end
end # test_image
