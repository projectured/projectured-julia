"""
    SqlDocumentModule

The SQL statement document model (ANSI/PostgreSQL conventions). The AST is
database-agnostic; `SqlToSyntax` renders it and `SqlToCellTable` executes it
against a `DatabaseInstance`.
"""
module SqlDocumentModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export SqlDocument, SqlStatement, SqlSelectExpression, SqlFromBaseItem, SqlJoinType,
       SqlJoinCondition, SqlJoinConditionExpression, SqlWhereCondition, SqlBooleanExpression

# ── Abstract types ─────────────────────────────────────────────────────────────

abstract type SqlDocument <: Document end
abstract type SqlStatement <: SqlDocument end

# ── SqlInsertion (editable SQL source being entered) ───────────────────────────

"""
A placeholder for SQL source being typed; committed on Enter by parsing with
`sqlparse` into a real `SqlStatement`.
"""
@document struct SqlInsertion <: SqlStatement
    value::String = ""
    selection::Reference = nothing
end
abstract type SqlSelectExpression <: SqlDocument end
abstract type SqlFromBaseItem <: SqlDocument end
abstract type SqlJoinType <: SqlDocument end
abstract type SqlJoinCondition <: SqlDocument end
abstract type SqlJoinConditionExpression <: SqlDocument end
abstract type SqlWhereCondition <: SqlDocument end
abstract type SqlBooleanExpression <: SqlDocument end

# ── Reusable name documents ────────────────────────────────────────────────────

@document struct SqlTableName <: SqlDocument
    schema_name::Any              # String or nothing
    name::String
    selection::Reference = nothing
end
SqlTableName(schema::AbstractString, name::AbstractString) =
    SqlTableName(String(schema), String(name), Cell(nothing))

@document struct SqlTableAlias <: SqlDocument
    name::String
    selection::Reference = nothing
end

@document struct SqlColumnName <: SqlDocument
    name::String
    selection::Reference = nothing
end

@document struct SqlColumnAlias <: SqlDocument
    name::String
    selection::Reference = nothing
end

# ── SELECT clause documents ────────────────────────────────────────────────────

@document struct SqlDistinct <: SqlDocument
    selection::Reference = nothing
end

@document struct SqlAllColumns <: SqlSelectExpression
    qualifier::Any = nothing      # SqlTableName | SqlTableAlias | nothing
    selection::Reference = nothing
end

@document struct SqlColumnReference <: SqlSelectExpression
    qualifier::Any                # SqlTableName | SqlTableAlias | nothing
    column_name::SqlColumnName
    selection::Reference = nothing
end
SqlColumnReference(col::AbstractString) =
    SqlColumnReference(nothing, SqlColumnName(col), Cell(nothing))

@document struct SqlSelectItem <: SqlDocument
    expression::SqlSelectExpression
    column_alias::Any             # SqlColumnAlias | nothing
    selection::Reference = nothing
end
SqlSelectItem(expr::SqlSelectExpression, alias::SqlColumnAlias) =
    SqlSelectItem(expr, alias, Cell(nothing))

@document struct SqlSelectClause <: SqlDocument
    distinct::Any                 # SqlDistinct | nothing
    items::CellVector
    selection::Reference = nothing
end
SqlSelectClause(items::SqlSelectItem...) =
    SqlSelectClause(nothing, CellVector([items...]), Cell(nothing))

# ── WHERE clause ───────────────────────────────────────────────────────────────

@document struct SqlWhereFilterCondition <: SqlWhereCondition
    expression::SqlBooleanExpression
    selection::Reference = nothing
end

@document struct SqlWhereClause <: SqlDocument
    condition::Any = nothing      # SqlWhereCondition | nothing
    selection::Reference = nothing
end

# ── Boolean expression documents ───────────────────────────────────────────────

@document struct SqlScalarValue <: SqlDocument
    value::Any                    # Number | String | Bool
    selection::Reference = nothing
end

@document struct SqlComparison <: SqlBooleanExpression
    left::Any                     # SqlColumnReference | SqlScalarValue
    operator::String              # "=", "<>", "<", ">", "<=", ">="
    right::Any                    # SqlColumnReference | SqlScalarValue
    selection::Reference = nothing
end

@document struct SqlAnd <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
    selection::Reference = nothing
end

@document struct SqlOr <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
    selection::Reference = nothing
end

@document struct SqlNot <: SqlBooleanExpression
    expression::SqlBooleanExpression
    selection::Reference = nothing
end

# ── Join type leaf documents ───────────────────────────────────────────────────

@document struct SqlInnerJoin <: SqlJoinType
    selection::Reference = nothing
end

@document struct SqlLeftOuterJoin <: SqlJoinType
    selection::Reference = nothing
end

@document struct SqlRightOuterJoin <: SqlJoinType
    selection::Reference = nothing
end

@document struct SqlFullOuterJoin <: SqlJoinType
    selection::Reference = nothing
end

@document struct SqlCrossJoin <: SqlJoinType
    selection::Reference = nothing
end

# ── Join condition documents ───────────────────────────────────────────────────

@document struct SqlJoinOnCondition <: SqlJoinCondition
    expression::SqlBooleanExpression
    selection::Reference = nothing
end

@document struct SqlJoinUsingCondition <: SqlJoinCondition
    column_names::CellVector      # [SqlColumnName]
    selection::Reference = nothing
end

# ── FROM clause documents ──────────────────────────────────────────────────────

@document struct SqlTableExpression <: SqlFromBaseItem
    table_name::SqlTableName
    alias::Any                    # SqlTableAlias | nothing
    selection::Reference = nothing
end
SqlTableExpression(tname::SqlTableName, alias::SqlTableAlias) =
    SqlTableExpression(tname, alias, Cell(nothing))

