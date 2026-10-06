# Fragment of `SqlModule`.
#
# Parser for SQL statements. Converts SQL source text into a `SqlStatement` tree
# from `SqlModule`. Two statement families are recognised:
#
# - **SELECT** queries → `SqlSelectStatement`.
# - **DDL** `CREATE TABLE` / `CREATE SCHEMA` → `SqlCreateTableStatement` /
#   `SqlCreateSchemaStatement`.
#
# A text of several statements separated by `;` parses into a `SqlStatementList`.
#
# Provides:
# - `parse_sql_text(text)` — parse a SQL string into a `SqlStatement`, or into a
#   `SqlStatementList` when it holds more than one statement
# - `parse_sql_file(path)` — read and parse a `.sql` file from disk
#
# A lightweight tokeniser feeds a single-pass, one-token-lookahead recursive-descent
# parser. Scope is the SELECT-related types defined in `SqlDocument.jl`:
# SELECT/FROM/WHERE clauses, joins, ON/USING conditions, subqueries, boolean
# expressions, column references, aliases, DISTINCT, and scalar values; plus the DDL
# `CREATE TABLE` (table name + column name/type list) and `CREATE SCHEMA` (schema
# name) forms.
#
# Unsupported fragments are handled gracefully: comments are stripped by the
# tokeniser, trailing clauses (GROUP BY, ORDER BY, …) are consumed, and a select
# expression that the model does not have, such as a function call, is kept as its
# source text in a `SqlRawExpression` by a greedy token fallback. A condition of a
# `WHERE` or an `ON` that the model does not have, such as `a LIKE 'x%'`, is kept
# in a `SqlRawCondition` by the same fallback. A join of a form that the model
# does not have, such as a `NATURAL JOIN`, has no raw form to be kept in, so it
# raises an error rather than being dropped. Input that is not a
# parseable statement raises an error rather than guessing, matching the other
# parsers in this directory.
# ══════════════════════════════════════════════════════════════════════════════
# §1  Entry points
# ══════════════════════════════════════════════════════════════════════════════

"""
    parse_sql_text(text::AbstractString) -> SqlStatement | SqlStatementList

Parse a SQL string into a `SqlStatement` (a `SqlSelectStatement` for queries, or a
`SqlCreateTableStatement` / `SqlCreateSchemaStatement` for DDL). A text of several
statements separated by `;` gives a `SqlStatementList`. Raises an error if a
statement of `text` is not parseable.
"""
function parse_sql_text(text::AbstractString)
    parsed = parse_sql(String(text))
    parsed === nothing && error("SQL: not a parseable statement")
    return parsed
end

"""
    parse_sql_file(path::AbstractString) -> SqlStatement | SqlStatementList

Read and parse a `.sql` file from disk.
"""
parse_sql_file(path::AbstractString) = parse_sql_text(read(path, String))

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
    TK_SIGN
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
    "TABLE", "SCHEMA",
    "SET", "INTO", "VALUES", "BY", "ASC", "DESC", "BETWEEN",
    "IN", "LIKE", "IS", "NULL", "CASE", "WHEN", "THEN", "ELSE", "END",
    "EXISTS", "ALL", "ANY", "SOME", "WITH", "WINDOW", "FOR",
    "NATURAL",
])

