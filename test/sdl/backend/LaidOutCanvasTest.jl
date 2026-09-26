# A laid-out canvas draws the elements between the edges of the clip, and the
# renderer and the dirty walk read the content of no other element. A thousand
# rows under a window of sixty rows compute the content of those sixty.
function test_laid_out_canvas()
@testset "a laid-out canvas reads only the rows in the clip" begin

SDL = ProjecturedSdl
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
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), NTuple{4,Int}[])

function render(window)
    off = SDL._open_offscreen_renderer(800, 600; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, window, 800, 600, background)
    finally
        SDL._close_offscreen_renderer(off)
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

@testset "a size query and a dirty unit read no row" begin
    read = Int[]
    rows = make_rows(read)
    @test has_declared_extent(rows)
    @test get_graphics_size(rows) == (100, 10000)
    @test isempty(read)
    # A list of rows that is computed again is one dirty unit, and its bounds
    # are its box, so the dirty walk reads no row for it.
    source = make_rows(read)
    computed = GraphicsCanvas(CellVector(Computation(() -> collect(Any, source.elements)));
                              y = -5000, w = 100, h = 10000,
                              layout = layout_vertical, overlapping = false)
    @test SDL._compute_dirty_rect(make_res(), GraphicsCanvas(Any[computed]; w = 800, h = 600)) !== nothing
    @test isempty(read)
end

end
end
