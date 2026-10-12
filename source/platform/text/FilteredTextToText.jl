# Fragment of `TextModule`.
#
# FilteredText → Text projection. The `grep` of a find bar: it prints the text of
# a `FilteredText` through the recursion of its stage, and keeps only the lines of
# the `TextBlock` that comes back whose text matches the pattern of the document,
# dropping the rest. A line's match string is the concatenation of the contents
# of its `TextString`s (a `TextSpacing` or a `TextGraphics` adds nothing to it).
#
# Surviving lines are emitted unchanged — the same `TextLine` objects, with the
# same styling and characters — so the mapping moves only the offsets after a
# dropped line, and only the line index is remapped. This makes the projection
# invertible by a simple `kept` table (`FilteredTextToTextIoMap.kept`): `kept[j]`
# is the line index, in the block of the text, of the j-th output line.
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
        _filter_lines(block, pattern, document.invert)
    end)   # (elements, kept)
    elements_cv = CellVector(@computation both[][1])
    kept_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(document, path ->
        _forward_map_text(kept_cell[], text_iomap[], TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    FilteredTextToTextIoMap(p, document, output, text_iomap, kept_cell)
end

# The lines whose text matches, each the same object, and the input index of each:
# `(lines, kept)`. A `nothing` pattern keeps every line. The text of a line is the
# text of its runs; a spacing or an image adds nothing to it.
function _filter_lines(text::TextBlock, pattern, invert::Bool)
    out = TextDocument[]
    kept = Int[]
    for (i, line) in enumerate(text.elements)
        if pattern !== nothing
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

# The runs of flat offsets that the filter keeps: one for each kept line. A
# dropped line is in no run, so the offsets after it move back by its length.
_make_filter_runs(kept::Vector{Int}, input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output, [(i, 0, j, get_flat_length(input.elements[i])) for (j, i) in enumerate(kept)])

# Forward: a dropped line moves the offsets after it, so every caret, range and box
# maps over the runs of the kept lines, and one on a dropped line maps to nothing.
# Takes the blocks explicitly so `print_document` can compute the output selection
# before the `IoMap` exists.
_forward_map(kept::Vector{Int}, in_block, out_block, sel) =
    _map_selection_over_runs(_make_filter_runs(kept, in_block, out_block), in_block, sel)

map_reference_forward(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, reference) =
    _forward_map_text(iomap.kept, iomap.text_iomap, iomap.output, reference)

map_reference_backward(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, reference) =
    _backward_map_text(iomap.text_iomap,
                       _backward_map_kept(iomap.kept, iomap.text_iomap.output, iomap.output,
                                          reference))

# A reference of the output, back across the kept table to the block of the text.
_backward_map_kept(kept, in_block, out_block, reference) =
    _map_selection_over_runs(_reverse_flat_runs(_make_filter_runs(kept, in_block, out_block)),
                             out_block, reference)

function read_intent(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, op::ReplacePathOperation)
    inner = _backward_map_kept(iomap.kept, iomap.text_iomap.output, iomap.output,
                               get_operation_path(op))
    inner === nothing && return nothing
    _read_text_operation(iomap.text_iomap, make_path_operation(op, inner))
end

# Translate a `ReplaceStringRangeOperation` from the filtered output back to the
# block of the text: remap the line index via the kept table, keep the run and
# the character range unchanged, and then read it through the IO map of the text.
function read_intent(p::FilteredTextToText, iomap::FilteredTextToTextIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_line_span_path(op.reference)
    (parsed === nothing || parsed[3] === nothing) && return nothing
    j, k, (char_start, char_stop) = parsed
    kept = iomap.kept
    1 <= j <= length(kept) || return nothing
    _read_text_operation(iomap.text_iomap,
        ReplaceStringRangeOperation(_text_replace_path(Int[kept[j], k], char_start, char_stop),
                                    op.replacement))
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
