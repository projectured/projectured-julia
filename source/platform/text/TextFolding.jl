# Fragment of `TextModule`.
#
# Text → Text projection that folds regions of lines. A closed `TextFold` hides
# the lines after its first one; the lines stay in the input, so a stage before
# this one, such as `TextLineNumbering`, counts them. The first line of each fold
# gets a triangle in a field of its gutter, and the first line of a closed fold
# gets the placeholder of the fold at its end. The output line `k` is the input
# line `kept[k]`, so the mapping is one run of flat offsets for each line shown.

"""
    TextFolding(; field = :fold, gutter_type = TextGutter, open_mark = "▾",
                closed_mark = "▸", theme = nothing, mark_style, placeholder_style)

Hide the lines that a closed [`TextFold`](@ref) holds after its first line; a
closed fold inside a hidden region is hidden with it. The first line of each fold
gets a triangle, `open_mark` or `closed_mark`, in the field `field` of its gutter,
by name, as `TextLineNumbering` puts its numbers; and the first line of a closed
fold gets the placeholder of the fold at its end, or `…`.

A click on the triangle or on the placeholder answers
`ToggleCollapseOperation(fold)`, and one with no target, as Ctrl+. makes, gets the
innermost fold around the line of the caret. A key that reaches this stage is read
against its output, so the caret steps over a closed fold. Put it after the stages
that count the lines, such as `TextLineNumbering`, so that they count the hidden
lines too.
"""
@projection UntrackedCell struct TextFolding
    field::Symbol
    gutter_type::Any
    open_mark::String
    closed_mark::String
    mark_style::StyleText
    placeholder_style::StyleText
end

TextFolding(; field::Symbol = :fold, gutter_type = TextGutter, open_mark::String = "▾",
            closed_mark::String = "▸", theme = nothing,
            mark_style::StyleText = unwrap_cell(get_text_style(theme, :line_number_text)),
            placeholder_style::StyleText = unwrap_cell(get_text_style(theme, :placeholder_text))) =
    TextFolding(field, gutter_type, open_mark, closed_mark, mark_style, placeholder_style)

"""
    TextFoldingIoMap

The IO map of `TextFolding`: `kept`, a cell of the input index of each output
element.
"""
@iomap struct TextFoldingIoMap
    projection::Any
    input::TextBlock
    output::TextBlock
    kept::Cell
end

# The elements of `text` that stay in view: every element but the lines that a
# closed fold holds after its first line.
function _find_shown_elements(text::TextBlock)
    shown = Int[]
    hidden_until = 0
    for (i, element) in enumerate(text.elements)
        i <= hidden_until && continue
        push!(shown, i)
        element isa TextLine || continue
        fold = element.fold
        (fold isa TextFold && fold.collapsed) && (hidden_until = max(hidden_until, i + fold.line_count))
    end
    shown
end

# The triangle of `fold`, which follows its state.
_make_fold_mark(p::TextFolding, fold::TextFold) =
    TextBlock(TextString(() -> fold.collapsed ? p.closed_mark : p.open_mark,
                         p.mark_style.font, p.mark_style.color))

# The spans that stand for the hidden lines of `fold` at the end of its first line.
function _make_fold_placeholder(p::TextFolding, fold::TextFold)
    placeholder = fold.placeholder
    placeholder isa TextBlock && return Any[element for element in placeholder.elements]
    placeholder isa TextDocument && return Any[placeholder]
    Any[TextString("…", p.placeholder_style.font, p.placeholder_style.color)]
end

# The output line of the input line `line`: its spans and the placeholder while its
# fold is closed, its indentation, its fold, its paths, and a gutter with the
# triangle of its fold.
function _make_folded_line(p::TextFolding, line::TextLine, marks::IdDict, placeholders::IdDict)
    elements = CellVector(Computation(function ()
        spans = Any[span for span in line.elements]
        fold = line.fold
        (fold isa TextFold && fold.collapsed) || return spans
        vcat(spans, get!(() -> _make_fold_placeholder(p, fold), placeholders, fold))
    end))
    field, gutter_type = p.field, p.gutter_type
    gutter = Cell(Computation(function ()
        fold = line.fold
        fold isa TextFold || return line.gutter
        _make_filled_gutter(line.gutter, field, get!(() -> _make_fold_mark(p, fold), marks, fold),
                            gutter_type)
    end))
    TextLine(elements, getfield(line, :indentation), gutter, getfield(line, :fold),
             getfield(line, :soft_breaks), getfield(line, :selection), getfield(line, :mouse_target))
