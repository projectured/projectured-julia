# Fragment of `TaskModule` — the pages of one task, of one execution and of one
# stream, which a navigator shows: what a task did, its acts, its executions and
# its streams; what one execution did; and every line of one stream. A part that
# leads to another page answers `OpenPageOperation` with the document that holds
# it and a path from that document, so the navigator around the page opens it.

"""
    TaskDocumentToWidgetPane(; theme styles…)

Draw a [`TaskDocument`](@ref) as the page of a task: its state, its name, its
kind and its verdict in one line, and the error message of an `ERROR` under it;
Stop, Run again and the buttons of its kind; the document of its kind, or the
lines of its facts when it gives no document; and the cards `Links`, `Process`, `Executions`, `stdout` and `stderr`: the links of its
kind, its process, its executions each a link to its page, and the last lines of each
stream of its current execution with a link to the page of the stream. The page is a column in a scroll area that grows
down; each card folds and keeps its own state, as the page has no group around it. A task
of a group stops and runs again through its group. A task alone shows its identifier
and who started it, and runs again with no group, back in its row. A kind that the editor does
not start has only the buttons of its kind. A task that is a group links to the
page of its group.
"""
@projection UntrackedCell struct TaskDocumentToWidgetPane <: Projection
    button_size::Point2D = get_task_style(nothing, :button_size)
    label_gap::Int = get_widget_style(nothing, :label_gap)
    button_gap::Int = get_widget_style(nothing, :button_gap)
    section_gap::Int = get_widget_style(nothing, :section_gap)
    success_color::StyleColor = get_task_style(nothing, :success_color)
    info_color::StyleColor = get_task_style(nothing, :info_color)
    warning_color::StyleColor = get_task_style(nothing, :warning_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    running_color::StyleColor = get_task_style(nothing, :running_color)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

"""
    TaskExecutionToWidgetPane(; theme styles…)

Draw the shadow of a [`TaskExecution`](@ref) as the page of one execution: when it
started and what it ended with, the facts of the kind of its task, its process,
its times and its use of the machine, and a link to the page of each stream.
"""
@projection UntrackedCell struct TaskExecutionToWidgetPane <: Projection
    button_size::Point2D = get_task_style(nothing, :button_size)
    label_gap::Int = get_widget_style(nothing, :label_gap)
    section_gap::Int = get_widget_style(nothing, :section_gap)
    success_color::StyleColor = get_task_style(nothing, :success_color)
    info_color::StyleColor = get_task_style(nothing, :info_color)
    warning_color::StyleColor = get_task_style(nothing, :warning_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    running_color::StyleColor = get_task_style(nothing, :running_color)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

# How many lines of each stream the page of a task shows before the link to the
# page of the stream.
const _STREAM_PREVIEW_LINES = 8

# A link that names the page at `reference` from `document`.
_make_task_link(text, document, reference::Reference) = WidgetLink(text, DocumentLocator(document, reference))

# A button whose label is a command that opens the page at `reference` from
# `document`.
_make_open_button(p, text, document, reference::Reference) =
    WidgetButton(text; size = p.button_size, gestures = make_open_page_gestures(document, reference; domain = "task"))

_make_steps(steps...) = foldr(ConcreteReference, steps; init = EmptyReference())

# Is `node` a child now of `layout`? A layout of a page that holds the document of a
# kind has the document as its child, and the document holds its own selection.
_is_child_of(layout, node) = run_without_cell_tracking(() ->
    any(k -> layout.children[k] === node, 1:length(layout.children)))

_get_execution_steps(k::Int) = (FieldReferenceStep("executions"), RangeReferenceStep(k - 1, k))

# The card of one stream of an execution: its name and the count of its lines, over
# the link to its page and its last lines; an empty stream is the muted word
# `stdout · empty`, with no card, no link and no lines. The part reads whether the
# stream has a line in a cell of its own, so a later line does not build it again.
function _build_stream_preview(p, document, steps, shadow, field::Symbol)
    name = field === :output ? "stdout" : "stderr"
    page = field === :output ? "stdout_page" : "stderr_page"
    has_lines = Cell(@computation getproperty(shadow, field).count > 0)
    preview = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(preview.children, :elements), () -> begin
        has_lines[] || return Cell[Cell(_make_label(name * " · empty", p.muted_color))]
        link = _make_open_button(p, "Open " * name, document, _make_steps(steps..., FieldReferenceStep(page)))
        lines = VerticalLayout(Any[]; gap = 0, child_width = Fill)
        set_cell_computation!(getfield(lines.children, :elements), () -> begin
            kept = collect_output_lines(getproperty(shadow, field))
            Cell[Cell(_make_label(line, p.muted_color)) for line in kept[max(1, end - _STREAM_PREVIEW_LINES + 1):end]]
        end)
        follow_built_children!(lines)
        title = _make_label(() -> _format_stream_count(name, getproperty(shadow, field).count), p.muted_color)
        Cell[Cell(WidgetCard(; title, content = VerticalLayout(Any[link, lines]; gap = p.section_gap, child_width = Fill),
                             collapsible = true))]
    end)
    follow_built_children!(preview)
    Any[preview]
end

function print_document(p::TaskDocumentToWidgetPane, recursion, document::TaskDocument, ctx)
    task = getfield(document, :task)[]
    place = find_task_document_group(document)
    parts = Any[]
    heading = Any[_make_task_state_badge(document), WidgetLabel(get_document_title(document)),
                  _make_task_header_note(p, document)]
    if place !== nothing
        (group, index) = place
        push!(heading, _make_task_link(() -> "in " * getfield(group, :title)[], group, EmptyReference()))
    end
    # A task alone is a row of the task list: its identifier, and who started it.
    identifier = getfield(document, :identifier)[]
    if !isempty(identifier)
        push!(heading, WidgetBadge(identifier; variant = :outline))
        push!(heading, _make_label(() -> _describe_row_starter(document), p.muted_color))
    end
    push!(parts, HorizontalLayout(heading; vertical_align = :center, gap = p.label_gap))
    push!(parts, _make_task_error_line(p, document))
    push!(parts, _build_task_page_actions(p, document, task, place))
    kind_part = _build_task_kind_part(p, document)
    push!(parts, kind_part)
    append!(parts, _build_task_links_cards(p, task))
    push!(parts, follow_built_children!(_build_process_card(p, place === nothing ? nothing : first(place), () -> document)))
    push!(parts, _build_task_page_executions(p, document))
    push!(parts, _build_task_page_streams(p, document))
    root = WidgetScrollPane(VerticalLayout(parts; horizontal_align = :left, gap = p.section_gap, child_width = Fill);
                            grows = (width = false, height = true))
    iomap = ChildrenIoMap(p, document, root, Cell(Any[]))
    follow_widget_output!(root, document, path -> map_reference_forward(p, iomap, path);
                          is_followed = node -> is_widget_or_layout(node) && !_is_child_of(kind_part, node))
    iomap
end

# What the kind says about a task: its document, drawn by the recursion like
# any document, and nothing when it gives none. A document whose fields are cells
# shows as its following copy (`make_following_document`), so its page is printed
# one time, and its cards keep their fold when the result comes and the kind makes
# its document again. Another document shows as it is.
function _build_task_kind_part(p, document::TaskDocument)
    part = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    has_document = Cell(@computation getfield(document, :kind_document)[] !== nothing)
    shown = Ref{Any}(nothing)
    set_cell_computation!(getfield(part.children, :elements), () -> begin
        has_document[] || return Cell[]
        if shown[] === nothing
            initial = getfield(document, :kind_document)[]
            shown[] = is_followable_document(initial) ?
                make_following_document(() -> something(getfield(document, :kind_document)[], initial)) :
                Cell(@computation getfield(document, :kind_document)[])
        end
        Cell[shown[] isa Cell ? shown[] : Cell(shown[])]
    end)
    part
end

# The card `Links` with the links of the kind of a task, or no card for a kind
# with none.
_build_task_links_cards(p, task) = isempty(get_task_links(task)) ? Any[] :
    Any[WidgetCard(; title = "Links", content = _build_task_links(p, task), collapsible = true)]

# The links of the kind of a task among its facts, one a line: the name of the
# fact, and the link (`get_task_links`). A kind with no links shows none.
_build_task_links(p, task) =
    VerticalLayout(Any[HorizontalLayout(Any[_make_label(link.label, p.muted_color),
                                            _make_task_link(link.text, link.document, link.reference)];
                                        vertical_align = :center, gap = p.label_gap)
                       for link in get_task_links(task)]; gap = p.section_gap, child_width = Fill)

# Who started a task alone, in words, or nothing before its start.
function _describe_row_starter(document::TaskDocument)
    starter = getfield(document, :started_by)[]
    starter === nothing ? "" : "started by " * describe_work_starter(starter)
end

# Stop, Run again and the buttons of the kind. A task of a group acts through its
# group, so the counts of the group follow; a task of no group acts on itself, and
# its Run again is the start of the editor, so a task alone goes back into its row.
# A kind that the editor does not start (`start_task`), such as a task that an agent
# runs and the editor only watches, has no Stop and no Run again: the buttons of
# its kind act on it. A task that is a group links to the page of its group.
function _build_task_page_actions(p, document::TaskDocument, task, place)
    if place === nothing
        stop = WidgetButton("Stop"; size = p.button_size,
                            action = _ -> _run_guarded("stop", () -> stop_task!(document)))
        again = WidgetButton("Run again"; size = p.button_size,
                             action = editor -> _run_guarded("run again",
                                 () -> evaluate_operation(editor, StartTaskOperation(document))))
        set_cell_computation!(getfield(again, :enabled), () -> !(get_task_document_status(document) in (:running, :cancelling)))
    else
        (group, index) = place
        stop = WidgetButton("Stop"; size = p.button_size,
                            action = editor -> _run_guarded("stop",
                                () -> evaluate_operation(editor, StopTaskOperation(group, index))))
        again = WidgetButton("Run again"; size = p.button_size,
                             action = editor -> _run_guarded("run again",
                                () -> evaluate_operation(editor, RerunTaskGroupOperation(group, [index]))))
        set_cell_computation!(getfield(again, :enabled), () -> !(getfield(group, :status)[] in (:running, :stopping)))
    end
    set_cell_computation!(getfield(stop, :enabled), () -> get_task_document_status(document) === :running)
    runs = applicable(start_task, task) ? Any[stop, again] : Any[]
    buttons = Any[runs..., (_make_task_action_button(p, label, action, task)
                            for (label, action) in get_task_actions(task))...]
    if place !== nothing && task isa TaskGroup
        inner = find_task_group_document(place[1], place[2])
        inner === nothing || push!(buttons, _make_open_button(p, "Open the group", inner, EmptyReference()))
    end
    HorizontalLayout(buttons; vertical_align = :center, gap = p.button_gap)
end

# The card `Executions` of the task: the executions, the newest first, each a link
# to its page, with its verdict in the colour of its role.
function _build_task_page_executions(p, document::TaskDocument)
    lines = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () -> begin
        executions = getfield(document, :executions)[]
        isempty(executions) && return Cell[Cell(_make_label("The task did not run yet.", p.muted_color))]
        rows = Any[]
        for k in length(executions):-1:1
            (text, result) = describe_task_execution(executions[k])
            color = result === nothing ? p.muted_color :
                    _get_role_color(p, get_result_role(get_result_codes(result), result.result))
            push!(rows, HorizontalLayout(Any[_make_task_link(string(k), document, _make_steps(_get_execution_steps(k)...)),
                                            _make_label(text, color)];
                                         vertical_align = :center, gap = p.label_gap))
        end
        Cell[Cell(row) for row in rows]
    end)
    follow_built_children!(lines)
    WidgetCard(; title = "Executions", content = lines, collapsible = true)
