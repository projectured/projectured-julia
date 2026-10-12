# Fragment of `TextModule`.
#
# Text → Text projection. Bakes the input `TextBlock`'s own selection into the
# spans as **inverse video** — swapping `font_color` ↔ `fill_color` over the
# selected character range, and widening a zero-width caret to a one-character
# block. Because the selection becomes ordinary span color, any backend that
# renders the Text domain shows it; in particular the console backend, which
# renders `TextBlock` straight to the terminal and has no separate cursor/highlight
# layer the way `TextToGraphics` does.
#
# It is the structural twin of `HighlightedTextToText`: both split `TextString`s at
# boundaries and restyle the resulting sub-spans **without** inserting or removing
# any character, so the selection/reader mapping is a piecewise offset table
# (`SelectionSegment`, the same shape as `HighlightSegment`). The only differences are the
# *segmentation source* (the input's own selection range vs regex matches) and the
# *restyle* (swap colors vs set a fill swatch). A `nothing`/absent selection is a
# pass-through (identity).
#
# A line that the selection touches gets new spans, and every other line is the
# same object. No character is inserted, so every flat offset
# stays: a caret, a range and a box map to themselves, and only a path into a span
# of a line maps through the segments of its line. A block caret at the end of a
# line inverts a space after the line, as one at the end of the text does.
#
# Do **not** insert this into the SDL/web graphics pipeline: those already draw a
# cursor/selection rect in `TextToGraphics` and would double up. It is for
# Text-domain backends (console), opt-in elsewhere.
# ── Projection struct ───────────────────────────────────────────────────────

"""
    SelectionInverting(; theme = nothing, default_bg, default_fg, block_cursor = true)

Encode the input `TextBlock`'s selection into span colors as inverse video.

  - `theme` — a `TextTheme`, scaled or not, whose `inverted_background` and
    `inverted_foreground` are the defaults of the two colors.
  - `default_bg` — concrete background color used as the inverted *foreground*
    when the original span has no `fill_color`. Inversion needs an explicit
    background (unlike a terminal's `\\e[7m`, which swaps against the default), so
    the highlight renders identically across all backends.
  - `default_fg` — color used as the inverted *background* when the original
    span has no `font_color`.
  - `block_cursor` — when `true` (default), a zero-width caret is widened to a
    one-character block by inverting the next glyph (or a synthesized trailing
    space at end-of-text), matching the console's block-cursor behaviour.

There is no pattern cell: the trigger is the input's own selection, so the
projection is stateless beyond its style options.
"""
@projection struct SelectionInverting <: Projection
    default_bg::ImmutableCell{StyleColor}
    default_fg::ImmutableCell{StyleColor}
    block_cursor::ImmutableCell{Bool}
end

