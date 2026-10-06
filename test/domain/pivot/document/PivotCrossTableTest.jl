"""
The cross table of a pivot: the keys that occur, in the order of each
dimension, the rows of each part, the values that a dimension hides, and the
measures of a part.
"""

function test_pivot_cross_table()
@testset "PivotCrossTable" begin

# ── The keys and the parts ──────────────────────────────────────────────────

table = (region = ["US", "EU", "EU", "US", "EU"], country = ["NY", "FR", "DE", "CA", "DE"],
         year = [2025, 2024, 2024, 2024, 2025], amount = [1.0, 2.0, 3.0, 4.0, 5.0])
rows = [PivotDimension("region"), PivotDimension("country")]
columns = [PivotDimension("year")]
cross = compute_pivot_cross_table(table, rows, columns)
@test cross.row_keys == [("EU", "DE"), ("EU", "FR"), ("US", "CA"), ("US", "NY")]
@test cross.column_keys == [(2024,), (2025,)]
@test get_pivot_row_count(cross) == 4
@test get_pivot_column_count(cross) == 2
@test find_pivot_part_rows(cross, 1, 1) == [3]
@test find_pivot_part_rows(cross, 1, 2) == [5]
@test find_pivot_part_rows(cross, 2, 1) == [2]
@test find_pivot_part_rows(cross, 2, 2) === nothing
@test find_pivot_part_rows(cross, 4, 2) == [1]
@test sum(length(find_pivot_part_rows(cross, r, c)) for r in 1:4, c in 1:2
          if find_pivot_part_rows(cross, r, c) !== nothing) == 5

# A pivot with no dimension on an axis has one key there, the empty tuple.
total = compute_pivot_cross_table(table, PivotDimension[], PivotDimension[])
@test total.row_keys == [()]
@test total.column_keys == [()]
@test find_pivot_part_rows(total, 1, 1) == 1:5

# A part keeps the order of the source.
by_region = compute_pivot_cross_table(table, [PivotDimension("region")], PivotDimension[])
@test find_pivot_part_rows(by_region, 1, 1) == [2, 3, 5]
@test find_pivot_part_rows(by_region, 2, 1) == [1, 4]

# ── The order of the values ─────────────────────────────────────────────────

by_first = compute_pivot_cross_table(table, [PivotDimension("country"; order = :first)], PivotDimension[])
@test by_first.row_keys == [("NY",), ("FR",), ("DE",), ("CA",)]
down = compute_pivot_cross_table(table, [PivotDimension("year"; descending = true)], PivotDimension[])
@test down.row_keys == [(2025,), (2024,)]

# `missing` is a value of its own, last in either direction.
gaps = (kind = ["b", missing, "a", "b"], amount = [1, 2, 3, 4])
up = compute_pivot_cross_table(gaps, [PivotDimension("kind")], PivotDimension[])
@test isequal(up.row_keys, [("a",), ("b",), (missing,)])
@test find_pivot_part_rows(up, 3, 1) == [2]
back = compute_pivot_cross_table(gaps, [PivotDimension("kind"; descending = true)], PivotDimension[])
@test isequal(back.row_keys, [("b",), ("a",), (missing,)])

# Values that `isless` does not compare sort by their texts.
mixed = (kind = Any[2, "a", 1], amount = [1, 2, 3])
@test compute_pivot_cross_table(mixed, [PivotDimension("kind")], PivotDimension[]).row_keys ==
      [(1,), (2,), ("a",)]

# ── Hidden values ───────────────────────────────────────────────────────────

hidden = compute_pivot_cross_table(table, [PivotDimension("country"; hidden_values = Any["FR", "NY"])],
                                   columns)
@test hidden.row_keys == [("CA",), ("DE",)]
@test find_pivot_part_rows(hidden, 2, 1) == [3]
@test find_pivot_part_rows(hidden, 2, 2) == [5]
@test isequal(compute_pivot_cross_table(gaps, [PivotDimension("kind"; hidden_values = Any[missing])],
                                        PivotDimension[]).row_keys, [("a",), ("b",)])

