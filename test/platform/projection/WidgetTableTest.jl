# WidgetTable whole-row light.
#
# The pointer over a body cell (or row header) lights that row; over a column
# header it lights the column; the corner or empty space lights nothing. The
# light is a faint band, mirroring the selection band, and it is driven by the
# table's own mouse target: a move writes the path of the part under the
# pointer, and the light follows whatever row or column that path names. Must
# also work when the table is nested in a layout / tabbed pane / shell (a point
# maps backward through the containers, and the mouse target reaches the table).

using ProjecturedKernel.CellModule: Cell, Computation
using ProjecturedPlatform.CollectionModule: ListNode

function test_widget_table()
@testset "WidgetTable hover" begin

_det = FixedMeasure(8, 12, 4, 0)
_w2g = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _det)
# A recursive dispatcher so the table's cell content is recursed (and so a nested
# layout/tab/shell dispatches too), and reads reach the table's readers.
_rec = RecursiveProjection(TypeDispatchingProjection(vcat(LayoutToGraphics().dispatch, _w2g.dispatch)))
_mods = ModifierKeys()
_mktable() = WidgetTable(["ID", "Name"],
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
# The rects of the graphics of the table: the header bands, the bands of the
# hover and of the selection, and the rules. Every region shows them, and the
# region of the cells is the last element of the table.
function _rects(io)
    region = io.output.elements[end]
    graphics = only(e for e in region.elements if e isa GraphicsViewport).content
    GraphicsRect[e for e in graphics.elements if e isa GraphicsRect]
end

@testset "a move over a body cell lights its whole row; a leave clears it" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    driver = MttDriver(_rec, w)
    # A move onto a body cell → its whole row lights.
    _mtt_move!(driver, _bx(g), _rowy(g, 1), 1.0)
    row1 = WidgetModule._find_wt_lit_reference(get_mouse_target(w))
    @test row1 == WidgetModule._wt_row_ref(1)
    # Another cell of the same row → the same light.
    _mtt_move!(driver, _bx(g), _rowy(g, 1), 1.1)
    @test WidgetModule._find_wt_lit_reference(get_mouse_target(w)) == row1
    # Another row → a different light.
    _mtt_move!(driver, _bx(g), _rowy(g, 2), 1.2)
    row2 = WidgetModule._find_wt_lit_reference(get_mouse_target(w))
    @test row2 !== nothing && row2 != row1
    # The table's own reader never answers a motion: the light comes only from
    # the mouse target that a move writes.
    @test _rd(io, MouseMove(_bx(g), _rowy(g, 2), MouseButtons(), _mods; time = 0.0)) === nothing
    # The leave of the window clears the light.
    _mtt_leave!(driver, 1.3)
    @test get_mouse_target(w) === nothing
end

@testset "a move over a column header lights the column; a click still selects" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    chy = (g.row_y[1] + g.row_y[2]) ÷ 2    # grid row 1 = the column-header strip
    driver = MttDriver(_rec, w)
    _mtt_move!(driver, _bx(g), chy, 1.0)
    lit = WidgetModule._find_wt_lit_reference(get_mouse_target(w))
    @test lit == WidgetModule._wt_col_ref(1)
    # Clicking the column header still selects the column (the light does not
    # shadow the click path). A body cell here holds a WidgetLabel, whose click
    # routes into the non-interactive label, so we assert on the header instead.
    @test _rd(io, MouseClick(:left, _bx(g), chy, _mods; time = 0.0)) isa ReplaceSelectionOperation
    # A lit column differs from a lit body row.
    _mtt_move!(driver, _bx(g), _rowy(g, 1), 1.1)
    @test WidgetModule._find_wt_lit_reference(get_mouse_target(w)) != lit
end

@testset "the light band renders (faint overlay follows the mouse target)" begin
    w = _mktable(); io = print_document(_rec, w); g = io.geometry
    _ = _rects(io)
    # The light band is the faint (alpha≈0x20) translucent rect; before the
    # pointer arrives it is collapsed to 0 height.
    _hover_band(io) = only(r for r in _rects(io) if is_color_equal(r.color, get_theme_defaults(WidgetTheme).hover))
    @test Int(_hover_band(io).h[]) == 0
    driver = MttDriver(_rec, w)
    _mtt_move!(driver, _bx(g), _rowy(g, 1), 1.0)
    b = _hover_band(io)
    @test Int(b.h[]) > 0                       # gained the row's height
    @test Int(b.y[]) == g.row_y[1 + g.row_offset]
end

@testset "hover + click reach a table nested in containers" begin
    # Count grid points where a move lights a row and a click selects.
    function reach(table, doc; xs, ys)
        io = print_document(_rec, doc)
        driver = MttDriver(_rec, doc)
        e = c = 0
        time = 0.0
        for x in xs, y in ys
            _mtt_move!(driver, x, y, time += 0.01)
            get_mouse_target(table) !== nothing && (e += 1)
            op = _rd(io, MouseClick(:left, x, y, _mods; time = 0.0))
            op isa ReplaceSelectionOperation && (c += 1)
        end
        (e, c)
    end
    for wrap in (table -> VerticalLayout(Any[table]),
                 table -> WidgetTabbedPane([("Data", VerticalLayout(Any[table]))]),
                 table -> WidgetShell(WidgetTabbedPane([("Data", VerticalLayout(Any[table]))]);
                                      size = Point2D(400, 300)))
        table = _mktable()
        e, c = reach(table, wrap(table); xs = 0:6:240, ys = 0:6:200)
        @test e > 0     # a move lights a row of the table
        @test c > 0     # MouseClick selects through the container
    end
end

end # @testset
end # function

# A table's header strips stay put while its body scrolls.
#
# The table scrolls its own parts: the corner, the header row, the header
# column and the cells are four regions that tile the table. The header row
# follows the cells to the side and the header column follows them down.
# A table cell of a column that was given a width clips or wraps by the policy
# of its column, else of its table. The default is one clipped line, because a
# table is a data table until someone says otherwise.
# A table whose columns share an offer ends where the offer does. The grid is
# drawn inside the table's outer rules and padding, so it is offered the width
# less those, and the table is no wider than what its container gave it.
function test_widget_table_fills_offer()
@testset "a table with a weighted column is as wide as its offer" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    table = WidgetTable(Any["name", "value"], Any[Any["a", "1"], Any["b", "2"]];
                        column_policies = Any[Fill, Fixed(80)])
    for width in (400, 600)
        ctx = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
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
# without offering them its width. The table fills its offer: wide, the columns
# share it; narrow, the columns are wider than the table, which scrolls them.
function test_widget_table_content_floor()
@testset "a weighted column is at least as wide as its widest cell" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    grow = SizePolicy(nothing, nothing, nothing, 1.0)
    long = "a cell that is wider than the header"
    table = WidgetTable(Any["id", "text"], Any[Any["1", long], Any["2", "b"]];
                        column_policies = Any[grow, grow])
    function geometry_at(width)
        ctx = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                              height = Cell(Int32(400)))
        iomap = print_document(rec, nothing, table, ctx)
        (Int(iomap.output.w[]), iomap.geometry)
    end
    (wide_w, _) = geometry_at(900)
    @test wide_w == 900
    (narrow_w, geometry) = geometry_at(100)
    @test narrow_w == 100
    @test geometry.total_w > 100
    # The second column's slot holds the long cell.
    slot = geometry.col_x[3] - geometry.col_x[2] - 2 * geometry.pad_x - geometry.bw
    @test slot == 8 * length(long)
