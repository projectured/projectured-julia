# Fragment of `TextModule`.
#
# Text → Text projection that numbers the lines of a `TextBlock`. A block of
# `TextLine`s gets the number of each line in a field of its gutter, by name. A
# block of spans has no line to hold a gutter: it gets a reactive prefix span
# before each line, where lines are delimited by `TextNewline` elements and
# embedded '\n's. A number is left-padded to a width derived from the total line
# count, or to `width` when it is more than 0.
# ── TextLineNumbering ──────────────────────────────────────────────────────

@projection struct TextLineNumbering <: Projection
    width::ImmutableCell{Int}      # 0 = auto (derived from total line count)
    separator::ImmutableCell{String}
    style::ImmutableCell{StyleText}
    field::ImmutableCell{Symbol}   # the field of the gutter that holds the number
    gutter_type::ImmutableCell{Any}  # the type of a gutter that a line with none gets
end

"""
    TextLineNumbering(; width = 0, separator = " | ", theme = nothing, style,
                      field = :number, gutter_type = TextGutter)

Number the lines of a `TextBlock`. On a block of `TextLine`s, the number of each
line goes into the field `field` of its gutter: a copy of the gutter of the line
with that field replaced, whose other fields keep their cells, or a new
`gutter_type` for a line with no gutter. Each number is padded to the digits of
the largest number, or to `width`, so the lane of the numbers has one width on
every line. A click that selects a number selects its whole line in the input.
On a block of spans, which has no line to hold a gutter, a number span and
`separator` stand before each line.
"""
TextLineNumbering(; width::Int = 0, separator::String = " | ", theme = nothing,
                  style::StyleText = unwrap_cell(get_text_style(theme, :line_number_text)),
                  field::Symbol = :number, gutter_type = TextGutter) =
    TextLineNumbering(width, separator, style, field, gutter_type)

# Projection print: wraps input.elements in a reactive Cell that rebuilds
# the output element list whenever the input spans change.  For each line
# (delimited by TextNewline elements) a TextString prefix is inserted before
# the first span on that line.
function print_document(p::TextLineNumbering, recursion, text::TextBlock, ctx)
    _is_block_of_lines(text) && return _print_numbered_lines(p, text)
    elements_cv = CellVector(@computation begin
        elems = text.elements
        n_newlines = 0
        for e in elems
            if e isa TextNewline
                n_newlines += 1
            elseif e isa TextString
                n_newlines += count(==('\n'), e.content::AbstractString)
            end
        end
        total_lines = n_newlines + 1
        w = p.width > 0 ? p.width : ndigits(total_lines)
        make_prefix(n) = TextString(lpad(string(n), w) * p.separator, p.style)
        result = TextDocument[]
        line = 1
        push!(result, make_prefix(line))
        for elem in elems
            if elem isa TextNewline
                push!(result, elem)
                line += 1
                push!(result, make_prefix(line))
            elseif elem isa TextString && occursin('\n', elem.content::AbstractString)
                parts = split(elem.content::AbstractString, '\n')
                for (i, part) in enumerate(parts)
                    if i < length(parts)
                        push!(result, _line_numbering_span(elem, part * "\n"))
                        line += 1
                        push!(result, make_prefix(line))
                    elseif !isempty(part)
                        push!(result, _line_numbering_span(elem, part))
                    end
                end
            else
                push!(result, elem)
            end
        end
        result
    end)
    paths = make_output_path_cells(text, path -> begin
        numbered = TextBlock(elements_cv, Cell(nothing))
        _map_selection_over_runs(_make_numbering_runs(text, numbered), text, path)
    end)
    SimpleIoMap(p, text, TextBlock(elements_cv, paths.selection, paths.mouse_target))
end

function _line_numbering_span(original::TextString, content::AbstractString)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
               getfield(original, :pointer_shape),
               Cell(nothing))
end

# The flat caret offset of a `TextRangeReferenceStep` selection, or `nothing`.
function _text_range_caret(ref)
    r = strip_reference_types(ref)
    r isa ConcreteReference && r.head isa TextRangeReferenceStep &&
        r.tail isa EmptyReference && r.head.start == r.head.stop || return nothing
    r.head.start::Int
