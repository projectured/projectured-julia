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

    @testset "the size from the head of a file is the size of the decode" begin
        SDL = ProjecturedSDL.SdlModule.SimpleDirectMediaLayer.LibSDL2
        directory = mktempdir()
        little16(n) = UInt8[n & 0xff, (n >> 8) & 0xff]
        little32(n) = UInt8[n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]
        function check_agreement(path, expected)
            @test read_image_size(path) == expected
            @test read_image_size(path) == Int.(decode_image(path)[2:3])
        end
        # A PNG and a BMP that `write_image` writes.
        for extension in (".png", ".bmp")
            path = joinpath(directory, "chart" * extension)
            write_image(WidgetButton("Chart"), NaturalToGraphics(; measure = FontFileMeasure()), path; width = 40, height = 30)
            check_agreement(path, Int.(decode_image(path)[2:3]))
        end
        # A BMP stored top-down: its height is negative.
        path = joinpath(directory, "top-down.bmp")
        write(path, vcat(codeunits("BM"), little32(54 + 120), little32(0), little32(54), little32(40),
                         little32(7), little32(UInt32(-5 % UInt32)), little16(1), little16(24), zeros(UInt8, 24),
                         zeros(UInt8, 120)))
        check_agreement(path, (7, 5))
        # A JPEG of 7 by 5 that `IMG_SaveJPG` writes, with an EXIF segment of orientation 6 and two
        # more APP1 segments of 65 535 bytes after its SOI.
        path = joinpath(directory, "photo.jpg")
        surface = SDL.SDL_CreateRGBSurface(UInt32(0), Int32(7), Int32(5), Int32(32), UInt32(0x00ff0000),
                                           UInt32(0x0000ff00), UInt32(0x000000ff), UInt32(0xff000000))
        @test SDL.IMG_SaveJPG(surface, path, 90) == 0
        SDL.SDL_FreeSurface(surface)
        jpeg = read(path)
        exif = vcat(codeunits("Exif"), UInt8[0, 0], codeunits("MM"), UInt8[0, 42, 0, 0, 0, 8],
                    UInt8[0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0], UInt8[0, 0, 0, 0])
        app1(body) = vcat(UInt8[0xff, 0xe1, 0xff, 0xff], body, zeros(UInt8, 65533 - length(body)))
        write(path, vcat(jpeg[1:2], app1(exif), app1(UInt8[]), app1(UInt8[]), jpeg[3:end]))
        @test filesize(path) > 197_000
        check_agreement(path, (7, 5))
        # A GIF with a screen of 20 by 10 and a frame of 5 by 4 at (2, 3). Its data is a clear code
        # before every two pixels of one colour, so each code is 3 bits.
        codes = vcat([[4, 0, 0] for _ in 1:10]..., [5])
        bits = reduce(vcat, [[(code >> bit) & 1 for bit in 0:2] for code in codes])
        data = UInt8[sum(get(bits, 8 * byte + bit + 1, 0) << bit for bit in 0:7) for byte in 0:(cld(length(bits), 8) - 1)]
        path = joinpath(directory, "frame.gif")
        write(path, vcat(codeunits("GIF89a"), little16(20), little16(10), UInt8[0x80, 0, 0], UInt8[0, 0, 0, 255, 255, 255],
                         UInt8[0x2c], little16(2), little16(3), little16(5), little16(4), UInt8[0],
                         UInt8[2, length(data)], data, UInt8[0, 0x3b]))
        check_agreement(path, (5, 4))
    end
end
