# A partial paint repaints the rectangles of the dirty walk. Its pixels are the
# pixels of a full paint of the same frame: also where the ink of a glyph reaches
# past the box of its text, where elements with alpha overlap, where two
# rectangles overlap, in a list of nodes, and inside a viewport with a scale.
function test_partial_paint()
@testset "a partial paint" begin

SDL = ProjecturedSDL.SdlModule
@assert SDL.TTF_Init() == 0   # a text measures with the fonts of SDL_ttf
width, height = 400, 300
background = (0xff, 0xff, 0xff, 0xff)
black = StyleColor(0.0, 0.0, 0.0, 1.0)
translucent = StyleColor(0.0, 0.0, 1.0, 0.5)
font = StyleFont("DejaVu Sans", 12)
large = StyleFont("DejaVu Sans", 48)

# The bytes of the surface of `off`.
function read_pixels(off)
    surface = unsafe_load(off.surface)
    copy(unsafe_wrap(Array, Ptr{UInt8}(surface.pixels), Int(surface.pitch) * Int(surface.h)))
end

# Paint `canvas` by the rectangles of the dirty walk into one renderer, and in full
# into another: once before the changes, and once after each of them. Answer the
# frames whose pixels differ; frame 1 is the paint before the changes.
function find_differing_frames(canvas, changes)
    partial = SDL.open_offscreen_renderer(width, height; supersample = 1)
    full = SDL.open_offscreen_renderer(width, height; supersample = 1)
    differing = Int[]
    try
        state = SDL.make_offscreen_paint_state(partial)
        for (frame, change!) in enumerate(Any[() -> nothing; changes])
            change!()
            SDL.render_offscreen_changes!(partial, state, canvas; background)
            SDL._render_canvas_offscreen!(full, canvas, width, height, background)
            read_pixels(partial) == read_pixels(full) || push!(differing, frame)
        end
    finally
        SDL.close_offscreen_renderer(partial)
        SDL.close_offscreen_renderer(full)
    end
    differing
end

# The changes that write each of `values` into `cell`, one in each frame.
make_writes(cell, values) = Any[() -> (cell[] = value) for value in values]

@testset "the ink of a glyph past the box of its text" begin
    # A glyph that rises above the ascent of its font, and a glyph that reaches left
    # of the x of its text, both further than the pad of a dirty rectangle.
    @test SDL._compute_text_texture_box("Ṏ", large, 1.0)[2] < -2
    @test SDL._compute_text_texture_box("ƒ", large, 1.0)[1] < -2
    tall = GraphicsText("Ṏ", 100, 100; font = large, color = black)
    reaching = GraphicsText("ƒ", 250, 100; font = large, color = black)
    # A flat bar that moves down to just above the box of the tall glyph, and a thin
    # bar that moves right to just left of the box of the other glyph. Each one
    # dirties the ink of a glyph, and not the box of its text.
    bar_y = Cell(20)
    bar_x = Cell(150)
    flat = GraphicsRect(90, () -> bar_y[], 60, 1; color = black)
    thin = GraphicsRect(() -> bar_x[], 90, 1, 80; color = black)
    canvas = GraphicsCanvas(Any[tall, reaching, flat, thin]; w = width, h = height)
    @test isempty(find_differing_frames(canvas,
        [make_writes(bar_y, [60, 90, 95, 96, 97, 20]);
         make_writes(bar_x, [200, 240, 245, 246, 247, 150])]))
end

@testset "elements with alpha that overlap, and a child that leaves its canvas" begin
    a_x = Cell(50)
    b_x = Cell(80)
    a = GraphicsRect(() -> a_x[], 50, 60, 60; color = translucent)
    b = GraphicsRect(() -> b_x[], 70, 60, 60; color = translucent)
    text = GraphicsText("over and under", 40, 90; font, color = black)
    # A child that moves far from the other child of its canvas: the bounds of the
    # canvas grow with it.
    child_x = Cell(10)
    nested = GraphicsCanvas(Any[GraphicsRect(0, 0, 20, 20; color = black),
                                GraphicsCircle(() -> child_x[], 10, 6; color = black)];
                            x = 200, y = 150)
    canvas = GraphicsCanvas(Any[text, a, nested, b]; w = width, h = height)
    # A move of 5 pixels gives an old and a new rectangle that overlap.
    @test isempty(find_differing_frames(canvas,
        [make_writes(a_x, [55, 60, 70]); make_writes(b_x, [75, 65]);
         make_writes(child_x, [100, 180, 30])]))
end

