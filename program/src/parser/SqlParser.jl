"""
    SqlParserModule

Parser for SQL SELECT statements. Converts SQL source text into a
`SqlSelectStatement` tree from `SqlDocumentModule`.

Provides:
- `sqlparse(text)` — parse a SQL string into a `SqlSelectStatement`
- `sqlparse_file(path)` — read and parse a `.sql` file from disk

A lightweight tokeniser feeds a single-pass, one-token-lookahead recursive-descent
parser. Scope is the SELECT-related types defined in `Sql.jl`: SELECT/FROM/WHERE
clauses, joins, ON/USING conditions, subqueries, boolean expressions, column
references, aliases, DISTINCT, and scalar values.

Unsupported fragments are handled gracefully: comments are stripped by the
tokeniser, trailing clauses (GROUP BY, ORDER BY, …) are consumed, and unsupported
expressions (function calls, arithmetic, CASE) are wrapped in `SqlScalarValue` via
a greedy token fallback. Input that is not a parseable SELECT statement raises an
error rather than guessing, matching the other parsers in this directory.
"""
module SqlParserModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..SqlDocumentModule: SqlSelectStatement, SqlSelectClause, SqlFromClause, SqlWhereClause,
                            SqlWhereFilterCondition,
                            SqlSelectItem, SqlAllColumns, SqlColumnReference,
                            SqlTableName, SqlTableAlias, SqlColumnName, SqlColumnAlias,
                            SqlDistinct,
                            SqlTableExpression, SqlSubqueryFromItem, SqlFromItem, SqlJoinedFromItem,
                            SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin, SqlFullOuterJoin, SqlCrossJoin,
                            SqlJoinOnCondition, SqlJoinUsingCondition,
                            SqlScalarValue, SqlComparison, SqlAnd, SqlOr, SqlNot

export sqlparse, sqlparse_file

# ══════════════════════════════════════════════════════════════════════════════
# §1  Entry points
# ══════════════════════════════════════════════════════════════════════════════

"""
    sqlparse(text::AbstractString) -> SqlSelectStatement

Parse a SQL string into a `SqlSelectStatement`. Raises an error if `text` is not a
parseable SELECT statement.
"""
function sqlparse(text::AbstractString)
    parsed = parse_sql(String(text))
    parsed === nothing && error("SQL: not a parseable SELECT statement")
    return parsed
end

"""
    sqlparse_file(path::AbstractString) -> SqlSelectStatement

Read and parse a `.sql` file from disk.
"""
sqlparse_file(path::AbstractString) = sqlparse(read(path, String))

# ══════════════════════════════════════════════════════════════════════════════
# §2  Tokeniser
# ══════════════════════════════════════════════════════════════════════════════

@enum SqlTokenKind begin
    TK_KEYWORD
    TK_IDENT
    TK_QUOTED_IDENT
    TK_STRING_LIT
    TK_NUMBER_LIT
    TK_OP
    TK_STAR
    TK_DOT
    TK_COMMA
    TK_LPAREN
    TK_RPAREN
    TK_SEMICOLON
    TK_EOF
end

struct SqlToken
    kind::SqlTokenKind
    value::SubString{String}
    pos::Int
end

const SQL_KEYWORDS = Set{String}([
    "SELECT", "FROM", "WHERE", "AS", "JOIN", "ON", "USING",
    "AND", "OR", "NOT", "DISTINCT",
    "LEFT", "RIGHT", "FULL", "OUTER", "INNER", "CROSS",
    "TRUE", "FALSE",
    "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION",
    "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
    "SET", "INTO", "VALUES", "BY", "ASC", "DESC", "BETWEEN",
    "IN", "LIKE", "IS", "NULL", "CASE", "WHEN", "THEN", "ELSE", "END",
    "EXISTS", "ALL", "ANY", "SOME", "WITH", "WINDOW", "FOR",
    "NATURAL",
])

