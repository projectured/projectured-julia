# Fragment of `OdbcModule`.
#
import ProjecturedKernel.CellModule: Cell, Computation, @computation
import ProjecturedPlatform.CollectionModule: CellVector, CellTable
import ProjecturedKernel.ProjectionModule: print_document, read_intent,
                              map_reference_forward, Projection, find_introduced_path
import ProjecturedSQL.SqlModule: SqlSelectStatement
import ProjecturedSQL.SqlModule: SqlToSyntax
import ProjecturedPlatform.SyntaxModule: SyntaxToText
import ProjecturedPlatform.TextModule: TextToString
import ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection
import ProjecturedPlatform.ProjectionAlgebraModule: ChainingProjection
import ProjecturedDatabase.DatabaseModule: DatabaseInstance
import ProjecturedDatabase.DatabaseModule: RawDatabaseResult, execute_db_raw
import ProjecturedKernel.IoMapModule: SimpleIoMap


struct SqlToCellTable <: Projection
    pool::OdbcConnectionPool
    instance::DatabaseInstance
end

function print_document(p::SqlToCellTable, recursion, stmt::SqlSelectStatement, ctx)
    raw = Cell(@computation begin
        pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql = print_document(pipe, stmt).output
        with_connection(p.pool, p.instance) do adapter
            execute_db_raw(adapter, sql, RawDatabaseResult)
        end
    end)
    rows = CellVector(@computation begin
        r = raw[]
        header = CellVector(r.columns)               # row 1: column names
        data   = [CellVector(row) for row in r.rows]  # rows 2..n: data rows
        vcat([header], data)
    end)
    SimpleIoMap(p, stmt, CellTable(rows, Cell(nothing)))
end

# No caret goes into the result. The default backward mapping names a part of the
# result table by an introduced reference, and only such a reference maps forward
# again.
map_reference_forward(p::SqlToCellTable, iomap, reference) = find_introduced_path(p, reference)
read_intent(::SqlToCellTable, iomap, op) = nothing
