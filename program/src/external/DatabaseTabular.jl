"""
    DatabaseTabularModule

Bridge module: extends `db_query` with a `TabularGrid` target so callers
can get a plain `TabularGrid` from a database table without needing the full
projection pipeline. The projection type and its IoMap live in
`projection/primitive/DatabaseTableToTabularGrid.jl`.
"""
module DatabaseTabularModule

import DBInterface
import Tables
import ..DatabaseModule: db_query
import ..OdbcAdapterModule: OdbcDatabaseAdapter
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
function db_query(adapter::OdbcDatabaseAdapter, table::String,
                  ::Type{TabularGrid};
                  columns=nothing, where=nothing, limit=nothing)::TabularGrid
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT $(col_part) FROM \"$(table)\""
    where !== nothing && (sql *= " WHERE $(where)")
    limit !== nothing && (sql *= " LIMIT $(limit)")
    ct = Tables.columntable(DBInterface.execute(adapter._conn, sql))
    col_names = String[String(n) for n in propertynames(ct)]
    col_count = length(col_names)
    nrows = col_count == 0 ? 0 : length(ct[1])
    header = Cell(TabularRow(CellVector(
        Cell[Cell(TabularCell(name)) for name in col_names])))
    data_rows = Cell[]
    for r in 1:nrows
        vals = Any[ct[j][r] for j in 1:col_count]
        push!(data_rows, Cell(TabularRow(CellVector(
            Cell[Cell(TabularCell(v)) for v in vals]))))
    end
    TabularGrid(CellVector(vcat([header], data_rows)), col_count)
end

end # module
