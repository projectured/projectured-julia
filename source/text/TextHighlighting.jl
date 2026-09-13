"""
    TextHighlightingModule

Text → Text projection. The "highlight all" of a search box: keeps every line of
a `TextBlock` and paints a background swatch behind the regex matches by setting
`fill_color` on the matched sub-spans (rendered as a background `GraphicsRect` by
`TextToGraphics`).

It is the structural sibling of `WordWrapping` — both split a `TextString` into
adjacent sub-spans and stay invertible through a piecewise offset table. Here the
split happens at match boundaries and the matched runs are restyled, but no
character is inserted or removed, so `HighlightSegment` is `WrapSegment` and the
selection/reader mapping is identical. Matching is per span (the same
span-delimited simplification as `TextFiltering`); a `nothing` pattern is a
pass-through (no highlights), so the projection can sit idle in a pipeline until
a pattern is set on the reactive `pattern` cell.
"""
module TextHighlightingModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextBlock, TextDocument, TextString, convert_flat_offset_to_element, convert_element_to_flat_offset, get_flat_caret
import ..TextRangeReferenceStepModule: TextRangeReferenceStep
import ..StyleModule: StyleColor, color_yellow
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, RangeReferenceStep, FieldReferenceStep, EmptyReference, strip_reference_types, Position
import ..TextSpanReferenceStepModule: TextSpanReferenceStep
import ..ReferenceModule: var"@reference"
import ..OperationModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
export TextHighlighting, TextHighlightingIoMap, HighlightSegment

# ── Projection struct ───────────────────────────────────────────────────────

"""
    TextHighlighting(pattern; color=color_yellow)
    TextHighlighting(; pattern=nothing, color=color_yellow)

Paint a background swatch behind every match of `pattern` (a `Regex`, a pattern
string, a `Cell` holding either, or `nothing`).

`pattern` is held in a reactive `Cell`, so updating it re-highlights live; a
`nothing` pattern adds no highlights. `color` is the `fill_color` set on matched
sub-spans (glyph color is left untouched so matched text stays readable). Regex
flags live in the `Regex` the caller builds.
"""
struct TextHighlighting <: Projection
    pattern::Cell          # Cell holding the source String | Regex | nothing — reactive
    case_insensitive::Cell # Cell{Bool} — reactive; adds the `i` flag when a source String is compiled
    color::StyleColor
end

TextHighlighting(pattern::Cell; case_insensitive=false, color::StyleColor=color_yellow) =
    TextHighlighting(pattern, case_insensitive isa Cell ? case_insensitive : Cell(case_insensitive), color)
TextHighlighting(pattern::Regex; kw...) = TextHighlighting(Cell(pattern); kw...)
TextHighlighting(pattern::AbstractString; kw...) = TextHighlighting(Cell(String(pattern)); kw...)
TextHighlighting(; pattern=nothing, kw...) =
    TextHighlighting(pattern isa Cell ? pattern : Cell(pattern); kw...)

# Normalise the (reactive) pattern cell value into the `Union{Regex,Nothing}` the
# highlighter consumes. `nothing` / empty source ⇒ no highlights (pass-through); a
# source `String` is compiled (with the `i` flag when `case_insensitive`); a `Regex`
# is used verbatim — flags it carries win, so it ignores `case_insensitive`.
function _effective_pattern(value, case_insensitive::Bool)
    value === nothing && return nothing
    value isa Regex && return value
    s = String(value)
    isempty(s) && return nothing
    case_insensitive ? Regex(s, "i") : Regex(s)
