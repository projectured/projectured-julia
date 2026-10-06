# ═══════════════════════════════════════════════════════════════════════════
# test/projection/TableSelectionTest.jl
#
# Whole cell / row / column / table selection in the WidgetTable → Graphics
# renderer (the single table abstraction).
#
# A whole-element selection is *not* a distinct reference step: it is just a
# path terminating AT the element, i.e. `∅`. The table renderer — the one place
# that owns the geometry of the grids of its parts — turns a 1-D axis handle into
# a 2-D highlight band. Reference vocabulary on WidgetTable:
#   * whole table   → `∅`
#   * whole row r   → `rows[r]∅`
#   * whole column c→ `columns[c]∅`
#   * header of c   → `column_headers[c]∅`, a part of its own
#   * whole cell    → `cells[r][c]∅`
#   * in-cell cursor→ `cells[r][c].<content-tail>` (draws no band; the cell's own
#                     pipeline draws the caret).
# ═══════════════════════════════════════════════════════════════════════════

# Synthetic monospace metric → deterministic geometry, no SDL fonts needed.
_table_measure() = FixedMeasure(10, 15, 5, 0)

# Reference builders in the WidgetTable vocabulary.
_wt_row(r)     = ConcreteReference(FieldReferenceStep("rows"),
                    ConcreteReference(ElementReferenceStep(r), EmptyReference()))
_wt_col(c)     = ConcreteReference(FieldReferenceStep("columns"),
                    ConcreteReference(ElementReferenceStep(c), EmptyReference()))
_wt_column_header(c) = ConcreteReference(FieldReferenceStep("column_headers"),
                    ConcreteReference(ElementReferenceStep(c), EmptyReference()))
_wt_row_header(r) = ConcreteReference(FieldReferenceStep("row_headers"),
                    ConcreteReference(ElementReferenceStep(r), EmptyReference()))
_wt_cell(r, c) = ConcreteReference(FieldReferenceStep("cells"),
                    ConcreteReference(ElementReferenceStep(r),
                        ConcreteReference(ElementReferenceStep(c), EmptyReference())))

# The translucent selection band(s) in the graphics of the table (a quarter
# opaque, as the theme makes the band of a selected row),
# which every region of the table shows, materialised to value tuples
# *immediately*. The band is a single persistent
# reactive overlay whose (x, y, w, h) cells read the LIVE `w.selection`, so holding
# the `GraphicsRect` and reading its cells later would report whichever selection is
# current then — not the one active at this print. Snapshotting here pins each band
# to the selection that produced it. A 0×0 band (no whole-element selection — e.g. an
# in-cell cursor) draws nothing and is filtered out. The region of the cells is
# the last element of the table, and its graphics are in its first viewport.
function _table_highlights(io)
    bands = @NamedTuple{x::Int, y::Int, w::Int, h::Int}[]
    region = io.output.elements[end]
    graphics = only(e for e in region.elements if e isa GraphicsViewport).content
    for c in collect(graphics.elements)
        (c isa GraphicsRect && c.color.alpha ≈ 0.25) || continue
        x, y, w, h = Int(c.x[]), Int(c.y[]), Int(c.w[]), Int(c.h[])
        (w > 0 && h > 0) || continue
        push!(bands, (x = x, y = y, w = w, h = h))
    end
    bands
end

function _print_with(doc, proj, path)
    clear_selection!(doc)
    path === nothing || set_selection!(doc, path)
    print_document(proj, doc)
end

function test_table_selection()
@testset "TableSelection" begin

@testset "highlight band extent per shape (with headers)" begin
    m = _table_measure()
    doc = make_math_table_document_example()        # 3×3 with row + column headers
    proj = make_math_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))

    table_hs = th(EmptyReference())
    row_hs   = th(_wt_row(2))
    col_hs   = th(_wt_col(3))
    cell_hs  = th(_wt_cell(2, 3))     # row 2, column 3 = intersection of the bands
    header_hs = th(_wt_column_header(3))
    row_header_hs = th(_wt_row_header(2))

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

    # A header is a part of its own: the cell of the header of its column, or of
    # its row, and not the column or the row.
    H, RH = only(header_hs), only(row_header_hs)
    @test H.x == C.x && H.w == C.w && H.y == 0 && 0 < H.h < C.h
    @test RH.y == R.y && RH.h == R.h && RH.x == 0 && 0 < RH.w < R.w
end

@testset "a whole column is a path that a table evaluates" begin
    doc = make_math_table_document_example()
    column = try_evaluate_reference(doc, _wt_col(2))
    @test column isa WidgetTableColumn && column.index == 2
    set_selection!(doc, _wt_col(2))
    @test strip_reference_types(get_selection(doc)) == _wt_col(2)
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

    # A content cursor (`cells[1][1].value`, inside the PrimitiveNumber cell) is not
    # a whole-element shape: the band collapses to 0×0 (draws nothing), so no visible
    # band. (cells[2][2] is a MathBinaryOperation with no `.value` — an unselectable
    # path — so use the primitive cell the click test below also lands on.)
    inner = ConcreteReference(FieldReferenceStep("cells"),
                ConcreteReference(ElementReferenceStep(1),
                    ConcreteReference(ElementReferenceStep(1),
                        ConcreteReference(FieldReferenceStep("value"), EmptyReference()))))
    @test isempty(_table_highlights(_print_with(doc, proj, inner)))

    # A plain left click routes into the clicked cell's content, landing on a
    # `cells[r][c].…` cursor.
    io = _print_with(doc, proj, nothing)
    geom = io.geometry
    gc = 1 + geom.col_offset
    gr = 1 + geom.row_offset
    cx = geom.col_x[gc] + geom.bw + geom.pad_x + 1
    cy = geom.row_y[gr] + geom.bw + geom.pad_y + 1
    op = read_intent(proj, io, MouseClick(:left, cx, cy, ModifierKeys(); time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test startswith(string(op.path), ".cells[1][1]")
end

@testset "JSON table (column headers only) bands rows/columns/cells" begin
    m = _table_measure()
    doc = make_table_document_example()             # 3×3 JSON cells, column headers, no row headers
    proj = make_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))
    @test length(th(EmptyReference())) == 1     # whole table
    @test length(th(_wt_row(2))) == 1               # row band
    @test length(th(_wt_col(2))) == 1               # column band
    @test length(th(_wt_cell(2, 2))) == 1           # cell band
end

end # @testset "TableSelection"
end # test_table_selection
