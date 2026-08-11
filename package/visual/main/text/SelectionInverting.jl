"""
    SelectionInvertingModule

Text → Text projection. Bakes the input `TextBlock`'s own selection into the
spans as **inverse video** — swapping `font_color` ↔ `fill_color` over the
selected character range, and widening a zero-width caret to a one-character
block. Because the selection becomes ordinary span color, any backend that
renders the Text domain shows it; in particular the console backend, which
renders `TextBlock` straight to the terminal and has no separate cursor/highlight
layer the way `TextToGraphics` does.

It is the structural twin of `TextHighlighting`: both split `TextString`s at
boundaries and restyle the resulting sub-spans **without** inserting or removing
any character, so the selection/reader mapping is a piecewise offset table
(`SelSeg`, the same shape as `HighlightSeg`). The only differences are the
*segmentation source* (the input's own selection range vs regex matches) and the
*restyle* (swap colors vs set a fill swatch). A `nothing`/absent selection is a
pass-through (identity).

Do **not** insert this into the SDL/web graphics pipeline: those already draw a
cursor/selection rect in `TextToGraphics` and would double up. It is for
Text-domain backends (console), opt-in elsewhere.
"""
module SelectionInvertingModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextBlock, TextDocument, TextString, text_flat_length, text_selection_flat, text_flat_to_elem, text_elem_to_flat, text_caret_flat
import ..TextRangeReferenceStepModule: TextRangeReferenceStep
import ..ColorModule: StyleColor, color_solarized_background_dark, color_solarized_content_lighter
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, RangeReferenceStep, FieldReferenceStep, EmptyReference, strip_reference_types, Position
import ..TextSpanReferenceStepModule: TextSpanReferenceStep
import ..ReferenceBuilderModule: var"@reference"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
export SelectionInverting, SelectionInvertingIoMap, SelSeg

# ── Projection struct ───────────────────────────────────────────────────────

"""
    SelectionInverting(; default_bg=color_solarized_background_dark,
                         default_fg=color_solarized_content_lighter,
                         block_cursor=true)

Encode the input `TextBlock`'s selection into span colors as inverse video.

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

SelectionInverting(; default_bg::StyleColor=color_solarized_background_dark,
                     default_fg::StyleColor=color_solarized_content_lighter,
                     block_cursor::Bool=true) =
    SelectionInverting(default_bg, default_fg, block_cursor)

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    SelSeg(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span (identical in shape to
`HighlightSeg`). `out_index` is its 1-based position in `output.elements`;
`in_span` is the 1-based originating input span; `in_char_start` is the 0-based
char offset of this sub-span within the input span; `length` is its char count.
"""
struct SelSeg
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

@iomap struct SelectionInvertingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    segs::Cell  # Cell{Vector{SelSeg}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::SelectionInverting, recursion, text::TextBlock, ctx)
    both = ComputedCell(() -> _invert(p, text))   # (elements, segs)
    elements_cv = ComputedCellVector(() -> both[][1])
    segs_cell = ComputedCell(() -> both[][2])
    out_selection = ComputedCell(() -> _forward_map(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), text.selection))
    output = TextBlock(elements_cv, out_selection)
    SelectionInvertingIoMap(p, text, output, segs_cell)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{SelSeg}).
# When there is no renderable selection every span is emitted unchanged
# (identity); otherwise each span overlapping the selected flat range is split at
# the boundaries and the in-range sub-spans are restyled to inverse video. No
# character is inserted or removed, so `SelSeg` is a piecewise offset map.
function _invert(p::SelectionInverting, text::TextBlock)
    sel = text_selection_flat(text)
    # Widen a zero-width caret to a one-char block so it is visible.
    hl = sel === nothing ? nothing :
         (sel[3] && p.block_cursor) ? (sel[1], sel[1] + 1) : (sel[1], sel[2])

    result = TextDocument[]
    segs = SelSeg[]
    base = 0   # flat char offset of the current span's start
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            base = _invert_string!(p, result, segs, elem, in_span, base, hl)
        else
            push!(result, elem)
            base += text_flat_length(elem)
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
            push!(segs, SelSeg(length(result), length(text.elements), base, 1))
        end
    end
    (result, segs)
end

# Split one input TextString at the selection boundaries, appending output
# sub-spans + SelSeg entries; restyle the in-range portion to inverse video.
# Returns the flat offset after this span.
function _invert_string!(p::SelectionInverting, result::Vector{TextDocument},
                         segs::Vector{SelSeg}, original::TextString, in_span::Int,
                         base::Int, hl)
    content = original.content::AbstractString
    L = length(content)
    emit_unchanged() = begin
        push!(result, original)
        push!(segs, SelSeg(length(result), in_span, 0, L))
    end
    if L == 0
        push!(result, original)
        push!(segs, SelSeg(length(result), in_span, 0, 0))
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
        push!(segs, SelSeg(length(result), in_span, start0, len))
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