end

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    HighlightSegment(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span. `out_index` is its 1-based
position in `output.elements`; `in_span` is the 1-based originating input span;
`in_char_start` is the 0-based char offset of this sub-span within the input
span; `length` is its character count.
"""
struct HighlightSegment
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

@iomap struct TextHighlightingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    segs::Cell  # Cell{Vector{HighlightSegment}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::TextHighlighting, recursion, text::TextBlock, ctx)
    pattern_cell = p.pattern
    ci_cell = p.case_insensitive
    color = p.color
    both = ComputedCell(() -> _highlight(text, _effective_pattern(pattern_cell[], ci_cell[]), color))   # (elements, segs)
    elements_cv = ComputedCellVector(() -> both[][1])
    segs_cell = ComputedCell(() -> both[][2])
    out_selection = ComputedCell(() -> _forward_map(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), text.selection))
    output = TextBlock(elements_cv, out_selection)
    TextHighlightingIoMap(p, text, output, segs_cell)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{HighlightSegment}).
# A `nothing` pattern keeps every span unchanged (identity). Otherwise each
# TextString is split at match boundaries into alternating unmatched / matched
# sub-spans, matched runs carrying the highlight fill. Non-text elements pass
# through untouched.
function _highlight(text::TextBlock, pattern, color::StyleColor)
    result = TextDocument[]
    segs = HighlightSegment[]
    fill_cell = Cell(color)
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            if pattern === nothing
                push!(result, elem)
                push!(segs, HighlightSegment(length(result), in_span, 0, length(elem.content::AbstractString)))
            else
                _highlight_string!(result, segs, elem, in_span, pattern, fill_cell)
            end
        else
            push!(result, elem)
        end
    end
    (result, segs)
end

# Split one input TextString at the (non-empty) matches of `pattern`, appending
# output sub-spans + HighlightSegment entries. Works in character space (via a
# byte→char map) so multi-byte content is handled correctly. A span with no
# match is emitted unchanged (original object reused) with one full-length seg.
function _highlight_string!(result::Vector{TextDocument}, segs::Vector{HighlightSegment},
                            original::TextString, in_span::Int, pattern::Regex, fill_cell::Cell)
    content = original.content::AbstractString
    if isempty(content)
        push!(result, original)
        push!(segs, HighlightSegment(length(result), in_span, 0, 0))
        return
    end
    total_chars = length(content)
    # 0-based char offset for each byte index that starts a character.
    byte_to_char0 = Dict{Int,Int}()
    for (ci, bi) in enumerate(eachindex(content))
        byte_to_char0[bi] = ci - 1
    end
    # Matched runs as (char_start0, char_len), in order, non-overlapping.
    runs = Tuple{Int,Int}[]
    for m in eachmatch(pattern, content)
        isempty(m.match) && continue          # skip zero-width matches
        push!(runs, (byte_to_char0[m.offset], length(m.match)))
    end
    if isempty(runs)
        push!(result, original)
        push!(segs, HighlightSegment(length(result), in_span, 0, total_chars))
        return
    end

    chars = collect(content)
    orig_fill = getfield(original, :fill_color)
    emit(start0, len, fill) = begin
        push!(result, _make_span(original, String(chars[start0+1 : start0+len]), fill))
        push!(segs, HighlightSegment(length(result), in_span, start0, len))
    end

    cursor = 0
    for (start0, len) in runs
        start0 > cursor && emit(cursor, start0 - cursor, orig_fill)  # unmatched gap
        emit(start0, len, fill_cell)                                 # highlighted run
        cursor = start0 + len
    end
    cursor < total_chars && emit(cursor, total_chars - cursor, orig_fill)  # trailing gap
    return
end

# Build an output sub-span: copy the original style, override `fill_color`.
function _make_span(original::TextString, content::AbstractString, fill_color::Cell)
    TextString(Cell(String(content)),
               getfield(original, :font),
               getfield(original, :font_color),
               fill_color,
               getfield(original, :line_color),
               getfield(original, :padding),
               Cell(nothing))
end

# ── Selection / reference mapping ───────────────────────────────────────────
# Identical to WordWrapping: the seg table is a piecewise-linear char-offset map.

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
# flat character space, which highlighting leaves unchanged, so they map
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
    flat = get_flat_caret(in_block, sel)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(in_block, flat)
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
    f = convert_element_to_flat_offset(out_block, best.out_index, in_char - best.in_char_start)
    f === nothing ? nothing : _flat_caret(f)
end

map_reference_forward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference) =
    _forward_map(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference)
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

function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Translate a `ReplaceStringRangeOperation` from the split output domain back to
# the unwrapped input domain, shifting the char range by the sub-span's start.
function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplaceStringRangeOperation)
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
# unchanged; a raw gesture (KeyPress/KeyDown/MousePress) falls through to the
# base `Projection.read_intent` which delegates via `read_gesture(input, evt)`.
read_intent(::TextHighlighting, ::TextHighlightingIoMap, op::Operation) = op

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

# Like `_parse_text_elem_path` but returns the full terminal `(span, start, stop)`.
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
