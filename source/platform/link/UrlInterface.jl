# Fragment of `LinkModule` — what an address names: whether it names its place by
# itself, the file of a `file:` address, and the open of an address as the target
# of a link.

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

is_absolute_url(url::Url) = occursin(r"^[A-Za-z][A-Za-z0-9+.\-]*:", url.address)

"""
    find_url_file_path(url) -> String or nothing

The path of the file that a `file:` address names, with its escaped characters
read, or `nothing` for any other address.

Use it to open the file of an address in a tab.

# Example

    find_url_file_path(Url("file:///tmp/a%20b.txt"))   # "/tmp/a b.txt"
"""
function find_url_file_path end

function find_url_file_path(url::Url)
    found = match(r"^file:(?://[^/]*)?(/.*)$", url.address)
    found === nothing ? nothing : _decode_url_text(found.captures[1])
end

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

find_web_url(text::AbstractString) =
    (occursin(r"^[A-Za-z][A-Za-z0-9+.\-]*://", text) || startswith(lowercase(text), "mailto:")) ?
        Url(String(text)) : nothing

# An absolute address opens outside the editor; a relative one opens through the
# page of the link, which resolves it (`find_navigator_target`).
make_target_open_operation(url::Url, place::Symbol) =
    is_absolute_url(url) ? OpenUrlOperation(url, place) :
                           OpenPageOperation(nothing, EmptyReference(), place; target = url.address)
