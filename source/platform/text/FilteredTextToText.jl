# Fragment of `TextModule`.
#
# FilteredText → Text projection. The `grep` of a find bar: it prints the text of
# a `FilteredText` through the recursion of its stage, and keeps only the lines of
# the `TextBlock` that comes back whose text matches the pattern of the document,
# dropping the rest. Lines are delimited by `TextNewline` elements; a line's match
# string is the concatenation of its `TextString` contents (`TextNewline` /
# `TextSpacing` / `TextGraphics` contribute nothing to the match).
#
# Surviving lines are emitted unchanged — same span objects, same styling, same
# character content — so the mapping is an identity on character offsets and only
# the element (span) index is remapped. This makes the projection invertible by a
# simple `kept` table (`FilteredTextToTextIoMap.kept`): `kept[j]` is the element
# index, in the block of the text, of the j-th output element.
#
# The pattern comes from the fields of the input, read inside a cell, so a write
# of a field filters again (`make_text_pattern`). An empty pattern, and one that
# does not compile, keep every line. A reference of the input starts with the step
# `text`, mapped as `HighlightedTextToText` maps it.

# ── Projection struct ───────────────────────────────────────────────────────

"""
    FilteredTextToText()

The projection of a `FilteredText`: the lines of its text that match the pattern
of the document, or, with `invert`, the lines that do not.

Use it in a text stage whose recursion gives a `TextBlock` for the text: a row
`TextBlock => IdentityProjection()` passes a plain block through, and a nested
`HighlightedText` or `FilteredText` gives its own block.

# Example

    RecursiveProjection(TypeDispatchingProjection(
        FilteredText    => FilteredTextToText(),
        HighlightedText => HighlightedTextToText(),
        TextBlock       => IdentityProjection()))

See also `FilteredText`, the document it draws.
"""
struct FilteredTextToText <: Projection end

# ── IoMap ───────────────────────────────────────────────────────────────────

