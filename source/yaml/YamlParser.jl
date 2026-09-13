"""
    YamlParserModule

A small YAML parser. Converts YAML source text into a `YamlDocument` tree from
`YamlModule`.

Provides:
- `parse_yaml(text)` — parse a YAML string into a `YamlDocument`
- `parse_yaml_file(path)` — read and parse a `.yaml`/`.yml` file from disk

Deliberately minimal — enough to turn typed/loaded YAML into a real document, not
a conformance-grade parser. It supports:

- **Block mappings** (`key: value`, nested by indentation) and **block sequences**
  (`- item`, including sequences of mappings).
- **Flow collections** `[a, b]` and `{a: 1}` (YAML is a JSON superset).
- **Scalars**: plain, single-/double-quoted strings, integers, floats,
  `true`/`false`, and `null`/`~`.
- Line `# comments` and a single leading `---` document marker.

Not supported (raises or misreads rather than guessing): multiple documents,
anchors/aliases/tags, block scalars (`|`, `>`), and inline nested block sequences
(`- - x`). Indentation must use spaces.
"""
module YamlParserModule

import ..YamlModule: YamlDocument, YamlNull, YamlBool, YamlNumber, YamlString,
                     YamlSequence, YamlMapping

export parse_yaml, parse_yaml_file

# ── Line preprocessing ─────────────────────────────────────────────────────────

# Strip a trailing `# comment` (one preceded by whitespace or at line start, and
# not inside a quoted scalar). Quotes are treated opaquely so a `#` inside them
# stays literal.
function _strip_comment(line::AbstractString)
    cs = collect(line)
    inq = false; qc = ' '
    for (i, c) in enumerate(cs)
        if inq
            c == qc && (inq = false)
        elseif c == '"' || c == '\''
            inq = true; qc = c
        elseif c == '#' && (i == 1 || cs[i-1] == ' ' || cs[i-1] == '\t')
            return String(cs[1:i-1])
        end
    end
    return String(line)
end

# Split into non-blank logical lines as `(indent, text)`, dropping comments,
# blank lines, and `---`/`...` document markers. `indent` is the leading-space
# count; `text` is the trimmed content.
function _logical_lines(text::AbstractString)
    out = Tuple{Int,String}[]
    for raw in split(text, '\n')
        line = _strip_comment(raw)
        t = strip(line)
        (isempty(t) || t == "---" || t == "...") && continue
        indent = 0
        for c in line
            c == ' ' ? (indent += 1) : break
        end
        push!(out, (indent, String(t)))
    end
    out
end

mutable struct _Block
    lines::Vector{Tuple{Int,String}}
    i::Int
end

_at_end(p::_Block) = p.i > length(p.lines)
_cur(p::_Block)    = p.lines[p.i]

# ── Block grammar ──────────────────────────────────────────────────────────────

# Parse the block starting at the current line, all of whose siblings share
# `indent`. Dispatches on the first line's shape: `-` ⇒ sequence, a top-level
# `key:` ⇒ mapping, otherwise a lone scalar / flow value.
function _block(p::_Block, indent::Int)
    _at_end(p) && return YamlNull()
    _, text = _cur(p)
    if _is_dash(text)
        return _sequence(p, indent)
    elseif _find_colon(text) !== nothing
        return _mapping(p, indent)
    else
        p.i += 1
        return _scalar_or_flow(text)
    end
end

_is_dash(text) = text == "-" || (startswith(text, "-") && length(text) >= 2 && text[2] == ' ')

function _mapping(p::_Block, indent::Int)
    pairs = Pair{String,YamlDocument}[]
    while !_at_end(p)
        ind, text = _cur(p)
        ind == indent || break
        ci = _find_colon(text)
        ci === nothing && break
        key = _parse_key(strip(text[1:ci-1]))
        valtext = strip(text[nextind(text, ci):end])
        p.i += 1
        if isempty(valtext)
            # nested block on deeper lines, else an explicit null
            val = (!_at_end(p) && _cur(p)[1] > indent) ? _block(p, _cur(p)[1]) : YamlNull()
        else
            val = _scalar_or_flow(valtext)
        end
        push!(pairs, key => val)
    end
    isempty(pairs) ? YamlMapping() : YamlMapping(pairs...)
