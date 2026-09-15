# Fragment of `MathModule` — a reader of the linear form.
#
# `MathToSyntax` prints a formula as one line, and this reads the line back
# into a tree. The printer is the grammar: a line the printer writes reads
# back to a tree that prints the same line. Where the line is ambiguous the
# reader decides, and the decisions are in the guide: `/` with no space around
# it is a fraction and ` / ` a division; a letter is a variable, a word is
# text, and a name directly before `(` is a function; a space is
# juxtaposition; a script takes one atom without braces; every `(…)` reads as
# a `MathParenthesized`, the printer's own parentheses included.
#
# The reader never evaluates. It builds documents and nothing else.

# ── Tokens ───────────────────────────────────────────────────────────────────

struct _MathToken
    kind::Symbol          # :number :name :word :glyph :command :operator :open :close :bar :comma :semicolon :insertion :end
    text::String
    space_before::Bool
    position::Int         # 1-based, in characters
end

# The glyph of every named symbol, read back to its name.
const _MATH_GLYPH_NAMES = Dict{String,Symbol}(glyph => name for (name, glyph) in _MATH_SYMBOLS)

# The linear name of every large operator, read back to its operator.
const _MATH_BIG_OPERATOR_NAMES =
    Dict{String,Symbol}(names[2][2:end] => op for (op, names) in _MATH_BIG_OPERATORS)

# The linear text of every operator, read back to its symbol; the backslash
# names without their backslash, the others as they are.
const _MATH_OPERATOR_NAMES = let table = Dict{String,Symbol}()
    for (op, entry) in _MATH_OPERATORS
        text = entry[1]
        table[startswith(text, "\\") ? text[2:end] : strip(text)] = op
    end
    table
end

# The delimiter pairs, by their opening and their closing character.
const _MATH_OPENERS = Dict{String,Symbol}(pair[1] => kind for (kind, pair) in _MATH_DELIMITERS
                                          if !isempty(pair[1]) && pair[1] != pair[2])
const _MATH_CLOSERS = Dict{String,Symbol}(pair[2] => kind for (kind, pair) in _MATH_DELIMITERS
                                          if !isempty(pair[2]) && pair[1] != pair[2])
const _MATH_BARS = Dict{String,Symbol}(pair[1] => kind for (kind, pair) in _MATH_DELIMITERS
                                       if !isempty(pair[1]) && pair[1] == pair[2])

const _MATH_SPACE_COMMANDS = Dict{String,Symbol}("," => :thin, ":" => :medium, ";" => :thick, "quad" => :quad)
const _MATH_ACCENTS = Set{String}(["bar", "hat", "vec", "dot", "ddot", "tilde"])

_is_name_start(c::Char) = ('a' <= c <= 'z') || ('A' <= c <= 'Z')
_is_name_char(c::Char) = _is_name_start(c) || isdigit(c)

