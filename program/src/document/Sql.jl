"""
    SqlDocumentModule

SQL statement document model following ANSI/PostgreSQL conventions.
Every semantic element is a dedicated document type.

The AST is database-agnostic — it carries no connection. Projections render it:
`SqlToSyntax` produces a syntax tree for display, and `SqlToCellTable` executes
it against a `DatabaseInstance` (through a connection pool) and returns the
result rows. `render_sql` produces the canonical executable SQL string.

After construction, call `resolve_sql_names!` to bind qualifier and column-name
reference fields to their canonical definition documents (bottom-up pass).
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
       SqlTableExpression,   ISqlTableExpression,
       SqlJoinSegment,       ISqlJoinSegment,
       SqlFromItem,          ISqlFromItem,
       SqlFromClause,        ISqlFromClause,
       SqlSelectStatement,   ISqlSelectStatement,
       SqlSubqueryFromItem,  ISqlSubqueryFromItem,
       SqlInsertStatement,   ISqlInsertStatement,
       SqlUpdateStatement,   ISqlUpdateStatement,
       SqlBooleanExpression,
       SqlScalarValue,    ISqlScalarValue,
       SqlComparison,     ISqlComparison,
       SqlAnd,            ISqlAnd,
       SqlOr,             ISqlOr,
       SqlNot,            ISqlNot,
       render_sql, resolve_sql_names!

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
    selection::Reference
end
SqlDistinct() = SqlDistinct(Cell(nothing))

@document struct SqlAllColumns <: SqlSelectExpression
    qualifier::Any                # SqlTableName | SqlTableAlias | nothing
    selection::Reference
end
SqlAllColumns() = SqlAllColumns(nothing, Cell(nothing))
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

@document struct SqlWhereClause <: SqlDocument
    condition::Any                # SqlBooleanExpression | nothing
    selection::Reference
end
SqlWhereClause() = SqlWhereClause(nothing, Cell(nothing))
SqlWhereClause(cond::SqlBooleanExpression) = SqlWhereClause(cond, Cell(nothing))

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
    selection::Reference
end
SqlInnerJoin() = SqlInnerJoin(Cell(nothing))

@document struct SqlLeftOuterJoin <: SqlJoinType
    selection::Reference
end
SqlLeftOuterJoin() = SqlLeftOuterJoin(Cell(nothing))

@document struct SqlRightOuterJoin <: SqlJoinType
    selection::Reference
end
SqlRightOuterJoin() = SqlRightOuterJoin(Cell(nothing))

@document struct SqlFullOuterJoin <: SqlJoinType
    selection::Reference
end
SqlFullOuterJoin() = SqlFullOuterJoin(Cell(nothing))

@document struct SqlCrossJoin <: SqlJoinType
    selection::Reference
end
SqlCrossJoin() = SqlCrossJoin(Cell(nothing))

# ── Join condition documents ───────────────────────────────────────────────────

@document struct SqlJoinOnCondition <: SqlJoinCondition
    expression::SqlJoinConditionExpression
    selection::Reference
end
SqlJoinOnCondition(expr::SqlJoinConditionExpression) =
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

@document struct SqlJoinSegment <: SqlDocument
    join_type::SqlJoinType
    from_item::SqlFromBaseItem
    condition::Any                # SqlJoinCondition | nothing
    selection::Reference
end
SqlJoinSegment(jt::SqlJoinType, fi::SqlFromBaseItem) =
    SqlJoinSegment(jt, fi, nothing, Cell(nothing))
SqlJoinSegment(jt::SqlJoinType, fi::SqlFromBaseItem, cond::SqlJoinCondition) =
    SqlJoinSegment(jt, fi, cond, Cell(nothing))

@document struct SqlFromItem <: SqlDocument
    base_item::SqlFromBaseItem
    joins::CellVector             # [SqlJoinSegment]
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

@document struct SqlInsertStatement <: SqlStatement
    selection::Reference
end
SqlInsertStatement() = SqlInsertStatement(Cell(nothing))

@document struct SqlUpdateStatement <: SqlStatement
    selection::Reference
end
SqlUpdateStatement() = SqlUpdateStatement(Cell(nothing))

# ── render_sql ─────────────────────────────────────────────────────────────────

"""
    render_sql(doc) -> String

