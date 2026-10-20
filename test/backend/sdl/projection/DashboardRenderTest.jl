# A dashboard of 64 cards on a page of 1100 by 500 pixels: 3 columns of cards make
# 22 rows. The rows of its grid are a list, so the renderer and the dirty walk
# build the rows that the page shows, and no other.
function test_dashboard_render()
@testset "a dashboard builds the rows of the cards it draws" begin
    SDL = ProjecturedSDL.SdlModule
    projection_module = ProjecturedKernel.ProjectionModule
    card(title) = DashboardCard(title, PrimitiveString("text of " * title))
    dashboard = Dashboard("Many", Any[card("Card $k") for k in 1:64])
    natural = RecursiveProjection(NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)))
    offer = projection_module.with_exact_size(projection_module.PrinterContext();
                                              width = ProjecturedKernel.CellModule.Cell(Int32(1100)),
                                              height = ProjecturedKernel.CellModule.Cell(Int32(500)))
    iomap = print_document(natural, nothing, dashboard, offer)
    # The search enters no graphics and no list, so it builds no row.
    grids = search_documents(iomap, x -> x isa GridLayoutListIoMap; raw = true, limit = nothing,
                             descend = (parent, child) -> !(child isa ListNode || child isa GraphicsDocument))
    @test length(grids) == 1
    built() = sort(collect(keys(only(grids).state.built)))
    off = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, iomap.output, 1100, 500, (0xff, 0xff, 0xff, 0xff))
    finally
        SDL.close_offscreen_renderer(off)
    end
    rendered = built()
    @test first(rendered) == 1 && rendered == collect(1:length(rendered))
    @test 2 <= length(rendered) < 22
    # The dirty walk reads the rows that the render reads.
    res = SDL.SdlWindowResources(C_NULL, C_NULL, :test, UInt32(0), "t", 1100, 500, 0, 0, :default,
                                 (0x00, 0x00, 0x00, 0xff), 1, 1.0, 1.0, C_NULL, 0, 0, false,
                                 Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), Vector{NTuple{4,Int}}[])
    SDL._compute_dirty_region(res, iomap.output)
    @test built() == rendered
end
end
