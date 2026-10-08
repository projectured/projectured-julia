# Fragment of `TextModule`.
#
# HighlightedText → Text projection. The "highlight all" of a find bar: it prints
# the text of a `HighlightedText` through the recursion of its stage, keeps every
# line of the `TextBlock` that comes back, and paints a background swatch behind
# the matches of the pattern of the document by setting `fill_color` on the
# matched sub-spans (rendered as a background `GraphicsRect` by `TextToGraphics`).
#
# The pattern comes from the fields of the input, read inside a cell, so a write
# of a field highlights again (`make_text_pattern`). An empty pattern, and one
# that does not compile, highlight nothing.
#
# It is the structural sibling of `WordWrapping` — both split a `TextString` into
# adjacent sub-spans and stay invertible through a piecewise offset table. Here the
# split happens at match boundaries and the matched runs are restyled, but no
# character is inserted or removed, so `HighlightSegment` is `WrapSegment` and the
# selection/reader mapping is identical. Matching is per span (the same
# span-delimited simplification as `FilteredTextToText`).
#
# A reference of the input starts with the step `text`. On the way forward the
# step comes off, the rest maps through the IO map of the text, and then across
# the segments; on the way back the other way, and the step goes on again. So a
# `HighlightedText` and a `FilteredText` nest, each in the `text` of the other.
# ── Projection struct ───────────────────────────────────────────────────────

"""
    HighlightedTextToText(; theme = nothing, color)

The projection of a `HighlightedText`: its text, with a swatch of `color` behind
each match of the pattern of the document.

Use it in a text stage whose recursion gives a `TextBlock` for the text: a row
`TextBlock => IdentityProjection()` passes a plain block through, and a nested
`FilteredText` or `HighlightedText` gives its own block. `color` is the
`fill_color` set on matched sub-spans (glyph color is left untouched so matched
text stays readable); its default is the `match_highlight` of the `TextTheme`
`theme`.

# Example

    RecursiveProjection(TypeDispatchingProjection(
        HighlightedText => HighlightedTextToText(),
        TextBlock       => IdentityProjection()))

See also `HighlightedText`, the document it draws.
"""
struct HighlightedTextToText <: Projection
    color::StyleColor
end