end

# The flat `(start, stop)` of a `TextRangeReferenceStep` selection, a caret or a
# range, or `nothing`.
function _text_range_pair(ref)
    r = strip_reference_types(ref)
    r isa ConcreteReference && r.head isa TextRangeReferenceStep &&
        r.tail isa EmptyReference || return nothing
    (r.head.start::Int, r.head.stop::Int)
end

# The runs of flat offsets that the numbering carries from `input` to `output`: one
# for each output element that holds input text. A number prefix has no input, so
# it lies between two runs and moves the offsets after it.
function _make_numbering_runs(input::TextBlock, output::TextBlock)
    entries = [(in_span, char_offset, j, get_flat_length(output.elements[j]))
               for (j, (in_span, char_offset, is_prefix)) in enumerate(_output_to_input_map(input.elements))
               if !is_prefix]
    _make_flat_runs(input, output, entries)
end

map_reference_forward(p::TextLineNumbering, iomap::SimpleIoMap, reference) =
    _map_selection_over_runs(_make_numbering_runs(iomap.input, iomap.output), iomap.input, reference)

# A caret on a number prefix has no pre-image, so it goes to the first character
# of its line.
map_reference_backward(p::TextLineNumbering, iomap::SimpleIoMap, reference) =
    _map_selection_over_runs(_reverse_flat_runs(_make_numbering_runs(iomap.input, iomap.output)),
                             iomap.output, reference)

