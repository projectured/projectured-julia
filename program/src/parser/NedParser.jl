"""
    NedParserModule

Parser for OMNeT++ NED2 files. Converts NED source text into a `NedFile`
document tree from `NedModule`.

Provides:
- `nedparse(text; filename="")` — parse a NED string into a `NedFile`
- `nedparse_file(path)` — read and parse a `.ned` file from disk

The parser is a hand-written recursive-descent parser operating on a token
stream. Expressions (parameter values, vector sizes, conditions) are captured
as opaque strings rather than parsed into an AST.
"""
module NedParserModule

import ..NedModule: NedFile, NedPackage, NedImport, NedProperty, NedPropertyDecl,
                    NedPropertyKey, NedLiteral, NedParam, NedGate,
                    NedSimpleModule, NedCompoundModule, NedModuleInterface,
                    NedChannel, NedChannelInterface,
                    NedSubmodule, NedConnection, NedConnectionGroup,
                    NedLoop, NedCondition, NedExtends, NedInterfaceName,
                    NedDocument
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
export nedparse, nedparse_file

# ── Token types ───────────────────────────────────────────────────────────

@enum TokKind begin
    TOK_IDENT          # identifier or qualified name
    TOK_STRING         # "..." string literal
    TOK_NUMBER         # numeric literal (possibly with unit suffix)
    TOK_LBRACE         # {
    TOK_RBRACE         # }
    TOK_LPAREN         # (
    TOK_RPAREN         # )
    TOK_LBRACKET       # [
    TOK_RBRACKET       # ]
    TOK_SEMI           # ;
    TOK_COMMA          # ,
    TOK_EQ             # =
    TOK_AT             # @
    TOK_DOT            # .
    TOK_DOTDOT         # ..
    TOK_COLON          # :
    TOK_PLUSPLUS        # ++
    TOK_ARROW_R        # -->
    TOK_ARROW_L        # <--
    TOK_ARROW_BI       # <-->
    TOK_OP             # any other operator character(s): +, -, *, /, %, ^, <, >, !, ?, &, |, ~
    TOK_EOF            # end of input
end

struct Token
    kind::TokKind
    text::String
    pos::Int       # byte offset in source
end

# ── Keywords ──────────────────────────────────────────────────────────────

const KEYWORDS = Set([
    "package", "import", "simple", "module", "network",
    "moduleinterface", "channelinterface", "channel",
    "extends", "like", "parameters", "gates", "types", "submodules",
    "connections", "allowunconnected",
    "input", "output", "inout", "volatile", "default",
    "if", "for", "int", "double", "string", "bool", "object", "xml",
    "true", "false", "sizeof", "index", "parent",
])

const PARAM_TYPES = Set(["int", "double", "string", "bool", "object", "xml"])
const GATE_TYPES = Set(["input", "output", "inout"])
const SECTION_KEYWORDS = Set(["parameters", "gates", "types", "submodules", "connections"])

# ── Tokenizer ─────────────────────────────────────────────────────────────