end

function _sequence(p::_Block, indent::Int)
    items = YamlDocument[]
    while !_at_end(p)
        ind, text = _cur(p)
        (ind == indent && _is_dash(text)) || break
        afterdash = length(text) >= 2 ? text[2:end] : ""
        nsp = length(afterdash) - length(lstrip(afterdash))
        restcol = indent + 1 + nsp
        rest = String(strip(afterdash))
        p.i += 1
        if isempty(rest)
            # `- ` with a nested block on deeper lines, else null
            push!(items, (!_at_end(p) && _cur(p)[1] > indent) ? _block(p, _cur(p)[1]) : YamlNull())
        elseif _find_colon(rest) !== nothing
            # `- key: value` (a mapping item): re-seat the item content as a virtual
            # line at its own column and parse a mapping there, so deeper aligned keys
            # join the same item.
            p.i -= 1
            p.lines[p.i] = (restcol, rest)
            push!(items, _mapping(p, restcol))
        else
            push!(items, _scalar_or_flow(rest))
        end
    end
    YamlSequence(items)
end

# The index of the top-level `key:` colon (followed by a space or end-of-line and
# outside quotes / flow brackets), or `nothing` if the line is not a mapping entry.
function _find_colon(text::AbstractString)
    cs = collect(text)
    depth = 0; inq = false; qc = ' '
    for i in eachindex(cs)
        c = cs[i]
        if inq
            c == qc && (inq = false)
        elseif c == '"' || c == '\''
            inq = true; qc = c
        elseif c == '[' || c == '{'
            depth += 1
        elseif c == ']' || c == '}'
            depth -= 1
        elseif c == ':' && depth == 0 && (i == length(cs) || cs[i+1] == ' ')
            return i
        end
    end
    return nothing
end

_parse_key(s::AbstractString) = _unquote(strip(s))

_scalar_or_flow(s::AbstractString) = begin
    t = strip(s)
    (startswith(t, "[") || startswith(t, "{")) ? _flow_toplevel(t) : _scalar(String(t))
end

# ── Scalars ────────────────────────────────────────────────────────────────────

function _scalar(s::AbstractString)
    t = strip(s)
    (isempty(t) || t == "null" || t == "~" || t == "Null" || t == "NULL") && return YamlNull()
    (t == "true"  || t == "True"  || t == "TRUE")  && return YamlBool(true)
    (t == "false" || t == "False" || t == "FALSE") && return YamlBool(false)
    if _is_quoted(t)
        return YamlString(_unquote(t))
    end
    n = tryparse(Int, t);     n !== nothing && return YamlNumber(n)
    f = tryparse(Float64, t); f !== nothing && return YamlNumber(f)
    return YamlString(String(t))
end

_is_quoted(s) = length(s) >= 2 &&
    ((s[1] == '"' && s[end] == '"') || (s[1] == '\'' && s[end] == '\''))

function _unquote(s::AbstractString)
    _is_quoted(s) || return String(s)
    inner = s[2:prevind(s, lastindex(s))]
    s[1] == '\'' ? replace(String(inner), "''" => "'") : _unescape_double(inner)
end

function _unescape_double(s::AbstractString)
    cs = collect(s)
    io = IOBuffer()
    i = 1
    while i <= length(cs)
        c = cs[i]
        if c == '\\' && i < length(cs)
            e = cs[i+1]; i += 2
            e == 'n'  ? print(io, '\n') :
            e == 't'  ? print(io, '\t') :
            e == 'r'  ? print(io, '\r') :
            e == 'b'  ? print(io, '\b') :
            e == 'f'  ? print(io, '\f') :
            e == '/'  ? print(io, '/')  :
            e == '\\' ? print(io, '\\') :
            e == '"'  ? print(io, '"')  :
            e == 'u'  ? (print(io, Char(parse(UInt16, String(cs[i:i+3]); base = 16))); i += 4) :
                        print(io, e)
        else
            print(io, c); i += 1
        end
    end
    String(take!(io))
