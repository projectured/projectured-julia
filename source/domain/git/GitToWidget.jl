# The pages of the git documents and the projection of their texts. A page shows its
# text in a pane that scrolls, and the text domain draws the text: `GitTextToText`
# makes a block of lines of a git text, with the label of each line of a diff in its
# gutter, and takes no edit of it.
#
#     a commit               table.<rest>     children[2].<rest>           the table of the changes
#                            diff.<rest>      children[3].content.<rest>   the diffs, in the pane
#     a change               diff.<rest>      children[1].content.<rest>   the text, in the pane
#     a file at a revision   content.<rest>   children[2].content.<rest>   the text, in the pane
#     a range of commits     table.<rest>     children[2].<rest>           the table, below its line

# The styles of the kinds of the lines of a git text, from a `GitTheme` scaled or not.
_make_git_text_styles(theme) =
    (; subject = get_git_style(theme, :subject_text), fact = get_git_style(theme, :fact_text),
     message = get_git_style(theme, :message_text), path = get_git_style(theme, :path_text),
     hunk = get_git_style(theme, :hunk_text), kept = get_git_style(theme, :kept_text),
     removed = get_git_style(theme, :removed_text), added = get_git_style(theme, :added_text),
     marked = get_git_style(theme, :marked_text), note = get_git_style(theme, :note_text),
     failure = get_git_style(theme, :failure_text))

# ── The text ────────────────────────────────────────────────────────────────

"""
    GitTextToText(; styles, number)

Draw a [`GitText`](@ref) as a block of lines of the text domain: a `TextLine` for
each [`GitTextLine`](@ref), with one `TextString` in the style of its kind, and the
label of a line of a diff in the number lane of its gutter, in the style `number`.
`styles` holds the styles of a [`GitTheme`](@ref) by the kind of a line.

The flat string of the block is the `text` of the document, so the caret of the
document, `text{s:e}`, is the flat range `{s:e}` of the block. A person selects and
copies, and the text takes no edit: the reader keeps a selection, the part under
the pointer and a drag, and answers no other operation of the text domain.
"""
@projection UntrackedCell struct GitTextToText <: Projection
    styles::NamedTuple = _make_git_text_styles(nothing)
    number::StyleText = unwrap_cell(get_text_style(nothing, :line_number_text))
end

function print_document(p::GitTextToText, recursion, text::GitText, ctx)
    lines = getfield(text, :lines)
    paths = make_output_path_cells(text, path -> _forward_git_text(text, path))
    output = TextBlock(CellVector(@computation _make_git_text_block_lines(p, lines[])), paths.selection,
                       paths.mouse_target)
    SimpleIoMap(p, text, output)
end

# The lines of the block: each in the style of its kind, and with the label of its
# gutter when a line of the text has a label.
function _make_git_text_block_lines(p::GitTextToText, lines::AbstractVector)
    width = maximum(line -> length(line.label), lines; init = 0)
    number = unwrap_cell(p.number)
    TextDocument[_make_git_text_line(p, line, width, number) for line in lines]
end

function _make_git_text_line(p::GitTextToText, line::GitTextLine, width::Int, number::StyleText)
    run = TextString(line.text, unwrap_cell(getproperty(p.styles, line.kind)))
    width == 0 && return TextLine(run)
    TextLine(run; gutter = TextGutter(; number = TextBlock(TextLine(TextString(lpad(line.label, width), number)))))
end

# Forward: the place `.text{s:e}` of the document is the flat range `{s:e}` of the
# block, and the line `.lines[k]` is the caret at the start of line `k`. A place past
# the end of the text has no image: a kept caret of a commit names a place in the
# diffs of another node.
function _forward_git_text(text::GitText, reference)
    @reference_case reference begin
        text{s:e} => max(s, e) <= length(text.text) ?
                     make_flat_range_reference(s, e; direction = get_range_direction(reference)) : nothing
        lines[k] => _make_git_line_start(getfield(text, :lines)[], k)
    end
end