end
@testset "a column that is its content is as wide as its header or its widest cell" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    # The header of the first column is wider than its cell, and the cell of
    # the second wider than its header. The header row and the cells are two
    # grids, and the cells take the width of the header as a floor.
    table = WidgetTable(Any["a long header", "b"], Any[Any["x", "a long cell value"]])
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(400)))
    g = print_document(rec, nothing, table, ctx).geometry
    slot(c) = g.col_x[c + 1] - g.col_x[c] - 2 * g.pad_x - g.bw
    @test slot(1) == 8 * length("a long header")
    @test slot(2) == 8 * length("a long cell value")
end
end

# A shell offers its content the room inside it: its own size when it has one,
# else the space its parent offered. With neither it offers nothing, and a pane in
# it that authors no size is as big as what it holds. It never offers 0, which
# would leave that pane drawing nothing.
function test_shell_offers_only_its_size()
@testset "a shell offers its size, else its parent's offer, and never 0" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    pane() = WidgetScrollPane(WidgetLabel("a label"); size = Point2D(0, 0))
    function viewport_of(shell; offered = true)
        ctx = offered ?
            with_exact_size(PrinterContext(); width = Cell(Int32(700)), height = Cell(Int32(500))) :
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
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    # A label and not a table: a table freezes its header, and a pane over it
    # draws one viewport for each region.
    content() = WidgetLabel("a label")
    function viewport(size, width)
        ctx = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
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
    set_cell_computation!(getfield(size, :y), () -> rows[])
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(400)), height = Cell(Int32(400)))
    out = print_document(rec, nothing, WidgetScrollPane(content(); size = size), ctx).output
    pane = only(e for e in out.elements if e isa GraphicsViewport)
    @test Int(pane.h) == 100
    rows[] = 160
    @test Int(pane.h) == 160