function tokenize(sql::String)::Vector{SqlToken}
    tokens = SqlToken[]
    i = 1
    n = length(sql)
    ss = SubString(sql)  # full view for cheap sub-slicing

    while i <= n
        c = sql[i]

        # ── skip whitespace ───────────────────────────────────────────
        if c == ' ' || c == '\t' || c == '\n' || c == '\r'
            i += 1
            continue
        end

        # ── line comment --  ──────────────────────────────────────────
        if c == '-' && i + 1 <= n && sql[i+1] == '-'
            i += 2
            while i <= n && sql[i] != '\n'
                i += 1
            end
            continue
        end

        # ── block comment /* */ (nestable) ────────────────────────────
        if c == '/' && i + 1 <= n && sql[i+1] == '*'
            depth = 1
            i += 2
            while i <= n && depth > 0
                if sql[i] == '/' && i + 1 <= n && sql[i+1] == '*'
                    depth += 1; i += 2
                elseif sql[i] == '*' && i + 1 <= n && sql[i+1] == '/'
                    depth -= 1; i += 2
                else
                    i += 1
                end
            end
            continue
        end

        # ── single-char tokens ────────────────────────────────────────
        if c == '*';  push!(tokens, SqlToken(TK_STAR,      SubString(sql, i, i), i)); i += 1; continue; end
        if c == '.';  push!(tokens, SqlToken(TK_DOT,       SubString(sql, i, i), i)); i += 1; continue; end
        if c == ',';  push!(tokens, SqlToken(TK_COMMA,     SubString(sql, i, i), i)); i += 1; continue; end
        if c == '(';  push!(tokens, SqlToken(TK_LPAREN,    SubString(sql, i, i), i)); i += 1; continue; end
        if c == ')';  push!(tokens, SqlToken(TK_RPAREN,    SubString(sql, i, i), i)); i += 1; continue; end
        if c == ';';  push!(tokens, SqlToken(TK_SEMICOLON, SubString(sql, i, i), i)); i += 1; continue; end

        # ── operators (multi-char first) ──────────────────────────────
        if c == '<' || c == '>' || c == '!' || c == '='
            start = i
            if c == '<' && i + 1 <= n && sql[i+1] == '>'
                i += 2
            elseif c == '<' && i + 1 <= n && sql[i+1] == '='
                i += 2
            elseif c == '>' && i + 1 <= n && sql[i+1] == '='
                i += 2
            elseif c == '!' && i + 1 <= n && sql[i+1] == '='
                i += 2
            else
                i += 1
            end
            push!(tokens, SqlToken(TK_OP, SubString(sql, start, i - 1), start))
            continue
        end

        # ── single-quoted string literal ──────────────────────────────
        if c == '\''
            start = i
            i += 1
            while i <= n
                if sql[i] == '\'' && i + 1 <= n && sql[i+1] == '\''
                    i += 2  # escaped quote
                elseif sql[i] == '\''
                    i += 1; break
                else
                    i += 1
                end
            end
            push!(tokens, SqlToken(TK_STRING_LIT, SubString(sql, start, i - 1), start))
            continue
        end

        # ── double-quoted identifier ──────────────────────────────────
        if c == '"'
            start = i
            i += 1
            while i <= n && sql[i] != '"'
                i += 1
            end
            if i <= n; i += 1; end  # consume closing "
            push!(tokens, SqlToken(TK_QUOTED_IDENT, SubString(sql, start, i - 1), start))
            continue
        end

        # ── numeric literal ───────────────────────────────────────────
        if c >= '0' && c <= '9'
            start = i
            i += 1
            while i <= n && (sql[i] >= '0' && sql[i] <= '9' || sql[i] == '.')
                i += 1
            end
            push!(tokens, SqlToken(TK_NUMBER_LIT, SubString(sql, start, i - 1), start))
            continue
        end

        # ── identifier / keyword ──────────────────────────────────────
        if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '_'
            start = i
            i += 1
            while i <= n && (sql[i] >= 'A' && sql[i] <= 'Z' || sql[i] >= 'a' && sql[i] <= 'z' ||
                             sql[i] >= '0' && sql[i] <= '9' || sql[i] == '_')
                i += 1
            end
            val = SubString(sql, start, i - 1)
            upper = uppercase(String(val))
            kind = upper in SQL_KEYWORDS ? TK_KEYWORD : TK_IDENT
            push!(tokens, SqlToken(kind, val, start))
            continue
        end

        # ── skip unknown character ────────────────────────────────────
        i += 1
    end

    push!(tokens, SqlToken(TK_EOF, SubString(sql, n + 1, n), n + 1))
    return tokens