# `i` is a string index: a character that is not ASCII takes more than one, so
# the tokenizer steps with `nextind` over any text that can hold one, and a token
# ends at `prevind` of the index after it.
function tokenize(sql::String)::Vector{SqlToken}
    tokens = SqlToken[]
    i = 1
    n = ncodeunits(sql)

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
                i = nextind(sql, i)
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
                    i = nextind(sql, i)
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

        # ── + and - ───────────────────────────────────────────────────
        # The parser reads one as the sign of a number where the grammar reads a
        # value, and keeps it as an operator between two operands.
        if c == '+' || c == '-'
            push!(tokens, SqlToken(TK_SIGN, SubString(sql, i, i), i)); i += 1; continue
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
                    i = nextind(sql, i)
                end
            end
            push!(tokens, SqlToken(TK_STRING_LIT, SubString(sql, start, prevind(sql, i)), start))
            continue
        end

        # ── double-quoted identifier ──────────────────────────────────
        if c == '"'
            start = i
            i += 1
            while i <= n && sql[i] != '"'
                i = nextind(sql, i)
            end
            if i <= n; i += 1; end  # consume closing "
            push!(tokens, SqlToken(TK_QUOTED_IDENT, SubString(sql, start, prevind(sql, i)), start))
            continue
        end

        # ── numeric literal ───────────────────────────────────────────
        if c >= '0' && c <= '9'
            start = i
            i += 1
            while i <= n && (sql[i] >= '0' && sql[i] <= '9' || sql[i] == '.')
                i += 1
            end
            i = _get_number_exponent_end(sql, i, n)
            push!(tokens, SqlToken(TK_NUMBER_LIT, SubString(sql, start, i - 1), start))
            continue
        end

        # ── identifier / keyword ──────────────────────────────────────
        # A letter of any script starts an identifier, as in PostgreSQL.
        if isletter(c) || c == '_'
            start = i
            i = nextind(sql, i)
            while i <= n && (isletter(sql[i]) || '0' <= sql[i] <= '9' || sql[i] == '_')
                i = nextind(sql, i)
            end
            val = SubString(sql, start, prevind(sql, i))
            upper = uppercase(String(val))
            kind = upper in SQL_KEYWORDS ? TK_KEYWORD : TK_IDENT
            push!(tokens, SqlToken(kind, val, start))
            continue
        end

        # ── skip unknown character ────────────────────────────────────
        i = nextind(sql, i)
    end

    push!(tokens, SqlToken(TK_EOF, SubString(sql, n + 1, n), n + 1))
    return tokens
end

# The index after the exponent of the number literal that ends at `i`, or `i`
# itself where no exponent stands there. An `e` or an `E` is part of the number
# only when a digit follows it, with a sign between them or without one, so `1e5`
# is one number and the `e` of `2e` is an identifier.
function _get_number_exponent_end(sql::String, i::Int, n::Int)
    (i <= n && (sql[i] == 'e' || sql[i] == 'E')) || return i
    j = i + 1
    (j <= n && (sql[j] == '+' || sql[j] == '-')) && (j += 1)
    (j <= n && '0' <= sql[j] <= '9') || return i
    while j <= n && '0' <= sql[j] <= '9'
        j += 1
    end
    return j
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

# The text of a quoted token without its two quotes. A character that is not ASCII
# takes more than one string index, so the quotes are cut by character.
_strip_quotes(s::String) = String(chop(s; head = 1, tail = 1))

# The value of a string literal token: the text between its quotes, with each
# doubled quote `''` read as one quote.
_unquote_string_literal(tok::SqlToken) = replace(_strip_quotes(String(tok.value)), "''" => "'")

# The string index of the last character of `tok` in the source.
_get_token_last_index(tok::SqlToken) = tok.pos + lastindex(tok.value) - 1

"""Extract the bare identifier string from an IDENT or QUOTED_IDENT token."""
function ident_string(tok::SqlToken)::String
    if tok.kind == TK_QUOTED_IDENT
        s = String(tok.value)
        return _strip_quotes(s)
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
    parse_sql(sql::String) → SqlStatement | SqlStatementList | nothing

Parse `sql` into the SQL document hierarchy. The statements are separated by `;`.
An empty statement is skipped, so a trailing `;` is allowed. One statement is
returned as it is, and more than one as a `SqlStatementList`. Returns `nothing`
if the input holds no statement, or if a statement is neither a SELECT query nor a
supported `CREATE` DDL statement, or cannot be parsed.
"""
function parse_sql(sql::String)
    p = Parser(sql)
    statements = SqlStatement[]
    while true
        while peek(p).kind == TK_SEMICOLON
            advance!(p)
        end
        peek(p).kind == TK_EOF && break
        statement = parse_statement!(p)
        statement === nothing && return nothing
        push!(statements, statement)
        # A statement ends at a `;` or at the end of the text.
        at_end(p) || return nothing
    end
    isempty(statements) && return nothing
    length(statements) == 1 ? statements[1] : SqlStatementList(statements)
end

# One statement, dispatched on its first keyword.
function parse_statement!(p::Parser)
    if match_keyword(p, "SELECT")
        try
            return parse_select_statement!(p)
        catch
            return nothing
        end
    elseif match_keyword(p, "CREATE")
        try
            return parse_create_statement!(p)
        catch
            return nothing
        end
    end
    return nothing
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
    wc === nothing && return nothing

    # skip trailing clauses (GROUP BY, ORDER BY, HAVING, LIMIT, etc.)
    skip_trailing!(p)

    return SqlSelectStatement(sc, fc, wc)
end

# ── CREATE (DDL) statements ─────────────────────────────────────────────────────

"""
    parse_create_statement!(p) → SqlCreateTableStatement | SqlCreateSchemaStatement | nothing