end
end

# A cell sits at the left, in the middle or at the right of its column, by
# `column_align`, in a table whose rows are a vector and in one whose rows are a
# list. A header cell sits as the cells of its column do.
function test_widget_table_column_align()
@testset "a table cell sits where its column aligns" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(400)))
    # The left edge of the first text a canvas drew with each content.
    function lefts(node, ox = 0, found = Dict{String,Int}())
        if node isa GraphicsCanvas
            for element in node.elements
                lefts(element, ox + Int(node.x), found)
            end
        elseif node isa GraphicsViewport
            lefts(node.content, ox + Int(node.x), found)
        elseif node isa GraphicsText
            get!(found, string(node.text), ox + Int(node.x))
        end
        found
    end
    columns = Any[Fixed(120), Fixed(120), Fixed(120)]
    vector(; kw...) = WidgetTable(Any["AA", "BB", "CC"], Any[Any["p", "q", "r"]];
                                  column_policies = columns, kw...)
    list(; kw...) = WidgetTable(; column_headers = Any["AA", "BB", "CC"],
                                rows = ListNode(make_widget_table_row(Any["p", "q", "r"])),
                                column_count = 3, column_policies = columns, kw...)
    for (form, make) in (("rows in a vector", vector), ("rows in a list", list))
        @testset "$form" begin
            plain_io = print_document(rec, nothing, make(), ctx)
            placed_io = print_document(rec, nothing,
                                       make(; column_align = Symbol[:left, :center, :right]), ctx)
            plain, placed = lefts(plain_io.output), lefts(placed_io.output)
            # A list draws its rows as the viewport reaches them, so the x of a
            # body cell is read from the head row that the grid of the cells
            # placed.
            cell_x(io, c) = Int(find_grid_list_row(io.state.cells_pane.content_iomap, 1)[2][c][1][])
            body_shift(c, text) = make === list ? cell_x(placed_io, c) - cell_x(plain_io, c) :
                                                  placed[text] - plain[text]
            # A cell 8 wide in a column 120 wide: none at the left, half the
            # rest in the middle, all of it at the right.
            @test body_shift(1, "p") == 0
            @test body_shift(2, "q") == 56
            @test body_shift(3, "r") == 112
            # The header of each column, 16 wide, the same way.
            @test placed["AA"] == plain["AA"]
            @test placed["BB"] - plain["BB"] == 52
            @test placed["CC"] - plain["CC"] == 104
        end
    end
    @testset "a side that is none of the three is refused" begin
        @test_throws ErrorException vector(; column_align = Symbol[:middle])
    end
end
end

