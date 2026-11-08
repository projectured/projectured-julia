# The pixels of an `Image` read from a real file with the SDL decoder, on a task
# of the editor after a frame in which a paint asked for them, with no video: a
# PNG that `write_image` wrote gives its size, a file of another size at the same
# path gives the new size after one more `read_count`, and a file with other pixels
# and the same size gives the new pixels, although the answer writes no cell.

function test_image_file_read()
    @testset "the pixels of a picture are read from a file on a task" begin
        directory = mktempdir()
        path = joinpath(directory, "chart.png")
        write_picture(width, height; label = "Chart") =
            write_image(WidgetButton(label), NaturalToGraphics(; measure = FontFileMeasure()), path; width, height)
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
        read_pixels() = ProjecturedKernel.ToolModule.run_with_evaluation_editor(() -> pixels[], editor)
        @test picture.natural_size === nothing
        @test read_in_frame!()
        @test picture.natural_size == (40, 30) && picture.failure === nothing
        # The same path with another size: one more read count reads the file again.
        write_picture(64, 48)
        picture.read_count = 1
        @test read_in_frame!()
        @test picture.natural_size == (64, 48)
        # The same path with the same size and other pixels: the answer writes no cell, and the
        # pixel cell answers the new bytes.
        before = copy(read_pixels()[1])
        runs = Ref(0)
        watcher = Cell(@computation (runs[] += 1; picture.natural_size))
        @test watcher[] == (64, 48) && runs[] == 1
        write_picture(64, 48; label = "Another chart with a longer label")
        picture.read_count = 2
        @test read_in_frame!()
        answer = read_pixels()
        @test answer[2:3] == (64, 48) && answer[1] != before
        @test picture.natural_size == (64, 48) && watcher[] == (64, 48) && runs[] == 1
        # A file that is gone fails as a value.
        rm(path)
        picture.read_count = 3
        @test read_in_frame!()
        @test picture.failure isa Exception
    end
end
