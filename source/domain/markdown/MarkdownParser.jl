# Fragment of `MarkdownModule`.
#
# A small, pragmatic Markdown parser. Converts Markdown source text into a
# `MarkdownRoot` tree from `MarkdownModule`.
#
# Provides:
# - `parse_markdown(text)` — parse a Markdown string into a `MarkdownRoot`
# - `parse_markdown_file(path)` — read and parse a `.md` file from disk
#
# Deliberately minimal (it is not CommonMark-conformant). Block level: ATX headings
# (`#`…`######`), fenced code blocks (```` ``` ````), indented code blocks (4
# columns), thematic breaks (`---`/`***`/`___`), blockquotes (`>`), Julia
# admonitions (`!!! note "title"`, read as a quote), GitHub tables (`| a | b |`
# over a `|---|:--:|` delimiter row), flat unordered/ordered lists
# (`-`/`*`/`+`, `1.`) whose items take their continuation lines, and paragraphs
# (consecutive non-blank lines). Inline level: `` `code` ``,
# `**strong**`, `*emphasis*`, `![alt](url)` images and `[text](url)` links; anything
# unmatched degrades to literal text. It is enough to turn model output or typed
# Markdown into a real document.
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

# A Julia admonition, `!!! kind "title"`, with or without its title.
_match_admonition(line::AbstractString) =
    match(r"^!!![ \t]+(\w+)(?:[ \t]+\"(.*)\")?[ \t]*$", line)

_is_block_start(line) =
    _is_thematic_break(strip(line)) ||
    match(r"^#{1,6}[ \t]+", line) !== nothing ||
    match(r"^[ \t]*```", line) !== nothing ||
    startswith(lstrip(line), ">") ||
    _list_marker(line) !== nothing ||
    _match_admonition(line) !== nothing

_is_blank(line::AbstractString) = isempty(strip(line))

# The indent of a line in columns. A tab goes to the next multiple of 4.
function _get_indent_width(line::AbstractString)
    width = 0
    for c in line
        c == ' '  ? (width += 1) :
        c == '\t' ? (width += 4 - width % 4) : break
    end
    width
end

# `line` without its first 4 columns of indent, or without all of its indent
# when it has less. A blank line becomes empty.
function _remove_indent(line::AbstractString)
    _is_blank(line) && return ""
    width = 0
    for (k, c) in pairs(line)
        (width >= 4 || !(c in (' ', '\t'))) && return String(line[k:end])
        width += c == '\t' ? 4 - width % 4 : 1
    end
    ""
end

# The entries of a table row, as GitHub Markdown splits them: at each `|` that
# is not escaped, with the pipes at the two ends dropped. An escaped pipe, `\|`,
# is a `|` in its entry, also inside a code span.
function _split_table_row(line::AbstractString)
    text = strip(line)
    startswith(text, '|') && (text = text[nextind(text, 1):end])
    endswith(text, '|') && !endswith(text, "\\|") && (text = text[1:prevind(text, lastindex(text))])
    entries = String[]
    entry = IOBuffer()
    escaped = false
    for c in text
        if escaped
            c == '|' || print(entry, '\\')
            print(entry, c)
            escaped = false
        elseif c == '\\'
            escaped = true
        elseif c == '|'
            push!(entries, String(strip(String(take!(entry)))))
        else
            print(entry, c)
        end
    end
    escaped && print(entry, '\\')
    push!(entries, String(strip(String(take!(entry)))))
    entries
end

# The alignment of a column, from its entry of the delimiter row, or `nothing`
# when the entry is not one of `---`, `:---`, `---:` and `:---:`.
function _parse_table_alignment(entry::AbstractString)
    match(r"^:?-+:?$", entry) === nothing && return nothing
    left, right = startswith(entry, ':'), endswith(entry, ':')
    left && right ? :center : left ? :left : right ? :right : :default
end

# The alignments of a table whose header is at `i` and whose delimiter row is
# below it, or `nothing` when the two lines do not start a table. The delimiter
# row has one entry for each entry of the header.
function _match_table_start(lines::Vector{String}, i::Int)
    i < length(lines) && occursin('|', lines[i]) && occursin('-', lines[i + 1]) ||
        return nothing
    alignments = _parse_table_alignment.(_split_table_row(lines[i + 1]))
    any(isnothing, alignments) && return nothing
    length(alignments) == length(_split_table_row(lines[i])) || return nothing
    Symbol[alignments...]
