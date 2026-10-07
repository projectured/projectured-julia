# The views of tasks: the pane of a group, the title of its tab, and the Tasks
# pane. The pane of a group is a card that says what the whole group does, a
# table with one row for each task, and the detail of the task that a person
# picked. The card follows the `summary` of the group, which a drain writes with
# each change; a row reads the cells of its own task document, so a task that
# reports draws its own row again. What a kind of task adds — its columns, its
# facts and its buttons — the views ask of the task.

# The columns of the table, in the order a reader wants them, and how they share
# the width: the prose most, a number least. The first column holds a square
# button as high as a button of the theme. The columns of the kind of task
# (`get_task_columns`) stand between the state and the progress.
const _LEADING_COLUMNS = ["" => 0, "state" => 1]
const _TRAILING_COLUMNS = ["progress" => 2, "elapsed" => 1, "process" => 1, "processor" => 1,
                           "memory" => 1, "result" => 6]

# The columns of the kind of the tasks of a group, which its first task says.
_get_kind_columns(group) =
    isempty(group.tasks) ? Pair{String,Int}[] : get_task_columns(first(group.tasks))

_get_columns(kind_columns) = vcat(_LEADING_COLUMNS, kind_columns, _TRAILING_COLUMNS)

_make_share_policy(weight) = SizePolicy(nothing, nothing, nothing, Float64(weight))

# The columns of a table: each holds the policy of its width.
function _make_table_columns(p, columns)
    Any[WidgetTableColumn(; policy = index == 1 ? Fixed(round(Int, p.button_size.y[])) :
                                                  _make_share_policy(share))
        for (index, (_, share)) in enumerate(columns)]
end

_get_column_headers(columns) = Any[name for (name, _) in columns]