# ── A vector of named tuples and a part of a table ─────────────────────────

sales = make_pivot_sales_rows()
pivot = make_pivot_document_example()
@test pivot isa PivotTable
@test [d.column for d in pivot.unused_dimensions] == ["quarter", "product", "amount"]
@test [d.column for d in pivot.row_dimensions] == ["region", "country"]
example = compute_pivot_cross_table(pivot)
@test example.row_keys == [("EU", "DE"), ("EU", "FR"), ("US", "CA"), ("US", "NY")]
@test example.column_keys == [(2024,), (2025,)]
@test length(find_pivot_part_rows(example, 1, 1)) == 4
part = make_table_part(sales, [1, 2, 9])
@test compute_pivot_cross_table(part, [PivotDimension("country")], PivotDimension[]).row_keys ==
      [("DE",), ("FR",)]

# Every part of every pivot of the sales is the set of rows that a direct filter
# finds, and the keys are the sorted keys that occur.
for (row_names, column_names) in ((["region"], ["year"]), (["region", "country"], ["year", "quarter"]),
                                  (["product"], String[]), (String[], ["country", "product"]))
    found = compute_pivot_cross_table(sales, PivotDimension.(row_names), PivotDimension.(column_names))
    key(row, names) = Tuple(getproperty(row, Symbol(name)) for name in names)
    @test found.row_keys == sort(unique(key(row, row_names) for row in sales))
    @test found.column_keys == sort(unique(key(row, column_names) for row in sales))
    for (r, row_key) in enumerate(found.row_keys), (c, column_key) in enumerate(found.column_keys)
        direct = [k for (k, row) in enumerate(sales)
                  if key(row, row_names) == row_key && key(row, column_names) == column_key]
        part = find_pivot_part_rows(found, r, c)
        @test (part === nothing ? Int[] : collect(part)) == direct
    end
end

# The code of a combination falls back from one `Int` to a vector when the
# counts of the values do not fit.
@test PivotModule._is_radix_size([3, 4])
@test !PivotModule._is_radix_size([typemax(Int) ÷ 2, 3])
value_codes = Vector{Int}[[1, 2, 1, 0], [2, 1, 2, 1]]
small = PivotModule._compute_combination_codes(value_codes, [2, 2], 4, Int)
large = PivotModule._compute_combination_codes(value_codes, [2, 2], 4, Vector{Int})
@test small[1] == large[1] == [1, 2, 1, 0]

# ── Measures ───────────────────────────────────────────────────────────────

values = (amount = Union{Missing,Float64}[4.0, missing, 1.0, 4.0], kind = ["x", "y", "x", "z"])
all_rows = [1, 2, 3, 4]
@test compute_pivot_measure(values, all_rows, PivotMeasure("", :count)) == 4
@test compute_pivot_measure(values, all_rows, PivotMeasure("amount", :sum)) == 9.0
@test compute_pivot_measure(values, all_rows, PivotMeasure("amount", :mean)) == 3.0
@test compute_pivot_measure(values, all_rows, PivotMeasure("amount", :minimum)) == 1.0
@test compute_pivot_measure(values, all_rows, PivotMeasure("amount", :maximum)) == 4.0
@test compute_pivot_measure(values, all_rows, PivotMeasure("amount", :distinct_count)) == 2
@test compute_pivot_measure(values, all_rows, PivotMeasure("kind", :distinct_count)) == 3
@test compute_pivot_measure(values, [2], PivotMeasure("amount", :sum)) == 0
@test ismissing(compute_pivot_measure(values, [2], PivotMeasure("amount", :mean)))
@test compute_pivot_measure(sales, find_pivot_part_rows(example, 1, 1), PivotMeasure("amount", :sum)) ==
      sum(row.amount for row in sales if row.country == "DE" && row.year == 2024)
@test_throws ArgumentError compute_pivot_measure(values, all_rows, PivotMeasure("amount", :median))

# ── make_pivot_table checks its columns ─────────────────────────────────────

@test_throws ArgumentError make_pivot_table(42)
@test_throws ArgumentError make_pivot_table(table; rows = ["nothing here"])

end
end
