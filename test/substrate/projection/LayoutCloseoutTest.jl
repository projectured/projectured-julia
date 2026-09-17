# Layout closeout (Qt-gap Parts A+B): GridLayout per-column align and policy +
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
    @test f.column_policies == Any[Content, Fill]
    @test length(f.children) == 4
end

@testset "GridLayout per-column fields default to empty, and every column is Content" begin
    g = GridLayout(Any[WidgetLabel(Point2D(0, 0), "a"), WidgetLabel(Point2D(0, 0), "b")], 2)
    @test isempty(g.column_align)
    @test isempty(g.column_policies)
    @test isempty(g.row_policies)
    # `Content` is what a grid has always meant, so a grid that says nothing
    # draws what it drew before.
    @test g.column_policy === Content
    @test g.row_policy === Content
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
    filled = GridLayout(copy(cells), 2; column_policies=Any[Content, Fill], horizontal_gap=8)
    ctx = with_available_size(PrinterContext(EmptyReference());
                              width=_LC_Cell(600), height=_LC_Cell(400))
    pw = Int(print_document(proj, nothing, plain,  ctx).output.w[])
    fw = Int(print_document(proj, nothing, filled, ctx).output.w[])
    @test fw > pw          # the stretched grid filled the available width
    @test fw >= 600 - 8    # ~the full seeded width (minus a gap rounding)
end

@testset "a row takes a policy too, and Content is what a grid always meant" begin
    # Two rows of one column. The second fills, so it takes what the first
    # leaves of a seeded height; with no policy both are their content.
    cells() = Any[WidgetLabel(Point2D(0, 0), "top"), WidgetLabel(Point2D(0, 0), "rest")]
    ctx = with_available_size(PrinterContext(EmptyReference());
                              width=_LC_Cell(600), height=_LC_Cell(400))
    plain  = GridLayout(cells(), 1)
    filled = GridLayout(cells(), 1; row_policies=Any[Content, Fill])
    ph = Int(print_document(proj, nothing, plain,  ctx).output.h[])
    fh = Int(print_document(proj, nothing, filled, ctx).output.h[])
    # A grid that says nothing is its content, whatever it is offered. That is
    # the rule a table's rows depend on: a cell must not fill an offered height.
    @test ph < 100
    @test fh >= 400 - 1
end

@testset "a Fixed column clips what it holds, and a withheld offer draws one line" begin
    long = "a value that is far too wide for forty pixels of column"
    cells() = Any[WidgetLabel(Point2D(0, 0), long), WidgetLabel(Point2D(0, 0), "b")]
    ctx = with_available_size(PrinterContext(EmptyReference());
                              width=_LC_Cell(600), height=_LC_Cell(400))
    # The column hands its forty pixels to the cell, which breaks its lines
    # there; the grid draws the cell inside a viewport of the slot, which is
    # §3b: what was handed out is clipped to.
    offered = print_document(proj, nothing,
                             GridLayout(cells(), 2; column_policies=Any[Fixed(40), Content]), ctx)
    first_element = offered.output.elements[1]
    @test first_element isa GraphicsViewport
    @test Int(first_element.w) == 40
    # The offer withheld: the cell draws the one line it measures, wider than
    # the column, and the viewport still cuts it at forty. The grid is shorter,
    # because nothing broke into lines.
    withheld = print_document(proj, nothing,
                              GridLayout(cells(), 2; column_policies=Any[Fixed(40), Content],
                                         column_offers=Bool[false]), ctx)
    element = withheld.output.elements[1]
    @test element isa GraphicsViewport
    @test Int(element.w) == 40
    child = element.content.elements[1]   # the viewport holds the cell's own canvas
    @test Int(child.w[]) > 40
    @test Int(withheld.output.h[]) < Int(offered.output.h[])
    # A column that is its content is drawn where it lands, in no viewport.
    second = withheld.output.elements[2]
    @test !(second isa GraphicsViewport)
end

@testset "a flow breaks at the width it is offered, and its children are their content" begin
    words() = Any[WidgetBadge(Point2D(0, 0), w) for w in ("alpha", "beta", "gamma", "delta", "epsilon")]
    wide = with_available_size(PrinterContext(EmptyReference());
                               width=_LC_Cell(600), height=_LC_Cell(400))
    narrow = with_available_size(PrinterContext(EmptyReference());
                                 width=_LC_Cell(150), height=_LC_Cell(400))
    flow() = FlowLayout(words(); max_width=400, horizontal_gap=4, vertical_gap=4)
    at_wide = print_document(proj, nothing, flow(), wide)
    at_narrow = print_document(proj, nothing, flow(), narrow)
    # Offered more than its own width, the flow keeps its own; offered less, it
    # takes the offer, and more lines.
    @test Int(at_wide.output.w[]) == 400
    @test Int(at_narrow.output.w[]) == 150
    @test Int(at_narrow.output.h[]) > Int(at_wide.output.h[])
    # A child is as wide as its word, not as wide as the offer. The element
    # after the five children is the selection ring, which draws nothing here.
    drawn = collect(at_narrow.output.elements)
    @test length(drawn) == 6
    @test drawn[end] isa GraphicsRect && Int(drawn[end].w) == 0
    for wrapper in drawn[1:5]
        child = only(collect(wrapper.elements))
        @test Int(child.w) < 150
    end
end

@testset "a Fixed column is exactly what it was told" begin
    cells = Any[WidgetLabel(Point2D(0, 0), "a-very-long-label"), WidgetLabel(Point2D(0, 0), "b")]
    g = GridLayout(cells, 2; column_policies=Any[Fixed(40), Content])
    io = print_document(proj, nothing, g,
                        with_available_size(PrinterContext(EmptyReference());
                                            width=_LC_Cell(600), height=_LC_Cell(400)))
    # 40 for the first column plus whatever "b" measures — far under the 600 it
    # was offered, because neither column asked for a share of it.
    @test Int(io.output.w[]) < 120
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

# ── Reactive reflow (PAR-STABLE-IOMAP-IDENTITY): a page add/remove reflows the stack
# through the SAME held iomap — no re-print. A `build` cell reading `doc.children`
# rebuilds the child iomaps, and the extent / elements / entries re-derive from it. ──
@testset "StackLayout child add/remove reflows through the held iomap" begin
    wproj = make_widget_projection_example()
    stack = StackLayout(Any[WidgetLabel(Point2D(0, 0), "P1"),
                            WidgetLabel(Point2D(0, 0), "P2")])   # active=0 ⇒ all visible
    io = print_document(wproj, stack)
    @test length(collect(io.output.elements)) == 2
    push!(stack.children, WidgetLabel(Point2D(0, 0), "P3"))
    @test length(collect(io.output.elements)) == 3    # add reflows reactively, no re-print
    pop!(stack.children)
    @test length(collect(io.output.elements)) == 2    # remove reflows back
end

end # @testset
end # function
