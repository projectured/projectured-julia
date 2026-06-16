"""
    SqlToCellTableModule

Projection: `SqlSelectStatement` → `CellTable` (the query result).

`SqlToCellTable(pool, instance)` prints the statement through the projection
pipeline (`SqlToSyntax → SyntaxToText → TextToString`), executes it against
`instance` through the connection `pool`, and materialises the result as a
`CellTable`: row 1 holds the column names, rows 2..n hold the data. The query
runs inside a reactive `Cell` thunk, so it fires lazily on first force and
re-runs when the statement changes — constructing the document never touches
the database.

The connection pool and the target `DatabaseInstance` are **projection
parameters**; the SQL statement itself stays database-agnostic.

Read-only (v1): no reference mapping or read support yet.
"""
module SqlToCellTableModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector, CellTable
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..SqlDocumentModule: SqlSelectStatement
import ..SqlToSyntaxModule: SqlToSyntax
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..RecursiveProjectionModule: RecursiveProjection
import ..SequentialProjectionModule: SequentialProjection
import ..DatabaseInstanceDocumentModule: DatabaseInstance
import ..DatabaseModule: RawDatabaseResult, db_execute_raw
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ..IoMapModule: SimpleIoMap

export SqlToCellTable

struct SqlToCellTable <: Projection
    pool::OdbcConnectionPool
    instance::DatabaseInstance
end

function projection_print(p::SqlToCellTable, recursion, stmt::SqlSelectStatement, ctx)
    raw = Cell(() -> begin
        pipe = SequentialProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql = projection_print(pipe, stmt).output[]
        with_connection(p.pool, p.instance) do adapter
            db_execute_raw(adapter, sql, RawDatabaseResult)
        end
    end)
    rows = CellVector(() -> begin
        r = raw[]
        header = CellVector(r.columns)               # row 1: column names
        data   = [CellVector(row) for row in r.rows]  # rows 2..n: data rows
        vcat([header], data)
    end)
    SimpleIoMap(p, stmt, CellTable(rows, Cell(nothing)))
end

map_reference_forward(::SqlToCellTable, iomap, ref) = nothing
map_reference_backward(::SqlToCellTable, iomap, ref) = nothing
projection_read(::SqlToCellTable, iomap, op) = nothing

end # module
