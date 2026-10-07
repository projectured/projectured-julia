# Fragment of `TextModule`.
#
# Text → Text projection. Pixel-accurate word wrapping: splits a TextString into
# sub-spans at word boundaries and inserts `TextNewline` elements where a word
# would push the column past the wrap width. The wrap width is the maximum of
# the range the parent gives on the width, `ctx.maximum_width`, exact or bounded
# (so a resize re-wraps reactively), cut at the projection's `max_width`; with
# neither, a line does not wrap.
#
# Character preservation: the projection is structural only — every character of
# the input survives in the output, exactly once and in order. A space that
# lands at a wrap boundary stays as the last character of the previous visual
# line. This makes the projection invertible by a clean piecewise-linear offset
# table (`WordWrappingIoMap.segs`), used by selection mapping and the reader.
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

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    WrapSegment(out_index, in_span, in_char_start, length)

One entry per output element that comes from an input element: a `TextString`
sub-span, an image, or an element that the wrap passes through, such as a hard
`TextNewline`. `out_index` is the 1-based position of the element in
`output.elements`. `in_span` is the 1-based index of the originating input
element. `in_char_start` is the 0-based character offset of a sub-span within
the input span, and 0 for any other element; `length` is its character count.
Inserted soft `TextNewline`s have no `WrapSegment`.
"""
struct WrapSegment
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

@iomap struct WordWrappingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    segs::Cell  # Cell{Vector{WrapSegment}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::WordWrapping, recursion, text::TextBlock, ctx)
    wrap_w_cell = _wrap_width_cell(p, ctx)
    measure_fn = p.measure
    both = Cell(@computation _wrap(text, Int(wrap_w_cell[]), measure_fn))
    elements_cv = CellVector(@computation both[][1])
    segs_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(text, path ->
        _forward_wrapped(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    WordWrappingIoMap(p, text, output, segs_cell)
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

# Returns (output_elements::Vector{TextDocument}, segs::Vector{WrapSegment}).
function _wrap(text::TextBlock, wrap_w::Int, measure_fn::TextMeasure)
    result = TextDocument[]
    segs = WrapSegment[]
    cx = 0
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            cx = _wrap_string!(result, segs, elem, in_span, cx, wrap_w, measure_fn)
        elseif elem isa TextNewline
            _pass_through!(result, segs, elem, in_span)
            cx = 0
        elseif elem isa TextGraphics
            cx = _wrap_graphics!(result, segs, text, in_span, cx, wrap_w)
        else
            _pass_through!(result, segs, elem, in_span)
        end
    end
    (result, segs)
end

function _pass_through!(result::Vector{TextDocument}, segs::Vector{WrapSegment},
                        element::TextDocument, in_span::Int)
    push!(result, element)
    push!(segs, WrapSegment(length(result), in_span, 0, get_flat_length(element)))
end

# Wraps one input TextString span, appending output sub-spans (and soft
# newlines) to `result` and the corresponding `WrapSegment` entries to `segs`.
# Returns the updated column offset.
function _wrap_string!(result::Vector{TextDocument}, segs::Vector{WrapSegment},
                       original::TextString, in_span::Int,
                       cx::Int, wrap_w::Int, measure_fn::TextMeasure)
    content = original.content::AbstractString
    if isempty(content)
        # An empty span stays one empty span, so a caret in it has a place to
        # map to and to be drawn at.
        push!(result, _make_span(original, ""))
        push!(segs, WrapSegment(length(result), in_span, 0, 0))
        return cx
    end
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
            cand_w = first(compute_text_extent(measure_fn, cand, font))
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
                cx += first(compute_text_extent(measure_fn, word, font))
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

# Place the TextGraphics image at `in_span` of `text` as a single unbreakable
# token. If it would overflow the current visual line, insert a soft TextNewline
# before it so the image drops whole onto the next line (it is never split). The
# image keeps its single atomic cursor range [0, 1), recorded as a zero-based
# WrapSegment so selection mapping can locate it in the wrapped output. Returns
# the updated column offset.
function _wrap_graphics!(result::Vector{TextDocument}, segs::Vector{WrapSegment},
                         text::TextBlock, in_span::Int, cx::Int, wrap_w::Int)
    image = text.elements[in_span]::TextGraphics
    img_w = Int(image.width::Int32)
    if cx > 0 && wrap_w > 0 && cx + img_w > wrap_w
        push!(result, _make_image_newline(text, in_span))
        cx = 0
    end
    push!(result, image)
    push!(segs, WrapSegment(length(result), in_span, 0, 1))
    return cx + img_w
end

# The soft newline before the image at `in_span`. An image has no style, so the
# newline takes the one a run typed beside the image takes (`_find_style_span`).
function _make_image_newline(text::TextBlock, in_span::Int)
    span = _find_style_span(text, Int[in_span])
    span === nothing && return TextNewline(font = UNSTYLED_TEXT_FONT)
    TextNewline(font=span.font,
                font_color=span.font_color,
                fill_color=span.fill_color,
                line_color=span.line_color,
                padding=span.padding)
end

function _flush!(result::Vector{TextDocument}, segs::Vector{WrapSegment},
                 original::TextString, in_span::Int, sub_start::Int, buf::IOBuffer)
    s = String(take!(buf))
    isempty(s) && return
    push!(result, _make_span(original, s))
    push!(segs, WrapSegment(length(result), in_span, sub_start, length(s)))
end

function _make_span(original::TextString, content::String)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               getfield(original, :pointer_shape),
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
_flat_caret(f::Int) = ConcreteReference(TextRangeReferenceStep(f, f), EmptyReference())

# The runs of flat offsets that the wrap carries from `input` to `output`, one for
# each segment. A soft `TextNewline` counts one flat offset, so each one moves the
# offsets after it by one; it lies between two runs.
_make_wrap_runs(segs, input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output,
                    [(s.in_span, s.in_char_start, s.out_index, get_flat_length(output.elements[s.out_index]))
                     for s in segs])

# An input selection as an output selection, over the seg table. Takes the blocks
# explicitly so `print_document` can compute the output selection before the
# `IoMap` exists. A whole-element box moves with the soft breaks before it; `∅`
# passes through.
function _forward_wrapped(segs, input::TextBlock, output::TextBlock, selection)
    box = _get_text_box(selection)
    box === nothing || return _map_text_box(_make_wrap_runs(segs, input, output), box)
    _forward_map(segs, input, output, selection; unmapped_maps_to_itself = true)
end

map_reference_forward(p::WordWrapping, iomap::WordWrappingIoMap, reference) =
    _forward_wrapped(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::WordWrapping, iomap::WordWrappingIoMap, reference)
    box = _get_text_box(reference)
    box === nothing ||
        return _map_text_box(_reverse_flat_runs(_make_wrap_runs(iomap.segs, iomap.input, iomap.output)), box)
    _is_structural_ref(reference) && return reference
    pair = _text_range_pair(reference)
    pair === nothing && return nothing
    start = _backward_flat(iomap, pair[1])
    # A caret over a `TextLine` (passed through unchanged, so no `WrapSegment` and no
    # flat top-level span) maps backward to itself — the mirror of the forward map.
    pair[1] == pair[2] && return start === :unmapped ? reference :
                                 start === nothing ? nothing : _flat_caret(start)
    # A range maps end by end; the two ends may lie in different lines of the
    # output and in one span of the input.
    stop = _backward_flat(iomap, pair[2])
    (start === :unmapped && stop === :unmapped) && return reference
    (start isa Int && stop isa Int) || return nothing
    make_flat_range_reference(start, stop)
end

# One flat offset of the output, as a flat offset of the input. `:unmapped` when it
# lies in no top-level span, `nothing` when no segment holds it.
function _backward_flat(iomap::WordWrappingIoMap, flat::Int)
    loc = convert_flat_offset_to_element(iomap.output, flat)
    loc === nothing && return :unmapped
    out_span, out_char = loc
    for seg in iomap.segs
        seg.out_index == out_span || continue
        return convert_element_to_flat_offset(iomap.input, seg.in_span, seg.in_char_start + out_char)
    end
    nothing
end

function read_intent(p::WordWrapping, iomap::WordWrappingIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
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
read_intent(p::WordWrapping, iomap::WordWrappingIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MouseClick) is handled above — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::WordWrapping, ::WordWrappingIoMap, op::Operation) = op

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::WordWrapping, ::WordWrappingIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op

# ── Path helpers ────────────────────────────────────────────────────────────

# The `(span_idx, char_start, char_stop)` of a `.elements[i].content[s:e]` path:
# the 1-based span and the 0-based range of its terminal `RangeReferenceStep`.
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
