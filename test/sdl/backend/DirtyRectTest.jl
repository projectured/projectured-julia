function test_dirty_rect()
@testset "dirty-rectangle analysis" begin

SDL = ProjecturedSdl   # the SDL backend module (provides SdlWindowResources + _compute_dirty_rect)

# A bare resource record is enough for `_compute_dirty_rect`: it only reads
# `width`/`height`/`dirty_bounds` and never touches the (null) renderer.
make_res() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", 800, 600, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), NTuple{4,Int}[])

@testset "detects an invalidated element and pads its bounds" begin
    # A canvas whose elements are produced by a computed thunk over `src`,
    # mirroring how the projection pipeline regenerates element vectors.
    src = Cell(10)
    cv = CellVector(@computation [GraphicsRect(src[], 20, 30, 40)])  # x=src, y=20, w=30, h=40
    canvas = GraphicsCanvas(cv, layout_none)
    res = make_res()

    # Frame 1: the computed element vector has never run → stale → dirty.
    # New bounds (10,20)-(40,60), padded by 2px.
    @test SDL._compute_dirty_rect(res, canvas) == (8, 18, 42, 62)

    # Frame 2: nothing changed → every cell is up to date → nothing to repaint.
    @test SDL._compute_dirty_rect(res, canvas) === nothing

    # Frame 3: move the rect. The write invalidates the computed elements cell;
    # the dirty rect must cover BOTH the old (x=10) and new (x=100) positions.
    src[] = 100
    @test SDL._compute_dirty_rect(res, canvas) == (8, 18, 132, 62)

    # And settles back to clean.
    @test SDL._compute_dirty_rect(res, canvas) === nothing
end

@testset "clamps to the window bounds" begin
    src = Cell(0)
    # A rect wider/taller than the window; padding must not push past edges.
    cv = CellVector(@computation [GraphicsRect(src[], src[], 2000, 2000)])
    canvas = GraphicsCanvas(cv, layout_none)
    res = make_res()
    @test SDL._compute_dirty_rect(res, canvas) == (0, 0, 800, 600)
end

@testset "an empty canvas is never dirty" begin
    res = make_res()
    @test SDL._compute_dirty_rect(res, GraphicsCanvas()) === nothing
end

@testset "ListNode: per-line edit vs. spine change" begin
    # Three stacked lines in a vertical, non-overlapping list — the structure
    # the text pipeline produces. The middle line's value is a computed cell so
    # editing `src` invalidates just that node (mirrors per-line regeneration).
    src = Cell(100)   # width of the middle line
    n1 = ListNode(GraphicsRect(0, 0, 50, 10))
    n2 = ListNode(GraphicsRect(0, 20, Int(src[]), 10))
    n3 = ListNode(GraphicsRect(0, 40, 50, 10))
    n1.next = n2; n2.prev = n1; n2.next = n3; n3.prev = n2
    set_cell_function!(getfield(n2, :value), () -> GraphicsRect(0, 20, Int(src[]), 10))
    canvas = GraphicsCanvas(n1; layout = layout_vertical, overlapping = false)
    res = make_res()

    # Only the middle line is stale → its box, padded. (0,20)-(100,30).
    @test SDL._compute_dirty_rect(res, canvas) == (0, 18, 102, 32)
    @test SDL._compute_dirty_rect(res, canvas) === nothing

    # Shrink the middle line; old (wide) ∪ new (narrow) must still clear the tail.
    src[] = 40
    @test SDL._compute_dirty_rect(res, canvas) == (0, 18, 102, 32)
    @test SDL._compute_dirty_rect(res, canvas) === nothing

    # A spine change (a `.next` pointer invalidated, as when a line is
    # inserted/removed) reflows everything below → dirty extends to the bottom
    # of the viewport (window height 600).
    set_cell_function!(getfield(n1, :next), () -> n2)
    d = SDL._compute_dirty_rect(res, canvas)
    @test d !== nothing
    @test d[2] == 0      # from the top of the affected list
    @test d[4] == 600    # down to the viewport bottom
    @test SDL._compute_dirty_rect(res, canvas) === nothing
end

@testset "nested line sub-canvases: per-line edit stays local" begin
    # Mirror TextToGraphics' per-line output: a top canvas (layout_none) whose
    # child is a vertical stack of one sub-canvas per line. Each line's elements
    # come from a computed cell; the line list and the stack are fixed vectors
    # (structural), so editing one line invalidates only that line's sub-canvas
    # and the dirty walk descends to repaint just that line.
    line_canvas(y, wcell) = GraphicsCanvas(
        Int32(0), Int32(y), Int32(0), Int32(0),
        CellVector(@computation [GraphicsRect(0, 0, Int(wcell[]), 18)]),
        layout_none, false, Cell(nothing))
    src3 = Cell(50)                       # width of line 3's rect
    l1 = line_canvas(0,  Cell(100))
    l2 = line_canvas(20, Cell(100))
    l3 = line_canvas(40, src3)
    stack = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                           CellVector(Cell[Cell(l1), Cell(l2), Cell(l3)]),
                           layout_vertical, false, Cell(nothing))
    top = GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
    res = make_res()

    # Seed every line's bounds, then settle.
    @test SDL._compute_dirty_rect(res, top) !== nothing
    @test SDL._compute_dirty_rect(res, top) === nothing

    # Editing the LAST line dirties only line 3 (y≈40..58, +2px pad) — not the
    # lines above and not the whole document.
    src3[] = 80
    d = SDL._compute_dirty_rect(res, top)
    @test d !== nothing
    @test d[2] == 38                      # top edge just above line 3
    @test d[4] == 60                      # bottom edge of line 3 — no reach into 1-2
    @test SDL._compute_dirty_rect(res, top) === nothing
end

end # testset
end # test_dirty_rect
