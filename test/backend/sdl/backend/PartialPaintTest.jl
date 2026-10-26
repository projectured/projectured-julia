# A partial paint repaints the rectangles of the dirty walk. Its pixels are the
# pixels of a full paint of the same frame: also where the ink of a glyph reaches
# past the box of its text, where elements with alpha overlap, where two
# rectangles overlap, in a list of nodes, and inside a viewport with a scale. A
# viewport with a scale clips at the device pixels of its box.
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
function find_differing_frames(canvas, changes; supersample = 1, density = 1)
    partial = SDL.open_offscreen_renderer(width, height; supersample, density)
    full = SDL.open_offscreen_renderer(width, height; supersample, density)
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
    # A viewport with a scale of 2 at (50, 50), which holds a viewport with no
    # scale: in the window, the inner one covers x 50 to 210 and y 110 to 190. A
    # bar moves across both, to even and to odd pixels.
    function make_scaled_scene()
        inner_x = Cell(10)
        inner = GraphicsCanvas(Any[GraphicsText("inner text", 0, 0; font, color = black),
                                   GraphicsRect(10, 5, 50, 20; color = translucent)])
        content = GraphicsCanvas(Any[GraphicsText("scaled text", 0, 0; font, color = black),
                                     GraphicsText("ƒ second line", 0, 20; font, color = black),
                                     GraphicsCircle(() -> inner_x[], 50, 5; color = translucent),
                                     GraphicsViewport(0, 30, 80, 40, inner)])
        viewport = GraphicsViewport(50, 50, 200, 150, content; transform = make_affine_scale(2))
        bar_x = Cell(10)
        bar = GraphicsRect(() -> bar_x[], 40, 4, 200; color = translucent)
        (GraphicsCanvas(Any[viewport, bar]; w = width, h = height), inner_x, bar_x)
    end
    # At the scale 1, at 2 as a window draws, and at 2.5, which is no whole number.
    for (supersample, density) in ((1, 1), (2, 1), (2, 1.25))
        canvas, inner_x, bar_x = make_scaled_scene()
        @test isempty(find_differing_frames(canvas,
            [make_writes(inner_x, [20, 60]);
             make_writes(bar_x, [44, 45, 46, 47, 52, 53, 101, 103, 120, 131, 207, 209, 300])];
            supersample, density))
    end
end

# The settings of each scroll: as a test paints, as a window paints, at a density
# that gives 2.5 device pixels for each pixel, and at the density 2.
scroll_settings = ((1, 1), (2, 1), (2, 1.25), (2, 2))

# A pane over `elements` at the box `(x, y, w, h)`, as a scroll pane draws it: a
# viewport over a canvas with no layout whose origin is the negative scroll.
make_pane(box, elements, scroll_x, scroll_y) =
    GraphicsViewport(box..., GraphicsCanvas(Any[elements...]; x = () -> -scroll_x[], y = () -> -scroll_y[]))

# `count` rows `height` pixels apart, in a laid-out canvas. In the large font a row
# holds a glyph that rises above the ascent of its font or one that reaches left
# of its x, past the pad of a rectangle.
function make_scroll_rows(count, height, row_font)
    slots = Cell[Cell(GraphicsText(string(isodd(k) ? "Ṏ" : "ƒ", " row ", k), 4, (k - 1) * height;
                                   font = row_font, color = black))
                 for k in 1:count]
    (GraphicsCanvas(CellVector(slots); w = 400, h = count * height, layout = layout_vertical,
                    overlapping = false), slots)
end

@testset "a scroll of rows whose ink crosses the edges of the box" begin
    for (supersample, density) in scroll_settings
        scroll_x, scroll_y = Cell(0), Cell(0)
        rows, slots = make_scroll_rows(100, 60, large)
        edited = Cell("Ṏ row 9")
        set_cell_computation!(slots[9], () -> GraphicsText(edited[], 4, 8 * 60; font = large, color = black))
        canvas = GraphicsCanvas(Any[make_pane((20, 20, 300, 200), [rows], scroll_x, scroll_y)];
                                w = width, h = height)
        # Down, down further, up, further than the box, on both axes at once, back
        # to the left, and a scroll with a change of a row in the same frame.
        @test isempty(find_differing_frames(canvas,
            [make_writes(scroll_y, [16, 85, 62, 700]);
             () -> (scroll_x[] = 7; scroll_y[] = 724);
             make_writes(scroll_x, [0]);
             () -> (scroll_y[] = 450; edited[] = "Ṏ row nine")];
            supersample, density))
    end
