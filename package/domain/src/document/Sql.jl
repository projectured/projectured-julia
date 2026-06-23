"""
    SqlDocumentModule

SQL statement document model following ANSI/PostgreSQL conventions.
Every semantic element is a dedicated document type.

The AST is database-agnostic — it carries no connection. Projections render it:
`SqlToSyntax` produces a syntax tree for display, and `SqlToCellTable` executes
it against a `DatabaseInstance` (through a connection pool) and returns the
result rows. The projection pipeline `Sql→Syntax→Text→String` produces the
printed text output.

"""
module SqlDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export SqlDocument, SqlStatement,
       SqlSelectExpression, SqlFromBaseItem, SqlJoinType, SqlJoinCondition,
       SqlJoinConditionExpression, SqlWhereCondition,
       SqlTableName,      ISqlTableName,
       SqlTableAlias,     ISqlTableAlias,
       SqlColumnName,     ISqlColumnName,
       SqlColumnAlias,    ISqlColumnAlias,
       SqlDistinct,       ISqlDistinct,
       SqlAllColumns,     ISqlAllColumns,
       SqlColumnReference, ISqlColumnReference,
       SqlSelectItem,     ISqlSelectItem,
       SqlSelectClause,   ISqlSelectClause,
       SqlWhereClause,    ISqlWhereClause,
       SqlInnerJoin,      ISqlInnerJoin,
       SqlLeftOuterJoin,  ISqlLeftOuterJoin,
       SqlRightOuterJoin, ISqlRightOuterJoin,
       SqlFullOuterJoin,  ISqlFullOuterJoin,
       SqlCrossJoin,      ISqlCrossJoin,
       SqlJoinOnCondition,    ISqlJoinOnCondition,
       SqlJoinUsingCondition, ISqlJoinUsingCondition,
       SqlTableExpression,     ISqlTableExpression,
       SqlJoinedFromItem,      ISqlJoinedFromItem,
       SqlWhereFilterCondition, ISqlWhereFilterCondition,
       SqlFromItem,          ISqlFromItem,
       SqlFromClause,        ISqlFromClause,
       SqlSelectStatement,   ISqlSelectStatement,
       SqlSubqueryFromItem,  ISqlSubqueryFromItem,
       SqlInsertStatement,   ISqlInsertStatement,
       SqlUpdateAssignment,  ISqlUpdateAssignment,
       SqlUpdateStatement,   ISqlUpdateStatement,
       SqlColumnDefinition,      ISqlColumnDefinition,
       SqlCreateTableStatement,  ISqlCreateTableStatement,
       SqlCreateSchemaStatement, ISqlCreateSchemaStatement,
       SqlStatementList,         ISqlStatementList,
       SqlBooleanExpression,
       SqlScalarValue,    ISqlScalarValue,
       SqlComparison,     ISqlComparison,
       SqlAnd,            ISqlAnd,
       SqlOr,             ISqlOr,
       SqlNot,            ISqlNot

# ── Abstract types ─────────────────────────────────────────────────────────────

abstract type SqlDocument <: Document end
abstract type SqlStatement <: SqlDocument end
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
    selection::Reference
end
SqlTableName(name::AbstractString) =
    SqlTableName(nothing, String(name), Cell(nothing))
SqlTableName(schema::AbstractString, name::AbstractString) =
    SqlTableName(String(schema), String(name), Cell(nothing))

@document struct SqlTableAlias <: SqlDocument
    name::String
    selection::Reference
end
SqlTableAlias(name::AbstractString) = SqlTableAlias(String(name), Cell(nothing))

@document struct SqlColumnName <: SqlDocument
    name::String
    selection::Reference
end
SqlColumnName(name::AbstractString) = SqlColumnName(String(name), Cell(nothing))

@document struct SqlColumnAlias <: SqlDocument
    name::String
    selection::Reference
end
SqlColumnAlias(name::AbstractString) = SqlColumnAlias(String(name), Cell(nothing))

# ── SELECT clause documents ────────────────────────────────────────────────────

@document struct SqlDistinct <: SqlDocument
    selection::Reference = nothing
end

@document struct SqlAllColumns <: SqlSelectExpression
    qualifier::Any = nothing      # SqlTableName | SqlTableAlias | nothing
    selection::Reference = nothing
end
SqlAllColumns(qualifier) = SqlAllColumns(qualifier, Cell(nothing))

@document struct SqlColumnReference <: SqlSelectExpression
    qualifier::Any                # SqlTableName | SqlTableAlias | nothing
    column_name::SqlColumnName
    selection::Reference
end
SqlColumnReference(col::SqlColumnName) =
    SqlColumnReference(nothing, col, Cell(nothing))
SqlColumnReference(col::AbstractString) =
    SqlColumnReference(nothing, SqlColumnName(col), Cell(nothing))
SqlColumnReference(qualifier, col::SqlColumnName) =
    SqlColumnReference(qualifier, col, Cell(nothing))

