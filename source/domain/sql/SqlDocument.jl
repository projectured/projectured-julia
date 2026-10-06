# Fragment of `SqlModule` — the SQL document types: the abstract `SqlDocument`
# and `SqlStatement`, the insertion that holds source being typed, and the
# clauses a statement is built from.

abstract type SqlDocument <: Document end
abstract type SqlStatement <: SqlDocument end

# ── SqlInsertion (editable SQL source being entered) ───────────────────────────

"""
A placeholder for SQL source being typed; committed on Enter by parsing with
`parse_sql_text` into a real `SqlStatement`.
"""
@document struct SqlInsertion <: SqlStatement
    value::String = ""
end

# The insertion kit adopts the hand-written root (it precedes `SqlStatement`,
# which the generated root cannot) and the existing `SqlInsertion`; only
# `SqlNothing`, the traits, the `"sql"` alias, and the Insert gesture are
# generated.
@domain Sql root = SqlDocument insertion = SqlInsertion

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
end
SqlTableName(schema::AbstractString, name::AbstractString) =
    SqlTableName(String(schema), String(name), Cell(nothing))

@document struct SqlTableAlias <: SqlDocument
    name::String
end

@document struct SqlColumnName <: SqlDocument
    name::String
end

@document struct SqlColumnAlias <: SqlDocument
    name::String
end

# ── SELECT clause documents ────────────────────────────────────────────────────

@document struct SqlDistinct <: SqlDocument
end

@document struct SqlAllColumns <: SqlSelectExpression
    qualifier::Any = nothing      # SqlTableName | SqlTableAlias | nothing
end

@document struct SqlColumnReference <: SqlSelectExpression
    qualifier::Any                # SqlTableName | SqlTableAlias | nothing
    column_name::SqlColumnName
end
SqlColumnReference(col::AbstractString) =
    SqlColumnReference(nothing, SqlColumnName(col), Cell(nothing))

"""
The source text of a select expression that the document model does not have, such
as a function call. The parser keeps it as it is written, and it prints unquoted.
"""
@document struct SqlRawExpression <: SqlSelectExpression
    text::String
end

@document struct SqlSelectItem <: SqlDocument
    expression::SqlSelectExpression
    column_alias::Any             # SqlColumnAlias | nothing
end
SqlSelectItem(expr::SqlSelectExpression, alias::SqlColumnAlias) =
    SqlSelectItem(expr, alias, Cell(nothing))

@document struct SqlSelectClause <: SqlDocument
    distinct::Any                 # SqlDistinct | nothing
    items::CellVector
end
SqlSelectClause(items::SqlSelectItem...) =
    SqlSelectClause(nothing, CellVector([items...]), Cell(nothing))

# ── WHERE clause ───────────────────────────────────────────────────────────────

@document struct SqlWhereFilterCondition <: SqlWhereCondition
    expression::SqlBooleanExpression
end

@document struct SqlWhereClause <: SqlDocument
    condition::Any = nothing      # SqlWhereCondition | nothing
end

# ── Boolean expression documents ───────────────────────────────────────────────

@document struct SqlScalarValue <: SqlSelectExpression
    value::Any                    # Number | String | Bool
end

"""
The source text of a condition that the document model does not have, such as a
`LIKE` or an `IN`. The parser keeps it as it is written, and it prints unquoted.
"""
@document struct SqlRawCondition <: SqlBooleanExpression
    text::String
end

@document struct SqlComparison <: SqlBooleanExpression
    left::Any                     # SqlColumnReference | SqlScalarValue
    operator::String              # "=", "<>", "<", ">", "<=", ">="
    right::Any                    # SqlColumnReference | SqlScalarValue
end

@document struct SqlAnd <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
end

@document struct SqlOr <: SqlBooleanExpression
    left::SqlBooleanExpression
    right::SqlBooleanExpression
end

@document struct SqlNot <: SqlBooleanExpression
    expression::SqlBooleanExpression
end

# ── Join type leaf documents ───────────────────────────────────────────────────

@document struct SqlInnerJoin <: SqlJoinType
end