# The caret at the start of line `k` of `lines`, or `nothing` when the text has no
# such line: each line before it counts its characters and its line end.
function _make_git_line_start(lines::AbstractVector, k::Integer)
    1 <= k <= length(lines) || return nothing
    start = sum((length(lines[i].text) + 1 for i in 1:(k - 1)); init = 0)
    make_flat_range_reference(start, start)
end

# Backward: the whole block is the whole document, and a place of the block is the
# place `.text{s:e}` of the document.
function _backward_git_text(text::GitText, block, reference)
    strip_reference_types(reference) isa EmptyReference && return EmptyReference()
    range = get_flat_range(block, reference)
    range === nothing && return nothing
    s, e = range
    s == e && return _make_git_text_caret(text, s)
    ConcreteReference(_get_git_text_type(text), FieldReferenceStep("text"),
                      ConcreteReference(String, RangeReferenceStep(s, e, get_range_direction(reference)),
                                        EmptyReference(String)))
end

_make_git_text_caret(::GitDiffText, s::Int) = @reference ::GitDiffText.text::String{s}::Position
_make_git_text_caret(::GitFileText, s::Int) = @reference ::GitFileText.text::String{s}::Position

_get_git_text_type(::GitDiffText) = GitDiffText
_get_git_text_type(::GitFileText) = GitFileText

map_reference_forward(::GitTextToText, iomap::SimpleIoMap, reference) = _forward_git_text(iomap.input, reference)

map_reference_backward(::GitTextToText, iomap::SimpleIoMap, reference) =
    _backward_git_text(iomap.input, iomap.output, reference)

# The reader keeps a selection, the part under the pointer and a drag, at their place
# in the document, and answers no edit: an edit of the text, of its lines or of its
# elements, and a key that the stages after this one give back.
function map_operation_backward(p::GitTextToText, iomap::SimpleIoMap, operation::ReplacePathOperation)
    operation isa Union{ReplaceSelectionOperation, ReplaceMouseTargetOperation, StartDragOperation} ||
        return nothing
    path = _backward_git_text(iomap.input, iomap.output, operation.path)
    path === nothing ? nothing : make_path_operation(operation, path)
end

# The gestures of the lines fire from their table (`_make_git_line_bindings`). A
# listing and a rest of the pointer read it at the line that a person points at. A
# click reads it at the line of the caret that the text domain answers, as an
# override of that caret, so the selection of the person stays.
get_projection_gesture_bindings(::GitTextToText, iomap::SimpleIoMap) =
    _make_git_line_bindings(_find_pointed_line(iomap.input))

function read_gesture(::GitTextToText, iomap::SimpleIoMap, gesture::Union{CollectIntents, MouseDwell};
                      answer = nothing)
    answer === nothing || return nothing
    text = iomap.input
    fire_gesture_bindings(_make_git_line_bindings(_find_pointed_line(text)), text, gesture;
                          selection = get_selection(text))
end

# The line of a click is the line of the caret that the text domain answers, in the
# output of the stage, where the answer was made: the path of the answer maps forward
# again to find it.
function read_gesture(p::GitTextToText, iomap::SimpleIoMap, click::MouseClick; answer = nothing)
    answer isa ReplaceSelectionOperation ||
        return answer === nothing ? invoke(read_gesture, Tuple{Projection, Any, Any}, p, iomap, click) : nothing
    text = iomap.input
    output_path = map_reference_forward(p, iomap, answer.path)
    offset = output_path === nothing ? nothing : get_flat_caret(iomap.output, output_path)
    offset === nothing && return nothing
    line = _find_offset_line(getfield(text, :lines)[], offset)
    fire_gesture_bindings(_make_git_line_bindings(line), text, click; selection = get_selection(text), answer)
end

