# A laid-out canvas draws the elements between the edges of the clip, and the
# renderer and the dirty walk read the content of no other element. A thousand
# rows under a window of sixty rows compute the content of those sixty.
function test_laid_out_canvas()
@testset "a laid-out canvas reads only the rows in the clip" begin

SDL = ProjecturedSDL.SdlModule
row_height = 10
background = (0xff, 0xff, 0xff, 0xff)

# A thousand rows along the vertical axis. The place of a row is a number, and
# its content is a cell that records the row in `read` when something reads it.
function make_rows(read::Vector{Int}; y = 0)
    rows = CellVector(Cell[Cell(GraphicsCanvas(
               CellVector(Computation(() -> (push!(read, k);
                                             Any[GraphicsRect(0, 0, 100, row_height)])));
               y = (k - 1) * row_height, w = 100, h = row_height)) for k in 1:1000])
    GraphicsCanvas(rows; y = y, w = 100, h = 1000 * row_height,
                   layout = layout_vertical, overlapping = false)
end

make_res() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", 800, 600, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), NTuple{4,Int}[], C_NULL)

function render(window)
    off = SDL.open_offscreen_renderer(800, 600; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, window, 800, 600, background)
    finally
        SDL.close_offscreen_renderer(off)
    end
end

@testset "the renderer reads the rows in the window" begin
    # Scrolled up by 5000 pixels, a window of 600 pixels shows rows 501 to 561.
    read = Int[]
    render(GraphicsCanvas(Any[make_rows(read; y = -5000)]; w = 800, h = 600))
    @test sort(read) == collect(501:561)
end

@testset "the dirty walk reads the same rows" begin
    read = Int[]
    @test SDL._compute_dirty_rect(make_res(), GraphicsCanvas(Any[make_rows(read; y = -5000)];
                                                             w = 800, h = 600)) !== nothing
    @test sort(read) == collect(501:561)
end

@testset "a viewport clips at its own edges" begin
    # 100 pixels from y = 100 show rows 501 to 511.
    read = Int[]
    viewport = GraphicsViewport(0, 100, 100, 100, make_rows(read; y = -5000))
    render(GraphicsCanvas(Any[viewport]; w = 800, h = 600))
    @test sort(read) == collect(501:511)
end

@testset "a viewport cut by the window reads the rows of the part that shows" begin
    # The viewport spans y = -100 to 100 and the window starts at 0, so the upper
    # half lies above the window and shows the rows from y = 100 to 200.
    read = Int[]
    window = GraphicsCanvas(Any[GraphicsViewport(0, -100, 100, 200, make_rows(read))]; w = 800, h = 600)
    render(window)
    @test sort(read) == collect(11:21)
    # A walk on a fresh print reads the same rows.
    read = Int[]
    window = GraphicsCanvas(Any[GraphicsViewport(0, -100, 100, 200, make_rows(read))]; w = 800, h = 600)
    @test SDL._compute_dirty_rect(make_res(), window) !== nothing
    @test sort(read) == collect(11:21)
end

@testset "a viewport that the window shows none of reads no row and keeps its box" begin
    read = Int[]
    window = GraphicsCanvas(Any[GraphicsViewport(0, -300, 100, 200, make_rows(read))]; w = 800, h = 600)
    render(window)
    @test isempty(read)
    res = make_res()
    SDL._compute_dirty_rect(res, window)
    @test isempty(read)
    @test (0, -300, 100, -100) in values(res.dirty_bounds)
end

@testset "a viewport that goes from shown to cut forgets only the rows it recorded" begin
    # The viewport spans y = -100 to 100, so its records hold rows 11 to 21 and not
    # the rows 1 to 10 of the hidden half. Then it moves out of the window.
    read = Int[]
    top = Cell(-100)
    window = GraphicsCanvas(Any[GraphicsViewport(0, () -> top[], 100, 200, make_rows(read))]; w = 800, h = 600)
    res = make_res()
    SDL._compute_dirty_rect(res, window)
    @test sort(read) == collect(11:21)
    top[] = -400
    SDL._compute_dirty_rect(res, window)
    @test sort(read) == collect(11:21)
    # Back in the window, the content is recorded again and reads the rows that show.
    top[] = -100
    SDL._compute_dirty_rect(res, window)
    @test sort(read) == collect(11:21)
end

# The bytes of the surface of `off`.
function read_pixels(off)
    surface = unsafe_load(off.surface)
    copy(unsafe_wrap(Array, Ptr{UInt8}(surface.pixels), Int(surface.pitch) * Int(surface.h)))
end

# Paint `canvas` by the rectangles of the dirty walk into one renderer, and in full
# into another, once before the changes and once after each of them. Answer the
# frames whose pixels differ.
function find_differing_frames(canvas, changes; on_first_frame = () -> nothing)
    partial = SDL.open_offscreen_renderer(400, 300; supersample = 1)
    full = SDL.open_offscreen_renderer(400, 300; supersample = 1)
    differing = Int[]
    try
        state = SDL.make_offscreen_paint_state(partial)
        for (frame, change!) in enumerate(Any[() -> nothing; changes])
            change!()
            SDL.render_offscreen_changes!(partial, state, canvas; background)
            frame == 1 && on_first_frame()
            SDL._render_canvas_offscreen!(full, canvas, 400, 300, background)
            read_pixels(partial) == read_pixels(full) || push!(differing, frame)
        end
    finally
        SDL.close_offscreen_renderer(partial)
        SDL.close_offscreen_renderer(full)
    end
    differing