end

@testset "a scroll of a list of nodes, with a pane inside it" begin
    for (supersample, density) in scroll_settings
        nodes = [ListNode(GraphicsText("line $k", 4, (k - 1) * 16; font, color = black)) for k in 1:60]
        for k in 1:59
            nodes[k].next = nodes[k + 1]
            nodes[k + 1].prev = nodes[k]
        end
        list = GraphicsCanvas(nodes[1]; layout = layout_vertical, overlapping = false)
        # A pane in the content, near its bottom edge, so the box of the outer pane
        # cuts it until the outer pane scrolls by 40.
        inner_rows, _ = make_scroll_rows(40, 16, font)
        stripes = [GraphicsRect(0, 8 * k, 100, 4; color = translucent) for k in 0:79]
        inner_scroll = Cell(0)
        inner = make_pane((150, 160, 100, 80), [stripes..., inner_rows], Cell(0), inner_scroll)
        outer_scroll = Cell(0)
        canvas = GraphicsCanvas(Any[make_pane((20, 20, 300, 200), [list, inner], Cell(0), outer_scroll)];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas,
            [make_writes(inner_scroll, [10, 27]);
             make_writes(outer_scroll, [16, 85, 62]);
             () -> (outer_scroll[] = 100; inner_scroll[] = 30);
             make_writes(outer_scroll, [700])];
            supersample, density))
    end
end

@testset "a scroll under and over other graphics" begin
    for (supersample, density) in scroll_settings
        gray = StyleColor(0.8, 0.8, 0.8, 1.0)
        # A plain fill under the whole box, stripes and a frame with a border under
        # a part of it, a dot over it that stays and one that moves, and a second
        # pane beside it.
        under = GraphicsRect(10, 10, 320, 220; color = StyleColor(0.95, 0.95, 0.9, 1.0))
        stripes = [GraphicsRect(20 + 20 * k, 20, 10, 200; color = gray) for k in 0:14]
        frame = GraphicsRect(40, 40, 100, 100; color = color_transparent, border_width = 3,
                             border_color = black)
        rows, _ = make_scroll_rows(200, 16, font)
        scroll = Cell(0)
        still = GraphicsCircle(200, 100, 10; color = translucent)
        dot_y = Cell(50)
        moving = GraphicsCircle(250, () -> dot_y[], 6; color = translucent)
        other_rows, _ = make_scroll_rows(200, 16, font)
        other_scroll = Cell(0)
        canvas = GraphicsCanvas(Any[under, stripes..., frame,
                                    make_pane((20, 20, 300, 200), [rows], Cell(0), scroll),
                                    still, moving,
                                    make_pane((330, 20, 60, 200), [other_rows], Cell(0), other_scroll)];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas,
            [make_writes(scroll, [16, 85, 62]);
             () -> (scroll[] = 100; dot_y[] = 120);
             make_writes(dot_y, [130]);
             () -> (scroll[] = 150; other_scroll[] = 40)];
            supersample, density))
    end
end

@testset "a scroll under a focus ring and over a filled rectangle" begin
    for (supersample, density) in scroll_settings
        # A ring of 2 pixels with corners of 3 around the pane and no fill, as a
        # focused pane has it; under the pane a filled rectangle with a border and
        # round corners over a part of its box; over the pane a translucent one.
        rows, _ = make_scroll_rows(200, 16, font)
        scroll = Cell(0)
        under = GraphicsRect(60, 50, 150, 120; color = StyleColor(0.9, 0.8, 0.6, 1.0), radius = 6,
                             border_width = 1, border_color = black)
        ring = GraphicsRect(20, 20, 300, 200; color = color_transparent, radius = 3, border_width = 2,
                            border_color = translucent)
        over = GraphicsRect(200, 40, 80, 90; color = translucent, radius = 4)
        canvas = GraphicsCanvas(Any[under, make_pane((20, 20, 300, 200), [rows], Cell(0), scroll), ring, over];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas, make_writes(scroll, [16, 85, 62, 63]); supersample, density))
    end
end