"""
    TaskGroupDocumentToWidgetPane(; theme styles…)

Draw a [`TaskGroupDocument`](@ref) as the pane of a group: the summary card, the
table of its tasks, and the detail of the selected task, the table above the
detail in a split a person can drag.
"""
@projection UntrackedCell struct TaskGroupDocumentToWidgetPane <: Projection
    button_size::Point2D = get_task_style(nothing, :button_size)
    inline_gap::Int = get_task_style(nothing, :inline_gap)
    stack_gap::Int = get_task_style(nothing, :stack_gap)
    success_color::StyleColor = get_task_style(nothing, :success_color)
    info_color::StyleColor = get_task_style(nothing, :info_color)
    warning_color::StyleColor = get_task_style(nothing, :warning_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    running_color::StyleColor = get_task_style(nothing, :running_color)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

# ── Words and colours ────────────────────────────────────────────────────────

# A time as `opp_repl` writes it, with the unit when it is a count of seconds:
# `0.2 s`, `42 s`, `1:05`, `2:00:13`.
function _format_duration(seconds::Real; precision::Integer = 0)
    text = format_elapsed_time(seconds; precision = precision)
    occursin(':', text) ? text : text * " s"
end

"""A number of bytes in the unit a person reads: `512 B`, `12.3 MB`, `1.2 GB`."""
function format_memory_size(bytes::Integer)
    bytes < 1024 && return string(bytes, " B")
    for (unit, size) in (("GB", 1024^3), ("MB", 1024^2), ("kB", 1024))
        bytes >= size && return string(round(bytes / size; digits = 1), " ", unit)
    end
end

# The colour of a role of a result code, and of the states that have none.
function _get_role_color(p, role::Symbol)
    role === :success ? p.success_color : role === :info ? p.info_color :
    role === :warning ? p.warning_color : role === :error ? p.error_color :
    role === :running ? p.running_color : p.muted_color
end

_make_label(text, color) = WidgetLabel(text; text_style = color)

"""
    make_task_progress_bar(value) -> LayoutConstraint

The progress bar of a task or of a group: a bar that shows `value()` and takes
the width that the buttons beside it leave in their row. The bar authors no
width, so the row decides it, and the row ends at the edge of the card.

`value` is a function, and the bar reads it inside its own cell, so the bar
follows the task without a new print. With no width offered, a row has nothing
to share, and the bar is not drawn.
"""
function make_task_progress_bar(value)
    bar = WidgetProgressBar(0.0; width = 0)
    set_cell_computation!(getfield(bar, :value), () -> Float64(value()))
    LayoutConstraint(bar; width = Fill)
end

# A label whose text and colour follow a computation of `(text, color)`. It
# takes no line while its text is empty.
function _make_live_label(f)
    label = WidgetLabel("")
    set_cell_computation!(getfield(label, :content), () -> f()[1])
    set_cell_computation!(getfield(label, :text_style), () -> f()[2])
    set_cell_computation!(getfield(label, :visible), () -> !isempty(f()[1]))
    label
end

# The word of the state of a group, and its color: running or stopping while it
# goes, cancelled after a stop, else its worst code. It reads the counts, which
# change only when a task starts or ends.
function _get_group_state(p, doc::TaskGroupDocument, group)
    status = getfield(doc, :status)[]
    counts = get_task_group_document_counts(doc)
    status === :running && return ("running", p.running_color)
    status === :stopping && return ("stopping", p.running_color)
    counts.finished == 0 && return ("not started", p.muted_color)
    group.stopping && return ("cancelled", p.warning_color)
    (counts.result, _get_role_color(p, get_result_role(group.codes, counts.result)))
end

# A field of the current execution of a task, as its shadow holds it, or
# `nothing` when the task has no current execution.
function _get_current_field(document::TaskDocument, name::Symbol)
    current = get_current_task_execution(document)
    current === nothing ? nothing : getproperty(current, name)
end

# What a task document says in the column `state`: its result code once it has
# one, else the state it is in.
function _get_task_state(p, group, document::TaskDocument)
    result = get_task_document_result(document)
    result === nothing || return (result.result, _get_role_color(p, get_result_role(group.codes, result.result)))
    status = get_task_document_status(document)
    status === :running && return ("running", p.running_color)
    status === :cancelling && return ("stopping", p.running_color)
    (string(status), p.muted_color)
end

# The time a task took, or is taking: the summary cell is read so a task that
# runs counts on with each drain.
function _format_task_elapsed_time(doc::TaskGroupDocument, document::TaskDocument)
    get_task_group_document_summary(doc)
    started = _get_current_field(document, :start_time)
    started === nothing && return ""
    _format_duration(something(_get_current_field(document, :end_time), time()) - started; precision = 1)
end

function _format_task_progress(document::TaskDocument)
    progress = _get_current_field(document, :progress)
    progress !== nothing && return string(round(Int, 100 * progress), "%")
    something(_get_current_field(document, :position), "")
end

# The column `result`: what a finished task ended with, in the words of
# `opp_repl`, else the last line the task printed.
function _format_task_outcome(document::TaskDocument)
    result = get_task_document_result(document)
    result === nothing || return format_task_result(result)
    output = _get_current_field(document, :output)
    output === nothing ? "" : something(find_last_output_line(output), "")
end

# ── The summary card ─────────────────────────────────────────────────────────

# The card of a group. An inner group shows no actions of its own: its row in
# the outer group stops it and runs it again.
function _build_summary_card(p, doc::TaskGroupDocument; actions::Bool = true)
    group = get_task_group(doc)
    get_summary() = get_task_group_document_summary(doc)
    title = WidgetLabel(() -> getfield(doc, :title)[])
    identifier = WidgetBadge(getfield(doc, :identifier)[]; variant = :outline)
    state = _make_live_label(() -> _get_group_state(p, doc, group))
    heading = HorizontalLayout(Any[title, identifier, state]; vertical_align = :center, gap = p.inline_gap)

    # One chip for each code that has a result, and the tasks that run and wait.
    chips = HorizontalLayout(Any[]; vertical_align = :center, gap = p.inline_gap)
    set_cell_computation!(getfield(chips.children, :elements), () -> begin
        s = get_summary()
        parts = Any[]
        for (code, expected, unexpected) in s.counts
            color = _get_role_color(p, get_result_role(group.codes, code))
            expected > 0 && push!(parts, _make_label(string(expected, " ", code), color))
            unexpected > 0 && push!(parts, _make_label(string(unexpected, " ", code, " unexpected"), color))
        end
        s.running > 0 && push!(parts, _make_label(string(s.running, " running"), p.running_color))
        s.pending > 0 && push!(parts, _make_label(string(s.pending, " waiting"), p.muted_color))
        Cell[Cell(x) for x in parts]
    end)

    timing = WidgetLabel(() -> begin
        s = get_summary()
        parts = String[string(s.finished, " of ", s.total, " finished"),
                       string(group.jobs, " at a time")]
        s.elapsed === nothing || push!(parts, _format_duration(s.elapsed; precision = 0) * " elapsed")
        s.remaining === nothing || push!(parts, "about " * _format_duration(s.remaining; precision = 0) * " left")
        s.rate === nothing || push!(parts, string(round(s.rate; digits = 1), " tasks a minute"))
        s.slowest === nothing ||
            push!(parts, "slowest " * s.slowest[1] * " (" * _format_duration(s.slowest[2]; precision = 1) * ")")
        join(parts, " · ")
    end)
    words = WidgetLabel(() -> begin
        s = get_summary()
        heading = getfield(doc, :status)[] === :finished ? format_task_group_close_description(group) :
                                                          format_task_group_description(group)
        isempty(s.summary) ? heading : heading * ": " * s.summary
    end)
    reason = _make_live_label(() -> begin
        s = get_summary()
        (something(s.reason, ""), s.is_expected ? p.muted_color : _get_role_color(p, get_result_role(group.codes, s.result)))
    end)

    is_going() = getfield(doc, :status)[] in (:running, :stopping)
    run_all = _make_action_button(p, "Run all", () -> is_going() ? nothing : start_task_group_document!(doc); enabled = () -> !is_going())
    stop = _make_action_button(p, "Stop", () -> stop_task_group_document!(doc); enabled = is_going)
    again = _make_action_button(p, "Run unexpected again", () -> rerun_task_group_document!(doc, :unexpected);
                   enabled = () -> !is_going() && !get_summary().is_expected)
    rows = WidgetToggleGroup(Any["all", "running", "unexpected"];
                             values = Any["all", "running", "unexpected"],
                             target = getfield(doc, :row_filter)[], field = "value")
    row = HorizontalLayout(actions ? Any[run_all, stop, again, rows] : Any[rows];
                           vertical_align = :center, gap = p.inline_gap)
    progress = make_task_progress_bar(() -> get_summary().progress)
    preparation = _build_preparation_line(p, doc)
    lines = preparation === nothing ? Any[chips, progress, timing, words, reason, row] :
                                      Any[preparation, chips, progress, timing, words, reason, row]
    WidgetCard(; title = heading, content = VerticalLayout(lines; gap = p.stack_gap, child_width = Fill))
end

# ── The preparation ──────────────────────────────────────────────────────────

# The line of the preparation of a group: what it is, its state, and why it
# failed when it did, with a button that shows it in the detail. `nothing` for a
# group with no preparation.
function _build_preparation_line(p, doc::TaskGroupDocument)
    preparation = get_task_group_preparation(doc)
    preparation === nothing && return nothing
    state = _make_live_label(() -> _get_preparation_label(p, doc))
    show = _make_action_button(p, "Show", () -> select_task_document!(doc, -1); enabled = () -> true)
    HorizontalLayout(Any[state, show]; vertical_align = :center, gap = p.inline_gap)
end

# The words of the state of the preparation and their colour: muted while it
# waits and when it ended as expected, the colour of its code when it did not.
function _get_preparation_label(p, doc::TaskGroupDocument)
    (text, state, expected) = describe_task_group_preparation(doc)
    state === :waiting && return (text, p.muted_color)
    state === :running && return (text, p.running_color)
    expected && return (text, p.muted_color)
    codes = get_result_codes(get_task_group(doc).preparation)
    (text, _get_role_color(p, get_result_role(codes, state)))
end

# The detail of the preparation: the pane of a preparation that is a group, or
# the state, the facts, the earlier executions and the output of one that is one
# task.
function _build_preparation_detail(p, doc::TaskGroupDocument, bounded::Bool)
    preparation = get_task_group_preparation(doc)
    preparation === nothing && return Any[_make_label("This group has no preparation.", p.muted_color)]
    preparation isa TaskGroupDocument && return _build_group_parts(p, preparation, bounded; actions = false)
    Any[_make_live_label(() -> _get_preparation_label(p, doc)),
        _build_task_details(p, getfield(preparation, :task)[], preparation),
        _build_earlier_executions(p, preparation),
        _make_label("stdout", p.muted_color),
        _build_output_pane(() -> collect_task_document_lines(preparation, :output); weight = 2),
        _make_label("stderr", p.muted_color),
        _build_output_pane(() -> collect_task_document_lines(preparation, :error_output); weight = 1)]
end

# A button that runs `action` while `enabled()` holds. A refused action is a
# warning, not a fault of the window.
# An action that takes one argument gets the editor that evaluates the press, as
# the callback of an `InvokeActionOperation` does.
function _make_action_button(p, text, action; enabled)
    button = WidgetButton(text; size = p.button_size, action = editor ->
        _run_guarded(text, applicable(action, editor) ? () -> action(editor) : action))
    set_cell_computation!(getfield(button, :enabled), enabled)
    button
end

# An action must never take the window down with it.
function _run_guarded(what::AbstractString, action)
    try
        action()
    catch e
        @warn "The group refused an action" what exception = e
        nothing
    end
end

# ── The table ────────────────────────────────────────────────────────────────

# The positions of the tasks the choice of rows shows, in the order of the group.
function _compute_shown_indices(doc::TaskGroupDocument)
    documents = collect(getfield(doc, :tasks)[])
    choice = getfield(doc, :row_filter)[]
    word = something(choice.value, "all")
    word == "running" &&
        return [i for (i, d) in enumerate(documents) if get_task_document_status(d) in (:running, :cancelling)]
    word == "unexpected" &&
        return [i for (i, d) in enumerate(documents)
                if (r = get_task_document_result(d)) !== nothing && r.result != r.expected_result]
    collect(eachindex(documents))
end

function _build_table_row(p, doc::TaskGroupDocument, group, kind_columns, index::Int,
                          document::TaskDocument)
    pick = WidgetButton("›"; action = _ -> select_task_document!(doc, index))
    task = getfield(document, :task)[]
    Any[pick,
        _make_live_label(() -> _get_task_state(p, group, document)),
        (WidgetLabel(format_task_column(task, name)) for (name, _) in kind_columns)...,
        WidgetLabel(() -> _format_task_progress(document)),
        WidgetLabel(() -> _format_task_elapsed_time(doc, document)),
        WidgetLabel(() -> _format_or_blank(_get_current_field(document, :process_id))),
        WidgetLabel(() -> (load = _get_current_field(document, :processor_load);
                           load === nothing ? "" : string(round(Int, load), "%"))),
        WidgetLabel(() -> (bytes = _get_current_field(document, :resident_memory);
                           bytes === nothing ? "" : format_memory_size(bytes))),
        WidgetLabel(() -> _format_task_outcome(document))]
end

_format_or_blank(value) = value === nothing ? "" : string(value)

# The table. Its rows are a list built one node at a time as the viewport reaches
# it, so a group of 22,731 runs costs what a group of twenty costs.
function _build_table(p, doc::TaskGroupDocument)
    group = get_task_group(doc)
    kind_columns = _get_kind_columns(group)
    columns = _get_columns(kind_columns)
    function make_row_node(shown, k)
        documents = getfield(doc, :tasks)[]
        index = shown[k]
        node = ListNode(make_widget_table_row(
            _build_table_row(p, doc, group, kind_columns, index, documents[index])))
        set_cell_computation!(getfield(node, :next), () -> begin
            k < length(shown) || return nothing
            following = make_row_node(shown, k + 1)
            set_cell_value!(getfield(following, :prev), node)
            following
        end)
        node
    end
    table = WidgetTable(; column_headers = _get_column_headers(columns),
                        cells = ListNode(make_widget_table_row(Any["" for _ in columns])),
                        columns = _make_table_columns(p, columns))
    set_cell_computation!(getfield(table, :cells), () -> begin
        shown = _compute_shown_indices(doc)
        isempty(shown) ? CellVector() : make_row_node(shown, 1)
    end)
    table
end

# A print with no offered height, such as an image of the whole pane, gives a
# list no extent to size it by. So the table then holds every row the choice
# shows, as a vector, and draws them all.
function _build_whole_table(p, doc::TaskGroupDocument)
    group = get_task_group(doc)
    kind_columns = _get_kind_columns(group)
    columns = _get_columns(kind_columns)
    documents = getfield(doc, :tasks)[]
    rows = Any[_build_table_row(p, doc, group, kind_columns, index, documents[index])
               for index in _compute_shown_indices(doc)]
    WidgetTable(_get_column_headers(columns), rows; columns = _make_table_columns(p, columns))
end

# ── The detail of one task ───────────────────────────────────────────────────

function _build_detail(p, doc::TaskGroupDocument, bounded::Bool)
    group = get_task_group(doc)
    detail = VerticalLayout(Any[]; gap = p.stack_gap, child_width = Fill)
    set_cell_computation!(getfield(detail.children, :elements), () -> begin
        index = getfield(doc, :selected)[]
        index == -1 && return Cell[Cell(x) for x in _build_preparation_detail(p, doc, bounded)]
        documents = getfield(doc, :tasks)[]
        (1 <= index <= length(documents)) ||
            return Cell[Cell(_make_label("Press › on a row to see its task here.", p.muted_color))]
        # A task that is a group shows its own pane: its card, its table and
        # the detail of the task picked in it.
        inner = find_task_group_document(doc, index)
        inner === nothing ||
            return Cell[Cell(x) for x in _build_group_parts(p, inner, bounded; actions = false)]
        document = documents[index]
        task = getfield(document, :task)[]
        parts = Any[]
        push!(parts, _make_live_label(() -> begin
            (text, color) = _get_task_state(p, group, document)
            (format_task_parameters(task) * " — " * text, color)
        end))
        push!(parts, _build_task_details(p, task, document))
        push!(parts, WidgetLabel(() -> begin
            facts = String[]
            process = _get_current_field(document, :process_id)
            process === nothing || push!(facts, "process " * string(process))
            elapsed = _format_task_elapsed_time(doc, document)
            isempty(elapsed) || push!(facts, "elapsed " * elapsed)
            join(facts, " · ")
        end))
        push!(parts, _make_live_label(() -> begin
            result = get_task_document_result(document)
            result === nothing ? ("", p.muted_color) :
                (format_task_result(result),
                 _get_role_color(p, get_result_role(group.codes, result.result)))
        end))
        push!(parts, _build_earlier_executions(p, document))
        stop = WidgetButton("Stop"; size = p.button_size,
                            action = _ -> _run_guarded("stop", () -> _stop_task(group, index)))
        set_cell_computation!(getfield(stop, :enabled), () -> get_task_document_status(document) === :running)
        again = WidgetButton("Run again"; size = p.button_size,
                             action = _ -> _run_guarded("run again", () -> rerun_task_group_document!(doc, [index])))
        set_cell_computation!(getfield(again, :enabled),
                              () -> !(getfield(doc, :status)[] in (:running, :stopping)))
        actions = Any[_make_task_action_button(p, label, action, task)
                      for (label, action) in get_task_actions(task)]
        push!(parts, HorizontalLayout(Any[stop, again, actions...]; vertical_align = :center,
                                      gap = p.inline_gap))
        push!(parts, _make_label("stdout", p.muted_color))
        push!(parts, _build_output_pane(() -> collect_task_document_lines(document, :output); weight = 2))
        push!(parts, _make_label("stderr", p.muted_color))
        push!(parts, _build_output_pane(() -> collect_task_document_lines(document, :error_output);
                                        weight = 1))
        Cell[Cell(x) for x in parts]
    end)
    detail
end

# What the kind of the task says about it, one fact a line, which follows what
# the task ended with.
function _build_task_details(p, task, document::TaskDocument)
    lines = VerticalLayout(Any[]; gap = p.stack_gap, child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () ->
        Cell[Cell(WidgetLabel(line))
             for line in format_task_details(task, get_task_document_result(document))])
    lines
end

# The executions before the current one, the oldest first, each with its verdict
# in the color of its role among the codes of its result. A task that ran once or
# never shows none.
function _build_earlier_executions(p, document::TaskDocument)
    lines = VerticalLayout(Any[]; gap = p.stack_gap, child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () -> begin
        earlier = get_earlier_task_executions(document)
        isempty(earlier) && return Cell[]
        parts = Any[_make_label("Earlier executions", p.muted_color)]
        for (number, execution) in enumerate(earlier)
            (text, result) = describe_task_execution(execution)
            color = result === nothing ? p.muted_color :
                    _get_role_color(p, get_result_role(get_result_codes(result), result.result))
            push!(parts, _make_label(string(number, ". ", text), color))
        end
        Cell[Cell(x) for x in parts]
    end)
    lines
end

# A button that the kind of the task adds: a press calls `action` with the editor
# that evaluates the press and the task.
_make_task_action_button(p, label, action, task) =
    WidgetButton(label; size = p.button_size,
                 action = editor -> _run_guarded(label, () -> action(editor, task)))

# The lines of a stream in a pane of its own that follows the end. The two panes
# of a task share the height that the lines above them leave, by `weight`, and
# the box in each is as high as its lines.
function _build_output_pane(lines; weight)
    area = WidgetTextarea(""; rows = 0)
    set_cell_computation!(getfield(area, :content), () -> begin
        value = lines()
        value isa AbstractVector ? join(value, "\n") : string(something(value, ""))
    end)
    LayoutConstraint(WidgetScrollPane(area; follow_end = true); height = Relative(weight), width = Fill)
end

_stop_task(group, index) = (run = group.runs[index]; run === nothing || stop_task_execution!(run); nothing)

# ── A group as a task ────────────────────────────────────────────────────────

# A task that is a group shows its name in a column of its own.
get_task_columns(::TaskGroup) = ["group" => 3]
format_task_column(group::TaskGroup, column::AbstractString) = column == "group" ? group.name : ""

# ── The tab ──────────────────────────────────────────────────────────────────

"""
    make_task_group_tab_title(doc; name = the title of the group) -> PaneTabTitle

The title of the tab that shows a group. Beside the name it says how far the
group is and the worst that it found:

- while it runs: a turning icon, the count of finished tasks over all of them,
  and a badge for each code that came back unexpected;
- at the end: a check and the count when everything is as expected, or a cross
  in the color of the worst code and a badge for each unexpected code;
- after a stop: a square and `cancelled`.

The tooltip holds the summary card in short. The icon and the badges read the
`counts` and the `status` of the group, which change when a task starts or ends,
and the tooltip reads the summary; so the tab follows the group, and nothing of
the title is written while the group runs.

It is the `make_pane_tab_title` of a group, so `open_pane!` gives each tab of a
group this title, also when its caller gives the name as a plain string.

# Example

    group = wrap_task_group_document(TaskGroup(tasks; name = "builds"))
    open_pane!(group; title = "Builds")
    start_task_group_document!(group)
"""
function make_task_group_tab_title(doc::TaskGroupDocument; name = getfield(doc, :title)[])
    group = get_task_group(doc)
    state() = (status = getfield(doc, :status)[], counts = get_task_group_document_counts(doc),
               cancelled = group.stopping)
    PaneTabTitle(String(name);
                 icon = () -> _get_tab_icon(state()),
                 icon_role = () -> _get_tab_role(group, state()),
                 badges = () -> _make_tab_badges(group, state()),
                 tooltip = () -> _format_tab_tooltip(doc, group))
end

make_pane_tab_title(doc::TaskGroupDocument, name::AbstractString) =
    make_task_group_tab_title(doc; name)

# What the tab of a group is in: not started, running, cancelled, all as
# expected, or with an unexpected code.
function _get_tab_state(state)
    state.status in (:running, :stopping) && return :running
    state.counts.finished == 0 && return :pending
    state.cancelled && return :cancelled
    state.counts.is_expected ? :expected : :unexpected
end

function _get_tab_icon(state)
    kind = _get_tab_state(state)
    kind === :running ? :loader : kind === :pending ? :circle : kind === :cancelled ? :stop :
    kind === :expected ? :circle_check : :x
end

# The role of the icon and of the count: a stop is a warning; else the worst
# code so far when it is unexpected, else the role of the state.
function _get_tab_role(group, state)
    kind = _get_tab_state(state)
    kind === :pending && return nothing
    kind === :cancelled && return :warning
    state.counts.is_expected || return get_result_role(group.codes, state.counts.result)
    kind === :running ? :accent : :success
end

function _make_tab_badges(group, state)
    kind = _get_tab_state(state)
    counts = state.counts
    badges = Any[]
    role = _get_tab_role(group, state)
    if kind === :running
        push!(badges, WidgetBadge(string(counts.finished, "/", counts.total); role))
    elseif kind === :expected
        push!(badges, WidgetBadge(string(counts.total); role))
    elseif kind === :pending
        push!(badges, WidgetBadge(string(counts.total); variant = :secondary))
    elseif kind === :cancelled
        push!(badges, WidgetBadge("cancelled"; role = :warning))
    end
    for (code, _, unexpected) in counts.counts
        unexpected > 0 || continue
        # The tasks that a stop cancelled are what `cancelled` says.
        kind === :cancelled && code == "CANCEL" && continue
        push!(badges, WidgetBadge(string(unexpected, " ", code);
                                  role = get_result_role(group.codes, code)))
    end
    badges
end

# The summary card in short: what the group is, how far it is, what it found,
# and the time.
function _format_tab_tooltip(doc::TaskGroupDocument, group)
    s = get_task_group_document_summary(doc)
    running = getfield(doc, :status)[] in (:running, :stopping)
    heading = running ? format_task_group_description(group) : format_task_group_close_description(group)
    lines = String[string(getfield(doc, :title)[], " (", getfield(doc, :identifier)[], ")"),
                   string(heading, ": ", s.finished, " of ", s.total, " finished, ", s.running,
                          " running, ", group.jobs, " at a time")]
    isempty(s.summary) || push!(lines, s.summary)
    times = String[]
    group.start_time === nothing ||
        push!(times, "Started " * Libc.strftime("%H:%M:%S", group.start_time))
    s.elapsed === nothing || push!(times, _format_duration(s.elapsed) * " elapsed")
    s.remaining === nothing || push!(times, "about " * _format_duration(s.remaining) * " left")
    isempty(times) || push!(lines, join(times, " · "))
    join(lines, "\n")
end

# ── The pane ─────────────────────────────────────────────────────────────────

# The card of a group, and below it its table above the detail of the task that
# a person picked, in a split a person can drag.
function _build_group_parts(p, doc::TaskGroupDocument, bounded::Bool; actions::Bool = true)
    card = _build_summary_card(p, doc; actions)
    tasks = bounded ? _build_table(p, doc) : _build_whole_table(p, doc)
    table = LayoutConstraint(WidgetScrollPane(tasks); width = Fill, height = Fill)
    detail = LayoutConstraint(_build_detail(p, doc, bounded); width = Fill, height = Fill)
    split = LayoutConstraint(WidgetSplitPane(:vertical, Any[table, detail]); width = Fill, height = Fill)
    Any[card, split]
end

function print_document(p::TaskGroupDocumentToWidgetPane, recursion, doc::TaskGroupDocument, ctx)
    bounded = ctx !== nothing && get_exact_height(ctx) !== nothing
    root = VerticalLayout(_build_group_parts(p, doc, bounded); horizontal_align = :left,
                          gap = p.stack_gap)
    iomap = ChildrenIoMap(p, doc, root, Cell(Any[]))
    # The part under the pointer, so a button lights and takes a press.
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(doc, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# ── The Tasks pane ───────────────────────────────────────────────────────────

"""
    TaskGroupListToWidgetPane(; theme styles…)

Draw a [`TaskGroupList`](@ref) as the Tasks pane: one row for each group of the
session, newest first, with its identifier, its title, its kind, the word of its
state, its counts, how far it is and the time, and the buttons that show its
pane, stop it, run its unexpected tasks again, and close its row. A group whose
pane was closed keeps its row, and Show opens the pane again.
"""
@projection UntrackedCell struct TaskGroupListToWidgetPane <: Projection
    button_size::Point2D = get_task_style(nothing, :button_size)
    inline_gap::Int = get_task_style(nothing, :inline_gap)
    stack_gap::Int = get_task_style(nothing, :stack_gap)
    success_color::StyleColor = get_task_style(nothing, :success_color)
    info_color::StyleColor = get_task_style(nothing, :info_color)
    warning_color::StyleColor = get_task_style(nothing, :warning_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    running_color::StyleColor = get_task_style(nothing, :running_color)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

const _LIST_COLUMNS = ("", "group", "title", "kind", "state", "counts", "progress", "elapsed", "")

"""
    make_task_group_list_tab_title(list) -> PaneTabTitle

The title of the Tasks tab: its name, and a badge with the count of the groups
that run while any does.
"""
make_task_group_list_tab_title(list::TaskGroupList) =
    PaneTabTitle("Tasks"; icon = :list,
                 badges = () -> (n = count(g -> getfield(g, :status)[] in (:running, :stopping), list.groups);
                                 n == 0 ? Any[] : Any[WidgetBadge(string(n, " running"); role = :accent)]))

# The counts of a group in a line: each code, then the tasks that run and wait.
function _format_group_counts(counts)
    parts = String[]
    for (code, expected, unexpected) in counts.counts
        expected > 0 && push!(parts, string(expected, " ", code))
        unexpected > 0 && push!(parts, string(unexpected, " ", code, " unexpected"))
    end
    counts.running > 0 && push!(parts, string(counts.running, " running"))
    counts.pending > 0 && push!(parts, string(counts.pending, " waiting"))
    join(parts, " · ")
end

function _build_list_row(p, list::TaskGroupList, doc::TaskGroupDocument)
    group = get_task_group(doc)
    is_going() = getfield(doc, :status)[] in (:running, :stopping)
    show_button = _make_action_button(p, "Show", editor -> open_task_group_pane(editor, list, doc);
                                      enabled = () -> true)
    stop_button = _make_action_button(p, "Stop", () -> stop_task_group_document!(doc); enabled = is_going)
    again_button = _make_action_button(p, "Run unexpected again",
                                       () -> rerun_task_group_document!(doc, :unexpected);
                                       enabled = () -> !is_going() && !get_task_group_document_counts(doc).is_expected)
    close_button = _make_action_button(p, "Close", () -> remove_task_group!(list, doc);
                                       enabled = () -> !is_going())
    Any[show_button,
        WidgetLabel(getfield(doc, :identifier)[]),
        WidgetLabel(() -> getfield(doc, :title)[]),
        WidgetLabel(group.name),
        _make_live_label(() -> _get_group_state(p, doc, group)),
        WidgetLabel(() -> _format_group_counts(get_task_group_document_counts(doc))),
        WidgetLabel(() -> string(round(Int, 100 * get_task_group_document_summary(doc).progress), "%")),
        WidgetLabel(() -> (e = get_task_group_document_summary(doc).elapsed; e === nothing ? "" : _format_duration(e))),
        HorizontalLayout(Any[stop_button, again_button, close_button]; vertical_align = :center,
                         gap = p.inline_gap)]
end

function print_document(p::TaskGroupListToWidgetPane, recursion, list::TaskGroupList, ctx)
    heading = WidgetLabel(() -> begin
        groups = collect(list.groups)
        running = count(g -> getfield(g, :status)[] in (:running, :stopping), groups)
        string(length(groups), length(groups) == 1 ? " group" : " groups", " · ", running, " running")
    end)
    body = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        groups = collect(list.groups)
        isempty(groups) && return Cell[Cell(_make_label(
            "No group of tasks ran in this session yet.", p.muted_color))]
        rows = Any[_build_list_row(p, list, doc) for doc in groups]
        Cell[Cell(WidgetTable(collect(Any, _LIST_COLUMNS), rows))]
    end)
    root = VerticalLayout(Any[heading, LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.stack_gap)
    iomap = ChildrenIoMap(p, list, root, Cell(Any[]))
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(list, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# ── Natural-projection registration ─────────────────────────────────────────

"""
    build_task_graphics_entry(; measure = nothing, appearance = Appearance())
        -> Vector{Pair{Type,Any}}

The rows of the natural renderer that draw a group of tasks as its pane and the
groups of the session as the Tasks pane. Each pane draws with the scaled
`TaskTheme` of `appearance`, and its widgets draw with a widget renderer of
their own, which also takes a click back to the button under it. `measure` is
what the registry gives every row; a row made by hand measures with the font
files.
"""
function build_task_graphics_entry(; measure = nothing, appearance::Appearance = Appearance())
    measured = measure === nothing ? FontFileMeasure() : measure
    theme = get_scaled_theme!(appearance, TaskTheme)
    get_style(name) = get_task_style(theme, name)
    styles = (button_size = get_style(:button_size), inline_gap = get_style(:inline_gap),
              stack_gap = get_style(:stack_gap), success_color = get_style(:success_color),
              info_color = get_style(:info_color), warning_color = get_style(:warning_color),
              error_color = get_style(:error_color), running_color = get_style(:running_color),
              muted_color = get_style(:muted_color))
    widgets() = RecursiveProjection(WidgetToGraphics(; measure = measured,
        theme = get_scaled_theme!(appearance, WidgetTheme),
        graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)))
    Pair{Type,Any}[
        TaskGroupDocument => ChainingProjection(TaskGroupDocumentToWidgetPane(; styles...), widgets()),
        TaskGroupList => ChainingProjection(TaskGroupListToWidgetPane(; styles...), widgets())]
end

function __init__()
    register_natural_graphics!(:task, build_task_graphics_entry)
end
