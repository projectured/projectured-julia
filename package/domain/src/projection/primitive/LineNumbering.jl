"""
    TextLineNumberingModule

Text → Text projection. Prepends a reactive line-number prefix to every
line in the input TextText. Lines are delimited by TextNewline elements;
each prefix is a plain TextString of the form "<n><separator>" where <n>
is left-padded to a uniform width derived from the total line count (or an
explicit width when width > 0).
"""
module TextLineNumberingModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..ColorModule: StyleColor, color_default
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapModule: SimpleIoMap
import ..PrinterContextModule: child_context
import ..ReferenceModule: ConcreteReferencePath, RangeReference, FieldReference, EmptyReferencePath, strip_reference_types
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
export TextLineNumbering, LineNumbering

# ── TextLineNumbering ──────────────────────────────────────────────────────

struct TextLineNumbering <: Projection
    width::Int      # 0 = auto (derived from total line count)
    separator::String
    font::StyleFont
end

TextLineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_20) =
    TextLineNumbering(width, separator, font)

# Projection print: wraps input.elements in a reactive Cell that rebuilds
# the output element list whenever the input spans change.  For each line
# (delimited by TextNewline elements) a TextString prefix is inserted before
# the first span on that line.
function print_document(p::TextLineNumbering, recursion, text::TextText, ctx)
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

# Reader: map an output `.elements[out_span].content{char}` path back to the
# matching input span. Prefix spans (added by this projection) have no
# pre-image, so they round-trip to char 0 of the next real input span.
function read_intent(p::TextLineNumbering, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    out_span, out_char = _parse_text_elem_path(op.path)
    out_span === nothing && return nothing
    mapping = _output_to_input_map(iomap.input.elements)
    out_span <= length(mapping) || return nothing
    in_span, char_offset, is_prefix = mapping[out_span]
    if is_prefix
        next = findnext(t -> !t[3], mapping, out_span + 1)
        next === nothing && return nothing
        in_span, char_offset, _ = mapping[next]
        out_char = 0
    end
    ReplaceSelectionOperation(@reference elements[in_span].content{char_offset + out_char})
end

read_intent(::TextLineNumbering, ::SimpleIoMap, evt::KeyDown) = evt

# Walk the input element list mirroring the printer's prefix-insertion
# logic. For each emitted output element, record the corresponding input
# element index and char offset, or mark it as a projection-inserted prefix.
function _output_to_input_map(input_elems)
    result = Tuple{Int, Int, Bool}[]
    push!(result, (0, 0, true))  # leading prefix
    for (in_idx, elem) in enumerate(input_elems)
        if elem isa TextNewline
            push!(result, (in_idx, 0, false))
            push!(result, (0, 0, true))
        elseif elem isa TextString && occursin('\n', elem.content::AbstractString)
            parts = split(elem.content::AbstractString, '\n')
            char_offset = 0
            for (i, part) in enumerate(parts)
                if i < length(parts)
                    push!(result, (in_idx, char_offset, false))
                    char_offset += length(part) + 1
                    push!(result, (0, 0, true))
                elseif !isempty(part)
                    push!(result, (in_idx, char_offset, false))
                end
            end
        else
            push!(result, (in_idx, 0, false))
        end
    end
    result
end

function _parse_text_elem_path(path)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return (nothing, nothing)
    h1 = path.head
    (h1 isa FieldReference && h1.name == "elements") || return (nothing, nothing)
    t1 = path.tail
    t1 isa ConcreteReferencePath || return (nothing, nothing)
    h2 = t1.head
    h2 isa RangeReference || return (nothing, nothing)
    span_idx = h2.start::Int + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return (nothing, nothing)
    h3 = t2.head
    (h3 isa FieldReference && h3.name == "content") || return (nothing, nothing)
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return (nothing, nothing)
    h4 = t3.head
    h4 isa RangeReference || return (nothing, nothing)
    (span_idx, h4.start::Int)
end


# ── Compound convenience constructor ────────────────────────────────────────

function LineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_20)
    TextLineNumbering(width=width, separator=separator, font=font)
end

end # module