@testset "a scroll under a rectangle that the box of another pane cuts" begin
    for (supersample, density) in scroll_settings
        # A second pane over the one that scrolls holds a filled rectangle that
        # goes past its bottom edge, so its fill ends where the box of the pane
        # cuts it, and not at its own edge.
        rows, _ = make_scroll_rows(200, 16, font)
        scroll = Cell(0)
        cut = GraphicsRect(20, 50, 100, 60; color = StyleColor(0.9, 0.8, 0.6, 1.0), border_width = 1,
                           border_color = black)
        canvas = GraphicsCanvas(Any[make_pane((20, 20, 300, 200), [rows], Cell(0), scroll),
                                    make_pane((100, 60, 150, 80), [cut], Cell(0), Cell(0))];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas, make_writes(scroll, [16, 85, 62, 63]); supersample, density))
    end
end

@testset "two viewports, one in the box of the other, that scroll together" begin
    # The shape of the table of a data frame: the rules of the rows in one
    # viewport, and the cells in a viewport inside its box, which scroll by the
    # same cell.
    for (supersample, density) in scroll_settings
        rules = GraphicsCanvas(Any[GraphicsRect(0, 16 * k + 15, 200, 1; color = black) for k in 0:199];
                               w = 200, h = 200 * 16, layout = layout_vertical, overlapping = false)
        rows, _ = make_scroll_rows(200, 16, font)
        scroll = Cell(0)
        canvas = GraphicsCanvas(Any[make_pane((20, 20, 200, 200), [rules], Cell(0), scroll),
                                    make_pane((30, 26, 180, 188), [rows], Cell(0), scroll)];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas, make_writes(scroll, [16, 85, 62, 500]);
                                            supersample, density))
        # A pane in the box of another one, shorter than the scroll, so its box is
        # painted and only the other box is copied: the copy carries its old
        # pixels, which the paint draws over.
        bars = GraphicsCanvas(Any[GraphicsRect(0, y, 180, 10; color = black) for y in (0, 20, 1000)];
                              w = 180, h = 2000, layout = layout_vertical, overlapping = false)
        short_scroll = Cell(0)
        canvas = GraphicsCanvas(Any[make_pane((20, 20, 200, 200), [rules], Cell(0), short_scroll),
                                    make_pane((30, 100, 180, 30), [bars], Cell(0), short_scroll)];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas, make_writes(short_scroll, [40, 45]); supersample, density))
    end
end

@testset "a scroll inside and around a scale" begin
    for (supersample, density) in scroll_settings
        # A pane in a viewport with a scale of 2, and a viewport with a scale of 2
        # in the content of a pane.
        inner_rows, _ = make_scroll_rows(100, 16, font)
        inner_scroll = Cell(0)
        scaled = GraphicsViewport(20, 20, 300, 160,
                                  GraphicsCanvas(Any[make_pane((10, 10, 120, 60), [inner_rows], Cell(0),
                                                               inner_scroll)]);
                                  transform = make_affine_scale(2))
        rows, _ = make_scroll_rows(100, 16, font)
        zoomed = GraphicsViewport(150, 40, 80, 40,
                                  GraphicsCanvas(Any[GraphicsText("zoomed", 0, 0; font, color = black)]);
                                  transform = make_affine_scale(2))
        scroll = Cell(0)
        canvas = GraphicsCanvas(Any[scaled, make_pane((20, 190, 300, 100), [rows, zoomed], Cell(0), scroll)];
                                w = width, h = height)
        @test isempty(find_differing_frames(canvas,
            [make_writes(inner_scroll, [16, 85, 62]);
             make_writes(scroll, [16, 33]);
             () -> (inner_scroll[] = 100; scroll[] = 50)];
            supersample, density))
        # A stripe under a part of the box, whose rectangles cut the box of the
        # viewport with a scale in the content.
        for stripe_x in (161, 163)
            rows, _ = make_scroll_rows(100, 16, font)
            zoomed = GraphicsViewport(150, 40, 80, 40,
                                      GraphicsCanvas(Any[GraphicsText("zoomed", 0, 0; font, color = black)]);
                                      transform = make_affine_scale(2))
            scroll = Cell(0)
            canvas = GraphicsCanvas(Any[GraphicsRect(stripe_x, 60, 30, 200; color = StyleColor(0.8, 0.8, 0.8, 1.0)),
                                        make_pane((20, 20, 300, 200), [rows, zoomed], Cell(0), scroll)];
                                    w = width, h = height)
            @test isempty(find_differing_frames(canvas, make_writes(scroll, [5, 21, 16]); supersample, density))
        end
    end
end

