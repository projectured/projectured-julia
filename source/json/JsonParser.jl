"""
    JsonParserModule

A small recursive-descent JSON parser. Converts JSON source text into a
`JsonDocument` tree from `JsonModule`.

Provides:
- `parse_json(text)` — parse a JSON string into a `JsonDocument`
- `parse_json_file(path)` — read and parse a `.json` file from disk

Deliberately minimal (objects, arrays, strings, numbers, `true`/`false`/`null`,
the common backslash escapes including `\\uXXXX`). It is not a conformance-grade
parser — it is enough to turn typed JSON in the editor into a real document.
Anything malformed raises an error rather than guessing.
"""
module JsonParserModule

import ..JsonModule: JsonDocument, JsonNull, JsonBool, JsonNumber, JsonString,
                     JsonArray, JsonObject

export parse_json, parse_json_file

# ── Cursor over the source (1-based char vector — simple, not the fastest) ─────

mutable struct _Cur
    cs::Vector{Char}
    i::Int
end

_eof(p)   = p.i > length(p.cs)
_peek(p)  = _eof(p) ? '\0' : p.cs[p.i]
_next!(p) = (_eof(p) && error("JSON: unexpected end of input"); c = p.cs[p.i]; p.i += 1; c)

function _skipws!(p)
    while !_eof(p) && isspace(_peek(p))
        p.i += 1
    end
end

function _expect!(p, ch::Char)
    c = _next!(p)
    c == ch || error("JSON: expected '$ch' but got '$c' at position $(p.i - 1)")
end

function _matches!(p, word::AbstractString)
    n = length(word)
    p.i + n - 1 <= length(p.cs) && String(p.cs[p.i:p.i + n - 1]) == word || return false
    p.i += n
    true
end

# ── Grammar ────────────────────────────────────────────────────────────────────

function _value!(p)
    _skipws!(p)
    c = _peek(p)
    c == '{'                      && return _object!(p)
    c == '['                      && return _array!(p)
    c == '"'                      && return JsonString(_string!(p))
    (c == 't' || c == 'f')        && return _bool!(p)
    c == 'n'                      && return _null!(p)
    (c == '-' || isdigit(c))      && return _number!(p)
    error("JSON: unexpected character '$c' at position $(p.i)")
end

function _string!(p)
    _expect!(p, '"')
    io = IOBuffer()
    while true
        c = _next!(p)
        c == '"' && break
        if c == '\\'
            e = _next!(p)
            e == 'n'  ? print(io, '\n') :
            e == 't'  ? print(io, '\t') :
            e == 'r'  ? print(io, '\r') :
            e == 'b'  ? print(io, '\b') :
            e == 'f'  ? print(io, '\f') :
            e == '/'  ? print(io, '/')  :
            e == '\\' ? print(io, '\\') :
            e == '"'  ? print(io, '"')  :
            e == 'u'  ? print(io, _unicode!(p)) :
                        print(io, e)
        else
            print(io, c)
        end
    end
    String(take!(io))
end

function _unicode!(p)
    hex = String([_next!(p) for _ in 1:4])
    Char(parse(UInt16, hex; base = 16))
end

function _number!(p)
    start = p.i
    _peek(p) == '-' && (p.i += 1)
    while !_eof(p) && (isdigit(_peek(p)) || _peek(p) in ('.', 'e', 'E', '+', '-'))
        p.i += 1
    end
    str = String(p.cs[start:p.i - 1])
    v = something(tryparse(Int, str), tryparse(Float64, str), Some(nothing))
    v === nothing && error("JSON: invalid number '$str'")
    JsonNumber(v)
end

_bool!(p) = _matches!(p, "true")  ? JsonBool(true)  :
            _matches!(p, "false") ? JsonBool(false) :
            error("JSON: invalid literal at position $(p.i)")

_null!(p) = _matches!(p, "null") ? JsonNull() :
            error("JSON: invalid literal at position $(p.i)")

function _array!(p)
    _expect!(p, '[')
    items = JsonDocument[]
    _skipws!(p)
    _peek(p) == ']' && (p.i += 1; return JsonArray(items))
    while true
        push!(items, _value!(p))
        _skipws!(p)
        c = _next!(p)
        c == ',' && continue
        c == ']' && break
        error("JSON: expected ',' or ']' but got '$c' at position $(p.i - 1)")
    end
    JsonArray(items)
end

function _object!(p)
    _expect!(p, '{')
    pairs = Pair{String,JsonDocument}[]
    _skipws!(p)
    _peek(p) == '}' && (p.i += 1; return JsonObject())
    while true
        _skipws!(p)
        key = _string!(p)
        _skipws!(p)
        _expect!(p, ':')
        push!(pairs, key => _value!(p))
        _skipws!(p)
        c = _next!(p)
        c == ',' && continue
        c == '}' && break
        error("JSON: expected ',' or '}' but got '$c' at position $(p.i - 1)")
    end
    JsonObject(pairs...)
end

# ── Entry points ───────────────────────────────────────────────────────────────

"""
    parse_json(text) -> JsonDocument

Parse a JSON string into a `JsonDocument`. Errors on malformed input or trailing
characters.
"""
function parse_json(text::AbstractString)
    p = _Cur(collect(String(text)), 1)
    value = _value!(p)
    _skipws!(p)
    _eof(p) || error("JSON: trailing characters at position $(p.i)")
    value
end

"""
    parse_json_file(path) -> JsonDocument

Read and parse a `.json` file from disk.
"""
parse_json_file(path::AbstractString) = parse_json(read(path, String))

end # module