# The gestures of `line`, a `GitTextLine`, or `nothing`: Ctrl+click opens the file at
# the place of the line, as a visit of the navigator around the page, Ctrl+Shift+click
# opens it in a new tab, and a rest of the pointer shows the file, the revision and
# the line that the click opens. Each has a name, so the command palette runs it at
# the line of the caret. A line with no place has none of them, so a listing shows
# them greyed.
function _make_git_line_bindings(line)
    place = line === nothing ? nothing : line.place
    has_place = (_, _) -> place !== nothing
    open(where) = (_, _, _) -> place === nothing ? nothing :
        OpenPageOperation(GitFileRevision(place.repository, place.revision, place.path; line = place.number),
                          EmptyReference(), where)
    click(modifiers) = MouseClickPattern(:left; modifiers, guard = event -> event.count == 1)
    here = "Open the file at this line"
    new_tab = "Open the file at this line in a new tab"
    GestureBinding[
        GestureBinding(click([:ctrl]), open(:here); applicable = has_place, description = here, domain = "git",
                       override = is_selection_change, name = here),
        GestureBinding(click([:ctrl, :shift]), open(:new_tab); applicable = has_place, description = new_tab,
                       domain = "git", override = is_selection_change, name = new_tab),
        make_tooltip_binding(_ -> _make_git_line_note(line); description = "Show the file that the line opens")]
end

# What a line says when the pointer rests on it: the file, the revision and the line
# that its Ctrl+click opens, or `nothing` for a line with no place.
function _make_git_line_note(line)
    (line === nothing || line.place === nothing) && return nothing
    place = line.place
    TooltipNote(; title = get(_GIT_LINE_TITLES, line.kind, "Line"),
                facts = ["File" => place.path, "Revision" => _format_short_hash(place.revision),
                         "Line" => string(place.number)],
                hint = "Ctrl+click opens the file at this line, and Ctrl+Shift+click opens it in a new tab.")
end

const _GIT_LINE_TITLES = Dict(:path => "Changed file", :hunk => "Start of a hunk", :kept => "Kept line",
                              :removed => "Removed line", :added => "Added line")

# The line that a person points at in a git text: the line under the pointer, or,
# when the pointer is not on the text, the line of the selection.
function _find_pointed_line(text::GitText)
    path = something(get_mouse_target(text), Some(get_selection(text)))
    path isa Reference || return nothing
    lines = getfield(text, :lines)[]
    @reference_case path begin
        text{s:e} => _find_offset_line(lines, s)
        lines[k] => (1 <= k <= length(lines) ? lines[k] : nothing)
    end
end

# The line that holds the flat offset `offset`: each line counts its characters and
# its line end.
function _find_offset_line(lines, offset::Int)
    start = 0
    for line in lines
        stop = start + length(line.text)
        offset <= stop && return line
        start = stop + 1
    end
    nothing
end

map_operation_backward(::GitTextToText, ::SimpleIoMap, ::ReplaceRangeOperation) = nothing
map_operation_backward(::GitTextToText, ::SimpleIoMap, ::ReplaceReferencedValueOperation) = nothing
read_gesture(::GitTextToText, ::SimpleIoMap, ::Union{KeyPress, KeyDown}; answer = nothing) = nothing

# ── The pages ───────────────────────────────────────────────────────────────

"""
    GitFileChangeToWidget()

Draw a [`GitFileChange`](@ref) as a page: its text, a [`GitDiffText`](@ref), in a
pane that scrolls. The text holds the path, the kind, the counts and the revisions
of the change, then its diff.
"""
struct GitFileChangeToWidget <: Projection end

"""
    GitFileRevisionToWidget(; title, gap)

Draw a [`GitFileRevision`](@ref) as a page: its path and its revision in the style
`title`, then its text, a [`GitFileText`](@ref), in a pane that scrolls, `gap`
below the title. The text numbers its lines and marks the line that the file names,
and the page opens with that line in the middle of the pane.
"""
@projection UntrackedCell struct GitFileRevisionToWidget <: Projection
    title::StyleText = unwrap_cell(get_git_style(nothing, :path_text))
    gap::Int = get_git_style(nothing, :gap)
end

const _GitPageToWidget = Union{GitFileChangeToWidget, GitFileRevisionToWidget}

# The field of the document that holds the text of a page, and the steps of the
# place of the pane that shows it, below the root of the page.
_get_page_text_step(::GitFileChangeToWidget) = FieldReferenceStep("diff")
_get_page_text_step(::GitFileRevisionToWidget) = FieldReferenceStep("content")

