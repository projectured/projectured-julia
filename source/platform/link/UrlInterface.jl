# Fragment of `LinkModule` — the pieces of an address: the read of a text into
# pieces, their print, and the edit of the text or of one piece; and what an
# address names: whether it names its place by itself, the file of a `file:`
# address, and the open of an address as the target of a link.

# The pieces of an address, in the order of its text.
const _URL_PIECES = (:scheme, :userinfo, :host, :port, :path, :query, :fragment)

# RFC 3986, appendix B, with the scheme limited to its grammar, so a text before a
# colon that is no scheme stays in the path. It matches every text.
const _URL_PATTERN = r"^(?:([A-Za-z][A-Za-z0-9+.\-]*):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$"s

Url(text::AbstractString) = Url(; _parse_url_pieces(text)...)

# The pieces of `text`, as written. In the `//` part, the userinfo is the text
# before the last `@`, the port the text after the last `:` that stands after any
# `]`, and the host the rest.
function _parse_url_pieces(text::AbstractString)
    found = match(_URL_PATTERN, text)
    (scheme, authority, path, query, fragment) = (piece === nothing ? nothing : String(piece)
                                                  for piece in found.captures)
    (userinfo, host, port) = (nothing, nothing, nothing)
    if authority !== nothing
        at = findlast('@', authority)
        at === nothing || (userinfo = authority[1:prevind(authority, at)])
        rest = at === nothing ? authority : authority[nextind(authority, at):end]
        colon = findlast(':', rest)
        bracket = findlast(']', rest)
        if colon !== nothing && (bracket === nothing || colon > bracket)
            (host, port) = (rest[1:prevind(rest, colon)], rest[nextind(rest, colon):end])
        else
            host = rest
        end
    end
    (; scheme, userinfo, host, port, path = something(path, ""), query, fragment)
end

_get_url_pieces(url::Url) = NamedTuple{_URL_PIECES}(Tuple(getproperty(url, piece) for piece in _URL_PIECES))

"""
    format_url(url) -> String

The text of `url`, its pieces as written, by the rule of RFC 3986, section 5.3:
`scheme:`, `//` when there is a host, `userinfo@`, the host, `:port`, the path,
`?query` and `#fragment`. The text of `Url(text)` is `text`.

Use it to show an address, or to give it to a program outside the editor.

# Example

    format_url(Url(; scheme = "https", host = "julialang.org", path = "/learning"))
    # "https://julialang.org/learning"
"""
function format_url end

format_url(url::Url) = _format_url_pieces(_get_url_pieces(url))

function _format_url_pieces(pieces::NamedTuple)
    io = IOBuffer()
    pieces.scheme === nothing || print(io, pieces.scheme, ':')
    if pieces.host !== nothing
        print(io, "//")
        pieces.userinfo === nothing || print(io, pieces.userinfo, '@')
        print(io, pieces.host)
        pieces.port === nothing || print(io, ':', pieces.port)
    end
    print(io, pieces.path)
    pieces.query === nothing || print(io, '?', pieces.query)
    pieces.fragment === nothing || print(io, '#', pieces.fragment)
    String(take!(io))
end

"""
    make_url_text_operation(url, text) -> Operation or nothing

The edit that gives `url` the address `text`: one operation that writes each
piece that `text` changes, or `nothing` when it changes no piece. It writes the
fields of `url` itself, so a link that holds `url` keeps it.

Use it to change a whole address, as the text line of an address does at each
typed edit.

# Example

    make_url_text_operation(url, "https://julialang.org/learning")
"""
function make_url_text_operation end

function make_url_text_operation(url::Url, text::AbstractString)
    pieces = _parse_url_pieces(text)
    writes = Any[ReplaceReferencedValueOperation(url, String(piece), pieces[piece])
                 for piece in _URL_PIECES if !isequal(pieces[piece], getproperty(url, piece))]
    isempty(writes) ? nothing : CompoundOperation(writes)
end

