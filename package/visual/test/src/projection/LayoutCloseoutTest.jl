# Layout closeout (Qt-gap Parts A+B): GridLayout per-column align/stretch +
# FormLayout sugar, and StackLayout's `active` page container.

const _LC_Cell = CellModule.Cell

function test_layout_closeout()
@testset "Layout closeout (grid/form/stack)" begin

proj = make_layout_projection_example()

@testset "FormLayout builds a 2-column grid with hug/fill columns" begin
    f = FormLayout([(WidgetLabel(Point2D(0, 0), "Name:"),  WidgetText(Point2D(0, 0), "alice")),
                    (WidgetLabel(Point2D(0, 0), "Email:"), WidgetText(Point2D(0, 0), "a@b.com"))])
    @test f isa GridLayout
    @test f.columns == 2
    @test f.column_align == [:right, :left]
    @test f.column_stretch == [0, 1]
    @test length(f.children) == 4
end

@testset "GridLayout per-column fields default to empty (backward compatible)" begin
    g = GridLayout(Any[WidgetLabel(Point2D(0, 0), "a"), WidgetLabel(Point2D(0, 0), "b")], 2)
    @test isempty(g.column_align)
    @test isempty(g.column_stretch)
    # Renders as before (two cells side by side, no stretch).
    io = print_document(proj, g)
    @test io.output isa GraphicsCanvas
end

@testset "a stretched column fills a seeded available width" begin
    # Two labels in a 2-col grid; column 2 stretches. With an available width far
    # wider than the content, column 2's left edge stays put but its cell widens,
    # so the outer width grows to fill (vs. the un-stretched, content-only width).
    cells = Any[WidgetLabel(Point2D(0, 0), "Name:"), WidgetText(Point2D(0, 0), "x")]
    plain  = GridLayout(copy(cells), 2)
    filled = GridLayout(copy(cells), 2; column_stretch=[0, 1], horizontal_gap=8)
    ctx = with_available_size(PrinterContext(EmptyReferencePath());
                              width=_LC_Cell(600), height=_LC_Cell(400))
    pw = Int(print_document(proj, nothing, plain,  ctx).output.w[])
    fw = Int(print_document(proj, nothing, filled, ctx).output.w[])
    @test fw > pw          # the stretched grid filled the available width
    @test fw >= 600 - 8    # ~the full seeded width (minus a gap rounding)
end

@testset "StackLayout active shows exactly one page" begin
    # The full widget pipeline registers StackLayout (the layout-only example omits it).
    wproj = make_widget_projection_example()
    pages() = Any[WidgetLabel(Point2D(0, 0), "P1"),
                  WidgetLabel(Point2D(0, 0), "P2"),
                  WidgetLabel(Point2D(0, 0), "P3")]
    all_io = print_document(wproj, StackLayout(pages()))                 # active=0 ⇒ z-stack
    one_io = print_document(wproj, StackLayout(pages(); active=2))       # only page 2
    @test length(collect(all_io.output.elements)) == 3
    @test length(collect(one_io.output.elements)) == 1
    # Out-of-range is empty (no crash).
    oor = print_document(wproj, StackLayout(pages(); active=9))
    @test length(collect(oor.output.elements)) == 0
end

end # @testset
end # function