end

# The last lines of each stream of the current execution, with the links to the
# pages of the streams.
function _build_task_page_streams(p, document::TaskDocument)
    streams = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(streams.children, :elements), () -> begin
        executions = getfield(document, :executions)[]
        isempty(executions) && return Cell[]
        k = length(executions)
        shadow = executions[k]
        parts = vcat(_build_stream_preview(p, document, _get_execution_steps(k), shadow, :output),
                     _build_stream_preview(p, document, _get_execution_steps(k), shadow, :error_output))
        Cell[Cell(part) for part in parts]
    end)
    follow_built_children!(streams)
    streams
end

function print_document(p::TaskExecutionToWidgetPane, recursion, shadow::ACTaskExecution, ctx)
    task = shadow.task
    state = _make_live_label(() -> begin
        result = shadow.result
        result === nothing ? (string(shadow.status), p.muted_color) :
            (format_task_result(result), _get_role_color(p, get_result_role(get_result_codes(result), result.result)))
    end)
    facts = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(facts.children, :elements), () -> begin
        lines = String[format_task_parameters(task)]
        shadow.process_id === nothing || push!(lines, "process " * string(shadow.process_id))
        shadow.start_time === nothing || push!(lines, "started " * Libc.strftime("%H:%M:%S", shadow.start_time))
        shadow.end_time === nothing || push!(lines, "ended " * Libc.strftime("%H:%M:%S", shadow.end_time))
        shadow.start_time === nothing ||
            push!(lines, "elapsed " * _format_duration(something(shadow.end_time, time()) - shadow.start_time; precision = 1))
        shadow.processor_load === nothing || push!(lines, string("processor ", round(Int, shadow.processor_load), "%"))
        shadow.resident_memory === nothing || push!(lines, "memory " * format_memory_size(shadow.resident_memory))
        result = shadow.result
        result === nothing || result.reason === nothing || push!(lines, "reason " * result.reason)
        Cell[Cell(WidgetLabel(line)) for line in lines]
    end)
    follow_built_children!(facts)
    kind = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(kind.children, :elements), () -> begin
        shown = make_task_kind_document(task, shadow.result)
        shown === nothing ? Cell[] : Cell[Cell(shown)]
    end)
    streams = vcat(_build_stream_preview(p, shadow, (), shadow, :output),
                   _build_stream_preview(p, shadow, (), shadow, :error_output))
    root = WidgetScrollPane(
        VerticalLayout(Any[HorizontalLayout(Any[WidgetLabel(get_document_title(shadow)), state];
                                            vertical_align = :center, gap = p.label_gap),
                           facts, kind, _build_task_links_cards(p, task)..., streams...];
                       horizontal_align = :left, gap = p.section_gap, child_width = Fill);
        grows = (width = false, height = true))
    iomap = ChildrenIoMap(p, shadow, root, Cell(Any[]))
    follow_widget_output!(root, shadow, path -> map_reference_forward(p, iomap, path);
                          is_followed = node -> is_widget_or_layout(node) && !_is_child_of(kind, node))
    iomap