@document struct SqlLeftOuterJoin <: SqlJoinType
end

@document struct SqlRightOuterJoin <: SqlJoinType
end

@document struct SqlFullOuterJoin <: SqlJoinType
end

@document struct SqlCrossJoin <: SqlJoinType
end

# ── Join condition documents ───────────────────────────────────────────────────

@document struct SqlJoinOnCondition <: SqlJoinCondition
    expression::SqlBooleanExpression
end

@document struct SqlJoinUsingCondition <: SqlJoinCondition
    column_names::CellVector      # [SqlColumnName]
end

# ── FROM clause documents ──────────────────────────────────────────────────────

@document struct SqlTableExpression <: SqlFromBaseItem
    table_name::SqlTableName
    alias::Any                    # SqlTableAlias | nothing
end
SqlTableExpression(tname::SqlTableName, alias::SqlTableAlias) =
    SqlTableExpression(tname, alias, Cell(nothing))

@document struct SqlJoinedFromItem <: SqlDocument
    join_type::SqlJoinType
    from_item::SqlFromBaseItem
    condition::Any                # SqlJoinCondition | nothing
end
SqlJoinedFromItem(jt::SqlJoinType, fi::SqlFromBaseItem, cond::SqlJoinCondition) =
    SqlJoinedFromItem(jt, fi, cond, Cell(nothing))

@document struct SqlFromItem <: SqlDocument
    base_item::SqlFromBaseItem
    joins::CellVector             # [SqlJoinedFromItem]
end

@document struct SqlFromClause <: SqlDocument
    items::CellVector             # [SqlFromItem]
end

# ── Statement layer ────────────────────────────────────────────────────────────

@document struct SqlSelectStatement <: SqlStatement
    select_clause::SqlSelectClause
    from_clause::SqlFromClause
    where_clause::SqlWhereClause
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
end

# Single-line UPDATE: `UPDATE <table> SET <assignment>, … [WHERE …]`.
@document struct SqlUpdateStatement <: SqlStatement
    table::Any = nothing          # SqlTableName | nothing (empty stub)
    assignments::CellVector = CellVector() # [SqlUpdateAssignment]
    where_clause::SqlWhereClause = SqlWhereClause()
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
end
SqlColumnDefinition(col::AbstractString, data_type::AbstractString) =
    SqlColumnDefinition(SqlColumnName(col), String(data_type), Cell(nothing))

# `CREATE TABLE <table-name> (<column-definition>, …)`.
@document struct SqlCreateTableStatement <: SqlStatement
    table_name::SqlTableName
    columns::CellVector           # [SqlColumnDefinition]
end
SqlCreateTableStatement(table_name::SqlTableName,
                        columns::AbstractVector{<:SqlColumnDefinition}) =
    SqlCreateTableStatement(table_name, CellVector([columns...]), Cell(nothing))

# `CREATE SCHEMA <schema-name>`.
@document struct SqlCreateSchemaStatement <: SqlStatement
    schema_name::String
end

# ── Statement sequence ──────────────────────────────────────────────────────────
# An ordered list of statements, rendered one after another (blank-line
# separated). Lets a projection emit a whole DDL script — e.g. a CREATE SCHEMA
# followed by its CREATE TABLEs — as a single Sql document.
@document struct SqlStatementList <: SqlDocument
    statements::CellVector        # [SqlStatement]
end
# The `@document` macro already generates `SqlStatementList(::AbstractVector)`
# (Rule C: single CellVector + defaulted siblings), which wraps into a CellVector
# and fills the `selection` default — so no hand-written ctor is needed here.

# ── Convenience constructors ─────────────────────────────────────────────────
# The `@document` macro regenerates the untyped positional / keyword forms, but
# not these typed-conversion, varargs, mixed-arity, and CellVector-wrapping forms
# that consumers rely on. Ctor location is independent of struct location, so they
# live here at module scope. (`SqlScalarValue(value)` is omitted — the macro's
# Rule Y already provides the untyped 1-arg form.)
SqlInsertion(value::AbstractString) = SqlInsertion(Cell(String(value)), Cell(nothing))
SqlTableName(name::AbstractString) =
    SqlTableName(nothing, String(name), Cell(nothing))