function _tokenize_math(text::AbstractString)
    chars = collect(String(text))
    tokens = _MathToken[]
    i = 1
    space = false
    n = length(chars)
    while i <= n
        c = chars[i]
        if isspace(c)
            space = true
            i += 1
            continue
        end
        start = i
        if isdigit(c) || (c == '.' && i < n && isdigit(chars[i + 1]))
            while i <= n && (isdigit(chars[i]) || chars[i] == '.')
                i += 1
            end
            push!(tokens, _MathToken(:number, String(chars[start:i - 1]), space, start))
        elseif _is_name_start(c)
            while i <= n && _is_name_char(chars[i])
                i += 1
            end
            word = String(chars[start:i - 1])
            push!(tokens, _MathToken(length(word) == 1 ? :name : :word, word, space, start))
        elseif c == '\\'
            i += 1
            if i <= n && _is_name_start(chars[i])
                while i <= n && _is_name_start(chars[i])
                    i += 1
                end
            elseif i <= n
                i += 1
            end
            push!(tokens, _MathToken(:command, String(chars[start + 1:i - 1]), space, start))
        elseif c == '⌷'
            push!(tokens, _MathToken(:insertion, "⌷", space, start)); i += 1
        elseif haskey(_MATH_GLYPH_NAMES, string(c))
            push!(tokens, _MathToken(:glyph, string(c), space, start)); i += 1
        elseif haskey(_MATH_BARS, string(c))
            push!(tokens, _MathToken(:bar, string(c), space, start)); i += 1
        elseif haskey(_MATH_OPENERS, string(c)) || c == '{'
            push!(tokens, _MathToken(:open, string(c), space, start)); i += 1
        elseif haskey(_MATH_CLOSERS, string(c)) || c == '}'
            push!(tokens, _MathToken(:close, string(c), space, start)); i += 1
        elseif c == ','
            push!(tokens, _MathToken(:comma, ",", space, start)); i += 1
        elseif c == ';'
            push!(tokens, _MathToken(:semicolon, ";", space, start)); i += 1
        elseif c in ('+', '-', '*', '/', '=', '!', '<', '>', '^', '_')
            two = i < n ? String(chars[i:i + 1]) : ""
            if two in ("<=", ">=", "!=", "->")
                push!(tokens, _MathToken(:operator, two, space, start)); i += 2
            else
                push!(tokens, _MathToken(:operator, string(c), space, start)); i += 1
            end
        else
            error("math: unexpected character ", repr(c), " at position ", start)
        end
        space = false
    end
    push!(tokens, _MathToken(:end, "", space, n + 1))
    tokens
end

# ── The cursor ───────────────────────────────────────────────────────────────

mutable struct _MathCursor
    tokens::Vector{_MathToken}
    index::Int
    stop_words::Set{String}     # words that end a row: `if` and `otherwise` in a case list
    bars::Vector{String}        # the bar delimiters open around the cursor, innermost last
end

_peek(p::_MathCursor) = p.tokens[p.index]
_peek(p::_MathCursor, ahead::Int) = p.tokens[min(p.index + ahead, length(p.tokens))]
_next!(p::_MathCursor) = (token = p.tokens[p.index]; p.index += 1; token)
_at(p::_MathCursor, kind::Symbol, text::AbstractString) =
    (token = _peek(p); token.kind === kind && token.text == text)
_at(p::_MathCursor, kind::Symbol) = _peek(p).kind === kind

function _expect!(p::_MathCursor, kind::Symbol, text::AbstractString)
    token = _next!(p)
    (token.kind === kind && token.text == text) ||
        error("math: expected ", repr(text), " at position ", token.position, ", got ",
              token.kind === :end ? "the end of the line" : repr(token.text))
    token
end

_refuse(p::_MathCursor, what::AbstractString) = begin
    token = _peek(p)
    error("math: expected ", what, " at position ", token.position, ", got ",
          token.kind === :end ? "the end of the line" : repr(token.text))
end

# ── The grammar, loosest first ───────────────────────────────────────────────

"""
    parse_math(text) -> MathDocument

The tree the one-line linear form of a formula stands for: what
`MathToSyntax` prints, read back. `p_{block} = ((1 - ρ) ρ^{n})/(1 - ρ^{n + 1})`
reads to an assignment of a fraction. A script takes one atom without braces
too, `ρ^n`, and a symbol reads as its glyph or as its name, `ρ` or `\\rho`.
An error names the position of what the reader could not read.
"""
function parse_math(text::AbstractString)
    p = _MathCursor(_tokenize_math(text), 1, Set{String}(), String[])
    _at(p, :end) && error("math: the line is empty")
    result = _parse_assignment(p)
    _at(p, :end) || _refuse(p, "the end of the line")
    result
end

function _parse_assignment(p::_MathCursor)
    left = _parse_relation(p)
    _at(p, :operator, "=") || return left
    _next!(p)
    right = _parse_relation(p)
    _at(p, :operator, "=") && error("math: one assignment per line, at position ", _peek(p).position)
    MathAssignment(left, right)
end

