"""
    TextHighlightingModule

Text → Text projection. The "highlight all" of a search box: keeps every line of
a `TextText` and paints a background swatch behind the regex matches by setting
`fill_color` on the matched sub-spans (rendered as a background `GraphicsRect` by
`TextToGraphics`).

It is the structural sibling of `WordWrapping` — both split a `TextString` into
adjacent sub-spans and stay invertible through a piecewise offset table. Here the
split happens at match boundaries and the matched runs are restyled, but no
character is inserted or removed, so `HighlightSeg` is `WrapSeg` and the
selection/reader mapping is identical. Matching is per span (the same
span-delimited simplification as `TextFiltering`); a `nothing` pattern is a
pass-through (no highlights), so the projection can sit idle in a pipeline until
a pattern is set on the reactive `pattern` cell.
"""
module TextHighlightingModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextDocument, TextString
import ..ColorModule: StyleColor, color_yellow
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, RangeReference, FieldReference, EmptyReferencePath, strip_reference_types
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
export TextHighlighting, TextHighlightingIoMap, HighlightSeg

# ── Projection struct ───────────────────────────────────────────────────────

"""
    TextHighlighting(pattern; color=color_yellow)
    TextHighlighting(; pattern=nothing, color=color_yellow)

Paint a background swatch behind every match of `pattern` (a `Regex`, a pattern
string, a `Cell` holding either, or `nothing`).

`pattern` is held in a reactive `Cell`, so updating it re-highlights live; a
`nothing` pattern adds no highlights. `color` is the `fill_color` set on matched
sub-spans (glyph color is left untouched so matched text stays readable). Regex
flags live in the `Regex` the caller builds.
"""
struct TextHighlighting <: Projection
    pattern::Cell          # Cell holding the source String | Regex | nothing — reactive
    case_insensitive::Cell # Cell{Bool} — reactive; adds the `i` flag when a source String is compiled
    color::StyleColor
end

TextHighlighting(pattern::Cell; case_insensitive=false, color::StyleColor=color_yellow) =
    TextHighlighting(pattern, case_insensitive isa Cell ? case_insensitive : Cell(case_insensitive), color)
TextHighlighting(pattern::Regex; kw...) = TextHighlighting(Cell(pattern); kw...)
TextHighlighting(pattern::AbstractString; kw...) = TextHighlighting(Cell(String(pattern)); kw...)
TextHighlighting(; pattern=nothing, kw...) =
    TextHighlighting(pattern isa Cell ? pattern : Cell(pattern); kw...)

# Normalise the (reactive) pattern cell value into the `Union{Regex,Nothing}` the
# highlighter consumes. `nothing` / empty source ⇒ no highlights (pass-through); a
# source `String` is compiled (with the `i` flag when `case_insensitive`); a `Regex`
# is used verbatim — flags it carries win, so it ignores `case_insensitive`.
function _effective_pattern(value, case_insensitive::Bool)
    value === nothing && return nothing
    value isa Regex && return value
    s = String(value)
    isempty(s) && return nothing
    case_insensitive ? Regex(s, "i") : Regex(s)
end

# ── Mapping table ───────────────────────────────────────────────────────────

"""
    HighlightSeg(out_index, in_span, in_char_start, length)

One entry per emitted output `TextString` sub-span. `out_index` is its 1-based
position in `output.elements`; `in_span` is the 1-based originating input span;
`in_char_start` is the 0-based char offset of this sub-span within the input
span; `length` is its character count.
"""
struct HighlightSeg
    out_index::Int
    in_span::Int
    in_char_start::Int
    length::Int
end

struct TextHighlightingIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    segs::Cell  # Cell{Vector{HighlightSeg}}
end

# ── Print ───────────────────────────────────────────────────────────────────

function print_document(p::TextHighlighting, recursion, text::TextText, ctx)
    pattern_cell = p.pattern
    ci_cell = p.case_insensitive
    color = p.color
    both = Cell(() -> _highlight(text, _effective_pattern(pattern_cell[], ci_cell[]), color))   # (elements, segs)
    elements_cv = CellVector(() -> both[][1])
    segs_cell = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(segs_cell[], text.selection))
    output = TextText(elements_cv, out_selection)
    TextHighlightingIoMap(p, text, output, segs_cell)
end