Dispatch a leading `CREATE` to the `TABLE` or `SCHEMA` form. Returns `nothing`
for any other `CREATE …` (INDEX, VIEW, DATABASE, …) — out of scope here.
"""
function parse_create_statement!(p::Parser)
    expect_keyword!(p, "CREATE") === nothing && return nothing
    if match_keyword(p, "TABLE")
        return parse_create_table!(p)
    elseif match_keyword(p, "SCHEMA")
        return parse_create_schema!(p)
    end
    return nothing
end

# CREATE SCHEMA <name>
function parse_create_schema!(p::Parser)
    expect_keyword!(p, "SCHEMA") === nothing && return nothing
    id = consume_ident!(p)
    id === nothing && return nothing
    name = ident_string(id)
    skip_trailing!(p)
    return SqlCreateSchemaStatement(name)
end

# CREATE TABLE [schema.]table ( <column-def> {, <column-def>} )
function parse_create_table!(p::Parser)
    expect_keyword!(p, "TABLE") === nothing && return nothing

    id = consume_ident!(p)
    id === nothing && return nothing
    name = ident_string(id)

    tname = if peek(p).kind == TK_DOT
        advance!(p)  # consume dot
        table_tok = consume_ident!(p)
        table_tok !== nothing ? SqlTableName(name, ident_string(table_tok)) : SqlTableName(name)
    else
        SqlTableName(name)
    end

    peek(p).kind == TK_LPAREN || return nothing
    advance!(p)  # consume (

    columns = SqlColumnDefinition[]
    if peek(p).kind != TK_RPAREN
        col = parse_column_definition!(p)
        col === nothing && return nothing
        push!(columns, col)
        while peek(p).kind == TK_COMMA
            advance!(p)  # consume comma
            col = parse_column_definition!(p)
            col === nothing && break
            push!(columns, col)
        end
    end

    if peek(p).kind == TK_RPAREN
        advance!(p)  # consume )
    end
    skip_trailing!(p)

    return SqlCreateTableStatement(tname, CellVector([columns...]))
end

# A single `<column-name> <data-type>` entry. The catalog model carries only the
# column name and a plain-string type, so the type is captured as raw source text
# (e.g. "integer", "varchar(255)", "numeric(10, 2)") up to the next top-level
# comma or the closing paren. Any trailing per-column constraints (NOT NULL,
# PRIMARY KEY, …) are folded into that string — the document model has no field
# for them yet (see plan: catalog enrichment is tracked separately).
function parse_column_definition!(p::Parser)
    id = consume_ident!(p)
    id === nothing && return nothing
    col_name = ident_string(id)

    type_str = parse_data_type!(p)
    type_str === nothing && return nothing

    return SqlColumnDefinition(SqlColumnName(col_name), type_str)
end

# Greedy raw-text capture of a column's data type, respecting paren depth so
# parameterised types like `numeric(10, 2)` are kept whole. Stops at a top-level
# comma or closing paren (the column-list delimiters).
function parse_data_type!(p::Parser)
    start_pos = peek(p).pos
    depth = 0
    last_end = -1

    while !at_end(p)
        tok = peek(p)
        if depth == 0 && (tok.kind == TK_COMMA || tok.kind == TK_RPAREN)
            break
        end
        if tok.kind == TK_LPAREN
            depth += 1
        elseif tok.kind == TK_RPAREN
            depth -= 1
        end
        last_end = _get_token_last_index(tok)
        advance!(p)
    end

    last_end < start_pos && return nothing
    raw = strip(SubString(p.source, start_pos, last_end))
    isempty(raw) && return nothing
    return String(raw)
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
    first_token = p.pos
    expr = parse_select_expression!(p)
    expr === nothing && return nothing
    # An expression that goes on after a column or a literal, such as `a + 1`, is
    # read again from its first token as raw text, so no part of it is lost.
    if !_is_select_expression_end(p)
        p.pos = first_token
        expr = parse_fallback_expression!(p)
        expr === nothing && return nothing
    end

    alias = nothing
    if match_keyword(p, "AS")
        advance!(p)  # consume AS
        tok = consume_ident!(p)
        if tok !== nothing
            alias = SqlColumnAlias(ident_string(tok))
        end
    end

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

    # number literal, with the sign in front of it
    number = parse_number_literal!(p)
    number === nothing || return SqlScalarValue(number)

    # string literal
    if tok.kind == TK_STRING_LIT
        advance!(p)
        return SqlScalarValue(_unquote_string_literal(tok))
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
        item === nothing && error("SQL: a from item after a comma that the parser does not read")
        push!(items, item)
    end

    return SqlFromClause(items...)
end

function parse_from_item!(p::Parser)
    base = parse_from_base_item!(p)
    base === nothing && return nothing

    # A join of a form that the document model does not have, such as a
    # `NATURAL JOIN` or a join of a list of tables, is an error for the whole
    # statement. The from items have no raw form to keep the text in, and the
    # skip of the trailing clauses would otherwise take the join and every
    # clause after it, so the error is what keeps the text.
    joins = SqlJoinedFromItem[]
    while is_join_start(p)
        j = parse_joined_from_item!(p)
        j === nothing && error("SQL: a join that the parser does not read")
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

# `NATURAL` starts a join that `parse_join_type!` does not read. It is here so
# that the join is seen and raises the error, and not left to the skip of the
# trailing clauses.
function is_join_start(p::Parser)
    tok = peek(p)
    tok.kind != TK_KEYWORD && return false
    upper = uppercase(String(tok.value))
    return upper in ("JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL")
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

# A join names a condition with `ON` or with `USING`, or names none at all. A
# condition that the documents can not hold keeps its text, so `nothing` from
# the condition parser means the `ON` stands before no condition, and an `ON` or
# a `USING` with no condition after it is an error for the whole statement.
function parse_join_condition!(p::Parser)
    if match_keyword(p, "ON")
        advance!(p)
        expr = parse_boolean_expression!(p)
        expr === nothing && error("SQL: the ON of a join has no condition")
        return SqlJoinOnCondition(expr)
    elseif match_keyword(p, "USING")
        advance!(p)
        peek(p).kind == TK_LPAREN || error("SQL: the USING of a join has no column list")
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
    return nothing
end

# ── WHERE clause ──────────────────────────────────────────────────────────────

function parse_where_clause!(p::Parser)
    expect_keyword!(p, "WHERE") === nothing && return nothing

    # A condition that the documents can not hold keeps its text, so `nothing`
    # here means the `WHERE` has no condition at all, which is not a statement.
    expr = parse_boolean_expression!(p)
    expr === nothing && return nothing

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
        right === nothing && return nothing   # the OR stands before no condition
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
        right === nothing && return nothing   # the AND stands before no condition
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

# One condition. The structured read comes first, and it stands only where the
# condition ends after it; otherwise the condition is read again from its first
# token as raw text, so no part of it is lost.
function parse_boolean_primary!(p::Parser)
    first_token = p.pos
    expr = parse_structured_condition!(p)
    expr !== nothing && _is_condition_end(p) && return expr
    p.pos = first_token
    return parse_raw_condition!(p)
end

# A parenthesised condition or a comparison, or `nothing` where neither stands at
# the position of `p`.
function parse_structured_condition!(p::Parser)
    if peek(p).kind == TK_LPAREN
        advance!(p)
        expr = parse_boolean_expression!(p)
        expr === nothing && return nothing
        peek(p).kind == TK_RPAREN || return nothing
        advance!(p)
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

    return nothing
end

function parse_scalar_operand!(p::Parser)
    tok = peek(p)

    # number, with the sign in front of it
    number = parse_number_literal!(p)
    number === nothing || return SqlScalarValue(number)

    # string
    if tok.kind == TK_STRING_LIT
        advance!(p)
        return SqlScalarValue(_unquote_string_literal(tok))
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

# ── Fallback: the source text of a condition ─────────────────────────────────

# The keywords that end a condition: the two that join two conditions, the clauses
# that follow a `WHERE` or an `ON`, and the ones that start a join.
const CONDITION_END_KEYWORDS = Set{String}([
    "AND", "OR", "WHERE",
    "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION",
    "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL",
])

# Whether a condition ends at the token of `p`: the end of the statement, a comma,
# a closing parenthesis, or a keyword that starts what follows a condition. `LEFT (`
# and `RIGHT (` are function calls, so they end no condition.
function _is_condition_end(p::Parser)
    at_end(p) && return true
    tok = peek(p)
    (tok.kind == TK_COMMA || tok.kind == TK_RPAREN) && return true
    tok.kind == TK_KEYWORD || return false
    word = uppercase(String(tok.value))
    word in CONDITION_END_KEYWORDS || return false
    (word == "LEFT" || word == "RIGHT") && p.tokens[p.pos + 1].kind == TK_LPAREN && return false
    return true
end

# The source text of a condition that the documents do not have, from the token of
# `p` to the token before the one that ends the condition. A parenthesis is
# counted, so a condition such as `a IN (1, 2)` stays whole, and the `AND` of a
# `BETWEEN` belongs to the condition that the `BETWEEN` is in.
function parse_raw_condition!(p::Parser)
    start_pos = peek(p).pos
    last_end = -1
    depth = 0
    open_betweens = 0

    while !at_end(p)
        tok = peek(p)
        if depth == 0 && _is_condition_end(p)
            word = tok.kind == TK_KEYWORD ? uppercase(String(tok.value)) : ""
            (open_betweens > 0 && word == "AND") || break
            open_betweens -= 1
        end
        if tok.kind == TK_LPAREN
            depth += 1
        elseif tok.kind == TK_RPAREN
            depth -= 1
        elseif depth == 0 && tok.kind == TK_KEYWORD && uppercase(String(tok.value)) == "BETWEEN"
            open_betweens += 1
        end
        last_end = _get_token_last_index(tok)
        advance!(p)
    end

    last_end < start_pos && return nothing
    raw = strip(SubString(p.source, start_pos, last_end))
    isempty(raw) && return nothing
    return SqlRawCondition(String(raw))
end

# ── Fallback: greedy token collection for unsupported expressions ─────────────

const FALLBACK_DELIMITERS = Set{String}([
    ",", ")", "AND", "OR", "FROM", "WHERE",
    "GROUP", "ORDER", "HAVING", "LIMIT", "UNION", "OFFSET",
])

# Whether the next token ends a select expression: the end of the statement, a
# delimiter of the fallback, or the `AS` of an alias.
function _is_select_expression_end(p::Parser)
    at_end(p) && return true
    tok = peek(p)
    (tok.kind == TK_COMMA || tok.kind == TK_RPAREN) && return true
    tok.kind == TK_KEYWORD || return false
    word = uppercase(String(tok.value))
    word == "AS" || word in FALLBACK_DELIMITERS
end

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

        last_end = _get_token_last_index(tok)
        advance!(p)
    end

    if last_end >= start_pos
        raw = strip(SubString(p.source, start_pos, last_end))
        if !isempty(raw)
            return SqlRawExpression(String(raw))
        end
    end
    return nothing
end

# ── Skip trailing clauses ────────────────────────────────────────────────────

# The clauses after the WHERE are skipped to the end of the statement. A
# parenthesis is counted, so a `)` of a clause such as `ORDER BY lower(name)` does
# not end the skip; a `)` that opens no parenthesis does, because it closes the
# subquery that the statement is in.
function skip_trailing!(p::Parser)
    depth = 0
    while !at_end(p)
        tok = peek(p)
        if tok.kind == TK_RPAREN
            depth == 0 && break
            depth -= 1
        elseif tok.kind == TK_LPAREN
            depth += 1
        end
        advance!(p)
    end
end

# ── Numeric parsing helper ───────────────────────────────────────────────────

# The value of the number literal at the position of `p`, with the `+` or `-` in
# front of it, or `nothing` when no number starts there. A sign that no number
# follows is an operator, and `p` does not move.
function parse_number_literal!(p::Parser)
    tok = peek(p)
    if tok.kind == TK_NUMBER_LIT
        advance!(p)
        return parse_number(String(tok.value))
    end
    tok.kind == TK_SIGN || return nothing
    # The token list ends with `TK_EOF`, so a sign always has a next token.
    number = p.tokens[p.pos + 1]
    number.kind == TK_NUMBER_LIT || return nothing
    advance!(p)
    advance!(p)
    value = parse_number(String(number.value))
    tok.value == "-" ? -value : value
end

function parse_number(s::String)
    if occursin('.', s) || occursin('e', s) || occursin('E', s)
        return parse(Float64, s)
    else
        return parse(Int, s)
    end
end