@testset "a box with a scale that one rectangle covers and another one cuts" begin
    # No scroll: a rectangle that moves by one pixel holds the box of a viewport
    # with a scale of 2 in its old and its new bounds, and a dot moves to cut the
    # box at its row 118.
    zoomed = GraphicsViewport(245, 113, 72, 32, GraphicsCanvas(Any[GraphicsText("zoom", 0, 0; font, color = black)]);
                              transform = make_affine_scale(2))
    big_y = Cell(2)
    big = GraphicsRect(167, () -> big_y[], 196, 148; color = StyleColor(0.9, 0.9, 0.7, 0.5))
    dot_y = Cell(200)
    dot = GraphicsRect(152, () -> dot_y[], 242, 70; color = StyleColor(0.2, 0.2, 0.9, 0.3))
    canvas = GraphicsCanvas(Any[big, zoomed, dot]; w = width, h = height)
    @test isempty(find_differing_frames(canvas, [() -> (big_y[] = 3; dot_y[] = 118)]))
end

@testset "a copy of a box moves the pixels that stay in it" begin
    # Squares of a color that differs in each row and each column. The box, the
    # offset and the edges are whole device pixels at each setting.
    squares = GraphicsCanvas(Any[GraphicsRect(x, y, 10, 10; color = StyleColor(x / width, y / height, 0.5, 1.0))
                                 for x in 0:10:(width - 10) for y in 0:10:(height - 10)])
    box, offset = (20, 10, 380, 290), (6, -8)
    # The pixels `before` with the pixels that stay in `box` moved by `offset`, at
    # `factor` device pixels for each pixel.
    function move_pixels(before, factor)
        source = SDL._make_device_rect(SDL._get_kept_box(box, offset)..., factor, factor)
        xs = (source.x + 1):(source.x + source.w)
        ys = (source.y + 1):(source.y + source.h)
        expected = copy(before)
        expected[xs .+ round(Int, offset[1] * factor), ys .+ round(Int, offset[2] * factor)] = before[xs, ys]
        expected
    end
    for (supersample, density) in scroll_settings
        off = SDL.open_offscreen_renderer(width, height; supersample, density)
        try
            state = SDL.make_offscreen_paint_state(off)
            SDL._render_canvas_offscreen!(off, squares, width, height, background)
            SDL.SDL_RenderFlush(off.renderer)
            surface = unsafe_load(off.surface)
            read_surface() = copy(unsafe_wrap(Array, Ptr{UInt32}(surface.pixels),
                                              (Int(surface.pitch) ÷ 4, Int(surface.h))))
            before = read_surface()
            @test SDL._copy_surface_box!(off, state.res, box, offset)
            @test read_surface() == move_pixels(before, state.res.ratio * state.res.ss)
        finally
            SDL.close_offscreen_renderer(off)
        end
    end
    # The kept target of a hidden window, through its scratch texture.
    backend = SdlBackend()
    initialize_backend!(backend)
    held = WindowDocument(; id = :copy_test, title = "copy_test", x = 100, y = 100,
                            width = width, height = height, content = PrimitiveString("content"))
    resource = SDL._open_native_window!(backend, held; hidden = true)
    try
        @test SDL._ensure_ss_target!(resource)
        renderer = resource.renderer
        factor = resource.ratio * resource.ss
        function read_target()
            SDL.SDL_SetRenderTarget(renderer, resource.target)
            pixels = Matrix{UInt32}(undef, resource.target_w, resource.target_h)
            SDL.SDL_RenderReadPixels(renderer, C_NULL, SDL.SDL_PIXELFORMAT_ARGB8888, pixels,
                                     resource.target_w * 4)
            pixels
        end
        SDL.SDL_SetRenderTarget(renderer, resource.target)
        SDL.SDL_RenderSetScale(renderer, Float32(factor), Float32(factor))
        SDL._paint_dirty_rects!(renderer, squares, [(0, 0, width, height)], background, width, height,
                                resource.ratio)
        before = read_target()
        @test SDL._copy_target_box!(resource, box, offset)
        @test read_target() == move_pixels(before, factor)
        @test resource.scratch != C_NULL
    finally
        SDL._close_native_window!(resource)
        quit_backend!(backend)
    end
end

# The records of a dirty walk, with no window.
make_resources() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", width, height, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), Vector{NTuple{4,Int}}[], C_NULL)

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

