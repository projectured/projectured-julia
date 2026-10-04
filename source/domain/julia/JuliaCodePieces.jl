# Fragment of `JuliaModule`.
#
# The colors of Julia code in a field of code, such as the expression bar of a
# data frame view: a field whose language is `:julia` asks `compute_code_pieces`,
# and this slice answers with the tokens of the text in the colors of the text
# roles of `JuliaTheme`, as the Julia domain draws them. The text is read as
# tokens, not parsed, so a text that does not parse yet, as a person types it,
# has its colors too.

# A token of Julia code: a comment, a string, a character, an operator, a
# symbol, a number or a word, in the order that they are tried.
const _JULIA_CODE_TOKEN = r"(?<comment>#.*)|(?<string>\"(?:[^\"\\]|\\.)*\"?)|(?<char>'(?:[^'\\]|\\.)')|(?<operator>::|[&|<>=!+\-*/^%÷∈≤≥≠]+)|(?<symbol>:[A-Za-z_][A-Za-z0-9_!]*)|(?<number>\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?<word>[A-Za-z_][A-Za-z0-9_!]*)"

# The words that the keyword role colors: the keywords, `true`, `false` and
# `nothing`.
const _JULIA_CODE_KEYWORDS = Set(["if", "else", "elseif", "end", "for", "while", "function", "return",
                                  "let", "begin", "do", "try", "catch", "finally", "where", "in", "isa",
                                  "true", "false", "nothing"])

# The text role of `JuliaTheme` that colors a token, or `nothing` for a name,
# which keeps the color of the field.
function _get_julia_code_role(token::RegexMatch)
    token[:comment] === nothing || return :comment_text
    (token[:string] === nothing && token[:char] === nothing && token[:number] === nothing) ||
        return :literal_text
    token[:operator] === nothing || return :operator_text
    token[:symbol] === nothing || return :symbol_text
    token.match in _JULIA_CODE_KEYWORDS && return :keyword_text
    nothing
end

# `appearance` gives its `JuliaTheme`, which a person edits, so a read of a color
# follows an edit; with no appearance, or no Julia theme in it, the default theme
# gives the colors. A color does not scale, so the theme need not be scaled.
function compute_code_pieces(::Val{:julia}, text::AbstractString, appearance)
    theme = appearance === nothing ? nothing : get_theme(appearance, JuliaTheme)
    theme === nothing && (theme = get_theme_defaults(JuliaTheme))
    function get_color(token)
        role = _get_julia_code_role(token)
        role === nothing ? nothing : getproperty(theme, role).color
    end
    pieces = Tuple{Int,Any}[]
    position = 1
    for token in eachmatch(_JULIA_CODE_TOKEN, text)
        token.offset > position &&
            push!(pieces, (length(text, position, prevind(text, token.offset)), nothing))
        push!(pieces, (length(token.match), get_color(token)))
        position = token.offset + ncodeunits(token.match)
    end
    position <= ncodeunits(text) && push!(pieces, (length(text, position, lastindex(text)), nothing))
    isempty(pieces) && push!(pieces, (0, nothing))
    pieces
end
