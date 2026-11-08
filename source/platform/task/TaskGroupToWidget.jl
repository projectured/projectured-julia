# The views of tasks: the pane of a group, the title of its tab, and the Tasks
# pane. The pane of a group is a card that says what the whole group does, a
# table with one row for each task, and the detail of the task whose row a person
# pressed. The card follows the `summary` of the group, which a drain writes with
# each change; a row reads the cells of its own task document, so a task that
# reports draws its own row again. What a kind of task adds — its columns, its
# facts and its buttons — the views ask of the task.

"""
    TaskGroupDocumentToWidgetPane(; theme styles…)

Draw a [`TaskGroupDocument`](@ref) as the pane of a group: the summary card, the
line of its buttons, the table of its tasks, and the detail of the selected
task, the table above the detail in a split a person can drag. The detail is one
column in a scroll area: each part takes the height of its content, and the
column scrolls.
"""
@projection UntrackedCell struct TaskGroupDocumentToWidgetPane <: Projection
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
    stream_box_height::Int = get_task_style(nothing, :stream_box_height)
end

# ── Words and colours ────────────────────────────────────────────────────────

# A time as `opp_repl` writes it, with the unit when it is a count of seconds:
# `0.2 s`, `42 s`, `1:05`, `2:00:13`.
function _format_duration(seconds::Real; precision::Integer = 0)
    text = format_elapsed_time(seconds; precision = precision)
    occursin(':', text) ? text : text * " s"
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
# takes no line while its text is empty. With `max_lines` above 0 it shows at
# most that many lines, the last cut with "…", and its tooltip holds the whole
# text.
function _make_live_label(f; max_lines::Integer = 0)
    label = WidgetLabel(""; max_lines)
    set_cell_computation!(getfield(label, :content), () -> f()[1])
    set_cell_computation!(getfield(label, :text_style), () -> f()[2])
    set_cell_computation!(getfield(label, :visible), () -> !isempty(f()[1]))
    max_lines > 0 && set_cell_computation!(getfield(label, :tooltip),
                                           () -> (text = f()[1]; isempty(text) ? nothing : text))
    label
end

# The word of the state of a group, and its role: running or stopping while it
# goes (`:accent`), not started (no role), cancelled after a stop (`:warning`),
# else its worst code in the role of the code. It reads the counts, which change
# only when a task starts or ends.
function _get_group_state_role(doc::TaskGroupDocument, group)
    status = getfield(doc, :status)[]
    counts = get_task_group_document_counts(doc)
    status === :running && return ("running", :accent)
    status === :stopping && return ("stopping", :accent)
    counts.finished == 0 && return ("not started", nothing)
    group.stopping && return ("cancelled", :warning)
    (counts.result, get_result_role(group.codes, counts.result))
end

# The word of the state of a group, and its color.
function _get_group_state(p, doc::TaskGroupDocument, group)
    (word, role) = _get_group_state_role(doc, group)
    (word, role === :accent ? p.running_color : role === nothing ? p.muted_color : _get_role_color(p, role))
end

# What a task document says in the column `state`: its result code once it has
# one, else the state it is in.
function _get_task_state(p, codes, document::TaskDocument)
    word = _get_task_state_word(document)
    result = get_task_document_result(document)
    result === nothing || return (word, _get_role_color(p, get_result_role(codes, word)))
    (word, get_task_document_status(document) in (:running, :cancelling) ? p.running_color : p.muted_color)
end

# The time a task took, or is taking: the summary cell of its group is read so a
# task that runs counts on with each drain.
function _format_task_elapsed_time(doc::Union{TaskGroupDocument,Nothing}, document::TaskDocument)
    doc === nothing || get_task_group_document_summary(doc)
    started = _get_current_field(document, :start_time)
    started === nothing && return ""
    _format_duration(something(_get_current_field(document, :end_time), time()) - started; precision = 1)
end

# ── The header of a task ─────────────────────────────────────────────────────

# The badge of the state of a task: its result code in the role of the code once
# it has a result, else the word of its state, in the accent role while it runs
# and stops, with no role otherwise. It follows the task without a new print.
function _make_task_state_badge(document::TaskDocument)
    badge = WidgetBadge("")
    set_cell_computation!(getfield(badge, :content), () -> _get_task_state_word(document))
    set_cell_computation!(getfield(badge, :role), () -> begin
        result = get_task_document_result(document)
        result === nothing &&
            return get_task_document_status(document) in (:running, :cancelling) ? :accent : nothing
        get_result_role(get_result_codes(result), result.result)
    end)
    badge
end

# The muted text beside the name of a task: the name of its kind, whether its
# result is the expected one (as `format_task_result` writes it), and the reason
# of its result, joined by ` · `. It takes no line while it is empty, and it is
# one line, cut with "…", so a long reason does not push the buttons down.
function _make_task_header_note(p, document::TaskDocument)
    task = getfield(document, :task)[]
    _make_live_label(() -> begin
        parts = String[]
        kind = get_task_kind_name(task)
        isempty(kind) || push!(parts, kind)
        result = get_task_document_result(document)
        if result !== nothing
            if !is_expected(result)
                push!(parts, "unexpected")
            elseif get_result_role(get_result_codes(result), result.result) !== :success
                push!(parts, "expected")
            end
            _has_text(result.reason) && push!(parts, result.reason)
        end
        (join(parts, " · "), p.muted_color)
    end; max_lines = 1)
end

# The error message of a task that ended with `ERROR`, in the error colour; no
# line while the task has none, or when its result says nothing about the error.
# With `max_lines` above 0 it shows at most that many lines, cut with "…".
_make_task_error_line(p, document::TaskDocument; max_lines::Integer = 0) = _make_live_label(() -> begin
    result = get_task_document_result(document)
    message = (result !== nothing && result.result == "ERROR") ? find_error_message(result) : nothing
    (something(message, ""), p.error_color)
end; max_lines)

# The facts of the process of a task: its process and the time it took or takes,
# each when it has a value. The elapsed time counts on with each drain of the
# group `doc`. A group with no fact is not visible.
function _make_task_process_group(doc::Union{TaskGroupDocument,Nothing}, document::TaskDocument)
    group = WidgetFactGroup(Any[])
    facts = group.facts
    set_cell_computation!(getfield(facts, :elements), () -> begin
        shown = Cell[]
        process = _get_current_field(document, :process_id)
        process === nothing || push!(shown, Cell(WidgetFact("process", string(process))))
        elapsed = _format_task_elapsed_time(doc, document)
        isempty(elapsed) || push!(shown, Cell(WidgetFact("elapsed", elapsed)))
        shown
    end)
    set_cell_computation!(getfield(group, :visible), () -> !isempty(getfield(facts, :elements)[]))
    group
end

# The column `progress`: a ring while the task runs, filled to the fraction that
# it reports, or turning when it reports none. Its tooltip says where the task
# is, such as the event and the time of a simulation.
function _make_task_progress_ring(document::TaskDocument)
    ring = WidgetProgressRing(() -> _get_current_field(document, :progress))
    set_cell_computation!(getfield(ring, :visible),
                          () -> get_task_document_status(document) in (:running, :cancelling))
    set_cell_computation!(getfield(ring, :tooltip), () -> _get_current_field(document, :position))
    ring
end

# ── The summary card ─────────────────────────────────────────────────────────

# A group of facts whose rows follow `f`, a function of `label => value` pairs
# where a value of `nothing` leaves its fact out. A group with no fact is not
# visible.
function _make_computed_fact_group(f)
    group = WidgetFactGroup(Any[])
    facts = group.facts
    set_cell_computation!(getfield(facts, :elements), () -> Cell[
        Cell(WidgetFact(label, value)) for (label, value) in f() if value !== nothing])
    set_cell_computation!(getfield(group, :visible), () -> !isempty(getfield(facts, :elements)[]))
    group
end

# The time facts of a group in two groups side by side, which follow the summary
# with each drain: what is done and how long, then the slowest task and the rate.
function _make_group_time_facts(p, doc::TaskGroupDocument)
    get_summary() = get_task_group_document_summary(doc)
    done = _make_computed_fact_group(() -> begin
        s = get_summary()
        Pair{String,Any}["finished" => string(s.finished, " of ", s.total),
                         "elapsed" => s.elapsed === nothing ? nothing :
                                      _format_duration(s.elapsed; precision = 0),
                         "left" => s.remaining === nothing ? nothing :
                                   "about " * _format_duration(s.remaining; precision = 0)]
    end)
    pace = _make_computed_fact_group(() -> begin
        s = get_summary()
        Pair{String,Any}["slowest" => s.slowest === nothing ? nothing :
                                      s.slowest[1] * ", " * _format_duration(s.slowest[2]; precision = 1),
                         "rate" => s.rate === nothing ? nothing : _format_task_rate(s.rate)]
    end)
    HorizontalLayout(Any[done, pace]; vertical_align = :top, gap = p.section_gap)
end

# The tasks finished in a minute, or in an hour when fewer than one a minute
# finish: a whole number from 10 up, else one digit after the point.
function _format_task_rate(per_minute::Real)
    format(rate) = rate >= 10 ? string(round(Int, rate)) : string(round(rate; digits = 1))
    per_minute >= 1 ? string(format(per_minute), " a minute") : string(format(per_minute * 60), " an hour")
