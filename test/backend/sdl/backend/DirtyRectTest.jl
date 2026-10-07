function test_dirty_rect()
@testset "dirty-rectangle analysis" begin

SDL = ProjecturedSDL.SdlModule   # the SDL backend slice (provides SdlWindowResources + _compute_dirty_rect)

# A bare resource record is enough for `_compute_dirty_rect`: it only reads
# `width`/`height`/`ratio`/`dirty_bounds`/`painted` and never touches the (null)
# renderer.
make_res() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", 800, 600, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), Vector{NTuple{4,Int}}[])

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
    set_cell_computation!(getfield(n2, :value), () -> GraphicsRect(0, 20, Int(src[]), 10))
    canvas = GraphicsCanvas(n1; layout = layout_vertical, overlapping = false)
    res = make_res()

    # A list that was never painted is painted as a reflow: every line it shows,
    # down to the viewport bottom (window height 600).
    @test SDL._compute_dirty_rect(res, canvas) == (0, 0, 102, 600)
    @test SDL._compute_dirty_rect(res, canvas) === nothing

    # Shrink the middle line; old (wide) ∪ new (narrow) must still clear the tail.
    src[] = 40
    @test SDL._compute_dirty_rect(res, canvas) == (0, 18, 102, 32)
    @test SDL._compute_dirty_rect(res, canvas) === nothing

    # A spine change (a `.next` pointer invalidated, as when a line is
    # inserted/removed) reflows everything below → dirty extends to the bottom
    # of the viewport (window height 600).
    set_cell_computation!(getfield(n1, :next), () -> n2)
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

# Two paragraphs in a vertical stack, as a text or a page draws them: the first
# lays out from `layout`, and the second sits below it at a `y` computed from the
# height of the first. An edit of the first makes that `y` stale, because
# propagation is write-driven, whether or not the height changed.
function make_two_paragraphs(layout::Cell)
    first = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, layout[].w, layout[].h)]))
    second = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 100, 18))]);
                            y = Cell(@computation Int32(layout[].h + 2)))
    stack = GraphicsCanvas(CellVector(Cell[Cell(first), Cell(second)]);
                           layout = layout_vertical, overlapping = false)
    GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
end

@testset "a paragraph below an edit that keeps its place is not repainted" begin
    size = Cell((w = 100, h = 18))
    top = make_two_paragraphs(Cell(@computation size[]))
    res = make_res()
    @test SDL._compute_dirty_rect(res, top) !== nothing
    @test SDL._compute_dirty_rect(res, top) === nothing

    # The first paragraph gets narrower and keeps its height: the `y` of the
    # second is stale but computes the same place, so only the first repaints —
    # its old extent included.
    size[] = (w = 60, h = 18)
    @test SDL._compute_dirty_rect(res, top) == (0, 0, 102, 20)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a paragraph that moves repaints its old and its new place" begin
    size = Cell((w = 100, h = 18))
    top = make_two_paragraphs(Cell(@computation size[]))
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing

    # The first paragraph grows by one line and pushes the second from y=20 to
    # y=40: the rectangle reaches the bottom of the second at its new place.
    size[] = (w = 100, h = 38)
    @test SDL._compute_dirty_rect(res, top) == (0, 0, 102, 60)
    @test SDL._compute_dirty_rect(res, top) === nothing

    # And back: it clears the rows the second paragraph leaves (y 40..58).
    size[] = (w = 100, h = 18)
    @test SDL._compute_dirty_rect(res, top) == (0, 0, 102, 60)
end

