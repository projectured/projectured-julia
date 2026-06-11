"""
    DatabaseTabularModule

Bridge module: extends `db_query` with a `TabularGrid` target so callers
can get a plain `TabularGrid` from a database table without needing the full
projection pipeline. The projection type and its IoMap live in
`projection/primitive/DatabaseTableToTabularGrid.jl`.
"""
module DatabaseTabularModule

import LibPQ
import ..DatabaseModule: PostgresDatabaseAdapter, db_query
import ..TabularModule: TabularGrid, TabularRow, TabularCell
import ..CollectionModule: CellVector
import ..ReactiveModule: Cell

"""
    db_query(adapter, table, ::Type{TabularGrid}; columns, where, limit) -> TabularGrid

Single-pass query into a `TabularGrid`. Row 1 is the header (column names as
`TabularCell` values); rows 2..n are data rows. `ctid` is fetched internally
but not included in the grid. Use `DatabaseTableToTabularGrid` projection when
you need the full `DatabaseTableIoMap` with `ctid` values for editing.
"""
function db_query(adapter::PostgresDatabaseAdapter, table::String,
                  ::Type{TabularGrid};
                  columns=nothing, where=nothing, limit=nothing)::TabularGrid
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT $(col_part) FROM \"$(table)\""
    where !== nothing && (sql *= " WHERE $(where)")
    limit !== nothing && (sql *= " LIMIT $(limit)")
    result   = LibPQ.execute(adapter._conn, sql)
    col_names = String[String(n) for n in LibPQ.column_names(result)]
    col_count = length(col_names)
    header = Cell(TabularRow(CellVector(
        Cell[Cell(TabularCell(Cell(name))) for name in col_names])))
    data_rows = Cell[]
    for row in result
        vals = Any[row[i] for i in 1:col_count]
        push!(data_rows, Cell(TabularRow(CellVector(
            Cell[Cell(TabularCell(Cell(v))) for v in vals]))))
    end
    TabularGrid(CellVector(vcat([header], data_rows)), col_count)
end

end # module