end

# ── Flow grammar (JSON-superset: `[…]`, `{…}`, scalars) ─────────────────────────

mutable struct _Flow
    cs::Vector{Char}
    i::Int
end

_feof(f)   = f.i > length(f.cs)
_fpeek(f)  = _feof(f) ? '\0' : f.cs[f.i]
_fnext!(f) = (_feof(f) && error("YAML: unexpected end of flow input"); c = f.cs[f.i]; f.i += 1; c)
_fws!(f)   = (while !_feof(f) && (_fpeek(f) == ' ' || _fpeek(f) == '\t'); f.i += 1; end)

function _flow_toplevel(s::AbstractString)
    f = _Flow(collect(s), 1)
    v = _flow_value(f)
    _fws!(f)
    _feof(f) || error("YAML: trailing characters in flow scalar '$s'")
    v
end

function _flow_value(f::_Flow)
    _fws!(f)
    c = _fpeek(f)
    c == '[' && return _flow_seq(f)
    c == '{' && return _flow_map(f)
    return _scalar(_flow_raw!(f, (',', ']', '}')))
end

function _flow_seq(f::_Flow)
    _fnext!(f)  # [
    items = YamlDocument[]
    _fws!(f)
    _fpeek(f) == ']' && (f.i += 1; return YamlSequence(items))
    while true
        push!(items, _flow_value(f))
        _fws!(f)
        c = _fnext!(f)
        c == ',' && continue
        c == ']' && break
        error("YAML: expected ',' or ']' but got '$c'")
    end
    YamlSequence(items)
end

function _flow_map(f::_Flow)
    _fnext!(f)  # {
    pairs = Pair{String,YamlDocument}[]
    _fws!(f)
    _fpeek(f) == '}' && (f.i += 1; return YamlMapping())
    while true
        _fws!(f)
        key = _parse_key(_flow_raw!(f, (':',)))
        _fws!(f)
        c = _fnext!(f)
        c == ':' || error("YAML: expected ':' in flow mapping but got '$c'")
        push!(pairs, key => _flow_value(f))
        _fws!(f)
        c = _fnext!(f)
        c == ',' && continue
        c == '}' && break
        error("YAML: expected ',' or '}' but got '$c'")
    end
    isempty(pairs) ? YamlMapping() : YamlMapping(pairs...)
end

# Read a raw scalar token up to (but not consuming) the first top-level `stops`
# char, treating quoted regions opaquely. Returned trimmed; `_scalar`/`_parse_key`
# then interpret it.
function _flow_raw!(f::_Flow, stops::Tuple)
    io = IOBuffer()
    while !_feof(f)
        c = _fpeek(f)
        c in stops && break
        if c == '"' || c == '\''
            q = _fnext!(f); print(io, q)
            while true
                d = _fnext!(f); print(io, d)
                if q == '"' && d == '\\' && !_feof(f)
                    print(io, _fnext!(f))            # keep escaped char literal
                elseif d == q
                    if q == '\'' && _fpeek(f) == '\''
                        print(io, _fnext!(f)); continue   # '' escaped single quote
                    end
                    break
                end
            end
        else
            print(io, _fnext!(f))
        end
    end
    String(strip(String(take!(io))))
end

# ── Entry points ───────────────────────────────────────────────────────────────

"""
    parse_yaml(text) -> YamlDocument

Parse a YAML string into a `YamlDocument`. An empty document yields `YamlNull`.
"""
function parse_yaml(text::AbstractString)
    p = _Block(_logical_lines(text), 1)
    _at_end(p) && return YamlNull()
    _block(p, _cur(p)[1])
end

"""
    parse_yaml_file(path) -> YamlDocument

Read and parse a `.yaml`/`.yml` file from disk.
"""
parse_yaml_file(path::AbstractString) = parse_yaml(read(path, String))

end # module
