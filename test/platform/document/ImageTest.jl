# The picture of a file (`Image`): its pixels are a background cell that a task
# fills after the frame in which a paint asked for them. The make of a picture and
# the print of a label or of a text span with it run no work. A read of the `data`
# of their `GraphicsImage` in a frame of an editor records a demand, and the work
# runs once after that frame. The work answers an exception as a value, and the
# `apply` of the answer writes the natural size or the failure, and no cell whose
# value stays the same.
#
# The file of a picture (`ImageFile`) is a file that a person does not edit. Its
# extensions are registered, the read of a file makes a picture that reads nothing,
# a change of the file adds one to the `read_count` of the picture that the file
# keeps, and a copy of a picture is a new picture that reads nothing.

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

# A paint of the window reads the output of each place that it draws. A frame of an
# editor with no window paints nothing, so a test prints the place itself and reads its
# output in each step.
function _print_image_test_place(editor, place)
    run_with_evaluation_editor(editor) do
        print_document(RecursiveProjection(NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))),
                       nothing, place, PrinterContext())
    end
end

function _paint_image_test_place!(editor, place_iomap)
    walk(element) = if element isa GraphicsCanvas
        (element.w, element.h)
        foreach(walk, element.elements)
    elseif element isa GraphicsViewport
        walk(element.content)
    end
    run_with_evaluation_editor(() -> walk(place_iomap.output), editor)
    nothing
end

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

# The file of a picture whose natural size is known and that no work reads: a test
# that measures what a picture draws needs no pixels.
function _make_sized_picture_file(name::AbstractString, width::Integer, height::Integer)
    source = BackgroundSource(inputs -> Any[nothing for _ in inputs]; description = "the pixels of a sized test picture")
    picture = ProjecturedPlatform.StyleModule._make_image(name, source)
    picture.natural_size = (Int(width), Int(height))
    ImageFile(name, picture)
end

# The file of a picture whose source counts its runs: the file keeps the time and the
# size of its path, as a file that a tab opens does.
function _make_image_test_file(path, calls, size)
    file = ImageFile(path, ProjecturedPlatform.StyleModule._make_image(path, _make_image_test_source(calls, size)))
    ProjecturedPlatform.FileFormatModule._record_read_file_hash!(file)
    file
end

# Wait until the store holds a change of a watched file, for at most `seconds`.
function _wait_for_image_test_change(store::FileChangeStore; seconds::Real = 10.0)
    deadline = time() + seconds
    while time() < deadline
        if lock(() -> !isempty(store.changed) &&
                      all(w -> w.stamp == compute_file_stamp(w.path), store.files), store.lock)
            return true
        end
        sleep(0.05)
    end
    false
end