function tokenize(src::AbstractString)
    tokens = Token[]
    i = 1
    n = lastindex(src)
    while i <= n
        c = src[i]

        # skip whitespace
        if c == ' ' || c == '\t' || c == '\r' || c == '\n'
            i = nextind(src, i)
            continue
        end

        # skip // comments
        if c == '/' && i < n && src[nextind(src, i)] == '/'
            while i <= n && src[i] != '\n'
                i = nextind(src, i)
            end
            continue
        end

        pos = i

        # string literal
        if c == '"'
            i = nextind(src, i)
            buf = IOBuffer()
            write(buf, '"')
            while i <= n
                ch = src[i]
                write(buf, ch)
                if ch == '\\' && i < n
                    i = nextind(src, i)
                    write(buf, src[i])
                elseif ch == '"'
                    i = nextind(src, i)
                    break
                end
                i = nextind(src, i)
            end
            push!(tokens, Token(TOK_STRING, String(take!(buf)), pos))
            continue
        end

        # number literal: starts with digit or . followed by digit
        if isdigit(c) || (c == '.' && i < n && isdigit(src[nextind(src, i)]))
            j = i
            while i <= n && (isdigit(src[i]) || src[i] == '.' || src[i] == 'e' || src[i] == 'E')
                if (src[i] == 'e' || src[i] == 'E') && i < n && (src[nextind(src, i)] == '+' || src[nextind(src, i)] == '-')
                    i = nextind(src, i) # skip e/E
                    i = nextind(src, i) # skip +/-
                else
                    i = nextind(src, i)
                end
            end
            # optional unit suffix (letters)
            while i <= n && (isletter(src[i]) || src[i] == '_')
                i = nextind(src, i)
            end
            push!(tokens, Token(TOK_NUMBER, src[j:prevind(src, i)], pos))
            continue
        end

        # identifier / keyword
        if isletter(c) || c == '_'
            j = i
            while i <= n && (isletter(src[i]) || isdigit(src[i]) || src[i] == '_')
                i = nextind(src, i)
            end
            push!(tokens, Token(TOK_IDENT, src[j:prevind(src, i)], pos))
            continue
        end

        # multi-char punctuation (order matters for prefix matching)
        if c == '<' && i + 2 <= n && src[i:i+2] == "<--"
            if i + 3 <= n && src[i+3] == '>'
                push!(tokens, Token(TOK_ARROW_BI, "<-->", pos))
                i += 4
            else
                push!(tokens, Token(TOK_ARROW_L, "<--", pos))
                i += 3
            end
            continue
        end

        if c == '-' && i + 1 <= n && src[i:i+1] == "->" && i >= 2 && src[prevind(src, i)] == '-'
            # already handled by --> below
        end

        if c == '-' && i + 2 <= n && src[i:i+2] == "-->"
            push!(tokens, Token(TOK_ARROW_R, "-->", pos))
            i += 3
            continue
        end

        if c == '.' && i < n && src[nextind(src, i)] == '.'
            push!(tokens, Token(TOK_DOTDOT, "..", pos))
            i += 2
            continue
        end

        if c == '+' && i < n && src[nextind(src, i)] == '+'
            push!(tokens, Token(TOK_PLUSPLUS, "++", pos))
            i += 2
            continue
        end

        # single-char punctuation
        if c == '{'; push!(tokens, Token(TOK_LBRACE, "{", pos)); i = nextind(src, i); continue; end
        if c == '}'; push!(tokens, Token(TOK_RBRACE, "}", pos)); i = nextind(src, i); continue; end
        if c == '('; push!(tokens, Token(TOK_LPAREN, "(", pos)); i = nextind(src, i); continue; end
        if c == ')'; push!(tokens, Token(TOK_RPAREN, ")", pos)); i = nextind(src, i); continue; end
        if c == '['; push!(tokens, Token(TOK_LBRACKET, "[", pos)); i = nextind(src, i); continue; end
        if c == ']'; push!(tokens, Token(TOK_RBRACKET, "]", pos)); i = nextind(src, i); continue; end
        if c == ';'; push!(tokens, Token(TOK_SEMI, ";", pos)); i = nextind(src, i); continue; end
        if c == ','; push!(tokens, Token(TOK_COMMA, ",", pos)); i = nextind(src, i); continue; end
        if c == '='; push!(tokens, Token(TOK_EQ, "=", pos)); i = nextind(src, i); continue; end
        if c == '@'; push!(tokens, Token(TOK_AT, "@", pos)); i = nextind(src, i); continue; end
        if c == '.'; push!(tokens, Token(TOK_DOT, ".", pos)); i = nextind(src, i); continue; end
        if c == ':'; push!(tokens, Token(TOK_COLON, ":", pos)); i = nextind(src, i); continue; end

        # operator characters
        if c in "+-*/%^<>!?&|~"
            push!(tokens, Token(TOK_OP, string(c), pos))
            i = nextind(src, i)
            continue
        end

        # skip unknown characters
        i = nextind(src, i)
    end

    push!(tokens, Token(TOK_EOF, "", n + 1))
    return tokens
end

# ── Parser state ──────────────────────────────────────────────────────────

mutable struct Parser
    tokens::Vector{Token}
    pos::Int
end

Parser(tokens::Vector{Token}) = Parser(tokens, 1)

peek(p::Parser) = p.tokens[p.pos]
peekn(p::Parser, n::Int) = p.pos + n - 1 <= length(p.tokens) ? p.tokens[p.pos + n - 1] : p.tokens[end]
advance!(p::Parser) = (t = p.tokens[p.pos]; p.pos += 1; t)
at_end(p::Parser) = peek(p).kind == TOK_EOF

function expect!(p::Parser, kind::TokKind)
    t = peek(p)
    t.kind == kind || error("NED parse error at pos $(t.pos): expected $(kind), got $(t.kind) '$(t.text)'")
    advance!(p)
end

function expect_ident!(p::Parser, word::AbstractString)
    t = peek(p)
    (t.kind == TOK_IDENT && t.text == word) ||
        error("NED parse error at pos $(t.pos): expected '$(word)', got '$(t.text)'")
    advance!(p)
end

function match_ident(p::Parser, word::AbstractString)
    t = peek(p)
    t.kind == TOK_IDENT && t.text == word
end

function match_kind(p::Parser, kind::TokKind)
    peek(p).kind == kind
end

function skip_if!(p::Parser, kind::TokKind)
    if peek(p).kind == kind
        advance!(p)
        return true
    end
    false
end

function skip_if_ident!(p::Parser, word::AbstractString)
    t = peek(p)
    if t.kind == TOK_IDENT && t.text == word
        advance!(p)
        return true
    end
    false
end