const _MATH_RELATIONS = Set{Symbol}([:ne, :lt, :gt, :le, :ge, :approx, :equiv, :sim, :in, :subset, :to, :propto])
const _MATH_PRODUCTS = Set{Symbol}([:*, :times, :cdot, :divide])

# The operator a token stands for at the relation or the product level, or nothing.
function _binary_operator(token::_MathToken, level::Set{Symbol})
    token.kind === :operator || token.kind === :command || return nothing
    op = get(_MATH_OPERATOR_NAMES, token.text, nothing)
    op === nothing && return nothing
    op in level ? op : nothing
end

function _parse_relation(p::_MathCursor)
    left = _parse_additive(p)
    while (op = _binary_operator(_peek(p), _MATH_RELATIONS)) !== nothing
        _next!(p)
        left = MathBinaryOperation(op, left, _parse_additive(p))
    end
    left
end

function _parse_additive(p::_MathCursor)
    left = _parse_product(p)
    while _at(p, :operator, "+") || _at(p, :operator, "-")
        op = Symbol(_next!(p).text)
        left = MathBinaryOperation(op, left, _parse_product(p))
    end
    left
end

# ` / ` with a space before it is the binary division; `/` without one is a
# fraction, read below.
function _parse_product(p::_MathCursor)
    left = _parse_row(p)
    while true
        token = _peek(p)
        if token.kind === :operator && token.text == "/" && token.space_before
            _next!(p)
            left = MathBinaryOperation(:/, left, _parse_row(p))
        elseif (op = _binary_operator(token, _MATH_PRODUCTS)) !== nothing
            _next!(p)
            left = MathBinaryOperation(op, left, _parse_row(p))
        else
            return left
        end
    end
end

# Juxtaposition: operands set apart by a space, with no operator between them.
function _parse_row(p::_MathCursor)
    first = _parse_fraction(p)
    elements = Any[first]
    while _starts_operand(p, _peek(p))
        push!(elements, _parse_fraction(p))
    end
    length(elements) == 1 ? first : MathRow(elements)
end

function _starts_operand(p::_MathCursor, token::_MathToken)
    kind = token.kind
    kind in (:number, :name, :glyph, :open, :insertion) && return true
    # A bar closes the bar it stands in; any other bar opens one.
    kind === :bar && return isempty(p.bars) || p.bars[end] != token.text
    kind === :word && return !(token.text in p.stop_words)
    if kind === :command
        text = token.text
        haskey(_MATH_SPACE_COMMANDS, text) && return true
        haskey(_MATH_OPERATOR_NAMES, text) && return false
        return true
    end
    false
end

function _parse_fraction(p::_MathCursor)
    left = _parse_prefix(p)
    while _at(p, :operator, "/") && !_peek(p).space_before
        _next!(p)
        left = MathFraction(left, _parse_prefix(p))
    end
    left
end

function _parse_prefix(p::_MathCursor)
    if _at(p, :operator, "-")
        following = _peek(p, 1)
        if following.kind === :number && !following.space_before
            _next!(p)
            return _negative_number(_next!(p))
        end
        _next!(p)
        return MathUnaryOperation(:-, _parse_prefix(p), false)
    end
    if _at(p, :command, "neg")
        _next!(p)
        return MathUnaryOperation(:not, _parse_prefix(p), false)
    end
    _parse_postfix(p)
end

function _parse_postfix(p::_MathCursor)
    base = _parse_scripted(p)
    while _at(p, :operator, "!") && !_peek(p).space_before
        _next!(p)
        base = MathUnaryOperation(:factorial, base, true)
    end
    base
end

function _parse_scripted(p::_MathCursor)
    base = _parse_atom(p)
    base isa MathFunction && base.base !== nothing && return _parse_superscript(p, base)
    subscript = nothing
    superscript = nothing
    if _at(p, :operator, "_")
        _next!(p)
        subscript = _parse_script(p)
    end
    if _at(p, :operator, "^")
        _next!(p)
        superscript = _parse_script(p)
    end
    (subscript === nothing && superscript === nothing) && return base
    MathScript(base; subscript = subscript, superscript = superscript)