Render a SQL AST node to its canonical executable SQL text.
"""
function render_sql(n::SqlTableName)
    n.schema_name === nothing ? "\"$(n.name)\"" : "\"$(n.schema_name)\".\"$(n.name)\""
end
render_sql(a::SqlTableAlias)  = a.name
render_sql(c::SqlColumnName)  = c.name
render_sql(a::SqlColumnAlias) = a.name

function render_sql(s::SqlAllColumns)
    s.qualifier === nothing ? "*" : "$(render_sql(s.qualifier)).*"
end

function render_sql(r::SqlColumnReference)
    col = r.column_name.name
    r.qualifier === nothing ? col : "$(render_sql(r.qualifier)).$col"
end

function render_sql(item::SqlSelectItem)
    expr = render_sql(item.expression)
    item.column_alias === nothing ? expr : "$expr AS $(item.column_alias.name)"
end

function render_sql(c::SqlSelectClause)
    list = join((render_sql(item) for item in c.items), ", ")
    c.distinct === nothing ? "SELECT $list" : "SELECT DISTINCT $list"
end

render_sql(::SqlInnerJoin)      = "JOIN"
render_sql(::SqlLeftOuterJoin)  = "LEFT JOIN"
render_sql(::SqlRightOuterJoin) = "RIGHT JOIN"
render_sql(::SqlFullOuterJoin)  = "FULL JOIN"
render_sql(::SqlCrossJoin)      = "CROSS JOIN"

function render_sql(c::SqlJoinUsingCondition)
    cols = join((render_sql(cn) for cn in c.column_names), ", ")
    "USING ($cols)"
end

function render_sql(t::SqlTableExpression)
    base = render_sql(t.table_name)
    t.alias === nothing ? base : "$base AS $(t.alias.name)"
end

function render_sql(j::SqlJoinSegment)
    base = "$(render_sql(j.join_type)) $(render_sql(j.from_item))"
    j.condition === nothing ? base : "$base $(render_sql(j.condition))"
end

function render_sql(fi::SqlFromItem)
    parts = String[render_sql(fi.base_item)]
    for seg in fi.joins
        push!(parts, render_sql(seg))
    end
    join(parts, " ")
end

function render_sql(c::SqlFromClause)
    "FROM $(join((render_sql(fi) for fi in c.items), ", "))"
end

function render_sql(c::SqlWhereClause)
    c.condition === nothing ? "" : "WHERE $(render_sql(c.condition))"
end

function render_sql(v::SqlScalarValue)
    val = v.value
    val isa Bool           ? (val ? "TRUE" : "FALSE") :
    val isa AbstractString ? "'$val'" :
    string(val)
end

render_sql(c::SqlComparison) =
    "$(render_sql(c.left)) $(c.operator) $(render_sql(c.right))"
render_sql(e::SqlAnd) =
    "($(render_sql(e.left)) AND $(render_sql(e.right)))"
render_sql(e::SqlOr)  =
    "($(render_sql(e.left)) OR $(render_sql(e.right)))"
render_sql(e::SqlNot) =
    "(NOT $(render_sql(e.expression)))"

function render_sql(s::SqlSubqueryFromItem)
    subq = "($(render_sql(s.subquery)))"
    s.alias === nothing ? subq : "$subq AS $(s.alias.name)"
end

function render_sql(stmt::SqlSelectStatement)
    parts = String[render_sql(stmt.select_clause), render_sql(stmt.from_clause)]
    w = render_sql(stmt.where_clause)
    isempty(w) || push!(parts, w)
    join(parts, " ")
end

# ── resolve_sql_names! ─────────────────────────────────────────────────────────

"""
    resolve_sql_names!(stmt::SqlSelectStatement) -> SqlSelectStatement