# ── Qualified name helper ─────────────────────────────────────────────────

# Parse a dotted identifier: id(.id)*
function parse_qualified_name!(p::Parser)
    t = expect!(p, TOK_IDENT)
    buf = IOBuffer()
    write(buf, t.text)
    while match_kind(p, TOK_DOT) && peekn(p, 2).kind == TOK_IDENT
        advance!(p) # .
        t2 = advance!(p) # id
        write(buf, '.', t2.text)
    end
    String(take!(buf))
end

# ── Expression collector ──────────────────────────────────────────────────

# Collect tokens until a delimiter is found, respecting nesting of (), [], {}.
# Returns the expression as a trimmed string. Does NOT consume the delimiter.
function collect_expression!(p::Parser, delimiters::Set{TokKind};
                              extra_delim_idents::Set{String}=Set{String}())
    buf = IOBuffer()
    depth_paren = 0
    depth_bracket = 0
    depth_brace = 0
    first = true

    while !at_end(p)
        t = peek(p)

        # stop at delimiter if not nested
        if depth_paren == 0 && depth_bracket == 0 && depth_brace == 0
            if t.kind in delimiters
                break
            end
            if t.kind == TOK_IDENT && t.text in extra_delim_idents
                break
            end
        end

        advance!(p)
        if t.kind == TOK_LPAREN; depth_paren += 1
        elseif t.kind == TOK_RPAREN; depth_paren -= 1
        elseif t.kind == TOK_LBRACKET; depth_bracket += 1
        elseif t.kind == TOK_RBRACKET; depth_bracket -= 1
        elseif t.kind == TOK_LBRACE; depth_brace += 1
        elseif t.kind == TOK_RBRACE; depth_brace -= 1
        end

        if !first
            write(buf, ' ')
        end
        write(buf, t.text)
        first = false
    end

    strip(String(take!(buf)))
end

# ── Property parser ──────────────────────────────────────────────────────

# Parse: @name or @name[index] optionally followed by (key1=val1;key2=val2;...)
# The @ has already been consumed.
function parse_property!(p::Parser)
    name_tok = expect!(p, TOK_IDENT)
    name = name_tok.text

    # optional [index]
    index = nothing
    if match_kind(p, TOK_LBRACKET)
        advance!(p) # [
        idx_tok = expect!(p, TOK_IDENT)
        index = idx_tok.text
        expect!(p, TOK_RBRACKET)
    end

    # optional (key=val;...)
    keys = NedPropertyKey[]
    if match_kind(p, TOK_LPAREN)
        advance!(p) # (
        while !match_kind(p, TOK_RPAREN) && !at_end(p)
            pk = _parse_property_key!(p)
            push!(keys, pk)
            skip_if!(p, TOK_SEMI)
        end
        expect!(p, TOK_RPAREN)
    end

    NedProperty(name; index=index, keys=keys)
end

# Parse a single property key: [name=]value,value,...
# Delimited by ; or )
function _parse_property_key!(p::Parser)
    # lookahead: if we see IDENT = ..., the IDENT is the key name
    key_name = nothing
    if peek(p).kind == TOK_IDENT && peekn(p, 2).kind == TOK_EQ
        key_name = advance!(p).text
        advance!(p) # =
    end

    literals = NedLiteral[]
    while !at_end(p)
        t = peek(p)
        if t.kind == TOK_SEMI || t.kind == TOK_RPAREN
            break
        end
        if t.kind == TOK_COMMA
            advance!(p)
            continue
        end
        lit = _parse_property_literal!(p)
        push!(literals, lit)
    end

    NedPropertyKey(; name=key_name, literals=literals)
end

function _parse_property_literal!(p::Parser)
    # Collect tokens until , ; or ) at depth 0
    text_str = collect_expression!(p, Set([TOK_COMMA, TOK_SEMI, TOK_RPAREN]))
    if isempty(text_str)
        return NedLiteral(:spec; text="", value="")
    end
    # Classify
    if startswith(text_str, '"') && endswith(text_str, '"')
        val = text_str[2:prevind(text_str, lastindex(text_str))]
        return NedLiteral(:string; text=text_str, value=val)
    end
    if text_str == "true" || text_str == "false"
        return NedLiteral(:bool; text=text_str, value=text_str)
    end
    if !isnothing(tryparse(Int, text_str))
        return NedLiteral(:int; text=text_str, value=text_str)
    end
    if !isnothing(tryparse(Float64, text_str))
        return NedLiteral(:double; text=text_str, value=text_str)
    end
    NedLiteral(:spec; text=text_str, value=text_str)
end

# ── Param parser ──────────────────────────────────────────────────────────

