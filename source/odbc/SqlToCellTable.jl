module SqlToCellTableModule

import ProjecturedKernel.CellModule: Cell, ComputedCell
import ProjecturedCollection.CollectionModule: CellVector, ComputedCellVector, CellTable
import ProjecturedKernel.ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedSql.SqlDocumentModule: SqlSelectStatement
import ProjecturedSql.SqlToSyntaxModule: SqlToSyntax
import ProjecturedSyntax.SyntaxToTextModule: SyntaxToText
import ProjecturedText.TextToStringModule: TextToString
import ProjecturedProjection.RecursiveProjectionModule: RecursiveProjection
import ProjecturedProjection.ChainingProjectionModule: ChainingProjection
import ProjecturedDatabase.DatabaseInstanceDocumentModule: DatabaseInstance
import ProjecturedDatabase.DatabaseModule: RawDatabaseResult, execute_db_raw
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ProjecturedKernel.IoMapModule: SimpleIoMap

export SqlToCellTable

struct SqlToCellTable <: Projection
    pool::OdbcConnectionPool
    instance::DatabaseInstance
end

function print_document(p::SqlToCellTable, recursion, stmt::SqlSelectStatement, ctx)
    raw = ComputedCell(() -> begin
        pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql = print_document(pipe, stmt).output
        with_connection(p.pool, p.instance) do adapter
            execute_db_raw(adapter, sql, RawDatabaseResult)
        end
    end)
    rows = ComputedCellVector(() -> begin
        r = raw[]
        header = CellVector(r.columns)               # row 1: column names
        data   = [CellVector(row) for row in r.rows]  # rows 2..n: data rows
        vcat([header], data)
    end)
    SimpleIoMap(p, stmt, CellTable(rows, Cell(nothing)))
end

map_reference_forward(::SqlToCellTable, iomap, ref) = nothing
map_reference_backward(::SqlToCellTable, iomap, ref) = nothing
read_intent(::SqlToCellTable, iomap, op) = nothing

end # module SqlToCellTableModule
