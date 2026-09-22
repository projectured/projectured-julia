# Fragment of `TextModule`.
#
# Text → Text projection. Keeps only the **first visual line** of a `TextBlock`:
# the span prefix up to the first line break, where a break is either
#
# - a standalone `TextNewline` span, or
# - the first embedded `'\\n'` inside a `TextString.content`
#
# (`SyntaxToText` and `WordWrapping` both treat an embedded `'\\n'` as a hard line
# break — see [`WordWrapping._wrap_string!`](WordWrapping.jl)). Spans before the
# break are emitted **verbatim** (their font/colour preserved); the span that
# contains the break is truncated to its pre-break prefix. The break span itself
# and everything after it are dropped.
#
# This is the collapsed "header" view of a part in the conversation chat UI: the
# full body is `… → Text → Graphics`, the collapsed body is
# `… → Text → TextFirstLine → Graphics`, sharing the upstream `… → Text` work.
#
# Invertibility: because kept spans keep their original index and order (the kept
# input spans are `1..k`, emitted as output spans `1..k`), reference mapping is the
# identity over the visible prefix. A position past the break maps forward to
# `nothing` (not drawn while collapsed); the backward map is the identity over the
# prefix, so edits/selection inside the first line land on the real underlying span.
# ── Projection struct ─────────────────────────────────────────────────────────

"""
    TextFirstLine()

`TextBlock → TextBlock` projection that keeps the first visual line only.
Stateless — the cut is recomputed reactively from the input spans.
"""
struct TextFirstLine <: Projection end

# ── IoMap ─────────────────────────────────────────────────────────────────────

# `kept` is the number of output spans (= number of input spans kept, since the
# prefix is index-aligned). `trunc_span` is the 1-based index of the span that
# was truncated at an embedded '\n' (or 0 if the prefix ended at a TextNewline /
# end of input with no truncation); `trunc_len` is that span's kept char count.
@iomap struct TextFirstLineIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    info::Cell  # Cell{NamedTuple{(:kept,:trunc_span,:trunc_len)}}
end

# ── Print ─────────────────────────────────────────────────────────────────────

function print_document(p::TextFirstLine, recursion, text::TextBlock, ctx)
    both = ComputedCell(() -> _first_line(text))
    elements_cv = ComputedCellVector(() -> both[][1])
    info_cell = ComputedCell(() -> both[][2])
    out_selection = ComputedCell(() -> begin
        kept = TextBlock(elements_cv, Cell(nothing))
        _map_selection_over_runs(_make_first_line_runs(info_cell[], text, kept), text, text.selection)
    end)
    output = TextBlock(elements_cv, out_selection)
    TextFirstLineIoMap(p, text, output, info_cell)
end

# Returns (output_elements::Vector{TextDocument}, info::NamedTuple).
function _first_line(text::TextBlock)
    result = TextDocument[]
    trunc_span = 0
    trunc_len = 0
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextNewline
            break
        elseif elem isa TextString
            content = elem.content::AbstractString
            nl = findfirst(==('\n'), content)
            if nl === nothing
                push!(result, elem)            # whole span is on the first line
            else
                prefix = content[1:prevind(content, nl)]
                push!(result, _make_span(elem, String(prefix)))
                trunc_span = in_span
                trunc_len = length(prefix)
                break
            end
        else
            # TextGraphics (atomic inline glyph) or any other span: part of the
            # first line, kept verbatim.
            push!(result, elem)
        end
    end
    (result, (kept = length(result), trunc_span = trunc_span, trunc_len = trunc_len))
end

# ── Selection / reference mapping ─────────────────────────────────────────────

# The runs of flat offsets that the first line keeps: each kept span is one run
# with the same offsets in both blocks, and the truncated span is as long as its
# kept prefix. A caret at or after the break is in no run, so it is not drawn.
_make_first_line_runs(info, input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output, [(i, 0, i, get_flat_length(output.elements[i])) for i in 1:info.kept])

# Forward and backward, a caret or a range in either caret form maps to the same
# flat offsets while it lies on the first line.
map_reference_forward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference) =
    _map_selection_over_runs(_make_first_line_runs(iomap.info, iomap.input, iomap.output),
                             iomap.input, reference)

map_reference_backward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference) =
    _map_selection_over_runs(_reverse_flat_runs(_make_first_line_runs(iomap.info, iomap.input, iomap.output)),
                             iomap.output, reference)

function read_intent(p::TextFirstLine, iomap::TextFirstLineIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# A range edit on the first line maps back to the identical span/range (indices
# and char offsets are preserved for the visible prefix).
function read_intent(p::TextFirstLine, iomap::TextFirstLineIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    out_span, char_start, char_stop = parsed
    new_ref = ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(out_span - 1, out_span),
                      ConcreteReference(FieldReferenceStep("content"),
                          ConcreteReference(RangeReferenceStep(char_start, char_stop),
                                                EmptyReference()))))
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MousePress) falls through to the base `Projection.read_intent`, which delegates
# via `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::TextFirstLine, ::TextFirstLineIoMap, op::Operation) = op
