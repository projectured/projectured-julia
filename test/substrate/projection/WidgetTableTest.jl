# WidgetTable whole-row hover.
#
# Hovering a body cell (or row header) highlights that row; a column header
# highlights its column; the corner / empty space clears. Hover is transient state
# (`WidgetTable.hovered`) rendered as a faint band, mirroring the selection band.
# Driven by MouseEnter/MouseMove/MouseLeave, which WidgetHoverTrackingProjection
# synthesises. Must also work when the table is nested in a layout / tabbed pane /
# shell (routed via the container crossing routing + the table's 3-arg bridge).

using ProjecturedKernel.CellModule: Cell, Computed

function test_widget_table()
@testset "WidgetTable hover" begin

_det = (t, f) -> (length(t) * 8, 16)
_w2g = WidgetToGraphics(font_ubuntu_regular_20; measure = _det)
# A recursive dispatcher so the table's cell content is recursed (and so a nested
# layout/tab/shell dispatches too), and reads reach the table's readers.
_rec = RecursiveProjection(TypeDispatchingProjection(vcat(LayoutToGraphics().dispatch, _w2g.dispatch)))
_mods = ModifierKeys()
_mktable() = WidgetTable(Point2D(0, 0), ["ID", "Name"],
                         [["1", "Ada"], ["2", "Bob"], ["3", "Cy"]])
_rd_marked(io, g) = begin
    ch = read_intent(_rec, nothing, Intent(g, nothing), io)
    ch isa Intent ? ch.operation : ch
end
# The answer, looking through the mark a hover carries as view state.
_rd(io, g) = (op = _rd_marked(io, g);
              op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op)
# Centre coordinate of body row r's band, and of a body column.
_bx(g) = (g.col_x[g.col_offset + 1] + g.col_x[g.col_offset + 2]) ÷ 2
_rowy(g, r) = let gr = r + g.row_offset; (g.row_y[gr] + g.row_y[gr + 1]) ÷ 2 end
function _rects(io)
    out = GraphicsRect[]
    for el in io.output.elements
        el = el isa Cell ? el[] : el
        el isa GraphicsRect && push!(out, el)
    end
    out
end

@testset "MouseEnter/Move/Leave drive the whole-row hover" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    # Enter a body cell → its whole row.
    # A hover is view state, and marked so that no history records it.
    @test _rd_marked(io, MouseEnter(_bx(g), _rowy(g, 1), :none, _mods)) isa ReplaceViewStateOperation
    op = _rd(io, MouseEnter(_bx(g), _rowy(g, 1), :none, _mods))
    @test op isa ReplaceReferencedValueOperation && op.document === w && op.value !== nothing
    getfield(w, :hovered)[] = op.value
    row1 = op.value
    # Move within the same row → no churn.
    @test _rd(io, MouseMove(_bx(g) + 2, _rowy(g, 1), :none, _mods)) === nothing
    # Move to another row → a fresh, different write.
    op2 = _rd(io, MouseMove(_bx(g), _rowy(g, 2), :none, _mods))
    @test op2 isa ReplaceReferencedValueOperation && op2.value !== nothing && op2.value != row1
    # Leave → clear.
    op3 = _rd(io, MouseLeave(0, 0, :none, _mods))
    @test op3 isa ReplaceReferencedValueOperation && op3.value === nothing
end

@testset "column header hovers the column; a click still selects" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    chy = (g.row_y[1] + g.row_y[2]) ÷ 2    # grid row 1 = the column-header strip
    op = _rd(io, MouseEnter(_bx(g), chy, :none, _mods))
    @test op isa ReplaceReferencedValueOperation && op.value !== nothing
    hov = op.value
    # Clicking the column header still selects the column (hover didn't shadow the
    # click path). A body cell here holds a WidgetLabel, whose click routes into the
    # non-interactive label, so we assert on the header instead.
    @test _rd(io, MousePress(:left, _bx(g), chy, _mods)) isa ReplaceSelectionOperation
    # The hovered column ref differs from a hovered body row.
    @test hov != _rd(io, MouseEnter(_bx(g), _rowy(g, 1), :none, _mods)).value
end