end

# The most reasons that the card lists; the rest are counted in a line.
const _SUMMARY_REASON_ROWS = 5

# The most names of tasks that a row of a reason lists; the rest are counted.
const _SUMMARY_REASON_NAMES = 3

# A label of one line, cut with "…" in a bounded width, whose tooltip holds the whole text.
_make_cut_label(text::AbstractString) = WidgetLabel(text; max_lines = 1, tooltip = text)

# The names of the tasks that gave a reason: the first ones, and a count of the rest.
_format_reason_names(names) = length(names) <= _SUMMARY_REASON_NAMES ? join(names, ", ") :
    string(join(first(names, _SUMMARY_REASON_NAMES), ", "), " and ", length(names) - _SUMMARY_REASON_NAMES, " more")

# The table of the reasons of the unexpected results of a group: a row for each
# reason, with its count and the tasks that gave it, and a muted line that counts
# the reasons beyond the first rows. Neither is visible while no result is
# unexpected.
function _make_group_reason_table(p, doc::TaskGroupDocument)
    reasons() = get_task_group_document_counts(doc).reasons
    rows = CellVector(Computation(() -> Any[
        CellVector(Cell[Cell(WidgetLabel(string(count))), Cell(_make_cut_label(reason)),
                        Cell(_make_cut_label(_format_reason_names(names)))])
        for (reason, count, names) in first(reasons(), _SUMMARY_REASON_ROWS)]))
    headers = CellVector(Cell[Cell(WidgetLabel(name)) for name in ("count", "reason", "tasks")])
    table = WidgetTable(headers, rows)
    # The count is as narrow as its numbers; the reasons and the tasks share the
    # rest, in the bounded width of a wrapped column, where each is one line cut
    # with "…", so a row of the card is one line high.
    columns = Any[WidgetTableColumn(; align = :right),
                  WidgetTableColumn(; policy = Relative(2.0), cell_policy = :wrap),
                  WidgetTableColumn(; policy = Relative(3.0), cell_policy = :wrap)]
    set_cell_computation!(getfield(table, :columns), () -> columns)
    set_cell_computation!(getfield(table, :visible), () -> !isempty(reasons()))
    more = _make_live_label(() -> begin
        left = length(reasons()) - _SUMMARY_REASON_ROWS
        (left > 0 ? string("+", left, " more ", left == 1 ? "reason" : "reasons") : "", p.muted_color)
    end)
    (table, more)
end

# The card of a group and the line of its buttons. The title of the card holds
# the name with the identifier and the state, and a badge for each count; the card
# holds the words that chose the tasks and the jobs, the preparation, the
# progress, the time facts, and the reasons of the unexpected results. The card
# folds, and it is made one time for each print of the group, so it keeps its
# fold while the person selects rows. The line of buttons stands outside
# the card, so it stays when the card is folded. An inner group shows no actions
# of its own: its row in the outer group stops it and runs it again.
function _build_summary_card(p, doc::TaskGroupDocument, ctx; actions::Bool = true)
    group = get_task_group(doc)
    get_summary() = get_task_group_document_summary(doc)
    title = WidgetLabel(uppercasefirst(group.name))
    identifier = WidgetBadge(getfield(doc, :identifier)[]; variant = :outline)
    state = WidgetBadge("")
    set_cell_computation!(getfield(state, :content), () -> _get_group_state_role(doc, group)[1])
    set_cell_computation!(getfield(state, :role), () -> _get_group_state_role(doc, group)[2])

    # One badge for each code that has a result, and the tasks that run and wait.
    badges = HorizontalLayout(Any[]; vertical_align = :center, gap = p.label_gap)
    set_cell_computation!(getfield(badges.children, :elements), () -> begin
        counts = get_task_group_document_counts(doc)
        parts = Any[]
        for (code, expected, unexpected) in counts.counts
            role = get_result_role(group.codes, code)
            expected > 0 && push!(parts, WidgetBadge(string(expected, " ", code); role))
            unexpected > 0 && push!(parts, WidgetBadge(string(unexpected, " ", code, " unexpected"); role))
        end
        counts.running > 0 && push!(parts, WidgetBadge(string(counts.running, " running"); role = :accent))
        counts.pending > 0 && push!(parts, WidgetBadge(string(counts.pending, " waiting")))
        Cell[Cell(x) for x in parts]
    end)
    heading = HorizontalLayout(Any[title, identifier, state, badges]; vertical_align = :center, gap = p.label_gap)

    selection = _make_live_label(() -> begin
        parts = String[]
        description = getfield(doc, :description)[]
        isempty(description) || push!(parts, description)
        push!(parts, string(group.jobs, " at a time"))
        (join(parts, " · "), p.muted_color)
    end)

    is_going() = getfield(doc, :status)[] in (:running, :stopping)
    run_all = _make_action_button(p, "Run all", editor -> evaluate_operation(editor, StartTaskGroupOperation(doc));
                                  enabled = () -> !is_going(), tooltip = "Start every task of the group.")
    stop = _make_action_button(p, "Stop", editor -> evaluate_operation(editor, StopTaskGroupOperation(doc));
                               enabled = is_going, tooltip = "Stop the tasks that run and start no more.")
    again = _make_action_button(p, "Run unexpected again",
                   editor -> evaluate_operation(editor, RerunTaskGroupOperation(doc, :unexpected));
                   enabled = () -> !is_going() && !get_summary().is_expected,
                   tooltip = _make_rerun_note(doc))
    rows = WidgetToggleGroup(Any["all", "running", "unexpected"];
                             values = Any["all", "running", "unexpected"],
                             target = getfield(doc, :row_filter)[], field = "value")
    buttons = HorizontalLayout(actions ? Any[run_all, stop, again, rows] : Any[rows];
                               vertical_align = :center, gap = p.button_gap)
    progress = make_task_progress_bar(() -> get_summary().progress)
    preparation = _build_preparation_line(p, doc)
    (table, more) = _make_group_reason_table(p, doc)
    lines = Any[selection]
    preparation === nothing || push!(lines, preparation)
    append!(lines, Any[progress, _make_group_time_facts(p, doc), table, more])
    card = WidgetCard(; title = heading, content = VerticalLayout(lines; gap = p.section_gap, child_width = Fill),
                      collapsible = true)
    (card, buttons)
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
    HorizontalLayout(Any[state, show]; vertical_align = :center, gap = p.label_gap)
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
function _build_preparation_detail(p, doc::TaskGroupDocument, ctx)
    preparation = get_task_group_preparation(doc)
    preparation === nothing && return Any[_make_label("This group has no preparation.", p.muted_color)]
    preparation isa TaskGroupDocument && return first(_build_group_parts(p, preparation, ctx; actions = false))
    Any[_make_live_label(() -> _get_preparation_label(p, doc)),
        _build_task_kind_part(p, preparation),
        _build_earlier_executions_card(p, () -> preparation),
        _build_stream_part(p, () -> preparation, :output),
        _build_stream_part(p, () -> preparation, :error_output)]
end

# A button that runs `action` while `enabled()` holds. A refused action is a
# warning, not a fault of the window.
# An action that takes one argument gets the editor that evaluates the press, as
# the callback of an `InvokeActionOperation` does.
function _make_action_button(p, text, action; enabled, tooltip = nothing)
    button = WidgetButton(text; size = p.button_size, tooltip, action = editor ->
        _run_guarded(text, applicable(action, editor) ? () -> action(editor) : action))
    set_cell_computation!(getfield(button, :enabled), enabled)
    button
end

# What "Run unexpected again" says when the pointer rests: how many tasks it runs
# again, the ones that finished with a result that was not expected.
_make_rerun_note(doc::TaskGroupDocument) = () ->
    TooltipNote(; title = "Run unexpected again",
                text = "Run again the tasks that finished with a result that was not expected.",
                facts = ["Tasks" => string(sum(counts -> counts[3], get_task_group_document_counts(doc).counts; init = 0))])

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

# The cells of the table of tasks: the colours of the pane, which the cells of the
# state read as the pane does.
Base.@kwdef struct TaskCells
    success_color::Any
    info_color::Any
    warning_color::Any
    error_color::Any
    running_color::Any
    muted_color::Any
    picture_height::Int = get_widget_style(nothing, :table_picture_height)
end

# The group document of a task and its place, or `nothing` for a task of no group.
_find_task_group_document(document::TaskDocument) =
    (place = find_task_document_group(document)) === nothing ? nothing : first(place)

_get_task_codes(document::TaskDocument) =
    (group = _find_task_group_document(document)) === nothing ?
        get_result_codes(getfield(document, :task)[]) : get_task_group(group).codes

# A table of the tasks of a group draws the state in the colour of its code, the
# progress as a ring, the time that counts on while the task runs, the load and the
# memory in their units, and the columns of the kind of the task as the value that
# the kind gives, which follows the result, also for a column that has the name of
# a field of the document. Any other item has the cells of the table.
make_roster_cell(::TaskCells, item, key, value) = nothing