@document struct SqlJoinedFromItem <: SqlDocument
    join_type::SqlJoinType
    from_item::SqlFromBaseItem
    condition::Any                # SqlJoinCondition | nothing
    selection::Reference = nothing
end
SqlJoinedFromItem(jt::SqlJoinType, fi::SqlFromBaseItem, cond::SqlJoinCondition) =
    SqlJoinedFromItem(jt, fi, cond, Cell(nothing))

@document struct SqlFromItem <: SqlDocument
    base_item::SqlFromBaseItem
    joins::CellVector             # [SqlJoinedFromItem]
    selection::Reference = nothing
end

@document struct SqlFromClause <: SqlDocument
    items::CellVector             # [SqlFromItem]
    selection::Reference = nothing
end

# ── Statement layer ────────────────────────────────────────────────────────────

@document struct SqlSelectStatement <: SqlStatement
    select_clause::SqlSelectClause
    from_clause::SqlFromClause
    where_clause::SqlWhereClause
    selection::Reference = nothing
end
SqlSelectStatement(sc::SqlSelectClause, fc::SqlFromClause, wc::SqlWhereClause) =
    SqlSelectStatement(sc, fc, wc, Cell(nothing))

# Convenience: `SELECT * FROM <table-name>`
SqlSelectStatement(table_name::AbstractString) =
    SqlSelectStatement(
        SqlSelectClause(SqlSelectItem(SqlAllColumns())),
        SqlFromClause(SqlFromItem(SqlTableExpression(table_name))),
        SqlWhereClause(),
        Cell(nothing))

@document struct SqlSubqueryFromItem <: SqlFromBaseItem
    subquery::SqlSelectStatement
    alias::Any                    # SqlTableAlias | nothing
    selection::Reference = nothing
end
SqlSubqueryFromItem(sq::SqlSelectStatement, alias::SqlTableAlias) =
    SqlSubqueryFromItem(sq, alias, Cell(nothing))

# ── INSERT ─────────────────────────────────────────────────────────────────────
# Single-row INSERT: `INSERT INTO <table> (<col>, …) VALUES (<val>, …)`.
# `columns` may be empty, in which case the column list is omitted.
@document struct SqlInsertStatement <: SqlStatement
    table::Any = nothing          # SqlTableName | nothing (empty stub)
    columns::CellVector = CellVector() # [SqlColumnName]
    values::CellVector = CellVector()  # [SqlScalarValue]
    selection::Reference = nothing
end
SqlInsertStatement(table::SqlTableName,
                   columns::AbstractVector{<:SqlColumnName},
                   values::AbstractVector{<:SqlScalarValue}) =
    SqlInsertStatement(table, CellVector([columns...]), CellVector([values...]), Cell(nothing))

# ── UPDATE ─────────────────────────────────────────────────────────────────────
# Single assignment `<col> = <value>` inside an UPDATE's SET list.
@document struct SqlUpdateAssignment <: SqlDocument
    column_name::SqlColumnName
    value::SqlScalarValue
    selection::Reference = nothing
end

# Single-line UPDATE: `UPDATE <table> SET <assignment>, … [WHERE …]`.
@document struct SqlUpdateStatement <: SqlStatement
    table::Any = nothing          # SqlTableName | nothing (empty stub)
    assignments::CellVector = CellVector() # [SqlUpdateAssignment]
    where_clause::SqlWhereClause = SqlWhereClause()
    selection::Reference = nothing
end
SqlUpdateStatement(table::SqlTableName, assignments::CellVector, wc::SqlWhereClause) =
    SqlUpdateStatement(table, assignments, wc, Cell(nothing))
SqlUpdateStatement(table::SqlTableName,
                   assignments::AbstractVector{<:SqlUpdateAssignment},
                   wc::SqlWhereClause=SqlWhereClause()) =
    SqlUpdateStatement(table, CellVector([assignments...]), wc, Cell(nothing))

# ── DDL: CREATE statements ─────────────────────────────────────────────────────
# Column definition inside a CREATE TABLE: `<column-name> <data-type>`.
# The catalog stores the data type as a plain string, so we carry it as a String.
# Room to grow later (nullable, default, constraints); start with name + type.
@document struct SqlColumnDefinition <: SqlDocument
    column_name::SqlColumnName
    data_type::String             # e.g. "integer", "text", "varchar(255)"
    selection::Reference = nothing
end
SqlColumnDefinition(col::AbstractString, data_type::AbstractString) =
    SqlColumnDefinition(SqlColumnName(col), String(data_type), Cell(nothing))

# `CREATE TABLE <table-name> (<column-definition>, …)`.
@document struct SqlCreateTableStatement <: SqlStatement
    table_name::SqlTableName
    columns::CellVector           # [SqlColumnDefinition]
    selection::Reference = nothing
end
SqlCreateTableStatement(table_name::SqlTableName,
                        columns::AbstractVector{<:SqlColumnDefinition}) =
    SqlCreateTableStatement(table_name, CellVector([columns...]), Cell(nothing))

# `CREATE SCHEMA <schema-name>`.
@document struct SqlCreateSchemaStatement <: SqlStatement
    schema_name::String
    selection::Reference = nothing
end

# ── Statement sequence ──────────────────────────────────────────────────────────
# An ordered list of statements, rendered one after another (blank-line
# separated). Lets a projection emit a whole DDL script — e.g. a CREATE SCHEMA
# followed by its CREATE TABLEs — as a single Sql document.
@document struct SqlStatementList <: SqlDocument
    statements::CellVector        # [SqlStatement]
    selection::Reference = nothing
end
SqlStatementList(statements::AbstractVector) =
    SqlStatementList(CellVector([statements...]), Cell(nothing))

end # module
