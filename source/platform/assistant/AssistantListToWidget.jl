# Fragment of `AssistantModule` — the Assistants pane: a table of the open
# assistants, one row each, which follows each assistant while it works, above
# the detail of the assistant that a person picked.

"""
    AssistantListToWidgetPane(theme)

Draw an [`AssistantList`](@ref) as the Assistants pane: a heading that counts the
conversations and the turns that run, a table with one row for each open
assistant, and below it, in a split that a person can drag, the detail of the
assistant that the person picked with the `›` of its row.

A row has the `›`, a button that shows the tab of the assistant and a button
that shows the work page of its agent ([`show_assistant_work!`](@ref)), then its
title, the state of its work, whose turn it is, what its turn does now, how many
prompts it has, how much of its context it uses, how far the plan of its agent
is, how many subagents and background tasks of its agent run, when it started
and how long it runs.
The title fills the width that the other columns leave and stays on one line,
and a pane narrower than the table scrolls it.
Each value is a label that reads the cells of the assistant, so a row follows
its assistant while a turn streams. The elapsed time of a turn that runs reads
the clock of the editor, so it moves while the turn runs. Between turns no label
reads the clock, so the editor draws no frame for the table.

The detail says the title and the facts of the assistant, holds its description
and its comment in the cards of embedded documents, where a key edits them,
offers the states of its work as a row of toggles, and shows its first and its
last prompt and its session. With no theme it takes the values of the default
theme.
"""
@projection UntrackedCell struct AssistantListToWidgetPane
    stack_gap::Int = get_conversation_style(nothing, :section_gap)
    muted_color::StyleColor = get_conversation_style(nothing, :placeholder_color)
end

AssistantListToWidgetPane(theme::Union{ConversationTheme,ScaledConversationTheme}) =
    AssistantListToWidgetPane(; stack_gap = get_conversation_style(theme, :section_gap),
                                muted_color = get_conversation_style(theme, :placeholder_color))

# The column `tasks` counts the background tasks that run, as the facet
# `background_tasks` does; the short name keeps the column narrow.
const _ASSISTANT_LIST_COLUMNS = ("", "title", "work", "turn", "activity", "prompts", "context",
                                 "plan", "subagents", "tasks", "started", "elapsed")

# The title takes the width that the other columns leave, and never less than its
# widest title, which stays on one line: a column with a weight and no minimum of
# its own, whose cells clip, is at least as wide as its widest cell. Each other
# column is its content and at least its header, so the columns of numbers do not
# narrow the title, and a pane narrower than the table scrolls it.
const _ASSISTANT_TITLE_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

_make_assistant_list_columns() =
    Any[WidgetTableColumn(; policy = name == "title" ? _ASSISTANT_TITLE_POLICY : nothing)
        for name in _ASSISTANT_LIST_COLUMNS]

# The words of a state of the work, and the role of its badge.
_format_work_state(state::Symbol) = replace(String(state), "_" => " ")
_get_work_state_role(state::Symbol) =
    state === :in_progress ? :accent : state === :abandoned ? :warning : nothing

# A duration as the table writes it: `42 s` under a minute, then `12:05` and
# `1:02:05`.
function _format_assistant_duration(seconds::Real)
    total = max(0, floor(Int, seconds))
    total < 60 && return string(total, " s")
    hours, rest = divrem(total, 3600)
    minutes, seconds = divrem(rest, 60)
    hours == 0 ? string(minutes, ":", lpad(seconds, 2, '0')) :
                 string(hours, ":", lpad(minutes, 2, '0'), ":", lpad(seconds, 2, '0'))
end

# A time as the table writes it: the hour and the minute of a time of today, and
# the date before them for an earlier day. Empty for `nothing`.
function _format_assistant_time(time)
    time === nothing && return ""
    clock = Libc.strftime("%H:%M", time)
    Libc.strftime("%Y-%m-%d", time) == Libc.strftime("%Y-%m-%d", Base.time()) ? clock :
        Libc.strftime("%Y-%m-%d ", time) * clock
