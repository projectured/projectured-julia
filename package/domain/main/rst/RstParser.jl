"""
    RstParserModule

A pragmatic reStructuredText parser. Converts RST source text into an
`RstRoot` tree from `RstModule`.

Provides:
- `rstparse(text)` — parse an RST string into an `RstRoot`
- `rstparse_file(path)` — read and parse a `.rst` file from disk

Deliberately minimal (it is not docutils). It covers what the INET
documentation uses. Block level: sections with any adornment character,
paragraphs, literal blocks, line blocks, bullet and enumerated lists,
definition lists, field lists, block quotes, grid tables, transitions,
comments, targets, substitution definitions, footnotes, and directives.
Inline level: `` ``literal`` ``, `` :role:`x` ``, `**strong**`, `*emphasis*`,
`` `text <url>`_ ``, `|substitution|` and `[label]_`; anything unmatched
degrades to literal text.

**Indentation drives everything.** The parser works on a line vector that a
region has already dedented to column zero. A construct that owns an indented
body — a directive, a list item, a definition — hands that body back to the
same block reader after dedenting it, so nesting needs no special case.

**Sections resolve by order of first use.** RST gives no fixed meaning to an
adornment character. The block reader emits a title marker carrying the
character, and one pass afterwards assigns depths: a character already seen
reopens its own depth, a new character opens one level deeper. That pass also
turns the flat sequence into the tree the document wants.
"""
module RstParserModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..RstModule: RstDocument, RstRoot, RstSection, RstParagraph, RstText, RstLiteral,
                    RstEmphasis, RstStrong, RstRole, RstReference, RstSubstitutionReference,
                    RstFootnoteReference, RstLiteralBlock, RstLineBlock, RstListItem,
                    RstBulletList, RstEnumeratedList, RstDefinitionItem, RstDefinitionList,
                    RstField, RstFieldList, RstBlockQuote, RstTransition, RstComment,
                    RstTarget, RstSubstitutionDefinition, RstFootnote, RstTableCell,
                    RstTableRow, RstGridTable, RstDirectiveOption, RstLiteralInclude,
                    RstFigure, RstCodeBlock, RstImage, RstVideo, RstAudio, RstAdmonition,
                    RstToctree, RstMathBlock, RstRawBlock, RstRoleDefinition, RstDirective

export rstparse, rstparse_file

# ── Line helpers ──────────────────────────────────────────────────────────────

# The characters that may underline a title or stand as a transition. Narrower
# than the docutils set: every character docutils allows but this omits would
# collide with a construct that starts a line (`|` with a line block, `>` with
# a quote), and none of them adorns a title in the corpus.
const _ADORNMENT_CHARS = Set{Char}("=-~^+*#\"'`:._")

_blank(line::AbstractString) = all(isspace, line)

# Leading-space count; `-1` for a blank line, which therefore never constrains
# the indent of a run.
function _indent(line::AbstractString)
    i = findfirst(c -> c != ' ', line)
    i === nothing ? -1 : i - 1
end

# Is this line a run of one adornment character and nothing else?
function _is_adornment(line::AbstractString)
    s = rstrip(line)
    length(s) >= 2 || return false
    c = s[1]
    c in _ADORNMENT_CHARS || return false
    all(==(c), s)
end

# Strip the common indent of every non-blank line.
function _dedent(lines::Vector{String})
    isempty(lines) && return lines
    base = typemax(Int)
    for l in lines
        _blank(l) && continue
        base = min(base, _indent(l))
    end
    base == typemax(Int) && return ["" for _ in lines]
    [_blank(l) ? "" : l[(base + 1):end] for l in lines]
end

# Drop the blank lines at both ends of a run.
function _trim_blanks(lines::Vector{String})
    a, b = 1, length(lines)
    while a <= b && _blank(lines[a]); a += 1 end
    while b >= a && _blank(lines[b]); b -= 1 end
    lines[a:b]
end

# The end of the run that starts at `i` and stays blank or indented by at
# least `least`. Returns `i - 1` when the run is empty.
function _indented_run(lines::Vector{String}, i::Int, least::Int)
    j = i - 1
    k = i
    while k <= length(lines)
        if _blank(lines[k])
            k += 1
        elseif _indent(lines[k]) >= least
            j = k
            k += 1
        else
            break
        end
    end
    j
