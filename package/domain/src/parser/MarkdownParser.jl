"""
    MarkdownParserModule

A small, pragmatic Markdown parser. Converts Markdown source text into a
`MarkdownRoot` tree from `MarkdownModule`.

Provides:
- `markdownparse(text)` — parse a Markdown string into a `MarkdownRoot`
- `markdownparse_file(path)` — read and parse a `.md` file from disk

Deliberately minimal (it is not CommonMark-conformant). Block level: ATX headings
(`#`…`######`), fenced code blocks (```` ``` ````), thematic breaks
(`---`/`***`/`___`), blockquotes (`>`), unordered/ordered lists (`-`/`*`/`+`,
`1.`), and paragraphs (consecutive non-blank lines). Inline level: `` `code` ``,
`**strong**`, `*emphasis*`, `![alt](url)` images and `[text](url)` links; anything
unmatched degrades to literal text. It is enough to turn model output or typed
Markdown into a real document.
"""
module MarkdownParserModule

import ..MarkdownModule: MarkdownDocument, MarkdownRoot, MarkdownHeading, MarkdownParagraph,
                         MarkdownCodeBlock, MarkdownThematicBreak, MarkdownQuote, MarkdownList,
                         MarkdownListItem, MarkdownText, MarkdownCode, MarkdownEmphasis,
                         MarkdownStrong, MarkdownLink, MarkdownImage

export markdownparse, markdownparse_file

# ── Inline parsing (character-level over a `Vector{Char}`) ─────────────────────

_find(cs, ch, from) = findnext(==(ch), cs, from)

# Index of the first of a `a`,`b` char pair at/after `from`, else `nothing`.
function _find2(cs, a::Char, b::Char, from::Int)
    for k in from:(length(cs) - 1)
        cs[k] == a && cs[k + 1] == b && return k
    end
    return nothing
end

# Parse `[text](url)` (or, for an image, `[alt](url)`) whose `[` sits at `i`.
# Returns `(text_chars, url_chars, next_index)` or `nothing`. No nesting of `]`.
function _match_link(cs, i::Int)
    (i <= length(cs) && cs[i] == '[') || return nothing
    close_b = _find(cs, ']', i + 1)
    close_b === nothing && return nothing
    (close_b + 1 <= length(cs) && cs[close_b + 1] == '(') || return nothing
    close_p = _find(cs, ')', close_b + 2)
    close_p === nothing && return nothing
    (cs[i + 1:close_b - 1], cs[close_b + 2:close_p - 1], close_p + 1)
end

"""
    _parse_inline(text) -> Vector{MarkdownDocument}

Split a run of inline Markdown into text / code / emphasis / strong / link / image
nodes. Unclosed delimiters are emitted as literal text.
"""
function _parse_inline(text::AbstractString)
    cs = collect(text)
    n = length(cs)
    nodes = MarkdownDocument[]
    buf = IOBuffer()
    flush!() = (s = String(take!(buf)); isempty(s) || push!(nodes, MarkdownText(s)))
    i = 1
    while i <= n
        c = cs[i]
        if c == '`'
            j = _find(cs, '`', i + 1)
            if j !== nothing
                flush!(); push!(nodes, MarkdownCode(String(cs[i + 1:j - 1]))); i = j + 1; continue
            end
        elseif c == '!' && i < n && cs[i + 1] == '['
            r = _match_link(cs, i + 1)
            if r !== nothing
                alt, url, nxt = r
                flush!(); push!(nodes, MarkdownImage(String(alt), String(url))); i = nxt; continue
            end
        elseif c == '['
            r = _match_link(cs, i)
            if r !== nothing
                txt, url, nxt = r
                flush!(); push!(nodes, MarkdownLink(_parse_inline(String(txt)), String(url))); i = nxt; continue
            end
        elseif c == '*' && i < n && cs[i + 1] == '*'
            j = _find2(cs, '*', '*', i + 2)
            if j !== nothing
                flush!(); push!(nodes, MarkdownStrong(_parse_inline(String(cs[i + 2:j - 1])))); i = j + 2; continue
            end
        elseif c == '*'
            j = _find(cs, '*', i + 1)
            if j !== nothing
                flush!(); push!(nodes, MarkdownEmphasis(_parse_inline(String(cs[i + 1:j - 1])))); i = j + 1; continue
            end
        end
        print(buf, c); i += 1
    end
    flush!()
    nodes