Bottom-up name resolution pass. Walks the document tree and rebinds qualifier
and column-name reference fields so they hold the same object instance as the
canonical definition document (the deepest node that originally introduced the
identifier). After this pass, identity equality (`===`) reliably indicates
co-reference.
"""
function resolve_sql_names!(stmt::SqlSelectStatement)
    # Recurse into subqueries first (bottom-up)
    for from_item in stmt.from_clause.items
        _resolve_subqueries!(from_item)
    end

    # Build table/alias scope from the FROM clause
    tscope = Dict{String, SqlDocument}()
    for from_item in stmt.from_clause.items
        _register_base_item!(tscope, from_item.base_item)
        for seg in from_item.joins
            _register_base_item!(tscope, seg.from_item)
        end
    end

    # Build column alias scope from the SELECT clause
    cscope = Dict{String, SqlColumnAlias}()
    for item in stmt.select_clause.items
        ca = item.column_alias
        ca !== nothing && (cscope[ca.name] = ca)
    end

    # Rewrite qualifier and column_name fields in SELECT expressions
    for item in stmt.select_clause.items
        _resolve_select_expr!(item.expression, tscope, cscope)
    end

    # Rewrite qualifier fields in WHERE condition
    cond = stmt.where_clause.condition
    cond !== nothing && _resolve_bool_expr!(cond, tscope, cscope)

    stmt
end

function _resolve_subqueries!(from_item::SqlFromItem)
    bi = from_item.base_item
    bi isa SqlSubqueryFromItem && resolve_sql_names!(bi.subquery)
    for seg in from_item.joins
        si = seg.from_item
        si isa SqlSubqueryFromItem && resolve_sql_names!(si.subquery)
    end
end

function _register_base_item!(scope::Dict, bi::SqlTableExpression)
    scope[bi.table_name.name] = bi.table_name
    bi.alias !== nothing && (scope[bi.alias.name] = bi.alias)
end
function _register_base_item!(scope::Dict, bi::SqlSubqueryFromItem)
    bi.alias !== nothing && (scope[bi.alias.name] = bi.alias)
end

function _resolve_select_expr!(expr::SqlAllColumns, tscope, _cscope)
    q = expr.qualifier
    q !== nothing && haskey(tscope, q.name) && (expr.qualifier = tscope[q.name])
end
function _resolve_select_expr!(expr::SqlColumnReference, tscope, cscope)
    q = expr.qualifier
    q !== nothing && haskey(tscope, q.name) && (expr.qualifier = tscope[q.name])
    cn = expr.column_name
    if haskey(cscope, cn.name)
        expr.column_name = cscope[cn.name]
    end
end
_resolve_select_expr!(::SqlSelectExpression, _, _) = nothing  # fallback for future types

function _resolve_bool_expr!(expr::SqlComparison, tscope, cscope)
    expr.left  isa SqlColumnReference && _resolve_select_expr!(expr.left,  tscope, cscope)
    expr.right isa SqlColumnReference && _resolve_select_expr!(expr.right, tscope, cscope)
end
function _resolve_bool_expr!(expr::SqlAnd, tscope, cscope)
    _resolve_bool_expr!(expr.left,  tscope, cscope)
    _resolve_bool_expr!(expr.right, tscope, cscope)
end
function _resolve_bool_expr!(expr::SqlOr, tscope, cscope)
    _resolve_bool_expr!(expr.left,  tscope, cscope)
    _resolve_bool_expr!(expr.right, tscope, cscope)
end
function _resolve_bool_expr!(expr::SqlNot, tscope, cscope)
    _resolve_bool_expr!(expr.expression, tscope, cscope)
end
_resolve_bool_expr!(::SqlBooleanExpression, _, _) = nothing  # fallback for future types

# ── Base.show ──────────────────────────────────────────────────────────────────

Base.show(io::IO, n::SqlTableName)        = print(io, render_sql(n))
Base.show(io::IO, a::SqlTableAlias)       = print(io, a.name)
Base.show(io::IO, c::SqlColumnName)       = print(io, c.name)
Base.show(io::IO, a::SqlColumnAlias)      = print(io, a.name)
Base.show(io::IO, s::SqlAllColumns)       = print(io, render_sql(s))
Base.show(io::IO, r::SqlColumnReference)  = print(io, render_sql(r))
Base.show(io::IO, t::SqlTableExpression)  = print(io, render_sql(t))
Base.show(io::IO, stmt::SqlSelectStatement) = print(io, render_sql(stmt))
Base.show(io::IO, v::SqlScalarValue)   = print(io, render_sql(v))
Base.show(io::IO, c::SqlComparison)    = print(io, render_sql(c))
Base.show(io::IO, e::SqlAnd)           = print(io, render_sql(e))
Base.show(io::IO, e::SqlOr)            = print(io, render_sql(e))
Base.show(io::IO, e::SqlNot)           = print(io, render_sql(e))

end # module
