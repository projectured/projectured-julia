# Fragment of `TextModule`.
#
# Text → Text projection that numbers the lines of a `TextBlock`: each line gets its
# number in a field of its gutter, by name. A number is left-padded to a width
# derived from the total line count, or to `width` when it is more than 0.
# ── TextLineNumbering ──────────────────────────────────────────────────────

@projection struct TextLineNumbering <: Projection
    width::ImmutableCell{Int}      # 0 = auto (derived from total line count)
    style::ImmutableCell{StyleText}
    field::ImmutableCell{Symbol}   # the field of the gutter that holds the number
    gutter_type::ImmutableCell{Any}  # the type of a gutter that a line with none gets
end

"""
    TextLineNumbering(; width = 0, theme = nothing, style,
                      field = :number, gutter_type = TextGutter)

Number the lines of a `TextBlock`. The number of each line goes into the field
`field` of its gutter: a copy of the gutter of the line
with that field replaced, whose other fields keep their cells, or a new
`gutter_type` for a line with no gutter. Each number is padded to the digits of
the largest number, or to `width`, so the lane of the numbers has one width on
every line. A click that selects a number selects its whole line in the input.
"""
TextLineNumbering(; width::Int = 0, theme = nothing,
                  style::StyleText = unwrap_cell(get_text_style(theme, :line_number_text)),
                  field::Symbol = :number, gutter_type = TextGutter) =
    TextLineNumbering(width, style, field, gutter_type)

print_document(p::TextLineNumbering, recursion, text::TextBlock, ctx) = _print_numbered_lines(p, text)

# ── The number in the gutter ───────────────────────────────────────────────

"""
    TextLineNumberingIoMap

The IO map of `TextLineNumbering`. The output line `i` is the
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
    for line in text.elements
        count += 1
        index[line] = count
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
    mark = TextBlock(TextLine(TextString(() -> (r = numbers[]; lpad(string(get(r.index, line, 0)), r.width)),
                                         style.font, style.color)))
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
        for line in text.elements
            push!(out, get!(() -> _make_numbered_line(p, line, numbers), lines, line))
            live[line] = true
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

function LineNumbering(; width::Int = 0, theme = nothing)
    TextLineNumbering(; width, theme)
end