end

# ── The page of a stream ─────────────────────────────────────────────────────

"""
    TaskStreamToWidget(; gap)

Draw a [`TaskStream`](@ref) as a grid of one column: the bar at the height of its
content, and below it the lines, which take the rest of the height, so they know
how many lines fit. `gap` is the space between the two.

    children[1].<rest>    bar.<rest>
    children[2].<rest>    lines.<rest>

The grid passes a key to the part that its selection names, so a key reaches a
field of the bar or the lines.
"""
@projection UntrackedCell struct TaskStreamToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _STREAM_PARTS = ("bar" => 1, "lines" => 2)

function print_document(p::TaskStreamToWidget, recursion, stream::TaskStream, ctx)
    output = GridLayout(Any[stream.bar, stream.lines], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, stream, output)
    set_output_path_computations!(output, stream, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

function map_reference_forward(::TaskStreamToWidget, iomap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    head isa FieldReferenceStep || return nothing
    for (name, k) in _STREAM_PARTS
        head.name == name || continue
        return annotate_reference_types(iomap.output, concat_references(
            _make_steps(FieldReferenceStep("children"), RangeReferenceStep(k - 1, k)),
            strip_reference_types(get_reference_tail(reference))))
    end
    nothing
end

function map_reference_backward(::TaskStreamToWidget, iomap, reference)
    reference isa ConcreteReference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(reference))
    length(steps) >= 2 && steps[1] == FieldReferenceStep("children") && steps[2] isa RangeReferenceStep ||
        return EmptyReference()
    k = steps[2].start + 1
    name = only(first(part) for part in _STREAM_PARTS if last(part) == k)
    _make_steps(FieldReferenceStep(name), steps[3:end]...)
end

"""
    TaskStreamLinesToWidget(; row_step, theme styles…)

Draw [`TaskStreamLines`](@ref) as the lines of a stream page: a line of counts,
and a table of the lines that fit the height it is offered, each with its number
and its text in the colour of its mark, beside a scroll bar. The lines come from
the file of the stream, so a stream of a million lines costs what shows. A turn
of the wheel and the scroll bar move the line at the top; while the page follows
the end, the last lines show. `row_step` is the height of a row with its
padding and its rule.
"""
@projection UntrackedCell struct TaskStreamLinesToWidget <: Projection
    row_step::Int = 24
    label_gap::Int = get_widget_style(nothing, :label_gap)
    warning_color::StyleColor = get_task_style(nothing, :warning_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    info_color::StyleColor = get_task_style(nothing, :info_color)
    running_color::StyleColor = get_task_style(nothing, :running_color)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

@iomap struct TaskStreamLinesToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    bar::Any
    rows::Any
    visible::Any
end

# The row at the top: the last rows while the page follows the end, else the row
# of the view, kept inside the rows.
function _compute_stream_top_row(lines::TaskStreamLines, count::Int, visible::Int)
    last_top = max(1, count - visible + 1)
    lines.follow ? last_top : clamp(lines.top_row, 1, last_top)
end

# The colour of a line by its mark, and of the line of the current match.
function _get_stream_line_color(p, mark, found::Bool)
    found && return p.running_color
    mark === :error ? p.error_color : mark === :warning ? p.warning_color :
    mark === :notice ? p.info_color : mark === :progress ? p.muted_color : nothing
end

function _format_stream_counts(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    parts = String[string(output.count, output.count == 1 ? " line" : " lines")]
    for (mark, word) in ((:error, "error"), (:warning, "warning"), (:notice, "notice"), (:progress, "progress"))
        n = get(output.mark_counts, mark, 0)
        n > 0 && push!(parts, string(n, " ", word, n == 1 || mark === :progress ? "" : "s"))
    end
    isempty(lines.filter_text) || push!(parts, string(length(collect_task_stream_rows(lines)), " shown"))
    join(parts, " · ")
end

function print_document(p::TaskStreamLinesToWidget, recursion, lines::TaskStreamLines, ctx)
    height = get_visible_height(ctx)
    step() = max(1, p.row_step)
    visible = Cell(@computation height === nothing ? 40 : max(1, Int(height[]) ÷ step() - 3))
    rows = Cell(@computation collect_task_stream_rows(lines))
    top = Cell(@computation _compute_stream_top_row(lines, length(rows[]), visible[]))
    task = lines.execution[].task
    headers = CellVector(Cell[Cell(WidgetLabel("line")), Cell(WidgetLabel("text"))])
    cells = CellVector(Computation(() -> begin
        shown = rows[]
        first_row = top[]
        numbers = shown[first_row:min(length(shown), first_row + visible[] - 1)]
        texts = _read_stream_lines(lines.index, numbers)
        found = lines.found_line
        Any[CellVector(Cell[Cell(WidgetLabel(string(n); text_style = n == found ? p.running_color : p.muted_color)),
                            Cell(WidgetLabel(text; text_style = _get_stream_line_color(
                                p, find_task_output_mark(task, lines.field, text), n == found)))])
            for (n, text) in zip(numbers, texts)]
    end))
    table = WidgetTable(headers, cells)
    # Positional: orientation, value, thumb_size, thumb_drag, position, size,
    # visible, margin, border, padding, style, tooltip, selection.
    bar = WidgetScrollBar(Cell(:vertical),
                          Cell(@computation compute_scroll_bar_value(top[], length(rows[]), visible[])),
                          Cell(@computation isempty(rows[]) ? 1.0 : min(1.0, visible[] / length(rows[]))),
                          Cell(nothing), Cell(nothing), Cell(nothing), Cell(true), Cell(nothing),
                          Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    counts = WidgetLabel(() -> _format_stream_counts(lines))
    body = HorizontalLayout(Any[LayoutConstraint(table; width = Fill, height = Fill), bar];
                            vertical_align = :top, gap = 0)
    output = VerticalLayout(Any[counts, LayoutConstraint(body; width = Fill, height = Fill)];
                            horizontal_align = :left, gap = p.label_gap, child_width = Fill)
    iomap = TaskStreamLinesToWidgetIoMap(p, lines, output, bar, rows, visible)
    follow_widget_output!(output, lines, path -> map_reference_forward(p, iomap, path))
    iomap
end

# A turn of the wheel moves the line at the top by three lines a notch, and a
# write of the value of the scroll bar is a jump to the line at that value; at the
# last lines the page follows the end again, and above them it stops. Every other
# answer passes on, and so does a turn with Ctrl, which zooms and never scrolls.
function read_intent(p::TaskStreamLinesToWidget, recursion, change::Intent, iomap::TaskStreamLinesToWidgetIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    lines = iomap.input
    count = length(iomap.rows)
    visible = iomap.visible
    top = _compute_stream_top_row(lines, count, visible)
    gesture = change.gesture
    if gesture isa MouseScroll && gesture.dy != 0 && !gesture.modifiers.ctrl
        return Intent(gesture, _make_stream_scroll_operation(lines, top - 3 * gesture.dy, count, visible),
                      change.description, change.domain)
    end
    operation = answer isa Intent ? answer.operation : answer
    value = _find_scroll_bar_value(iomap.bar, operation)
    value === nothing && return answer
    Intent(answer isa Intent ? answer.gesture : gesture,
           _make_stream_scroll_operation(lines, compute_scroll_bar_top_row(value, count, visible), count, visible),
           change.description, change.domain)
end

function _make_stream_scroll_operation(lines::TaskStreamLines, top::Int, count::Int, visible::Int)
    last_top = max(1, count - visible + 1)
    top = clamp(top, 1, last_top)
    _make_stream_view_operation(lines, "top_row" => top, "follow" => top == last_top)
end

# The value that `operation` writes into the scroll bar, or `nothing`.
function _find_scroll_bar_value(bar, operation)
    operation isa CompoundOperation &&
        return something((_find_scroll_bar_value(bar, member) for member in operation.operations)..., nothing)
    write = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    (write isa ReplaceReferencedValueOperation && write.document === bar && write.reference isa ConcreteReference &&
     get_reference_head(write.reference) == FieldReferenceStep("value")) || return nothing
    write.value
end