end

# ── Section markers ───────────────────────────────────────────────────────────

# What the block reader emits in place of a title; `_nest_sections` turns a run
# of these plus the blocks between them into the section tree.
struct _SectionTitle
    adornment::String
    overline::Bool
    text::String
end

# ── Block reading ─────────────────────────────────────────────────────────────

"""
    _parse_blocks(lines) -> Vector{Any}

Read a dedented line vector into a flat vector of blocks and
[`_SectionTitle`](@ref) markers.
"""
function _parse_blocks(lines::Vector{String})
    out = Any[]
    i = 1
    n = length(lines)
    while i <= n
        line = lines[i]
        if _blank(line)
            i += 1
            continue
        end
        # An indented start with no marker of its own is a block quote. Every
        # other construct below is flush left, because the caller dedented.
        if _indent(line) > 0
            j = _indented_run(lines, i, 1)
            push!(out, _parse_block_quote(_dedent(_trim_blanks(lines[i:j]))))
            i = j + 1
            continue
        end
        # An overlined title: adornment, title, the same adornment again.
        if _is_adornment(line) && i + 2 <= n && !_blank(lines[i + 1]) &&
           !_is_adornment(lines[i + 1]) && _is_adornment(lines[i + 2]) &&
           rstrip(lines[i + 2])[1] == rstrip(line)[1]
            push!(out, _SectionTitle(string(rstrip(line)[1]), true, strip(lines[i + 1])))
            i += 3
            continue
        end
        # A transition: an adornment standing alone between blanks.
        if _is_adornment(line) && length(rstrip(line)) >= 4 &&
           (i == n || _blank(lines[i + 1]))
            push!(out, RstTransition())
            i += 1
            continue
        end
        # A title: a line underlined by an adornment at least as long.
        if i < n && _is_adornment(lines[i + 1]) &&
           length(rstrip(lines[i + 1])) >= length(rstrip(line)) && !_is_adornment(line)
            push!(out, _SectionTitle(string(rstrip(lines[i + 1])[1]), false, strip(line)))
            i += 2
            continue
        end
        # Explicit markup: a directive, a target, a substitution, a footnote or
        # a comment.
        if startswith(line, "..") && (length(strip(line)) == 2 || startswith(line, ".. "))
            j = _indented_run(lines, i + 1, 1)
            block, i = _parse_explicit(lines, i, j)
            push!(out, block)
            continue
        end
        # A grid table.
        if _is_grid_border(line)
            j = i
            while j <= n && !_blank(lines[j]) && (_is_grid_border(lines[j]) || startswith(lines[j], "|"))
                j += 1
            end
            push!(out, _parse_grid_table(lines[i:(j - 1)]))
            i = j
            continue
        end
        # A line block.
        if startswith(line, "| ") || rstrip(line) == "|"
            j = i
            while j <= n && (startswith(lines[j], "| ") || rstrip(lines[j]) == "|" ||
                             (!_blank(lines[j]) && _indent(lines[j]) > 0))
                j += 1
            end
            push!(out, _parse_line_block(lines[i:(j - 1)]))
            i = j
            continue
        end
        # A bullet list.
        if _bullet_match(line) !== nothing
            block, i = _parse_bullet_list(lines, i)
            push!(out, block)
            continue
        end
        # An enumerated list.
        if _enum_match(line) !== nothing
            block, i = _parse_enumerated_list(lines, i)
            push!(out, block)
            continue
        end
        # A field list.
        if _field_match(line) !== nothing
            block, i = _parse_field_list(lines, i)
            push!(out, block)
            continue
        end
        # A definition list: an unindented term whose next line is indented,
        # with no blank line between the two. A blank line there would make the
        # indented run a block quote instead.
        if i < n && !_blank(lines[i + 1]) && _indent(lines[i + 1]) > 0
            block, i = _parse_definition_list(lines, i)
            push!(out, block)
            continue
        end
        # A paragraph, and the literal block a trailing `::` introduces.
        j = i
        while j <= n && !_blank(lines[j]) && _indent(lines[j]) == 0 &&
              !(j > i && _is_adornment(lines[j]))
            j += 1
        end
        text = join(strip.(lines[i:(j - 1)]), "\n")
        i = j
        literal = endswith(text, "::")
        if literal
            text = _strip_literal_marker(text)
            isempty(text) || push!(out, RstParagraph(_parse_inline(text)))
            k = _indented_run(lines, i, 1)
            if k >= i
                push!(out, RstLiteralBlock(join(_dedent(_trim_blanks(lines[i:k])), "\n")))
                i = k + 1
            end
        else
            push!(out, RstParagraph(_parse_inline(text)))
        end
    end
    out
