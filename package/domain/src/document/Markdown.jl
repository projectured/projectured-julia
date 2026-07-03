"""
    MarkdownModule

The Markdown document domain. A Markdown document is a sequence of block-level
nodes; blocks in turn hold either further blocks or a sequence of inline nodes,
so the selection mechanism can descend from the whole document down into a
single character of emphasised text.

The domain includes:
- **Root**: `MarkdownRoot` (the whole document — a block sequence)
- **Block nodes**: `MarkdownHeading`, `MarkdownParagraph`, `MarkdownCodeBlock`,
  `MarkdownThematicBreak`, `MarkdownQuote`, `MarkdownList`, `MarkdownListItem`
- **Inline nodes**: `MarkdownText`, `MarkdownCode`, `MarkdownEmphasis`,
  `MarkdownStrong`, `MarkdownLink`, `MarkdownImage`
- **Insertion cursor**: `MarkdownInsertion`
"""
module MarkdownModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document, @forward_vector
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export MarkdownDocument, set_function!

abstract type MarkdownDocument <: Document end

# ── Insertion cursor ────────────────────────────────────────────────────────

"""
A placeholder for a Markdown node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct MarkdownInsertion <: MarkdownDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Inline nodes ──────────────────────────────────────────────────────────────

"""
A run of plain inline text. Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownText <: MarkdownDocument
    content::String
    selection::Reference = nothing
end

Base.getindex(t::MarkdownText) = t.content::String
Base.setindex!(t::MarkdownText, v::AbstractString) = (t.content = String(v))
set_function!(t::MarkdownText, f::Function) = (set_function!(getfield(t, :content), f); t)
set_value!(t::MarkdownText, v::AbstractString) = (set_value!(getfield(t, :content), String(v)); t)

"""
An inline code span (`` `code` ``). Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownCode <: MarkdownDocument
    content::String
    selection::Reference = nothing
end

Base.getindex(c::MarkdownCode) = c.content::String
Base.setindex!(c::MarkdownCode, v::AbstractString) = (c.content = String(v))
set_function!(c::MarkdownCode, f::Function) = (set_function!(getfield(c, :content), f); c)
set_value!(c::MarkdownCode, v::AbstractString) = (set_value!(getfield(c, :content), String(v)); c)

"""
Emphasised (italic) inline content (`*…*`), a sequence of inline nodes.
"""
@document struct MarkdownEmphasis <: MarkdownDocument
    content::CellVector = CellVector()
    selection::Reference = nothing
end

@forward_vector MarkdownEmphasis content

"""
Strong (bold) inline content (`**…**`), a sequence of inline nodes.
"""
@document struct MarkdownStrong <: MarkdownDocument
    content::CellVector = CellVector()
    selection::Reference = nothing
end

@forward_vector MarkdownStrong content

"""
An inline link (`[content](url)`). `content` is the inline text shown, `url` the
target.
"""
@document struct MarkdownLink <: MarkdownDocument
    content::CellVector = CellVector()
    url::String
    selection::Reference = nothing
end

@forward_vector MarkdownLink content

"""
An inline image (`![alt](url)`). `alt` is the alternative text, `url` the source.
"""
@document struct MarkdownImage <: MarkdownDocument
    alt::String
    url::String
    selection::Reference = nothing
end

# ── Block nodes ───────────────────────────────────────────────────────────────

"""
A heading (`#`…`######`). `level` is 1–6 and `content` is a sequence of inline
nodes.
"""
@document struct MarkdownHeading <: MarkdownDocument
    level::Int
    content::CellVector = CellVector()
    selection::Reference = nothing
end

@forward_vector MarkdownHeading content

"""
A prose paragraph — a sequence of inline nodes.
"""
@document struct MarkdownParagraph <: MarkdownDocument
    content::CellVector = CellVector()
    selection::Reference = nothing
end

@forward_vector MarkdownParagraph content

"""
A fenced code block (```` ``` ````). `language` is the info string (may be `""`)
and `code` the verbatim body. `collapsed` hides the body behind a marker in the
projection.
"""
@document struct MarkdownCodeBlock <: MarkdownDocument
    language::String
    code::String
    collapsed::Bool = false
    selection::Reference = nothing
end

"""
A thematic break — a horizontal rule (`---`).
"""
@document struct MarkdownThematicBreak <: MarkdownDocument
    selection::Reference = nothing
end

"""
A block quote (`> …`). `elements` holds its child blocks; `collapsed` hides them
behind a marker in the projection.
"""
@document struct MarkdownQuote <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector MarkdownQuote elements

"""
One item of a `MarkdownList`. `elements` holds its child blocks (a list item may
itself contain paragraphs, nested lists, …); `collapsed` hides them in the
projection.
"""
@document struct MarkdownListItem <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector MarkdownListItem elements

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
    selection::Reference = nothing
end

@forward_vector MarkdownList items

# ── Root ──────────────────────────────────────────────────────────────────────

"""
The whole Markdown document — a top-level sequence of block nodes. `collapsed`
hides the body behind a marker in the projection.
"""
@document struct MarkdownRoot <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector MarkdownRoot elements

# Text-replace edits need no per-type method: the type-in target fields —
# `MarkdownText.content`, `MarkdownCode.content`, `MarkdownHeading.level` (a
# number reparsed from its text), `MarkdownCodeBlock.language`/`code`,
# `MarkdownLink.url`, and `MarkdownImage.alt`/`url` — are all plain strings (or a
# reparsed number), handled by the generic splice.

end # module