# Returns (output_elements::Vector{TextDocument}, segs::Vector{HighlightSeg}).
# A `nothing` pattern keeps every span unchanged (identity). Otherwise each
# TextString is split at match boundaries into alternating unmatched / matched
# sub-spans, matched runs carrying the highlight fill. Non-text elements pass
# through untouched.
function _highlight(text::TextText, pattern, color::StyleColor)
    result = TextDocument[]
    segs = HighlightSeg[]
    fill_cell = Cell(color)
    for (in_span, elem) in enumerate(text.elements)
        if elem isa TextString
            if pattern === nothing
                push!(result, elem)
                push!(segs, HighlightSeg(length(result), in_span, 0, length(elem.content::AbstractString)))
            else
                _highlight_string!(result, segs, elem, in_span, pattern, fill_cell)
            end
        else
            push!(result, elem)
        end
    end
    (result, segs)
end

# Split one input TextString at the (non-empty) matches of `pattern`, appending
# output sub-spans + HighlightSeg entries. Works in character space (via a
# byte→char map) so multi-byte content is handled correctly. A span with no
# match is emitted unchanged (original object reused) with one full-length seg.
function _highlight_string!(result::Vector{TextDocument}, segs::Vector{HighlightSeg},
                            original::TextString, in_span::Int, pattern::Regex, fill_cell::Cell)
    content = original.content::AbstractString
    if isempty(content)
        push!(result, original)
        push!(segs, HighlightSeg(length(result), in_span, 0, 0))
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
        push!(segs, HighlightSeg(length(result), in_span, 0, total_chars))
        return
    end

    chars = collect(content)
    orig_fill = getfield(original, :fill_color)
    emit(start0, len, fill) = begin
        push!(result, _make_span(original, String(chars[start0+1 : start0+len]), fill))
        push!(segs, HighlightSeg(length(result), in_span, start0, len))
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
               Cell(nothing))
end

# ── Selection / reference mapping ───────────────────────────────────────────
# Identical to WordWrapping: the seg table is a piecewise-linear char-offset map.

# Forward: rebuild an input cursor `elements[s].content{c}` against the split
# output by finding the sub-span the cursor falls into. At the exact boundary
# between two sub-spans of the same input span, prefer the start of the next
# sub-span.
function _forward_map(segs::Vector{HighlightSeg}, sel)
    sel === nothing && return nothing
    parsed = _parse_text_elem_path(sel)
    parsed === nothing && return nothing
    in_span, in_char = parsed
    best = nothing
    for seg in segs
        seg.in_span == in_span || continue
        if seg.in_char_start <= in_char <= seg.in_char_start + seg.length
            best = seg
            if in_char == seg.in_char_start && seg.in_char_start != 0
                break
            end
        end
    end
    best === nothing && return nothing
    _text_elem_path(best.out_index, in_char - best.in_char_start)
end

function map_reference_forward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference)
    _forward_map(iomap.segs[], reference)
end

function map_reference_backward(p::TextHighlighting, iomap::TextHighlightingIoMap, reference)
    parsed = _parse_text_elem_path(reference)
    parsed === nothing && return nothing
    out_span, out_char = parsed
    for seg in iomap.segs[]
        seg.out_index == out_span || continue
        return _text_elem_path(seg.in_span, seg.in_char_start + out_char)
    end
    nothing
end

function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Translate a `ReplaceStringRangeOperation` from the split output domain back to
# the unwrapped input domain, shifting the char range by the sub-span's start.
function read_intent(p::TextHighlighting, iomap::TextHighlightingIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    out_span, char_start, char_stop = parsed
    for seg in iomap.segs[]
        seg.out_index == out_span || continue
        new_start = seg.in_char_start + char_start
        new_stop  = seg.in_char_start + char_stop
        new_ref = ConcreteReferencePath(FieldReference("elements"),
                      ConcreteReferencePath(RangeReference(seg.in_span - 1, seg.in_span),
                          ConcreteReferencePath(FieldReference("content"),
                              ConcreteReferencePath(RangeReference(new_start, new_stop),
                                                    EmptyReferencePath()))))
        return ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    nothing
end

# Forward arbitrary events upstream (KeyDown / KeyPress / etc.).
read_intent(::TextHighlighting, ::TextHighlightingIoMap, op) = op

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

# Like `_parse_text_elem_path` but returns the full terminal `(span, start, stop)`.
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