"""
    FilteredTextToTextIoMap(projection, input, output, text_iomap, kept)

`input` is the `FilteredText`; `text_iomap` is the IO map of its text, printed
through the recursion, whose output is the block that is filtered. `kept` is a
`Cell{Vector{Int}}`: `kept[][j]` is the 1-based `elements` index, in that block,
of the j-th output element. Character offsets pass through unchanged, so unlike a
wrap table only the element index is recorded.
"""
@iomap struct FilteredTextToTextIoMap
    projection::Any
    input::Any
    output::TextBlock
    text_iomap::Any
    kept::Cell  # Cell{Vector{Int}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::FilteredTextToText, recursion, document::FilteredText, ctx)
    text_ctx = ctx === nothing ? nothing : make_child_context(ctx, FieldReferenceStep("text"))
    text_iomap = make_reconciled_child_iomap_cell(() -> document.text,
                                                  text -> print_child(recursion, text, text_ctx))
    both = Cell(@computation begin
        block = text_iomap[].output::TextBlock
        pattern = make_text_pattern(document.pattern, document.regex, document.case_insensitive)
        _is_block_of_lines(block) ? _filter_lines(block, pattern, document.invert) :
                                    _filter(block, pattern, document.invert)
    end)   # (elements, kept)
    elements_cv = CellVector(@computation both[][1])
    kept_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(document, path ->
        _forward_map_text(kept_cell[], text_iomap[], TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    FilteredTextToTextIoMap(p, document, output, text_iomap, kept_cell)
end

# Returns (output_elements::Vector{TextDocument}, kept::Vector{Int}).
# A `nothing` pattern keeps every element (identity filter). Otherwise the
# input is grouped into logical lines — the run of elements up to and including
# each TextNewline — and a line's elements are emitted iff its concatenated
# TextString content matches (XOR invert).
function _filter(text::TextBlock, pattern, invert::Bool)
    elems = text.elements
    n = length(elems)
    pattern === nothing && return (TextDocument[elems[i] for i in 1:n], collect(1:n))
    out = TextDocument[]
    kept = Int[]
    line = Int[]        # input indices of the current line's members
    buf = IOBuffer()    # match string accumulated for the current line
    flush_line! = function ()
        isempty(line) && return
        s = String(take!(buf))
        keep = occursin(pattern, s)
        invert && (keep = !keep)
        if keep
            for i in line
                push!(out, elems[i])
                push!(kept, i)
            end
        end
        empty!(line)
    end
    for i in 1:n
        elem = elems[i]
        push!(line, i)
        if elem isa TextString
            print(buf, elem.content::AbstractString)
        elseif elem isa TextNewline
            flush_line!()
        end
        # TextSpacing / TextGraphics contribute nothing to the match string.
    end
    flush_line!()  # trailing line with no terminating newline
    (out, kept)
end

# A block of lines: the lines whose text matches, each the same object, and the
# input index of each. The text of a line is the text of its spans.
function _filter_lines(text::TextBlock, pattern, invert::Bool)
    out = TextDocument[]
    kept = Int[]
    for (i, line) in enumerate(text.elements)
        if pattern !== nothing && line isa TextLine
            keep = occursin(pattern, join(span.content::AbstractString for span in line.elements
                                          if span isa TextString))
            keep == invert && continue
        end
        push!(out, line)
        push!(kept, i)
    end
    (out, kept)
end

# ── Selection / reference mapping ───────────────────────────────────────────

# A whole-element selection at this layer is either `∅` (the whole text) or a
# `TextSpanReferenceStep(s,e)…∅` box over a flat character range — the same
# two shapes `SyntaxToText` emits and `TextToGraphics` highlights. A decorator
# that only splits or restyles spans keeps every flat offset, so both pass through
# it unchanged. A decorator that drops or adds elements moves a box with its
# table of runs, and passes only `∅` through.
_is_structural_ref(ref) =
    ref isa EmptyReference ||
    (ref isa ConcreteReference && ref.head isa TextSpanReferenceStep)

# The runs of flat offsets that the filter keeps: one for each kept element. A
# dropped line is in no run, so the offsets after it move back by its length.
_make_filter_runs(kept::Vector{Int}, input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output, [(i, 0, j, get_flat_length(input.elements[i])) for (j, i) in enumerate(kept)])

# Forward: input flat caret → output position by finding in_span in the kept
# table. Returns nothing when the line was filtered out (the selection has no
# image in the output). Takes the blocks explicitly so `print_document` can
# compute the output selection before the `IoMap` exists.
function _forward_map(kept::Vector{Int}, in_block, out_block, sel)
    # On a block of lines a dropped line moves the offsets after it, so every
    # caret, range and box maps over the runs of the kept lines.
    _is_block_of_lines(in_block) &&
        return _map_selection_over_runs(_make_filter_runs(kept, in_block, out_block), in_block, sel)
    box = _get_text_box(sel)
    box === nothing || return _map_text_box(_make_filter_runs(kept, in_block, out_block), box)
    _is_structural_ref(sel) && return sel
    # Resolve either caret form (flat `TextRangeReferenceStep{k}` or structural
    # `.elements[i].content{k}`); a flat-only read drops the cursor after an edit.
    flat = get_flat_caret(in_block, sel)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(in_block, flat)
    loc === nothing && return nothing
    in_span, in_char = loc
    j = findfirst(==(in_span), kept)
    j === nothing && return nothing
    f = convert_element_to_flat_offset(out_block, j, in_char)
    f === nothing ? nothing : _flat_caret(f)
end

map_reference_forward(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, reference) =
    _forward_map_text(iomap.kept, iomap.text_iomap, iomap.output, reference)

map_reference_backward(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, reference) =
    _backward_map_text(iomap.text_iomap,
                       _backward_map_kept(iomap.kept, iomap.text_iomap.output, iomap.output,
                                          reference))

# A reference of the output, back across the kept table to the block of the text.
function _backward_map_kept(kept, in_block, out_block, reference)
    _is_block_of_lines(in_block) &&
        return _map_selection_over_runs(_reverse_flat_runs(_make_filter_runs(kept, in_block, out_block)),
                                        out_block, reference)
    box = _get_text_box(reference)
    box === nothing ||
        return _map_text_box(_reverse_flat_runs(_make_filter_runs(kept, in_block, out_block)), box)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(out_block, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    (out_span < 1 || out_span > length(kept)) && return nothing
    in_span = kept[out_span]
    f = convert_element_to_flat_offset(in_block, in_span, out_char)
    f === nothing ? nothing : _flat_caret(f)
end

function read_intent(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, op::ReplacePathOperation)
    inner = _backward_map_kept(iomap.kept, iomap.text_iomap.output, iomap.output,
                               get_operation_path(op))
    inner === nothing && return nothing
    _read_text_operation(iomap.text_iomap, make_path_operation(op, inner))
end

# Translate a `ReplaceStringRangeOperation` from the filtered output back to the
# block of the text: remap the element index via the kept table, keep the
# character range unchanged, and then read it through the IO map of the text.
function read_intent(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, op::ReplaceStringRangeOperation)
    if _is_block_of_lines(iomap.text_iomap.output)
        parsed = _parse_line_span_path(op.reference)
        (parsed === nothing || parsed[3] === nothing) && return nothing
        j, k, (char_start, char_stop) = parsed
        kept = iomap.kept
        1 <= j <= length(kept) || return nothing
        return _read_text_operation(iomap.text_iomap,
            ReplaceStringRangeOperation(_text_replace_path(Int[kept[j], k], char_start, char_stop),
                                        op.replacement))
    end
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    out_span, char_start, char_stop = parsed
    kept = iomap.kept
    (out_span < 1 || out_span > length(kept)) && return nothing
    in_span = kept[out_span]
    new_ref = ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(in_span - 1, in_span),
                      ConcreteReference(FieldReferenceStep("content"),
                          ConcreteReference(RangeReferenceStep(char_start, char_stop),
                                                EmptyReference()))))
    _read_text_operation(iomap.text_iomap, ReplaceStringRangeOperation(new_ref, op.replacement))
end

# Forward any other Operation upstream unchanged; a raw gesture (MouseClick)
# falls through to the base `Projection.read_intent`, which delegates via
# `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::FilteredTextToText, ::FilteredTextToTextIoMap, op::Operation) = op

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# block of the text and lower it there, as `WordWrapping` does, and then through
# the IO map of the text.
read_intent(::FilteredTextToText, iomap::FilteredTextToTextIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_text_operation(iomap.text_iomap, _read_lowered_gesture(iomap.text_iomap.output, evt))

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::FilteredTextToText, ::FilteredTextToTextIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op