end

# The elapsed time of a conversation. While a turn runs the label reads the clock
# of the editor, so it computes again on each frame. Between turns it reads no
# clock, so the editor draws no frame for it.
function _format_elapsed_time(a::Assistant, clock)
    is_assistant_turn_running(a) && clock !== nothing && get_reactive_clock_time(clock)
    elapsed = compute_assistant_elapsed_time(a)
    elapsed === nothing ? "" : _format_assistant_duration(elapsed)
end

function _build_assistant_row(list::AssistantList, a::Assistant, clock)
    pick = WidgetButton("›"; action = _ -> select_assistant!(list, a))
    show = WidgetButton("Show"; action = editor -> open_assistant_tab!(editor, list, a))
    show_work = editor -> (show_assistant_work!(a; editor); nothing)
    work_page = WidgetButton("Work"; tooltip = "Show the plans, the subagents and the tasks of the agent.",
                             action = show_work)
    work = WidgetBadge(() -> _format_work_state(a.work_state))
    set_cell_computation!(getfield(work, :role), () -> _get_work_state_role(a.work_state))
    turn = WidgetBadge(() -> compute_assistant_turn_side(a) === :assistant ? "assistant" : "you")
    set_cell_computation!(getfield(turn, :role), () -> compute_assistant_turn_side(a) === :assistant ? :accent : nothing)
    Any[HorizontalLayout(Any[pick, show, work_page]; vertical_align = :center),
        WidgetLabel(() -> compute_assistant_overview_title(a)),
        work,
        turn,
        WidgetLabel(() -> describe_assistant_activity(a)),
        WidgetLabel(() -> string(compute_prompt_count(a))),
        WidgetLabel(() -> format_agent_usage(a.agent_usage)),
        WidgetLabel(() -> compute_item_facet(a, Val(:plan))),
        WidgetLabel(() -> string(compute_item_facet(a, Val(:subagents)))),
        WidgetLabel(() -> string(compute_item_facet(a, Val(:background_tasks)))),
        WidgetLabel(() -> _format_assistant_time(find_assistant_start_time(a))),
        WidgetLabel(() -> _format_elapsed_time(a, clock))]
end

function _build_assistant_table(p, list::AssistantList, clock)
    body = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        assistants = list.assistants
        isempty(assistants) && return Cell[Cell(WidgetLabel("No assistant is open in this window.";
                                                            text_style = p.muted_color))]
        rows = Any[_build_assistant_row(list, a, clock) for a in assistants]
        Cell[Cell(WidgetTable(collect(Any, _ASSISTANT_LIST_COLUMNS), rows;
                              columns = _make_assistant_list_columns()))]
    end)
    body
end

# ── The detail of one assistant ──────────────────────────────────────────────
#
# The detail draws the description and the comment of the assistant that a
# person picked in the cards of embedded documents (`make_embed_card`). A path
# from the list reaches each document through the row of that assistant,
# `assistants[i].description + rest`, so the pane maps that path to its card,
# `content + rest`, and back, as the detail of a task maps the document of a
# result. A pick of another row changes `i`, so a caret in the card of the
# assistant before leaves the detail and does not move into the next one. Every
# other path takes the defaults of `Projection`.

# The steps from the root of the pane to the detail: the split is the second
# child of the root, in a constraint, and the detail is the second pane of the
# split, in a constraint too.
const _ASSISTANT_DETAIL_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2),
                                 FieldReferenceStep("child"), FieldReferenceStep("elements"),
                                 RangeReferenceStep(1, 2), FieldReferenceStep("child"))

# The documents of an assistant that the detail edits, each with the place of its
# card among the parts of the detail, counted from 0: after the title and the
# facts.
const _ASSISTANT_DETAIL_CARDS = ((:description, "Description", 2), (:comment, "Comment", 3))

