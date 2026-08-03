"""
    WordWrappingModule

Text → Text projection. Pixel-accurate word wrapping: splits a TextString into
sub-spans at word boundaries and inserts `TextNewline` elements where a word
would push the column past the wrap width. The wrap width is taken from
`ctx.available_width` when present (so a resize re-wraps reactively), falling
back to the projection's `max_width`.

Character preservation: the projection is structural only — every character of
the input survives in the output, exactly once and in order. A space that
lands at a wrap boundary stays as the last character of the previous visual
line. This makes the projection invertible by a clean piecewise-linear offset
table (`WordWrappingIoMap.segs`), used by selection mapping and the reader.
"""
module WordWrappingModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextBlock, TextDocument, TextString, TextNewline, TextGraphics, text_flat_to_elem, text_elem_to_flat, text_caret_flat, ReplaceTextRangeOperation, _lower_text_range
import ..TextRangeReferenceStepModule: TextRangeReferenceStep
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..IoMapModule: IoMap, var"@iomap"
import ..PrinterContextModule: PrinterContext
import ..ReferenceModule: ConcreteReference, RangeReferenceStep, FieldReferenceStep, EmptyReference, Reference, strip_reference_types, Position
import ..TextSpanReferenceStepModule: TextSpanReferenceStep
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyDown, KeyPress
export WordWrapping, WordWrappingIoMap, WrapSeg

# ── Projection struct ───────────────────────────────────────────────────────

"""
    WordWrapping(; max_width=800, measure)

Pixel-based word-wrap projection. `measure(text, font) -> (width, height)`
matches the downstream `TextToGraphics` measurer so wrap points line up with
layout. `max_width` is the pixel fallback used when no `available_width` is
present on the context.
"""
struct WordWrapping <: Projection
    max_width::Int
    measure::Function
end

