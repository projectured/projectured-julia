# Fragment of `TextModule`.
#
# Text → Text projection. Pixel-accurate word wrapping. Each output line holds the
# spans of its input line, and its `soft_breaks` cell holds the offsets where a row
# starts, computed from the text of that line and the wrap width. The wrap width is
# the maximum of the range the parent gives on the width, `ctx.maximum_width`,
# exact or bounded (so a resize re-wraps reactively), cut at the projection's
# `max_width`; with neither, a line does not wrap.
#
# A soft break is no character, so no flat offset moves and every reference maps
# to itself. The list of lines reads no width and no content, so a keystroke or a
# resize changes the soft breaks of the lines it touches and nothing else.
# ── Projection struct ───────────────────────────────────────────────────────

"""
    WordWrapping(; max_width=nothing, measure)

Pixel-based word-wrap projection. `measure::TextMeasure` matches the downstream
`TextToGraphics` measurer so wrap points line up with layout. A line wraps at
the edge of the range the parent gives (`ctx.maximum_width`), and at
`max_width` when that is less. With neither, a line does not wrap.
"""
struct WordWrapping <: Projection
    max_width::Union{Nothing, Int}
    measure::TextMeasure
end

WordWrapping(; max_width::Union{Nothing, Integer} = nothing, measure::TextMeasure) =
    WordWrapping(max_width === nothing ? nothing : Int(max_width), measure)

# ── Print ───────────────────────────────────────────────────────────────────

@iomap struct WordWrappingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
end

function print_document(p::WordWrapping, recursion, text::TextBlock, ctx)
    wrap_w_cell = _wrap_width_cell(p, ctx)
    measure_fn = p.measure
    # Each output line is made once and kept while its input line stays.
    lines = IdDict{Any, Any}()
    elements_cv = CellVector(@computation _wrap_lines(text, lines, wrap_w_cell, measure_fn))
    paths = make_output_path_cells(text, path -> path)
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    WordWrappingIoMap(p, text, output)
end

# The width a line wraps at: the maximum of the range the parent gave, exact or
# bounded, cut at `p.max_width`; with neither, a width no line reaches.
const _NO_WRAP_WIDTH = Int(typemax(Int32))

function _wrap_width_cell(p::WordWrapping, ctx)
    limit = something(p.max_width, _NO_WRAP_WIDTH)
    edge = ctx isa PrinterContext ? ctx.maximum_width : nothing
    edge === nothing && return Cell(limit)
    Cell(@computation begin
        v = edge[]
        min(v isa Integer ? max(1, Int(v)) : _NO_WRAP_WIDTH, limit)
    end)
end

# The wrapped lines of `text`: each line maps to itself. Reads only the list of
# lines.
function _wrap_lines(text::TextBlock, lines::IdDict, wrap_w_cell::Cell, measure_fn::TextMeasure)
    out = TextDocument[]
    live = IdDict{Any, Bool}()
    for line in text.elements
        push!(out, get!(() -> _make_wrapped_line(line, wrap_w_cell, measure_fn), lines, line))
        live[line] = true
    end
    for line in collect(keys(lines))
        haskey(live, line) || delete!(lines, line)
    end
    out
end

# The output line of `line`: its spans and every other field, and the soft breaks
# for the width that `wrap_w_cell` holds.
function _make_wrapped_line(line::TextLine, wrap_w_cell::Cell, measure_fn::TextMeasure)
    soft_breaks = Cell(@computation CellVector{Int}(_compute_soft_breaks(line, Int(wrap_w_cell[]), measure_fn)))
    TextLine(getfield(line, :elements), getfield(line, :indentation), getfield(line, :gutter),
             getfield(line, :fold), soft_breaks, getfield(line, :selection),
             getfield(line, :mouse_target))
end

# The width of the indentation of `line`, in the font of its first text span, as
# `TextToGraphics` draws it.
function _measure_indentation(line::TextLine, measure_fn::TextMeasure)
    line.indentation > 0 || return 0
    for span in line.elements
        span isa TextString &&
            return first(compute_text_extent(measure_fn, " " ^ line.indentation, span.font::StyleFont))
    end
    0
end

# The soft breaks of `line` at the wrap width `wrap_w`: a row breaks before a word
# that would pass the width, and the space before that word stays at the end of
# the upper row; an image that would pass it starts a row. Every row starts at the
# indentation of the line, so the width of a row is the width less the
# indentation.
function _compute_soft_breaks(line::TextLine, wrap_w::Int, measure_fn::TextMeasure)
    breaks = Int[]
    width = wrap_w - _measure_indentation(line, measure_fn)
    width > 0 || return breaks
    cx = 0
    offset = 0
    for span in line.elements
        if span isa TextString
            font = span.font::StyleFont
            for (wi, word) in enumerate(split(span.content::AbstractString, ' '; keepempty = true))
                separator = wi == 1 ? "" : " "
                candidate_w = first(compute_text_extent(measure_fn, separator * word, font))
                if cx > 0 && cx + candidate_w > width
                    offset += length(separator)
                    push!(breaks, offset)
                    offset += length(word)
                    cx = first(compute_text_extent(measure_fn, word, font))
                else
                    offset += length(separator) + length(word)
                    cx += candidate_w
                end
            end
        elseif span isa TextGraphics
            image_w = Int(span.width::Int32)
            if cx > 0 && cx + image_w > width
                push!(breaks, offset)
                cx = 0
            end
            offset += 1
            cx += image_w
        else
            offset += get_flat_length(span)
        end
    end
    breaks
end

# ── Selection / reference mapping ───────────────────────────────────────────

map_reference_forward(p::WordWrapping, iomap::WordWrappingIoMap, reference) = reference
map_reference_backward(p::WordWrapping, iomap::WordWrappingIoMap, reference) = reference

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# input and lower it there: in a pure-text pipeline no stage below lowers it.
read_intent(p::WordWrapping, iomap::WordWrappingIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MouseClick) is handled above — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::WordWrapping, ::WordWrappingIoMap, op::Operation) = op

# An element write of the output (the edit beside an inline image) names an output
# line, which is another object than its input line. Decline it: the chain then
# reads the gesture again against the input of this stage.
read_intent(::WordWrapping, ::WordWrappingIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op
