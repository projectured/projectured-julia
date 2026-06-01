"""
    TextWordWrappingModule

Text → Text projection. Word-wraps lines in a TextText document by splitting
TextString spans at word boundaries and inserting TextNewline elements when
the accumulated column width exceeds the configured limit.
"""
module TextWordWrappingModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapModule: SimpleIoMap
import ..ProjectionContextModule: child_context
export TextWordWrapping, WordWrapping

# ── TextWordWrapping ────────────────────────────────────────────────────────

struct TextWordWrapping <: Projection
    width::Int   # column width; 0 = no wrapping
end

TextWordWrapping(; width::Int = 80) = TextWordWrapping(width)

# Projection print: wraps input.elements in a reactive Cell that rebuilds
# the output element list whenever the input spans change.  TextString spans
# are split at word boundaries when their content would push the column
# offset past `width`; TextNewline elements reset the column counter.
function projection_print(p::TextWordWrapping, text::TextText, recursion, ctx)
    elements_cv = CellVector(() -> begin
        elems = text.elements
        result = TextDocument[]
        col = 0
        for elem in elems
            if elem isa TextNewline
                push!(result, elem)
                col = 0
            elseif elem isa TextString
                content = elem.content::AbstractString
                col = _wrap_string!(result, elem, content, col, p.width)
            else
                push!(result, elem)
            end
        end
        result
    end)
    SimpleIoMap(p, text, TextText(elements_cv, Cell(nothing)))
end

# ── Word-wrap helpers ───────────────────────────────────────────────────────

function _make_span(original::TextString, content::String)
    TextString(Cell(content), getfield(original, :font), getfield(original, :font_color),
               getfield(original, :fill_color), getfield(original, :line_color), getfield(original, :padding), Cell(nothing))
end

function _make_newline(original::TextString)
    TextNewline(font=original.font, font_color=original.font_color,
                fill_color=original.fill_color, line_color=original.line_color,
                padding=original.padding)
end

# Splits content into alternating runs of whitespace and non-whitespace.
function _tokenize(content::AbstractString)
    [m.match for m in eachmatch(r"\s+|\S+", content)]
end

# Appends word-wrapped spans derived from `original` to `result`, inserting
# TextNewline elements when a word would push the column past `width`.
# Spaces at the start of a line (after a wrap) are dropped.
# Returns the updated column offset.
function _wrap_string!(result::Vector{TextDocument}, original::TextString,
                       content::AbstractString, col::Int, width::Int)
    width <= 0 && (push!(result, original); return col + length(content))
    isempty(content) && return col
    buf = IOBuffer()
    for token in _tokenize(content)
        tlen = length(token)
        if isspace(first(token))
            col == 0 && continue           # drop leading spaces after a wrap
            col + tlen > width && continue # drop trailing spaces before a wrap
            print(buf, token)
            col += tlen
        else
            if col > 0 && col + tlen > width
                s = String(take!(buf))
                !isempty(s) && push!(result, _make_span(original, s))
                push!(result, _make_newline(original))
                col = 0
            end
            print(buf, token)
            col += tlen
        end
    end
    s = String(take!(buf))
    !isempty(s) && push!(result, _make_span(original, s))
    return col
end

# ── Compound convenience constructor ────────────────────────────────────────

function WordWrapping(; width::Int = 80)
    TextWordWrapping(width=width)
end

end # module
