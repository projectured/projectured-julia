# The pixels of an `Image` read from a real file with the SDL decoder, on a task
# of the editor after a frame in which a paint asked for them, with no video: a
# PNG that `write_image` wrote gives its size, and a file of another size at the
# same path gives the new size after one more `read_count`.

function test_image_file_read()
    @testset "the pixels of a picture are read from a file on a task" begin
        directory = mktempdir()
        path = joinpath(directory, "chart.png")
        write_picture(width, height) = write_image(WidgetButton("Chart"), NaturalToGraphics(; measure = FontFileMeasure()),
                                                   path; width, height)
        write_picture(40, 30)
        picture = Image(path)
        label = print_document(RecursiveProjection(TypeDispatchingProjection(
                                   WidgetToGraphics(; measure = FontFileMeasure()).dispatch)),
                               nothing, WidgetLabel(picture), PrinterContext()).output
        image = only(filter(element -> element isa GraphicsImage, label.elements))
        editor = Editor(WidgetLabel(picture), NaturalToGraphics(; measure = FontFileMeasure());
                        backend = SdlBackend(), devices = Device[])
        pixels = getfield(picture, :pixels)
        function read_in_frame!()
            ProjecturedKernel.ToolModule.run_with_evaluation_editor(() -> image.data, editor)
            EditorModule.start_background_cell_work!(editor)
            deadline = time() + 20
            while time() < deadline
                EditorModule.drain_operations!(editor)
                ProjecturedKernel.ToolModule.run_with_evaluation_editor(() -> pixels[], editor)
                is_cell_provisional(pixels) || return true
                sleep(0.01)
            end
            false
        end
        @test picture.natural_size === nothing
        @test read_in_frame!()
        @test picture.natural_size == (40, 30) && picture.failure === nothing
        # The same path with another size: one more read count reads the file again.
        write_picture(64, 48)
        picture.read_count = 1
        @test read_in_frame!()
        @test picture.natural_size == (64, 48)
        # A file that is gone fails as a value.
        rm(path)
        picture.read_count = 2
        @test read_in_frame!()
        @test picture.failure isa Exception
    end
end