end

# ══════════════════════════════════════════════════════════════════════════════
# §3  Recursive-descent parser
# ══════════════════════════════════════════════════════════════════════════════

mutable struct Parser
    tokens::Vector{SqlToken}
    pos::Int
    source::String  # original SQL for fallback raw-text extraction
end

Parser(sql::String) = Parser(tokenize(sql), 1, sql)

# ── lookahead helpers ─────────────────────────────────────────────────────────

peek(p::Parser) = p.tokens[p.pos]

function advance!(p::Parser)
    tok = p.tokens[p.pos]
    if p.pos < length(p.tokens)
        p.pos += 1
    end
    return tok
end

function expect_keyword!(p::Parser, kw::String)
    tok = peek(p)
    if tok.kind == TK_KEYWORD && uppercase(String(tok.value)) == kw
        return advance!(p)
    end
    return nothing
end

function match_keyword(p::Parser, kw::String)
    tok = peek(p)
    tok.kind == TK_KEYWORD && uppercase(String(tok.value)) == kw
end

function match_any_keyword(p::Parser, kws::String...)
    tok = peek(p)
    tok.kind == TK_KEYWORD || return false
    upper = uppercase(String(tok.value))
    return any(k -> k == upper, kws)
end

at_end(p::Parser) = peek(p).kind == TK_EOF || peek(p).kind == TK_SEMICOLON

# ── identifier helpers ────────────────────────────────────────────────────────

"""Extract the bare identifier string from an IDENT or QUOTED_IDENT token."""
function ident_string(tok::SqlToken)::String
    if tok.kind == TK_QUOTED_IDENT
        s = String(tok.value)
        # strip surrounding quotes
        return s[2:end-1]
    end
    return String(tok.value)
end

"""Consume an identifier (IDENT, QUOTED_IDENT, or a keyword used as identifier)."""
function consume_ident!(p::Parser)
    tok = peek(p)
    if tok.kind == TK_IDENT || tok.kind == TK_QUOTED_IDENT
        return advance!(p)
    end
    # Some keywords can appear as identifiers in certain contexts
    if tok.kind == TK_KEYWORD
        upper = uppercase(String(tok.value))
        # Only allow non-structural keywords as identifiers
        if !(upper in ("SELECT", "FROM", "WHERE", "JOIN", "ON", "USING",
                        "AND", "OR", "NOT", "DISTINCT",
                        "LEFT", "RIGHT", "FULL", "OUTER", "INNER", "CROSS",
                        "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION",
                        "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER"))
            return advance!(p)
        end
    end
    return nothing
end

# ── top-level entry ───────────────────────────────────────────────────────────

"""
    parse_sql(sql::String) → SqlSelectStatement | nothing

Parse `sql` into the SQL document hierarchy.  Returns `nothing` if the input
is not a SELECT statement or cannot be parsed.
"""
function parse_sql(sql::String)
    p = Parser(sql)
    # Must start with SELECT
    if !match_keyword(p, "SELECT")
        return nothing
    end
    try
        return parse_select_statement!(p)
    catch
        return nothing
    end
end

# ── SELECT statement ──────────────────────────────────────────────────────────

function parse_select_statement!(p::Parser)
    sc = parse_select_clause!(p)
    sc === nothing && return nothing

    fc = if match_keyword(p, "FROM")
        parse_from_clause!(p)
    else
        SqlFromClause()
    end
    fc === nothing && return nothing

    wc = if match_keyword(p, "WHERE")
        parse_where_clause!(p)
    else
        SqlWhereClause()
    end

    # skip trailing clauses (GROUP BY, ORDER BY, HAVING, LIMIT, etc.)
    skip_trailing!(p)

    return SqlSelectStatement(sc, fc, wc)
