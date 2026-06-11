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

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString, TextNewline
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, RangeReference, FieldReference, EmptyReferencePath
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
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
    pattern::Cell    # Cell{Union{Regex,Nothing}} — reactive; nothing = keep all
    invert::Bool
end

TextFiltering(pattern::Cell; invert::Bool=false) = TextFiltering(pattern, invert)
TextFiltering(pattern::Regex; invert::Bool=false) = TextFiltering(Cell(pattern), invert)
TextFiltering(pattern::AbstractString; invert::Bool=false) = TextFiltering(Cell(Regex(pattern)), invert)
TextFiltering(; pattern=nothing, invert::Bool=false) =
    TextFiltering(pattern isa Cell ? pattern : Cell(pattern), invert)

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

function projection_print(p::TextFiltering, recursion, text::TextText, ctx)
    pattern_cell = p.pattern
    invert = p.invert
    both = Cell(() -> _filter(text, pattern_cell[], invert))   # (elements, kept)
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

function projection_read(p::TextFiltering, iomap::TextFilteringIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Translate a `StringReplaceRangeOperation` from the filtered output domain back
# to the input domain: remap the element index via the kept table, keep the
# character range unchanged.
function projection_read(p::TextFiltering, iomap::TextFilteringIoMap, op::StringReplaceRangeOperation)
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
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# Forward arbitrary events upstream (KeyDown / KeyPress / etc.) so projections
# above TextFiltering keep getting a chance at them.
projection_read(::TextFiltering, ::TextFilteringIoMap, op) = op

# ── Path helpers ────────────────────────────────────────────────────────────

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

function _parse_text_elem_path(path)
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