end

# ── Block parsing (line-level) ─────────────────────────────────────────────────

# A run of ≥3 of the same `-`/`*`/`_` (spaces allowed) on its own line.
function _is_thematic_break(line::AbstractString)
    s = replace(strip(line), " " => "")
    length(s) >= 3 && (s[1] in ('-', '*', '_')) && all(==(s[1]), s)
end

# `(; ordered, text)` when `line` is a list item, else `nothing`.
function _list_marker(line::AbstractString)
    m = match(r"^[ \t]*[-*+][ \t]+(.*)$", line)
    m !== nothing && return (ordered = false, text = String(m.captures[1]))
    m = match(r"^[ \t]*\d+[.)][ \t]+(.*)$", line)
    m !== nothing && return (ordered = true, text = String(m.captures[1]))
    return nothing
end

_is_block_start(line) =
    _is_thematic_break(strip(line)) ||
    match(r"^#{1,6}[ \t]+", line) !== nothing ||
    match(r"^[ \t]*```", line) !== nothing ||
    startswith(lstrip(line), ">") ||
    _list_marker(line) !== nothing

function _parse_blocks(lines::Vector{String})
    blocks = MarkdownDocument[]
    n = length(lines)
    i = 1
    while i <= n
        line = lines[i]
        if isempty(strip(line))
            i += 1; continue
        end
        if _is_thematic_break(strip(line))
            push!(blocks, MarkdownThematicBreak()); i += 1; continue
        end
        m = match(r"^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$", line)
        if m !== nothing
            push!(blocks, MarkdownHeading(length(m.captures[1]), _parse_inline(String(m.captures[2]))))
            i += 1; continue
        end
        mf = match(r"^[ \t]*```[ \t]*([^`]*)$", line)
        if mf !== nothing
            code_lines = String[]
            i += 1
            while i <= n && match(r"^[ \t]*```[ \t]*$", lines[i]) === nothing
                push!(code_lines, lines[i]); i += 1
            end
            i <= n && (i += 1)   # consume the closing fence
            push!(blocks, MarkdownCodeBlock(String(strip(String(mf.captures[1]))), join(code_lines, "\n")))
            continue
        end
        if startswith(lstrip(line), ">")
            q_lines = String[]
            while i <= n && startswith(lstrip(lines[i]), ">")
                push!(q_lines, replace(lstrip(lines[i]), r"^>[ ]?" => "")); i += 1
            end
            push!(blocks, MarkdownQuote(_parse_blocks(q_lines))); continue
        end
        lm = _list_marker(line)
        if lm !== nothing
            ordered = lm.ordered
            items = MarkdownListItem[]
            while i <= n && (cur = _list_marker(lines[i])) !== nothing && cur.ordered == ordered
                push!(items, MarkdownListItem([MarkdownParagraph(_parse_inline(cur.text))])); i += 1
            end
            push!(blocks, MarkdownList(ordered, items)); continue
        end
        para_lines = String[]
        while i <= n && !isempty(strip(lines[i])) && !_is_block_start(lines[i])
            push!(para_lines, strip(lines[i])); i += 1
        end
        push!(blocks, MarkdownParagraph(_parse_inline(join(para_lines, " "))))
    end
    blocks
end

# ── Entry points ───────────────────────────────────────────────────────────────

"""
    markdownparse(text) -> MarkdownRoot

Parse a Markdown string into a `MarkdownRoot`. Never errors: unrecognised or
malformed constructs degrade to plain paragraphs / literal text.
"""
function markdownparse(text::AbstractString)
    normalized = replace(String(text), "\r\n" => "\n", "\r" => "\n")
    lines = String.(split(normalized, '\n'))
    MarkdownRoot(_parse_blocks(lines))
end

"""
    markdownparse_file(path) -> MarkdownRoot

Read and parse a `.md` file from disk.
"""
markdownparse_file(path::AbstractString) = markdownparse(read(path, String))

end # module