end

# `text::` keeps one colon, `text ::` and a bare `::` keep none — the docutils
# rule, which decides whether the marker was punctuation or a word ending.
function _strip_literal_marker(text::AbstractString)
    body = text[1:(end - 2)]
    isempty(body) && return ""
    endswith(body, " ") ? String(rstrip(body)) : String(body * ":")
end

function _parse_block_quote(lines::Vector{String})
    attribution = ""
    body = lines
    if !isempty(body)
        last = strip(body[end])
        if startswith(last, "-- ") || startswith(last, "— ")
            attribution = String(strip(last[(findfirst(' ', last)):end]))
            body = _trim_blanks(body[1:(end - 1)])
        end
    end
    RstBlockQuote(_build_all(_parse_blocks(body)), attribution)
end

# ── Lists ─────────────────────────────────────────────────────────────────────

_bullet_match(line::AbstractString) = match(r"^([-*+])(?:(\s+)(.*))?$", line)
_enum_match(line::AbstractString)   = match(r"^(\d+|#)([.)])(?:(\s+)(.*))?$", line)
# A field needs a space (or the line end) after its closing colon, which is
# what tells `:author: name` apart from a paragraph opening with `:ned:`Foo``.
_field_match(line::AbstractString)  = match(r"^:([^:\s][^:]*):(?:\s+(.*))?$", line)

# Collect one item of a marked list: the text on the marker line plus every
# following line indented to the marker's content column.
#
# The continuation lines are dedented **on their own**, not together with the
# marker line. The marker line arrives already stripped of its marker and so
# sits at column zero; dedenting the two together would find a common indent of
# zero and leave every continuation indented, which makes the item re-read as a
# definition list.
function _collect_item(lines::Vector{String}, i::Int, content_indent::Int, first_text::String)
    j = _indented_run(lines, i + 1, content_indent)
    rest = j >= i + 1 ? _dedent(collect(lines[(i + 1):j])) : String[]
    (_trim_blanks(vcat(String[first_text], rest)), max(j, i) + 1)
end

function _parse_bullet_list(lines::Vector{String}, i::Int)
    marker = string(lines[i][1])
    items = Any[]
    n = length(lines)
    while i <= n
        _blank(lines[i]) && (i += 1; continue)
        m = _indent(lines[i]) == 0 ? _bullet_match(lines[i]) : nothing
        (m === nothing || m.captures[1] != marker) && break
        gap = m.captures[2] === nothing ? 1 : length(m.captures[2])
        text = m.captures[3] === nothing ? "" : String(m.captures[3])
        body, i = _collect_item(lines, i, 1 + gap, text)
        push!(items, RstListItem(_build_all(_parse_blocks(body))))
    end
    (RstBulletList(marker, items), i)
end

function _parse_enumerated_list(lines::Vector{String}, i::Int)
    m0 = _enum_match(lines[i])
    style = String(m0.captures[1] == "#" ? "#" : "1") * String(m0.captures[2])
    start = m0.captures[1] == "#" ? 1 : parse(Int, m0.captures[1])
    items = Any[]
    n = length(lines)
    while i <= n
        _blank(lines[i]) && (i += 1; continue)
        m = _indent(lines[i]) == 0 ? _enum_match(lines[i]) : nothing
        (m === nothing || m.captures[2] != m0.captures[2]) && break
        gap = m.captures[3] === nothing ? 1 : length(m.captures[3])
        text = m.captures[4] === nothing ? "" : String(m.captures[4])
        body, i = _collect_item(lines, i, length(m.captures[1]) + 1 + gap, text)
        push!(items, RstListItem(_build_all(_parse_blocks(body))))
    end
    (RstEnumeratedList(style, items, start), i)
end