# Parse a parameter declaration line (within a parameters: block).
# Grammar (simplified):
#   [volatile] [type] name [@prop(...)...] [= expr | = default(expr)] ;
function parse_param!(p::Parser)
    is_volatile = skip_if_ident!(p, "volatile")

    # optional type keyword
    ptype = nothing
    if peek(p).kind == TOK_IDENT && peek(p).text in PARAM_TYPES
        # only if followed by another ident (the name)
        if peekn(p, 2).kind == TOK_IDENT
            ptype = Symbol(advance!(p).text)
        end
    end

    name = parse_qualified_name!(p)

    # inline @properties
    properties = NedProperty[]
    while match_kind(p, TOK_AT)
        advance!(p) # @
        push!(properties, parse_property!(p))
    end

    # optional = value
    value = nothing
    is_default = false
    if skip_if!(p, TOK_EQ)
        if skip_if_ident!(p, "default")
            is_default = true
            expect!(p, TOK_LPAREN)
            value = collect_expression!(p, Set([TOK_RPAREN]))
            expect!(p, TOK_RPAREN)
        else
            value = collect_expression!(p, Set([TOK_SEMI, TOK_AT]))
            # there might be trailing @properties after value
        end
    end

    # trailing @properties after value
    while match_kind(p, TOK_AT)
        advance!(p) # @
        push!(properties, parse_property!(p))
    end

    skip_if!(p, TOK_SEMI)

    val_str = (value !== nothing && !isempty(value)) ? value : nothing
    NedParam(name; type=ptype, value=val_str, is_volatile=is_volatile,
             is_default=is_default, properties=properties)
end

# ── Gate parser ───────────────────────────────────────────────────────────

# Parse a gate declaration:  [input|output|inout] name [vector-size] [@prop...] ;
function parse_gate!(p::Parser)
    gtype = nothing
    if peek(p).kind == TOK_IDENT && peek(p).text in GATE_TYPES
        gtype = Symbol(advance!(p).text)
    end

    name = advance!(p).text  # gate name

    is_vector = false
    vector_size = nothing
    if match_kind(p, TOK_LBRACKET)
        advance!(p) # [
        is_vector = true
        if !match_kind(p, TOK_RBRACKET)
            vector_size = collect_expression!(p, Set([TOK_RBRACKET]))
        end
        expect!(p, TOK_RBRACKET)
    end

    properties = NedProperty[]
    while match_kind(p, TOK_AT)
        advance!(p) # @
        push!(properties, parse_property!(p))
    end

    skip_if!(p, TOK_SEMI)

    NedGate(name; type=gtype, is_vector=is_vector, vector_size=vector_size,
            properties=properties)
end

# ── Submodule parser ──────────────────────────────────────────────────────

# Parse: name[vector_size] : Type { parameters: ... gates: ... }
function parse_submodule!(p::Parser)
    name = advance!(p).text

    # optional [vector_size]
    vector_size = nothing
    if match_kind(p, TOK_LBRACKET)
        advance!(p)
        vector_size = collect_expression!(p, Set([TOK_RBRACKET]))
        expect!(p, TOK_RBRACKET)
    end

    expect!(p, TOK_COLON)

    # type or <expr> like Type
    mod_type = nothing
    like_type = nothing
    like_expr = nothing
    if match_kind(p, TOK_OP) && peek(p).text == "<"
        advance!(p) # <
        like_expr = collect_expression!(p, Set([TOK_OP]))
        # expect >
        t = advance!(p)
        expect_ident!(p, "like")
        like_type = parse_qualified_name!(p)
    else
        mod_type = parse_qualified_name!(p)
    end

    # optional { ... } body with parameters:/gates: sections or bare param assignments
    condition = nothing
    params = NedDocument[]
    params_implicit = false
    gates = NedDocument[]
    if match_kind(p, TOK_LBRACE)
        advance!(p) # {
        while !match_kind(p, TOK_RBRACE) && !at_end(p)
            if skip_if_ident!(p, "parameters")
                expect!(p, TOK_COLON)
                _parse_params_into!(p, params)
            elseif skip_if_ident!(p, "gates")
                expect!(p, TOK_COLON)
                _parse_gates_into!(p, gates)
            elseif match_kind(p, TOK_AT)
                advance!(p)
                push!(params, parse_property!(p))
                skip_if!(p, TOK_SEMI)
                params_implicit = true
            else
                push!(params, parse_param!(p))
                params_implicit = true
            end
        end
        expect!(p, TOK_RBRACE)
    end

    skip_if!(p, TOK_SEMI)

    sub = NedSubmodule(name; type=mod_type, like_type=like_type, like_expr=like_expr,
                       vector_size=vector_size, condition=condition)
    for pr in params
        push!(sub.params, Cell(pr))
    end
    for g in gates
        push!(sub.gates, Cell(g))
    end
    return sub
end

# ── Connection parser ────────────────────────────────────────────────────

