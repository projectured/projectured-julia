# A pivot of a data frame: the pivot reads the frame through the table interface
# that `ProjecturedDataFrames` adds, so a part is a `SubDataFrame`, and each sum of
# the pivot is the sum that `groupby` and `combine` of DataFrames give.

"""
    test_pivot_data_frame()

A pivot of a data frame computes the parts that `groupby` finds, a part of the
frame is a `SubDataFrame` that writes the frame, and the natural renderer draws
the pivot with its headers and its sums.
"""
function test_pivot_data_frame()
@testset "a pivot of a data frame" begin

sales = make_pivot_sales_rows()
frame = DataFrames.DataFrame(sales)
pivot = make_pivot_table(frame; rows = ["region", "country"], columns = ["year", "quarter"],
                         measures = [PivotMeasure("amount", :sum)])
cross = pivot.cross_table
grouped = DataFrames.combine(DataFrames.groupby(frame, [:region, :country, :year, :quarter]),
                             :amount => sum => :amount)
@test get_pivot_row_count(cross) * get_pivot_column_count(cross) == DataFrames.nrow(grouped)
for row in eachrow(grouped)
    rows = find_pivot_part_rows(cross, (row.region, row.country), (row.year, row.quarter))
    @test compute_pivot_measure(frame, rows, PivotMeasure("amount", :sum)) == row.amount
end

part = make_table_part(frame, find_pivot_part_rows(cross, 1, 1))
@test part isa DataFrames.SubDataFrame
part[1, "amount"] = 99.0
@test frame[first(find_pivot_part_rows(cross, 1, 1)), "amount"] == 99.0

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(1200)), height = Cell(Int32(400)))
drawn = Set(t[3] for t in ProjecturedPivotTest._pivot_texts(print_document(projection, nothing, pivot, context).output))
@test "EU" in drawn && "NY" in drawn && "2024" in drawn && "Q4" in drawn
@test "99" in drawn

end
end