# The flat caret offset of a `TextRangeReferenceStep` selection (or `nothing`), and the
# flat caret path for an offset. `∅` / `TextSpanReferenceStep` shapes are handled
# by `_is_structural_ref` before these are reached.
function _text_range_caret(ref)
    r = strip_reference_types(ref)
    r isa ConcreteReference && r.head isa TextRangeReferenceStep &&
        r.tail isa EmptyReference && r.head.start == r.head.stop || return nothing
    r.head.start::Int
end
_flat_caret(f::Int) = ConcreteReference(TextRangeReferenceStep(f, f), EmptyReference())

# A whole-element selection at this layer is either `∅` (the whole text) or a
# `TextSpanReferenceStep(s,e)…∅` box over a flat character range — the same
# two shapes `SyntaxToText` emits and `TextToGraphics` highlights. Both index the
# flat character space, which inversion leaves unchanged, so they map
# identically in either direction.
_is_structural_ref(ref) =
    ref isa EmptyReference ||
    (ref isa ConcreteReference && ref.head isa TextSpanReferenceStep)

# Forward: rebuild an input flat caret against the split output by finding the
# sub-span the cursor falls into. At the exact boundary between two sub-spans
# of the same input span, prefer the start of the next sub-span.
# input flat caret → output flat caret, over the seg table. Takes the blocks
# explicitly so `print_document` can compute the output selection before the
# `IoMap` exists.
function _forward_map(segs, in_block, out_block, sel)
    _is_structural_ref(sel) && return sel
    # Resolve either caret form (flat `TextRangeReferenceStep{k}` or structural
    # `.elements[i].content{k}`); a flat-only read drops the cursor after an edit.
    flat = text_caret_flat(in_block, sel)
    flat === nothing && return nothing
    loc = text_flat_to_elem(in_block, flat)
    loc === nothing && return nothing
    in_span, in_char = loc
    best = nothing
    for seg in segs
        seg.in_span == in_span || continue
        if seg.in_char_start <= in_char <= seg.in_char_start + seg.length
            best = seg
            # Prefer the start of the next sub-span at the split boundary.
            in_char == seg.in_char_start && seg.in_char_start != 0 && break
        end
    end
    best === nothing && return nothing
    f = text_elem_to_flat(out_block, best.out_index, in_char - best.in_char_start)
    f === nothing ? nothing : _flat_caret(f)
end

map_reference_forward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference) =
    _forward_map(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::SelectionInverting, iomap::SelectionInvertingIoMap, reference)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = text_flat_to_elem(iomap.output, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    for seg in iomap.segs
        seg.out_index == out_span || continue
        f = text_elem_to_flat(iomap.input, seg.in_span, seg.in_char_start + out_char)
        return f === nothing ? nothing : _flat_caret(f)
    end
    nothing
end

function read_intent(p::SelectionInverting, iomap::SelectionInvertingIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
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
read_intent(::SelectionInverting, ::SelectionInvertingIoMap, op) = nothing

# ── Path helpers ────────────────────────────────────────────────────────────

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference ::TextBlock.elements::CellVector[span_idx]::TextString.content::String{char_idx}::Position

function _parse_text_elem_path(path)
    path = strip_reference_types(path)
    path isa ConcreteReference || return nothing
    h1 = path.head
    h1 isa FieldReferenceStep && h1.name == "elements" || return nothing
    t1 = path.tail
    t1 isa ConcreteReference || return nothing
    h2 = t1.head
    h2 isa RangeReferenceStep || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReference || return nothing
    h3 = t2.head
    h3 isa FieldReferenceStep && h3.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReference || return nothing
    h4 = t3.head
    h4 isa RangeReferenceStep || return nothing
    (span_idx, h4.start::Int)
end

function _parse_text_elem_range(path)
    path = strip_reference_types(path)
    path isa ConcreteReference || return nothing
    h1 = path.head
    h1 isa FieldReferenceStep && h1.name == "elements" || return nothing
    t1 = path.tail
    t1 isa ConcreteReference || return nothing
    h2 = t1.head
    h2 isa RangeReferenceStep || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReference || return nothing
    h3 = t2.head
    h3 isa FieldReferenceStep && h3.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReference || return nothing
    h4 = t3.head
    h4 isa RangeReferenceStep || return nothing
    (span_idx, h4.start::Int, h4.stop::Int)
end

end # module