# The steps from the root of the pane to the card at `place` among the parts of
# the detail, which stands in a constraint.
_get_assistant_card_steps(place::Int) =
    (_ASSISTANT_DETAIL_STEPS..., FieldReferenceStep("children"), RangeReferenceStep(place, place + 1),
     FieldReferenceStep("child"))

# The steps from the list to the document `field` of the assistant of row `index`.
_get_assistant_document_steps(field::Symbol, index::Int) =
    (FieldReferenceStep("assistants"), RangeReferenceStep(index - 1, index), FieldReferenceStep(String(field)))

# The row of the assistant whose detail the pane shows, the picked one while it
# is open, and the assistant; `nothing` when the pane shows none.
function _find_shown_assistant(list::AssistantList)
    a = list.selected
    a === nothing && return nothing
    index = findfirst(open -> open === a, collect(list.assistants))
    index === nothing ? nothing : (index, a)
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

function map_reference_forward(p::AssistantListToWidgetPane, iomap, reference)
    shown = reference isa ConcreteReference ? _find_shown_assistant(iomap.input) : nothing
    if shown !== nothing
        for (field, _, place) in _ASSISTANT_DETAIL_CARDS
            inside = _find_path_below(reference, _get_assistant_document_steps(field, first(shown)))
            inside === nothing && continue
            return annotate_reference_types(iomap.output,
                concat_references(_make_steps_reference(_get_assistant_card_steps(place)),
                                  make_embed_card_path(inside)))
        end
    end
    invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function map_reference_backward(p::AssistantListToWidgetPane, iomap, reference)
    shown = reference isa ConcreteReference ? _find_shown_assistant(iomap.input) : nothing
    if shown !== nothing
        for (field, _, place) in _ASSISTANT_DETAIL_CARDS
            below = _find_path_below(reference, _get_assistant_card_steps(place))
            inside = below === nothing ? nothing : find_embed_card_path_inside(below)
            inside === nothing && continue
            return annotate_reference_types(iomap.input,
                concat_references(_make_steps_reference(_get_assistant_document_steps(field, first(shown))),
                                  inside))
        end
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# A key goes to the child that the selection of each container names, so each
# widget and layout from the root of the pane to a card holds its part of the
# path. The walk stops at a card that holds a document: the card follows the
# paths of its document (`make_embed_card`). It leaves out the table, whose rows
# take no key.
_is_assistant_embed_card(node) =
    node isa WidgetCard && node.content isa Document &&
    !(node.content isa WidgetDocument || node.content isa LayoutDocument)
_is_followed_by_assistant_selection(node) =
    (node isa WidgetDocument || node isa LayoutDocument || node isa LayoutConstraint) &&
    !(node isa WidgetTable) && !_is_assistant_embed_card(node)

# A part that the detail builds holds its part of the paths of the detail, so a
# key reaches a card after the person picks another assistant: the walk of the
# pane reaches only the parts that were there when the pane was drawn.
function _follow_assistant_detail_part!(detail, part, place::Int)
    steps = (FieldReferenceStep("children"), RangeReferenceStep(place, place + 1))
    below(field) = () -> _find_path_below(getfield(detail, field)[], steps)
    follow_output_selection!(part, below(:selection); forward_mouse_target = below(:mouse_target),
                             is_followed = _is_followed_by_assistant_selection)
end

# The states of the work as a row of toggles; a press writes `work_state`.
function _make_work_state_choice(a::Assistant)
    choice = WidgetToggleGroup(Any[_format_work_state(state) for state in ASSISTANT_WORK_STATES];
                               values = Any[ASSISTANT_WORK_STATES...], target = a, field = "work_state")
    set_cell_computation!(getfield(choice, :selected),
                          () -> something(findfirst(==(a.work_state), ASSISTANT_WORK_STATES), 1))
    choice
end