_get_page_pane_steps(::GitFileChangeToWidget) =
    (FieldReferenceStep("children"), RangeReferenceStep(0, 1), FieldReferenceStep("content"))
_get_page_pane_steps(::GitFileRevisionToWidget) =
    (FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("content"))

print_document(p::GitFileChangeToWidget, recursion, change::GitFileChange, ctx) =
    _print_git_page(p, change, Any[], 0, false)

function print_document(p::GitFileRevisionToWidget, recursion, file::GitFileRevision, ctx)
    title = LayoutConstraint(WidgetLabel(string(file.path, " at ", file.revision); text_style = unwrap_cell(p.title));
                             height = Content)
    _print_git_page(p, file, Any[title], p.gap, true)
end

# The page: the parts `above` the pane, and the pane that shows the text of the
# document and fills the rest of the height. The pane of a file at a revision shows
# the selection of its text when it starts, the caret at the named line. The layout
# passes a key by its own selection, so it carries the part of the path of the
# document below it.
function _print_git_page(p::_GitPageToWidget, document, above::Vector, gap::Int, is_selection_revealed::Bool)
    text = getfield(document, Symbol(_get_page_text_step(p).name))[]
    pane = WidgetScrollPane(text; is_selection_revealed)
    output = VerticalLayout(Any[above..., pane]; gap, child_width = Fill, child_height = Fill)
    iomap = SimpleIoMap(p, document, output)
    set_output_path_computations!(output, document, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The rest of `path` after `steps`, or `nothing` when it does not start with them.
function _find_git_path_below(path, steps)
    path = strip_reference_types(path)
    for step in steps
        (path isa ConcreteReference && path.head == step) || return nothing
        path = path.tail
    end
    path
end

# The rest of `path` after `steps`, with the node types that it holds, or `nothing`
# when it does not start with them.
function _find_typed_path_below(path, steps)
    for step in steps
        (path isa ConcreteReference && path.head == step) || return nothing
        path = path.tail
    end
    path
end

# `diff.<rest>` or `content.<rest>` ↔ the text in the pane.
function map_reference_forward(p::_GitPageToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    step = _get_page_text_step(p)
    rest = _find_git_path_below(reference, (step,))
    rest === nothing && return nothing
    text = getfield(iomap.input, Symbol(step.name))[]
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), _get_page_pane_steps(p)...)),
                      annotate_reference_types(text, rest))
end

# A path into the text takes the step of the text; a path into the title names
# nothing, so a press on it leaves the selection where it is; a path to the layout
# itself names the whole document.
function map_reference_backward(p::_GitPageToWidget, iomap::SimpleIoMap, reference)
    isempty(get_reference_steps(strip_reference_types(reference))) && return EmptyReference()
    rest = _find_git_path_below(reference, _get_page_pane_steps(p))
    rest === nothing ? nothing : ConcreteReference(_get_page_text_step(p), rest)
end

# ── The page of a commit ────────────────────────────────────────────────────

"""
    GitCommitToWidget(; styles, gap)

Draw a [`GitCommit`](@ref) as a page: its header, the subject, the short hash with
the author and the date, and the parents; under it a split pane, with the tree of
the changed files on the left, a quarter of the width, and the diffs of the chosen
node on the right, a [`GitDiffText`](@ref) in a pane that scrolls. A node of the
tree shows its counts, and the icon of a file shows the kind of its change. A press
on a node chooses it; a double press or Return on a file opens the page of its
change. `styles` holds the styles of a [`GitTheme`](@ref), and `gap` is the gap
between the parts.
"""
@projection UntrackedCell struct GitCommitToWidget <: Projection
    styles::NamedTuple = _make_git_text_styles(nothing)
    gap::Int = get_git_style(nothing, :gap)
end

const _COMMIT_TREE_STEP = FieldReferenceStep("tree")
const _COMMIT_DIFF_STEP = FieldReferenceStep("diff")
const _COMMIT_SPLIT_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))
const _COMMIT_HOLDER_STEPS = (_COMMIT_SPLIT_STEPS..., FieldReferenceStep("elements"), RangeReferenceStep(0, 1),
                              FieldReferenceStep("child"))