function make_roster_cell(cells::TaskCells, item::TaskDocument, key, value)
    key == "state" && return _make_live_label(() -> _get_task_state(cells, _get_task_codes(item), item))
    key == "progress" && return _make_task_progress_ring(item)
    key == "elapsed" && return WidgetLabel(() -> _format_task_elapsed_time(_find_task_group_document(item), item))
    key == "processor" && return WidgetLabel(() -> (load = value[];
                                                   load === nothing ? "" : string(round(Int, load), "%")))
    key == "memory" && return WidgetLabel(() -> (bytes = value[];
                                                bytes === nothing ? "" : format_memory_size(bytes)))
    task = getfield(item, :task)[]
    (!_has_item_facet(TaskDocument, key) && any(column -> first(column) == key, get_task_columns(task))) ?
        _make_task_column_cell(cells, task, item, key) :
        make_roster_cell(nothing, item, key, value)
end

# The cell of a column of a kind: the value that the kind gives for the result,
# which follows the result, as a cell of any table shows it: a picture, at most
# `picture_height` high, or the text of the value.
_make_task_column_cell(cells::TaskCells, task, item::TaskDocument, key) =
    make_roster_value_cell(Cell(@computation get_task_column_value(task, get_task_document_result(item), key)),
                           cells.picture_height)

# The path from a group to its table.
const _TABLE_STEP = FieldReferenceStep("table")

# The steps from the root of the pane to the table: the split is the third child
# of the root, in a constraint, and the table is the first pane of the split, in a
# constraint (`_build_group_parts`).
const _TABLE_PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(2, 3), FieldReferenceStep("child"),
                            FieldReferenceStep("elements"), RangeReferenceStep(0, 1), FieldReferenceStep("child"))

# ── The detail of one task ───────────────────────────────────────────────────

# ── The documents of a task, edited where they show ─────────────────────────
#
# The detail of a task draws the document of its kind and the tree of the
# processes of the task while it runs, each in a place of its own: a constraint that
# gives the document its share of the height, in the split and alone. A path from
# the group reaches each document, `tasks[i].kind_document + rest` and
# `tasks[i].process_tree + rest`, so the pane maps that path to the place and
# back, with the same `rest`. Every other path takes the defaults of `Projection`.

# The steps from the root of the pane to the detail: the place below the summary card is
# the third child of the root, in a constraint. It holds the split, whose second
# pane is the detail, in a constraint too, or the detail alone
# (`_build_group_parts`).
const _PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(2, 3), FieldReferenceStep("child"))
const _DETAIL_STEPS = (_PLACE_STEPS..., FieldReferenceStep("elements"), RangeReferenceStep(1, 2),
                       FieldReferenceStep("child"))
_get_detail_steps(doc::TaskGroupDocument) = getfield(doc, :is_detail_alone)[] ? _PLACE_STEPS : _DETAIL_STEPS

# The steps from the detail to the column of its parts: the detail is a scroll
# area, and its content a column.
const _COLUMN_STEPS = (FieldReferenceStep("content"), FieldReferenceStep("children"))

# The steps from the column of the detail to the place of each document of a
# task: the slot in the column, then the place in the slot. The slot of the
# document of the kind is the fourth part of the column, below the header line,
# the error line and the buttons, and it holds the one place. The tree of the
# processes is the first part of the fifth, the slot of the parts below the
# document (`_build_task_parts`).
const _DOCUMENT_SLOT_STEPS = (kind_document = (RangeReferenceStep(3, 4), FieldReferenceStep("children"),
                                               RangeReferenceStep(0, 1)),
                              process_tree = (RangeReferenceStep(4, 5), FieldReferenceStep("children"),
                                              RangeReferenceStep(0, 1)))

# The document of the kind that the place below the card of the group holds while
# the detail is alone: the one of the selected task, or `nothing` for a task that
# has none and for a row that is an inner group, which shows its detail.
function _find_alone_document(doc::TaskGroupDocument)
    index = getfield(doc, :selected)[]
    documents = getfield(doc, :tasks)[]
    (1 <= index <= length(documents)) || return nothing
    find_task_group_document(doc, index) === nothing || return nothing
    getfield(documents[index], :kind_document)[]
end

# The place of each document that the detail of the pane shows: the steps from the
# group to the document, and the steps from the root of the pane to its place. A
# task of an inner group shows in the detail of that group, which no path from
# this group reaches.
function _find_document_places(doc::TaskGroupDocument)
    places = Tuple{Tuple,Tuple}[]
    index = getfield(doc, :selected)[]
    documents = getfield(doc, :tasks)[]
    (1 <= index <= length(documents)) || return places
    find_task_group_document(doc, index) === nothing || return places
    # The document of the kind alone in the place below the card of the group: the
    # tree of the processes has no place, and the detail is not in the output.
    if getfield(doc, :is_detail_alone)[] && _find_alone_document(doc) !== nothing
        push!(places, ((FieldReferenceStep("tasks"), RangeReferenceStep(index - 1, index),
                        FieldReferenceStep("kind_document")), (_PLACE_STEPS..., FieldReferenceStep("content"))))
        return places
    end
    for field in keys(_DOCUMENT_SLOT_STEPS)
        getfield(documents[index], field)[] === nothing && continue
        push!(places, ((FieldReferenceStep("tasks"), RangeReferenceStep(index - 1, index),
                        FieldReferenceStep(String(field))),
                       (_get_detail_steps(doc)..., _COLUMN_STEPS..., _DOCUMENT_SLOT_STEPS[field]...,
                        FieldReferenceStep("child"))))
    end
    places
end

# What a step names, so a step that a reader answers and a step written here
# compare by what they select.
_get_step_key(step::FieldReferenceStep) = (:field, step.name)
_get_step_key(step::RangeReferenceStep) = (:range, step.start, step.stop)
_get_step_key(step) = (:other, step)

_make_steps_reference(steps) =
    foldr((step, rest) -> ConcreteReference(step, rest), steps; init = EmptyReference())

# The part of `path` below `head`, or `nothing` when `path` does not begin with it.
function _find_path_below(path, head)
    path isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    length(steps) >= length(head) || return nothing
    all(_get_step_key(steps[k]) == _get_step_key(head[k]) for k in eachindex(head)) || return nothing
    _make_steps_reference(steps[(length(head) + 1):end])
end

# A key goes to the child that the selection of each container names, so each
# widget and layout from the root of the pane to the place of a document holds its
# part of the path. The walk stops at a document of a domain, which holds its own.
# It leaves out the table, whose rows take no key and which selects the row of the
# task of the detail itself. A constraint is on the way: the split and
# the detail each stand in one.
_is_followed_by_selection(node) =
    (node isa WidgetDocument || node isa LayoutDocument || node isa LayoutConstraint) &&
    !(node isa WidgetTable)

# A part that the detail builds, at `steps` from the detail, holds its part of
# the paths of the detail, so a key reaches the document after the person picks
# another task: the walk of the pane reaches only the parts that were there when
# the pane was drawn. `is_followed` leaves out a node and what is below it.
function _follow_detail_part!(detail, part, steps::Tuple; is_followed = _is_followed_by_selection)
    below(field) = () -> _find_path_below(getfield(detail, field)[], steps)
    follow_output_selection!(part, below(:selection); forward_mouse_target = below(:mouse_target), is_followed)
end

# The task document of the selected row, or `nothing` while no row is selected,
# while the preparation is selected, and for a row that is an inner group.
function _find_selected_task_document(doc::TaskGroupDocument)
    index = getfield(doc, :selected)[]
    documents = getfield(doc, :tasks)[]
    (1 <= index <= length(documents)) || return nothing
    find_task_group_document(doc, index) === nothing || return nothing
    documents[index]
end

# What the detail shows: `:preparation`, `:hint` while no row is selected,
# `:group` for a row that is an inner group, and `:task` for a task. A symbol is
# plain data, so a cell of it stops when another row of a task is selected.
function _get_detail_mode(doc::TaskGroupDocument)
    index = getfield(doc, :selected)[]
    index == -1 && return :preparation
    (1 <= index <= length(getfield(doc, :tasks)[])) || return :hint
    find_task_group_document(doc, index) === nothing ? :task : :group
end

# A part of the detail that holds what `parts()` answers, each `nothing` left
# out. It is the only reader of what it holds, so the column around it stays as
# it is when the part shows something else, and the other parts of the column
# do not print again.
function _make_detail_slot(parts; gap::Integer = 0)
    slot = VerticalLayout(Any[]; gap, child_width = Fill)
    set_cell_computation!(getfield(slot.children, :elements),
                          () -> Cell[Cell(part) for part in parts() if part !== nothing])
    slot
end

# The pages of the documents of the kinds of the tasks of a group, which the
# detail and the place below the card show: for each type of document, one
# document to show, and its place in the detail. A document whose fields are
# cells shows as its following copy (`make_following_document`), one object for
# the type, so a print of the page is made one time for each type, and the cards
# of the page keep their fold while the person selects rows. Another document
# shows as it is. `key` is the number of the type of the document of the
# selected task, `0` when it has none: plain data, so a cell of it stops when
# another task with a document of the same type is selected.
struct _KindPages
    types::Vector{Any}
    shown::Vector{Any}          # for each type: a function that answers the document to show
    places::Vector{Any}         # for each type: the `LayoutConstraint` of the document in the detail
    key::Cell
end

