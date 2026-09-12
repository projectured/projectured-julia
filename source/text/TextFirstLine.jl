"""
    TextFirstLineModule

Text → Text projection. Keeps only the **first visual line** of a `TextBlock`:
the span prefix up to the first line break, where a break is either

- a standalone `TextNewline` span, or
- the first embedded `'\\n'` inside a `TextString.content`

(`SyntaxToText` and `WordWrapping` both treat an embedded `'\\n'` as a hard line
break — see [`WordWrapping._wrap_string!`](WordWrapping.jl)). Spans before the
break are emitted **verbatim** (their font/colour preserved); the span that
contains the break is truncated to its pre-break prefix. The break span itself
and everything after it are dropped.

This is the collapsed "header" view of a part in the conversation chat UI: the
full body is `… → Text → Graphics`, the collapsed body is
`… → Text → TextFirstLine → Graphics`, sharing the upstream `… → Text` work.

Invertibility: because kept spans keep their original index and order (the kept
input spans are `1..k`, emitted as output spans `1..k`), reference mapping is the
identity over the visible prefix. A position past the break maps forward to
`nothing` (not drawn while collapsed); the backward map is a pure identity, so
edits/selection inside the first line land on the real underlying span.
"""
module TextFirstLineModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextBlock, TextDocument, TextString, TextNewline, TextGraphics
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, RangeReferenceStep, FieldReferenceStep, EmptyReference, strip_reference_types, Position
import ..ReferenceModule: var"@reference"
import ..OperationModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation

export TextFirstLine, TextFirstLineIoMap

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
    out_selection = ComputedCell(() -> _forward(info_cell[], text.selection))
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

# Copy a TextString preserving every styling cell, replacing only the content.
function _make_span(original::TextString, content::String)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               Cell(nothing))
end

# ── Selection / reference mapping ─────────────────────────────────────────────

# Forward: an input cursor `elements[s].content{c}` survives unchanged iff its
# span is within the kept prefix (and, for the truncated span, the char offset
# is within the kept length). Anything at/after the break is not drawn → nothing.
function _forward(info, sel)
    sel === nothing && return nothing
    parsed = _parse_text_elem_path(sel)
    parsed === nothing && return nothing
    in_span, in_char = parsed
    in_span <= info.kept || return nothing
    if in_span == info.trunc_span && in_char > info.trunc_len
        return nothing
    end
    _text_elem_path(in_span, in_char)
end

map_reference_forward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference) =
    _forward(iomap.info, reference)

# Backward: output spans are index-aligned with their input spans, so the map is
# the identity over the visible prefix.
function map_reference_backward(p::TextFirstLine, iomap::TextFirstLineIoMap, reference)
    parsed = _parse_text_elem_path(reference)
    parsed === nothing && return nothing
    out_span, out_char = parsed
    _text_elem_path(out_span, out_char)
end

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

# ── Path helpers (mirrors WordWrapping) ───────────────────────────────────────

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
