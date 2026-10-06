"""
A data frame is a table of the table interface: its columns are the vectors of
the frame, and a part of its rows is a `SubDataFrame`, so an edit of the part
writes the frame.
"""

function test_data_frame_table()
@testset "DataFrameTable" begin

frame = DataFrame(region = ["EU", "US", "EU"], year = [2024, 2024, 2025],
                  amount = Union{Missing,Float64}[12.0, missing, 15.0])
@test is_table(frame)
@test get_table_row_count(frame) == 3
@test get_table_column_names(frame) == ["region", "year", "amount"]
@test get_table_column_type(frame, "amount") == Union{Missing,Float64}
@test get_table_value(frame, 3, "amount") == 15.0
@test find_table_column(frame, "year") === frame.year

part = make_table_part(frame, [3, 1])
@test part isa SubDataFrame
@test is_table(part)
@test get_table_row_count(part) == 2
@test get_table_value(part, 1, "year") == 2025
@test find_table_column(part, "region") == ["EU", "EU"]
inner = make_table_part(part, [2])
@test parent(inner) === frame
@test get_table_value(inner, 1, "year") == 2024

part[1, "amount"] = 16.0
@test frame[3, "amount"] == 16.0

end
end