const _COMMIT_TREE_PLACE_STEPS = (_COMMIT_HOLDER_STEPS..., FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _COMMIT_DIFF_PLACE_STEPS = (_COMMIT_SPLIT_STEPS..., FieldReferenceStep("elements"), RangeReferenceStep(1, 2),
                                  FieldReferenceStep("child"), FieldReferenceStep("content"))

function print_document(p::GitCommitToWidget, recursion, commit::GitCommit, ctx)
    heading = VerticalLayout(Any[]; horizontal_align = :left, gap = p.gap)
    set_cell_computation!(getfield(heading.children, :elements),
                          () -> Cell[Cell(widget) for widget in _build_commit_heading(p, commit)])
    # The one child of a layout whose children follow the tree of the commit, which
    # the commit makes again when its read gives the changes.
    holder = VerticalLayout(CellVector(@computation Any[getfield(commit, :tree)[]]),
                            Cell(:left), Cell(0), Cell(Fill), Cell(Fill), Cell(nothing))
    pane = WidgetScrollPane(getfield(commit, :diff)[])
    split = WidgetSplitPane(:horizontal, Any[LayoutConstraint(holder; width = Relative(1)),
                                             LayoutConstraint(pane; width = Relative(3))])
    output = GridLayout(Any[heading, split], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, commit, output)
    # The grid and the split pane pass a key by their own selection, so each carries
    # the part of the path of the commit below it. The tree and the text are
    # documents of the commit, which hold their own.
    set_output_path_computations!(output, commit, path -> map_reference_forward(p, iomap, path); dormant = false)
    set_output_path_computations!(split, output, path -> _find_typed_path_below(path, _COMMIT_SPLIT_STEPS))
    set_output_path_computations!(holder, output, path -> _find_typed_path_below(path, _COMMIT_HOLDER_STEPS))
    iomap
end

# The header of a commit: the subject, the facts and the parents; a note while the
# read is to come, and the words of git for a read that failed. The rest of the
# message stands above the diffs of the top node.
function _build_commit_heading(p::GitCommitToWidget, commit::GitCommit)
    header = _read_git_answer(getfield(commit, :header))
    header === nothing && return Any[_make_git_label(p, :subject, commit.revision),
                                     _make_git_label(p, :note, "Reading the commit…")]
    header isa GitException && return Any[_make_git_label(p, :subject, commit.revision),
                                          _make_git_label(p, :failure, sprint(showerror, header))]
    facts = string(_format_short_hash(header.hash), " · ", header.author_name, " <", header.author_email, "> · ",
                   header.author_date)
    Any[_make_git_label(p, :subject, header.subject), _make_git_label(p, :fact, facts),
        _make_git_label(p, :fact, _format_parents(header.parents))]
end

# A label of `text` in the style `name` of the projection `p`.
_make_git_label(p, name::Symbol, text::AbstractString) =
    WidgetLabel(String(text); text_style = unwrap_cell(getproperty(p.styles, name)))

# `tree.<rest>` ↔ the tree on the left; `diff.<rest>` ↔ the text in the pane on the
# right.
function map_reference_forward(::GitCommitToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    for (step, place) in ((_COMMIT_TREE_STEP, _COMMIT_TREE_PLACE_STEPS), (_COMMIT_DIFF_STEP, _COMMIT_DIFF_PLACE_STEPS))
        rest = _find_git_path_below(reference, (step,))
        rest === nothing && continue
        part = getfield(iomap.input, Symbol(step.name))[]
        return concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), place...)),
                                 annotate_reference_types(part, rest))
    end
    nothing
end

# A path into the tree or the text takes its step; a path into the header names
# nothing, so a press on it leaves the selection where it is; a path to the grid
# itself names the whole commit.
function map_reference_backward(::GitCommitToWidget, iomap::SimpleIoMap, reference)
    isempty(get_reference_steps(strip_reference_types(reference))) && return EmptyReference()
    for (step, place) in ((_COMMIT_TREE_STEP, _COMMIT_TREE_PLACE_STEPS), (_COMMIT_DIFF_STEP, _COMMIT_DIFF_PLACE_STEPS))
        rest = _find_git_path_below(reference, place)
        rest === nothing || return ConcreteReference(step, rest)
    end
    nothing
