# Fragment of `ProjecturedDataFramesExample` — the one factory the package
# holds, built by formula rather than by a random draw.

"""
    make_data_frame_example(; rows::Integer = 1000) -> DataFrame

A `DataFrame` of `rows` rows and six columns, deterministic so a test or a
gallery reads the same table every run:

- `id::Int` — `1:rows`.
- `name::String` — `"item \$i"`.
- `price::Float64` — a formula over `i`, rounded to two decimal places.
- `quantity::Int` — a formula over `i`, spread across `0:96`.
- `in_stock::Bool` — `true` for two rows out of three.
- `discount::Union{Missing, Float64}` — `missing` for one row in five, else a
  step of `0.05`, which prints with two decimal places at most.
"""
function make_data_frame_example(; rows::Integer = 1000)
    DataFrame(
        id = collect(1:rows),
        name = ["item $i" for i in 1:rows],
        price = [round(1 + (i * 7919 % 1000) / 10; digits = 2) for i in 1:rows],
        quantity = [i * 31 % 97 for i in 1:rows],
        in_stock = [i % 3 != 0 for i in 1:rows],
        discount = Union{Missing, Float64}[i % 5 == 0 ? missing : (i % 4) * 5 / 100
                                           for i in 1:rows])
end

"""
    make_data_frame_navigator_example(; rows::Integer = 1000) -> Navigator

A navigator on the view of `make_data_frame_example(; rows)`, with the table as
its first page. A double click on the number of a row, or Ctrl+Return on a
selected row, opens the row as a page, a form of its columns. Back returns to the
table with the row selected, Parent goes from a row to the table, and the arrow
before "row r" in the address lists the other rows.
"""
make_data_frame_navigator_example(; rows::Integer = 1000) =
    Navigator(DataFrameView(make_data_frame_example(; rows)))