function _parse_field_list(lines::Vector{String}, i::Int)
    fields = Any[]
    n = length(lines)
    while i <= n
        _blank(lines[i]) && (i += 1; continue)
        m = _indent(lines[i]) == 0 ? _field_match(lines[i]) : nothing
        m === nothing && break
        text = m.captures[2] === nothing ? "" : String(m.captures[2])
        body, i = _collect_item(lines, i, 1, text)
        push!(fields, RstField(String(m.captures[1]), _build_all(_parse_blocks(body))))
    end
    (RstFieldList(fields), i)
end

function _parse_definition_list(lines::Vector{String}, i::Int)
    items = Any[]
    n = length(lines)
    while i <= n
        _blank(lines[i]) && (i += 1; continue)
        (_indent(lines[i]) == 0 && i < n && !_blank(lines[i + 1]) && _indent(lines[i + 1]) > 0) || break
        term = strip(lines[i])
        j = _indented_run(lines, i + 1, 1)
        body = _dedent(_trim_blanks(lines[(i + 1):j]))
        push!(items, RstDefinitionItem(_parse_inline(String(term));
                                       elements = _build_all(_parse_blocks(body))))
        i = j + 1
    end
    (RstDefinitionList(items), i)
end

function _parse_line_block(lines::Vector{String})
    rows = Any[]
    for l in lines
        s = rstrip(l)
        if startswith(s, "| ")
            push!(rows, RstParagraph(_parse_inline(String(strip(s[3:end])))))
        elseif s == "|"
            push!(rows, RstParagraph(Any[]))
        elseif !isempty(strip(s)) && !isempty(rows)
            # A continuation of the line above.
            push!(rows, RstParagraph(_parse_inline(String(strip(s)))))
        end
    end
    RstLineBlock(rows)
end

# ── Grid tables ───────────────────────────────────────────────────────────────

_is_grid_border(line::AbstractString) =
    (s = rstrip(line); length(s) >= 3 && startswith(s, "+") && all(c -> c in ('+', '-', '='), s))

function _parse_grid_table(lines::Vector{String})
    borders = [k for k in eachindex(lines) if _is_grid_border(lines[k])]
    isempty(borders) && return RstGridTable(0, Any[])
    cuts = [k - 1 for k in eachindex(lines[borders[1]]) if lines[borders[1]][k] == '+']
    widths = [cuts[k + 1] - cuts[k] - 1 for k in 1:(length(cuts) - 1)]
    header_rows = 0
    rows = Any[]
    for b in 1:(length(borders) - 1)
        a, z = borders[b], borders[b + 1]
        z - a <= 1 && continue
        body = lines[(a + 1):(z - 1)]
        cells = Any[]
        for c in 1:(length(cuts) - 1)
            from, to = cuts[c] + 2, cuts[c + 1]
            text = String[]
            for l in body
                push!(text, from > length(l) ? "" : String(rstrip(l[from:min(to, length(l))])))
            end
            push!(cells, RstTableCell(_build_all(_parse_blocks(_dedent(_trim_blanks(text))))))
        end
        push!(rows, RstTableRow(cells))
        # A `+===+` border closes the head.
        occursin('=', lines[z]) && (header_rows = length(rows))
    end
    RstGridTable(header_rows, rows, widths)
end

# ── Explicit markup ───────────────────────────────────────────────────────────

# Read the explicit-markup construct that starts at `i` and owns the indented
# run through `j`. Returns the block and the next line index.
function _parse_explicit(lines::Vector{String}, i::Int, j::Int)
    line = lines[i]
    body = j >= i + 1 ? _dedent(_trim_blanks(lines[(i + 1):j])) : String[]
    next = j + 1

    m = match(r"^\.\. _(.+):\s*$", line)
    m !== nothing && return (RstTarget(String(m.captures[1])), next)

    m = match(r"^\.\. \|([^|]+)\|\s+(.*)$", line)
    if m !== nothing
        inner = _parse_directive(String(m.captures[2]), body)
        return (RstSubstitutionDefinition(String(m.captures[1]), inner), next)
    end

    m = match(r"^\.\. \[([^\]]+)\]\s*(.*)$", line)
    if m !== nothing
        text = String(m.captures[2])
        all = isempty(text) ? body : vcat([text], body)
        return (RstFootnote(String(m.captures[1]), _build_all(_parse_blocks(all))), next)
    end

    m = match(r"^\.\. ([a-zA-Z0-9_+:.-]+)::\s*(.*)$", line)
    m !== nothing && return (_parse_directive(line[4:end], body), next)

    # Anything else is a comment. Its body rides along verbatim.
    text = strip(line) == ".." ? "" : String(line[4:end])
    isempty(body) || (text = isempty(text) ? join(body, "\n") : text * "\n" * join(body, "\n"))
    (RstComment(text), next)