SqlTableAlias(name::AbstractString) = SqlTableAlias(String(name), Cell(nothing))
SqlColumnName(name::AbstractString) = SqlColumnName(String(name), Cell(nothing))
SqlColumnAlias(name::AbstractString) = SqlColumnAlias(String(name), Cell(nothing))
SqlAllColumns(qualifier) = SqlAllColumns(qualifier, Cell(nothing))
SqlColumnReference(col::SqlColumnName) =
    SqlColumnReference(nothing, col, Cell(nothing))
SqlColumnReference(qualifier, col::SqlColumnName) =
    SqlColumnReference(qualifier, col, Cell(nothing))
SqlSelectItem(expr::SqlSelectExpression) =
    SqlSelectItem(expr, nothing, Cell(nothing))
SqlSelectClause(items::CellVector) =
    SqlSelectClause(nothing, items, Cell(nothing))
SqlWhereFilterCondition(expr::SqlBooleanExpression) =
    SqlWhereFilterCondition(expr, Cell(nothing))
SqlWhereClause(cond::SqlWhereCondition) = SqlWhereClause(cond, Cell(nothing))
SqlComparison(left, op::AbstractString, right) =
    SqlComparison(left, String(op), right, Cell(nothing))
SqlAnd(left::SqlBooleanExpression, right::SqlBooleanExpression) =
    SqlAnd(left, right, Cell(nothing))
SqlOr(left::SqlBooleanExpression, right::SqlBooleanExpression) =
    SqlOr(left, right, Cell(nothing))
SqlNot(expr::SqlBooleanExpression) = SqlNot(expr, Cell(nothing))
SqlJoinOnCondition(expr::SqlBooleanExpression) =
    SqlJoinOnCondition(expr, Cell(nothing))
SqlJoinUsingCondition(cols::SqlColumnName...) =
    SqlJoinUsingCondition(CellVector([cols...]), Cell(nothing))
SqlTableExpression(tname::SqlTableName) =
    SqlTableExpression(tname, nothing, Cell(nothing))
SqlTableExpression(name::AbstractString) =
    SqlTableExpression(SqlTableName(name), nothing, Cell(nothing))
SqlJoinedFromItem(jt::SqlJoinType, fi::SqlFromBaseItem) =
    SqlJoinedFromItem(jt, fi, nothing, Cell(nothing))
SqlFromItem(base::SqlFromBaseItem) =
    SqlFromItem(base, CellVector(), Cell(nothing))
SqlFromClause(items::SqlFromItem...) =
    SqlFromClause(CellVector([items...]), Cell(nothing))
SqlSelectStatement(sc::SqlSelectClause, fc::SqlFromClause) =
    SqlSelectStatement(sc, fc, SqlWhereClause(), Cell(nothing))
SqlSubqueryFromItem(sq::SqlSelectStatement) =
    SqlSubqueryFromItem(sq, nothing, Cell(nothing))
SqlInsertStatement(table::SqlTableName, columns::CellVector, values::CellVector) =
    SqlInsertStatement(table, columns, values, Cell(nothing))
SqlUpdateAssignment(col::SqlColumnName, value::SqlScalarValue) =
    SqlUpdateAssignment(col, value, Cell(nothing))
SqlUpdateStatement(table::SqlTableName, assignments::CellVector) =
    SqlUpdateStatement(table, assignments, SqlWhereClause(), Cell(nothing))
SqlColumnDefinition(col::SqlColumnName, data_type::AbstractString) =
    SqlColumnDefinition(col, String(data_type), Cell(nothing))
SqlCreateTableStatement(table_name::SqlTableName, columns::CellVector) =
    SqlCreateTableStatement(table_name, columns, Cell(nothing))
SqlCreateSchemaStatement(schema_name::AbstractString) =
    SqlCreateSchemaStatement(String(schema_name), Cell(nothing))
