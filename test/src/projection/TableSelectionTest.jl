# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/TableSelectionTest.jl
#
# Whole cell / row / column / table selection in the Table → Graphics
# projection (plan/pending/table-selection.md, phase 1).
#
# A whole-element selection is *not* a distinct reference step: it is just a
# path terminating AT the element, i.e. `∅`. The table projection — the one
# place that owns the grid geometry — turns a 1-D axis handle (`.rows[r]∅` /
# `.columns[c]∅`) into a 2-D highlight band. These tests pin:
#   * set_selection!/clear_selection! placing `∅` at the table / row / column /
#     cell node (and `nothing` everywhere else),
#   * the highlight layer emitting one translucent rect of the right extent for
#     each shape, drawn behind the grid,
#   * an in-cell cursor (`.cells[idx].content.…`) drawing no band, and the
#     existing cell-content cursor routing still working through a plain click.
# ═══════════════════════════════════════════════════════════════════════════

# Synthetic monospace metric → deterministic geometry, no SDL fonts needed.
_table_measure() = (text, font) -> (length(text) * 10, 20)

# The translucent selection rects the projection prepends (alpha 0x40).
function _table_highlights(io)
    GraphicsRect[c for c in collect(io.output.elements) if c isa GraphicsRect && c.a == 0x40]
end

function _print_with(doc, proj, path)
    clear_selection!(doc)
    path === nothing || set_selection!(doc, path)
    projection_print(proj, doc)
end

function test_table_selection()
@testset "TableSelection" begin

selof(x) = getfield(x, :selection)[]

@testset "set/clear_selection! place ∅ at the target node" begin
    doc = make_math_table_document_example()  # 3×3 with row + column headers

    # whole table: ∅ lands on the table node itself.
    set_selection!(doc, EmptyReferencePath())
    @test selof(doc) isa EmptyReferencePath
    clear_selection!(doc)
    @test selof(doc) === nothing

    # whole row 2: the table holds `.rows[2]` (non-empty), the row holds ∅,
    # siblings stay nothing — the tree-position invariant.
    set_selection!(doc, @reference rows[2])
    @test selof(doc) isa ConcreteReferencePath
    @test !isempty(selof(doc))
    @test selof(doc.rows[2]) isa EmptyReferencePath
    @test selof(doc.rows[1]) === nothing
    clear_selection!(doc)
    @test selof(doc) === nothing
    @test selof(doc.rows[2]) === nothing

    # whole column 3.
    set_selection!(doc, @reference columns[3])
    @test selof(doc.columns[3]) isa EmptyReferencePath
    @test selof(doc.columns[1]) === nothing
    clear_selection!(doc)

    # whole cell idx 5 (row 2, column 2).
    set_selection!(doc, @reference cells[5])
    @test selof(doc.cells[5]) isa EmptyReferencePath
    @test selof(doc.cells[4]) === nothing
    clear_selection!(doc)
    @test selof(doc.cells[5]) === nothing
end

@testset "highlight band extent per shape (with headers)" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))

    table_hs = th(EmptyReferencePath())
    row_hs   = th(@reference rows[2])
    col_hs   = th(@reference columns[3])
    cell_hs  = th(@reference cells[6])     # row 2, column 3 = intersection of the two bands

    @test length(table_hs) == 1
    @test length(row_hs) == 1
    @test length(col_hs) == 1
    @test length(cell_hs) == 1

    T, R, C, X = table_hs[1], row_hs[1], col_hs[1], cell_hs[1]

    # Whole table starts at the origin.
    @test T.x == 0 && T.y == 0
    @test T.w > 0 && T.h > 0

    # Row band: full width, somewhere below the header row, real height.
    @test R.x == 0 && R.w == T.w
    @test R.y > 0 && R.h > 0

    # Column band: full height, to the right of the header column, real width.
    @test C.y == 0 && C.h == T.h
    @test C.x > 0 && C.w > 0

    # The cell band is exactly the intersection of its row band and column band.
    @test X.x == C.x && X.w == C.w
    @test X.y == R.y && X.h == R.h

    # Table extent agrees with the bands.
    @test T.w == R.w && T.h == C.h
end

@testset "highlight is drawn behind the grid" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    els = collect(_print_with(doc, proj, @reference cells[5]).output.elements)
    @test els[1] isa GraphicsRect
    @test (els[1]::GraphicsRect).a == 0x40   # the highlight, ahead of all grid lines
end

@testset "in-cell cursor draws no band; content routing intact" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)

    # A content cursor (`.cells[idx].content.…`) is not a whole-element shape:
    # no band is painted here — the cell's own pipeline draws the caret.
    inner = ConcreteReferencePath(FieldReference("cells"),
                ConcreteReferencePath(ElementReference(5),
                    ConcreteReferencePath(FieldReference("content"), EmptyReferencePath())))
    @test isempty(_table_highlights(_print_with(doc, proj, inner)))

    # A plain left click still routes into the clicked cell's content, landing
    # on a `.cells[idx].content.…` cursor (existing behaviour, unchanged).
    io = _print_with(doc, proj, nothing)
    geom = io.child_iomap.geometry[]    # NestingProjection wraps the table iomap
    # Click squarely inside the first data cell (row 1, column 1).
    gc = 1 + geom.col_offset
    gr = 1 + geom.row_offset
    cx = geom.col_x[gc] + geom.bw + geom.pad + 1
    cy = geom.row_y[gr] + geom.bw + geom.pad + 1
    op = projection_read(proj, io, MousePress(:left, cx, cy, Modifiers()))
    @test op isa ReplaceSelectionOperation
    s = string(op.path)
    @test startswith(s, ".cells[1].content")
end

@testset "headerless table still bands rows/columns/cells" begin
    m = _table_measure()
    doc = make_table_document_example()             # 4×3, no axis headers
    proj = make_table_projection_example(measure=m)

    th(path) = _table_highlights(_print_with(doc, proj, path))
    @test length(th(EmptyReferencePath())) == 1     # whole table
    @test length(th(@reference rows[2])) == 1       # row band, reachable by keyboard
    @test length(th(@reference columns[2])) == 1    # column band
    @test length(th(@reference cells[5])) == 1      # cell band

    # With no header strips, a click in the top-left lands on a data cell, not a
    # corner/header — so it routes into content rather than selecting an axis.
    io = _print_with(doc, proj, nothing)
    op = projection_read(proj, io, MousePress(:left, 5, 5, Modifiers()))
    @test op isa ReplaceSelectionOperation
    @test startswith(string(op.path), ".cells[1].content")
end

end # @testset "TableSelection"
end # test_table_selection