@testset "hover band renders (faint overlay follows w.hovered)" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    _ = _rects(io)
    # The hover band is the faint (alpha≈0x20) translucent rect; before hovering it
    # is collapsed to 0 height.
    _hover_band(io) = only(r for r in _rects(io) if 0.1 < r.color.alpha[] < 0.2)
    @test Int(_hover_band(io).h[]) == 0
    getfield(w, :hovered)[] = _rd(io, MouseEnter(_bx(g), _rowy(g, 1), :none, _mods)).value
    b = _hover_band(io)
    @test Int(b.h[]) > 0                       # gained the row's height
    @test Int(b.y[]) == g.row_y[1 + g.row_offset]
end

@testset "hover + click reach a table nested in containers" begin
    function reach(doc; xs, ys)
        io = print_document(_rec, doc)
        e = c = 0
        for x in xs, y in ys
            oe = _rd(io, MouseEnter(x, y, :none, _mods))
            oe isa ReplaceReferencedValueOperation && oe.document isa WidgetTable && oe.value !== nothing && (e += 1)
            op = _rd(io, MousePress(:left, x, y, _mods))
            op isa ReplaceSelectionOperation && (c += 1)
        end
        (e, c)
    end
    for doc in (VerticalLayout(Any[_mktable()]),
                WidgetTabbedPane([("Data", VerticalLayout(Any[_mktable()]))]),
                WidgetShell(WidgetTabbedPane([("Data", VerticalLayout(Any[_mktable()]))]);
                            size = Point2D(400, 300)))
        e, c = reach(doc; xs = 0:6:240, ys = 0:6:200)
        @test e > 0     # MouseEnter reaches the table (row hover)
        @test c > 0     # MousePress selects through the container
    end
end

end # @testset
end # function

# A table's header strips stay put while its body scrolls.
#
# The pane freezes and the content declares: `get_frozen_extent` answers the extent of
# the strips, and the pane draws four regions instead of one. A pane over any
# other content answers `nothing` and stays the single viewport it has always
# been.
# A table cell of a column that was given a width clips or wraps by the policy
# of its column, else of its table. The default is one clipped line, because a
# table is a data table until someone says otherwise.
# A table whose columns share an offer ends where the offer does. The grid is
# drawn inside the table's outer rules and padding, so it is offered the width
# less those, and the table is no wider than what its container gave it.
function test_widget_table_fills_offer()
@testset "a table with a weighted column is as wide as its offer" begin
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    table = WidgetTable(Point2D(0, 0), Any["name", "value"], Any[Any["a", "1"], Any["b", "2"]];
                        column_policies = Any[Fill, Fixed(80)])
    for width in (400, 600)
        ctx = with_available_size(PrinterContext(); width = Cell(Int32(width)),
                                  height = Cell(Int32(400)))
        iomap = print_document(rec, nothing, table, ctx)
        @test Int(iomap.output.w[]) == width
        # The last rule is the right edge of the table.
        @test last(iomap.geometry.col_x) + iomap.geometry.bw == width
    end
end
end

# A weighted column with no minimum, in a table whose rows are a vector, is at
# least as wide as its widest cell: the cells clip, so the column reads them
# without offering them its width. Wide, the table fills its offer.
function test_widget_table_content_floor()
@testset "a weighted column is at least as wide as its widest cell" begin
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    grow = SizePolicy(nothing, nothing, nothing, 1.0)
    long = "a cell that is wider than the header"
    table = WidgetTable(Point2D(0, 0), Any["id", "text"], Any[Any["1", long], Any["2", "b"]];
                        column_policies = Any[grow, grow])
    function geometry_at(width)
        ctx = with_available_size(PrinterContext(); width = Cell(Int32(width)),
                                  height = Cell(Int32(400)))
        iomap = print_document(rec, nothing, table, ctx)
        (Int(iomap.output.w[]), iomap.geometry)
    end
    (wide_w, _) = geometry_at(900)
    @test wide_w == 900
    (narrow_w, geometry) = geometry_at(100)
    @test narrow_w > 100
    # The second column's slot holds the long cell.
    slot = geometry.col_x[3] - geometry.col_x[2] - 2 * geometry.pad_x - geometry.bw
    @test slot == 8 * length(long)
end
end

