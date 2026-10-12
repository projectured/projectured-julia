# Fragment of `TextModule`.
#
# Text → Text projection. Keeps only the **first line** of a `TextBlock`: the same
# `TextLine` object, so its runs keep their fonts and colours, and the lines after
# it are dropped. A block with no line gives a block with no line.
#
# This is the collapsed "header" view of a part in the conversation chat UI: the
# full body is `… → Text → Graphics`, the collapsed body is
# `… → Text → TextFirstLine → Graphics`, sharing the upstream `… → Text` work.
#
# Invertibility: the first line has the same flat offsets in both blocks, so
# reference mapping is the identity over it. A position on a later line maps
# forward to `nothing` (not drawn while collapsed); the backward map is the
# identity over the first line, so edits and selection inside it land on the real
# underlying line.
# ── Projection struct ─────────────────────────────────────────────────────────

"""
    TextFirstLine()

`TextBlock → TextBlock` projection that keeps the first line only.
Stateless — the cut is recomputed reactively from the input lines.
"""
struct TextFirstLine <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────────

@iomap struct TextFirstLineIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
end

# ── Print ─────────────────────────────────────────────────────────────────────

function print_document(p::TextFirstLine, recursion, text::TextBlock, ctx)
    elements_cv = CellVector(@computation _first_line(text))
    paths = make_output_path_cells(text, path ->
        _map_selection_over_runs(_make_first_line_runs(text, TextBlock(elements_cv, Cell(nothing))), text, path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
    TextFirstLineIoMap(p, text, output)
end

# The first line of `text`, the same object, or none.
_first_line(text::TextBlock) = isempty(text.elements) ? TextDocument[] : TextDocument[text.elements[1]]

# ── Selection / reference mapping ─────────────────────────────────────────────

# The runs of flat offsets that the first line keeps: one run with the same
# offsets in both blocks. A caret on a later line is in no run, so it is not drawn.
_make_first_line_runs(input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output,
                    [(1, 0, 1, get_flat_length(output.elements[1])) for _ in 1:min(1, length(output.elements))])

# Forward and backward, a caret or a range in either caret form maps to the same
# flat offsets while it lies on the first line.
map_reference_forward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference) =
    _map_selection_over_runs(_make_first_line_runs(iomap.input, iomap.output), iomap.input, reference)

map_reference_backward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference) =
    _map_selection_over_runs(_reverse_flat_runs(_make_first_line_runs(iomap.input, iomap.output)),
                             iomap.output, reference)

function read_intent(p::TextFirstLine, iomap::TextFirstLineIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# A range edit on the first line maps back to the same line and range: the one
# output line is the first input line.
function read_intent(p::TextFirstLine, iomap::TextFirstLineIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_line_span_path(op.reference)
    (parsed !== nothing && parsed[1] == 1 && parsed[3] !== nothing) ? op : nothing
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MouseClick) falls through to the base `Projection.read_intent`, which delegates
# via `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::TextFirstLine, ::TextFirstLineIoMap, op::Operation) = op

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# input and lower it there, as `WordWrapping` does.
read_intent(::TextFirstLine, iomap::TextFirstLineIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::TextFirstLine, ::TextFirstLineIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op