# Parse a gate spec: [module[index].]gate[subg][$i|$o][index][++]
# Returns (module, module_index, gate, gate_subg, gate_index, gate_plusplus)
function _parse_gate_spec!(p::Parser)
    mod_name = nothing
    mod_index = nothing
    gate_name = nothing
    gate_subg = nothing
    gate_index = nothing
    gate_plusplus = false

    # first identifier
    first = advance!(p).text

    # is it module.gate or just gate?
    if match_kind(p, TOK_LBRACKET)
        # module[index].gate  OR  gate[index]
        advance!(p) # [
        idx_expr = collect_expression!(p, Set([TOK_RBRACKET]))
        expect!(p, TOK_RBRACKET)
        if match_kind(p, TOK_DOT)
            # it was module[index].gate
            advance!(p)
            mod_name = first
            mod_index = idx_expr
            gate_name = advance!(p).text
        else
            # it was gate[index]
            gate_name = first
            gate_index = idx_expr
        end
    elseif match_kind(p, TOK_DOT)
        # module.gate
        advance!(p)
        mod_name = first
        gate_name = advance!(p).text
    else
        gate_name = first
    end

    # gate might have [index] if not consumed yet
    if gate_index === nothing && match_kind(p, TOK_LBRACKET)
        advance!(p) # [
        gate_index = collect_expression!(p, Set([TOK_RBRACKET]))
        expect!(p, TOK_RBRACKET)
    end

    # ++
    if match_kind(p, TOK_PLUSPLUS)
        advance!(p)
        gate_plusplus = true
    end

    # gate might still have [index] after ++ (rare)
    if gate_index === nothing && match_kind(p, TOK_LBRACKET)
        advance!(p)
        gate_index = collect_expression!(p, Set([TOK_RBRACKET]))
        expect!(p, TOK_RBRACKET)
    end

    return (mod_name, mod_index, gate_name, gate_subg, gate_index, gate_plusplus)
end

# Parse inline channel spec: { param = val; ... }
function _parse_inline_channel_params!(p::Parser)
    params = NedDocument[]
    if match_kind(p, TOK_LBRACE)
        advance!(p) # {
        while !match_kind(p, TOK_RBRACE) && !at_end(p)
            if match_kind(p, TOK_AT)
                advance!(p)
                push!(params, parse_property!(p))
                skip_if!(p, TOK_SEMI)
            else
                push!(params, parse_param!(p))
            end
        end
        expect!(p, TOK_RBRACE)
    end
    return params
end

# Parse a single connection line:
# src_gate_spec arrow [ChannelType | { params }] arrow dest_gate_spec [if cond] ;
function parse_connection!(p::Parser)
    src_mod, src_mod_idx, src_gate, src_subg, src_gate_idx, src_pp = _parse_gate_spec!(p)

    # arrow
    t = peek(p)
    is_bidir = false
    is_forward = true
    if t.kind == TOK_ARROW_BI
        advance!(p); is_bidir = true
    elseif t.kind == TOK_ARROW_R
        advance!(p); is_forward = true
    elseif t.kind == TOK_ARROW_L
        advance!(p); is_forward = false
    else
        error("NED parse error at pos $(t.pos): expected arrow, got '$(t.text)'")
    end

    # optional channel type or inline params between arrows (for bidirectional/forward)
    chan_type = nothing
    chan_params = NedDocument[]
    if match_kind(p, TOK_LBRACE)
        chan_params = _parse_inline_channel_params!(p)
        # expect second arrow
        t2 = peek(p)
        if t2.kind == TOK_ARROW_BI || t2.kind == TOK_ARROW_R || t2.kind == TOK_ARROW_L
            advance!(p)
        end
    elseif match_kind(p, TOK_IDENT) && !(peek(p).text in SECTION_KEYWORDS) &&
           # check if this is a channel type name (followed by another arrow or { or ident that's a gate)
           _looks_like_channel_type(p)
        chan_type = parse_qualified_name!(p)
        # inline params after channel type name
        if match_kind(p, TOK_LBRACE)
            chan_params = _parse_inline_channel_params!(p)
        end
        # expect second arrow
        t2 = peek(p)
        if t2.kind == TOK_ARROW_BI || t2.kind == TOK_ARROW_R || t2.kind == TOK_ARROW_L
            advance!(p)
        end
    end

    # dest gate spec
    dest_mod, dest_mod_idx, dest_gate, dest_subg, dest_gate_idx, dest_pp = _parse_gate_spec!(p)

    # optional trailing "if condition"
    conds = NedCondition[]
    if skip_if_ident!(p, "if")
        cond_str = collect_expression!(p, Set([TOK_SEMI, TOK_RBRACE]))
        push!(conds, NedCondition(cond_str))
    end

    skip_if!(p, TOK_SEMI)

    conn = NedConnection(; src_module=src_mod, src_module_index=src_mod_idx,
                           src_gate=src_gate, src_gate_plusplus=src_pp,
                           src_gate_index=src_gate_idx, src_gate_subg=src_subg,
                           dest_module=dest_mod, dest_module_index=dest_mod_idx,
                           dest_gate=dest_gate, dest_gate_plusplus=dest_pp,
                           dest_gate_index=dest_gate_idx, dest_gate_subg=dest_subg,
                           name=nothing, type=chan_type,
                           is_bidirectional=is_bidir, is_forward_arrow=is_forward)
    for cp in chan_params
        push!(conn.params, Cell(cp))
    end
    for cd in conds
        push!(conn.conditions, Cell(cd))
    end
    return conn
