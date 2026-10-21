# Fragment of `TextModule`.
#
# MarkedText → Text projection. It prints the string of a `MarkedText` as a block
# of lines, a line for each line of the string, and splits each line at the marks
# of the document: a piece that a mark covers takes the colour of the mark, and a
# piece that no mark covers takes the style of the projection. The flat string of
# the block is the string, so a flat offset of the block is an offset of the
# string, and a place maps to `.text{s:e}` and back with no table.
#
# An edit of the block is an edit of the string at the same offsets: an edit in
# one run, an edit of the lines (Enter, a join, a paste of many lines), and an
# edit that crosses two runs, which the stages after this one give back as the
# key, because they lower an edit to one run.

"""
    MarkedTextToText(; theme = nothing, style, appearance = nothing)

The projection of a `MarkedText`: a line for each line of its string, each line
split at the marks, and each piece that a mark covers in the colour of the mark.

`style` is the font and the colour of a piece that no mark covers; its default
is the `plain_text` of the `TextTheme` `theme`. `appearance` resolves a mark that
names a role or a colour of the palette (`resolve_theme_color`); with `nothing`,
the default `Appearance()` resolves it. Where two marks cover a character, the
later one in `marks` gives its colour. A mark past the end of the string is cut
there, and a mark of no width draws nothing.

A line whose text and pieces did not change keeps its object, so a layout keyed
by the line lays out only the lines that a key or a new set of marks changed.

# Example

    ChainingProjection(MarkedTextToText(), TextToGraphics(measure = FontFileMeasure()))

See also `MarkedText`, the document it draws.
"""
@projection UntrackedCell struct MarkedTextToText <: Projection
    style::StyleText
    appearance::Any
end

MarkedTextToText(; theme = nothing, style = get_text_style(theme, :plain_text),
                 appearance = nothing) =
    MarkedTextToText(style, appearance === nothing ? Appearance() : appearance)

# ── The places ──────────────────────────────────────────────────────────────

# Forward: the place `.text{s:e}` of the document is the flat range `{s:e}` of the
# block, because the lines of the block are the lines of the string.
function _forward_marked_text(reference)
    @reference_case reference begin
        text{s:e} => make_flat_range_reference(s, e)
    end
end

# The place `.text{s:e}` of a `MarkedText`, from a range of its string.
_make_marked_text_path(s::Int, e::Int) =
    ConcreteReference(MarkedText, FieldReferenceStep("text"),
                      ConcreteReference(String, RangeReferenceStep(s, e), EmptyReference(String)))

# Backward: a place of the block, in the flat form or in the structural form that
# an edit leaves behind (`get_flat_range` reads both), is the place `.text{s:e}`.
# A caret keeps its typed form, which the DSL needs for a terminal `::Position`.
function _backward_marked_text(block, reference)
    range = get_flat_range(block, reference)
    range === nothing && return nothing
    s, e = range
    s == e ? (@reference ::MarkedText.text::String{s}::Position) : _make_marked_text_path(s, e)
end

map_reference_forward(::MarkedTextToText, iomap::SimpleIoMap, reference) =
    _forward_marked_text(reference)
map_reference_backward(::MarkedTextToText, iomap::SimpleIoMap, reference) =
    _backward_marked_text(iomap.output, reference)

# ── The print ───────────────────────────────────────────────────────────────

function print_document(p::MarkedTextToText, recursion, document::MarkedText, ctx)
    previous = Ref(Pair{Any, TextLine}[])
    lines() = _compute_marked_lines!(previous, document.text, document.marks, p.style, p.appearance)
    paths = make_output_path_cells(document, _forward_marked_text)
    out = TextBlock(CellVector(@computation lines()), paths.selection, paths.mouse_target)
    SimpleIoMap(p, document, out)
end

# The lines of `text` split at `marks`. Each line has a key, its text and its
# pieces; a line of `previous` keeps its object for each line of the common head
# and of the common tail of the keys, and for each line between them at the same
# place when the count of the lines did not change. `previous` takes the result.
function _compute_marked_lines!(previous::Ref{Vector{Pair{Any, TextLine}}}, text::AbstractString,
                                marks, style::StyleText, appearance)
    texts = split(text, '\n')
    pieces = _compute_line_pieces(texts, marks, appearance)
    keys = Any[(texts[k], pieces[k]) for k in eachindex(texts)]
    old = previous[]
    count, old_count = length(keys), length(old)
    head = 0
    while head < min(count, old_count) && first(old[head + 1]) == keys[head + 1]
        head += 1
    end
    tail = 0
    while tail < min(count, old_count) - head && first(old[old_count - tail]) == keys[count - tail]
        tail += 1
    end
    lines = Vector{Pair{Any, TextLine}}(undef, count)
    for k in 1:count
        kept = k <= head ? old[k] :
               k > count - tail ? old[old_count - (count - k)] :
               count == old_count && first(old[k]) == keys[k] ? old[k] : nothing
        # A new key holds a string of its own, so no kept line holds an old text.
        lines[k] = kept !== nothing ? kept :
                   (String(texts[k]), pieces[k]) => _make_marked_line(texts[k], pieces[k], style)
    end
    previous[] = lines
    TextDocument[last(line) for line in lines]