@testset "a scroll paints only what the copy of its box does not give" begin
    # 2000 rows of 23 pixels in a pane of 290 pixels. A scroll by 69 pixels shows
    # rows 4 to 16, and the box moves by -69. The copy gives rows 4 to 12. The paint
    # draws rows 14 to 16 in the strip of 69 pixels at the bottom, and row 13, which
    # crosses the bottom edge of the box at its old place. A paint of the whole box
    # draws all 13 rows.
    slots = Cell[Cell(GraphicsText("row $k", 4, (k - 1) * 23; font, color = black)) for k in 1:2000]
    rows = GraphicsCanvas(CellVector(slots); w = 200, h = 2000 * 23, layout = layout_vertical, overlapping = false)
    scroll = Cell(0)
    pane = make_pane((0, 0, 200, 290), [rows], Cell(0), scroll)
    canvas = GraphicsCanvas(Any[pane]; w = width, h = height)
    resources = make_resources()
    SDL._compute_dirty_change(resources, canvas)
    scroll[] = 69
    rects, moves = SDL._compute_dirty_change(resources, canvas)
    @test moves == [((0, 0, 200, 290), (0, -69))]
    # The keys of the rows, made as the walk makes them.
    pane_key = SDL._make_placement_key(pane, SDL._make_placement_key(canvas, UInt(0)))
    rows_key = SDL._make_placement_key(rows, SDL._make_placement_key(pane.content, pane_key))
    paint = SDL._PartialPaint(resources.dirty_bounds, (0, 0, 0, 0), 0)
    function meets(rect, k)
        paint.rect = rect
        key = SDL._make_placement_key(slots[k][], rows_key)
        haskey(resources.dirty_bounds, key) && !SDL._is_outside_partial_paint(paint, key)
    end
    @test filter(k -> any(r -> meets(r, k), rects), 1:2000) == 13:16
    # The paint of each rectangle draws the rows that it meets, and nothing else.
    off = SDL.open_offscreen_renderer(width, height; supersample = 1)
    try
        drawn = SDL._paint_dirty_rects!(off.renderer, canvas, rects, background, width, height, 1.0;
                                        records = resources.dirty_bounds).drawn
        @test drawn == sum(r -> count(k -> meets(r, k), 13:16), rects)
    finally
        SDL.close_offscreen_renderer(off)
    end
end

@testset "a focus ring does not stop the copy of the box that it holds" begin
    rows, _ = make_scroll_rows(200, 16, font)
    scroll = Cell(0)
    ring = GraphicsRect(20, 20, 300, 200; color = color_transparent, radius = 3, border_width = 2,
                        border_color = black)
    canvas = GraphicsCanvas(Any[make_pane((20, 20, 300, 200), [rows], Cell(0), scroll), ring];
                            w = width, h = height)
    resources = make_resources()
    SDL._compute_dirty_change(resources, canvas)
    scroll[] = 16
    rects, moves = SDL._compute_dirty_change(resources, canvas)
    @test moves == [((20, 20, 320, 220), (0, -16))]
    @test !any(r -> SDL._is_rect_covered((20, 20, 320, 220), r), rects)
end

@testset "two viewports that scroll together are one copy" begin
    # The shape of the table of a data frame: the copy of the outer box moves the
    # inner one, which gives its strip and the band that its box covers after the
    # copy, and not its whole box.
    rules = GraphicsCanvas(Any[GraphicsRect(0, 16 * k + 15, 200, 1; color = black) for k in 0:199];
                           w = 200, h = 200 * 16, layout = layout_vertical, overlapping = false)
    rows, _ = make_scroll_rows(200, 16, font)
    scroll = Cell(0)
    canvas = GraphicsCanvas(Any[make_pane((20, 20, 200, 200), [rules], Cell(0), scroll),
                                make_pane((30, 26, 180, 188), [rows], Cell(0), scroll)];
                            w = width, h = height)
    resources = make_resources()
    SDL._compute_dirty_change(resources, canvas)
    scroll[] = 16
    rects, moves = SDL._compute_dirty_change(resources, canvas)
    @test moves == [((20, 20, 220, 220), (0, -16))]
    @test !any(r -> SDL._is_rect_covered((30, 26, 210, 214), r), rects)
end