function read_intent(p::TextLineNumbering, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# A key reaches this stage only when the stages after it gave no operation, or one
# this stage declines, such as the edit beside an inline image. Read it against the
# input and lower it there, as `WordWrapping` does: a key is an edit at the caret of
# the input, or `nothing`, so the stage before this one gets it.
read_intent(::TextLineNumbering, iomap::SimpleIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

# A string edit of the output names an output span, and the number spans of this
# stage move the spans. Decline it: the chain then reads the key again against the
# input, where the edit is made.
read_intent(::TextLineNumbering, ::SimpleIoMap, ::ReplaceStringRangeOperation) = nothing

# Walk the input element list mirroring the printer's prefix-insertion
# logic. For each emitted output element, record the corresponding input
# element index and char offset, or mark it as a projection-inserted prefix.
function _output_to_input_map(input_elems)
    result = Tuple{Int, Int, Bool}[]
    push!(result, (0, 0, true))  # leading prefix
    for (in_idx, elem) in enumerate(input_elems)
        if elem isa TextNewline
            push!(result, (in_idx, 0, false))
            push!(result, (0, 0, true))
        elseif elem isa TextString && occursin('\n', elem.content::AbstractString)
            parts = split(elem.content::AbstractString, '\n')
            char_offset = 0
            for (i, part) in enumerate(parts)
                if i < length(parts)
                    push!(result, (in_idx, char_offset, false))
                    char_offset += length(part) + 1
                    push!(result, (0, 0, true))
                elseif !isempty(part)
                    push!(result, (in_idx, char_offset, false))
                end
            end
        else
            push!(result, (in_idx, 0, false))
        end
    end
    result
end


# ── A block of lines: the number in the gutter ─────────────────────────────

# Whether `text` is a block of `TextLine`s, which hold a gutter each.
_is_block_of_lines(text::TextBlock) =
    text.elements isa CellVector && length(text.elements) > 0 && text.elements[1] isa TextLine

"""
    TextLineNumberingIoMap

The IO map of `TextLineNumbering` on a block of lines. The output line `i` is the
input line `i` with another gutter, so a path maps to the same path, but a path
into the field of the numbers, which has no pre-image.
"""
@iomap struct TextLineNumberingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
end

# The number of each line, by the line, and the width of the widest number.
function _number_lines(p::TextLineNumbering, text::TextBlock)
    index = IdDict{Any, Int}()
    count = 0
    for element in text.elements
        element isa TextLine || continue
        count += 1
        index[element] = count
    end
    (index = index, width = p.width > 0 ? p.width : ndigits(max(count, 1)))
end

# The gutter `gutter` with `mark` in its field `field`: a copy whose other fields,
# its selection and its part under the pointer keep their cells, or a new
# `gutter_type` when the line has no gutter.
function _make_filled_gutter(gutter, field::Symbol, mark, gutter_type)
    gutter === nothing && return gutter_type(; (field => mark,)...)
    T = typeof(gutter)
    hasfield(T, field) ||
        throw(ArgumentError("TextLineNumbering: the gutter $(nameof(T)) has no field `$(field)`"))
    replacements = Dict{Symbol, Any}(name => getfield(gutter, name) for name in fieldnames(T))
    replacements[field] = mark
    copy_document_fields(PlainCopyPolicy(), gutter; replacements...)
end

# The output line of the input line `line`: its spans, its indentation, its
# selection and its part under the pointer, and a gutter with its number.
function _make_numbered_line(p::TextLineNumbering, line::TextLine, numbers::Cell)
    style = p.style
    mark = TextBlock(TextString(() -> (r = numbers[]; lpad(string(get(r.index, line, 0)), r.width)),
                                style.font, style.color))
    field, gutter_type = p.field, p.gutter_type
    gutter = Cell(@computation _make_filled_gutter(line.gutter, field, mark, gutter_type))
    TextLine(getfield(line, :elements), getfield(line, :indentation), gutter, getfield(line, :fold),
             getfield(line, :soft_breaks), getfield(line, :selection), getfield(line, :mouse_target))
end

function _print_numbered_lines(p::TextLineNumbering, text::TextBlock)
    numbers = Cell(@computation _number_lines(p, text))
    # Each output line is made once and kept while its input line stays, so a new
    # line or a new number makes no other line again.
    lines = IdDict{Any, Any}()
    elements = CellVector(Computation(function ()
        out = Any[]
        live = IdDict{Any, Bool}()
        for element in text.elements
            if element isa TextLine
                push!(out, get!(() -> _make_numbered_line(p, element, numbers), lines, element))
                live[element] = true
            else
                push!(out, element)
            end
        end
        for line in collect(keys(lines))
            haskey(live, line) || delete!(lines, line)
        end
        out
    end))
    paths = make_output_path_cells(text, path -> path)
    TextLineNumberingIoMap(p, text, TextBlock(elements, paths.selection, paths.mouse_target))
end

# The line whose field of the numbers a path names, `.elements[i].gutter.<field>…`,
# or `nothing`.
function _find_numbered_line(p::TextLineNumbering, reference)
    reference isa Reference || return nothing
    split = _split_gutter_reference(strip_reference_types(reference))
    split === nothing && return nothing
    line, rest = split
    (rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
     rest.head.name == String(p.field)) ? line : nothing
end

map_reference_forward(::TextLineNumbering, ::TextLineNumberingIoMap, reference) = reference

map_reference_backward(p::TextLineNumbering, ::TextLineNumberingIoMap, reference) =
    _find_numbered_line(p, reference) === nothing ? reference : nothing

# A selection of a number, as a click makes, selects the whole line in the input.
# Any other path maps to the same path.
function read_intent(p::TextLineNumbering, iomap::TextLineNumberingIoMap, op::ReplacePathOperation)
    line = _find_numbered_line(p, get_operation_path(op))
    line === nothing && return op
    op isa ReplaceSelectionOperation || return nothing
    text = iomap.input
    start = get_flat_offsets(text)[line]
    ReplaceSelectionOperation(make_flat_range_reference(start, start + get_flat_length(text.elements[line])))
end

read_intent(::TextLineNumbering, iomap::TextLineNumberingIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_lowered_gesture(iomap.input, evt)

read_intent(::TextLineNumbering, ::TextLineNumberingIoMap, payload) =
    payload isa Operation ? payload : nothing

# ── Compound convenience constructor ────────────────────────────────────────

function LineNumbering(; width::Int = 0, separator::String = " | ", theme = nothing)
    TextLineNumbering(; width, separator, theme)
end