@document struct SqlSelectItem <: SqlDocument
    expression::SqlSelectExpression
    column_alias::Any             # SqlColumnAlias | nothing
    selection::Reference
end
SqlSelectItem(expr::SqlSelectExpression) =
    SqlSelectItem(expr, nothing, Cell(nothing))
SqlSelectItem(expr::SqlSelectExpression, alias::SqlColumnAlias) =
    SqlSelectItem(expr, alias, Cell(nothing))

@document struct SqlSelectClause <: SqlDocument
    distinct::Any                 # SqlDistinct | nothing
    items::CellVector
    selection::Reference
end
SqlSelectClause(items::CellVector) =
    SqlSelectClause(nothing, items, Cell(nothing))
SqlSelectClause(items::SqlSelectItem...) =
    SqlSelectClause(nothing, CellVector([items...]), Cell(nothing))

# ── WHERE clause ───────────────────────────────────────────────────────────────

@document struct SqlWhereFilterCondition <: SqlWhereCondition
    expression::SqlBooleanExpression
    selection::Reference
end
SqlWhereFilterCondition(expr::SqlBooleanExpression) =
    SqlWhereFilterCondition(expr, Cell(nothing))

@document struct SqlWhereClause <: SqlDocument
    condition::Any = nothing      # SqlWhereCondition | nothing
    selection::Reference = nothing
end
SqlWhereClause(cond::SqlWhereCondition) = SqlWhereClause(cond, Cell(nothing))

# ── Boolean expression documents ───────────────────────────────────────────────

@document struct SqlScalarValue <: SqlDocument
    value::Any                    # Number | String | Bool
    selection::Reference
end
SqlScalarValue(value) = SqlScalarValue(value, Cell(nothing))

@document struct SqlComparison <: SqlBooleanExpression
    left::Any                     # SqlColumnReference | SqlScalarValue
    operator::String              # "=", "<>", "<", ">", "<=", ">="
    right::Any                    # SqlColumnReference | SqlScalarValue
    selection::Reference
end
SqlComparison(left, op::AbstractString, right) =
    SqlComparison(left, String(op), right, Cell(nothing))

@document struct SqlAnd <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
    selection::Reference
end
SqlAnd(left::SqlBooleanExpression, right::SqlBooleanExpression) =
    SqlAnd(left, right, Cell(nothing))

@document struct SqlOr <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
    selection::Reference
end
SqlOr(left::SqlBooleanExpression, right::SqlBooleanExpression) =
    SqlOr(left, right, Cell(nothing))

@document struct SqlNot <: SqlBooleanExpression
    expression::SqlBooleanExpression
    selection::Reference
end
SqlNot(expr::SqlBooleanExpression) = SqlNot(expr, Cell(nothing))

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
    selection::Reference
end
SqlJoinOnCondition(expr::SqlBooleanExpression) =
    SqlJoinOnCondition(expr, Cell(nothing))

@document struct SqlJoinUsingCondition <: SqlJoinCondition
    column_names::CellVector      # [SqlColumnName]
    selection::Reference
end
SqlJoinUsingCondition(cols::SqlColumnName...) =
    SqlJoinUsingCondition(CellVector([cols...]), Cell(nothing))

# ── FROM clause documents ──────────────────────────────────────────────────────

@document struct SqlTableExpression <: SqlFromBaseItem
    table_name::SqlTableName
    alias::Any                    # SqlTableAlias | nothing
    selection::Reference
end
SqlTableExpression(tname::SqlTableName) =
    SqlTableExpression(tname, nothing, Cell(nothing))
SqlTableExpression(tname::SqlTableName, alias::SqlTableAlias) =
    SqlTableExpression(tname, alias, Cell(nothing))
SqlTableExpression(name::AbstractString) =
    SqlTableExpression(SqlTableName(name), nothing, Cell(nothing))

@document struct SqlJoinedFromItem <: SqlDocument
    join_type::SqlJoinType
    from_item::SqlFromBaseItem
    condition::Any                # SqlJoinCondition | nothing
    selection::Reference
end
SqlJoinedFromItem(jt::SqlJoinType, fi::SqlFromBaseItem) =
    SqlJoinedFromItem(jt, fi, nothing, Cell(nothing))
SqlJoinedFromItem(jt::SqlJoinType, fi::SqlFromBaseItem, cond::SqlJoinCondition) =
    SqlJoinedFromItem(jt, fi, cond, Cell(nothing))

@document struct SqlFromItem <: SqlDocument
    base_item::SqlFromBaseItem
    joins::CellVector             # [SqlJoinedFromItem]
    selection::Reference
end
SqlFromItem(base::SqlFromBaseItem) =
    SqlFromItem(base, CellVector(), Cell(nothing))

@document struct SqlFromClause <: SqlDocument
    items::CellVector             # [SqlFromItem]
    selection::Reference
end
SqlFromClause(items::SqlFromItem...) =
    SqlFromClause(CellVector([items...]), Cell(nothing))

