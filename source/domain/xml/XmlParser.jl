# Fragment of `XmlModule`.
#
# A small recursive-descent XML parser. Converts XML source text into an
# `XmlElement` tree from `XmlModule`.
#
# Provides:
# - `parse_xml(text)` — parse an XML string into its root `XmlElement`
# - `parse_xml_file(path)` — read and parse a `.xml` file from disk
#
# Deliberately minimal: one root element, nested elements, attributes
# (`name="value"` or `name='value'`), text content, self-closing tags, the five
# named entities and the numeric character references. The XML declaration
# (`<?xml …?>`), comments (`<!-- … -->`), and `<!…>` declarations are skipped. Not namespace- or DTD-aware — enough to turn
# typed XML in the editor into a real document. Malformed input raises an error.
# ── Cursor over the source ─────────────────────────────────────────────────────

mutable struct _Cur
    cs::Vector{Char}
    i::Int
end

_eof(p)   = p.i > length(p.cs)
_peek(p)  = _eof(p) ? '\0' : p.cs[p.i]
_next!(p) = (_eof(p) && error("XML: unexpected end of input"); c = p.cs[p.i]; p.i += 1; c)

function _skipws!(p)
    while !_eof(p) && isspace(_peek(p))
        p.i += 1
    end
end

function _expect!(p, ch::Char)
    c = _next!(p)
    c == ch || error("XML: expected '$ch' but got '$c' at position $(p.i - 1)")
end

_starts(p, word) = p.i + length(word) - 1 <= length(p.cs) &&
                   String(p.cs[p.i:p.i + length(word) - 1]) == word

function _skip_past!(p, marker)
    while !_eof(p) && !_starts(p, marker)
        p.i += 1
    end
    p.i += length(marker)
end

_isname(c) = isletter(c) || isdigit(c) || c in ('-', '_', ':', '.')

function _name!(p)
    start = p.i
    while !_eof(p) && _isname(_peek(p))
        p.i += 1
    end
    p.i > start || error("XML: expected a name at position $(p.i)")
    String(p.cs[start:p.i - 1])
end

const _NAMED_ENTITIES = Dict("lt" => "<", "gt" => ">", "quot" => "\"", "apos" => "'", "amp" => "&")

# One pass reads the named entities and the numeric character references, so the
# `&` that `&amp;` gives never starts a second reference: `&amp;#65;` is `&#65;`.
_unescape(s) = replace(String(s), r"&(lt|gt|quot|apos|amp|#[0-9]+|#x[0-9A-Fa-f]+);" => _unescape_reference)

# A code point that is not a valid `Char` stays as it is written.
function _unescape_reference(reference)
    name = SubString(reference, 2, lastindex(reference) - 1)
    startswith(name, '#') || return _NAMED_ENTITIES[name]
    code = startswith(name, "#x") ? tryparse(UInt32, SubString(name, 3); base = 16) :
                                    tryparse(UInt32, SubString(name, 2))
    (code === nothing || !isvalid(Char, code)) && return reference
    string(Char(code))
end

# Skip whitespace, the XML declaration, comments, and `<!…>` declarations.
function _skip_prolog!(p)
    while true
        _skipws!(p)
        if _starts(p, "<?")
            _skip_past!(p, "?>")
        elseif _starts(p, "<!--")
            _skip_past!(p, "-->")
        elseif _starts(p, "<!")
            _skip_past!(p, ">")
        else
            return
        end
    end
end

# ── Grammar ────────────────────────────────────────────────────────────────────

function _element!(p)
    _expect!(p, '<')
    tag = _name!(p)
    attrs = XmlAttribute[]
    while true
        _skipws!(p)
        c = _peek(p)
        (c == '>' || c == '/') && break
        name = _name!(p)
        _skipws!(p); _expect!(p, '='); _skipws!(p)
        push!(attrs, XmlAttribute(name, _attr_value!(p)))
    end
    _skipws!(p)
    if _peek(p) == '/'                      # self-closing: <tag …/>
        p.i += 1
        _expect!(p, '>')
        return XmlElement(tag, attrs, XmlDocument[])
    end
    _expect!(p, '>')
    children = XmlDocument[]
    while true
        text = _text_until_lt!(p)
        isempty(strip(text)) || push!(children, XmlText(text))
        if _starts(p, "</")                 # closing tag
            p.i += 2
            close = _name!(p)
            _skipws!(p); _expect!(p, '>')
            close == tag || error("XML: </$close> does not match <$tag>")
            break
        elseif _starts(p, "<!--")
            _skip_past!(p, "-->")
        elseif _peek(p) == '<'              # nested element
            push!(children, _element!(p))
        else
            error("XML: unexpected end of input inside <$tag>")
        end
    end
    XmlElement(tag, attrs, children)
end

function _attr_value!(p)
    q = _next!(p)
    (q == '"' || q == '\'') || error("XML: expected a quoted attribute value at position $(p.i - 1)")
    start = p.i
    while !_eof(p) && _peek(p) != q
        p.i += 1
    end
    val = String(p.cs[start:p.i - 1])
    _expect!(p, q)
    _unescape(val)
end

function _text_until_lt!(p)
    start = p.i
    while !_eof(p) && _peek(p) != '<'
        p.i += 1
    end
    _unescape(p.cs[start:p.i - 1])
end

# ── Entry points ───────────────────────────────────────────────────────────────

"""
    parse_xml(text) -> XmlElement

Parse an XML string into its root `XmlElement`.
"""
function parse_xml(text::AbstractString)
    p = _Cur(collect(String(text)), 1)
    _skip_prolog!(p)
    _skipws!(p)
    _peek(p) == '<' || error("XML: expected a root element")
    _element!(p)
end

"""
    parse_xml_file(path) -> XmlElement

Read and parse a `.xml` file from disk.
"""
parse_xml_file(path::AbstractString) = parse_xml(read(path, String))
