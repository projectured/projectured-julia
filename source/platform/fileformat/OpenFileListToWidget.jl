# Fragment of `FileFormatModule` — the page of the open files of an editor: a line
# that counts the files, and under it the table of the files, which the grid prints
# through the recursion, so a path in it is a path of the list.
#
#     table.<rest>    children[2].<rest>

"""
    OpenFileListToWidget(; gap)

Draw an [`OpenFileList`](@ref): a line that says how many files are open and how
many of them have unsaved edits, and under it the table of the files, which fills
the rest of the height. A row of the table shows a file: its name, its folder and
its state. A person filters and sorts the table in its bar, and a click on the
name of a file, or a double click on its row, opens the page of the file.
"""
@projection UntrackedCell struct OpenFileListToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _OPEN_FILE_TABLE_STEP = FieldReferenceStep("table")

# The line above the table: the open files, and those of them with unsaved edits.
function _format_open_file_line(list::OpenFileList)
    total = length(list.files)
    total == 0 && return "No file is open."
    line = string(total, total == 1 ? " open file" : " open files")
    unsaved = _count_unsaved_files(list)
    unsaved == 0 ? line : string(line, " · ", unsaved, " unsaved")
end

function print_document(p::OpenFileListToWidget, recursion, list::OpenFileList, ctx)
    line = WidgetLabel("")
    set_cell_computation!(line, () -> _format_open_file_line(list))
    output = GridLayout(Any[line, getfield(list, :table)[]], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, list, output)
    # The grid passes a key by its own selection, so it carries the path of the list
    # below it. The table is a document of the list, which holds its own.
    set_output_path_computations!(output, list, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# `table.<rest>` ↔ the table in the grid.
function map_reference_forward(::OpenFileListToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    (reference isa ConcreteReference && get_reference_head(reference) == _OPEN_FILE_TABLE_STEP) || return nothing
    rest = get_reference_tail(reference)
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(getfield(iomap.input, :table)[], strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), _FILE_PAGE_SECOND_STEPS...)),
                      rest)
end

# A path into the table takes the step of the table; a path into the line names
# nothing, so a press on it leaves the selection where it is; a path to the grid
# itself names the whole list.
function map_reference_backward(::OpenFileListToWidget, iomap::SimpleIoMap, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    isempty(steps) && return EmptyReference()
    (length(steps) >= 2 && steps[1] == _FILE_PAGE_SECOND_STEPS[1] && steps[2] == _FILE_PAGE_SECOND_STEPS[2]) ||
        return nothing
    concat_references(ConcreteReference(_OPEN_FILE_TABLE_STEP, EmptyReference()),
                      get_reference_tail(get_reference_tail(reference)))
end

# The generic bridge maps the answer of the grid back. The page keeps the
# arrangement of its table when the last entry goes, so the next filter or sort of
# the table has an arrangement to go to.
function read_intent(p::OpenFileListToWidget, recursion, change::Intent, iomap::SimpleIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    operation = keep_held_arrangement(answer.operation, getfield(iomap.input, :table)[], _OPEN_FILE_TABLE_STEP)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end