end

# The pieces of each line: the count of the characters of each piece, and its
# colour, or `nothing` for the style of the projection. A line with no mark is one
# piece.
function _compute_line_pieces(texts::AbstractVector, marks, appearance)
    lengths = [length(text) for text in texts]
    starts = Vector{Int}(undef, length(texts))
    offset = 0
    for k in eachindex(texts)
        starts[k] = offset
        offset += lengths[k] + 1
    end
    covers = [Tuple{Int,Int,Any}[] for _ in texts]
    colors = Dict{Any, Any}()
    for mark in marks
        (mark.text === nothing || mark.start >= mark.stop) && continue
        color = get!(() -> _resolve_mark_color(mark.text, appearance), colors, mark.text)
        k = max(searchsortedlast(starts, mark.start), 1)
        while k <= length(texts) && starts[k] < mark.stop
            a = max(mark.start - starts[k], 0)
            b = min(mark.stop - starts[k], lengths[k])
            a < b && push!(covers[k], (a, b, color))
            k += 1
        end
    end
    [_compute_pieces_of_line(lengths[k], covers[k]) for k in eachindex(texts)]
end

_resolve_mark_color(color::StyleColor, appearance) = color
_resolve_mark_color(color, appearance) = resolve_theme_color(color, appearance)

# The pieces of a line of `line_length` characters that `covers` colour, in the
# order of the marks: at each edge of a cover a piece starts, and a piece takes
# the colour of the last cover that holds it. Two pieces of the same colour side
# by side are one.
function _compute_pieces_of_line(line_length::Int, covers::Vector{Tuple{Int,Int,Any}})
    isempty(covers) && return Tuple{Int,Any}[(line_length, nothing)]
    edges = sort!(unique!(vcat(0, line_length, [c[1] for c in covers], [c[2] for c in covers])))
    pieces = Tuple{Int,Any}[]
    for i in 1:(length(edges) - 1)
        a, b = edges[i], edges[i + 1]
        color = nothing
        for (start, stop, cover_color) in covers
            start <= a && b <= stop && (color = cover_color)
        end
        if !isempty(pieces) && last(pieces)[2] == color
            pieces[end] = (last(pieces)[1] + b - a, color)
        else
            push!(pieces, (b - a, color))
        end
    end
    pieces
end

# A line of `text` with a run for each piece, and one empty run on an empty line,
# so that the line has a height and a style for what is typed there.
function _make_marked_line(text::AbstractString, pieces::Vector{Tuple{Int,Any}}, style::StyleText)
    isempty(text) && return TextLine(TextString("", style))
    runs = TextDocument[]
    index = firstindex(text)
    for (count, color) in pieces
        count == 0 && continue
        stop = prevind(text, nextind(text, index, count))
        piece_style = color === nothing ? style : StyleText(style.font, color)
        push!(runs, TextString(String(text[index:stop]), piece_style))
        index = nextind(text, stop)
    end
    TextLine(runs)
end

# ── The reader ──────────────────────────────────────────────────────────────

function read_intent(p::MarkedTextToText, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = _backward_marked_text(iomap.output, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# An edit of the block, in one run or of its lines, is an edit of the string at
# the same offsets.
function read_intent(p::MarkedTextToText, iomap::SimpleIoMap, op::ReplaceRangeOperation)
    range = get_flat_range(iomap.output, operation_reference(op))
    range === nothing && return nothing
    ReplaceStringRangeOperation(_make_marked_text_path(range...), op.replacement)
end

# A key that the stages after this one give back: an edit that crosses two runs,
# which they lower to one run and so decline. Read against the block with no
# lowering, it is an edit of the string.
function read_intent(p::MarkedTextToText, iomap::SimpleIoMap, evt::Union{KeyPress, KeyDown})
    op = read_gesture(iomap.output, evt)
    op isa ReplaceTextRangeOperation ? read_intent(p, iomap, op) : nothing
end