end

# Rows of three colours along the vertical axis, 100 of them, whose reads go to `read`.
function make_colored_rows(read::Vector{Int}, scroll::Cell)
    colors = [(0.9, 0.2, 0.2, 1.0), (0.2, 0.9, 0.2, 1.0), (0.2, 0.2, 0.9, 1.0)]
    rows = CellVector(Cell[Cell(GraphicsCanvas(
               CellVector(Computation(() -> (push!(read, k);
                   Any[GraphicsRect(0, 0, 100, row_height; color = StyleColor(colors[mod1(k, 3)]...))])));
               y = (k - 1) * row_height, w = 100, h = row_height)) for k in 1:100])
    GraphicsCanvas(rows; y = () -> -scroll[], w = 100, h = 100 * row_height,
                   layout = layout_vertical, overlapping = false)
end

@testset "an outer scroll brings a cut inner viewport further on the screen" begin
    # The outer pane spans y = 20 to 220. Its content holds a pane of 80 pixels at
    # y = 180 of the content, so the outer pane shows 20 pixels of it until it scrolls.
    outer_scroll, inner_scroll = Cell(0), Cell(0)
    read = Int[]
    inner = GraphicsViewport(0, 180, 100, 80, make_colored_rows(read, inner_scroll))
    outer = GraphicsViewport(20, 20, 300, 200,
                             GraphicsCanvas(Any[inner]; y = () -> -outer_scroll[]))
    canvas = GraphicsCanvas(Any[outer]; w = 400, h = 300)
    differing = find_differing_frames(canvas,
        [() -> (outer_scroll[] = 16), () -> (outer_scroll[] = 85), () -> (inner_scroll[] = 27),
         () -> (outer_scroll[] = 62), () -> (outer_scroll[] = 0)];
        on_first_frame = () -> @test sort(unique(read)) == [1, 2, 3])
    @test isempty(differing)
end

@testset "a viewport with a scale reads the rows of the part that shows" begin
    # A scale of 2 at y = -100: the box spans y = -100 to 300 of the window, and
    # the window starts at 0, so the content shows from its y = 50 to 150.
    transform = make_affine_scale(2)
    read = Int[]
    window = GraphicsCanvas(Any[GraphicsViewport(0, -100, 200, 400, make_rows(read); transform)]; w = 800, h = 600)
    render(window)
    @test sort(read) == collect(6:21)
    read = Int[]
    window = GraphicsCanvas(Any[GraphicsViewport(0, -100, 200, 400, make_rows(read); transform)]; w = 800, h = 600)
    SDL._compute_dirty_rect(make_res(), window)
    @test sort(read) == collect(6:21)
    # A scroll of the content gives the pixels of a full paint.
    scroll = Cell(0)
    canvas = GraphicsCanvas(Any[GraphicsViewport(0, -100, 200, 200, make_colored_rows(Int[], scroll); transform)];
                            w = 400, h = 300)
    @test isempty(find_differing_frames(canvas, [() -> (scroll[] = 10), () -> (scroll[] = 33), () -> (scroll[] = 0)]))
end

@testset "a size query reads no row, and a dirty unit the rows in the window" begin
    read = Int[]
    rows = make_rows(read)
    @test has_declared_extent(rows)
    @test get_graphics_size(rows) == (100, 10000)
    @test isempty(read)
    # A list of rows that is computed again is one dirty unit. The walk records
    # the rows that the render draws, and reads no other.
    source = make_rows(read)
    computed = GraphicsCanvas(CellVector(Computation(() -> collect(Any, source.elements)));
                              y = -5000, w = 100, h = 10000,
                              layout = layout_vertical, overlapping = false)
    @test SDL._compute_dirty_rect(make_res(), GraphicsCanvas(Any[computed]; w = 800, h = 600)) !== nothing
    @test sort(read) == collect(501:561)
end


# An endless list of rows: each `next` is computed when a reader reads it. A read
# past 10000 nodes throws, so a walk that does not stop fails the test and does
# not hang it.
function make_endless_list(read::Ref{Int}, k::Int = 1)
    node = ListNode(GraphicsRect(0, (k - 1) * row_height, 100, row_height))
    set_cell_computation!(getfield(node, :next), () -> begin
        read[] += 1
        read[] > 10_000 && error("an endless list was walked past 10000 nodes")
        make_endless_list(read, k + 1)
    end)
    node
end

@testset "a list in a canvas with no layout is refused, and never walked" begin
    read = Ref(0)
    head = make_endless_list(read)
    @test_throws ArgumentError GraphicsCanvas(head)
    # A cell can give the list after the canvas is made, which no constructor sees.
    unbounded = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                               Cell(head), layout_none, true, Cell(nothing))
    window = GraphicsCanvas(Any[unbounded]; w = 800, h = 600)
    @test SDL._compute_dirty_rect(make_res(), window) === nothing
    @test_throws ArgumentError render(window)
    @test_throws ArgumentError hit_element_at(unbounded, 5, 5)
    @test read[] == 0
    # The same list with a layout and no overlap draws the rows in the window.
    bounded = GraphicsCanvas(head; layout = layout_vertical, overlapping = false)
    render(GraphicsCanvas(Any[bounded]; w = 800, h = 600))
    @test 59 <= read[] <= 61
end
end
end