function test_widget_table_cell_policy()
@testset "a table cell clips or wraps by policy" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    long = "a value that is far too wide for eighty pixels"
    # The header names are chosen so that neither is a piece of the long cell.
    make(; kw...) = WidgetTable(Any["AA", "BB"],
                                Any[Any[long, "x"], Any["second", "y"]];
                                column_policies = Any[Fixed(80), Fixed(80)], kw...)
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(400)))
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
        @test clipped.geometry.total_h < wrapped.geometry.total_h
    end
    @testset "a column's own policy wins over the table's" begin
        mixed = print_document(rec, nothing,
                               make(; cell_policy = :wrap, column_cell_policies = Symbol[:clip]), ctx)
        @test mixed.geometry.total_h == clipped.geometry.total_h
    end
    @testset "a policy that is neither is refused" begin
        @test_throws ErrorException make(; cell_policy = :squash)
    end
    @testset "a plain click on a label cell selects its row" begin
        geometry = clipped.geometry
        x = geometry.col_x[1] + geometry.bw + geometry.pad_x + 2
        y = geometry.row_y[3] + geometry.bw + geometry.pad_y + 2     # body row two
        change = read_intent(rec, nothing, Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0), nothing), clipped)
        op = change isa Intent ? change.operation : change
        @test op isa ReplaceSelectionOperation
        @test op.path.head.name == "rows"
        @test op.path.tail.head.start == 1
        @test op.path.tail.tail isa EmptyReference
    end
    @testset "the padding around a cell is the theme's, one token per axis" begin
        scaled = make_scaled_theme(make_slate_light_theme(font = StyleFont("Ubuntu", 20)))
        geometry = clipped.geometry
        @test geometry.pad_x == scaled.control_padding.left[]
        @test geometry.pad_y == scaled.control_padding.top[]
        # A row is one line of sixteen plus the padding above and below plus
        # the rule: the theme decides the height of a row nobody sized.
        @test geometry.row_y[2] - geometry.row_y[1] == 16 + 2 * scaled.control_padding.top[] + 1
    end
end
end

function test_frozen_table_headers()
@testset "a table's header strips do not scroll" begin

_det = FixedMeasure(8, 12, 4, 0)
_w2g = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _det)
_rec = RecursiveProjection(TypeDispatchingProjection(vcat(LayoutToGraphics().dispatch, _w2g.dispatch)))

# Both strips: three columns named, and an ordinal beside each of six rows.
_table() = WidgetTable(;
                       column_headers = Any["ID", "Name", "Role"],
                       row_headers = Any["1", "2", "3", "4", "5", "6"],
                       rows = Any[Any["r$(i)a", "r$(i)b", "r$(i)c"] for i in 1:6],
                       column_count = 3)

