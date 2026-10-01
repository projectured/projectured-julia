# Fragment of `JuliaModule`.
#
# The colors of Julia code in a field of code, such as the expression bar of a
# data frame view: a field whose language is `:julia` asks `compute_code_pieces`,
# and this slice answers with the tokens of the text in the colors of the Julia
# domain. The text is read as tokens, not parsed, so a text that does not parse
# yet, as a person types it, has its colors too.

# A token of Julia code: a comment, a string, a character, an operator, a
# symbol, a number or a word, in the order that they are tried.
const _JULIA_CODE_TOKEN = r"(?<comment>#.*)|(?<string>\"(?:[^\"\\]|\\.)*\"?)|(?<char>'(?:[^'\\]|\\.)')|(?<operator>::|[&|<>=!+\-*/^%÷∈≤≥≠]+)|(?<symbol>:[A-Za-z_][A-Za-z0-9_!]*)|(?<number>\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?<word>[A-Za-z_][A-Za-z0-9_!]*)"

const _JULIA_CODE_KEYWORDS = Set(["if", "else", "elseif", "end", "for", "while", "function", "return",
                                  "let", "begin", "do", "try", "catch", "finally", "where", "in", "isa"])

const _JULIA_CODE_LITERALS = Set(["true", "false", "nothing", "missing"])

# The color of a token, or `nothing` for a name, which keeps the color of the
# field.
function _get_julia_code_color(token::RegexMatch)
    token[:comment] === nothing || return color_solarized_gray
    (token[:string] === nothing && token[:char] === nothing && token[:number] === nothing) ||
        return color_solarized_green
    token[:operator] === nothing || return color_solarized_cyan
    token[:symbol] === nothing || return color_solarized_violet
    word = token.match
    word in _JULIA_CODE_KEYWORDS && return color_solarized_magenta
    word in _JULIA_CODE_LITERALS && return color_solarized_green
    nothing
end

function compute_code_pieces(::Val{:julia}, text::AbstractString)
    pieces = Tuple{Int,Any}[]
    position = 1
    for token in eachmatch(_JULIA_CODE_TOKEN, text)
        token.offset > position &&
            push!(pieces, (length(text, position, prevind(text, token.offset)), nothing))
        push!(pieces, (length(token.match), _get_julia_code_color(token)))
        position = token.offset + ncodeunits(token.match)
    end
    position <= ncodeunits(text) && push!(pieces, (length(text, position, lastindex(text)), nothing))
    isempty(pieces) && push!(pieces, (0, nothing))
    pieces
end
