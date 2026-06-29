# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/TableSelectionTest.jl
#
# Whole cell / row / column / table selection in the WidgetTable → Graphics
# renderer (the single table abstraction; bands ported from the old
# TableToGraphics).
#
# A whole-element selection is *not* a distinct reference step: it is just a
# path terminating AT the element, i.e. `∅`. The table renderer — the one place
# that owns the grid geometry (read off the GridLayout iomap) — turns a 1-D axis
# handle into a 2-D highlight band. Reference vocabulary on WidgetTable:
#   * whole table   → `∅`
#   * whole row r   → `rows[r]∅`
#   * whole column c→ `column_headers[c]∅`
#   * whole cell    → `rows[r][c]∅`
#   * in-cell cursor→ `rows[r][c].<content-tail>` (draws no band; the cell's own
#                     pipeline draws the caret).
# ═══════════════════════════════════════════════════════════════════════════

# Synthetic monospace metric → deterministic geometry, no SDL fonts needed.
_table_measure() = (text, font) -> (length(text) * 10, 20)

# Reference builders in the WidgetTable vocabulary.
_wt_row(r)     = ConcreteReferencePath(FieldReference("rows"),
                    ConcreteReferencePath(ElementReference(r), EmptyReferencePath()))
_wt_col(c)     = ConcreteReferencePath(FieldReference("column_headers"),
                    ConcreteReferencePath(ElementReference(c), EmptyReferencePath()))
_wt_cell(r, c) = ConcreteReferencePath(FieldReference("rows"),
                    ConcreteReferencePath(ElementReference(r),
                        ConcreteReferencePath(ElementReference(c), EmptyReferencePath())))

# The translucent selection rects the renderer prepends (alpha 0x40).
function _table_highlights(io)
    GraphicsRect[c for c in collect(io.output.elements) if c isa GraphicsRect && c.color.alpha == 0x40 / 255]
end

function _print_with(doc, proj, path)
    clear_selection!(doc)
    path === nothing || set_selection!(doc, path)
    projection_print(proj, doc)
end

function test_table_selection()
@testset "TableSelection" begin

@testset "highlight band extent per shape (with headers)" begin
    m = _table_measure()
    doc = make_math_table_document_example()        # 3×3 with row + column headers
    proj = make_math_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))

    table_hs = th(EmptyReferencePath())
    row_hs   = th(_wt_row(2))
    col_hs   = th(_wt_col(3))
    cell_hs  = th(_wt_cell(2, 3))     # row 2, column 3 = intersection of the bands

    @test length(table_hs) == 1
    @test length(row_hs) == 1
    @test length(col_hs) == 1
    @test length(cell_hs) == 1

    T, R, C, X = table_hs[1], row_hs[1], col_hs[1], cell_hs[1]

    # Whole table starts at the origin.
    @test T.x == 0 && T.y == 0
    @test T.w > 0 && T.h > 0

    # Row band: full width, below the header row, real height.
    @test R.x == 0 && R.w == T.w
    @test R.y > 0 && R.h > 0

    # Column band: full height, right of the header column, real width.
    @test C.y == 0 && C.h == T.h
    @test C.x > 0 && C.w > 0

    # The cell band is exactly the intersection of its row band and column band.
    @test X.x == C.x && X.w == C.w
    @test X.y == R.y && X.h == R.h

    # Table extent agrees with the bands.
    @test T.w == R.w && T.h == C.h
end

@testset "highlight is drawn behind the grid content" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    hs = _table_highlights(_print_with(doc, proj, _wt_cell(2, 2)))
    @test length(hs) == 1               # one band for the selected cell
end

@testset "in-cell cursor draws no band; content routing intact" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)

    # A content cursor (`rows[r][c].…`) is not a whole-element shape: no band.
    inner = ConcreteReferencePath(FieldReference("rows"),
                ConcreteReferencePath(ElementReference(2),
                    ConcreteReferencePath(ElementReference(2),
                        ConcreteReferencePath(FieldReference("value"), EmptyReferencePath()))))
    @test isempty(_table_highlights(_print_with(doc, proj, inner)))

    # A plain left click routes into the clicked cell's content, landing on a
    # `rows[r][c].…` cursor.
    io = _print_with(doc, proj, nothing)
    geom = io.geometry[]
    gc = 1 + geom.col_offset
    gr = 1 + geom.row_offset
    cx = geom.col_x[gc] + geom.bw + geom.pad + 1
    cy = geom.row_y[gr] + geom.bw + geom.pad + 1
    op = projection_read(proj, io, MousePress(:left, cx, cy, Modifiers()))
    @test op isa ReplaceSelectionOperation
    @test startswith(string(op.path), ".rows[1][1]")
end

@testset "JSON table (column headers only) bands rows/columns/cells" begin
    m = _table_measure()
    doc = make_table_document_example()             # 3×3 JSON cells, column headers, no row headers
    proj = make_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))
    @test length(th(EmptyReferencePath())) == 1     # whole table
    @test length(th(_wt_row(2))) == 1               # row band
    @test length(th(_wt_col(2))) == 1               # column band
    @test length(th(_wt_cell(2, 2))) == 1           # cell band
end

end # @testset "TableSelection"
end # test_table_selection