end

# Heuristic: is the current IDENT a channel type name (as opposed to a destination module)?
# A channel type name is followed by <--> or --> or <-- or { (inline params).
function _looks_like_channel_type(p::Parser)
    saved = p.pos
    # skip the qualified name
    while p.pos <= length(p.tokens)
        t = p.tokens[p.pos]
        if t.kind == TOK_IDENT || t.kind == TOK_DOT
            p.pos += 1
        else
            break
        end
    end
    t = peek(p)
    result = t.kind == TOK_ARROW_BI || t.kind == TOK_ARROW_R || t.kind == TOK_ARROW_L || t.kind == TOK_LBRACE
    p.pos = saved
    return result
end

# Parse for-loop header: for var = expr .. expr
function parse_loop!(p::Parser)
    # "for" already consumed
    param_name = advance!(p).text
    expect!(p, TOK_EQ)
    from_val = collect_expression!(p, Set([TOK_DOTDOT]))
    expect!(p, TOK_DOTDOT)
    to_val = collect_expression!(p, Set([TOK_COMMA, TOK_LBRACE, TOK_SEMI]),
                                  extra_delim_idents=Set(["for"]))
    NedLoop(param_name; from=from_val, to=to_val)
end

# Parse a connection group: for ... , for ... { connection; ... }
function parse_connection_group!(p::Parser)
    loops = NedLoop[]
    conditions = NedCondition[]

    # parse for/if headers
    while true
        if skip_if_ident!(p, "for")
            push!(loops, parse_loop!(p))
            skip_if!(p, TOK_COMMA)
        elseif skip_if_ident!(p, "if")
            cond_str = collect_expression!(p, Set([TOK_LBRACE, TOK_COMMA]),
                                           extra_delim_idents=Set(["for"]))
            push!(conditions, NedCondition(cond_str))
            skip_if!(p, TOK_COMMA)
        else
            break
        end
    end

    connections = NedConnection[]
    expect!(p, TOK_LBRACE)
    while !match_kind(p, TOK_RBRACE) && !at_end(p)
        push!(connections, parse_connection!(p))
    end
    expect!(p, TOK_RBRACE)

    group = NedConnectionGroup()
    for l in loops; push!(group.loops, Cell(l)); end
    for c in conditions; push!(group.conditions, Cell(c)); end
    for c in connections; push!(group.connections, Cell(c)); end
    return group
end

# ── Block parsers (fill CellVectors) ─────────────────────────────────────

function _parse_params_into!(p::Parser, params::Vector{NedDocument})
    while !at_end(p)
        t = peek(p)
        # stop at section keywords or closing brace
        if t.kind == TOK_RBRACE
            break
        end
        if t.kind == TOK_IDENT && t.text in SECTION_KEYWORDS
            break
        end
        if t.kind == TOK_AT
            advance!(p)
            push!(params, parse_property!(p))
            skip_if!(p, TOK_SEMI)
        else
            push!(params, parse_param!(p))
        end
    end
end

function _parse_gates_into!(p::Parser, gates::Vector{NedDocument})
    while !at_end(p)
        t = peek(p)
        if t.kind == TOK_RBRACE
            break
        end
        if t.kind == TOK_IDENT && t.text in SECTION_KEYWORDS
            break
        end
        push!(gates, parse_gate!(p))
    end
end

function _parse_submodules_into!(p::Parser, submodules::Vector{NedDocument})
    while !at_end(p)
        t = peek(p)
        if t.kind == TOK_RBRACE
            break
        end
        if t.kind == TOK_IDENT && t.text in SECTION_KEYWORDS
            break
        end
        push!(submodules, parse_submodule!(p))
    end
end

function _parse_connections_into!(p::Parser, connections::Vector{NedDocument};
                                   allow_unconnected::Bool=false)
    while !at_end(p)
        t = peek(p)
        if t.kind == TOK_RBRACE
            break
        end
        if t.kind == TOK_IDENT && t.text in SECTION_KEYWORDS
            break
        end
        # for ... { ... } is a connection group
        if match_ident(p, "for")
            push!(connections, parse_connection_group!(p))
        else
            push!(connections, parse_connection!(p))
        end
    end
end

# ── Module/channel body parser ────────────────────────────────────────────