@testset "the first change after the first paint clears what was painted" begin
    # The first paint paints the whole tree as one unit. It must still record the
    # extent of each canvas and leaf inside it, or the first change of one of
    # them could not clear the pixels it no longer covers.
    width = Cell(300)
    line = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, width[], 18)]); y = 20)
    caret = GraphicsRect(10, 20, 2, 18)
    caret_x = Cell(10)
    set_cell_computation!(getfield(caret, :x), () -> Int32(caret_x[]))
    top = GraphicsCanvas(CellVector(Cell[Cell(line), Cell(caret)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing

    # The line shrinks from 300 to 20: its old width is cleared.
    width[] = 20
    @test SDL._compute_dirty_rect(res, top) == (0, 18, 302, 40)

    # The caret moves from x=10 to x=200: its old place is cleared too.
    caret_x[] = 200
    @test SDL._compute_dirty_rect(res, top) == (8, 18, 204, 40)
end

@testset "a paint records only what the render reaches" begin
    # A vertical stack stops where the window ends, and so does what a paint
    # records: a paragraph below the window is not laid out to be recorded.
    below_width = Cell(100)
    shown = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 100, 18))]))
    below = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, below_width[], 18)]); y = 700)
    stack = GraphicsCanvas(CellVector(Cell[Cell(shown), Cell(below)]);
                           layout = layout_vertical, overlapping = false)
    top = GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
    res = make_res()
    @test SDL._compute_dirty_rect(res, top) == (0, 0, 102, 20)
    @test !is_cell_up_to_date(getfield(getfield(below, :elements)[], :elements))
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a list inside a canvas that scrolls moves with it" begin
    # A list has no bounds of its own; a paint of the canvas around it still
    # records what the list draws, so the scroll clears the old place.
    n1 = ListNode(GraphicsRect(0, 0, 50, 10))
    n2 = ListNode(GraphicsRect(0, 20, 50, 10))
    n1.next = n2; n2.prev = n1
    list = GraphicsCanvas(n1; layout = layout_vertical, overlapping = false)
    scroll = Cell(0)
    pane = GraphicsCanvas(CellVector(Cell[Cell(list)]); y = Cell(@computation Int32(100 - scroll[])))
    top = GraphicsCanvas(CellVector(Cell[Cell(pane)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing

    # The list moves from y 100..130 to y 80..110.
    scroll[] = 20
    @test SDL._compute_dirty_rect(res, top) == (0, 78, 52, 132)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a nested stack is walked as far as it is drawn" begin
    # The render passes the bottom of the window to a nested canvas unchanged,
    # so the second paragraph at y = 320 is drawn, and its change is seen.
    width = Cell(40)
    first = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 50, 10))]))
    second = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, width[], 10)]); y = 20)
    nested = GraphicsCanvas(CellVector(Cell[Cell(first), Cell(second)]); y = 300,
                            layout = layout_vertical, overlapping = false)
    top = GraphicsCanvas(CellVector(Cell[Cell(nested)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    width[] = 80
    @test SDL._compute_dirty_rect(res, top) == (0, 318, 82, 332)
end

@testset "a graphic drawn at two places keeps each place" begin
    # Two regions show one element list, as the regions of a table do.
    # Each place is its own record, so neither looks moved on an idle frame.
    inner = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 50, 10))]))
    shared = CellVector(Cell[Cell(inner)])
    top = GraphicsCanvas(CellVector(Cell[Cell(GraphicsCanvas(shared)),
                                         Cell(GraphicsCanvas(shared; x = 200))]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a graphic that leaves the view clears where it was" begin
    # The second paragraph is pushed from y = 580 to y = 700, below the window.
    # The render no longer reaches it, and its old rows 580..598 are cleared.
    leaving_y = Cell(580)
    shown = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 100, 18))]))
    leaving = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 100, 18))]);
                             y = Cell(@computation Int32(leaving_y[])))
    stack = GraphicsCanvas(CellVector(Cell[Cell(shown), Cell(leaving)]);
                           layout = layout_vertical, overlapping = false)
    top = GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    leaving_y[] = 700
    @test SDL._compute_dirty_rect(res, top) == (0, 578, 102, 600)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a list that moves left clears its old right edge" begin
    # A gutter beside the text gets narrower: the list moves from x = 30 to 20.
    gutter = Cell(30)
    n1 = ListNode(GraphicsRect(0, 0, 100, 10))
    list = GraphicsCanvas(n1; x = Cell(@computation Int32(gutter[])),
                          layout = layout_vertical, overlapping = false)
    top = GraphicsCanvas(CellVector(Cell[Cell(list)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    gutter[] = 20
    d = SDL._compute_dirty_rect(res, top)
    @test d[1] == 18 && d[3] == 132    # the old right edge at x = 130, padded
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a paragraph whose line grew clears the whole line when it moves" begin
    # The line repaints alone when it grows; the record of the paragraph around it
    # must still grow with it, or a later move of the paragraph clears the old,
    # narrower extent only.
    wide = Cell(100)
    line = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, wide[], 18)]))
    pos = Cell(100)
    para = GraphicsCanvas(CellVector(Cell[Cell(line)]); y = Cell(@computation Int32(pos[])))
    top = GraphicsCanvas(CellVector(Cell[Cell(para)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    wide[] = 300
    @test SDL._compute_dirty_rect(res, top) == (0, 98, 302, 120)
    pos[] = 200
    @test SDL._compute_dirty_rect(res, top) == (0, 98, 302, 220)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a leaf that moves along its stack repaints" begin
    # The early-stop reads the place of a leaf; its cells are tested before that.
    leaf_y = Cell(20)
    leaf = GraphicsRect(0, 20, 50, 10)
    set_cell_computation!(getfield(leaf, :y), () -> Int32(leaf_y[]))
    stack = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 50, 10)), Cell(leaf)]);
                           layout = layout_vertical, overlapping = false)
    top = GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    leaf_y[] = 40
    @test SDL._compute_dirty_rect(res, top) == (0, 18, 52, 52)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "two changes far apart are two rectangles, not the box that spans them" begin
    # A paragraph at the top and a status line at the bottom change in one frame.
    top_width = Cell(100)
    bottom_width = Cell(100)
    upper = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, top_width[], 18)]))
    lower = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, bottom_width[], 18)]); y = 500)
    top = GraphicsCanvas(CellVector(Cell[Cell(upper), Cell(lower)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test isempty(SDL._compute_dirty_region(res, top))
    top_width[] = 60
    bottom_width[] = 80
    @test sort(SDL._compute_dirty_region(res, top)) == [(0, 0, 102, 20), (0, 498, 102, 520)]
end

@testset "a rectangle that another covers is dropped" begin
    # The caret moves inside the line that changes: the line's box holds both
    # places of the caret, so the region is that one box.
    width = Cell(300)
    line = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, width[], 18)]); y = 20)
    caret = GraphicsRect(10, 20, 2, 18)
    caret_x = Cell(10)
    set_cell_computation!(getfield(caret, :x), () -> Int32(caret_x[]))
    top = GraphicsCanvas(CellVector(Cell[Cell(line), Cell(caret)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    width[] = 200
    caret_x[] = 150
    @test SDL._compute_dirty_region(res, top) == [(0, 18, 302, 40)]
end

@testset "a recording does not hide a change the walk has still to test" begin
    # A box first in the list measures the canvas after it, as the box of a
    # composite measures its children: the size of a canvas reads every graphic
    # in it. The canvas shrinks from 80 to 40; its old width is still cleared.
    width = Cell(80)
    child = GraphicsCanvas(CellVector(@computation [GraphicsRect(0, 0, width[], 10)]); y = 100)
    box = GraphicsCanvas(CellVector(@computation (get_graphics_size(child); Any[])))
    top = GraphicsCanvas(CellVector(Cell[Cell(box), Cell(child)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test isempty(SDL._compute_dirty_region(res, top))
    width[] = 40
    @test SDL._compute_dirty_region(res, top) == [(0, 98, 82, 112)]
end

@testset "the outline of rects that overlap is one shape" begin
    # Two boxes that overlap: each keeps only the parts of its edges that lie on
    # the boundary of their union, so no line is drawn inside it.
    bars = SDL._compute_union_outline([(0, 0, 10, 10), (5, 5, 15, 15)], 1)
    @test sort(bars) == sort([(0, 0, 10, 1), (0, 9, 5, 10), (0, 0, 1, 10), (9, 0, 10, 5),
                              (10, 5, 15, 6), (5, 14, 15, 15), (5, 10, 6, 15), (14, 5, 15, 15)])
    # A box inside another adds nothing to the outline.
    @test sort(SDL._compute_union_outline([(0, 0, 20, 20), (5, 5, 10, 10)], 1)) ==
          sort([(0, 0, 20, 1), (0, 19, 20, 20), (0, 0, 1, 20), (19, 0, 20, 20)])
    # Two boxes that touch are outlined as one: the edges they share are inside.
    @test sort(SDL._compute_union_outline([(0, 0, 10, 10), (0, 10, 10, 20)], 1)) ==
          sort([(0, 0, 10, 1), (0, 19, 10, 20), (0, 0, 1, 10), (9, 0, 10, 10),
                (0, 10, 1, 20), (9, 10, 10, 20)])
end

@testset "a scaled viewport repaints its box when its content moves" begin
    offset = Cell(0)
    content = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 50, 10))]);
                             y = Cell(@computation Int32(offset[])))
    viewport = GraphicsViewport(10, 10, 200, 100, content; transform = make_affine_scale(2))
    top = GraphicsCanvas(CellVector(Cell[Cell(viewport)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    offset[] = 5
    @test SDL._compute_dirty_rect(res, top) == (8, 8, 212, 112)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a viewport repaints when its geometry changes, not when it is computed again" begin
    # A pane whose box is computed from the window, holding a canvas that does
    # not change. Writing the window cell makes the box stale.
    window = Cell(400)
    content = GraphicsCanvas(CellVector(Cell[Cell(GraphicsRect(0, 0, 50, 10))]))
    viewport = GraphicsViewport(Cell(@computation Int32(window[] ÷ 4)), Int32(10),
                                Cell(@computation Int32(window[] ÷ 2)), Int32(100), content)
    top = GraphicsCanvas(CellVector(Cell[Cell(viewport)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing

    # The same width again: the box is computed again to the same place.
    window[] = 400
    @test SDL._compute_dirty_rect(res, top) === nothing

    # A wider window moves the pane from x=100 to x=150: the old box and the new.
    window[] = 600
    @test SDL._compute_dirty_rect(res, top) == (98, 8, 452, 112)
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a new element list paints what it adds and moves, and clears what it drops" begin
    # Rows in a vertical stack, kept by the list that holds them, as the rows of
    # a tree: a folder opens under the first row, so the two rows below it move
    # down. The first row keeps its place and is not painted.
    tops = Dict(:a => Cell(0), :b => Cell(20), :c => Cell(40))
    make_row(name) = GraphicsRect(0, () -> tops[name][], 100, 18)
    a, b, c = make_row(:a), make_row(:b), make_row(:c)
    opened = GraphicsRect(20, 20, 80, 18)
    is_open = Cell(false)
    stack = GraphicsCanvas(CellVector(@computation is_open[] ? Any[a, opened, b, c] : Any[a, b, c]);
                           layout = layout_vertical, overlapping = false)
    res = make_res()
    SDL._compute_dirty_rect(res, stack)
    @test SDL._compute_dirty_rect(res, stack) === nothing

    is_open[] = true
    tops[:b][] = 40
    tops[:c][] = 60
    @test SDL._compute_dirty_rect(res, stack) == (0, 18, 102, 80)
    @test SDL._compute_dirty_rect(res, stack) === nothing

    # The folder closes: the row of the folder is cleared, and the rows below
    # move up again.
    is_open[] = false
    tops[:b][] = 20
    tops[:c][] = 40
    @test SDL._compute_dirty_rect(res, stack) == (0, 18, 102, 80)
    @test SDL._compute_dirty_rect(res, stack) === nothing
end

@testset "a stale leaf that draws what it drew is not painted" begin
    # The chevron of a folder that did not toggle reads the set of open folders:
    # its cell is computed again, to the same value.
    level = Cell(1)
    mark = GraphicsRect(0, 0, 10, 10; color = color_black)
    set_cell_computation!(getfield(mark, :color), () -> level[] > 5 ? color_red : color_black)
    top = GraphicsCanvas(CellVector(Cell[Cell(mark)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    level[] = 2
    @test SDL._compute_dirty_rect(res, top) === nothing
    level[] = 9
    @test SDL._compute_dirty_rect(res, top) == (0, 0, 12, 12)
end

@testset "a rectangle that draws nothing gives no rectangle" begin
    # The hit target of a widget: a transparent rectangle that grows with it.
    height = Cell(100)
    target = GraphicsRect(Int32(0), Int32(0), Int32(200), Cell(@computation Int32(height[]));
                          color = color_transparent)
    top = GraphicsCanvas(CellVector(Cell[Cell(target)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    height[] = 300
    @test SDL._compute_dirty_rect(res, top) === nothing
end

@testset "a viewport inside a new list gives its rectangles to the viewport around it" begin
    # A pane inside a slot of a layout, which clips each slot with a viewport: the
    # list around the pane changes in the frame where a mark in the pane does.
    k = Cell(1)
    mark = GraphicsRect(10, 10, 20, 20; color = color_black)
    set_cell_computation!(getfield(mark, :color), () -> k[] > 1 ? color_red : color_black)
    pane = GraphicsViewport(Int32(0), Int32(0), Int32(100), Int32(100),
                            GraphicsCanvas(CellVector(Cell[Cell(mark)]), layout_none))
    extra = Cell(false)
    other = GraphicsRect(200, 10, 20, 20; color = color_black)
    slots = GraphicsCanvas(CellVector(@computation extra[] ? Any[pane, other] : Any[pane]), layout_none)
    top = GraphicsCanvas(CellVector(Cell[Cell(GraphicsViewport(Int32(0), Int32(0), Int32(400),
                                                                Int32(300), slots))]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    @test SDL._compute_dirty_rect(res, top) === nothing
    extra[] = true
    k[] = 2
    @test sort(SDL._compute_dirty_region(res, top)) == [(8, 8, 32, 32), (198, 8, 222, 32)]
end

@testset "a container records its bounds after a new list inside it" begin
    # The list inside grows from one row to three; later the container moves, and
    # the old place of all three rows is cleared.
    n = Cell(1)
    rows = [GraphicsRect(0, 20 * (i - 1), 100, 18) for i in 1:3]
    stack = GraphicsCanvas(CellVector(@computation Any[rows[i] for i in 1:n[]]);
                           layout = layout_vertical, overlapping = false)
    shift = Cell(0)
    holder = GraphicsCanvas(CellVector(Cell[Cell(stack)]), layout_none)
    set_cell_computation!(getfield(holder, :x), () -> Int32(shift[]))
    top = GraphicsCanvas(CellVector(Cell[Cell(holder)]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    n[] = 3
    @test SDL._compute_dirty_rect(res, top) == (0, 18, 102, 60)
    shift[] = 200
    @test sort(SDL._compute_dirty_region(res, top)) == [(0, 0, 102, 60), (198, 0, 302, 60)]
end

@testset "a new order of elements that overlap paints them" begin
    # A card raised over the one it overlaps: the same elements, in another order.
    a = GraphicsRect(0, 0, 50, 50; color = color_red)
    b = GraphicsRect(25, 25, 50, 50; color = color_black)
    front = Cell(false)
    top = GraphicsCanvas(CellVector(@computation front[] ? Any[b, a] : Any[a, b]), layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, top)
    front[] = true
    @test sort(SDL._compute_dirty_region(res, top)) == [(0, 0, 52, 52), (23, 23, 77, 77)]
end

@testset "a list that a layout read before the walk clears what it no longer holds" begin
    # The badges of a zone of a pivot, where a drag adds the badge of the drop and
    # its end takes it out. The size of a canvas reads its elements, so the layout
    # around the row computes the new list, and the walk finds no stale cell.
    a = GraphicsRect(0, 0, 50, 20)
    b = GraphicsRect(60, 0, 50, 20)
    c = GraphicsRect(60, 0, 30, 20)
    step = Cell(1)
    row = GraphicsCanvas(CellVector(@computation step[] == 1 ? Any[a, b] : step[] == 2 ? Any[a, c] : Any[a]),
                         layout_none)
    res = make_res()
    SDL._compute_dirty_rect(res, row)
    @test SDL._compute_dirty_rect(res, row) === nothing
    # A smaller graphic in the place of the second: the second is cleared.
    step[] = 2
    length(row.elements)
    @test SDL._compute_dirty_rect(res, row) == (58, 0, 112, 22)
    # The same elements give no rectangle.
    length(row.elements)
    @test SDL._compute_dirty_rect(res, row) === nothing
    # The last element leaves the list.
    step[] = 3
    length(row.elements)
    @test SDL._compute_dirty_rect(res, row) == (58, 0, 92, 22)
end

@testset "a leaf has a signature only when its hash follows what it draws" begin
    @test SDL._compute_leaf_signature(GraphicsRect(0, 0, 10, 10; color = color_red)) !== nothing
    @test SDL._compute_leaf_signature(GraphicsText("a", 0, 0; font = StyleFont("Ubuntu", 20))) !== nothing
    # `hash` reads a sample of a large array, so a change in place could keep it.
    @test SDL._compute_leaf_signature(GraphicsImage(0, 0, 100, 100, zeros(UInt8, 40_000))) === nothing
    @test SDL._compute_leaf_signature(GraphicsImage(0, 0, 10, 10, zeros(UInt8, 400))) !== nothing
end

end # testset
end # test_dirty_rect