# The facts of an assistant in a line: its backend and model, and its times.
# While a turn runs the line reads the clock of the editor, as the elapsed time
# of a row does.
function _format_assistant_facts(a::Assistant, clock)
    is_assistant_turn_running(a) && clock !== nothing && get_reactive_clock_time(clock)
    facts = String[isempty(a.model) ? String(a.backend) : string(a.backend, " ", a.model)]
    start = find_assistant_start_time(a)
    start === nothing || push!(facts, "started " * _format_assistant_time(start))
    elapsed = compute_assistant_elapsed_time(a)
    elapsed === nothing || push!(facts, "elapsed " * _format_assistant_duration(elapsed))
    busy = compute_assistant_busy_time(a)
    busy > 0 && push!(facts, "busy " * _format_assistant_duration(busy))
    last_activity = find_assistant_last_activity_time(a)
    last_activity === nothing || push!(facts, "last activity " * _format_assistant_time(last_activity))
    join(facts, " · ")
end

_format_prompt_line(label, prompt) = prompt === nothing ? label * ": none" : label * ": " * prompt

function _build_assistant_detail(p, list::AssistantList, clock)
    detail = VerticalLayout(Any[]; gap = p.stack_gap, child_width = Fill)
    set_cell_computation!(getfield(detail.children, :elements), () -> begin
        shown = _find_shown_assistant(list)
        shown === nothing && return Cell[Cell(WidgetLabel("Press › on a row to see its conversation here.";
                                                      text_style = p.muted_color))]
        a = last(shown)
        parts = Any[WidgetLabel(() -> compute_assistant_overview_title(a)),
                    WidgetLabel(() -> _format_assistant_facts(a, clock))]
        for (field, title, place) in _ASSISTANT_DETAIL_CARDS
            length(parts) == place || error("the card of the ", field, " is not where the maps of the pane find it")
            card = make_embed_card(getproperty(a, field), title)
            push!(parts, _follow_assistant_detail_part!(detail, LayoutConstraint(card; width = Fill), place))
        end
        push!(parts, _make_work_state_choice(a))
        push!(parts, WidgetLabel(() -> _format_prompt_line("First prompt", find_first_prompt(a))))
        push!(parts, WidgetLabel(() -> _format_prompt_line("Last prompt", find_last_prompt(a))))
        push!(parts, WidgetLabel(() -> isempty(a.agent_session_id) ? "" :
                                       "Session " * a.agent_session_id * " in " * a.agent_session_directory))
        Cell[Cell(x) for x in parts]
    end)
    detail
end

# ── The pane ─────────────────────────────────────────────────────────────────

function print_document(p::AssistantListToWidgetPane, recursion, list::AssistantList, ctx)
    clock = ctx === nothing ? nothing : ctx.clock
    heading = WidgetLabel(() -> begin
        assistants = list.assistants
        running = count(is_assistant_turn_running, assistants)
        string(length(assistants), length(assistants) == 1 ? " conversation" : " conversations",
               " · ", running, " running")
    end)
    table = LayoutConstraint(WidgetScrollPane(_build_assistant_table(p, list, clock)); width = Fill, height = Fill)
    detail = LayoutConstraint(_build_assistant_detail(p, list, clock); width = Fill, height = Fill)
    split = LayoutConstraint(WidgetSplitPane(:vertical, Any[table, detail]); width = Fill, height = Fill)
    root = VerticalLayout(Any[heading, split]; horizontal_align = :left, gap = p.stack_gap)
    iomap = ChildrenIoMap(p, list, root, Cell(Any[]))
    # The part under the pointer, so a button lights and takes a press.
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(list, path -> map_reference_forward(p, iomap, path));
        is_followed = !_is_assistant_embed_card)
    # The caret, so a key reaches the description or the comment in the detail.
    follow_output_selection!(root, () -> begin
        path = getfield(list, :selection)[]
        path === nothing ? nothing : map_reference_forward(p, iomap, path)
    end; is_followed = _is_followed_by_assistant_selection)
    iomap
end