end

# Split a directive body into its leading option lines and the rest.
function _split_options(body::Vector{String})
    k = 1
    options = Any[]
    while k <= length(body)
        m = _indent(body[k]) == 0 ? match(r"^:([^:\s][^:]*):(?:\s+(.*))?$", body[k]) : nothing
        m === nothing && break
        value = m.captures[2] === nothing ? "" : String(strip(m.captures[2]))
        # An option value may continue on the following indented lines.
        e = _indented_run(body, k + 1, 1)
        e >= k + 1 && (value = strip(value * "\n" * join(_dedent(body[(k + 1):e]), "\n")))
        push!(options, RstDirectiveOption(String(m.captures[1]), String(value)))
        k = max(e, k) + 1
    end
    (options, _trim_blanks(body[min(k, length(body) + 1):end]))
end

_option(options, name) = (k = findfirst(o -> o.name == name, options);
                          k === nothing ? "" : options[k].value)
_take!(options, names) = (kept = filter(o -> !(o.name in names), options);
                          (Dict(o.name => o.value for o in options if o.name in names), kept))

_flag(d, name) = haskey(d, name)
_int(d, name, default) = (v = get(d, name, ""); isempty(v) ? default : something(tryparse(Int, v), default))
_str(d, name) = String(get(d, name, ""))

const _ADMONITIONS = ("note", "warning", "important", "caution", "tip", "hint",
                      "danger", "attention", "error", "todo", "admonition")

# Build the directive that `head` (the text after `.. `) names, with `body` as
# its already-dedented content.
function _parse_directive(head::AbstractString, body::Vector{String})
    m = match(r"^([a-zA-Z0-9_+:.-]+)::\s*(.*)$", strip(head))
    m === nothing && return RstComment(String(head))
    name = String(m.captures[1])
    argument = String(strip(m.captures[2]))
    options, content = _split_options(body)

    if name == "literalinclude"
        d, extra = _take!(options, ("language", "start-at", "end-at", "start-after", "end-before"))
        return RstLiteralInclude(argument, _str(d, "language"), _str(d, "start-at"),
                                 _str(d, "end-at"), _str(d, "start-after"),
                                 _str(d, "end-before"), extra)
    elseif name == "figure"
        d, extra = _take!(options, ("align", "width"))
        return RstFigure(argument; align = _str(d, "align"), width = _str(d, "width"),
                         caption = _build_all(_parse_blocks(content)), extra = extra)
    elseif name == "code-block" || name == "code"
        return RstCodeBlock(isempty(argument) ? "" : argument, join(content, "\n"), options)
    elseif name == "image"
        d, extra = _take!(options, ("width", "height", "alt"))
        return RstImage(argument, _str(d, "width"), _str(d, "height"), _str(d, "alt"), extra)
    elseif name == "video" || name == "video_noloop"
        d, extra = _take!(options, ("width", "height"))
        return RstVideo(argument, _str(d, "width"), _str(d, "height"),
                        name == "video", extra)
    elseif name == "audio"
        return RstAudio(argument, options)
    elseif name in _ADMONITIONS
        all = isempty(argument) ? content : vcat([argument], content)
        return RstAdmonition(name, _build_all(_parse_blocks(all)))
    elseif name == "toctree"
        d, extra = _take!(options, ("maxdepth", "titlesonly", "glob"))
        entries = [RstText(String(strip(l))) for l in content if !_blank(l)]
        return RstToctree(entries; maxdepth = _int(d, "maxdepth", 0),
                          titlesonly = _flag(d, "titlesonly"), glob = _flag(d, "glob"),
                          extra = extra)
    elseif name == "math"
        all = isempty(argument) ? content : vcat([argument], content)
        return RstMathBlock(join(all, "\n"))
    elseif name == "raw"
        d, extra = _take!(options, ("format",))
        fmt = isempty(argument) ? _str(d, "format") : argument
        return RstRawBlock(fmt, join(content, "\n"))
    elseif name == "role"
        r = match(r"^([^(\s]+)(?:\(([^)]*)\))?$", argument)
        r === nothing && return RstRoleDefinition(argument, "", options)
        return RstRoleDefinition(String(r.captures[1]),
                                 r.captures[2] === nothing ? "" : String(r.captures[2]),
                                 options)
    end
    RstDirective(name, argument; options = options,
                 elements = _build_all(_parse_blocks(content)))
