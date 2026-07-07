"""
    TextFilteringModule

Text → Text projection. The `grep` of the projection stack: keeps only the
lines of a `TextText` whose text matches a regex, dropping the rest. Lines are
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
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, RangeReference, FieldReference, EmptyReferencePath, strip_reference_types
import ..ReferenceBuilderModule: var"@reference"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
export TextFiltering, TextFilteringIoMap

# ── Projection struct ───────────────────────────────────────────────────────

"""
    TextFiltering(pattern; invert=false)
    TextFiltering(; pattern=nothing, invert=false)

Keep only the lines of the input `TextText` whose text matches `pattern`
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
struct TextFilteringIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    kept::Cell  # Cell{Vector{Int}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::TextFiltering, recursion, text::TextText, ctx)
    pattern_cell = p.pattern
    ci_cell = p.case_insensitive
    invert_cell = p.invert
    both = Cell(() -> _filter(text, _effective_pattern(pattern_cell[], ci_cell[]), invert_cell[]))   # (elements, kept)
    elements_cv = CellVector(() -> both[][1])
    kept_cell = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(kept_cell[], text.selection))
    output = TextText(elements_cv, out_selection)
    TextFilteringIoMap(p, text, output, kept_cell)
end

# Returns (output_elements::Vector{TextDocument}, kept::Vector{Int}).
# A `nothing` pattern keeps every element (identity filter). Otherwise the
# input is grouped into logical lines — the run of elements up to and including
# each TextNewline — and a line's elements are emitted iff its concatenated
# TextString content matches (XOR invert).
function _filter(text::TextText, pattern, invert::Bool)
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

# Forward: input `elements[in_span].content{char}` → output position by finding
# in_span in the kept table. Returns nothing when the line was filtered out
# (the selection has no image in the output).
function _forward_map(kept::Vector{Int}, sel)
    sel === nothing && return nothing
    parsed = _parse_text_elem_path(sel)
    parsed === nothing && return nothing
    in_span, in_char = parsed
    j = findfirst(==(in_span), kept)
    j === nothing && return nothing
    _text_elem_path(j, in_char)
end

function map_reference_forward(p::TextFiltering, iomap::TextFilteringIoMap, reference)
    _forward_map(iomap.kept[], reference)
end

function map_reference_backward(p::TextFiltering, iomap::TextFilteringIoMap, reference)
    parsed = _parse_text_elem_path(reference)
    parsed === nothing && return nothing
    out_span, out_char = parsed
    kept = iomap.kept[]
    (out_span < 1 || out_span > length(kept)) && return nothing
    _text_elem_path(kept[out_span], out_char)
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
    kept = iomap.kept[]
    (out_span < 1 || out_span > length(kept)) && return nothing
    in_span = kept[out_span]
    new_ref = ConcreteReferencePath(FieldReference("elements"),
                  ConcreteReferencePath(RangeReference(in_span - 1, in_span),
                      ConcreteReferencePath(FieldReference("content"),
                          ConcreteReferencePath(RangeReference(char_start, char_stop),
                                                EmptyReferencePath()))))
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MousePress) falls through to the base `Projection.read_intent`, which delegates
# via `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::TextFiltering, ::TextFilteringIoMap, op::Operation) = op

# ── Path helpers ────────────────────────────────────────────────────────────

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
