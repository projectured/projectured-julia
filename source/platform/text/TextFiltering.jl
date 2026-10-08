# Fragment of `TextModule`.
#
# Text → Text projection. The `grep` of the projection stack: keeps only the
# lines of a `TextBlock` whose text matches a regex, dropping the rest. Lines are
# delimited by `TextNewline` elements; a line's match string is the concatenation
# of its `TextString` contents (`TextNewline` / `TextSpacing` / `TextGraphics`
# contribute nothing to the match).
#
# Surviving lines are emitted unchanged — same span objects, same styling, same
# character content — so the mapping is an identity on character offsets and only
# the element (span) index is remapped. This makes the projection invertible by a
# simple `kept` table (`TextFilteringIoMap.kept`): `kept[j]` is the input element
# index of the j-th output element.
#
# A `nothing` pattern is a pass-through (keep every line), so the projection can
# sit permanently in a pipeline with its filter idle until a pattern is set on the
# reactive `pattern` cell.
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
    both = Cell(@computation begin
        pattern = _effective_pattern(pattern_cell[], ci_cell[])
        _is_block_of_lines(text) ? _filter_lines(text, pattern, invert_cell[]) : _filter(text, pattern, invert_cell[])
    end)   # (elements, kept)
    elements_cv = CellVector(@computation both[][1])
    kept_cell = Cell(@computation both[][2])
    paths = make_output_path_cells(text, path ->
        _forward_map(kept_cell[], text, TextBlock(elements_cv, Cell(nothing)), path))
    output = TextBlock(elements_cv, paths.selection, paths.mouse_target)
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

map_reference_forward(p::TextFiltering, iomap::TextFilteringIoMap, reference) =
    _forward_map(iomap.kept, iomap.input, iomap.output, reference)

function map_reference_backward(p::TextFiltering, iomap::TextFilteringIoMap, reference)
    _is_block_of_lines(iomap.input) &&
        return _map_selection_over_runs(_reverse_flat_runs(_make_filter_runs(iomap.kept, iomap.input, iomap.output)),
                                        iomap.output, reference)
    box = _get_text_box(reference)
    box === nothing ||
        return _map_text_box(_reverse_flat_runs(_make_filter_runs(iomap.kept, iomap.input, iomap.output)), box)
    _is_structural_ref(reference) && return reference
    flat = _text_range_caret(reference)
    flat === nothing && return nothing
    loc = convert_flat_offset_to_element(iomap.output, flat)
    loc === nothing && return nothing
    out_span, out_char = loc
    kept = iomap.kept
    (out_span < 1 || out_span > length(kept)) && return nothing
    in_span = kept[out_span]
    f = convert_element_to_flat_offset(iomap.input, in_span, out_char)
    f === nothing ? nothing : _flat_caret(f)
end

function read_intent(p::TextFiltering, iomap::TextFilteringIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# Translate a `ReplaceStringRangeOperation` from the filtered output domain back
# to the input domain: remap the element index via the kept table, keep the
# character range unchanged.
function read_intent(p::TextFiltering, iomap::TextFilteringIoMap, op::ReplaceStringRangeOperation)
    if _is_block_of_lines(iomap.input)
        parsed = _parse_line_span_path(op.reference)
        (parsed === nothing || parsed[3] === nothing) && return nothing
        j, k, (char_start, char_stop) = parsed
        kept = iomap.kept
        1 <= j <= length(kept) || return nothing
        return ReplaceStringRangeOperation(_text_replace_path(Int[kept[j], k], char_start, char_stop),
                                           op.replacement)
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
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Forward any Operation upstream unchanged; a raw gesture (KeyPress/KeyDown/
# MouseClick) falls through to the base `Projection.read_intent`, which delegates
# via `read_gesture(input, evt)` — otherwise a wildcard here would echo the raw
# gesture back as if it were an operation, breaking upstream chain dispatch.
read_intent(::TextFiltering, ::TextFilteringIoMap, op::Operation) = op

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# input and lower it there, as `WordWrapping` does.
read_intent(::TextFiltering, iomap::TextFilteringIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# An element write of the output (the edit beside an inline image) names output
# element indices, which this stage changes. Decline it: the chain then reads the
# gesture again against the input of this stage.
read_intent(::TextFiltering, ::TextFilteringIoMap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) =
    is_text_element_write(op) ? nothing : op

# ── Path helpers ────────────────────────────────────────────────────────────