# ── Statement layer ────────────────────────────────────────────────────────────

@document struct SqlSelectStatement <: SqlStatement
    select_clause::SqlSelectClause
    from_clause::SqlFromClause
    where_clause::SqlWhereClause
    selection::Reference
end
SqlSelectStatement(sc::SqlSelectClause, fc::SqlFromClause) =
    SqlSelectStatement(sc, fc, SqlWhereClause(), Cell(nothing))
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
    selection::Reference
end
SqlSubqueryFromItem(sq::SqlSelectStatement) =
    SqlSubqueryFromItem(sq, nothing, Cell(nothing))
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
SqlInsertStatement(table::SqlTableName, columns::CellVector, values::CellVector) =
    SqlInsertStatement(table, columns, values, Cell(nothing))
SqlInsertStatement(table::SqlTableName,
                   columns::AbstractVector{SqlColumnName},
                   values::AbstractVector{SqlScalarValue}) =
    SqlInsertStatement(table, CellVector([columns...]), CellVector([values...]), Cell(nothing))

# ── UPDATE ─────────────────────────────────────────────────────────────────────
# Single assignment `<col> = <value>` inside an UPDATE's SET list.
@document struct SqlUpdateAssignment <: SqlDocument
    column_name::SqlColumnName
    value::SqlScalarValue
    selection::Reference
end
SqlUpdateAssignment(col::SqlColumnName, value::SqlScalarValue) =
    SqlUpdateAssignment(col, value, Cell(nothing))

# Single-line UPDATE: `UPDATE <table> SET <assignment>, … [WHERE …]`.
@document struct SqlUpdateStatement <: SqlStatement
    table::Any = nothing          # SqlTableName | nothing (empty stub)
    assignments::CellVector = CellVector() # [SqlUpdateAssignment]
    where_clause::SqlWhereClause = SqlWhereClause()
    selection::Reference = nothing
end
SqlUpdateStatement(table::SqlTableName, assignments::CellVector) =
    SqlUpdateStatement(table, assignments, SqlWhereClause(), Cell(nothing))
SqlUpdateStatement(table::SqlTableName, assignments::CellVector, wc::SqlWhereClause) =
    SqlUpdateStatement(table, assignments, wc, Cell(nothing))
SqlUpdateStatement(table::SqlTableName,
                   assignments::AbstractVector{SqlUpdateAssignment},
                   wc::SqlWhereClause=SqlWhereClause()) =
    SqlUpdateStatement(table, CellVector([assignments...]), wc, Cell(nothing))

# ── DDL: CREATE statements ─────────────────────────────────────────────────────
# Column definition inside a CREATE TABLE: `<column-name> <data-type>`.
# The catalog stores the data type as a plain string, so we carry it as a String.
# Room to grow later (nullable, default, constraints); start with name + type.
@document struct SqlColumnDefinition <: SqlDocument
    column_name::SqlColumnName
    data_type::String             # e.g. "integer", "text", "varchar(255)"
    selection::Reference
end
SqlColumnDefinition(col::SqlColumnName, data_type::AbstractString) =
    SqlColumnDefinition(col, String(data_type), Cell(nothing))
SqlColumnDefinition(col::AbstractString, data_type::AbstractString) =
    SqlColumnDefinition(SqlColumnName(col), String(data_type), Cell(nothing))

# `CREATE TABLE <table-name> (<column-definition>, …)`.
@document struct SqlCreateTableStatement <: SqlStatement
    table_name::SqlTableName
    columns::CellVector           # [SqlColumnDefinition]
    selection::Reference
end
SqlCreateTableStatement(table_name::SqlTableName, columns::CellVector) =
    SqlCreateTableStatement(table_name, columns, Cell(nothing))
SqlCreateTableStatement(table_name::SqlTableName,
                        columns::AbstractVector{SqlColumnDefinition}) =
    SqlCreateTableStatement(table_name, CellVector([columns...]), Cell(nothing))

# `CREATE SCHEMA <schema-name>`.
@document struct SqlCreateSchemaStatement <: SqlStatement
    schema_name::String
    selection::Reference
end
SqlCreateSchemaStatement(schema_name::AbstractString) =
    SqlCreateSchemaStatement(String(schema_name), Cell(nothing))

# ── Statement sequence ──────────────────────────────────────────────────────────
# An ordered list of statements, rendered one after another (blank-line
# separated). Lets a projection emit a whole DDL script — e.g. a CREATE SCHEMA
# followed by its CREATE TABLEs — as a single Sql document.
@document struct SqlStatementList <: SqlDocument
    statements::CellVector        # [SqlStatement]
    selection::Reference
end
SqlStatementList(statements::CellVector) =
    SqlStatementList(statements, Cell(nothing))
SqlStatementList(statements::AbstractVector) =
    SqlStatementList(CellVector([statements...]), Cell(nothing))
SqlStatementList(statements::SqlStatement...) =
    SqlStatementList(CellVector([statements...]), Cell(nothing))

end # module
