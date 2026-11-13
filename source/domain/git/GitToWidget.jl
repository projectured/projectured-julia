# The pages of the git documents and the projection of their texts. A page shows its
# text in a pane that scrolls, and the text domain draws the text: `GitTextToText`
# makes a block of lines of a git text, with the label of each line of a diff in its
# gutter, and takes no edit of it.
#
#     a commit or a change   diff.<rest>      children[1].content.<rest>   the text, in the pane
#     a file at a revision   content.<rest>   children[2].content.<rest>   the text, in the pane
#     a range of commits     table.<rest>     children[2].<rest>           the table, below its line

# The styles of the kinds of the lines of a git text, from a `GitTheme` scaled or not.
_make_git_text_styles(theme) =
    (; subject = get_git_style(theme, :subject_text), fact = get_git_style(theme, :fact_text),
     message = get_git_style(theme, :message_text), section = get_git_style(theme, :section_text),
     file = get_git_style(theme, :file_text), path = get_git_style(theme, :path_text),
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
    paths = make_output_path_cells(text, _forward_git_text)
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
# block.
function _forward_git_text(reference)
    @reference_case reference begin
        text{s:e} => make_flat_range_reference(s, e; direction = get_range_direction(reference))
    end
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

map_reference_forward(::GitTextToText, ::SimpleIoMap, reference) = _forward_git_text(reference)

map_reference_backward(::GitTextToText, iomap::SimpleIoMap, reference) =
    _backward_git_text(iomap.input, iomap.output, reference)

# The reader keeps a selection, the part under the pointer and a drag, at their place
# in the document, and answers no edit: an edit of the text, of its lines or of its
# elements, and a key that the stages after this one give back.
function read_intent(p::GitTextToText, iomap::SimpleIoMap, operation::ReplacePathOperation)
    operation isa Union{ReplaceSelectionOperation, ReplaceMouseTargetOperation, StartDragOperation} ||
        return nothing
    path = _backward_git_text(iomap.input, iomap.output, operation.path)
    path === nothing ? nothing : make_path_operation(operation, path)
end

read_intent(::GitTextToText, ::SimpleIoMap, ::ReplaceRangeOperation) = nothing
read_intent(::GitTextToText, ::SimpleIoMap, ::ReplaceReferencedValueOperation) = nothing
read_intent(::GitTextToText, ::SimpleIoMap, ::Union{KeyPress, KeyDown}) = nothing

# ── The pages ───────────────────────────────────────────────────────────────

"""
    GitCommitToWidget()

Draw a [`GitCommit`](@ref) as a page: its text, a [`GitDiffText`](@ref), in a pane
that scrolls. The text holds the subject, the facts and the message of the commit,
the list of its changed files, and the path and the diff of each changed file.
"""
struct GitCommitToWidget <: Projection end

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
below the title. The text numbers its lines and marks the line that the file names.
"""
@projection UntrackedCell struct GitFileRevisionToWidget <: Projection
    title::StyleText = unwrap_cell(get_git_style(nothing, :path_text))
    gap::Int = get_git_style(nothing, :gap)
end

const _GitPageToWidget = Union{GitCommitToWidget, GitFileChangeToWidget, GitFileRevisionToWidget}

# The field of the document that holds the text of a page, and the steps of the
# place of the pane that shows it, below the root of the page.
_get_page_text_step(::Union{GitCommitToWidget, GitFileChangeToWidget}) = FieldReferenceStep("diff")
_get_page_text_step(::GitFileRevisionToWidget) = FieldReferenceStep("content")

_get_page_pane_steps(::Union{GitCommitToWidget, GitFileChangeToWidget}) =
    (FieldReferenceStep("children"), RangeReferenceStep(0, 1), FieldReferenceStep("content"))
_get_page_pane_steps(::GitFileRevisionToWidget) =
    (FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("content"))

print_document(p::GitCommitToWidget, recursion, commit::GitCommit, ctx) = _print_git_page(p, commit, Any[], 0)

print_document(p::GitFileChangeToWidget, recursion, change::GitFileChange, ctx) =
    _print_git_page(p, change, Any[], 0)

function print_document(p::GitFileRevisionToWidget, recursion, file::GitFileRevision, ctx)
    title = LayoutConstraint(WidgetLabel(string(file.path, " at ", file.revision); text_style = unwrap_cell(p.title));
                             height = Content)
    _print_git_page(p, file, Any[title], p.gap)
end

# The page: the parts `above` the pane, and the pane that shows the text of the
# document and fills the rest of the height. The layout passes a key by its own
# selection, so it carries the part of the path of the document below it.
function _print_git_page(p::_GitPageToWidget, document, above::Vector, gap::Int)
    text = getfield(document, Symbol(_get_page_text_step(p).name))[]
    output = VerticalLayout(Any[above..., WidgetScrollPane(text)]; gap, child_width = Fill, child_height = Fill)
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

# The generic bridge maps the answer of the grid back. The page keeps the
# arrangement of the table when its last entry goes, so the next filter or sort has
# an arrangement to go to, and it opens the commit of a row at its place in the
# range, `commits[j]`.
function read_intent(p::GitCommitRangeToWidget, recursion, change::Intent, iomap::SimpleIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    range = iomap.input
    operation = keep_held_arrangement(answer.operation, getfield(range, :table)[], _RANGE_TABLE_STEP)
    operation = retarget_held_row_open(operation, range, _RANGE_TABLE_STEP)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
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
make_graphics_projection(::Type{<:GitCommit}; measure, appearance) =
    ChainingProjection(GitCommitToWidget(), VerticalLayoutToGraphicsCanvas())

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