# The document of the kind of the selected task, or `nothing`.
_find_selected_kind_document(doc::TaskGroupDocument) =
    (document = _find_selected_task_document(doc); document === nothing ? nothing : getfield(document, :kind_document)[])

function _make_kind_pages(doc::TaskGroupDocument, detail)
    pages = _KindPages(Any[], Any[], Any[], Cell(0))
    set_cell_computation!(pages.key, () -> begin
        shown = _find_selected_kind_document(doc)
        shown === nothing ? 0 : _find_kind_page!(pages, doc, detail, shown)
    end)
    pages
end

# The number of the type of `shown` among the pages, with a new page for a new
# type. The page of a type shows the document of the selected task while it is
# of that type, and the last such document while it is not.
function _find_kind_page!(pages::_KindPages, doc::TaskGroupDocument, detail, shown)
    type = typeof(shown)
    found = findfirst(t -> t === type, pages.types)
    found === nothing || return found
    last_shown = Ref{Any}(shown)
    source = () -> begin
        current = _find_selected_kind_document(doc)
        current isa type && (last_shown[] = current)
        last_shown[]
    end
    if is_followable_document(shown)
        copy = make_following_document(source)
        place = LayoutConstraint(copy; width = Fill)
        push!(pages.shown, () -> copy)
    else
        place = LayoutConstraint(shown; width = Fill)
        set_cell_computation!(getfield(place, :child), source)
        push!(pages.shown, source)
    end
    _follow_detail_part!(detail, place, (_COLUMN_STEPS..., _DOCUMENT_SLOT_STEPS.kind_document...))
    push!(pages.types, type)
    push!(pages.places, place)
    length(pages.types)
end

# The document that the place below the card shows while the detail is alone,
# or `nothing` when the selected task has no document of its kind.
_find_alone_page(pages::_KindPages) = (key = pages.key[]; key == 0 ? nothing : pages.shown[key]())

# The parts of the detail of a task, made one time: the header line, the error
# line and the buttons; the slot of the document of the kind; and one slot of the
# parts below it, which holds only the parts that show: the tree of the processes
# while the task runs, the cards `Process` and `Earlier executions` while they have
# something to show, and the two streams. Each part reads the selected task in a
# computation of its own, so a card stays the same card while the person selects
# rows, and keeps its fold. A part that does not show takes no place and no gap.
function _build_task_parts(p, doc::TaskGroupDocument, detail, pages::_KindPages)
    group = get_task_group(doc)
    selected = () -> _find_selected_task_document(doc)
    header = _make_detail_slot(() -> begin
        document = selected()
        document === nothing && return Any[]
        task = getfield(document, :task)[]
        Any[HorizontalLayout(Any[_make_task_state_badge(document), WidgetLabel(format_task_parameters(task)),
                                 _make_task_header_note(p, document)];
                             vertical_align = :center, gap = p.label_gap)]
    end)
    error_line = _make_detail_slot(() -> begin
        document = selected()
        document === nothing ? Any[] : Any[_make_task_error_line(p, document; max_lines = 2)]
    end)
    buttons = _make_detail_slot(() -> begin
        document = selected()
        document === nothing && return Any[]
        index = getfield(doc, :selected)[]
        task = getfield(document, :task)[]
        stop = WidgetButton("Stop"; size = p.button_size,
                            action = editor -> _run_guarded("stop",
                                () -> evaluate_operation(editor, StopTaskOperation(doc, index))))
        set_cell_computation!(getfield(stop, :enabled), () -> get_task_document_status(document) === :running)
        again = WidgetButton("Run again"; size = p.button_size,
                             action = editor -> _run_guarded("run again",
                                () -> evaluate_operation(editor, RerunTaskGroupOperation(doc, [index]))))
        set_cell_computation!(getfield(again, :enabled),
                              () -> !(getfield(doc, :status)[] in (:running, :stopping)))
        actions = Any[_make_task_action_button(p, label, action, task)
                      for (label, action) in get_task_actions(task)]
        page = WidgetButton("Open the task page"; size = p.button_size,
                            gestures = make_open_page_gestures(doc, _make_task_reference(index); domain = "task"))
        Any[HorizontalLayout(Any[page, stop, again, actions...]; vertical_align = :center, gap = p.button_gap)]
    end)
    kind = _make_detail_slot(() -> (key = pages.key[]; key == 0 ? Any[] : Any[pages.places[key]]))
    tree = Cell(@computation (document = selected();
                              document === nothing ? nothing : getfield(document, :process_tree)[]))
    (process, shows_process) = _make_process_card(p, doc, selected)
    (executions, shows_executions) = _make_earlier_executions_card(p, selected)
    (output, error_output) = (_build_stream_part(p, selected, :output), _build_stream_part(p, selected, :error_output))
    below = _make_detail_slot(; gap = p.section_gap) do
        shown = tree[]
        place = shown === nothing ? nothing :
            _follow_detail_part!(detail, LayoutConstraint(shown; width = Fill),
                                 (_COLUMN_STEPS..., _DOCUMENT_SLOT_STEPS.process_tree...))
        Any[place, shows_process[] ? process : nothing, shows_executions[] ? executions : nothing, output, error_output]
    end
    Cell[Cell(part) for part in Any[header, error_line, buttons, kind, below]]
end

# The detail of the selected task: one column of parts in a scroll area that
# grows down, each part the height of its content (`_build_task_parts`). The
# column keeps its parts while the person selects tasks: only a change between a
# task, an inner group, the preparation and no row makes it again. The maps of
# the pane find each document by its place. It answers the detail and the pages of
# the kinds of the tasks (`_KindPages`).
function _build_detail(p, doc::TaskGroupDocument, ctx)
    column = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    detail = WidgetScrollPane(column; grows = (width = false, height = true))
    pages = _make_kind_pages(doc, detail)
    task_parts = _build_task_parts(p, doc, detail, pages)
    mode = Cell(@computation _get_detail_mode(doc))
    set_cell_computation!(getfield(column.children, :elements), () -> begin
        shown = mode[]
        shown === :task && return task_parts
        shown === :preparation && return Cell[Cell(x) for x in _build_preparation_detail(p, doc, ctx)]
        shown === :hint && return Cell[Cell(_make_label("Press a row to see its task here.", p.muted_color))]
        # A task that is a group shows its own pane: its card, its buttons, its
        # table and the detail of the task picked in it.
        inner = find_task_group_document(doc, getfield(doc, :selected)[])
        Cell[Cell(x) for x in first(_build_group_parts(p, inner, ctx; actions = false))]
    end)
    (detail, pages)
end

# The card `Process` with the facts of the process of the task that `selected()`
# answers, and a cell of whether it shows: while the task has such a fact. The
# card is made one time, and only its content follows the task. A card reads
# whether it is visible when it prints, so a slot holds the card while it shows,
# and the parts around the slot do not print again.
function _make_process_card(p, doc, selected)
    facts = Cell(@computation (document = selected();
                               document === nothing ? nothing : _make_task_process_group(doc, document)))
    card = WidgetCard(; title = "Process", content = _make_detail_slot(() -> Any[facts[]]), collapsible = true)
    (card, Cell(@computation (shown = facts[]; shown !== nothing && getfield(shown, :visible)[])))
end

# The card `Process` of the task that `selected()` answers in a slot of its own,
# which holds it while it shows (`_make_process_card`).
function _build_process_card(p, doc, selected)
    (card, shows) = _make_process_card(p, doc, selected)
    _make_detail_slot(() -> Any[shows[] ? card : nothing])
end

# The card `Earlier executions` of the task that `selected()` answers, and a cell
# of whether it shows: while the task has such executions. The card is made one
# time.
function _make_earlier_executions_card(p, selected)
    content = _make_detail_slot(() -> (document = selected();
                                       document === nothing ? Any[] : Any[_build_earlier_executions(p, document)]))
    card = WidgetCard(; title = "Earlier executions", content, collapsible = true)
    (card, Cell(@computation (document = selected();
                              document !== nothing && !isempty(get_earlier_task_executions(document)))))
end

# The card `Earlier executions` in a slot of its own, which holds it while it shows.
function _build_earlier_executions_card(p, selected)
    (card, shows) = _make_earlier_executions_card(p, selected)
    _make_detail_slot(() -> Any[shows[] ? card : nothing])
end

