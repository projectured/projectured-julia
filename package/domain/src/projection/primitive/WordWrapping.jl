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
import ..TextModule: TextText, TextDocument, TextString, TextNewline, TextGraphics
import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..IoMapApiModule: IoMap
import ..PrinterContextModule: PrinterContext
import ..ReferenceModule: ConcreteReferencePath, RangeReference, FieldReference, EmptyReferencePath, ReferencePath, TextRectangularReference, strip_reference_types
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
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

struct WordWrappingIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    segs::Cell  # Cell{Vector{WrapSeg}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::WordWrapping, recursion, text::TextText, ctx)
    wrap_w_cell = _wrap_width_cell(p, ctx)
    measure_fn = p.measure
    both = Cell(() -> _wrap(text, Int(wrap_w_cell[]), measure_fn))
    elements_cv = CellVector(() -> both[][1])
    segs_cell = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(segs_cell[], text.selection))
    output = TextText(elements_cv, out_selection)
    WordWrappingIoMap(p, text, output, segs_cell)
end

function _wrap_width_cell(p::WordWrapping, ctx)
    if ctx isa PrinterContext && ctx.available_width !== nothing
        aw = ctx.available_width
        fallback = p.max_width
        return Cell(() -> begin
            v = aw[]
            v isa Integer ? max(1, Int(v)) : fallback
        end)
    end
    Cell(p.max_width)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{WrapSeg}).
function _wrap(text::TextText, wrap_w::Int, measure_fn::Function)
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
function _forward_map(segs::Vector{WrapSeg}, sel)
    sel === nothing && return nothing
    # Structural / whole-element selections live in a flat character space that
    # wrapping leaves invariant (every input character survives exactly once and
    # in order; the soft `TextNewline`s inserted at wrap points are not counted),
    # so their shapes pass straight through:
    #   ∅                                → the whole text element
    #   TextRectangularReference(s,e)…∅  → the flat character box [s, e)
    _is_structural_ref(sel) && return sel
    parsed = _parse_text_elem_path(sel)
    parsed === nothing && return nothing
    in_span, in_char = parsed
    best = nothing
    for seg in segs
        seg.in_span == in_span || continue
        if seg.in_char_start <= in_char <= seg.in_char_start + seg.length
            best = seg
            # Prefer the start of the next sub-span when the cursor sits
            # exactly at the boundary; this yields "start of next visual
            # line" at a wrap.
            if in_char == seg.in_char_start && seg.in_char_start != 0
                break
            end
        end
    end
    best === nothing && return nothing
    _text_elem_path(best.out_index, in_char - best.in_char_start)
end

function map_reference_forward(p::WordWrapping, iomap::WordWrappingIoMap, reference)
    _forward_map(iomap.segs[], reference)
end

function map_reference_backward(p::WordWrapping, iomap::WordWrappingIoMap, reference)
    # Structural / whole-element selections are invariant under wrapping (see
    # `_forward_map`); map them back unchanged so the round-trip is exact.
    _is_structural_ref(reference) && return reference
    parsed = _parse_text_elem_path(reference)
    parsed === nothing && return nothing
    out_span, out_char = parsed
    segs = iomap.segs[]
    for seg in segs
        seg.out_index == out_span || continue
        return _text_elem_path(seg.in_span, seg.in_char_start + out_char)
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
function read_intent(p::WordWrapping, iomap::WordWrappingIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    out_span, char_start, char_stop = parsed
    segs = iomap.segs[]
    for seg in segs
        seg.out_index == out_span || continue
        new_start = seg.in_char_start + char_start
        new_stop  = seg.in_char_start + char_stop
        new_ref = ConcreteReferencePath(FieldReference("elements"),
                      ConcreteReferencePath(RangeReference(seg.in_span - 1, seg.in_span),
                          ConcreteReferencePath(FieldReference("content"),
                              ConcreteReferencePath(RangeReference(new_start, new_stop),
                                                    EmptyReferencePath()))))
        return ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    nothing
end

# Forward arbitrary events upstream (KeyDown / KeyPress / etc.) so projections
# above WordWrapping keep getting a chance at them.
read_intent(::WordWrapping, ::WordWrappingIoMap, op) = op

# ── Path helpers ────────────────────────────────────────────────────────────

# A whole-element selection at this layer is either `∅` (the whole text) or a
# `TextRectangularReference(s,e)…∅` box over a flat character range — the same
# two shapes `SyntaxToText` emits and `TextToGraphics` highlights. Both index the
# flat character space, which wrapping leaves unchanged, so they map identically
# in either direction.
function _is_structural_ref(ref)
    ref = ref
    ref isa EmptyReferencePath ||
        (ref isa ConcreteReferencePath && ref.head isa TextRectangularReference)
end

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference ::TextText.elements[span_idx].content::String{char_idx}

function _parse_text_elem_path(path)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    h1 isa FieldReference && h1.name == "elements" || return nothing
    t1 = path.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    h3 isa FieldReference && h3.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    (span_idx, h4.start::Int)
end

# Like `_parse_text_elem_path` but returns the full `(span_idx, char_start,
# char_stop)` of the terminal `RangeReference` instead of only its start.
function _parse_text_elem_range(path)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    h1 isa FieldReference && h1.name == "elements" || return nothing
    t1 = path.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    h3 isa FieldReference && h3.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    (span_idx, h4.start::Int, h4.stop::Int)
end

end # module
