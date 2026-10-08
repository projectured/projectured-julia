# Fragment of `TextModule`.
#
# Text → Text projection. The "highlight all" of a search box: keeps every line of
# a `TextBlock` and paints a background swatch behind the regex matches by setting
# `fill_color` on the matched sub-spans (rendered as a background `GraphicsRect` by
# `TextToGraphics`).
#
# It is the structural sibling of `WordWrapping` — both split a `TextString` into
# adjacent sub-spans and stay invertible through a piecewise offset table. Here the
# split happens at match boundaries and the matched runs are restyled, but no
# character is inserted or removed, so `HighlightSegment` is `WrapSegment` and the
# selection/reader mapping is identical. Matching is per span (the same
# span-delimited simplification as `TextFiltering`); a `nothing` pattern is a
# pass-through (no highlights), so the projection can sit idle in a pipeline until
# a pattern is set on the reactive `pattern` cell.
# ── Projection struct ───────────────────────────────────────────────────────

"""
    TextHighlighting(pattern; theme = nothing, color)
    TextHighlighting(; pattern = nothing, theme = nothing, color)

Paint a background swatch behind every match of `pattern` (a `Regex`, a pattern
string, a `Cell` holding either, or `nothing`).

`pattern` is held in a reactive `Cell`, so updating it re-highlights live; a
`nothing` pattern adds no highlights. `color` is the `fill_color` set on matched
sub-spans (glyph color is left untouched so matched text stays readable); its
default is the `match_highlight` of the `TextTheme` `theme`. Regex
flags live in the `Regex` the caller builds.
"""
struct TextHighlighting <: Projection
    pattern::Cell          # Cell holding the source String | Regex | nothing — reactive
    case_insensitive::Cell # Cell{Bool} — reactive; adds the `i` flag when a source String is compiled
    color::StyleColor
end

TextHighlighting(pattern::Cell; case_insensitive=false, theme = nothing,
                 color::StyleColor = unwrap_cell(get_text_style(theme, :match_highlight))) =
    TextHighlighting(pattern, case_insensitive isa Cell ? case_insensitive : Cell(case_insensitive), color)
TextHighlighting(pattern::Regex; kw...) = TextHighlighting(Cell(pattern); kw...)
TextHighlighting(pattern::AbstractString; kw...) = TextHighlighting(Cell(String(pattern)); kw...)
TextHighlighting(; pattern=nothing, kw...) =
    TextHighlighting(pattern isa Cell ? pattern : Cell(pattern); kw...)

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
    # Cell{Vector{HighlightSegment}} for a block of spans; for a block of lines,
    # Cell{Vector{Pair{Int,Vector{HighlightSegment}}}}, each line that is split =>
    # the segments of its spans, whose indices count in the line.
    segs::Cell
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::TextHighlighting, recursion, text::TextBlock, ctx)
    pattern_cell = p.pattern
    ci_cell = p.case_insensitive
    color = p.color
    both = Cell(@computation begin
        pattern = _effective_pattern(pattern_cell[], ci_cell[])
        _is_block_of_lines(text) ? _highlight_lines(text, pattern, color) : _highlight(text, pattern, color)
    end)
    elements_cv = CellVector(@computation both[][1])
    segs_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(text, path -> _is_block_of_lines(text) ?
        _map_line_path(segs_cell[], path, true) :
        _forward_map(segs_cell[], text, TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
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

map_reference_forward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference) =
    _is_block_of_lines(iomap.input) ? _map_line_path(iomap.segs, reference, true) :
    _forward_map(iomap.segs, iomap.input, iomap.output, reference)

function map_reference_backward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference)
    _is_block_of_lines(iomap.input) && return _map_line_path(iomap.segs, reference, false)
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

function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# Translate a `ReplaceStringRangeOperation` from the split output domain back to
# the unwrapped input domain, shifting the char range by the sub-span's start.
function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplaceStringRangeOperation)
    if _is_block_of_lines(iomap.input)
        reference = _map_line_path(iomap.segs, op.reference, false)
        return reference === nothing ? nothing : ReplaceStringRangeOperation(reference, op.replacement)
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
        return ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    nothing
end

# Forward any Operation (ToggleCollapseOperation, collection ops, etc.) upstream
# unchanged; a raw gesture (KeyPress/KeyDown/MouseClick) falls through to the
# base `Projection.read_intent` which delegates via `read_gesture(input, evt)`.
read_intent(::TextHighlighting, ::TextHighlightingIoMap, op::Operation) = op

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# input and lower it there, as `WordWrapping` does.
read_intent(::TextHighlighting, iomap::TextHighlightingIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::TextHighlighting, ::TextHighlightingIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op

# ── Path helpers ────────────────────────────────────────────────────────────