end

# ── Section nesting ───────────────────────────────────────────────────────────

# One node of the tree the nesting pass builds before it constructs documents.
mutable struct _Section
    title::_SectionTitle
    level::Int
    children::Vector{Any}
end

# Turn the flat block/marker sequence into a tree. The adornment character
# decides the depth, by the order the document first uses it.
function _nest_sections(items::Vector{Any})
    order = String[]
    roots = Any[]
    stack = _Section[]
    for it in items
        if it isa _SectionTitle
            k = findfirst(==(it.adornment), order)
            if k === nothing
                push!(order, it.adornment)
                k = length(order)
            end
            while !isempty(stack) && stack[end].level >= k
                pop!(stack)
            end
            node = _Section(it, k, Any[])
            push!(isempty(stack) ? roots : stack[end].children, node)
            push!(stack, node)
        else
            push!(isempty(stack) ? roots : stack[end].children, it)
        end
    end
    roots
end

# Construct the documents for one already-nested vector.
_build_all(items::Vector{Any}) = Any[_build(x) for x in _nest_sections(items)]

_build(x) = x
_build(s::_Section) = RstSection(s.level, s.title.adornment, _parse_inline(s.title.text);
                                 elements = Any[_build(c) for c in s.children],
                                 overline = s.title.overline)

# ── Inline parsing ────────────────────────────────────────────────────────────

# The characters an inline start-string may follow, and the ones an inline
# end-string may precede. These two sets are what keeps the corpus readable:
# an INET page writes `*.host.numApps = 1` in running prose, and without the
# rule that a start-string is followed by a non-blank and an end-string is
# preceded by a non-blank, every such wildcard would open an emphasis span.
const _PRE_OK  = Set{Char}(" \t\n-:/'\"<([{")
const _POST_OK = Set{Char}(" \t\n-.,:;!?\\/'\")]}>")

# May a delimiter of `width` characters start a span at `i`?
function _start_ok(cs::Vector{Char}, i::Int, width::Int)
    (i == 1 || cs[i - 1] in _PRE_OK) || return false
    i + width <= length(cs) || return false
    !isspace(cs[i + width])
end

# May a delimiter of `width` characters end a span at `j`?
function _end_ok(cs::Vector{Char}, j::Int, width::Int)
    j > 1 || return false
    isspace(cs[j - 1]) && return false
    j + width - 1 == length(cs) || cs[j + width] in _POST_OK
end

# The index of the first valid end-string at or after `from`.
function _find_end(cs::Vector{Char}, delim::Vector{Char}, from::Int)
    width = length(delim)
    j = from
    while j + width - 1 <= length(cs)
        if cs[j:(j + width - 1)] == delim && _end_ok(cs, j, width)
            return j
        end
        j += 1
    end
    nothing
end

# A reference closes with `` `_ `` or `` `__ ``, so the underscore that follows
# its backtick belongs to the marker. The general end-string rule would reject
# it — `_` is not a character an inline span may precede — which is why a
# reference gets its own finder.
function _find_reference_end(cs::Vector{Char}, from::Int)
    j = from
    while j < length(cs)
        cs[j] == '`' && !isspace(cs[j - 1]) && cs[j + 1] == '_' && return j
        j += 1
    end
    nothing
end

# `:name:`content`` at `i`; returns the name, the content and the next index.
function _match_role(cs::Vector{Char}, i::Int)
    n = length(cs)
    j = findnext(==(':'), cs, i + 1)
    (j === nothing || j == i + 1) && return nothing
    name = String(cs[(i + 1):(j - 1)])
    occursin(r"^[a-zA-Z0-9_+.-]+$", name) || return nothing
    (j + 1 <= n && cs[j + 1] == '`') || return nothing
    k = findnext(==('`'), cs, j + 2)
    k === nothing && return nothing
    (name, String(cs[(j + 2):(k - 1)]), k + 1)