SelectionInverting(; theme = nothing,
                     default_bg::StyleColor = unwrap_cell(get_text_style(theme, :inverted_background)),
                     default_fg::StyleColor = unwrap_cell(get_text_style(theme, :inverted_foreground)),
                     block_cursor::Bool=true) =
    SelectionInverting(default_bg, default_fg, block_cursor)

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    SelectionSegment(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span of a split line (identical in
shape to `HighlightSegment`). `out_index` is its 1-based position in the spans of
the output line; `in_span` is the 1-based originating span of the input line;
`in_char_start` is the 0-based char offset of this sub-span within the input span;
`length` is its char count.
"""
struct SelectionSegment
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

@iomap struct SelectionInvertingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    # Cell{Vector{Pair{Int,Vector{SelectionSegment}}}}: each line that is split =>
    # the segments of its spans, whose indices count in the line.
    segs::Cell
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::SelectionInverting, recursion, text::TextBlock, ctx)
    both = Cell(@computation _invert_lines(p, text))
    elements_cv = CellVector(@computation both[][1])
    segs_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(text, path -> _map_line_path(segs_cell[], path, true))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    SelectionInvertingIoMap(p, text, output, segs_cell)
end

# The flat range that the selection of `text` inverts, `(start, stop)`, and whether
# it is a caret widened to a block; `nothing` when there is no selection.
function _get_inverted_range(p::SelectionInverting, text::TextBlock)
    sel = get_flat_selection(text)
    sel === nothing && return nothing
    is_block = sel[3] && p.block_cursor
    (start = sel[1], stop = is_block ? sel[1] + 1 : sel[2], is_block = is_block)
end

# The output lines and the segments of each line that is split: `(lines, segs)`.
# Each span that overlaps the selected flat range is split at its boundaries, and
# the selected sub-spans are restyled to inverse video. No character is inserted
# or removed, so the segments are a piecewise offset map of each split line.
function _invert_lines(p::SelectionInverting, text::TextBlock)
    range = _get_inverted_range(p, text)
    hl = range === nothing ? nothing : (range.start, range.stop)
    result = TextDocument[]
    segs = Pair{Int,Vector{SelectionSegment}}[]
    offsets = get_flat_offsets(text)
    for (i, line) in enumerate(text.elements)
        base = offsets[i] + line.indentation
        stop = base + sum(get_flat_length(span) for span in line.elements; init = 0)
        at_end = range !== nothing && range.is_block && range.start == stop
        if hl === nothing || (!at_end && (hl[2] <= base || hl[1] >= stop))
            push!(result, line)
            continue
        end
        spans = TextDocument[]
        line_segs = SelectionSegment[]
        for (j, span) in enumerate(line.elements)
            if span isa TextString
                base = _invert_string!(p, spans, line_segs, span, j, base, hl)
            else
                push!(spans, span)
                span isa TextGraphics && push!(line_segs, SelectionSegment(length(spans), j, 0, 1))
                base += get_flat_length(span)
            end
        end
        if at_end
            last_span = findlast(span -> span isa TextString, spans)
            last_span === nothing || push!(spans, _invert_span(p, spans[last_span], " "))
        end
        push!(result, _make_line_with_spans(line, spans))
        push!(segs, i => line_segs)
    end
    (result, segs)
end

# Split one input TextString at the selection boundaries, appending output
# sub-spans + SelectionSegment entries; restyle the in-range portion to inverse video.
# Returns the flat offset after this span.
function _invert_string!(p::SelectionInverting, result::Vector{TextDocument},
                         segs::Vector{SelectionSegment}, original::TextString, in_span::Int,
                         base::Int, hl)
    content = original.content::AbstractString
    L = length(content)
    emit_unchanged() = begin
        push!(result, original)
        push!(segs, SelectionSegment(length(result), in_span, 0, L))
    end
    if L == 0
        push!(result, original)
        push!(segs, SelectionSegment(length(result), in_span, 0, 0))
        return base
    end
    if hl === nothing
        emit_unchanged()
        return base + L
    end
    hs, he = hl
    # Overlap of [hs, he) with this span's [base, base+L), in span-local chars.
    lo = clamp(hs - base, 0, L)
    hi = clamp(he - base, 0, L)
    if lo >= hi
        emit_unchanged()        # no overlap → unchanged single span
        return base + L
    end
    chars = collect(content)
    emit(start0, len, inverted) = begin
        seg_chars = chars[start0+1 : start0+len]
        span = inverted ? _invert_span(p, original, String(seg_chars)) :
                          _restyle_span(original, String(seg_chars))
        push!(result, span)
        push!(segs, SelectionSegment(length(result), in_span, start0, len))
    end
    lo > 0   && emit(0, lo, false)            # leading unselected
    emit(lo, hi - lo, true)                   # selected → inverted
    hi < L   && emit(hi, L - hi, false)       # trailing unselected
    return base + L
end

# Build an output sub-span carrying the original style with new content.
function _restyle_span(original::TextString, content::AbstractString)
    TextString(Cell(String(content)),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               getfield(original, :pointer_shape),
               Cell(nothing))
end

# Build an inverted sub-span: swap font_color ↔ fill_color, using the projection
# defaults where a color is absent (inversion needs explicit colors).
function _invert_span(p::SelectionInverting, original::TextString, content::AbstractString)
    old_fg = getfield(original, :font_color)[]
    old_bg = getfield(original, :fill_color)[]
    new_fg = old_bg isa StyleColor ? old_bg : p.default_bg
    new_bg = old_fg isa StyleColor ? old_fg : p.default_fg
    TextString(Cell(String(content)),
               getfield(original, :font),
               Cell(new_fg),
               Cell(new_bg),
               getfield(original, :line_color),
               getfield(original, :padding),
               getfield(original, :pointer_shape),
               Cell(nothing))
end

# ── Selection / reference mapping ───────────────────────────────────────────
# As in HighlightedTextToText: a path into a span of a split line maps through the
# segments of that line, and every other path stays.

map_reference_forward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference) =
    _map_line_path(iomap.segs, reference, true)

map_reference_backward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference) =
    _map_line_path(iomap.segs, reference, false)

function read_intent(p::SelectionInverting, iomap::SelectionInvertingIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# Translate a `ReplaceStringRangeOperation` from the split output domain back to
# the un-split input domain, across the segments of its line.
function read_intent(p::SelectionInverting, iomap::SelectionInvertingIoMap, op::ReplaceStringRangeOperation)
    reference = _map_line_path(iomap.segs, op.reference, false)
    reference === nothing ? nothing : ReplaceStringRangeOperation(reference, op.replacement)
end

# Forward any Operation (ToggleCollapseOperation, collection ops, etc.) upstream
# unchanged. Raw gestures (KeyDown, KeyPress, …) return nothing so the
# ChainingProjection tries earlier steps (e.g. SyntaxToText's console fallback).
read_intent(::SelectionInverting, ::SelectionInvertingIoMap, op::Operation) = op

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::SelectionInverting, ::SelectionInvertingIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op
read_intent(::SelectionInverting, ::SelectionInvertingIoMap, op) = nothing
