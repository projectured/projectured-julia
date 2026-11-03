# A window that a placement function places: the screen computes its place from
# the printed screen, and the place follows what the function reads.

function test_window_placement()
@testset "a placement places a window" begin

_make_placement_projection() = RecursiveProjection(TypeDispatchingProjection(
    ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
    WindowDocument => ScreenToScreen(),
    CellVector     => CopyingProjection(),
    Any            => IdentityProjection()))

# A main window at (100, 50) whose content holds one part at (20, 30), 800 wide.
function _make_placement_screen()
    part = GraphicsCanvas(CellVector(); x = 20, y = 30, w = 800, h = 400)
    main = WindowDocument(; id = :main, x = 100, y = 50, width = 1000, height = 600,
                            content = GraphicsCanvas(CellVector(Cell[Cell(part)]); w = 1000, h = 600))
    screen = ScreenDocument([main])
    (screen, main, part)
end

@testset "the top placement stands at the top center of the part, and follows it" begin
    screen, main, part = _make_placement_screen()
    placement = make_part_top_placement(@reference(screen, windows[1].content.elements[1]);
                                        width_share = 0.5, minimum_width = 200,
                                        maximum_height = 300, gap = 8)
    push!(screen.windows, WindowDocument(; id = :list, style = :popup, placement,
                                           content = PrimitiveString("x")))
    output = print_document(_make_placement_projection(), screen).output
    list = output.windows[2]
    # The part is at (120, 80) on the screen and 800 wide: the list is 400 wide,
    # in the middle of it, 8 below its top edge.
    @test (list.x, list.y) == (320, 88)
    @test list.minimum_size == (400, 0)
    @test list.maximum_size == (400, 300)
    @test is_window_placed(list)
    # A move of the main window moves the list.
    main.x = 300
    @test (list.x, list.y) == (520, 88)
    # A part that grows makes the list wider, and keeps it in the middle.
    part.w = 1000
    @test list.maximum_size == (500, 300)
    @test (list.x, list.y) == (570, 88)
end

@testset "a window with no placement shares its place with the input" begin
    screen, main, _ = _make_placement_screen()
    output = print_document(_make_placement_projection(), screen).output
    @test !is_window_placed(output.windows[1])
    main.x = 7
    @test output.windows[1].x == 7
end

@testset "a placement that answers nothing leaves the place of the window" begin
    screen, _, _ = _make_placement_screen()
    push!(screen.windows, WindowDocument(; id = :list, x = 11, y = 12, maximum_size = (90, 80),
                                           placement = context -> nothing,
                                           content = PrimitiveString("x")))
    list = print_document(_make_placement_projection(), screen).output.windows[2]
    @test (list.x, list.y) == (11, 12)
    @test list.maximum_size == (90, 80)
end

@testset "a window that gains a placement is a new window" begin
    screen, _, _ = _make_placement_screen()
    editor = (; document = screen)
    evaluate_operation(editor, OpenWindowOperation(; id = :list, x = 5, y = 6, style = :popup,
                                                     content = PrimitiveString("x")))
    plain = screen.windows[2]
    @test !is_window_placed(plain)
    evaluate_operation(editor, OpenWindowOperation(; id = :list, style = :popup,
                                                     placement = context -> WindowPlace(40, 41),
                                                     content = PrimitiveString("y")))
    @test length(screen.windows) == 2
    @test screen.windows[2] !== plain
    @test is_window_placed(screen.windows[2])
    list = print_document(_make_placement_projection(), screen).output.windows[2]
    @test (list.x, list.y) == (40, 41)
end

@testset "a file keeps no placement" begin
    window = WindowDocument(; id = :list, placement = context -> WindowPlace(1, 2),
                              content = PrimitiveString("x"))
    @test :placement ∉ first.(last(pred_arguments(window)))
end

end
end # test_window_placement