# The read that a draw of a file asks for when a change is counted, run to its end with
# no editor.
function _read_image_test_file!(file)
    ensure_file_text_cell!(file)
    state = get_file_disk_state(file)
    state.read_count > state.loaded_count && wait_for_cell!(state.text.cell; editor = nothing)
    file
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

    @testset "the extensions of a picture are an ImageFile that a person does not edit" begin
        folder = mktempdir()
        for extension in (".png", ".jpg", ".jpeg", ".bmp", ".gif", ".PNG")
            @test get_file_document_type("chart" * extension) === ImageFile
        end
        @test !is_editable_file_type(ImageFile)
        path = joinpath(folder, "a.png")
        write(path, "not a picture")
        # The read of the file makes a picture of its path and reads no byte.
        picture = read_document_file(path)
        @test picture isa Image && picture.filename == path && picture.read_count == 0
        @test picture.natural_size === nothing && picture.failure === nothing
        @test read_file_content(ImageFile, path) isa Image
        @test read_document_file(joinpath(folder, "missing.png")) isa DocumentNothing
        file = make_file_tab(path)
        @test file isa ImageFile && get_edited_document(file) isa Image
        @test get_file_content(file).filename == path
        state = get_file_disk_state(file)
        @test state.file_stamp == compute_file_stamp(path) && state.file_hash === nothing
        @test get_document_title(file) == "a.png"
        # A file of a picture is a file document: a save writes nothing of it.
        @test is_file_document(file)
        evaluate_operation(nothing, SaveFileOperation(file))
        @test read(path, String) == "not a picture"
        # `ImageFile(path)` reads nothing and holds a picture of its path.
        made = ImageFile(path)
        @test get_edited_document(made) isa Image && get_edited_document(made).natural_size === nothing
        @test any(condition -> condition.name === :read_only, get_document_decoration(file).conditions)
    end

    @testset "a label and a text span draw the picture that a picture file holds" begin
        calls = Vector{Any}[]
        picture = ProjecturedPlatform.StyleModule._make_image("e.png", _make_image_test_source(calls, Ref((4, 3))))
        file = ImageFile("e.png", picture)
        @test get_shown_picture(file) === picture && get_shown_picture(picture) === picture
        @test get_shown_picture("text") == "text"
        pixels = getfield(picture, :pixels)
        label_images = _print_image_test_label(file)
        span_images = _print_image_test_span(file)
        @test length(label_images) == 1 && length(span_images) == 1
        @test getfield(label_images[1], :data) === pixels && getfield(span_images[1], :data) === pixels
        @test isempty(calls)
    end

    @testset "a load of the file keeps its picture and adds one to its read count" begin
        folder = mktempdir()
        path = joinpath(folder, "chart.png")
        write(path, "one")
        calls = Vector{Any}[]
        file = _make_image_test_file(path, calls, Ref((4, 3)))
        picture = get_edited_document(file)
        store = FileChangeStore()
        try
            watch_document_file!(file; store)
            write(path, "other bytes")
            @test _wait_for_image_test_change(store)
            @test drain_file_changes!(; store) == 1
            # The drain counts the change and reads nothing.
            @test get_file_disk_state(file).read_count == 1 && picture.read_count == 0
            _read_image_test_file!(file)
            @test get_edited_document(file) === picture && picture.read_count == 1
            @test get_file_disk_state(file).file_hash == hash(compute_file_stamp(path))
            @test isempty(calls)
            # The new input is read when a frame asks for the pixels.
            editor = _make_image_test_editor()
            run_with_evaluation_editor(() -> getfield(picture, :pixels)[], editor)
            start_background_cell_work!(editor)
            @test _wait_until_image_test_final(editor, getfield(picture, :pixels))
            @test calls == [[(path, 1)]]
            # A report with the same time and size changes no cell of the picture.
            FileChangeModule._mark_changed_files!(store, folder)
            @test drain_file_changes!(; store) == 0
            _read_image_test_file!(file)
            @test picture.read_count == 1 && get_file_disk_state(file).read_count == 1
            # F5 takes the hash of the time and the size, and adds one to the count.
            evaluate_operation(nothing, ReloadFileOperation(file))
            @test get_edited_document(file) === picture && picture.read_count == 2
            @test get_file_disk_state(file).file_hash == hash(compute_file_stamp(path))
            @test get_file_disk_state(file).file_hash != compute_file_text_hash(path)
            # A file that is gone loads the seed of its extension, and a picture of another path is not kept.
            rm(path)
            evaluate_operation(nothing, ReloadFileOperation(file))
            @test get_edited_document(file) isa DocumentNothing
            unwatch_document_file!(file; store)
        finally
            close_file_change_store!(store)
        end
    end

    @testset "a picture of another path replaces the picture" begin
        picture = Image("x.png")
        other = Image("y.png")
        @test replace_wrapped_document!(picture, other) === other && picture.read_count == 0
        @test replace_wrapped_document!(picture, Image("x.png")) === picture && picture.read_count == 1
    end

    @testset "a copy of a picture is a new picture of the same path that reads nothing" begin
        calls = Vector{Any}[]
        picture = ProjecturedPlatform.StyleModule._make_image("d.png", _make_image_test_source(calls, Ref((4, 3))))
        wait_for_cell!(getfield(picture, :pixels); editor = nothing)
        @test picture.natural_size == (4, 3) && length(calls) == 1
        # A copy gesture and a plain copy rebuild the document, here through a file and a label.
        for copied in (copy_document(picture), copy_document(ClipboardCopyPolicy(), picture),
                       get_edited_document(copy_document(ImageFile("d.png", picture))),
                       get_edited_document(copy_document(ClipboardCopyPolicy(), ImageFile("d.png", picture))))
            @test copied isa Image && copied !== picture && copied.filename == "d.png"
            @test copied.natural_size === nothing && copied.failure === nothing && copied.read_count == 0
            @test getfield(copied, :pixels) !== getfield(picture, :pixels)
            @test getfield(copied, :source)[] !== getfield(picture, :source)[]
        end
        # The copy reads through its own source and writes its own cells.
        copied = copy_document(Image(joinpath(mktempdir(), "gone.png")))
        @test wait_for_cell!(getfield(copied, :pixels); editor = nothing) isa Exception
        @test copied.failure isa Exception && picture.failure === nothing
        @test length(calls) == 1
    end

    @testset "a picture file opens in a tab, follows its file, and reads its file when it is drawn" begin
        folder = mktempdir()
        path = joinpath(folder, "chart.png")
        write(path, "one")
        editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                              backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                              appearance = false, settings = Settings(), file_change = true)
        try
            run_frame!(editor)
            store = get_session_file_change_store(; editor)
            # The open of the path is an `OpenFileOperation`, which opens a tab of the view of the file.
            tab = open_file!(path; editor)
            run_frame!(editor)
            file = find_open_file_document(path; editor)
            @test file isa ImageFile
            view = get_document(tab).content
            @test view isa FileView && view.file === file
            @test only(store.files).receiver === file
            picture = get_edited_document(file)
            @test picture isa Image && picture.read_count == 0
            # A new file at the path, a drain and frames: the file holds the same picture, one read more.
            write(path, "other bytes")
            @test _wait_for_image_test_change(store)
            @test drain_file_changes!(; store) == 1
            draw_view!(shown) = run_with_evaluation_editor(editor) do
                length(print_document(FileViewToWidget(), nothing, shown, nothing).output.children)
            end
            draw_view!(view)
            deadline = time() + 30
            while time() < deadline && picture.read_count < 1
                drain_operations!(editor)
                run_frame!(editor)
                sleep(0.02)
            end
            @test get_edited_document(file) === picture && picture.read_count == 1
            # A file that reads nothing yet holds the seed until a view of it is drawn.
            second_path = joinpath(folder, "b.png")
            write(second_path, "two")
            second = open_file_document!(second_path; editor)
            @test second isa ImageFile && get_edited_document(second) isa DocumentNothing
            second_view = make_file_view(second)
            draw_view!(second_view)
            deadline = time() + 30
            while time() < deadline && !(get_edited_document(second) isa Image)
                drain_operations!(editor)
                run_frame!(editor)
                sleep(0.02)
            end
            @test get_edited_document(second) isa Image && get_edited_document(second).filename == second_path
        finally
            foreach(step -> step(editor), editor.stop_steps)
        end
    end

    @testset "a zoom tab holds the picture file, reads it at its first draw and follows it" begin
        folder = mktempdir()
        path = joinpath(folder, "zoom.png")
        write(path, "one")
        editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                              backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                              appearance = false, settings = Settings(), file_change = true)
        painted = nothing
        step!() = (drain_operations!(editor); run_frame!(editor);
                   painted === nothing || _paint_image_test_place!(editor, painted); sleep(0.02))
        try
            # The window holds its tabs before the zoom tab opens.
            step!()
            store = get_session_file_change_store(; editor)
            # The file reads nothing until a place draws it, and only the zoom tab holds it.
            file = open_file_document!(path; editor)
            @test file isa ImageFile && get_edited_document(file) isa DocumentNothing
            zoom = WidgetTransformPane(file)
            @test get_edited_field(zoom) === :content
            tab = open_pane!(zoom; title = "Zoom", editor)
            step!()
            @test only(store.files).receiver === file
            # The draw of the zoom tab asks for the read: no view of the file draws it.
            deadline = time() + 30
            while time() < deadline && !(get_edited_document(file) isa Image)
                step!()
            end
            picture = get_edited_document(file)
            @test picture isa Image && picture.filename == path && picture.read_count == 0
            # A new file at the path and a drain reach the same picture, with no view of the file,
            # when a place draws it again.
            painted = _print_image_test_place(editor, WidgetTransformPane(file))
            write(path, "other bytes")
            @test _wait_for_image_test_change(store)
            @test drain_file_changes!(; store) == 1
            deadline = time() + 30
            while time() < deadline && picture.read_count < 1
                step!()
            end
            @test get_edited_document(file) === picture && picture.read_count == 1
            # The tab that holds the file is the zoom tab, and its close releases the file.
            @test get_document(open_file!(path; editor)) === get_document(tab)
            @test count(w -> w.receiver === file, store.files) == 1
            close_pane!(tab; editor)
            step!()
            @test isempty(store.files)
            @test find_open_file_document(path; editor) === nothing
        finally
            foreach(step -> step(editor), editor.stop_steps)
        end
    end

end
end # test_image