end

# ── SELECT clause ─────────────────────────────────────────────────────────────

function parse_select_clause!(p::Parser)
    expect_keyword!(p, "SELECT") === nothing && return nothing

    dist = if match_keyword(p, "DISTINCT")
        advance!(p)
        SqlDistinct()
    else
        nothing
    end

    items = SqlSelectItem[]
    item = parse_select_item!(p)
    item === nothing && return nothing
    push!(items, item)

    while peek(p).kind == TK_COMMA
        advance!(p)  # consume comma
        item = parse_select_item!(p)
        item === nothing && break
        push!(items, item)
    end

    clause = SqlSelectClause(CellVector([items...]))
    if dist !== nothing
        # Use the 3-arg constructor: distinct, items, selection
        clause = SqlSelectClause(dist, CellVector([items...]), Cell(nothing))
    end
    return clause
end

# ── SELECT item ───────────────────────────────────────────────────────────────

function parse_select_item!(p::Parser)
    expr = parse_select_expression!(p)
    expr === nothing && return nothing

    alias = nothing
    if match_keyword(p, "AS")
        advance!(p)  # consume AS
        tok = consume_ident!(p)
        if tok !== nothing
            alias = SqlColumnAlias(ident_string(tok))
        end
    end

    # SqlSelectItem constructors require SqlSelectExpression, but fallback
    # expressions produce SqlScalarValue (which is SqlDocument, not
    # SqlSelectExpression).  Build via Cell-level constructor directly.
    return SqlSelectItem(expr, alias, Cell(nothing))
end

# ── SELECT expression (column ref, *, or fallback) ───────────────────────────

function parse_select_expression!(p::Parser)
    tok = peek(p)

    # *
    if tok.kind == TK_STAR
        advance!(p)
        return SqlAllColumns()
    end

    # identifier — could be column, qualifier.column, qualifier.*, or start of complex expr
    if tok.kind == TK_IDENT || tok.kind == TK_QUOTED_IDENT || tok.kind == TK_KEYWORD
        # Try to parse as column reference
        result = try_parse_column_or_star!(p)
        if result !== nothing
            return result
        end
    end

    # number literal
    if tok.kind == TK_NUMBER_LIT
        advance!(p)
        return SqlScalarValue(parse_number(String(tok.value)))
    end

    # string literal
    if tok.kind == TK_STRING_LIT
        advance!(p)
        s = String(tok.value)
        return SqlScalarValue(s[2:end-1])  # strip quotes
    end

    # fallback: collect tokens until delimiter
    return parse_fallback_expression!(p)
end

"""Try to parse `ident`, `qualifier.ident`, or `qualifier.*`."""
function try_parse_column_or_star!(p::Parser)
    tok = peek(p)
    if !(tok.kind == TK_IDENT || tok.kind == TK_QUOTED_IDENT)
        # keyword used as ident — only if it's safe
        if tok.kind == TK_KEYWORD
            id = consume_ident!(p)
            id === nothing && return nothing
            name = ident_string(id)
        else
            return nothing
        end
    else
        id = advance!(p)
        name = ident_string(id)
    end

    # check for DOT
    if peek(p).kind == TK_DOT
        advance!(p)  # consume dot
        next = peek(p)
        if next.kind == TK_STAR
            advance!(p)
            return SqlAllColumns(SqlTableAlias(name))
        elseif next.kind == TK_IDENT || next.kind == TK_QUOTED_IDENT
            col_tok = advance!(p)
            return SqlColumnReference(SqlTableAlias(name), SqlColumnName(ident_string(col_tok)))
        elseif next.kind == TK_KEYWORD
            col_tok = consume_ident!(p)
            if col_tok !== nothing
                return SqlColumnReference(SqlTableAlias(name), SqlColumnName(ident_string(col_tok)))
            end
        end
        # dot followed by something unexpected — treat first ident as column
        return SqlColumnReference(SqlColumnName(name))
    end

    # Check if next token indicates this is a function call (identifier followed by LPAREN)
    if peek(p).kind == TK_LPAREN
        # This is a function call — backtrack and use fallback
        p.pos -= 1  # put the identifier back
        return parse_fallback_expression!(p)
    end

    return SqlColumnReference(SqlColumnName(name))