HighlightedTextToText(; theme = nothing,
                      color::StyleColor = unwrap_cell(get_text_style(theme, :match_highlight))) =
    HighlightedTextToText(color)

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    HighlightSegment(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span. `out_index` is its 1-based
position in `output.elements`; `in_span` is the 1-based originating span of the
block of the text; `in_char_start` is the 0-based char offset of this sub-span
within that span; `length` is its character count.
"""
struct HighlightSegment
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

"""
    HighlightedTextToTextIoMap(projection, input, output, text_iomap, segs)

`input` is the `HighlightedText`; `text_iomap` is the IO map of its text, printed
through the recursion, whose output is the block that is highlighted; `segs` is the
table of segments from that block to `output`.
"""
@iomap struct HighlightedTextToTextIoMap
    projection::Any
    input::Any
    output::TextBlock
    text_iomap::Any
    # Cell{Vector{HighlightSegment}} for a block of spans; for a block of lines,
    # Cell{Vector{Pair{Int,Vector{HighlightSegment}}}}, each line that is split =>
    # the segments of its spans, whose indices count in the line.
    segs::Cell
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::HighlightedTextToText, recursion, document::HighlightedText, ctx)
    text_ctx = ctx === nothing ? nothing : make_child_context(ctx, FieldReferenceStep("text"))
    text_iomap = make_reconciled_child_iomap_cell(() -> document.text,
                                                  text -> print_child(recursion, text, text_ctx))
    color = p.color
    both = Cell(@computation begin
        block = text_iomap[].output::TextBlock
        pattern = make_text_pattern(document.pattern, document.regex, document.case_insensitive)
        _is_block_of_lines(block) ? _highlight_lines(block, pattern, color) : _highlight(block, pattern, color)
    end)   # (elements, segs)
    elements_cv = CellVector(@computation both[][1])
    segs_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(document, path ->
        _forward_map_text(segs_cell[], text_iomap[], TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    HighlightedTextToTextIoMap(p, document, output, text_iomap, segs_cell)
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
        elseif elem isa TextGraphics
            # An inline image is one position: the carets before and after it map.
            push!(result, elem)
            push!(segs, HighlightSegment(length(result), in_span, 0, 1))
        else
            push!(result, elem)
        end
    end
    (result, segs)
end

# A block of lines: each line with a match gets new spans, and every other line is
# the same object; the segments of each line that is split. A match lies inside one
# span, as on a block of spans.
function _highlight_lines(text::TextBlock, pattern, color::StyleColor)
    result = TextDocument[]
    segs = Pair{Int,Vector{HighlightSegment}}[]
    fill_cell = Cell(color)
    for (i, line) in enumerate(text.elements)
        if pattern === nothing || !(line isa TextLine)
            push!(result, line)
            continue
        end
        spans = TextDocument[]
        line_segs = HighlightSegment[]
        for (j, span) in enumerate(line.elements)
            if span isa TextString
                _highlight_string!(spans, line_segs, span, j, pattern, fill_cell)
            else
                push!(spans, span)
                span isa TextGraphics && push!(line_segs, HighlightSegment(length(spans), j, 0, 1))
            end
        end
        if length(spans) == length(line.elements) && all(k -> spans[k] === line.elements[k], eachindex(spans))
            push!(result, line)
        else
            push!(result, _make_line_with_spans(line, spans))
            push!(segs, i => line_segs)
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
               getfield(original, :pointer_shape),
               Cell(nothing))
end

# ── Selection / reference mapping ───────────────────────────────────────────
# Identical to WordWrapping: the seg table is a piecewise-linear char-offset map.

# Forward: rebuild an input flat caret against the split output by finding the
# sub-span the cursor falls into. At the exact boundary between two sub-spans
# of the same input span, prefer the start of the next sub-span.
# input flat caret → output flat caret, over the seg table. Takes the blocks
# explicitly so `print_document` can compute the output selection before the
# `IoMap` exists.
"""
    _forward_map(segs, in_block, out_block, sel; unmapped_maps_to_itself = false)

Map a caret on `in_block` forward to `out_block` across the segments `segs`.

`unmapped_maps_to_itself` says what a caret with no segment means. A projection
that rewrites every top-level span leaves nothing unmapped, so `nothing` is the
honest answer and the default. Word wrapping is the exception: `_wrap` reflows
only top-level spans and passes a `TextLine` through unchanged, so a caret inside
one carries no `WrapSegment`. The line is identical in the output, so such a
caret maps to itself, and the cursor stays visible over a line-structured block.
"""
function _forward_map(segs, in_block, out_block, sel;
                      unmapped_maps_to_itself::Bool = false)
    _is_structural_ref(sel) && return sel
    # Resolve either caret form (flat `TextRangeReferenceStep{k}` or structural
    # `.elements[i].content{k}`); a flat-only read drops the cursor after an edit.
    flat = get_flat_caret(in_block, sel)
    if flat === nothing
        # A range maps end by end. Its start opens the sub-span it enters and its
        # stop closes the one it leaves, so a range that ends at a soft break
        # stays on its line.
        pair = _text_flat_selection(in_block, sel)
        pair === nothing && return nothing
        start = _forward_flat(segs, in_block, out_block, pair[1], true)
        stop = _forward_flat(segs, in_block, out_block, pair[2], false)
        (start === :unmapped && stop === :unmapped) &&
            return unmapped_maps_to_itself ? sel : nothing
        (start isa Int && stop isa Int) || return nothing
        return make_flat_range_reference(start, stop)
    end
    f = _forward_flat(segs, in_block, out_block, flat, true)
    f === :unmapped && return unmapped_maps_to_itself ? sel : nothing
    f === nothing ? nothing : _flat_caret(f)
end

# One flat offset of the input, as a flat offset of the output. `:unmapped` when
# the offset lies in no top-level span (a `TextLine` passes through unchanged),
# `nothing` when no sub-span holds it. At a split boundary `opens` prefers the
# start of the next sub-span, and otherwise the end of the previous one.
function _forward_flat(segs, in_block, out_block, flat::Int, opens::Bool)
    loc = convert_flat_offset_to_element(in_block, flat)
    loc === nothing && return :unmapped
    in_span, in_char = loc
    best = nothing
    for seg in segs
        seg.in_span == in_span || continue
        if seg.in_char_start <= in_char <= seg.in_char_start + seg.length
            best = seg
            opens || break
            # Prefer the start of the next sub-span at the split boundary.
            in_char == seg.in_char_start && seg.in_char_start != 0 && break
        end
    end
    best === nothing && return nothing
    convert_element_to_flat_offset(out_block, best.out_index, in_char - best.in_char_start)
end

# A block of lines: a path into a span of a line maps through the segments of
# that line (`_map_line_path`).
_forward_map(segs::Vector{Pair{Int,Vector{HighlightSegment}}}, in_block, out_block, sel) =
    _map_line_path(segs, sel, true)

# ── The step `text` ─────────────────────────────────────────────────────────

# The rest of a reference of the input after its step `text`, or `nothing`.
function _strip_text_step(reference)
    reference isa Reference || return nothing
    stripped = strip_reference_types(reference)
    stripped isa ConcreteReference || return nothing
    head = get_reference_head(stripped)
    (head isa FieldReferenceStep && head.name == "text") || return nothing
    get_reference_tail(stripped)
end

# A reference of the input, forward to the output of a projection whose segments
# are `segs`: the step `text` comes off, the rest maps through the IO map of the
# text, and then across the segments.
function _forward_map_text(segs, text_iomap, out_block, reference)
    inner = _strip_text_step(reference)
    inner === nothing && return nothing
    mapped = map_reference_forward(text_iomap.projection, text_iomap, inner)
    mapped === nothing && return nothing
    _forward_map(segs, text_iomap.output, out_block, mapped)
end

# A reference of the block of the text, back through the IO map of the text, with
# the step `text` in front.
function _backward_map_text(text_iomap, reference)
    reference === nothing && return nothing
    inner = map_reference_backward(text_iomap.projection, text_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("text"), inner)
end

# An operation of the block of the text, read by the IO map of the text, with the
# step `text` in front of what it names.
function _read_text_operation(text_iomap, operation)
    operation === nothing && return nothing
    answer = read_intent(text_iomap.projection, text_iomap, operation)
    answer === nothing ? nothing : reroot_operation(answer, (FieldReferenceStep("text"),))
end

# ── Selection / reference mapping ───────────────────────────────────────────

map_reference_forward(p::HighlightedTextToText, iomap::HighlightedTextToTextIoMap, reference) =
    _forward_map_text(iomap.segs, iomap.text_iomap, iomap.output, reference)

map_reference_backward(p::HighlightedTextToText, iomap::HighlightedTextToTextIoMap, reference) =
    _backward_map_text(iomap.text_iomap,
                       _backward_map_segments(iomap.segs, iomap.text_iomap.output, iomap.output,
                                              reference))

# A reference of the output, back across the segments to the block of the text.
function _backward_map_segments(segs, in_block, out_block, reference)
    _is_block_of_lines(in_block) && return _map_line_path(segs, reference, false)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(out_block, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    for seg in segs
        seg.out_index == out_span || continue
        f = convert_element_to_flat_offset(in_block, seg.in_span, seg.in_char_start + out_char)
        return f === nothing ? nothing : _flat_caret(f)
    end
    nothing
end

# ── Readers ─────────────────────────────────────────────────────────────────

function read_intent(p::HighlightedTextToText, iomap::HighlightedTextToTextIoMap, op::ReplacePathOperation)
    inner = _backward_map_segments(iomap.segs, iomap.text_iomap.output, iomap.output,
                                   get_operation_path(op))
    inner === nothing && return nothing
    _read_text_operation(iomap.text_iomap, make_path_operation(op, inner))
end

# Translate a `ReplaceStringRangeOperation` from the split output back to the
# block of the text, shifting the char range by the sub-span's start, and then
# through the IO map of the text.
function read_intent(p::HighlightedTextToText, iomap::HighlightedTextToTextIoMap, op::ReplaceStringRangeOperation)
    if _is_block_of_lines(iomap.text_iomap.output)
        reference = _map_line_path(iomap.segs, op.reference, false)
        reference === nothing && return nothing
        return _read_text_operation(iomap.text_iomap, ReplaceStringRangeOperation(reference, op.replacement))
    end
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
        return _read_text_operation(iomap.text_iomap, ReplaceStringRangeOperation(new_ref, op.replacement))
    end
    nothing
end

# Forward any other Operation (ToggleCollapseOperation, collection ops, etc.)
# upstream unchanged.
read_intent(::HighlightedTextToText, ::HighlightedTextToTextIoMap, op::Operation) = op

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# block of the text and lower it there, as `WordWrapping` does, and then through
# the IO map of the text.
read_intent(::HighlightedTextToText, iomap::HighlightedTextToTextIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_text_operation(iomap.text_iomap, _read_lowered_gesture(iomap.text_iomap.output, evt))

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::HighlightedTextToText, ::HighlightedTextToTextIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op