@testset "a window paints a scroll with the pixels of a full paint" begin
    # Two hidden windows show one canvas: one paints by the copies and the
    # rectangles, and one paints in full. Their kept targets hold the same pixels:
    # with the renderer that SDL picks on this machine, and with the software
    # renderer, which a machine with no graphics card draws a window with.
    function read_target(resource)
        SDL.SDL_SetRenderTarget(resource.renderer, resource.target)
        pixels = Matrix{UInt32}(undef, resource.target_w, resource.target_h)
        SDL.SDL_RenderReadPixels(resource.renderer, C_NULL, SDL.SDL_PIXELFORMAT_ARGB8888, pixels,
                                 resource.target_w * 4)
        SDL.SDL_SetRenderTarget(resource.renderer, C_NULL)
        pixels
    end
    for driver in (nothing, "software")
        driver === nothing || SDL.SDL_SetHintWithPriority(SDL.SDL_HINT_RENDER_DRIVER, driver,
                                                          SDL.SDL_HINT_OVERRIDE)
        backends = (SdlBackend(; partial_render = true), SdlBackend(; partial_render = false))
        foreach(initialize_backend!, backends)
        gray = StyleColor(0.8, 0.8, 0.8, 1.0)
        rows, _ = make_scroll_rows(50, 60, large)
        other_rows, _ = make_scroll_rows(200, 16, font)
        scroll, other_scroll, dot_y = Cell(0), Cell(0), Cell(50)
        canvas = GraphicsCanvas(Any[GraphicsRect(10, 10, 320, 220; color = gray),
                                    [GraphicsRect(20 + 20 * k, 20, 10, 200; color = translucent) for k in 0:14]...,
                                    make_pane((20, 20, 300, 200), [rows], Cell(0), scroll),
                                    GraphicsCircle(250, () -> dot_y[], 6; color = translucent),
                                    make_pane((330, 20, 60, 200), [other_rows], Cell(0), other_scroll)];
                                w = width, h = height)
        resources = [SDL._open_native_window!(backend,
                                              WindowDocument(; id = Symbol(:scroll_window_, k), title = "scroll_window",
                                                               x = 100, y = 100, width, height,
                                                               content = PrimitiveString("content"));
                                              hidden = true)
                     for (k, backend) in enumerate(backends)]
        differing = Int[]
        try
            changes = Any[() -> nothing; make_writes(scroll, [16, 85, 62, 700]);
                          () -> (scroll[] = 100; dot_y[] = 120);
                          () -> (scroll[] = 150; other_scroll[] = 40)]
            for (frame, change!) in enumerate(changes)
                change!()
                foreach((backend, resource) -> SDL._render_window!(backend, resource, canvas), backends, resources)
                read_target(resources[1]) == read_target(resources[2]) || push!(differing, frame)
            end
            @test isempty(differing)
            # A window at a whole device pixel ratio copied a box; at another ratio a
            # scroll paints its box.
            @test !isinteger(resources[1].ratio) || resources[1].scratch != C_NULL
        finally
            foreach(SDL._close_native_window!, resources)
            foreach(quit_backend!, backends)
            driver === nothing || SDL.SDL_ResetHint(SDL.SDL_HINT_RENDER_DRIVER)
        end
    end
end

@testset "a viewport with a scale clips at the device pixels of its box" begin
    # A viewport with a scale of 2, at an odd place and of an odd width, holds a
    # wider viewport with no scale. Both are filled with black, so the black
    # columns of a row are the clip: x 51 to 151.
    for supersample in (1, 2)
        inner = GraphicsViewport(-5, -5, 200, 100,
                                 GraphicsCanvas(Any[GraphicsRect(0, 0, 200, 100; color = black)]))
        viewport = GraphicsViewport(51, 20, 101, 60, GraphicsCanvas(Any[inner]);
                                    transform = make_affine_scale(2))
        off = SDL.open_offscreen_renderer(width, height; supersample)
        try
            SDL._render_canvas_offscreen!(off, GraphicsCanvas(Any[viewport]; w = width, h = height),
                                          width, height, background)
            surface = unsafe_load(off.surface)
            pixels = unsafe_wrap(Array, Ptr{UInt32}(surface.pixels),
                                 (Int(surface.pitch) ÷ 4, Int(surface.h)))
            row = 40 * supersample + 1
            black_columns = [x - 1 for x in 1:(width * supersample) if pixels[x, row] & 0x00ffffff == 0]
            @test black_columns == collect((51 * supersample):(152 * supersample - 1))
        finally
            SDL.close_offscreen_renderer(off)
        end
    end
end
end
end