# The executions before the current one, the oldest first, each with its verdict
# in the color of its role among the codes of its result. A task that ran once or
# never shows none.
function _build_earlier_executions(p, document::TaskDocument)
    lines = VerticalLayout(Any[]; gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () -> begin
        parts = Any[]
        for (number, execution) in enumerate(get_earlier_task_executions(document))
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

# How many lines the stream `field` of the current execution of a task holds: none
# before the first start and while the task waits to start again.
_get_stream_line_count(document::TaskDocument, field::Symbol) =
    (current = get_current_task_execution(document); current === nothing ? 0 : getproperty(current, field).count)

# Whether the stream `field` of the current execution of a task holds a line.
_has_stream_lines(document::TaskDocument, field::Symbol) = _get_stream_line_count(document, field) > 0

# The words over a stream: its name and the count of its lines, or its name and
# `empty`.
_format_stream_count(name::AbstractString, count::Integer) =
    count == 0 ? name * " · empty" : string(name, " · ", count, count == 1 ? " line" : " lines")

# The part of one stream of the task that `selected()` answers: a card with its
# name and the count of its lines over the box of its lines, or the muted word
# `stdout · empty` and no card. The card and the word are made one time. The part
# reads whether the stream has a line in a cell of its own, which stays as it is
# while lines come, so a line changes only the count and the box.
function _build_stream_part(p, selected, field::Symbol)
    name = field === :output ? "stdout" : "stderr"
    count = () -> (document = selected(); document === nothing ? 0 : _get_stream_line_count(document, field))
    has_lines = Cell(@computation count() > 0)
    title = _make_label(() -> _format_stream_count(name, count()), p.muted_color)
    lines = () -> (document = selected(); document === nothing ? String[] : collect_task_document_lines(document, field))
    card = WidgetCard(; title, content = _build_output_pane(p, lines), collapsible = true)
    empty = _make_label(name * " · empty", p.muted_color)
    _make_detail_slot(() -> Any[has_lines[] ? card : empty])
end

# The lines of a stream in a box of at most `stream_box_height`, which scrolls
# and follows the end, so it shows the last lines.
function _build_output_pane(p, lines)
    area = WidgetTextarea(""; rows = 0)
    set_cell_computation!(getfield(area, :content), () -> begin
        value = lines()
        value isa AbstractVector ? join(value, "\n") : string(something(value, ""))
    end)
    VerticalLayout(Any[LayoutConstraint(WidgetScrollPane(area; follow_end = true); max_height = p.stream_box_height)];
                   child_width = Fill)
end

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

It is the title that the decoration of a group gives
(`get_document_decoration`), as `open_pane!` gives each tab of a group, also when
its caller gives the name as a plain string, and as a row of a tree shows it.

Use it to give the tab of a group a title that shows how far the group is.

# Example

    group_1 = find_task_group("T3")
    title_1 = make_task_group_tab_title(group_1)

See also `describe_task_group` and `open_pane!`.

For the assistant.
"""
function make_task_group_tab_title end

make_task_group_tab_title(doc::TaskGroupDocument; name = getfield(doc, :title)[]) =
    make_pane_tab_title(doc, String(name))
make_task_group_tab_title(document::ReferencedDocument; keywords...) =
    make_task_group_tab_title(get_document(document); keywords...)

# A group is a work item: its icon is its state, its tint the role of its state,
# its counts how far it is and each code that came back unexpected, and its
# tooltip the summary card in short. It reads the counts and the status, which
# change when a task starts or ends.
function get_document_decoration(doc::TaskGroupDocument)
    group = get_task_group(doc)
    state = (status = getfield(doc, :status)[], counts = get_task_group_document_counts(doc),
             cancelled = group.stopping)
    kind = _get_tab_state(state)
    role = _get_tab_role(group, state)
    condition = kind === :running ? DocumentCondition(:running) :
                kind === :pending ? DocumentCondition(:pending) :
                kind === :cancelled ? DocumentCondition(:stopped) :
                kind === :expected ? DocumentCondition(:done) :
                DocumentCondition(role === :error ? :failed : :unexpected; role)
    counts = DocumentCount[DocumentCount(badge.content; role = badge.role) for badge in _make_tab_badges(group, state)]
    DocumentDecoration(; icon = _get_tab_icon(state), conditions = [condition], counts,
                       tooltip = _make_tab_note(doc, group), work_item = true)
end

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

# The summary card in short, as a note: the title of the group and what it does,
# then how far it is, what it found and the time, as facts.
function _make_tab_note(doc::TaskGroupDocument, group)
    s = get_task_group_document_summary(doc)
    running = getfield(doc, :status)[] in (:running, :stopping)
    heading = running ? format_task_group_description(group) : format_task_group_close_description(group)
    facts = Pair{String,String}["Identifier" => getfield(doc, :identifier)[],
                                "Finished" => string(s.finished, " of ", s.total)]
    s.running > 0 && push!(facts, "Running" => string(s.running))
    push!(facts, "At a time" => string(group.jobs))
    isempty(s.summary) || push!(facts, "Result" => s.summary)
    group.start_time === nothing || push!(facts, "Started" => Libc.strftime("%H:%M:%S", group.start_time))
    s.elapsed === nothing || push!(facts, "Elapsed" => _format_duration(s.elapsed))
    s.remaining === nothing || push!(facts, "Left" => "about " * _format_duration(s.remaining))
    TooltipNote(; title = getfield(doc, :title)[], text = heading, facts)
end

# ── The node of a tree ───────────────────────────────────────────────────────

# A group in a tree has its tasks under its node. Its text is its identifier and
# its title; how far it is shows as the counts of its decoration.
get_tree_children_steps(::TaskGroupDocument) = ((FieldReferenceStep("tasks"),),)

format_tree_node_label(doc::TaskGroupDocument) = getfield(doc, :identifier)[] * " " * getfield(doc, :title)[]

# The list of the groups has a node for each group, and a closed group keeps its
# place there and says that it closed.
get_tree_children_steps(::TaskGroupList) = ((FieldReferenceStep("groups"),),)
format_tree_node_label(group::ClosedTaskGroup) = getfield(group, :identifier)[] * " " * getfield(group, :title)[]
get_document_decoration(group::ClosedTaskGroup) =
    DocumentDecoration(; icon = :minus, conditions = [DocumentCondition(:stopped)], detail = "closed", work_item = true,
                       tooltip = () -> TooltipNote(; title = getfield(group, :title)[],
                                                   text = isempty(getfield(group, :summary)[]) ? nothing :
                                                          getfield(group, :summary)[]))

# ── The pane ─────────────────────────────────────────────────────────────────

# The card of a group, and below it its table above the detail of the task that
# a person picked, in a split a person can drag. The table takes its rows up to
# half of the split, and the detail takes the rest, so a group of a few tasks
# gives the detail the height that its rows leave. While `is_detail_alone` is
# set, the place of the split holds the document of the kind of the selected task
# and nothing else, or the detail alone when the task has no such document.
function _build_group_parts(p, doc::TaskGroupDocument, ctx; actions::Bool = true)
    (card, buttons) = _build_summary_card(p, doc, ctx; actions)
    table = LayoutConstraint(getfield(doc, :table)[]; width = Fill, height = Content, weight_height = 1.0)
    alone = WidgetScrollPane(nothing; grows = (width = false, height = true))
    (detail, pages) = _build_detail(p, doc, ctx)
    split = WidgetSplitPane(:vertical, Any[table, LayoutConstraint(detail; width = Fill, height = Fill)])
    set_cell_computation!(getfield(alone, :content), () -> _find_alone_page(pages))
    # Plain data, so the place stays as it is while the person selects tasks.
    shows_alone = Cell(@computation getfield(doc, :is_detail_alone)[] && pages.key[] != 0)
    shows_detail_alone = Cell(@computation getfield(doc, :is_detail_alone)[] && pages.key[] == 0)
    place = LayoutConstraint(split; width = Fill, height = Fill)
    set_cell_computation!(getfield(place, :child),
                          () -> shows_alone[] ? alone : shows_detail_alone[] ? detail : split)
    (Any[card, buttons, place], detail, alone)
end

function print_document(p::TaskGroupDocumentToWidgetPane, recursion, doc::TaskGroupDocument, ctx)
    (parts, detail, alone) = _build_group_parts(p, doc, ctx)
    root = VerticalLayout(parts; horizontal_align = :left, gap = p.section_gap)
    iomap = ChildrenIoMap(p, doc, root, Cell(Any[]))
    # The part under the pointer, so a button lights and takes a press.
    forward_mouse_target = () -> map_mouse_target_forward(doc, path -> map_reference_forward(p, iomap, path))
    follow_output_mouse_target!(root, forward_mouse_target;
        is_followed = node -> !(node isa ArrangementDocument))
    # The caret, so a key reaches the document of a result in the detail.
    forward_selection = () -> begin
        path = getfield(doc, :selection)[]
        path === nothing ? nothing : map_reference_forward(p, iomap, path)
    end
    follow_output_selection!(root, forward_selection; is_followed = _is_followed_by_selection)
    # The detail stands in the split and, while it is alone, in the place below the
    # summary card, so it takes the part of the path below the place where it stands now.
    below_detail(forward) = () -> begin
        path = forward()
        (path === nothing || (getfield(doc, :is_detail_alone)[] && _find_alone_document(doc) !== nothing)) &&
            return nothing
        _find_path_below(path, _get_detail_steps(doc))
    end
    follow_output_mouse_target!(detail, below_detail(forward_mouse_target);
        is_followed = node -> !(node isa ArrangementDocument))
    follow_output_selection!(detail, below_detail(forward_selection); is_followed = _is_followed_by_selection)
    # The scroll area of the document alone stands in the place below the buttons.
    below_alone(forward) = () -> begin
        path = forward()
        (path === nothing || !getfield(doc, :is_detail_alone)[] || _find_alone_document(doc) === nothing) &&
            return nothing
        _find_path_below(path, _PLACE_STEPS)
    end
    follow_output_mouse_target!(alone, below_alone(forward_mouse_target);
        is_followed = node -> !(node isa ArrangementDocument))
    follow_output_selection!(alone, below_alone(forward_selection); is_followed = _is_followed_by_selection)
    iomap
end

# ── A press on a row ─────────────────────────────────────────────────────────
#
# The table is the arrangement of a roster in the field `table` of the group, which
# the recursion prints, so its answers are paths of the group: a press on a row is
# the selection of the row, `table.document.rows[k].item`, and a scroll far from
# the head writes the item of the head to `anchor` of the roster. The pane turns
# the first into what the press does to the task of the row, and the second into a
# write of the anchor of the group. The `k` of a row is its place in the roster,
# which lists the tasks that the choice shows, so a task is found by its identity
# in the `tasks` of its group.

# The group of the pane and the groups that its detail shows in turn, as
# `(group, steps)`: `steps` lead from `doc` to the group, as fields; `output` leads
# from the root of the pane to the parts of that group.
function _collect_detail_groups(doc::TaskGroupDocument, steps = (), output = (), found = Any[])
    push!(found, (doc, steps, output))
    inner = _find_detail_group(doc)
    inner === nothing && return found
    index = getfield(doc, :selected)[]
    below = index == -1 ? (FieldReferenceStep("preparation"),) :
            (FieldReferenceStep("tasks"), RangeReferenceStep(index - 1, index), FieldReferenceStep("inner_group"))
    _collect_detail_groups(inner, (steps..., below...), (output..., _get_detail_steps(doc)...), found)
end

# The group whose parts the detail of `doc` shows: the selected task when it is a
# group, or the preparation when it is a group and the detail shows it.
function _find_detail_group(doc::TaskGroupDocument)
    index = getfield(doc, :selected)[]
    inner = index == -1 ? get_task_group_preparation(doc) : find_task_group_document(doc, index)
    inner isa TaskGroupDocument ? inner : nothing
end

# The place of each table that the pane draws: the steps from the group of the
# pane to the table, and from the root of the pane to it.
_collect_table_places(doc::TaskGroupDocument) =
    Tuple{Tuple,Tuple}[((steps..., _TABLE_STEP), (output..., _TABLE_PLACE_STEPS...))
                       for (group, steps, output) in _collect_detail_groups(doc)
                       if !getfield(group, :is_detail_alone)[]]

# `table.<rest>` of each table ↔ the table in the output.
function map_reference_forward(p::TaskGroupDocumentToWidgetPane, iomap, reference)
    if reference isa ConcreteReference
        for (document_steps, place_steps) in _find_document_places(iomap.input)
            inside = _find_path_below(reference, document_steps)
            inside === nothing || return annotate_reference_types(iomap.output,
                concat_references(_make_steps_reference(place_steps), inside))
        end
        for (document_steps, output_steps) in _collect_table_places(iomap.input)
            inside = _find_path_below(reference, document_steps)
            inside === nothing && continue
            table = try_evaluate_reference(iomap.input, _make_steps_reference(document_steps), nothing)
            table === nothing && continue
            return concat_references(annotate_reference_types(iomap.output, _make_steps_reference(output_steps)),
                                     annotate_reference_types(table, inside))
        end
    end
    invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function map_reference_backward(p::TaskGroupDocumentToWidgetPane, iomap, reference)
    if reference isa ConcreteReference
        for (document_steps, place_steps) in _find_document_places(iomap.input)
            below = _find_path_below(reference, place_steps)
            below === nothing || return annotate_reference_types(iomap.input,
                concat_references(_make_steps_reference(document_steps), below))
        end
        for (document_steps, output_steps) in _collect_table_places(iomap.input)
            below = _find_path_below(reference, output_steps)
            below === nothing || return annotate_reference_types(iomap.input,
                concat_references(_make_steps_reference(document_steps), below))
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# The path from a group to the document of its task `index`.
_make_task_reference(index::Int) = Reference(FieldReferenceStep("tasks"), RangeReferenceStep(index - 1, index))

# What a press on the row of task `index` of `group` does: a press shows the task
# in the detail, a double press opens its page, in the navigator around the pane
# or else in a new tab, and Ctrl+press opens it in a new tab. Which task the
# detail shows is view state, so the undo does not record it.
function _make_row_press_operation(group::TaskGroupDocument, index::Int, gesture)
    reference = _make_task_reference(index)
    if gesture isa MouseClick
        gesture.modifiers.ctrl && return OpenPageOperation(group, reference, :new_tab)
        gesture.count == 2 && return OpenPageOperation(group, reference, :here)
    end
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(group, "selected", index))
end

# ── The detail alone ─────────────────────────────────────────────────────────
#
# The keys of the group answer when no part nearer the caret answers them: Return
# shows the detail of the selected task alone, and Escape shows the table again.
# While the detail is alone, Up and Down select the previous or the next task in
# the order of the table, and the detail follows. Every other key, such as Left and
# Right, goes to the part that reads it.

# What a key does to the state of the view: it is not recorded for undo.
_make_view_write_operation(doc::TaskGroupDocument, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(doc, field, value))

# The task documents that the table shows, in its order: its filter, its sort and
# its first items count.
function _collect_shown_task_documents(doc::TaskGroupDocument)
    found = find_arranged_collection(doc, extend_reference(EmptyReference(), _TABLE_STEP,
                                                           FieldReferenceStep("document"), FieldReferenceStep("rows")))
    found === nothing && return TaskDocument[]
    TaskDocument[peek(getfield(row, :item)) for row in collect_shown_items(found.entry, found.items)
                 if row isa RosterRow]
end

# The place in the group of the task that is `step` rows after the selected task in
# the table, or before it with a negative `step`, or `nothing` where the table has
# no such row. With no selected task in the table, a step forward gives the first
# row and a step back the last.
function _find_neighbour_task(doc::TaskGroupDocument, step::Int)
    shown = _collect_shown_task_documents(doc)
    isempty(shown) && return nothing
    documents = _task_documents(doc)
    selected = getfield(doc, :selected)[]
    here = (1 <= selected <= length(documents)) ? findfirst(task -> task === documents[selected], shown) : nothing
    target = here === nothing ? (step > 0 ? 1 : length(shown)) : here + step
    (1 <= target <= length(shown)) || return nothing
    findfirst(task -> task === shown[target], documents)
end

# The caret in the document of the kind of task `index`, so a key reaches that
# document first; the caret on the group when the task has none.
function _make_kind_caret_operation(doc::TaskGroupDocument, index::Int)
    documents = getfield(doc, :tasks)[]
    (1 <= index <= length(documents) && getfield(documents[index], :kind_document)[] !== nothing) ||
        return ReplaceSelectionOperation(EmptyReference())
    ReplaceSelectionOperation(extend_reference(EmptyReference(), FieldReferenceStep("tasks"),
                                               RangeReferenceStep(index - 1, index),
                                               FieldReferenceStep("kind_document")))
end

function _make_detail_move_operation(doc::TaskGroupDocument, step::Int)
    getfield(doc, :is_detail_alone)[] || return nothing
    index = _find_neighbour_task(doc, step)
    index === nothing && return DoNothingOperation()
    CompoundOperation(Any[_make_view_write_operation(doc, "selected", index), _make_kind_caret_operation(doc, index)])
end

# Return writes the caret into the document of the kind of the selected task, so Left and Right
# reach the document of the kind, and Escape puts it back on the group.
function _make_detail_alone_operation(doc::TaskGroupDocument, is_alone::Bool)
    getfield(doc, :is_detail_alone)[] == is_alone && return nothing
    index = getfield(doc, :selected)[]
    is_alone && !(1 <= index <= length(getfield(doc, :tasks)[])) && return nothing
    write = _make_view_write_operation(doc, "is_detail_alone", is_alone)
    caret = is_alone ? _make_kind_caret_operation(doc, index) : ReplaceSelectionOperation(EmptyReference())
    CompoundOperation(Any[write, caret])
end

@gestures TaskGroupDocument begin
    KeyPress('\n') => "Show the detail alone" => _make_detail_alone_operation(doc, true)
    KeyDown(:escape) => "Show the table and the detail" => _make_detail_alone_operation(doc, false)
    KeyDown(:up) => "Select the previous task of the table" => _make_detail_move_operation(doc, -1)
    KeyDown(:down) => "Select the next task of the table" => _make_detail_move_operation(doc, 1)
end

# The group of a table that `path`, a path of the pane's group, goes into at a row
# of its roster, with the place of the task of that row in the group, the steps of
# the group, and the steps of `path` after the item of the row; `nothing` for any
# other path.
function _find_row_task(doc::TaskGroupDocument, path)
    path isa ConcreteReference || return nothing
    for (group, steps, _) in _collect_detail_groups(doc)
        rest = _find_path_below(path, (steps..., _TABLE_STEP, FieldReferenceStep("document"),
                                       FieldReferenceStep("rows")))
        rest isa ConcreteReference || continue
        below = get_reference_steps(rest)
        (below[1] isa RangeReferenceStep && is_element_reference_step(below[1])) || continue
        (length(below) == 1 || below[2] == FieldReferenceStep("item")) || continue
        rows = getfield(group, :table)[].document.rows
        k = below[1].start + 1
        (1 <= k <= length(rows)) || continue
        index = findfirst(task -> task === peek(getfield(rows[k], :item)), _task_documents(group))
        index === nothing && continue
        return (group, index, steps, below[min(3, end + 1):end])
    end
    nothing
end

# The task that a place `shown[j]` of the group names, as in `_find_row_task`.
function _find_shown_task(doc::TaskGroupDocument, path)
    path isa ConcreteReference || return nothing
    rest = _find_path_below(path, (FieldReferenceStep("shown"),))
    rest isa ConcreteReference || return nothing
    below = get_reference_steps(rest)
    (below[1] isa RangeReferenceStep && is_element_reference_step(below[1])) || return nothing
    shown = getfield(doc, :shown)[]
    j = below[1].start + 1
    (1 <= j <= length(shown)) || return nothing
    index = findfirst(task -> task === shown[j], _task_documents(doc))
    index === nothing ? nothing : (doc, index, (), below[2:end])
end

# `operation`, with each open of a page that names a task through a row of a
# table, or through a place `shown[j]`, naming it by its place `tasks[i]` in its
# group, which does not change with the choice of rows.
function _retarget_task_open(doc::TaskGroupDocument, operation)
    if operation isa CompoundOperation
        parts = Any[_retarget_task_open(doc, part) for part in operation.operations]
        return all(k -> parts[k] === operation.operations[k], eachindex(parts)) ? operation : CompoundOperation(parts)
    end
    if operation isa WrappingOperation
        inner = get_wrapped_operation(operation)
        retargeted = _retarget_task_open(doc, inner)
        return retargeted === inner ? operation : rewrap_operation(operation, retargeted)
    end
    (operation isa OpenPageOperation && operation.document === nothing) || return operation
    found = something(_find_row_task(doc, operation.reference), _find_shown_task(doc, operation.reference), Some(nothing))
    found === nothing && return operation
    (_, index, steps, rest) = found
    retarget_operation(operation, extend_reference(EmptyReference(), steps..., FieldReferenceStep("tasks"),
                                                   RangeReferenceStep(index - 1, index), rest...))
end

# The pane's answer to a selection of a row of a table of a group, and to a write
# of the head of the list of one: the press of the row with the caret on the group,
# and the write of the anchor of the group. A double click on a row is a selection and an open that the
# roster adds, which the press already is.
function _convert_table_answer(doc::TaskGroupDocument, operation, gesture)
    if operation isa ReplaceSelectionOperation
        found = _find_row_task(doc, operation.path)
        found === nothing && return operation
        press = _make_row_press_operation(found[1], found[2], gesture)
        # A plain press puts the caret on the group, so the keys of the group reach it.
        return press isa ReplaceViewStateOperation ?
               CompoundOperation(Any[press, ReplaceSelectionOperation(extend_reference(EmptyReference(), found[3]...))]) :
               press
    end
    if operation isa CompoundOperation
        parts = Any[_convert_table_answer(doc, part, gesture) for part in operation.operations]
        pressed = any(k -> parts[k] !== operation.operations[k] && operation.operations[k] isa ReplaceSelectionOperation,
                      eachindex(parts))
        kept = pressed ? Any[part for part in parts if !(part isa OpenPageOperation && part.document === nothing)] : parts
        all(k -> parts[k] === operation.operations[k], eachindex(parts)) && length(kept) == length(parts) &&
            return operation
        return length(kept) == 1 ? only(kept) : CompoundOperation(kept)
    end
    operation isa ReplaceViewStateOperation || return operation
    write = get_wrapped_operation(operation)
    (write isa ReplaceReferencedValueOperation &&
     get_reference_steps(strip_reference_types(write.reference)) == [FieldReferenceStep("anchor")]) || return operation
    for (group, _, _) in _collect_detail_groups(doc)
        getfield(group, :table)[].document === write.document || continue
        index = findfirst(task -> task === write.value, _task_documents(group))
        return index === nothing ? DoNothingOperation() :
               ReplaceViewStateOperation(ReplaceReferencedValueOperation(group, "anchor", index))
    end
    operation
end

# The generic bridge maps the answer of the output back. The removal of the last
# entry of the arrangement of the table leaves the arrangement with no entry, so the
# next filter or sort has an arrangement to go to, and the open of a row names its
# task by its place in the group.
function read_intent(p::TaskGroupDocumentToWidgetPane, recursion, change::Intent, iomap)
    answer = invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    doc = iomap.input
    operation = keep_held_arrangement(answer.operation, getfield(doc, :table)[], _TABLE_STEP)
    operation = retarget_held_row_open(operation, doc, _TABLE_STEP)
    operation = _retarget_task_open(doc, operation)
    operation = _convert_table_answer(doc, operation, change.gesture)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end

# ── The Tasks pane ───────────────────────────────────────────────────────────

"""
    TaskGroupListToWidgetPane(; theme styles…)

Draw a [`TaskGroupList`](@ref) as the Tasks pane: one row for each open work item
of the session, newest first. A group shows its identifier, its title, its kind,
the word of its state, its counts, how far it is and the time, and the buttons
that stop it, run its unexpected tasks again, and close its row. Another work
item, such as a search, shows its identifier, its title, its kind, and the word
of its state and its line as its decoration says them, and the buttons that stop
it and close its row. The title is a link to the page of the item. A closed row
leaves a [`ClosedTaskGroup`](@ref) in the list, which the pane does not show.
"""
@projection UntrackedCell struct TaskGroupListToWidgetPane <: Projection
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

const _LIST_COLUMNS = ("item", "title", "kind", "state", "counts", "progress", "elapsed", "")

"""
    make_task_group_list_tab_title(list) -> PaneTabTitle

The title of the Tasks tab: its name, and a badge with the count of the work items
that run while any does. It is the title that the decoration of the list gives
(`get_document_decoration`), so a navigator whose page is the list gives its tab
the same icon and badge, and a row of a tree shows the same.
"""
make_task_group_list_tab_title(list::TaskGroupList; name = "Tasks") = make_pane_tab_title(list, String(name))

# The list says how many of its work items run, and runs while one does.
function get_document_decoration(list::TaskGroupList)
    running = count(_is_work_item_running, collect_work_items(list))
    tooltip = () -> TooltipNote(; title = "Tasks", text = "Every task group of this session, and its tasks.",
                                facts = ["Groups" => string(length(collect(list.groups))),
                                         "Running" => string(running)])
    running == 0 && return DocumentDecoration(; icon = :list, tooltip)
    DocumentDecoration(; icon = :list, conditions = [DocumentCondition(:running)],
                       counts = [DocumentCount(string(running, " running"); role = :accent)], tooltip)
end

function _build_list_row(p, list::TaskGroupList, doc::TaskGroupDocument, index::Int)
    group = get_task_group(doc)
    # The title is a link to the page of the group.
    title = WidgetLink(() -> getfield(doc, :title)[],
                       DocumentLocator(list, Reference(FieldReferenceStep("groups"), RangeReferenceStep(index - 1, index))))
    is_going() = getfield(doc, :status)[] in (:running, :stopping)
    stop_button = _make_action_button(p, "Stop", editor -> evaluate_operation(editor, StopTaskGroupOperation(doc));
                                      enabled = is_going,
                                      tooltip = "Stop the tasks that run and start no more.")
    again_button = _make_action_button(p, "Run unexpected again",
                                       editor -> evaluate_operation(editor, RerunTaskGroupOperation(doc, :unexpected));
                                       enabled = () -> !is_going() && !get_task_group_document_counts(doc).is_expected,
                                       tooltip = _make_rerun_note(doc))
    close_button = _make_action_button(p, "Close", editor -> evaluate_operation(editor, CloseTaskGroupOperation(list, doc));
                                       enabled = () -> !is_going(),
                                       tooltip = "Close the group: its tasks and their output are gone, and its summary stays.")
    Any[WidgetLabel(getfield(doc, :identifier)[]),
        title,
        WidgetLabel(group.name),
        _make_live_label(() -> _get_group_state(p, doc, group)),
        WidgetLabel(() -> _format_group_counts(get_task_group_document_counts(doc))),
        WidgetLabel(() -> string(round(Int, 100 * get_task_group_document_summary(doc).progress), "%")),
        WidgetLabel(() -> (e = get_task_group_document_summary(doc).elapsed; e === nothing ? "" : _format_duration(e))),
        HorizontalLayout(Any[stop_button, again_button, close_button]; vertical_align = :center,
                         gap = p.button_gap)]
end

# The row of another work item: its identifier, its title as a link to its page,
# its kind, the word of its state and its line, as its decoration says them, and
# the buttons that stop it and close its row.
function _build_list_row(p, list::TaskGroupList, item, index::Int)
    title = WidgetLink(() -> get_document_title(item),
                       DocumentLocator(list, Reference(FieldReferenceStep("groups"), RangeReferenceStep(index - 1, index))))
    is_going() = _is_work_item_running(item)
    stop_button = _make_action_button(p, "Stop", () -> stop_work_item!(item); enabled = is_going,
                                      tooltip = "Stop this work before it ends.")
    close_button = _make_action_button(p, "Close", editor -> evaluate_operation(editor, CloseTaskGroupOperation(list, item));
                                       enabled = () -> !is_going(),
                                       tooltip = "Close the row: a summary of the work takes its place.")
    Any[WidgetLabel(get_work_item_identifier(item)),
        title,
        WidgetLabel(describe_work_item_kind(item, 1)),
        _make_live_label(() -> _get_work_item_state(p, item)),
        WidgetLabel(() -> get_document_decoration(item).detail),
        WidgetLabel(""),
        WidgetLabel(""),
        HorizontalLayout(Any[stop_button, close_button]; vertical_align = :center, gap = p.button_gap)]
end

# The word of the state of a work item and its color: the first condition of its
# decoration.
function _get_work_item_state(p, item)
    conditions = get_document_decoration(item).conditions
    isempty(conditions) && return ("", p.muted_color)
    condition = first(conditions)
    look = get_condition_look(Val(condition.name))
    role = something(condition.role, Some(look.role))
    (look.words, role === :accent ? p.running_color : role === nothing ? p.muted_color : _get_role_color(p, role))
end

# The open work items of the list, newest first, each with its place in the list,
# which the path of its link names.
_collect_shown_task_groups(list::TaskGroupList) =
    [(index, item) for (index, item) in Iterators.reverse(collect(enumerate(list.groups)))
     if !(item isa ClosedTaskGroup)]

# The count of each kind of the open work items, in the order of the first start
# of each kind, and how many run: "2 groups · 1 search · 1 running". With no item,
# "0 groups · 0 running".
function _format_list_heading(items)
    kinds = Pair{Any,Vector{Any}}[]
    for item in items
        kind = Base.typename(typeof(item)).wrapper
        place = findfirst(pair -> first(pair) === kind, kinds)
        place === nothing ? push!(kinds, kind => Any[item]) : push!(last(kinds[place]), item)
    end
    parts = String[string(length(found), " ", describe_work_item_kind(first(found), length(found)))
                   for (_, found) in kinds]
    isempty(parts) && push!(parts, "0 groups")
    join(vcat(parts, string(count(_is_work_item_running, items), " running")), " · ")
end

function print_document(p::TaskGroupListToWidgetPane, recursion, list::TaskGroupList, ctx)
    heading = WidgetLabel(() -> _format_list_heading(collect_work_items(list)))
    body = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        shown = _collect_shown_task_groups(list)
        isempty(shown) && return Cell[Cell(_make_label(
            "No group of tasks is open in this session.", p.muted_color))]
        rows = Any[_build_list_row(p, list, item, index) for (index, item) in shown]
        Cell[Cell(WidgetTable(collect(Any, _LIST_COLUMNS), rows))]
    end)
    root = VerticalLayout(Any[heading, LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.section_gap)
    iomap = ChildrenIoMap(p, list, root, Cell(Any[]))
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(list, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# ── A closed group ───────────────────────────────────────────────────────────

"""
    ClosedTaskGroupToWidgetPane(; section_gap, label_gap, muted_color)

Draw a [`ClosedTaskGroup`](@ref) as its page: the title and the identifier of the
group, that it closed, and the line that sums it up. A path that named the group
names this page, and never another group.
"""
@projection UntrackedCell struct ClosedTaskGroupToWidgetPane <: Projection
    section_gap::Int = get_widget_style(nothing, :section_gap)
    label_gap::Int = get_widget_style(nothing, :label_gap)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
end

function print_document(p::ClosedTaskGroupToWidgetPane, recursion, group::ClosedTaskGroup, ctx)
    heading = HorizontalLayout(Any[WidgetLabel(getfield(group, :title)[]),
                                   WidgetBadge(getfield(group, :identifier)[]; variant = :outline)];
                               vertical_align = :center, gap = p.label_gap)
    lines = VerticalLayout(Any[_make_label("This group is closed. Its tasks and their output are gone.", p.muted_color),
                               WidgetLabel(getfield(group, :summary)[])]; gap = p.section_gap, child_width = Fill)
    root = VerticalLayout(Any[WidgetCard(; title = heading, content = lines)]; horizontal_align = :left,
                          gap = p.section_gap)
    ChildrenIoMap(p, group, root, Cell(Any[]))
end

# ── Natural-projection registration ─────────────────────────────────────────

"""
    build_task_graphics_entry(; measure = nothing, appearance = Appearance())
        -> Vector{Pair{Type,Any}}

The rows of the natural renderer that draw a group of tasks as its pane, the
groups of the session as the Tasks pane, a closed group, and a task, an execution
and a stream as their pages. Each pane draws with the scaled
`TaskTheme` of `appearance`, and its widgets draw with a widget renderer of
their own, which also takes a click back to the button under it. `measure` is
what the registry gives every row; a row made by hand measures with the font
files.
"""
function build_task_graphics_entry(; measure = nothing, appearance::Appearance = Appearance())
    measured = measure === nothing ? FontFileMeasure() : measure
    theme = get_scaled_theme!(appearance, TaskTheme)
    get_style(name) = get_task_style(theme, name)
    widget_theme = get_scaled_theme!(appearance, WidgetTheme)
    styles = (button_size = get_style(:button_size), label_gap = get_widget_style(widget_theme, :label_gap),
              button_gap = get_widget_style(widget_theme, :button_gap),
              section_gap = get_widget_style(widget_theme, :section_gap), success_color = get_style(:success_color),
              info_color = get_style(:info_color), warning_color = get_style(:warning_color),
              error_color = get_style(:error_color), running_color = get_style(:running_color),
              muted_color = get_style(:muted_color))
    # A document that a kind gives for a result draws as it draws in any
    # document: by the method of `make_graphics_projection` for its type.
    documents = Pair{Type,Any}[type => Base.invokelatest(make_graphics_projection, type;
                                                         measure = measured, appearance = appearance)
                               for type in collect_graphics_projection_types()]
    make_widget_rows() = WidgetToGraphics(; measure = measured, theme = widget_theme,
                                          graphics_theme = get_scaled_theme!(appearance, GraphicsTheme),
                                          text_theme = get_scaled_theme!(appearance, TextTheme)).dispatch
    cells = TaskCells(; (name => unwrap_cell(getproperty(styles, name)) for name in
                         (:success_color, :info_color, :warning_color, :error_color, :running_color, :muted_color))...,
                         picture_height = unwrap_cell(get_widget_style(widget_theme, :table_picture_height)))
    # The table of a group is the arrangement of a roster, which draws its rows with
    # the cells of the pane before the natural rows.
    tables = Pair{Type,Any}[ArrangementDocument => ArrangingProjection(),
                            ArrangementChips => ArrangementChipsToGraphics(; gap = get_widget_style(widget_theme, :item_gap)),
                            CellVector{ArrangementGroupRow} => ChainingProjection(ArrangementGroupRowsToWidget(),
                                                                                  GridLayoutToGraphicsCanvas()),
                            Roster => RosterToGraphics(),
                            CellVector{RosterRow} => ChainingProjection(RosterRowsToWidget(widget_theme, cells),
                                                                        GridLayoutToGraphicsCanvas())]
    # A primitive in a document of a result, such as a cell of its table, draws as
    # it draws in a tab.
    primitives = Pair{Type,Any}[make_natural_primitive_row(; measure = measured, appearance)]
    widgets() = RecursiveProjection(make_arranged_dispatch(
        TypeDispatchingProjection(vcat(tables, make_widget_rows(), documents, primitives));
        bar = ArrangementBarProjection))
    # The page of a stream draws the fields of its bar and its lines too. A row of lines is a line of the font of the widgets with the padding of
    # a cell and a rule, as the table draws it.
    table = last(only(row for row in make_widget_rows() if first(row) === WidgetTable))
    row_step = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measured, "M", widget_theme.font).height) +
                                               2 * Int(table.cell_padding.top[]) + 1)
    lines = TaskStreamLinesToWidget(; row_step, label_gap = styles.label_gap, warning_color = styles.warning_color,
                                    error_color = styles.error_color, info_color = styles.info_color,
                                    running_color = styles.running_color, muted_color = styles.muted_color)
    stream_widgets() = RecursiveProjection(TypeDispatchingProjection(vcat(
        make_object_field_widget_dispatch(make_widget_rows()), documents, Pair{Type,Any}[
            TaskStreamLines => ChainingProjection(lines, VerticalLayoutToGraphicsCanvas())])))
    Pair{Type,Any}[
        TaskGroupDocument => ChainingProjection(TaskGroupDocumentToWidgetPane(; styles...,
                                                    stream_box_height = get_style(:stream_box_height)),
                                                widgets()),
        TaskGroupList => ChainingProjection(TaskGroupListToWidgetPane(; styles...), widgets()),
        ClosedTaskGroup => ChainingProjection(ClosedTaskGroupToWidgetPane(; section_gap = styles.section_gap,
                                                  label_gap = styles.label_gap, muted_color = styles.muted_color),
                                              widgets()),
        TaskDocument => ChainingProjection(TaskDocumentToWidgetPane(; styles...), widgets()),
        ACTaskExecution => ChainingProjection(TaskExecutionToWidgetPane(; Base.structdiff(styles, (button_gap = 0,))...), widgets()),
        TaskStream => ChainingProjection(TaskStreamToWidget(; gap = styles.section_gap), stream_widgets())]
end

function __init__()
    register_natural_graphics!(:task, build_task_graphics_entry)
    # The tasks of the groups of the session, as a source of a roster.
    register_roster_source!(:tasks, link -> _SessionTasks();
                            description = "the tasks of the groups of the session, each with its group as within")
end