# Parse the { ... } body of a module or channel definition.
# Dispatches to section-specific parsers based on section keywords.
function _parse_body!(p::Parser, params, gates, types, submodules, connections;
                      has_gates=true, has_types=false, has_submodules=false,
                      has_connections=false)
    params_implicit = false
    connections_allow_unconnected = false

    expect!(p, TOK_LBRACE)
    while !match_kind(p, TOK_RBRACE) && !at_end(p)
        if skip_if_ident!(p, "parameters")
            expect!(p, TOK_COLON)
            _parse_params_into!(p, params)
        elseif has_gates && skip_if_ident!(p, "gates")
            expect!(p, TOK_COLON)
            _parse_gates_into!(p, gates)
        elseif has_types && skip_if_ident!(p, "types")
            expect!(p, TOK_COLON)
            _parse_types_into!(p, types)
        elseif has_submodules && skip_if_ident!(p, "submodules")
            expect!(p, TOK_COLON)
            _parse_submodules_into!(p, submodules)
        elseif has_connections && skip_if_ident!(p, "connections")
            allow_unc = false
            if skip_if_ident!(p, "allowunconnected")
                allow_unc = true
                connections_allow_unconnected = true
            end
            expect!(p, TOK_COLON)
            _parse_connections_into!(p, connections; allow_unconnected=allow_unc)
        elseif match_kind(p, TOK_AT)
            advance!(p)
            push!(params, parse_property!(p))
            skip_if!(p, TOK_SEMI)
            params_implicit = true
        else
            # bare param assignment (implicit parameters section)
            push!(params, parse_param!(p))
            params_implicit = true
        end
    end
    expect!(p, TOK_RBRACE)
    return (params_implicit, connections_allow_unconnected)
end

function _parse_types_into!(p::Parser, types::Vector{NedDocument})
    while !at_end(p)
        t = peek(p)
        if t.kind == TOK_RBRACE
            break
        end
        if t.kind == TOK_IDENT && t.text in SECTION_KEYWORDS
            break
        end
        if match_ident(p, "channel")
            push!(types, _parse_channel!(p))
        elseif match_ident(p, "channelinterface")
            push!(types, _parse_channel_interface!(p))
        elseif match_ident(p, "simple")
            push!(types, _parse_simple_module!(p))
        elseif match_ident(p, "module") || match_ident(p, "network")
            push!(types, _parse_compound_module!(p))
        elseif match_ident(p, "moduleinterface")
            push!(types, _parse_module_interface!(p))
        else
            error("NED parse error: unexpected '$(t.text)' in types block")
        end
    end
end

# ── Extends/like parsing ──────────────────────────────────────────────────

function _parse_extends_single!(p::Parser)
    expect_ident!(p, "extends")
    name = parse_qualified_name!(p)
    NedExtends(name)
end

function _parse_extends_list!(p::Parser)
    expect_ident!(p, "extends")
    result = NedExtends[]
    push!(result, NedExtends(parse_qualified_name!(p)))
    while skip_if!(p, TOK_COMMA)
        push!(result, NedExtends(parse_qualified_name!(p)))
    end
    result
end

function _parse_interface_names!(p::Parser)
    expect_ident!(p, "like")
    result = NedInterfaceName[]
    push!(result, NedInterfaceName(parse_qualified_name!(p)))
    while skip_if!(p, TOK_COMMA)
        push!(result, NedInterfaceName(parse_qualified_name!(p)))
    end
    result
end

# ── Top-level definition parsers ──────────────────────────────────────────

function _parse_simple_module!(p::Parser)
    expect_ident!(p, "simple")
    name = advance!(p).text

    ext = nothing
    ifaces = NedInterfaceName[]
    if match_ident(p, "extends")
        ext = _parse_extends_single!(p)
    end
    if match_ident(p, "like")
        ifaces = _parse_interface_names!(p)
    end

    params = NedDocument[]
    gates = NedDocument[]
    params_implicit, _ = _parse_body!(p, params, gates, NedDocument[], NedDocument[], NedDocument[];
                                       has_gates=true, has_types=false,
                                       has_submodules=false, has_connections=false)

    m = NedSimpleModule(name; extends=ext)
    for iface in ifaces; push!(m.interface_names, Cell(iface)); end
    for pr in params; push!(m.params, Cell(pr)); end
    for g in gates; push!(m.gates, Cell(g)); end
    return m
end

function _parse_compound_module!(p::Parser)
    # consume "module" or "network"
    advance!(p)
    name = advance!(p).text

    ext = nothing
    ifaces = NedInterfaceName[]
    if match_ident(p, "extends")
        ext = _parse_extends_single!(p)
    end
    if match_ident(p, "like")
        ifaces = _parse_interface_names!(p)
    end

    params = NedDocument[]
    gates = NedDocument[]
    types = NedDocument[]
    submodules = NedDocument[]
    connections = NedDocument[]
    params_implicit, conn_allow = _parse_body!(p, params, gates, types, submodules, connections;
                                                has_gates=true, has_types=true,
                                                has_submodules=true, has_connections=true)

    m = NedCompoundModule(name; extends=ext)
    for iface in ifaces; push!(m.interface_names, Cell(iface)); end
    for pr in params; push!(m.params, Cell(pr)); end
    for g in gates; push!(m.gates, Cell(g)); end
    for t in types; push!(m.types, Cell(t)); end
    for s in submodules; push!(m.submodules, Cell(s)); end
    for c in connections; push!(m.connections, Cell(c)); end
    return m