end

# ── FROM clause ───────────────────────────────────────────────────────────────

function parse_from_clause!(p::Parser)
    expect_keyword!(p, "FROM") === nothing && return nothing

    items = SqlFromItem[]
    item = parse_from_item!(p)
    item === nothing && return nothing
    push!(items, item)

    while peek(p).kind == TK_COMMA
        advance!(p)  # consume comma
        item = parse_from_item!(p)
        item === nothing && break
        push!(items, item)
    end

    return SqlFromClause(items...)
end

function parse_from_item!(p::Parser)
    base = parse_from_base_item!(p)
    base === nothing && return nothing

    joins = SqlJoinedFromItem[]
    while is_join_start(p)
        j = parse_joined_from_item!(p)
        j === nothing && break
        push!(joins, j)
    end

    return SqlFromItem(base, CellVector([joins...]), Cell(nothing))
end

function parse_from_base_item!(p::Parser)
    tok = peek(p)

    # subquery: ( SELECT ... ) [AS alias]
    if tok.kind == TK_LPAREN
        advance!(p)  # consume (
        if match_keyword(p, "SELECT")
            subquery = parse_select_statement!(p)
            subquery === nothing && return nothing
            if peek(p).kind == TK_RPAREN
                advance!(p)  # consume )
            end
            alias = parse_optional_alias!(p)
            if alias !== nothing
                return SqlSubqueryFromItem(subquery, alias)
            else
                return SqlSubqueryFromItem(subquery)
            end
        end
        # Not a subquery — skip until matching )
        depth = 1
        while !at_end(p) && depth > 0
            t = advance!(p)
            if t.kind == TK_LPAREN; depth += 1; end
            if t.kind == TK_RPAREN; depth -= 1; end
        end
        return nothing
    end

    # table expression: [schema.]table [AS alias]
    id = consume_ident!(p)
    id === nothing && return nothing
    name = ident_string(id)

    # check for schema.table
    tname = if peek(p).kind == TK_DOT
        advance!(p)  # consume dot
        table_tok = consume_ident!(p)
        if table_tok !== nothing
            SqlTableName(name, ident_string(table_tok))
        else
            SqlTableName(name)
        end
    else
        SqlTableName(name)
    end

    alias = parse_optional_alias!(p)
    if alias !== nothing
        return SqlTableExpression(tname, alias)
    else
        return SqlTableExpression(tname)
    end
end

function parse_optional_alias!(p::Parser)
    if match_keyword(p, "AS")
        advance!(p)  # consume AS
        tok = consume_ident!(p)
        tok !== nothing && return SqlTableAlias(ident_string(tok))
    elseif peek(p).kind == TK_IDENT || peek(p).kind == TK_QUOTED_IDENT
        # implicit alias (no AS keyword) — only if it doesn't look like a keyword
        tok = peek(p)
        upper = uppercase(String(tok.value))
        if !(upper in ("WHERE", "JOIN", "ON", "USING", "LEFT", "RIGHT", "FULL",
                        "INNER", "CROSS", "GROUP", "ORDER", "HAVING", "LIMIT",
                        "OFFSET", "UNION", "AND", "OR", "NOT", "SET", "SELECT", "FROM"))
            advance!(p)
            return SqlTableAlias(ident_string(tok))
        end
    end
    return nothing
end

# ── JOIN parsing ──────────────────────────────────────────────────────────────

function is_join_start(p::Parser)
    tok = peek(p)
    tok.kind != TK_KEYWORD && return false
    upper = uppercase(String(tok.value))
    return upper in ("JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS")
end

