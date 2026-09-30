# Fragment of `MarkdownModule` — the Markdown document types: the abstract
# `MarkdownDocument`, its insertion cursor, and the block and inline nodes a
# document tree holds.

abstract type MarkdownDocument <: Document end

# ── Insertion cursor ────────────────────────────────────────────────────────

"""
A placeholder for a Markdown node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct MarkdownInsertion <: MarkdownDocument
    value::Any = nothing
end

# ── Inline nodes ──────────────────────────────────────────────────────────────

"""
A run of plain inline text. Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownText <: MarkdownDocument
    content::String
end

Base.getindex(t::MarkdownText) = t.content::String
Base.setindex!(t::MarkdownText, v::AbstractString) = (t.content = String(v))
set_cell_computation!(t::MarkdownText, f::Function) = (set_cell_computation!(getfield(t, :content), f); t)
set_cell_value!(t::MarkdownText, v::AbstractString) = (set_cell_value!(getfield(t, :content), String(v)); t)

"""
An inline code span (`` `code` ``). Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownCode <: MarkdownDocument
    content::String
end

Base.getindex(c::MarkdownCode) = c.content::String
Base.setindex!(c::MarkdownCode, v::AbstractString) = (c.content = String(v))
set_cell_computation!(c::MarkdownCode, f::Function) = (set_cell_computation!(getfield(c, :content), f); c)
set_cell_value!(c::MarkdownCode, v::AbstractString) = (set_cell_value!(getfield(c, :content), String(v)); c)

"""
Emphasised (italic) inline content (`*…*`), a sequence of inline nodes.
"""
@document struct MarkdownEmphasis <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownEmphasis to content

"""
Strong (bold) inline content (`**…**`), a sequence of inline nodes.
"""
@document struct MarkdownStrong <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownStrong to content

"""
An inline link (`[content](url)`). `content` is the inline text shown, `url` the
target.
"""
@document struct MarkdownLink <: MarkdownDocument
    content::CellVector = CellVector()
    url::String
end

@forward_vector_protocol on MarkdownLink to content

"""
An inline image (`![alt](url)`). `alt` is the alternative text, `url` the source.
"""
@document struct MarkdownImage <: MarkdownDocument
    alt::String
    url::String
end

# ── Block nodes ───────────────────────────────────────────────────────────────

"""
A heading (`#`…`######`). `level` is 1–6 and `content` is a sequence of inline
nodes.
"""
@document struct MarkdownHeading <: MarkdownDocument
    level::Int
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownHeading to content

"""
A prose paragraph — a sequence of inline nodes.
"""
@document struct MarkdownParagraph <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownParagraph to content

"""
A fenced code block (```` ``` ````). `language` is the info string (may be `""`)
and `code` the verbatim body. `collapsed` hides the body behind a marker in the
projection.
"""
@document struct MarkdownCodeBlock <: MarkdownDocument
    language::String
    code::String
    collapsed::Bool = false
end

"""
A thematic break — a horizontal rule (`---`).
"""
@document struct MarkdownThematicBreak <: MarkdownDocument
end

"""
A block quote (`> …`). `elements` holds its child blocks; `collapsed` hides them
behind a marker in the projection.
"""
@document struct MarkdownQuote <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownQuote to elements

"""
One item of a `MarkdownList`. `elements` holds its child blocks (a list item may
itself contain paragraphs, nested lists, …); `collapsed` hides them in the
projection.
"""
@document struct MarkdownListItem <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownListItem to elements

"""
A list. `ordered` selects between a numbered (`1.`) and a bulleted (`-`) list;
`items` holds its `MarkdownListItem`s. `collapsed` hides them in the projection.
`ordered` is a required leading argument so `items` reaches the `CellVector`-
wrapping constructor: `MarkdownList(true, [MarkdownListItem(…), …])`.
"""
@document struct MarkdownList <: MarkdownDocument
    ordered::Bool
    items::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownList to items

"""
One row of a `MarkdownTable`. `elements` holds one `MarkdownParagraph` for each
column: an entry of a table is a run of inlines, which is what a paragraph is.
"""
@document struct MarkdownTableRow <: MarkdownDocument
    elements::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownTableRow to elements

"""
A table, as GitHub Markdown writes it: the `header` row, a delimiter row, and the
body `rows`, each a `MarkdownTableRow`. `alignments` holds one of `:default`,
`:left`, `:center` and `:right` for each column; it is what the delimiter row
says, and the delimiter row is printed from it. `alignments` and `header` are
required leading arguments, so `rows` reaches the `CellVector`-wrapping
constructor: `MarkdownTable([:default], MarkdownTableRow(…), [MarkdownTableRow(…)])`.
"""
@document struct MarkdownTable <: MarkdownDocument
    alignments::Any             # Vector{Symbol}, one per column
    header::MarkdownTableRow
    rows::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownTable to rows

# ── Root ──────────────────────────────────────────────────────────────────────

"""
The whole Markdown document — a top-level sequence of block nodes. `collapsed`
hides the body behind a marker in the projection.
"""
@document struct MarkdownRoot <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownRoot to elements

# Text-replace edits need no per-type method: the type-in target fields —
# `MarkdownText.content`, `MarkdownCode.content`, `MarkdownHeading.level` (a
# number reparsed from its text), `MarkdownCodeBlock.language`/`code`,
# `MarkdownLink.url`, and `MarkdownImage.alt`/`url` — are all plain strings (or a
# reparsed number), handled by the generic splice.