# A shell offers its content the room inside it: its own size when it has one,
# else the space its parent offered. With neither it offers nothing, and a pane in
# it that authors no size is as big as what it holds. It never offers 0, which
# would leave that pane drawing nothing.
function test_shell_offers_only_its_size()
@testset "a shell offers its size, else its parent's offer, and never 0" begin
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    pane() = WidgetScrollPane(WidgetLabel(Point2D(0, 0), "a label"); size = Point2D(0, 0))
    function viewport_of(shell; offered = true)
        ctx = offered ?
            with_available_size(PrinterContext(); width = Cell(Int32(700)), height = Cell(Int32(500))) :
            PrinterContext()
        found = GraphicsViewport[]
        walk(node) = node isa GraphicsViewport ? push!(found, node) :
                     node isa GraphicsCanvas ? foreach(walk, node.elements) : nothing
        walk(print_document(rec, nothing, shell, ctx).output)
        only(found)
    end
    # Inside an offer, a shell with no size draws its content exactly as a shell
    # that authors that size does: the offer is its size.
    offered = viewport_of(WidgetShell(pane()))
    authored = viewport_of(WidgetShell(pane(); size = Point2D(700, 500)))
    @test Int(offered.w) == Int(authored.w)
    @test Int(offered.h) == Int(authored.h)
    @test Int(offered.w) > 600
    # With no offer and no size, the pane is as wide as its label.
    free = viewport_of(WidgetShell(pane()); offered = false)
    @test Int(free.w) == 8 * length("a label")
    sized = viewport_of(WidgetShell(pane(); size = Point2D(400, 300)))
    @test Int(sized.w) > 300
end
end

# A scroll pane reads its size one axis at a time, and 0 on an axis authors
# nothing on it. A pane that authors its height and a width of 0 keeps the
# height and takes the width its parent offers, as a pane that authors no size.
function test_scroll_pane_axis_size()
@testset "a scroll pane with a width of 0 takes the offered width" begin
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    # A label and not a table: a table freezes its header, and a pane over it
    # draws one viewport for each region.
    content() = WidgetLabel(Point2D(0, 0), "a label")
    function viewport(size, width)
        ctx = with_available_size(PrinterContext(); width = Cell(Int32(width)),
                                  height = Cell(Int32(400)))
        out = print_document(rec, nothing, WidgetScrollPane(content(); size = size), ctx).output
        only(e for e in out.elements if e isa GraphicsViewport)
    end
    for width in (400, 600)
        free = viewport(nothing, width)
        tall = viewport(Point2D(0, 100), width)
        @test Int(tall.w) == Int(free.w)
        @test Int(tall.w) > width - 100
        @test Int(tall.h) == 100
    end
    # An authored extent that is a computed cell is followed after the print.
    rows = Cell(100)
    size = Point2D(Cell(0), Cell(100))
    set_cell_function!(getfield(size, :y), () -> rows[])
    ctx = with_available_size(PrinterContext(); width = Cell(Int32(400)), height = Cell(Int32(400)))
    out = print_document(rec, nothing, WidgetScrollPane(content(); size = size), ctx).output
    pane = only(e for e in out.elements if e isa GraphicsViewport)
    @test Int(pane.h) == 100
    rows[] = 160
    @test Int(pane.h) == 160
end
end

