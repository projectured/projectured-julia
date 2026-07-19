"""
    TextFilteringModule

Text → Text projection. The `grep` of the projection stack: keeps only the
lines of a `TextBlock` whose text matches a regex, dropping the rest. Lines are
delimited by `TextNewline` elements; a line's match string is the concatenation
of its `TextString` contents (`TextNewline` / `TextSpacing` / `TextGraphics`
contribute nothing to the match).

Surviving lines are emitted unchanged — same span objects, same styling, same
character content — so the mapping is an identity on character offsets and only
the element (span) index is remapped. This makes the projection invertible by a
simple `kept` table (`TextFilteringIoMap.kept`): `kept[j]` is the input element
index of the j-th output element.

A `nothing` pattern is a pass-through (keep every line), so the projection can
sit permanently in a pipeline with its filter idle until a pattern is set on the
reactive `pattern` cell.
"""
module TextFilteringModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextBlock, TextDocument, TextString, TextNewline, text_flat_to_elem, text_elem_to_flat, text_caret_flat
import ..TextRangeReferenceStepModule: TextRangeReferenceStep
import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, RangeReferenceStep, FieldReferenceStep, EmptyReference, strip_reference_types, Position
import ..TextSpanReferenceStepModule: TextSpanReferenceStep
import ..ReferenceBuilderModule: var"@reference"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
export TextFiltering, TextFilteringIoMap

# ── Projection struct ───────────────────────────────────────────────────────

"""
    TextFiltering(pattern; invert=false)
    TextFiltering(; pattern=nothing, invert=false)

Keep only the lines of the input `TextBlock` whose text matches `pattern`
(a `Regex`, a pattern string, a `Cell` holding either, or `nothing`).

`pattern` is held in a reactive `Cell`, so updating it re-filters live; a
`nothing` pattern keeps every line. `invert=true` keeps the *non*-matching
lines (`grep -v`). Regex flags (case-insensitivity, multiline, …) live in the
`Regex` the caller builds — the projection does not interpret them.
"""
struct TextFiltering <: Projection
    pattern::Cell          # Cell holding the source String | Regex | nothing — reactive
    case_insensitive::Cell # Cell{Bool} — reactive; adds the `i` flag when a source String is compiled
    invert::Cell           # Cell{Bool} — reactive; keep the *non*-matching lines (grep -v)
end

TextFiltering(pattern::Cell; case_insensitive=false, invert=false) =
    TextFiltering(pattern,
                  case_insensitive isa Cell ? case_insensitive : Cell(case_insensitive),
                  invert isa Cell ? invert : Cell(invert))
TextFiltering(pattern::Regex; kw...) = TextFiltering(Cell(pattern); kw...)
TextFiltering(pattern::AbstractString; kw...) = TextFiltering(Cell(String(pattern)); kw...)
TextFiltering(; pattern=nothing, kw...) =
    TextFiltering(pattern isa Cell ? pattern : Cell(pattern); kw...)

# Normalise the (reactive) pattern cell value into the `Union{Regex,Nothing}` the
# filter consumes. `nothing` / empty source ⇒ keep every line (pass-through); a
# source `String` is compiled (with the `i` flag when `case_insensitive`); a `Regex`
# is used verbatim — flags it carries win, so it ignores `case_insensitive`.
function _effective_pattern(value, case_insensitive::Bool)
    value === nothing && return nothing
    value isa Regex && return value
    s = String(value)
    isempty(s) && return nothing
    case_insensitive ? Regex(s, "i") : Regex(s)
end

# ── IoMap ───────────────────────────────────────────────────────────────────

"""
    TextFilteringIoMap(projection, input, output, kept)

`kept` is a `Cell{Vector{Int}}`: `kept[][j]` is the 1-based input `elements`
index of the j-th output element. Character offsets pass through unchanged, so
unlike a wrap table only the element index is recorded.
"""
@iomap struct TextFilteringIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    kept::Cell  # Cell{Vector{Int}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::TextFiltering, recursion, text::TextBlock, ctx)
    pattern_cell = p.pattern
    ci_cell = p.case_insensitive
    invert_cell = p.invert
    both = Cell(() -> _filter(text, _effective_pattern(pattern_cell[], ci_cell[]), invert_cell[]))   # (elements, kept)
    elements_cv = CellVector(() -> both[][1])
    kept_cell = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(kept_cell[], text, TextBlock(elements_cv, Cell(nothing)), text.selection))
    output = TextBlock(elements_cv, out_selection)
    TextFilteringIoMap(p, text, output, kept_cell)
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

# ── Selection / reference mapping ───────────────────────────────────────────

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

# A whole-element selection at this layer is either `∅` (the whole text) or a
# `TextSpanReferenceStep(s,e)…∅` box over a flat character range — the same
# two shapes `SyntaxToText` emits and `TextToGraphics` highlights. Both index the
# flat character space, which filtering leaves unchanged within a kept line, so
# they map identically in either direction.
_is_structural_ref(ref) =
    ref isa EmptyReference ||
    (ref isa ConcreteReference && ref.head isa TextSpanReferenceStep)

# Forward: input flat caret → output position by finding in_span in the kept
# table. Returns nothing when the line was filtered out (the selection has no
# image in the output).
# input flat caret → output flat caret via the kept table. Takes the blocks
# explicitly so `print_document` can compute the output selection before the
# `IoMap` exists.
function _forward_map(kept::Vector{Int}, in_block, out_block, sel)
    _is_structural_ref(sel) && return sel
    # Resolve either caret form (flat `TextRangeReferenceStep{k}` or structural
    # `.elements[i].content{k}`); a flat-only read drops the cursor after an edit.
    flat = text_caret_flat(in_block, sel)
    flat === nothing && return nothing
    loc = text_flat_to_elem(in_block, flat)
    loc === nothing && return nothing
    in_span, in_char = loc
    j = findfirst(==(in_span), kept)
    j === nothing && return nothing
    f = text_elem_to_flat(out_block, j, in_char)
    f === nothing ? nothing : _flat_caret(f)
end

map_reference_forward(p::TextFiltering, iomap::TextFilteringIoMap, reference) =
    _forward_map(iomap.kept, iomap.input, iomap.output, reference)

function map_reference_backward(p::TextFiltering, iomap::TextFilteringIoMap, reference)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = text_flat_to_elem(iomap.output, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    kept = iomap.kept
    (out_span < 1 || out_span > length(kept)) && return nothing
    in_span = kept[out_span]
    f = text_elem_to_flat(iomap.input, in_span, out_char)
    f === nothing ? nothing : _flat_caret(f)
end

function read_intent(p::TextFiltering, iomap::TextFilteringIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Translate a `ReplaceStringRangeOperation` from the filtered output domain back
# to the input domain: remap the element index via the kept table, keep the
# character range unchanged.
function read_intent(p::TextFiltering, iomap::TextFilteringIoMap, op::ReplaceStringRangeOperation)
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
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MousePress) falls through to the base `Projection.read_intent`, which delegates
# via `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::TextFiltering, ::TextFilteringIoMap, op::Operation) = op

# ── Path helpers ────────────────────────────────────────────────────────────

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