function parse_join_type!(p::Parser)
    tok = peek(p)
    upper = uppercase(String(tok.value))

    if upper == "JOIN"
        advance!(p)
        return SqlInnerJoin()
    elseif upper == "INNER"
        advance!(p)
        expect_keyword!(p, "JOIN")
        return SqlInnerJoin()
    elseif upper == "LEFT"
        advance!(p)
        match_keyword(p, "OUTER") && advance!(p)
        expect_keyword!(p, "JOIN")
        return SqlLeftOuterJoin()
    elseif upper == "RIGHT"
        advance!(p)
        match_keyword(p, "OUTER") && advance!(p)
        expect_keyword!(p, "JOIN")
        return SqlRightOuterJoin()
    elseif upper == "FULL"
        advance!(p)
        match_keyword(p, "OUTER") && advance!(p)
        expect_keyword!(p, "JOIN")
        return SqlFullOuterJoin()
    elseif upper == "CROSS"
        advance!(p)
        expect_keyword!(p, "JOIN")
        return SqlCrossJoin()
    end
    return nothing
end

function parse_joined_from_item!(p::Parser)
    jt = parse_join_type!(p)
    jt === nothing && return nothing

    base = parse_from_base_item!(p)
    base === nothing && return nothing

    cond = parse_join_condition!(p)
    if cond !== nothing
        return SqlJoinedFromItem(jt, base, cond)
    else
        return SqlJoinedFromItem(jt, base)
    end
end

function parse_join_condition!(p::Parser)
    if match_keyword(p, "ON")
        advance!(p)
        expr = parse_boolean_expression!(p)
        expr === nothing && return nothing
        return SqlJoinOnCondition(expr)
    elseif match_keyword(p, "USING")
        advance!(p)
        if peek(p).kind == TK_LPAREN
            advance!(p)  # consume (
            cols = SqlColumnName[]
            tok = consume_ident!(p)
            tok !== nothing && push!(cols, SqlColumnName(ident_string(tok)))
            while peek(p).kind == TK_COMMA
                advance!(p)
                tok = consume_ident!(p)
                tok !== nothing && push!(cols, SqlColumnName(ident_string(tok)))
            end
            if peek(p).kind == TK_RPAREN
                advance!(p)  # consume )
            end
            return SqlJoinUsingCondition(cols...)
        end
    end
    return nothing
end

# ── WHERE clause ──────────────────────────────────────────────────────────────

function parse_where_clause!(p::Parser)
    expect_keyword!(p, "WHERE") === nothing && return nothing

    expr = parse_boolean_expression!(p)
    expr === nothing && return SqlWhereClause()

    return SqlWhereClause(SqlWhereFilterCondition(expr))
end

# ── Boolean expressions (precedence: OR < AND < NOT < primary) ────────────────

function parse_boolean_expression!(p::Parser)
    return parse_or!(p)
end

function parse_or!(p::Parser)
    left = parse_and!(p)
    left === nothing && return nothing

    while match_keyword(p, "OR")
        advance!(p)
        right = parse_and!(p)
        right === nothing && break
        left = SqlOr(left, right)
    end
    return left
end

function parse_and!(p::Parser)
    left = parse_not!(p)
    left === nothing && return nothing

    while match_keyword(p, "AND")
        advance!(p)
        right = parse_not!(p)
        right === nothing && break
        left = SqlAnd(left, right)
    end
    return left
end

function parse_not!(p::Parser)
    if match_keyword(p, "NOT")
        advance!(p)
        expr = parse_not!(p)
        expr === nothing && return nothing
        return SqlNot(expr)
    end
    return parse_boolean_primary!(p)
end

function parse_boolean_primary!(p::Parser)
    # parenthesised boolean expression
    if peek(p).kind == TK_LPAREN
        advance!(p)
        expr = parse_boolean_expression!(p)
        if peek(p).kind == TK_RPAREN
            advance!(p)
        end
        return expr
    end

    return parse_comparison!(p)
end

