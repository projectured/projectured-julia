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
# It is the structural twin of `TextHighlighting`: both split `TextString`s at
# boundaries and restyle the resulting sub-spans **without** inserting or removing
# any character, so the selection/reader mapping is a piecewise offset table
# (`SelectionSegment`, the same shape as `HighlightSegment`). The only differences are the
# *segmentation source* (the input's own selection range vs regex matches) and the
# *restyle* (swap colors vs set a fill swatch). A `nothing`/absent selection is a
# pass-through (identity).
#
# Do **not** insert this into the SDL/web graphics pipeline: those already draw a
# cursor/selection rect in `TextToGraphics` and would double up. It is for
# Text-domain backends (console), opt-in elsewhere.
# ── Projection struct ───────────────────────────────────────────────────────

"""
    SelectionInverting(; theme = nothing, default_bg, default_fg, block_cursor = true)

Encode the input `TextBlock`'s selection into span colors as inverse video.

  - `theme` — a `TextTheme` or a scaled one, whose `inverted_background` and
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

One entry per emitted output `TextString` sub-span (identical in shape to
`HighlightSegment`). `out_index` is its 1-based position in `output.elements`;
`in_span` is the 1-based originating input span; `in_char_start` is the 0-based
char offset of this sub-span within the input span; `length` is its char count.
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
    segs::Cell  # Cell{Vector{SelectionSegment}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::SelectionInverting, recursion, text::TextBlock, ctx)
    both = Cell(@computation _invert(p, text))   # (elements, segs)
    elements_cv = CellVector(@computation both[][1])
    segs_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(text, path ->
        _forward_map(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    SelectionInvertingIoMap(p, text, output, segs_cell)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{SelectionSegment}).
# When there is no renderable selection every span is emitted unchanged
# (identity); otherwise each span overlapping the selected flat range is split at
# the boundaries and the in-range sub-spans are restyled to inverse video. No
# character is inserted or removed, so `SelectionSegment` is a piecewise offset map.
function _invert(p::SelectionInverting, text::TextBlock)
    sel = get_flat_selection(text)
    # Widen a zero-width caret to a one-char block so it is visible.
    hl = sel === nothing ? nothing :
         (sel[3] && p.block_cursor) ? (sel[1], sel[1] + 1) : (sel[1], sel[2])

    result = TextDocument[]
    segs = SelectionSegment[]
    base = 0   # flat char offset of the current span's start
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            base = _invert_string!(p, result, segs, elem, in_span, base, hl)
        else
            push!(result, elem)
            # An inline image is one position: the carets before and after it map.
            elem isa TextGraphics && push!(segs, SelectionSegment(length(result), in_span, 0, 1))
            base += get_flat_length(elem)
        end
    end
    # End-of-text caret: the selection sits one past the last char. Synthesize a
    # trailing inverted space so the block caret stays visible.
    if hl !== nothing && hl[1] >= base && hl[2] > base && !isempty(result)
        last_span = nothing
        for e in result
            e isa TextString && (last_span = e)
        end
        if last_span !== nothing
            push!(result, _invert_span(p, last_span, " "))
            push!(segs, SelectionSegment(length(result), length(text.elements), base, 1))
        end
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
               Cell(nothing))
end

# ── Selection / reference mapping ───────────────────────────────────────────
# Identical to TextHighlighting: the seg table is a piecewise-linear offset map.

map_reference_forward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference) =
    _forward_map(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(iomap.output, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    for seg in iomap.segs
        seg.out_index == out_span || continue
        f = convert_element_to_flat_offset(iomap.input, seg.in_span, seg.in_char_start + out_char)
        return f === nothing ? nothing : _flat_caret(f)
    end
    nothing
end

function read_intent(p::SelectionInverting, iomap::SelectionInvertingIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# Translate a `ReplaceStringRangeOperation` from the split output domain back to
# the un-split input domain, shifting the char range by the sub-span's start.
function read_intent(p::SelectionInverting, iomap::SelectionInvertingIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    out_span, char_start, char_stop = parsed
    for seg in iomap.segs
        seg.out_index == out_span || continue
        new_start = seg.in_char_start + char_start
        new_stop  = seg.in_char_start + char_stop
        new_ref = ConcreteReference(FieldReferenceStep("elements"),
                      ConcreteReference(RangeReferenceStep(seg.in_span - 1, seg.in_span),
                          ConcreteReference(FieldReferenceStep("content"),
                              ConcreteReference(RangeReferenceStep(new_start, new_stop),
                                                    EmptyReference()))))
        return ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    nothing
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

# ── Path helpers ────────────────────────────────────────────────────────────
