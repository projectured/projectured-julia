"""
    TextLineNumberingModule

Text → Text projection. Prepends a reactive line-number prefix to every
line in the input TextText. Lines are delimited by TextNewline elements;
each prefix is a plain TextString of the form "<n><separator>" where <n>
is left-padded to a uniform width derived from the total line count (or an
explicit width when width > 0).
"""
module TextLineNumberingModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..ColorModule: StyleColor, color_default
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapModule: SimpleIoMap
import ..ProjectionContextModule: child_context
export TextLineNumbering, LineNumbering

# ── TextLineNumbering ──────────────────────────────────────────────────────

struct TextLineNumbering <: Projection
    width::Int      # 0 = auto (derived from total line count)
    separator::String
    font::StyleFont
end

TextLineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_24) =
    TextLineNumbering(width, separator, font)

# Projection print: wraps input.elements in a reactive Cell that rebuilds
# the output element list whenever the input spans change.  For each line
# (delimited by TextNewline elements) a TextString prefix is inserted before
# the first span on that line.
function projection_print(p::TextLineNumbering, text::TextText, recursion, ctx)
    elements_cv = CellVector(() -> begin
        elems = text.elements
        n_newlines = 0
        for e in elems
            if e isa TextNewline
                n_newlines += 1
            elseif e isa TextString
                n_newlines += count(==('\n'), e.content::AbstractString)
            end
        end
        total_lines = n_newlines + 1
        w = p.width > 0 ? p.width : ndigits(total_lines)
        prefix_color = StyleColor(88/255, 110/255, 117/255, 1.0)
        make_prefix(n) = TextString(lpad(string(n), w) * p.separator, p.font, prefix_color)
        result = TextDocument[]
        line = 1
        push!(result, make_prefix(line))
        for elem in elems
            if elem isa TextNewline
                push!(result, elem)
                line += 1
                push!(result, make_prefix(line))
            elseif elem isa TextString && occursin('\n', elem.content::AbstractString)
                parts = split(elem.content::AbstractString, '\n')
                for (i, part) in enumerate(parts)
                    if i < length(parts)
                        push!(result, _line_numbering_span(elem, part * "\n"))
                        line += 1
                        push!(result, make_prefix(line))
                    elseif !isempty(part)
                        push!(result, _line_numbering_span(elem, part))
                    end
                end
            else
                push!(result, elem)
            end
        end
        result
    end)
    SimpleIoMap(p, text, TextText(elements_cv, Cell(nothing)))
end

function _line_numbering_span(original::TextString, content::AbstractString)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               Cell(nothing))
end


# ── Compound convenience constructor ────────────────────────────────────────

function LineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_24)
    TextLineNumbering(width=width, separator=separator, font=font)
end

end # module
