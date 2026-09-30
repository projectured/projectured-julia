# What a window carries through the screen, and what a window that fits its
# content says. The size itself is given by a backend, which has the printed
# canvas; this suite holds the document half.

function test_window_fit()
@testset "a window says its bounds" begin

@testset "the mirror keeps what the window says about itself" begin
    # The screen mirrors every window, and the mirror is built by keyword: a
    # field added to WindowDocument would shift a positional list, and the size
    # and the position are all `Int`, so a shifted argument would pass unseen.
    input = WindowDocument(; id = :mirror_test, title = "mirror", x = 12, y = 34,
                             width = 300, height = 200,
                             minimum_size = (120, 32), maximum_size = (560, 400),
                             style = :tooltip, auto_dismiss = true,
                             content = PrimitiveString("x"))
    screen = ScreenDocument([input])
    projection = RecursiveProjection(TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        Any            => IdentityProjection()))
    output = print_document(projection, screen).output
    mirror = output.windows[1]
    @test mirror.id === :mirror_test
    @test mirror.title == "mirror"
    @test (mirror.x, mirror.y) == (12, 34)
    @test (mirror.width, mirror.height) == (300, 200)
    @test mirror.minimum_size == (120, 32)
    @test mirror.maximum_size == (560, 400)
    @test mirror.style === :tooltip
    @test mirror.auto_dismiss
end

@testset "a window opened without bounds keeps its size" begin
    # Every window that exists today opens without them, and a maximum of
    # (0, 0) is what says "this window has a size of its own".
    operation = OpenWindowOperation(; id = :plain, width = 420, height = 120,
                                      content = PrimitiveString("x"))
    @test operation.minimum_size == (0, 0)
    @test operation.maximum_size == (0, 0)
    @test (operation.width, operation.height) == (420, 120)
end

@testset "a window saved before the bounds still loads" begin
    loaded = parse_pred_text("WindowDocument(\n" *
                             "    id = :saved,\n" *
                             "    title = \"saved\",\n" *
                             "    x = 1,\n" *
                             "    y = 2,\n" *
                             "    width = 300,\n" *
                             "    height = 200,\n" *
                             "    content = PrimitiveString(\"x\"),\n)")
    @test loaded isa WindowDocument
    @test (loaded.width, loaded.height) == (300, 200)
    @test loaded.minimum_size == (0, 0)
    @test loaded.maximum_size == (0, 0)
end

end
end # test_window_fit