end

function _parse_module_interface!(p::Parser)
    expect_ident!(p, "moduleinterface")
    name = advance!(p).text

    ext_list = NedExtends[]
    if match_ident(p, "extends")
        ext_list = _parse_extends_list!(p)
    end

    params = NedDocument[]
    gates = NedDocument[]
    _parse_body!(p, params, gates, NedDocument[], NedDocument[], NedDocument[];
                 has_gates=true)

    m = NedModuleInterface(name)
    for e in ext_list; push!(m.extends_list, Cell(e)); end
    for pr in params; push!(m.params, Cell(pr)); end
    for g in gates; push!(m.gates, Cell(g)); end
    return m
end

function _parse_channel!(p::Parser)
    expect_ident!(p, "channel")
    name = advance!(p).text

    ext = nothing
    ifaces = NedInterfaceName[]
    if match_ident(p, "extends")
        ext = _parse_extends_single!(p)
    end
    if match_ident(p, "like")
        ifaces = _parse_interface_names!(p)
    end

    params = NedDocument[]
    _parse_body!(p, params, NedDocument[], NedDocument[], NedDocument[], NedDocument[];
                 has_gates=false)

    ch = NedChannel(name; extends=ext)
    for iface in ifaces; push!(ch.interface_names, Cell(iface)); end
    for pr in params; push!(ch.params, Cell(pr)); end
    return ch
end

function _parse_channel_interface!(p::Parser)
    expect_ident!(p, "channelinterface")
    name = advance!(p).text

    ext_list = NedExtends[]
    if match_ident(p, "extends")
        ext_list = _parse_extends_list!(p)
    end

    params = NedDocument[]
    _parse_body!(p, params, NedDocument[], NedDocument[], NedDocument[], NedDocument[];
                 has_gates=false)

    ci = NedChannelInterface(name)
    for e in ext_list; push!(ci.extends_list, Cell(e)); end
    for pr in params; push!(ci.params, Cell(pr)); end
    return ci
end

# ── File-level parser ────────────────────────────────────────────────────

function _parse_file!(p::Parser, filename::AbstractString)
    file = NedFile(filename)

    while !at_end(p)
        t = peek(p)

        if match_ident(p, "package")
            advance!(p)
            name = parse_qualified_name!(p)
            skip_if!(p, TOK_SEMI)
            push!(file, NedPackage(name))

        elseif match_ident(p, "import")
            advance!(p)
            spec = parse_qualified_name!(p)
            # handle wildcard: import a.b.*
            if match_kind(p, TOK_DOT)
                advance!(p)
                if match_kind(p, TOK_OP) && peek(p).text == "*"
                    spec = spec * "." * advance!(p).text
                end
            end
            skip_if!(p, TOK_SEMI)
            push!(file, NedImport(spec))

        elseif match_kind(p, TOK_AT)
            advance!(p) # @
            prop = parse_property!(p)
            skip_if!(p, TOK_SEMI)
            push!(file, prop)

        elseif match_ident(p, "simple")
            push!(file, _parse_simple_module!(p))

        elseif match_ident(p, "module") || match_ident(p, "network")
            push!(file, _parse_compound_module!(p))

        elseif match_ident(p, "moduleinterface")
            push!(file, _parse_module_interface!(p))

        elseif match_ident(p, "channel")
            push!(file, _parse_channel!(p))

        elseif match_ident(p, "channelinterface")
            push!(file, _parse_channel_interface!(p))

        else
            # skip unrecognised token
            advance!(p)
        end
    end

    return file
end

# ── Public API ────────────────────────────────────────────────────────────

"""
    nedparse(text::AbstractString; filename::AbstractString="") -> NedFile

Parse an OMNeT++ NED source string into a `NedFile` document tree.

Handles package declarations, imports, file-level properties, simple modules,
compound modules (including `network`), module interfaces, channels, and
channel interfaces. Expressions in parameter values, vector sizes, and
conditions are captured as opaque strings.
"""
function nedparse(text::AbstractString; filename::AbstractString="")
    tokens = tokenize(text)
    p = Parser(tokens)
    _parse_file!(p, filename)
end

"""
    nedparse_file(path::AbstractString) -> NedFile

Read a `.ned` file from disk and parse it into a `NedFile` document tree.
"""
function nedparse_file(path::AbstractString)
    nedparse(read(path, String); filename=path)
end

end # module
