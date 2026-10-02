# A child of a grid takes more than one column with
# `LayoutConstraint(child; column_span)`: the grid fills its rows in order, a
# spanning child starts a new row when its row is short, it adds nothing to the
# width of a column, and it breaks its text to the width of the columns that it
# spans.

const _GS_Cell = CellModule.Cell

# The IO map of the grid in what the layout projection printed, found by
# `_at_find_iomap` of the test of the appearance tab.
_gs_grid(iomap) = _at_find_iomap(iomap, GridLayoutIoMap)

# The place of each child of the grid that `iomap` printed, in the frame of the grid.
_gs_places(iomap) = [(Int(x[]), Int(y[])) for (x, y, _) in _gs_grid(iomap).child_iomaps]

function test_grid_span()
@testset "a child of a grid spans columns" begin

proj = make_layout_projection_example()
offer() = with_exact_size(PrinterContext(EmptyReference()); width = _GS_Cell(600), height = _GS_Cell(400))
place = ProjecturedPlatform.LayoutModule._gl_place

@testset "the grid fills its rows in order, and a span takes the columns after it" begin
    @test place([1, 1, 2, 1, 1], 2) == [(1, 1, 1), (1, 2, 1), (2, 1, 2), (3, 1, 1), (3, 2, 1)]
    # A child that takes more columns than its row has left starts the next row.
    @test place([1, 2, 1], 2) == [(1, 1, 1), (2, 1, 2), (3, 1, 1)]
    # A span past the number of columns takes the whole row.
    @test place([5, 1], 2) == [(1, 1, 2), (2, 1, 1)]
    # With every span 1, a child stands where it always stood.
    for c in 1:4, n in 0:9
        @test place(fill(1, n), c) == [(div(i - 1, c) + 1, mod(i - 1, c) + 1, 1) for i in 1:n]
    end
end

@testset "a spanning child gets a row of its own under the row before it" begin
    grid = GridLayout(Any[WidgetLabel("name"), WidgetLabel("control"),
                          LayoutConstraint(WidgetLabel("a note"); column_span = 2),
                          WidgetLabel("next"), WidgetLabel("value")], 2;
                      horizontal_gap = 8, vertical_gap = 4)
    iomap = print_document(proj, nothing, grid, offer())
    places = _gs_places(iomap)
    @test places[3][1] == 0                      # it starts at the first column
    @test places[3][2] > places[1][2]            # under the first row
    @test places[4][2] > places[3][2]            # the next row is under it
    @test places[4][1] == places[1][1] && places[5][1] == places[2][1]   # the columns line up
    @test Int(_gs_grid(iomap).row_count[]) == 3
end

@testset "a spanning child adds nothing to a column, and breaks its text to the columns it spans" begin
    long = "a description that is far longer than the name and the control together, " *
           "so it must break into lines"
    without = GridLayout(Any[WidgetLabel("name"), WidgetLabel("control")], 2; horizontal_gap = 8)
    with = GridLayout(Any[WidgetLabel("name"), WidgetLabel("control"),
                          LayoutConstraint(WidgetLabel(long); column_span = 2)], 2; horizontal_gap = 8)
    plain = print_document(proj, nothing, without, offer())
    spanned = print_document(proj, nothing, with, offer())
    # The grid is as wide as its first row: the long text widened no column.
    @test Int(spanned.output.w[]) == Int(plain.output.w[])
    # The text broke into lines inside the width of the two columns.
    note = last(_gs_grid(spanned).child_iomaps)[3].output
    @test Int(note.w[]) <= Int(spanned.output.w[])
    one_line = print_document(proj, nothing, WidgetLabel("name"), PrinterContext(EmptyReference())).output
    @test Int(note.h[]) > 2 * Int(one_line.h[])
end

end
end