end

# The page opens the change of a file node at its place in the commit,
# `changes[j]`, so the address of its page holds no step of the tree.
function map_operation_backward(p::GitCommitToWidget, iomap::SimpleIoMap, operation)
    mapped = invoke(map_operation_backward, Tuple{Projection, Any, Any}, p, iomap, operation)
    # The default map gives each member of a compound to this method.
    operation isa CompoundOperation ? mapped : _retarget_change_open(mapped, iomap.input)
end

# The open of a file node of the tree as the open of its change, `changes[j]`; any
# other operation as it is.
_retarget_change_open(operation, commit::GitCommit) = operation
_retarget_change_open(operation::CompoundOperation, commit::GitCommit) =
    CompoundOperation(Any[_retarget_change_open(member, commit) for member in operation.operations])
function _retarget_change_open(operation::OpenPageOperation, commit::GitCommit)
    (operation.document === nothing && operation.target === nothing) || return operation
    _find_git_path_below(operation.reference, (_COMMIT_TREE_STEP,)) === nothing && return operation
    node = try_evaluate_reference(commit, strip_reference_types(operation.reference), nothing)
    node isa GitFileChange || return operation
    index = findfirst(change -> change === node, collect(commit.changes))
    index === nothing && return operation
    place = extend_reference(EmptyReference(), FieldReferenceStep("changes"), ElementReferenceStep(index))
    OpenPageOperation(nothing, annotate_reference_types(commit, place), operation.place)
end

# ── The page of a range ─────────────────────────────────────────────────────

"""
    GitCommitRangeToWidget(; gap)

Draw a [`GitCommitRange`](@ref) as a page: a line with its revisions, the count of
its commits and its paths, and the state of its read, and under it the table of its
commits, which fills the rest of the height. A row shows the short hash of a commit,
then the columns of the list of gitk: the subject, the author and the date. A person
filters and sorts the table in its bar, and the hash of a row opens the commit.
"""
@projection UntrackedCell struct GitCommitRangeToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _RANGE_LINE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _RANGE_TABLE_PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))
const _RANGE_TABLE_STEP = FieldReferenceStep("table")

# The line above the table: the revisions, the count of the commits, the paths, and
# a read that is still to come or failed.
function _format_range_line(range::GitCommitRange)
    answer = _read_git_answer(getfield(range, :listing))
    count = length(range.commits)
    parts = String[range.revisions, string(count, count == 1 ? " commit" : " commits")]
    isempty(range.paths) || push!(parts, join(range.paths, " "))
    answer isa GitException && push!(parts, sprint(showerror, answer))
    answer === nothing && count == 0 && push!(parts, "reading")
    join(parts, " · ")
end

function print_document(p::GitCommitRangeToWidget, recursion, range::GitCommitRange, ctx)
    line = WidgetLabel("")
    set_cell_computation!(line, () -> _format_range_line(range))
    output = GridLayout(Any[line, getfield(range, :table)[]], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, range, output)
    # The grid passes a key by its own selection, so it carries the path of the range
    # below it. The table is a document of the range, which holds its own.
    set_output_path_computations!(output, range, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# `table.<rest>` ↔ the table in the grid.
function map_reference_forward(::GitCommitRangeToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    rest = _find_git_path_below(reference, (_RANGE_TABLE_STEP,))
    rest === nothing && return nothing
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(getfield(iomap.input, :table)[], strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), _RANGE_TABLE_PLACE_STEPS...)),
                      rest)
end

# A path into the line names nothing, so a press on it leaves the selection where
# it is; a path into the grid itself names the whole range.
function map_reference_backward(::GitCommitRangeToWidget, iomap::SimpleIoMap, reference)
    _find_git_path_below(reference, _RANGE_LINE_STEPS) === nothing || return nothing
    rest = _find_git_path_below(reference, _RANGE_TABLE_PLACE_STEPS)
    rest === nothing ? EmptyReference() : ConcreteReference(_RANGE_TABLE_STEP, rest)