function test_widget_table_cell_policy()
@testset "a table cell clips or wraps by policy" begin
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    long = "a value that is far too wide for eighty pixels"
    # The header names are chosen so that neither is a piece of the long cell.
    make(; kw...) = WidgetTable(Point2D(0, 0), Any["AA", "BB"],
                                Any[Any[long, "x"], Any["second", "y"]];
                                column_policies = Any[Fixed(80), Fixed(80)], kw...)
    ctx = with_available_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(400)))
    # Every text a table drew, through the viewports the grid now emits.
    function texts(node, found = String[])
        if node isa GraphicsCanvas
            for element in node.elements
                texts(element, found)
            end
        elseif node isa GraphicsViewport
            texts(node.content, found)
        elseif node isa GraphicsText
            push!(found, string(node.text))
        end
        found
    end
    pieces(io) = count(t -> t != long && length(t) > 1 && occursin(t, long), texts(io.output))

    clipped = print_document(rec, nothing, make(), ctx)
    wrapped = print_document(rec, nothing, make(; cell_policy = :wrap), ctx)
    @testset "the default is one line, and :wrap breaks it into several" begin
        @test long in texts(clipped.output)
        @test pieces(clipped) == 0
        @test pieces(wrapped) > 1
        @test Int(clipped.output.h[]) < Int(wrapped.output.h[])
    end
    @testset "a column's own policy wins over the table's" begin
        mixed = print_document(rec, nothing,
                               make(; cell_policy = :wrap, column_cell_policies = Symbol[:clip]), ctx)
        @test Int(mixed.output.h[]) == Int(clipped.output.h[])
    end
    @testset "a policy that is neither is refused" begin
        @test_throws ErrorException make(; cell_policy = :squash)
    end
    @testset "a plain click on a label cell selects its row" begin
        geometry = clipped.geometry
        x = geometry.col_x[1] + geometry.bw + geometry.pad_x + 2
        y = geometry.row_y[3] + geometry.bw + geometry.pad_y + 2     # body row two
        change = read_intent(rec, nothing, Intent(MousePress(:left, x, y, ModifierKeys()), nothing), clipped)
        op = change isa Intent ? change.operation : change
        @test op isa ReplaceSelectionOperation
        @test op.path.head.name == "rows"
        @test op.path.tail.head.start == 1
        @test op.path.tail.tail isa EmptyReference
    end
    @testset "the padding around a cell is the theme's, one token per axis" begin
        theme = make_slate_light_theme(font = font_ubuntu_regular_20)
        geometry = clipped.geometry
        @test geometry.pad_x == theme.pad_x
        @test geometry.pad_y == theme.pad_y
        # A row is one line of sixteen plus the padding above and below plus
        # the rule: the theme decides the height of a row nobody sized.
        @test geometry.row_y[2] - geometry.row_y[1] == 16 + 2 * theme.pad_y + 1
    end
end
end

function test_frozen_table_headers()
@testset "a table's header strips do not scroll" begin

_det = (t, f) -> (length(t) * 8, 16)
_w2g = WidgetToGraphics(font_ubuntu_regular_20; measure = _det)
_rec = RecursiveProjection(TypeDispatchingProjection(vcat(LayoutToGraphics().dispatch, _w2g.dispatch)))

# Both strips: three columns named, and an ordinal beside each of six rows.
_table() = WidgetTable(Point2D(0, 0);
                       column_headers = Any["ID", "Name", "Role"],
                       row_headers = Any["1", "2", "3", "4", "5", "6"],
                       rows = Any[Any["r$(i)a", "r$(i)b", "r$(i)c"] for i in 1:6],
                       column_count = 3)

# Every viewport of a printed pane, with its box.
function _viewports(node, ox = 0, oy = 0, found = Tuple{Int,Int,Int,Int}[])
    if node isa GraphicsCanvas
        for e in node.elements
            _viewports(e, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        push!(found, (ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h)))
    end
    found
end

@testset "a content with no prefix is one viewport, as it always was" begin
    pane = WidgetScrollPane(WidgetLabel(Point2D(0, 0), "plain"); size = Point2D(120, 60))
    @test length(_viewports(print_document(_rec, pane).output)) == 1
end

@testset "a table is four regions, and they tile the viewport" begin
    pane = WidgetScrollPane(_table(); size = Point2D(200, 100))
    boxes = _viewports(print_document(_rec, pane).output)
    @test length(boxes) == 4
    # The corner is the only one at the pane's own origin, and both strips share
    # one of its edges: that is what tiling means here.
    corner = boxes[end]
    @test corner[3] > 0 && corner[4] > 0
    body = boxes[1]
    @test body[1] == corner[1] + corner[3]
    @test body[2] == corner[2] + corner[4]
    # Nothing reaches past the pane.
    for b in boxes
        @test b[1] + b[3] <= 200 + 1
        @test b[2] + b[4] <= 100 + 1
    end
end

@testset "the column names stay put while the body travels" begin
    held = _table()
    scrolled = WidgetScrollPane(held; size = Point2D(200, 100),
                                scroll_position = Point2D(0, 40))
    boxes = _viewports(print_document(_rec, scrolled).output)
    # The corner and the column-header strip are at the pane's top whatever the
    # scroll is: a held axis does not travel.
    @test boxes[end][2] == 0          # the corner
    @test boxes[2][2] == 0            # the column headers, beside it
    @test boxes[2][1] == boxes[end][3]
    # The body is offset by the scroll, and the row headers travel with it.
    @test boxes[1][2] == boxes[end][4]
    @test boxes[3][1] == 0            # the row headers, under the corner
end

end # @testset
end # function