WordWrapping(; max_width::Int = 800, measure::Function) =
    WordWrapping(max_width, measure)

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    WrapSeg(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span. `out_index` is the 1-based
position of the sub-span in `output.elements`. `in_span` is the 1-based index
of the originating input span. `in_char_start` is the 0-based character offset
of this sub-span within the input span; `length` is its character count.
Inserted soft `TextNewline`s have no `WrapSeg`.
"""
struct WrapSeg
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

@iomap struct WordWrappingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    segs::Cell  # Cell{Vector{WrapSeg}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::WordWrapping, recursion, text::TextBlock, ctx)
    wrap_w_cell = _wrap_width_cell(p, ctx)
    measure_fn = p.measure
    both = ComputedCell(() -> _wrap(text, Int(wrap_w_cell[]), measure_fn))
    elements_cv = ComputedCellVector(() -> both[][1])
    segs_cell = ComputedCell(() -> both[][2])
    out_selection = ComputedCell(() -> _forward_map(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), text.selection))
    output = TextBlock(elements_cv, out_selection)
    WordWrappingIoMap(p, text, output, segs_cell)
end

function _wrap_width_cell(p::WordWrapping, ctx)
    if ctx isa PrinterContext && ctx.available_width !== nothing
        aw = ctx.available_width
        fallback = p.max_width
        return ComputedCell(() -> begin
            v = aw[]
            v isa Integer ? max(1, Int(v)) : fallback
        end)
    end
    Cell(p.max_width)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{WrapSeg}).
function _wrap(text::TextBlock, wrap_w::Int, measure_fn::Function)
    result = TextDocument[]
    segs = WrapSeg[]
    cx = 0
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            cx = _wrap_string!(result, segs, elem, in_span, cx, wrap_w, measure_fn)
        elseif elem isa TextNewline
            push!(result, elem)
            cx = 0
        elseif elem isa TextGraphics
            cx = _wrap_graphics!(result, segs, elem, in_span, cx, wrap_w)
        else
            push!(result, elem)
        end
    end
    (result, segs)
end

# Wraps one input TextString span, appending output sub-spans (and soft
# newlines) to `result` and the corresponding `WrapSeg` entries to `segs`.
# Returns the updated column offset.
function _wrap_string!(result::Vector{TextDocument}, segs::Vector{WrapSeg},
                       original::TextString, in_span::Int,
                       cx::Int, wrap_w::Int, measure_fn::Function)
    content = original.content::AbstractString
    isempty(content) && return cx
    font = getfield(original, :font)[]
    # Split on embedded \n first so hard newlines reset the column without
    # leaving wrap math to chew through them as if they were horizontal.
    in_char = 0          # 0-based offset within input span
    sub_start = in_char  # input char offset where the current accumulating
                         # output sub-span begins
    buf = IOBuffer()
    lines = split(content, '\n'; keepempty=true)
    for (li, line) in enumerate(lines)
        if li > 1
            # Consume the '\n' as a character within the current sub-span.
            # TextToGraphics handles embedded '\n' in a TextString as a hard
            # line break, so cx resets without an extra TextNewline element.
            print(buf, '\n')
            in_char += 1
            cx = 0
        end
        # Tokenize the line into words separated by single spaces.
        words = split(line, ' '; keepempty=true)
        for (wi, word) in enumerate(words)
            sep = wi == 1 ? "" : " "
            cand = sep * word
            cand_w = first(measure_fn(cand, font))
            if cx > 0 && wrap_w > 0 && cx + cand_w > wrap_w
                # Wrap before this word. The leading space (if any) stays at
                # the tail of the previous visual line so every input
                # character has exactly one home in the output.
                if !isempty(sep)
                    print(buf, sep)
                    in_char += length(sep)
                end
                _flush!(result, segs, original, in_span, sub_start, buf)
                push!(result, _make_newline(original))
                cx = 0
                sub_start = in_char
                print(buf, word)
                in_char += length(word)
                cx += first(measure_fn(word, font))
            else
                print(buf, cand)
                in_char += length(cand)
                cx += cand_w
            end
        end
    end
    _flush!(result, segs, original, in_span, sub_start, buf)
    return cx
end

# Place a TextGraphics image as a single unbreakable token. If it would
# overflow the current visual line, insert a soft TextNewline before it so the
# image drops whole onto the next line (it is never split). The image keeps its
# single atomic cursor range [0, 1), recorded as a zero-based WrapSeg so
# selection mapping can locate it in the wrapped output. Returns the updated
# column offset.
function _wrap_graphics!(result::Vector{TextDocument}, segs::Vector{WrapSeg},
                         image::TextGraphics, in_span::Int, cx::Int, wrap_w::Int)
    img_w = Int(image.width::Int32)
    if cx > 0 && wrap_w > 0 && cx + img_w > wrap_w
        push!(result, _make_image_newline(image))
        cx = 0
    end
    push!(result, image)
    push!(segs, WrapSeg(length(result), in_span, 0, 1))
    return cx + img_w
end

function _make_image_newline(image::TextGraphics)
    TextNewline(font=image.font,
                font_color=image.font_color,
                fill_color=image.fill_color,
                line_color=image.line_color,
                padding=image.padding)
end

function _flush!(result::Vector{TextDocument}, segs::Vector{WrapSeg},
                 original::TextString, in_span::Int, sub_start::Int, buf::IOBuffer)
    s = String(take!(buf))
    isempty(s) && return
    push!(result, _make_span(original, s))
    push!(segs, WrapSeg(length(result), in_span, sub_start, length(s)))
end

function _make_span(original::TextString, content::String)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               Cell(nothing))
end

function _make_newline(original::TextString)
    TextNewline(font=original.font,
                font_color=original.font_color,
                fill_color=original.fill_color,
                line_color=original.line_color,
                padding=original.padding)
end

# ── Selection / reference mapping ───────────────────────────────────────────

# Forward: rebuild an input cursor `elements[s].content{c}` against the
# wrapped output by finding the sub-span the cursor falls into. At the exact
# boundary between two consecutive sub-spans of the same input span (the
# cursor sitting between a wrap), prefer the start of the next visual line —
# matches the boundary-duplicate convention in TextToGraphics.
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

# input flat caret → output flat caret, over the seg table. Takes the blocks
# explicitly so `print_document` can compute the output selection before the
# `IoMap` exists (structural ∅ / `TextSpanReferenceStep` pass through: the flat
# character space is wrap-invariant since soft `TextNewline`s are not counted).
function _forward_map(segs, in_block, out_block, sel)
    _is_structural_ref(sel) && return sel
    # Accept either caret representation: the flat `TextRangeReferenceStep{k}` or the
    # structural `.elements[i].content{k}` a lowered edit leaves on the input block.
    # A flat-only read here drops the cursor the moment an edit lands (the caret
    # disappears after the first typed character).
    flat = text_caret_flat(in_block, sel)
    flat === nothing && return nothing
    loc = text_flat_to_elem(in_block, flat)
    # A caret inside a `TextLine` has no flat top-level span mapping — `_wrap` passes
    # `TextLine` elements through unchanged (it reflows only top-level spans), so they
    # carry no `WrapSeg`. The line is identical in the output, so such a caret maps to
    # itself; returning `sel` keeps the cursor visible over a line-structured block.
    loc === nothing && return sel
    in_span, in_char = loc
    best = nothing
    for seg in segs
        seg.in_span == in_span || continue
        if seg.in_char_start <= in_char <= seg.in_char_start + seg.length
            best = seg
            # Prefer the start of the next sub-span at a wrap boundary.
            in_char == seg.in_char_start && seg.in_char_start != 0 && break
        end
    end
    best === nothing && return nothing
    f = text_elem_to_flat(out_block, best.out_index, in_char - best.in_char_start)
    f === nothing ? nothing : _flat_caret(f)
end

map_reference_forward(p::WordWrapping, iomap::WordWrappingIoMap, reference) =
    _forward_map(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::WordWrapping, iomap::WordWrappingIoMap, reference)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = text_flat_to_elem(iomap.output, flat)
    # A caret over a `TextLine` (passed through unchanged, so no `WrapSeg` and no
    # flat top-level span) maps backward to itself — the mirror of the forward map.
    loc === nothing && return reference
    out_span, out_char = loc
    for seg in iomap.segs
        seg.out_index == out_span || continue
        f = text_elem_to_flat(iomap.input, seg.in_span, seg.in_char_start + out_char)
        return f === nothing ? nothing : _flat_caret(f)
    end
    nothing
end

function read_intent(p::WordWrapping, iomap::WordWrappingIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Translate a `ReplaceStringRangeOperation` from the wrapped output domain
# back to the unwrapped input domain. The output path is
# `.elements[out_span].content[s:e]`; we look up the input span and shift
# the character range by the sub-span's start offset. Ranges that span more
# than one input span are rejected (return `nothing`) for now.
# `.elements[i].elements[j].content[s:e]` — a caret inside a `TextLine`. `_wrap`
# passes lines through unchanged, so the edit maps to itself.
function _is_line_nested_content_range(path)
    path = strip_reference_types(path)
    path isa ConcreteReference || return false
    (path.head isa FieldReferenceStep && path.head.name == "elements") || return false
    t1 = path.tail
    (t1 isa ConcreteReference && t1.head isa RangeReferenceStep) || return false
    t2 = t1.tail
    t2 isa ConcreteReference || return false
    t2.head isa FieldReferenceStep && t2.head.name == "elements"   # a second `elements` hop ⇒ line-nested
end

function read_intent(p::WordWrapping, iomap::WordWrappingIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    # A line-nested edit reference addresses a passed-through `TextLine` span; map it
    # to itself. `_parse_text_elem_range` only recognises the top-level span shape.
    parsed === nothing && return _is_line_nested_content_range(op.reference) ? op : nothing
    out_span, char_start, char_stop = parsed
    segs = iomap.segs
    for seg in segs
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

# A raw character/edit gesture reaches this stage only because the layers above
# (TextToGraphics) declined it — e.g. a Backspace whose delete range straddles a
# soft wrap in the laid-out block, which is cross-span there but a clean in-span edit
# on the UN-wrapped input. Read it against the input block and lower the flat
# `ReplaceTextRangeOperation` to the structural single-span `ReplaceStringRangeOperation`,
# exactly as `TextToGraphics._gesture_op` does at the top and a `SyntaxToText` stage
# would do below (`_lower_text_range` against the same block SyntaxToText owns as its
# output). In a pure-text pipeline there is no syntax stage beneath to lower it, so
# without this the caret at a wrap boundary keeps a flat `TextRangeReferenceStep` and the
# edit surfaces as a raw `ReplaceTextRangeOperation`.
function read_intent(p::WordWrapping, iomap::WordWrappingIoMap, evt::Union{KeyPress, KeyDown})
    op = read_gesture(iomap.input, evt)
    op isa ReplaceTextRangeOperation ? _lower_text_range(iomap.input, op) : op
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MousePress) is handled above — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::WordWrapping, ::WordWrappingIoMap, op::Operation) = op

# ── Path helpers ────────────────────────────────────────────────────────────

# A whole-element selection at this layer is either `∅` (the whole text) or a
# `TextSpanReferenceStep(s,e)…∅` box over a flat character range — the same
# two shapes `SyntaxToText` emits and `TextToGraphics` highlights. Both index the
# flat character space, which wrapping leaves unchanged, so they map identically
# in either direction.
function _is_structural_ref(ref)
    ref = ref
    ref isa EmptyReference ||
        (ref isa ConcreteReference && ref.head isa TextSpanReferenceStep)
end

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

# Like `_parse_text_elem_path` but returns the full `(span_idx, char_start,
# char_stop)` of the terminal `RangeReferenceStep` instead of only its start.
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