end

# The default map maps the answer of the grid back. The page keeps the
# arrangement of the table when its last entry goes, so the next filter or sort has
# an arrangement to go to, and it opens the commit of a row at its place in the
# range, `commits[j]`.
function map_operation_backward(p::GitCommitRangeToWidget, iomap::SimpleIoMap, operation)
    mapped = invoke(map_operation_backward, Tuple{Projection, Any, Any}, p, iomap, operation)
    # The default map gives each member of a compound to this method.
    operation isa CompoundOperation && return mapped
    range = iomap.input
    mapped = keep_held_arrangement(mapped, getfield(range, :table)[], _RANGE_TABLE_STEP)
    retarget_held_row_open(mapped, range, _RANGE_TABLE_STEP)
end

# ── The titles and the projections ──────────────────────────────────────────

# The title of the tab of a commit: its short hash and its subject, or its revision
# while no read gave them.
function get_document_title(commit::GitCommit)
    header = _read_git_answer(getfield(commit, :header))
    header isa GitCommitHeader ? string(_format_short_hash(header.hash), " ", header.subject) : commit.revision
end

get_document_title(change::GitFileChange) =
    string(_format_change_path(change.kind, change.old_path, change.new_path), " in ",
           _format_short_hash(change.new_revision))

get_document_title(file::GitFileRevision) = string(basename(file.path), " at ", file.revision)

get_document_title(range::GitCommitRange) = range.revisions

# A page draws as its layout inside any document that a renderer draws; the pane and
# the text come back through the recursion of the renderer.
function make_graphics_projection(::Type{<:GitCommit}; measure, appearance)
    theme = get_scaled_theme!(appearance, GitTheme)
    ChainingProjection(GitCommitToWidget(; styles = _make_git_text_styles(theme), gap = get_git_style(theme, :gap)),
                       GridLayoutToGraphicsCanvas())
end

make_graphics_projection(::Type{<:GitFileChange}; measure, appearance) =
    ChainingProjection(GitFileChangeToWidget(), VerticalLayoutToGraphicsCanvas())

make_graphics_projection(::Type{<:GitCommitRange}; measure, appearance) =
    ChainingProjection(
        GitCommitRangeToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        GridLayoutToGraphicsCanvas())

function make_graphics_projection(::Type{<:GitFileRevision}; measure, appearance)
    theme = get_scaled_theme!(appearance, GitTheme)
    ChainingProjection(GitFileRevisionToWidget(; title = get_git_style(theme, :path_text),
                                               gap = get_git_style(theme, :gap)),
                       VerticalLayoutToGraphicsCanvas())
end

# A text draws as the code of a file does: its lines and their gutters in a
# `ScrollLayout`, which the pane of the page takes apart, so the gutter stays at the
# left edge while the lines scroll. A text of a file numbers its lines with
# `TextLineNumbering`; a text of a diff has the labels of its lines.
make_graphics_projection(::Type{<:GitDiffText}; measure, appearance) =
    _make_git_text_projection(GitDiffText, measure, appearance)

make_graphics_projection(::Type{<:GitFileText}; measure, appearance) =
    _make_git_text_projection(GitFileText, measure, appearance)

function _make_git_text_projection(type::Type, measure, appearance)
    text_theme = get_scaled_theme!(appearance, TextTheme)
    line_spacing = make_style_field(TextTheme, text_theme, LineSpacing; name = :code_line_spacing)
    stage = GitTextToText(; styles = _make_git_text_styles(get_scaled_theme!(appearance, GitTheme)),
                          number = unwrap_cell(get_text_style(text_theme, :line_number_text)))
    numbering = type === GitFileText ? (TextLineNumbering(; theme = text_theme),) : ()
    text = ChainingProjection(stage, numbering..., TextBlockToScrollLayout(; measure, theme = text_theme, line_spacing))
    RecursiveProjection(TypeDispatchingProjection(
        type => text,
        TextGutter => TextGutterToGraphics(),
        TextBlock => TextToGraphics(; measure, theme = text_theme),
        GraphicsCanvas => GraphicsToGraphics()))
end
