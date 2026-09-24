# Fragment of `TextModule`.
#
# Text → Text projection. Prepends a reactive line-number prefix to every
# line in the input TextBlock. Lines are delimited by TextNewline elements;
# each prefix is a plain TextString of the form "<n><separator>" where <n>
# is left-padded to a uniform width derived from the total line count (or an
# explicit width when width > 0).
# ── TextLineNumbering ──────────────────────────────────────────────────────

@projection struct TextLineNumbering <: Projection
    width::ImmutableCell{Int}      # 0 = auto (derived from total line count)
    separator::ImmutableCell{String}
    font::ImmutableCell{StyleFont}
end

TextLineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_20) =
    TextLineNumbering(width, separator, font)

# Projection print: wraps input.elements in a reactive Cell that rebuilds
# the output element list whenever the input spans change.  For each line
# (delimited by TextNewline elements) a TextString prefix is inserted before
# the first span on that line.
function print_document(p::TextLineNumbering, recursion, text::TextBlock, ctx)
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
        prefix_color = StyleColor(88/255, 110/255, 117/255, 1.0)
        make_prefix(n) = TextString(lpad(string(n), w) * p.separator, p.font, prefix_color)
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
    out_selection = Cell(@computation begin
        numbered = TextBlock(elements_cv, Cell(nothing))
        _map_selection_over_runs(_make_numbering_runs(text, numbered), text, text.selection)
    end)
    SimpleIoMap(p, text, TextBlock(elements_cv, out_selection))
end

function _line_numbering_span(original::TextString, content::AbstractString)
    TextString(Cell(content),
               getfield(original, :font),
               getfield(original, :font_color),
               getfield(original, :fill_color),
               getfield(original, :line_color),
               getfield(original, :padding),
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

function read_intent(p::TextLineNumbering, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# A raw gesture falls through to the base `Projection.read_intent`, which reads it
# with `read_gesture` of the input block: a key is an edit at the caret of the
# input, or `nothing`, so the stage before this one gets it.

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


# ── Compound convenience constructor ────────────────────────────────────────

function LineNumbering(; width::Int = 0, separator::String = " | ", font=font_ubuntu_monospace_regular_20)
    TextLineNumbering(width=width, separator=separator, font=font)
end