end

# `text <url>` splits into its two halves; a bare `name` keeps an empty target.
function _split_reference(body::AbstractString)
    m = match(r"^(.*?)\s*<([^>]*)>$", body)
    m === nothing && return (String(strip(body)), "")
    (String(strip(m.captures[1])), String(m.captures[2]))
end

"""
    _parse_inline(text) -> Vector{Any}

Split a run of inline RST into text / literal / role / strong / emphasis /
reference / substitution / footnote nodes.

The delimiters are tried in the order an outer one can contain an inner one:
`` ``literal`` `` first (it protects everything inside it), then a role, then
`**strong**` before `*emphasis*`, then a reference, a substitution and a
footnote reference. An unclosed delimiter degrades to literal text.
"""
function _parse_inline(text::AbstractString)
    cs = collect(text)
    n = length(cs)
    out = Any[]
    buf = Char[]
    flush!() = isempty(buf) ? nothing : (push!(out, RstText(String(buf))); empty!(buf); nothing)
    i = 1
    while i <= n
        c = cs[i]
        matched = false
        if c == '`' && i + 1 <= n && cs[i + 1] == '`' && _start_ok(cs, i, 2)
            j = _find_end(cs, ['`', '`'], i + 2)
            if j !== nothing
                flush!(); push!(out, RstLiteral(String(cs[(i + 2):(j - 1)])))
                i = j + 2; matched = true
            end
        end
        if !matched && c == ':' && (i == 1 || cs[i - 1] in _PRE_OK)
            m = _match_role(cs, i)
            if m !== nothing
                flush!(); push!(out, RstRole(m[1], m[2]))
                i = m[3]; matched = true
            end
        end
        if !matched && c == '*' && i + 1 <= n && cs[i + 1] == '*' && _start_ok(cs, i, 2)
            j = _find_end(cs, ['*', '*'], i + 2)
            if j !== nothing
                flush!(); push!(out, RstStrong(_parse_inline(String(cs[(i + 2):(j - 1)]))))
                i = j + 2; matched = true
            end
        end
        if !matched && c == '*' && _start_ok(cs, i, 1)
            j = _find_end(cs, ['*'], i + 1)
            if j !== nothing
                flush!(); push!(out, RstEmphasis(_parse_inline(String(cs[(i + 1):(j - 1)]))))
                i = j + 1; matched = true
            end
        end
        if !matched && c == '`' && _start_ok(cs, i, 1)
            j = _find_reference_end(cs, i + 1)
            if j !== nothing
                anonymous = j + 2 <= n && cs[j + 2] == '_'
                text, target = _split_reference(String(cs[(i + 1):(j - 1)]))
                flush!(); push!(out, RstReference(text, target, anonymous))
                i = j + (anonymous ? 3 : 2); matched = true
            end
        end
        if !matched && c == '|' && _start_ok(cs, i, 1)
            j = _find_end(cs, ['|'], i + 1)
            if j !== nothing
                flush!(); push!(out, RstSubstitutionReference(String(cs[(i + 1):(j - 1)])))
                i = j + 1; matched = true
            end
        end
        if !matched && c == '[' && _start_ok(cs, i, 1)
            j = findnext(==(']'), cs, i + 1)
            if j !== nothing && j + 1 <= n && cs[j + 1] == '_' && j > i + 1
                flush!(); push!(out, RstFootnoteReference(String(cs[(i + 1):(j - 1)])))
                i = j + 2; matched = true
            end
        end
        matched || (push!(buf, c); i += 1)
    end
    flush!()
    out
end

# ── Entry points ──────────────────────────────────────────────────────────────

"""
    rstparse(text) -> RstRoot

Parse reStructuredText source into an `RstRoot`.
"""
function rstparse(text::AbstractString)
    normalised = replace(String(text), "\r\n" => "\n", "\t" => "        ")
    lines = String.(split(normalised, '\n'))
    RstRoot(_build_all(_parse_blocks(_dedent(lines))))
end

"""
    rstparse_file(path) -> RstRoot

Read and parse a `.rst` file from disk.
"""
rstparse_file(path::AbstractString) = rstparse(read(path, String))

end # module