end

# A function with a base, `log_{2}(x)`, has spent its subscript; a superscript may follow.
function _parse_superscript(p::_MathCursor, base)
    _at(p, :operator, "^") || return base
    _next!(p)
    MathScript(base; superscript = _parse_script(p))
end

# `{…}` holds any expression; without braces a script is one atom.
function _parse_script(p::_MathCursor)
    if _at(p, :open, "{")
        _next!(p)
        content = _parse_assignment(p)
        _expect!(p, :close, "}")
        return content
    end
    _parse_atom(p)
end

function _parse_atom(p::_MathCursor)
    token = _peek(p)
    kind = token.kind
    if kind === :number
        _next!(p)
        return _number(token)
    elseif kind === :name
        _next!(p)
        _at(p, :open, "(") && !_peek(p).space_before &&
            return token.text == "d" ? _parse_derivative(p, :total, 1) : _parse_call(p, token.text, nothing)
        if token.text == "d" && _at(p, :operator, "^") && !_peek(p).space_before && _peek(p, 1).kind === :number
            _next!(p)
            order = parse(Int, _next!(p).text)
            return _parse_derivative(p, :total, order)
        end
        return MathVariable(token.text)
    elseif kind === :word
        _next!(p)
        return _parse_word(p, token)
    elseif kind === :glyph
        _next!(p)
        return MathSymbol(_MATH_GLYPH_NAMES[token.text])
    elseif kind === :command
        _next!(p)
        return _parse_command(p, token)
    elseif kind === :open
        _next!(p)
        token.text == "{" && error("math: a brace opens a script only, at position ", token.position)
        delimiter = _MATH_OPENERS[token.text]
        content = _parse_assignment(p)
        closer = _MATH_DELIMITERS[delimiter][2]
        _expect!(p, :close, closer)
        return MathParenthesized(content, delimiter)
    elseif kind === :bar
        _next!(p)
        delimiter = _MATH_BARS[token.text]
        push!(p.bars, token.text)
        content = try
            _parse_assignment(p)
        finally
            pop!(p.bars)
        end
        _expect!(p, :bar, token.text)
        return MathParenthesized(content, delimiter)
    elseif kind === :insertion
        _next!(p)
        return MathInsertion()
    end
    _refuse(p, "an operand")
end

function _number(token::_MathToken)
    text = token.text
    value = occursin('.', text) ? tryparse(Float64, text) : tryparse(Int, text)
    value === nothing && error("math: not a number: ", repr(text), " at position ", token.position)
    PrimitiveNumber(value)
end

_negative_number(token::_MathToken) = PrimitiveNumber(-_number(token).value)

# A word: a function when `(` follows it directly, with a base when `_{…}(`
# does; a differential when it is `d` and one lower-case letter; text
# otherwise.
function _parse_word(p::_MathCursor, token::_MathToken)
    word = token.text
    _at(p, :open, "(") && !_peek(p).space_before && return _parse_call(p, word, nothing)
    if _at(p, :operator, "_") && _peek(p, 1).kind === :open && _peek(p, 1).text == "{"
        index = p.index
        _next!(p)
        base = _parse_script(p)
        _at(p, :open, "(") && !_peek(p).space_before && return _parse_call(p, word, base)
        p.index = index
    end
    length(word) == 2 && word[1] == 'd' && islowercase(word[2]) &&
        return MathDifferential(MathVariable(string(word[2])), :total)
    MathText(word)
end

function _parse_call(p::_MathCursor, name::AbstractString, base)
    _expect!(p, :open, "(")
    argument = _parse_assignment(p)
    _expect!(p, :close, ")")
    MathFunction(String(name), argument; base = base)
end