# Every text of a printed table, as (x, y, text), through its canvases and
# viewports.
function _texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        for e in node.elements
            _texts(e, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end

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
    pane = WidgetScrollPane(WidgetLabel("plain"); size = Point2D(120, 60))
    @test length(_viewports(print_document(_rec, pane).output)) == 1
end

# The regions of a printed table, as the box of each: the canvases after the
# hit target, which is a rect.
_regions(io) = [(Int(e.x), Int(e.y), Int(e.w), Int(e.h)) for e in io.output.elements
                if e isa GraphicsCanvas]
_sized() = with_exact_size(PrinterContext(); width = Cell(Int32(200)), height = Cell(Int32(100)))

@testset "a table is four regions, and they tile the table" begin
    io = print_document(_rec, nothing, _table(), _sized())
    boxes = _regions(io)
    @test length(boxes) == 4
    corner, header_row, header_column, cells = boxes
    @test corner[1:2] == (0, 0)
    @test corner[3] > 0 && corner[4] > 0
    @test header_row[1:2] == (corner[3], 0)
    @test header_column[1:2] == (0, corner[4])
    @test cells[1:2] == (corner[3], corner[4])
    @test header_row[4] == corner[4]
    @test header_column[3] == corner[3]
    # The cells fill the rest of the table, and nothing reaches past it.
    @test cells[1] + cells[3] == 200
    @test cells[2] + cells[4] == 100
end

@testset "the column names stay put while the body travels" begin
    texts(io) = Dict(t[3] => (t[1], t[2]) for t in _texts(io.output))
    still = texts(print_document(_rec, nothing, _table(), _sized()))
    moved = texts(print_document(_rec, nothing, WidgetTable(;
                       column_headers = Any["ID", "Name", "Role"],
                       row_headers = Any["1", "2", "3", "4", "5", "6"],
                       rows = Any[Any["r$(i)a", "r$(i)b", "r$(i)c"] for i in 1:6],
                       column_count = 3, scroll_position = Point2D(10, 40)), _sized()))
    # The header row travels to the side only, the header column down only,
    # and the cells both ways.
    @test moved["Name"] == (still["Name"][1] - 10, still["Name"][2])
    @test moved["3"] == (still["3"][1], still["3"][2] - 40)
    @test moved["r3b"] == (still["r3b"][1] - 10, still["r3b"][2] - 40)
end

end # @testset
end # function

# A caret in a cell is edited by the readers of the cell. A key the table does not
# take, such as a character, an arrow or Backspace, goes to the cell the selection
# is in, and the answer comes back under `rows[r][c]`. The table whose rows are a
# vector and the table whose rows are a list do the same.
function test_widget_table_cell_editing()
@testset "a key edits the cell the caret is in" begin
    projection = NaturalToGraphics(measure = FixedMeasure(8, 12, 4, 0), font = StyleFont("Ubuntu", 20))
    context = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
    mods = ModifierKeys()
    make_cells() = Any[WidgetText("abc"; width = 80),
                       TextBlock(TextString("prose", StyleFont("Ubuntu", 20), color_default))]
    get_text(cell::WidgetText) = cell.content
    get_text(cell::TextBlock) = cell.elements[1].content
    get_cell(table, c) = table.rows isa ListNode ? table.rows.value[c] : table.rows[1][c]
    # Every text the table drew, through the viewports of its cells, and through
    # the rows a list table built, from its head on.
    function collect_drawn_texts(node, found = String[])
        if node isa GraphicsCanvas && node.elements isa ListNode
            link = node.elements
            while link !== nothing
                collect_drawn_texts(link.value, found)
                link = link.next
            end
        elseif node isa GraphicsCanvas
            foreach(element -> collect_drawn_texts(element, found), node.elements)
        elseif node isa GraphicsViewport
            collect_drawn_texts(node.content, found)
        elseif node isa GraphicsText
            push!(found, string(node.text))
        end
        found
    end
    # The row and the column of the cell a selection `rows[r][c].…` is in.
    get_selected_cell(path) = (path.tail.head.start + 1, path.tail.tail.head.start + 1)
    forms = [
        "rows are a vector" => () -> WidgetTable(Any["A", "B"], Any[make_cells()]),
        "rows are a list" => () -> WidgetTable(; column_headers = Any["A", "B"],
                                               rows = ListNode(make_widget_table_row(make_cells())),
                                               column_count = 2, column_policies = Any[Fixed(120), Fixed(120)]),
    ]
    # A point four pixels inside the left edge of body cell (1, c).
    function get_cell_point(iomap, c)
        iomap = get_content_iomap(iomap)
        if hasproperty(iomap, :geometry)
            g = iomap.geometry
            return (g.col_x[c] + g.grid_off_x + 4, g.row_y[2] + g.grid_off_y + 4)
        end
        st = iomap.state
        (Int(st.edges[][c]) + st.bw + st.pad_x + 4, Int(st.header_height[]) + st.bw + st.pad_y + 4)
    end
    for (form, make_table) in forms, (c, original, edited) in ((1, "abc", "aYbc"), (2, "prose", "pYrose"))
        @testset "$form, cell $c" begin
            table = make_table()
            editor = _WidgetTextMockEditor(table)
            iomap = print_document(projection, nothing, table, context)
            read_key(event) = read_intent(projection, iomap, event)
            x, y = get_cell_point(iomap, c)
            click = read_key(MouseClick(:left, x, y, mods; time = 0.0))
            @test click isa ReplaceSelectionOperation
            evaluate_operation(editor, click)
            @test get_selected_cell(table.selection) == (1, c)
            # The cell holds the caret, at the start of the text. An arrow moves
            # it, and a character goes in where it is.
            @test get_cell(table, c).selection !== nothing
            evaluate_operation(editor, read_key(KeyDown(:right, mods; time = 0.0)))
            typed = read_key(KeyPress('Y', "Y", mods; time = 0.0))
            @test typed isa ReplaceStringRangeOperation
            @test typed.reference.head.name == "rows"
            evaluate_operation(editor, typed)
            @test get_text(get_cell(table, c)) == edited
            @test edited in collect_drawn_texts(iomap.output)
            @test get_selected_cell(table.selection) == (1, c)
            evaluate_operation(editor, read_key(KeyDown(:backspace, mods; time = 0.0)))
            @test get_text(get_cell(table, c)) == original
            @test original in collect_drawn_texts(iomap.output)
            # A selected row is in no cell, and a character goes nowhere.
            evaluate_operation(editor, ReplaceSelectionOperation(make_widget_table_row_selection(1)))
            @test read_key(KeyPress('Z', "Z", mods; time = 0.0)) === nothing
        end
    end
end
end
