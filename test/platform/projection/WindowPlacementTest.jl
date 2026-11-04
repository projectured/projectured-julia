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

@testset "an anchored place goes below its box, flips above, and slides inside the area" begin
    screen = ScreenDocument(; display_areas = [(0, 0, 1200, 700)])
    window = WindowDocument(; id = :popup, style = :popup, width = 300, height = 200,
                              content = PrimitiveString("x"))
    place(anchor; keywords...) =
        (p = compute_anchored_place(WindowPlacementContext(screen, window, nothing), anchor; keywords...);
         (p.x, p.y))
    # Room below: the left edges are aligned, `gap` under the box.
    @test place((x = 10, y = 100, width = 50, height = 20); gap = 4) == (10, 124)
    # No room below: above the box; no room on the right: it slides left.
    @test place((x = 1000, y = 600, width = 100, height = 20); gap = 4) == (900, 396)
    # No room above either: it stays below and slides up inside the area.
    window.height = 650
    @test place((x = 10, y = 100, width = 50, height = 20); gap = 4) == (10, 50)
    window.height = 200
    # A point is a box of no size.
    @test place((x = 1100, y = 650, width = 0, height = 0)) == (900, 450)
    # The center of the box, inside the area.
    @test place((x = 0, y = 0, width = 1000, height = 600); side = :center) == (350, 200)
    @test place((x = 1100, y = 0, width = 400, height = 100); side = :center) == (900, 0)
    # The area is the one that holds the middle of the box.
    screen.display_areas = [(0, 0, 1000, 700), (1000, 0, 800, 600)]
    @test place((x = 1500, y = 550, width = 0, height = 0)) == (1500, 350)
    @test place((x = 900, y = 650, width = 0, height = 0)) == (700, 450)
    # A screen with no areas keeps the place on its side.
    screen.display_areas = NTuple{4,Int}[]
    @test place((x = 1000, y = 600, width = 100, height = 20); gap = 4) == (1000, 624)
    @test_throws ArgumentError place((x = 0, y = 0, width = 0, height = 0); side = :left)
end

@testset "an anchored place follows the size of its window and the areas" begin
    screen, _, _ = _make_placement_screen()
    screen.display_areas = [(0, 0, 1200, 700)]
    anchor = (x = 1000, y = 600, width = 100, height = 20)
    push!(screen.windows, WindowDocument(; id = :popup, style = :popup, width = 100, height = 200,
                                           maximum_size = (300, 400),
                                           placement = context -> compute_anchored_place(context, anchor;
                                                                                         gap = 4),
                                           content = PrimitiveString("x")))
    popup = print_document(_make_placement_projection(), screen).output.windows[2]
    @test (popup.x, popup.y) == (1000, 396)
    # The backend writes the size that it fits to the content, and the place
    # follows it in the same frame.
    popup.height = 50
    @test (popup.x, popup.y) == (1000, 624)
    popup.width = 300
    @test (popup.x, popup.y) == (900, 624)
    screen.display_areas = [(0, 0, 2000, 1000)]
    @test (popup.x, popup.y) == (1000, 624)
end

@testset "a fixed placement answers its place whatever the screen holds" begin
    placement = make_fixed_placement(30, 40; maximum_size = (200, 100))
    @test placement(nothing) == WindowPlace(30, 40; maximum_size = (200, 100))
    @test has_window_frame(WindowDocument(; style = :dialog, content = PrimitiveString("x")))
    @test has_window_frame(WindowDocument(; style = :floating, content = PrimitiveString("x")))
    @test !has_window_frame(WindowDocument(; style = :popup, content = PrimitiveString("x")))
    @test !has_window_frame(WindowDocument(; style = :tooltip, content = PrimitiveString("x")))
end

@testset "a person resizes a placed window with a frame, and it stays where it stands" begin
    screen, main, _ = _make_placement_screen()
    push!(screen.windows, WindowDocument(; id = :dialog, style = :dialog, width = 300, height = 200,
                                           placement = context -> (box = find_window_part_box(context,
                                                                       @reference(screen, windows[1].content));
                                                                   box === nothing ? nothing :
                                                                   compute_anchored_place(context, box;
                                                                                          side = :center)),
                                           content = PrimitiveString("x")))
    projection = _make_placement_projection()
    iomap = print_document(projection, screen)
    dialog = iomap.output.windows[2]
    # The main window is 1000 by 600 at (100, 50).
    @test (dialog.x, dialog.y) == (450, 250)
    answer = read_intent(projection, nothing, Intent(WindowInput(:dialog, WindowResize(400, 300; time = 0.0))),
                         iomap)
    evaluate_operation((; document = screen), answer.operation)
    @test (dialog.width, dialog.height) == (400, 300)
    @test (dialog.x, dialog.y) == (450, 250)
    main.x = 300
    @test (dialog.x, dialog.y) == (450, 250)
    # A popup has no frame, so a resize keeps its placement.
    push!(screen.windows, WindowDocument(; id = :popup, style = :popup, width = 100, height = 50,
                                           placement = context -> WindowPlace(Int(context.window.width), 7),
                                           content = PrimitiveString("x")))
    popup = iomap.output.windows[3]
    answer = read_intent(projection, nothing, Intent(WindowInput(:popup, WindowResize(120, 50; time = 0.0))),
                         iomap)
    evaluate_operation((; document = screen), answer.operation)
    @test (popup.x, popup.y) == (120, 7)
end

@testset "a file keeps no placement" begin
    window = WindowDocument(; id = :list, placement = context -> WindowPlace(1, 2),
                              content = PrimitiveString("x"))
    @test :placement ∉ first.(last(pred_arguments(window)))
end

end
end # test_window_placement