end

function print_document(p::TextFolding, recursion, text::TextBlock, ctx)
    kept = Cell(@computation _find_shown_elements(text))
    # Each output line is made once and kept while its input line is shown, so a
    # fold that closes makes no other line again.
    lines = IdDict{Any, Any}()
    marks = IdDict{Any, Any}()
    placeholders = IdDict{Any, Any}()
    elements = CellVector(Computation(function ()
        out = Any[]
        live = IdDict{Any, Bool}()
        for i in kept[]
            element = text.elements[i]
            if element isa TextLine
                push!(out, get!(() -> _make_folded_line(p, element, marks, placeholders), lines, element))
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
    paths = make_output_path_cells(text, path ->
        _forward_folded(kept[], text, TextBlock(elements, Cell(nothing)), path))
    TextFoldingIoMap(p, text, TextBlock(elements, paths.selection, paths.mouse_target), kept)
end

# The runs of flat offsets that the fold keeps: one for each line shown, as long as
# the line is in the input. A hidden line is in no run, and the placeholder of a
# closed line lies past the end of its run.
_make_fold_runs(kept::Vector{Int}, input::TextBlock, output::TextBlock) =
    _make_flat_runs(input, output, [(i, 0, k, get_flat_length(input.elements[i])) for (k, i) in enumerate(kept)])

# A path that names an element, `.elements[i]…`, with `i` replaced by `index(i)`,
# or `nothing` when that is `nothing`.
function _remap_element_path(path, index)
    path isa ConcreteReference || return nothing
    (path.head isa FieldReferenceStep && path.head.name == "elements") || return nothing
    indexed = path.tail
    (indexed isa ConcreteReference && indexed.head isa RangeReferenceStep) || return nothing
    j = index(indexed.head.start + 1)
    j === nothing && return nothing
    ConcreteReference(path.head, ConcreteReference(RangeReferenceStep(j - 1, j), indexed.tail))
end

# A text selection maps over the runs; any other path into a line, such as one
# into its gutter, maps to the same line.
function _forward_folded(kept::Vector{Int}, input::TextBlock, output::TextBlock, reference)
    reference isa EmptyReference && return reference
    mapped = _map_selection_over_runs(_make_fold_runs(kept, input, output), input, reference)
    mapped === nothing || return mapped
    _remap_element_path(strip_reference_types(reference), i -> findfirst(==(i), kept))
end

map_reference_forward(::TextFolding, iomap::TextFoldingIoMap, reference) =
    _forward_folded(unwrap_cell(iomap.kept), iomap.input, iomap.output, reference)

# The output line `k` as the input line, or `nothing`.
_get_kept_line(kept::Vector{Int}) = k -> 1 <= k <= length(kept) ? kept[k] : nothing

# The output line whose triangle a path names, `.elements[k].gutter.<field>…`, or
# `nothing`.
function _find_fold_mark_line(p::TextFolding, reference)
    reference isa Reference || return nothing
    split = _split_gutter_reference(strip_reference_types(reference))
    split === nothing && return nothing
    line, rest = split
    (rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
     rest.head.name == String(p.field)) ? line : nothing
end

function map_reference_backward(p::TextFolding, iomap::TextFoldingIoMap, reference)
    reference isa EmptyReference && return reference
    # The triangle has no pre-image.
    _find_fold_mark_line(p, reference) === nothing || return nothing
    kept = unwrap_cell(iomap.kept)
    runs = _reverse_flat_runs(_make_fold_runs(kept, iomap.input, iomap.output))
    mapped = _map_selection_over_runs(runs, iomap.output, reference)
    mapped === nothing || return mapped
    _remap_element_path(strip_reference_types(reference), _get_kept_line(kept))
end

# The fold that a selection of the output clicks: the fold of the line whose
# triangle it selects, or the fold of the closed line whose placeholder holds its
# caret. `nothing` for any other selection.
function _find_clicked_fold(p::TextFolding, iomap::TextFoldingIoMap, path)
    input, output = iomap.input, iomap.output
    kept = unwrap_cell(iomap.kept)
    k = _find_fold_mark_line(p, path)
    if k !== nothing
        line = input.elements[kept[k]]
        return line isa TextLine && line.fold isa TextFold ? line.fold : nothing
    end
    path isa Reference || return nothing
    caret = get_flat_caret(output, path)
    caret === nothing && return nothing
    offsets = get_flat_offsets(output)
    for (k, start) in enumerate(offsets)
        caret < start && break
        caret <= start + get_flat_length(output.elements[k]) || continue
        line = input.elements[kept[k]]
        (line isa TextLine && line.fold isa TextFold && line.fold.collapsed) || return nothing
        return caret > start + get_flat_length(line) ? line.fold : nothing
    end
    nothing
end

function read_intent(p::TextFolding, iomap::TextFoldingIoMap, op::ReplacePathOperation)
    path = get_operation_path(op)
    if op isa ReplaceSelectionOperation
        fold = _find_clicked_fold(p, iomap, path)
        fold === nothing || return ToggleCollapseOperation(fold)
    end
    input_path = map_reference_backward(p, iomap, path)
    input_path === nothing ? nothing : make_path_operation(op, input_path)
end

# The innermost fold of `text` around the line of its caret, or `nothing`.
function _find_innermost_fold(text::TextBlock)
    selection = get_selection(text)
    selection isa Reference || return nothing
    caret = get_flat_caret(text, selection)
    caret === nothing && return nothing
    line = findlast(start -> start <= caret, get_flat_offsets(text))
    line === nothing && return nothing
    for j in line:-1:1
        element = text.elements[j]
        element isa TextLine || continue
        fold = element.fold
        (fold isa TextFold && j + fold.line_count >= line) && return fold
    end
    nothing
end

# A fold with no target, from Ctrl+., gets the innermost fold around the caret; a
# stage before this one passes an operation that has a target.
function read_intent(::TextFolding, iomap::TextFoldingIoMap, op::ToggleCollapseOperation)
    op.target === nothing || return op
    fold = _find_innermost_fold(iomap.input)
    fold === nothing ? op : ToggleCollapseOperation(fold)
end

# An edit of a span of a line shown is an edit of the same span of its input line.
# A span of the placeholder has no pre-image.
function read_intent(::TextFolding, iomap::TextFoldingIoMap, op::ReplaceStringRangeOperation)
    kept = unwrap_cell(iomap.kept)
    path = _remap_element_path(strip_reference_types(op.reference), _get_kept_line(kept))
    path === nothing && return nothing
    _is_input_span_path(iomap.input, path) || return nothing
    ReplaceStringRangeOperation(path, op.replacement)
end

# Whether `path`, `.elements[i].elements[j]…`, names a span that the input line `i`
# holds, or names no span of a line at all.
function _is_input_span_path(input::TextBlock, path::ConcreteReference)
    line = input.elements[path.tail.head.start + 1]
    rest = path.tail.tail
    (line isa TextLine && rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
     rest.head.name == "elements") || return true
    indexed = rest.tail
    (indexed isa ConcreteReference && indexed.head isa RangeReferenceStep) || return true
    indexed.head.stop <= length(line.elements)
end

# A write of a value of a part of a line, such as a widget in the gutter, writes
# the same part of its input line. An element write, the edit beside an inline
# image, names output elements and is declined, so the chain reads the key again.
function read_intent(::TextFolding, iomap::TextFoldingIoMap, op::ReplaceReferencedValueOperation)
    is_text_element_write(op) && return nothing
    op.document === nothing || return op
    path = _remap_element_path(strip_reference_types(op.reference), _get_kept_line(unwrap_cell(iomap.kept)))
    path === nothing ? op : ReplaceReferencedValueOperation(nothing, path, op.value)
end

read_intent(::TextFolding, ::TextFoldingIoMap, op::CompoundOperation) =
    is_text_element_write(op) ? nothing : op

# A key is read against the output, so a motion steps over a closed fold, and its
# answer maps back as an answer of the stages after this one does.
function read_intent(p::TextFolding, iomap::TextFoldingIoMap, evt::Union{KeyPress, KeyDown})
    op = _read_lowered_gesture(iomap.output, evt)
    op isa Operation ? read_intent(p, iomap, op) : nothing
end

read_intent(::TextFolding, ::TextFoldingIoMap, payload) = payload isa Operation ? payload : nothing
