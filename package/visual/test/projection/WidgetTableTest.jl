# WidgetTable whole-row hover.
#
# Hovering a body cell (or row header) highlights that row; a column header
# highlights its column; the corner / empty space clears. Hover is transient state
# (`WidgetTable.hovered`) rendered as a faint band, mirroring the selection band.
# Driven by MouseEnter/MouseMove/MouseLeave, which WidgetHoverTrackingProjection
# synthesises. Must also work when the table is nested in a layout / tabbed pane /
# shell (routed via the container crossing routing + the table's 3-arg bridge).

using ProjecturedKernel.CellModule: Cell, ComputedCell

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
_rd(io, g) = begin
    ch = read_intent(_rec, nothing, Intent(g, nothing), io)
    ch isa Intent ? ch.operation : ch
end
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
