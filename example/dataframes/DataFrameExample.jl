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
  step of `0.05`.
"""
function make_data_frame_example(; rows::Integer = 1000)
    DataFrame(
        id = collect(1:rows),
        name = ["item $i" for i in 1:rows],
        price = [round(1 + (i * 7919 % 1000) / 10; digits = 2) for i in 1:rows],
        quantity = [i * 31 % 97 for i in 1:rows],
        in_stock = [i % 3 != 0 for i in 1:rows],
        discount = [i % 5 == 0 ? missing : (i % 4) * 0.05 for i in 1:rows])
end
