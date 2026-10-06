"""
The table interface of `CollectionModule`: a vector of named tuples and a named
tuple of vectors give the same rows, the same columns and the same parts, and a
part of a part is a part of the table.
"""

function test_table_interface()
@testset "TableInterface" begin

rows = [(region = "EU", year = 2024, amount = 12.0),
        (region = "US", year = 2024, amount = 5.0),
        (region = "EU", year = 2025, amount = 15.0)]
columns = (region = ["EU", "US", "EU"], year = [2024, 2024, 2025], amount = [12.0, 5.0, 15.0])

for table in (rows, columns)
    @test is_table(table)
    @test get_table_row_count(table) == 3
    @test get_table_column_names(table) == ["region", "year", "amount"]
    @test get_table_column_type(table, "year") == Int
    @test get_table_value(table, 3, "amount") == 15.0
    part = make_table_part(table, [3, 1])
    @test part isa TablePart
    @test is_table(part)
    @test get_table_row_count(part) == 2
    @test get_table_column_names(part) == ["region", "year", "amount"]
    @test get_table_column_type(part, "amount") == Float64
    @test get_table_value(part, 1, "year") == 2025
    @test get_table_value(part, 2, "region") == "EU"
    inner = make_table_part(part, [2])
    @test inner.table === table
    @test inner.rows == [1]
end

# A kind that holds a column as a vector gives it, and a part gives a view of it.
@test find_table_column(rows, "year") === nothing
@test find_table_column(columns, "year") === columns.year
@test find_table_column(make_table_part(columns, [3, 1]), "year") == [2025, 2024]
@test find_table_column(make_table_part(rows, [3, 1]), "year") === nothing

@test !is_table(42)
@test !is_table("text")
@test !is_table((a = [1, 2], b = [1]))
@test !is_table((a = 1, b = 2))

# Rows of no one type take the names of the first row, and their types are not known.
mixed = NamedTuple[(a = 1, b = "x"), (a = 2.5, b = "y")]
@test get_table_column_names(mixed) == ["a", "b"]
@test get_table_column_type(mixed, "a") == Any
@test get_table_value(mixed, 2, "a") == 2.5
@test get_table_row_count(NamedTuple[]) == 0
@test get_table_column_names(NamedTuple[]) == String[]

end
end
