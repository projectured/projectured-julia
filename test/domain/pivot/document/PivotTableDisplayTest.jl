"""
The display of a pivot, which the REPL and the answer of a tool show: the line
of its zones, the grid of its values, and a limited display that leaves out rows
and columns and says so.
"""

function test_pivot_table_display()
@testset "the display of a pivot" begin

sales = make_pivot_sales_rows()
shown(pivot; context...) = sprint(show, MIME"text/plain"(), pivot; context = (context...,))

# ── The zones and the grid ──────────────────────────────────────────────────

pivot = make_pivot_document_example()
@test shown(pivot) == """
    PivotTable of 32 source rows. Fields (unused_dimensions): quarter, product, amount. \
    Columns (column_dimensions): year. Rows (row_dimensions): region, country. \
    Cells (cell_dimensions, cell_view): as numbers (automatic). Values (measures): sum(amount). \
    Totals (totals): hidden.
    region  country  2024  2025
    EU      DE         60    80
    EU      FR        100   120
    US      CA        140   160
    US      NY        180   200
    """

# With no column dimension, the one column is headed by the names of the measures.
by_region = make_pivot_table(sales; rows = ["region"], measures = [PivotMeasure("amount", :sum), PivotMeasure("", :count)])
@test endswith(shown(by_region), """
    region  sum(amount)  count
    EU              360     16
    US              680     16
    """)
# With a column dimension, a line under its values names each measure.
by_region_year = make_pivot_table(sales; rows = ["region"], columns = ["year"],
                                  measures = [PivotMeasure("amount", :sum), PivotMeasure("", :count)])
@test endswith(shown(by_region_year), """
                   2024   2024         2025   2025
    region  sum(amount)  count  sum(amount)  count
    EU              160      8          200      8
    US              320      8          360      8
    """)

# The totals, a closed run and two column dimensions show as the table shows them.
getfield(pivot, :totals)[] = true
getfield(pivot, :collapsed)[] = Any[("US",)]
quarters = shown(pivot)
@test occursin("Totals (totals): shown. Closed runs (collapsed): 1.", quarters)
@test occursin("\n▸ US    total     320   360    680\n", quarters)
@test occursin("\ntotal   total     480   560   1040\n", quarters)
two = make_pivot_table(sales; rows = ["region"], columns = ["year", "quarter"])
@test occursin("\n        2024  2024  2024  2024  2025  2025  2025  2025\nregion    Q1    Q2    Q3    Q4    Q1    Q2    Q3    Q4\n", shown(two))

# ── A limited display ───────────────────────────────────────────────────────

pivot = make_pivot_document_example()
@test endswith(shown(pivot; limit = true, displaysize = (8, 30)), """
    US      CA        140   160
    ⋮ 1 row more. `find_pivot_value(pivot, row_key, column_key)` reads one cell.""")
@test endswith(shown(pivot; limit = true, displaysize = (8, 24)), """
    region  country  2024
    EU      DE         60
    EU      FR        100
    US      CA        140
    ⋮ 1 row and 1 column more. `find_pivot_value(pivot, row_key, column_key)` reads one cell.""")

# A limited display lists the first eight names of the Fields zone.
wide = NamedTuple{Tuple(Symbol.("c", 1:12))}(Tuple([1, 2] for _ in 1:12))
@test occursin("Fields (unused_dimensions): c2, c3, c4, c5, c6, c7, c8, c9, and 3 more. Columns (column_dimensions): none.",
               shown(make_pivot_table(wide; rows = ["c1"]); limit = true))

end
end