@testset "rows in viewports, a list of nodes and a scroll" begin
    # 500 rows in a laid-out canvas, in a viewport at the left that scrolls.
    scroll = Cell(0)
    rows = GraphicsCanvas(CellVector(Cell[Cell(GraphicsText("row $k", 4, (k - 1) * 16;
                                                            font, color = black))
                                          for k in 1:500]);
                          y = () -> -scroll[], w = 180, h = 500 * 16,
                          layout = layout_vertical, overlapping = false)
    # A list of 30 nodes, with a dot that moves over it, in a viewport at the right.
    nodes = [ListNode(GraphicsText("line $k", 4, (k - 1) * 16; font, color = black)) for k in 1:30]
    for k in 1:29
        nodes[k].next = nodes[k + 1]
        nodes[k + 1].prev = nodes[k]
    end
    edited = Cell("line 5")
    set_cell_computation!(getfield(nodes[5], :value),
                          () -> GraphicsText(edited[], 4, 64; font, color = black))
    list = GraphicsCanvas(nodes[1]; layout = layout_vertical, overlapping = false)
    dot_y = Cell(8)
    dot = GraphicsCircle(30, () -> dot_y[], 4; color = translucent)
    canvas = GraphicsCanvas(Any[GraphicsViewport(0, 0, 180, 300, rows),
                                GraphicsViewport(200, 0, 200, 300, GraphicsCanvas(Any[list, dot]))];
                            w = width, h = height)
    @test isempty(find_differing_frames(canvas,
        [make_writes(dot_y, [12, 30, 70, 71]); make_writes(edited, ["line five", "5"]);
         make_writes(scroll, [16, 40, 33])]))
end

@testset "a viewport with a scale" begin
    # A viewport with a scale of 2, and a bar that moves across its left edge.
    function make_scaled_scene()
        inner_x = Cell(10)
        content = GraphicsCanvas(Any[GraphicsText("scaled text", 0, 0; font, color = black),
                                     GraphicsText("ƒ second line", 0, 20; font, color = black),
                                     GraphicsCircle(() -> inner_x[], 50, 5; color = translucent)])
        viewport = GraphicsViewport(50, 50, 200, 150, content; transform = make_affine_scale(2))
        bar_x = Cell(10)
        bar = GraphicsRect(() -> bar_x[], 40, 4, 200; color = translucent)
        (GraphicsCanvas(Any[viewport, bar]; w = width, h = height), inner_x, bar_x)
    end
    canvas, inner_x, bar_x = make_scaled_scene()
    @test isempty(find_differing_frames(canvas,
        [make_writes(inner_x, [20, 60]); make_writes(bar_x, [44, 46, 52, 120, 300])]))
    canvas, _, bar_x = make_scaled_scene()
    # @broken: a viewport with a scale sets its clip in the units of its content, so a dirty rectangle that cuts its box at an odd pixel gets a clip one pixel off; plan/done/a-repaint-draws-only-what-its-rectangles-touch.md
    @test_broken isempty(find_differing_frames(canvas, make_writes(bar_x, [45])))
end

# The records of a dirty walk, with no window.
make_resources() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", width, height, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), Vector{NTuple{4,Int}}[])

# Walk and paint `canvas` in full, run `change!`, then walk and paint the change by
# its rectangles. Answer the rectangles and the count of the leaves drawn.
function paint_change(canvas, change!)
    resources = make_resources()
    off = SDL.open_offscreen_renderer(width, height; supersample = 1)
    try
        SDL._compute_dirty_region(resources, canvas)
        SDL._render_canvas_offscreen!(off, canvas, width, height, background)
        change!()
        rects = SDL._limit_dirty_rects(SDL._compute_dirty_region(resources, canvas))
        paint = SDL._paint_dirty_rects!(off.renderer, canvas, rects, background, width, height, 1.0;
                                        records = resources.dirty_bounds)
        (rects, paint.drawn)
    finally
        SDL.close_offscreen_renderer(off)
    end
end

@testset "a change far from a viewport draws nothing of it" begin
    # 5000 labels in a canvas with no layout, as a chart or a graph holds them, in
    # a viewport at the left. A dot at the right moves.
    labels = GraphicsCanvas(Any[GraphicsText("label $k", (k % 10) * 18, (k ÷ 10) * 14; font, color = black)
                                for k in 0:4999])
    dot_x = Cell(300)
    canvas = GraphicsCanvas(Any[GraphicsViewport(0, 0, 180, 300, labels),
                                GraphicsCircle(() -> dot_x[], 150, 4; color = black)];
                            w = width, h = height)
    rects, drawn = paint_change(canvas, () -> dot_x[] = 360)
    @test length(rects) == 2
    # The dot at its new place, and no label.
    @test drawn == 1
end

@testset "a dot that moves over a list draws the rows under it" begin
    rows = GraphicsCanvas(CellVector(Cell[Cell(GraphicsText("row $k", 4, (k - 1) * 20; font, color = black))
                                          for k in 1:200]);
                          w = 180, h = 200 * 20, layout = layout_vertical, overlapping = false)
    dot_y = Cell(3 * 20 + 7)
    dot = GraphicsCircle(14, () -> dot_y[], 3; color = translucent)
    canvas = GraphicsCanvas(Any[GraphicsViewport(0, 0, 180, 300, GraphicsCanvas(Any[rows, dot]))];
                            w = width, h = height)
    rects, drawn = paint_change(canvas, () -> dot_y[] = 8 * 20 + 7)
    @test length(rects) == 2
    # Row 4 under the old place of the dot, row 9 under its new place, and the dot.
    @test drawn == 3
end
end
end