end

# One row of a table: an entry for each column. A row with fewer entries gets
# empty ones, and the entries past the last column are dropped.
function _make_table_row(line::AbstractString, column_count::Int)
    entries = _split_table_row(line)
    MarkdownTableRow([MarkdownParagraph(_parse_inline(j <= length(entries) ? entries[j] : ""))
                      for j in 1:column_count])
end

# A line that starts no block continues the paragraph above it, with or without
# an indent.
_is_continuation_line(lines::Vector{String}, i::Int) =
    !_is_blank(lines[i]) && !_is_block_start(lines[i]) && _match_table_start(lines, i) === nothing

# The lines from `i` on that are blank or indented by 4 columns, with the indent
# removed and the blank lines at the end dropped, and the index after them.
function _take_indented_lines(lines::Vector{String}, i::Int)
    taken = String[]
    while i <= length(lines) && (_is_blank(lines[i]) || _get_indent_width(lines[i]) >= 4)
        push!(taken, _remove_indent(lines[i])); i += 1
    end
    while !isempty(taken) && isempty(taken[end])
        pop!(taken)
    end
    taken, i
end

# An admonition is a quote: its title in bold, then its body. The kind names the
# title when the admonition gives none.
function _make_admonition_quote(m::RegexMatch, body::Vector{String})
    title = m.captures[2] === nothing ? uppercasefirst(String(m.captures[1])) :
                                        String(m.captures[2])
    elements = MarkdownDocument[MarkdownParagraph([MarkdownStrong([MarkdownText(title)])])]
    append!(elements, _parse_blocks(body))
    MarkdownQuote(elements)
end

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
        ma = _match_admonition(line)
        if ma !== nothing
            body, i = _take_indented_lines(lines, i + 1)
            push!(blocks, _make_admonition_quote(ma, body)); continue
        end
        alignments = _match_table_start(lines, i)
        if alignments !== nothing
            column_count = length(alignments)
            header = _make_table_row(line, column_count)
            rows = MarkdownTableRow[]
            i += 2
            while i <= n && occursin('|', lines[i]) && !_is_blank(lines[i]) && !_is_block_start(lines[i])
                push!(rows, _make_table_row(lines[i], column_count)); i += 1
            end
            push!(blocks, MarkdownTable(alignments, header, rows)); continue
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
                item_lines = String[strip(cur.text)]; i += 1
                while i <= n && _is_continuation_line(lines, i)
                    push!(item_lines, strip(lines[i])); i += 1
                end
                push!(items, MarkdownListItem([MarkdownParagraph(_parse_inline(join(item_lines, " ")))]))
            end
            push!(blocks, MarkdownList(ordered, items)); continue
        end
        # An indented code block comes after the list, so an indented list line
        # stays a list. It can not interrupt a paragraph or a list item: those
        # take an indented line as their own continuation first.
        if _get_indent_width(line) >= 4
            code_lines, i = _take_indented_lines(lines, i)
            push!(blocks, MarkdownCodeBlock("", join(code_lines, "\n"))); continue
        end
        # The first line always belongs to the paragraph, so a line that looks
        # like the start of a block but is none still moves the parse on.
        para_lines = String[strip(line)]; i += 1
        while i <= n && _is_continuation_line(lines, i)
            push!(para_lines, strip(lines[i])); i += 1
        end
        push!(blocks, MarkdownParagraph(_parse_inline(join(para_lines, " "))))
    end
    blocks
end

# ── Entry points ───────────────────────────────────────────────────────────────

"""
    parse_markdown(text) -> MarkdownRoot

Parse a Markdown string into a `MarkdownRoot`. Never errors: unrecognised or
malformed constructs degrade to plain paragraphs / literal text.
"""
function parse_markdown(text::AbstractString)
    normalized = replace(String(text), "\r\n" => "\n", "\r" => "\n")
    lines = String.(split(normalized, '\n'))
    MarkdownRoot(_parse_blocks(lines))
end

"""
    parse_markdown_file(path) -> MarkdownRoot

Read and parse a `.md` file from disk.
"""
parse_markdown_file(path::AbstractString) = parse_markdown(read(path, String))