"""
    make_url_piece_operation(url, piece, text) -> Operation or nothing

The edit that gives the piece `piece` of `url`, such as `:host` or `:query`, the
text `text`, or removes the piece for `nothing`. It reads the changed address
again, so a delimiter of another piece moves its text into that piece: the host
`julialang.org/learning` gives the host `julialang.org` and the path `/learning`.
A userinfo or a port on an address with no host gives it the host `""`, and a
path after a host starts with `/`, as RFC 3986 needs.

Use it, and not a write of the field, to change one piece of an address.

# Example

    make_url_piece_operation(url, :query, "lang=en")
"""
function make_url_piece_operation end

function make_url_piece_operation(url::Url, piece::Symbol, text::Union{Nothing, AbstractString})
    piece in _URL_PIECES || throw(ArgumentError("an address has no piece $(repr(piece))"))
    value = piece === :path ? String(something(text, "")) : (text === nothing ? nothing : String(text))
    pieces = merge(_get_url_pieces(url), NamedTuple{(piece,)}((value,)))
    if piece in (:userinfo, :port) && value !== nothing && pieces.host === nothing
        pieces = merge(pieces, (; host = ""))
    end
    if pieces.host !== nothing && !isempty(pieces.path) && !startswith(pieces.path, '/')
        pieces = merge(pieces, (; path = "/" * pieces.path))
    end
    make_url_text_operation(url, _format_url_pieces(pieces))
end

"""
    is_absolute_url(url) -> Bool

Whether `url` names its place by itself, with a scheme such as `https:`,
`mailto:` or `file:`, and not relative to the page of its link.

Use it to tell an address outside the editor from a place that a page resolves.

# Example

    is_absolute_url(Url("https://julialang.org"))   # true
    is_absolute_url(Url("#install"))                # false
"""
function is_absolute_url end

is_absolute_url(url::Url) = url.scheme !== nothing

"""
    find_url_file_path(url) -> String or nothing

The path of the file that a `file:` address names, with its escaped characters
read, or `nothing` for any other address.

Use it to open the file of an address in a tab.

# Example

    find_url_file_path(Url("file:///tmp/a%20b.txt"))   # "/tmp/a b.txt"
"""
function find_url_file_path end

find_url_file_path(url::Url) =
    url.scheme !== nothing && lowercase(url.scheme) == "file" && startswith(url.path, '/') ?
        _decode_url_text(url.path) : nothing

# The text of `text` with each `%` and two hex digits read as the byte that they
# name, so a name of a file keeps its spaces and its letters outside ASCII.
function _decode_url_text(text::AbstractString)
    units = codeunits(text)
    bytes = UInt8[]
    k = 1
    while k <= length(units)
        byte = units[k] == UInt8('%') && k + 2 <= length(units) ?
               tryparse(UInt8, String(units[(k + 1):(k + 2)]); base = 16) : nothing
        byte === nothing ? (push!(bytes, units[k]); k += 1) : (push!(bytes, byte); k += 3)
    end
    String(bytes)
end

"""
    find_web_url(text) -> Url or nothing

The address that `text` names when it is an address outside the editor: a scheme
with `//` after it, such as `https://julialang.org` or `file:///tmp/notes.txt`,
or a `mailto:` address. `nothing` for any other text, such as a relative path or
a name with a colon in it, which only the page of the link resolves.

Use it in a domain whose links name their target by a text, to tell an address
outside the editor from a place of the page.

# Example

    find_web_url("https://julialang.org")   # Url("https://julialang.org")
    find_web_url("ug:cha:queueing")         # nothing
"""
function find_web_url end

function find_web_url(text::AbstractString)
    pieces = _parse_url_pieces(text)
    pieces.scheme !== nothing && (pieces.host !== nothing || lowercase(pieces.scheme) == "mailto") ?
        Url(; pieces...) : nothing
end

# An absolute address opens outside the editor; a relative one opens through the
# page of the link, which resolves it (`find_navigator_target`).
make_target_open_operation(url::Url, place::Symbol) =
    is_absolute_url(url) ? OpenUrlOperation(url, place) :
                           OpenPageOperation(nothing, EmptyReference(), place; target = format_url(url))
