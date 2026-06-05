"""
    TextModule

The text domain bridges the structural (syntax tree) and visual (graphics) domains.
Text is stored as a flat sequence of spans, each with its own reactive style and color.
The selection is a flat character offset, making keyboard navigation straightforward
before the pixel-coordinate layout is applied.

The domain includes:
- **Span types**: `TextString` (text content), `TextNewline` (line break), `TextSpacing` (spacing), `TextGraphics` (embedded graphics)
- **Container type**: `TextText` (sequence of spans)
- **Base type**: `TextDocument` abstract type for all text documents

Selection semantics:
- Spans: `.content[k]` — character offset within the span's content
- TextText: `.elements[i]` — cursor within span i, then `.content[k]` for character offset

Each span has reactive styling fields:
- `font` — font style (e.g., "bold", "italic", "monospace")
- `font_color` — text color (name, hex, or rgb)
- `fill_color` — background fill color
- `line_color` — border/line color
- `padding` — inset/padding value
"""
module TextModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..GeometryModule: Inset
import ..ReferenceModule: Reference
import ..OperationApiModule: _apply_string_replace!
export TextDocument, TextInsertion, TextForeign, TextNewline, TextSpacing, TextString, TextGraphics, TextText, setfn!,
       ITextInsertion, ITextForeign, ITextNewline, ITextSpacing, ITextString, ITextGraphics, ITextText

# ── TextDocument (base) ───────────────────────────────────────────────────

"""
    TextDocument

Abstract base type for all text document types. Every concrete text type
subtypes `TextDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type TextDocument <: Document end

# ── TextInsertion ────────────────────────────────────────────────────

@document struct TextInsertion <: TextDocument
    value::Any
    selection::Reference
end
TextInsertion() = TextInsertion(Cell(nothing), Cell(nothing))

@document struct TextForeign <: TextDocument
    value::Any
    selection::Reference
end
TextForeign(value) = TextForeign(Cell(value), Cell(nothing))

# ── TextNewline ─────────────────────────────────────────────────────

"""
    TextNewline

Represents a line break in text. All styling fields are reactive cells for
incremental updates.

# Fields

- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — text color
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructor

- `TextNewline(; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextNewline <: TextDocument
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextNewline(; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextNewline(Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextSpacing ─────────────────────────────────────────────────────

"""
    TextSpacing

Represents horizontal or vertical spacing in text. The size can be specified
in pixels or character spaces.

# Fields

- `size::Cell` — holds the spacing size as `Number`
- `unit::Cell` — holds the unit as `Symbol` (`:pixel` or `:space`)
- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — text color
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructor

- `TextSpacing(size::Number; unit=:pixel, font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextSpacing <: TextDocument
    size::Number
    unit::Symbol
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextSpacing(size::Number; unit=:pixel, font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextSpacing(Cell(size), Cell(unit), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextString ─────────────────────────────────────────────────────

"""
    TextString(content, font, font_color)

A single text span. Each field is a reactive `Cell`.

- `content::Cell`    — holds `AbstractString`
- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — holds `StyleColor` (RGBA color with components in [0,1])
- `fill_color::Cell` — holds background fill color or `nothing`
- `line_color::Cell` — holds border/line color or `nothing`
- `padding::Cell`    — holds inset/padding value or `nothing`

When a `TextText` selection path descends into a span, the sub-path
refers to a character within the span's `content` field:  `.content[k]`
"""
@document struct TextString <: TextDocument
    content::AbstractString
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextString(content::AbstractString, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), Cell(font), Cell(font_color), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::AbstractString) =
    TextString(Cell(content), Cell(font_ubuntu_monospace_regular_24), Cell(color_default), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::Function, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), Cell(font), Cell(font_color), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# ── TextGraphics ─────────────────────────────────────────────────────

"""
    TextGraphics

Embeds a graphics document within text. This allows mixing graphical elements
with text spans. The content can be any `Document` type (e.g., `GraphicsCanvas`).

# Fields

- `content::Cell` — holds the embedded `Document`
- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — text color
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructor

- `TextGraphics(content; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextGraphics <: TextDocument
    content::Document
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextGraphics(content; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextText ───────────────────────────────────────────────────────────

"""
    TextText(spans)

A sequence of `TextString` spans. The span list is a reactive `Cell`
holding `Vector{TextString}`, so structural changes (add/remove spans)
are tracked alongside per-span value changes.

The `selection` cell holds a path into the span sequence, or `nothing`:
  `.elements[i]`  — cursor within element i
"""
@document struct TextText <: TextDocument
    elements::CollectionDocument
    selection::Reference
end

TextText() = TextText(CellVector(), Cell(nothing))

TextText(spans::Vector{<:TextDocument}) =
    TextText(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextText(spans::TextDocument...) =
    TextText(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextText(f::Function) = TextText(CellVector(f), Cell(nothing))

# ── Element access ─────────────────────────────────────────────────

Base.length(st::TextText)               = length(st.elements)
Base.isempty(st::TextText)              = isempty(st.elements)
Base.getindex(st::TextText, i::Integer) = st.elements[i]
Base.firstindex(::TextText)             = 1
Base.lastindex(st::TextText)            = length(st)
Base.iterate(st::TextText, state...)    = iterate(st.elements, state...)
Base.eachindex(st::TextText)            = eachindex(st.elements)

function Base.setindex!(st::TextText, span::TextDocument, i::Integer)
    st.elements[i] = span
    return span
end

function Base.push!(st::TextText, spans::TextDocument...)
    for s in spans
        push!(st.elements, Cell(s))
    end
    return st
end

function Base.pop!(st::TextText)
    pop!(st.elements)
end

function Base.insert!(st::TextText, i::Integer, span::TextDocument)
    insert!(st.elements, i, Cell(span))
    return st
end

function Base.deleteat!(st::TextText, i)
    deleteat!(st.elements, i)
    return st
end

# ── String-replace operation ────────────────────────────────────────

function _apply_string_replace!(target::TextString, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "content" || error("TextString supports only field 'content', got: $field_name")
    old = target.content::AbstractString
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    target.content = String(left) * replacement * String(right)
end

# ── setfn! delegation ───────────────────────────────────────────────

setfn!(s::TextString, f::Function) = (setfn!(getfield(s, :content), f); s)
setfn!(st::TextText, f::Function) = (setfn!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

# ── Display ──────────────────────────────────────────────────────

function Base.show(io::IO, s::TextString)
    print(io, "TextString(", repr(s.content),
          ", font=", repr(s.font),
          ", font_color=", repr(s.font_color), ")")
end

function Base.show(io::IO, st::TextText)
    print(io, "TextText([")
    for (i, s) in enumerate(st.elements)
        i > 1 && print(io, ", ")
        show(io, s)
    end
    print(io, "])")
end

end # module