# `d(Q)/d(t)`, `\\partial^2(P)/\\partial(t)^2`: the body, the sign again, the
# variable, and the order on both sides when it is not one.
function _parse_derivative(p::_MathCursor, kind::Symbol, order::Int)
    _expect!(p, :open, "(")
    body = _parse_assignment(p)
    _expect!(p, :close, ")")
    _expect!(p, :operator, "/")
    sign = _next!(p)
    (kind === :total && sign.kind === :name && sign.text == "d") ||
        (kind === :partial && sign.kind === :command && sign.text == "partial") ||
        error("math: a derivative names its variable after its sign, at position ", sign.position)
    _expect!(p, :open, "(")
    variable = _parse_assignment(p)
    _expect!(p, :close, ")")
    if order != 1
        _expect!(p, :operator, "^")
        again = _next!(p)
        again.kind === :number && parse(Int, again.text) == order ||
            error("math: the order of a derivative is the same on both sides, at position ", again.position)
    end
    MathDerivative(body, variable, order, kind)
end

function _parse_command(p::_MathCursor, token::_MathToken)
    name = token.text
    haskey(_MATH_SPACE_COMMANDS, name) && return MathSpace(_MATH_SPACE_COMMANDS[name])
    if name == "partial"
        if _at(p, :open, "(") && !_peek(p).space_before
            return _parse_derivative(p, :partial, 1)
        elseif _at(p, :operator, "^") && !_peek(p).space_before && _peek(p, 1).kind === :number
            _next!(p)
            order = parse(Int, _next!(p).text)
            return _parse_derivative(p, :partial, order)
        end
        return MathDifferential(_parse_atom(p), :partial)
    end
    if haskey(_MATH_BIG_OPERATOR_NAMES, name)
        op = _MATH_BIG_OPERATOR_NAMES[name]
        lower = nothing
        upper = nothing
        if _at(p, :operator, "_")
            _next!(p)
            lower = _parse_script(p)
        end
        if _at(p, :operator, "^")
            _next!(p)
            upper = _parse_script(p)
        end
        body = _parse_fraction(p)
        return MathBigOperator(op, body; lower = lower, upper = upper)
    end
    if name == "sqrt"
        index = nothing
        if _at(p, :open, "[")
            _next!(p)
            index = _parse_assignment(p)
            _expect!(p, :close, "]")
        end
        _expect!(p, :open, "{")
        radicand = _parse_assignment(p)
        _expect!(p, :close, "}")
        return MathRadical(radicand, index)
    end
    if name in _MATH_ACCENTS
        _expect!(p, :open, "{")
        base = _parse_assignment(p)
        _expect!(p, :close, "}")
        return MathAccent(base, Symbol(name))
    end
    if name == "matrix"
        _expect!(p, :open, "[")
        columns = _next!(p)
        columns.kind === :number || error("math: a matrix names its column count, at position ", columns.position)
        _expect!(p, :close, "]")
        _expect!(p, :open, "{")
        elements = Any[]
        while !_at(p, :close, "}")
            push!(elements, _parse_assignment(p))
            _at(p, :comma) && _next!(p)
        end
        _expect!(p, :close, "}")
        return MathMatrix(elements, parse(Int, columns.text))
    end
    if name == "cases"
        _expect!(p, :open, "{")
        cases = Any[]
        saved = p.stop_words
        p.stop_words = Set{String}(["if", "otherwise"])
        try
            while !_at(p, :close, "}")
                value = _parse_assignment(p)
                if _at(p, :word, "otherwise")
                    _next!(p)
                    push!(cases, MathCase(value, nothing))
                elseif _at(p, :word, "if")
                    _next!(p)
                    push!(cases, MathCase(value, _parse_assignment(p)))
                else
                    _refuse(p, "`if` or `otherwise` after a case")
                end
                _at(p, :semicolon) && _next!(p)
            end
        finally
            p.stop_words = saved
        end
        _expect!(p, :close, "}")
        return MathCases(cases)
    end
    haskey(_MATH_SYMBOLS, Symbol(name)) && return MathSymbol(Symbol(name))
    haskey(_MATH_OPERATOR_NAMES, name) &&
        error("math: the operator \\", name, " needs an operand before it, at position ", token.position)
    error("math: unknown command \\", name, " at position ", token.position)
end