function parse_comparison!(p::Parser)
    left = parse_scalar_operand!(p)
    left === nothing && return nothing

    tok = peek(p)
    if tok.kind == TK_OP
        advance!(p)
        op = String(tok.value)
        # normalise != to <>
        if op == "!="
            op = "<>"
        end
        right = parse_scalar_operand!(p)
        right === nothing && return nothing
        return SqlComparison(left, op, right)
    end

    # bare operand used as boolean — wrap as comparison if it's a column ref
    # This handles cases like just a column name in a WHERE position
    if left isa SqlColumnReference || left isa SqlScalarValue
        # Return as-is if it can serve as a boolean expression
        # For our purposes, a bare scalar/column isn't a valid boolean
        # but we return a comparison with itself to avoid losing it
    end
    return nothing
end

function parse_scalar_operand!(p::Parser)
    tok = peek(p)

    # number
    if tok.kind == TK_NUMBER_LIT
        advance!(p)
        return SqlScalarValue(parse_number(String(tok.value)))
    end

    # string
    if tok.kind == TK_STRING_LIT
        advance!(p)
        s = String(tok.value)
        return SqlScalarValue(s[2:end-1])  # strip quotes
    end

    # TRUE / FALSE
    if tok.kind == TK_KEYWORD
        upper = uppercase(String(tok.value))
        if upper == "TRUE"
            advance!(p)
            return SqlScalarValue(true)
        elseif upper == "FALSE"
            advance!(p)
            return SqlScalarValue(false)
        end
    end

    # identifier — column reference [qualifier.]name
    if tok.kind == TK_IDENT || tok.kind == TK_QUOTED_IDENT
        id = advance!(p)
        name = ident_string(id)
        if peek(p).kind == TK_DOT
            advance!(p)  # consume dot
            col_tok = consume_ident!(p)
            if col_tok !== nothing
                return SqlColumnReference(SqlTableAlias(name), SqlColumnName(ident_string(col_tok)))
            end
        end
        return SqlColumnReference(SqlColumnName(name))
    end

    # keyword used as identifier
    if tok.kind == TK_KEYWORD
        id = consume_ident!(p)
        if id !== nothing
            name = ident_string(id)
            if peek(p).kind == TK_DOT
                advance!(p)
                col_tok = consume_ident!(p)
                if col_tok !== nothing
                    return SqlColumnReference(SqlTableAlias(name), SqlColumnName(ident_string(col_tok)))
                end
            end
            return SqlColumnReference(SqlColumnName(name))
        end
    end

    return nothing
end

# ── Fallback: greedy token collection for unsupported expressions ─────────────

const FALLBACK_DELIMITERS = Set{String}([
    ",", ")", "AND", "OR", "FROM", "WHERE",
    "GROUP", "ORDER", "HAVING", "LIMIT", "UNION", "OFFSET",
])

function parse_fallback_expression!(p::Parser)
    start_pos = peek(p).pos
    depth = 0
    last_end = start_pos

    while !at_end(p)
        tok = peek(p)

        # stop at structural delimiters (unless inside parens)
        if depth == 0
            if tok.kind == TK_COMMA || tok.kind == TK_RPAREN
                break
            end
            if tok.kind == TK_KEYWORD && uppercase(String(tok.value)) in FALLBACK_DELIMITERS
                break
            end
            # also stop at AS for alias detection
            if tok.kind == TK_KEYWORD && uppercase(String(tok.value)) == "AS"
                break
            end
        end

        if tok.kind == TK_LPAREN
            depth += 1
        elseif tok.kind == TK_RPAREN
            if depth > 0
                depth -= 1
            else
                break
            end
        end

        last_end = tok.pos + length(tok.value) - 1
        advance!(p)
    end

    if last_end >= start_pos
        raw = strip(SubString(p.source, start_pos, last_end))
        if !isempty(raw)
            return SqlScalarValue(String(raw))
        end
    end
    return nothing
end

# ── Skip trailing clauses ────────────────────────────────────────────────────

function skip_trailing!(p::Parser)
    while !at_end(p) && peek(p).kind != TK_RPAREN
        advance!(p)
    end
end

# ── Numeric parsing helper ───────────────────────────────────────────────────

function parse_number(s::String)
    if occursin('.', s)
        return parse(Float64, s)
    else
        return parse(Int, s)
    end
end

end # module
