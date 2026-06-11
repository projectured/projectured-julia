"""
    SqlDocumentModule

A minimal SQL statement document. This is the v1 AST: enough to express
`SELECT * FROM <table>`, shaped so it can grow (a select list of items, an
explicit FROM table reference, and reserved `where_clause` / `limit` slots).

The AST is database-agnostic — it carries no connection. Projections render it:
`SqlToSyntax` produces a syntax tree for display, and `SqlToCellTable` executes
it against a `DatabaseInstance` (through a connection pool) and returns the
result rows. `render_sql` produces the canonical executable SQL string.
"""
module SqlDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export SqlDocument, SqlStatement, SqlSelectStatement,
       SqlAllColumns, SqlTableReference,
       ISqlSelectStatement, ISqlAllColumns, ISqlTableReference,
       render_sql

abstract type SqlDocument <: Document end
abstract type SqlStatement <: SqlDocument end

# ── SqlAllColumns ───────────────────────────────────────────────────────────────
# The `*` select item.

@document struct SqlAllColumns <: SqlDocument
    selection::Reference
end
SqlAllColumns() = SqlAllColumns(Cell(nothing))

# ── SqlTableReference ───────────────────────────────────────────────────────────
# A `FROM <table>` reference.

@document struct SqlTableReference <: SqlDocument
    name::String
    selection::Reference
end
SqlTableReference(name::AbstractString) = SqlTableReference(String(name), Cell(nothing))

# ── SqlSelectStatement ──────────────────────────────────────────────────────────
# `SELECT <select_list> FROM <from>`. `where_clause` and `limit` are reserved
# (always `nothing` in v1) so the struct stays stable as the AST grows.

@document struct SqlSelectStatement <: SqlStatement
    select_list::CellVector       # items, e.g. [SqlAllColumns()]
    from::SqlTableReference
    where_clause::Any             # reserved (nothing in v1)
    limit::Any                    # reserved (nothing in v1)
    selection::Reference
end

SqlSelectStatement(select_list::CellVector, from::SqlTableReference) =
    SqlSelectStatement(select_list, from, Cell(nothing), Cell(nothing), Cell(nothing))

# Convenience: `SELECT * FROM <table-name>`
SqlSelectStatement(table_name::AbstractString) =
    SqlSelectStatement(CellVector(SqlAllColumns()), SqlTableReference(table_name))

# ── render_sql ──────────────────────────────────────────────────────────────────

"""
    render_sql(doc) -> String

Render a SQL AST node to its canonical executable SQL text.
"""
render_sql(::SqlAllColumns) = "*"
render_sql(t::SqlTableReference) = "\"" * t.name * "\""
function render_sql(s::SqlSelectStatement)
    cols = join((render_sql(item) for item in s.select_list), ", ")
    "SELECT " * cols * " FROM " * render_sql(s.from)
end

# ── Base.show ───────────────────────────────────────────────────────────────────

Base.show(io::IO, ::SqlAllColumns)        = print(io, "*")
Base.show(io::IO, t::SqlTableReference)   = print(io, t.name)
Base.show(io::IO, s::SqlSelectStatement)  = print(io, render_sql(s))

end # module
