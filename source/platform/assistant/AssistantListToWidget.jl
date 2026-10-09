# Fragment of `AssistantModule` — the Assistants pane: a table of the open
# assistants, one row each, which follows each assistant while it works.

"""
    AssistantListToWidgetPane(theme)

Draw an [`AssistantList`](@ref) as the Assistants pane: a heading that counts the
conversations and the turns that run, and a table with one row for each open
assistant. A row has a button that shows the tab of the assistant, and its
title, the state of its work, whose turn it is, what its turn does now, how many
prompts it has, how much of its context it uses, when it started and how long it
runs. Each value is a label that reads the cells of the assistant, so a row
follows its assistant while a turn streams. The elapsed time of a turn that runs
reads the clock of the editor, so it moves while the turn runs, and an idle
table asks for no frame. With no theme it takes the values of the default theme.
"""
@projection UntrackedCell struct AssistantListToWidgetPane
    stack_gap::Int = get_conversation_style(nothing, :section_gap)
    muted_color::StyleColor = get_conversation_style(nothing, :placeholder_color)
end

AssistantListToWidgetPane(theme::Union{ConversationTheme,ScaledConversationTheme}) =
    AssistantListToWidgetPane(; stack_gap = get_conversation_style(theme, :section_gap),
                                muted_color = get_conversation_style(theme, :placeholder_color))

const _ASSISTANT_LIST_COLUMNS = ("", "title", "work", "turn", "activity", "prompts", "context",
                                 "started", "elapsed")

# The words of a state of the work, and the role of its badge.
_format_work_state(state::Symbol) = replace(String(state), "_" => " ")
_get_work_state_role(state::Symbol) =
    state === :in_progress ? :accent : state === :abandoned ? :warning : nothing

"""
    format_assistant_duration(seconds) -> String

A duration as the table of the assistants writes it: `42 s` under a minute, then
`12:05` and `1:02:05`.
"""
function format_assistant_duration(seconds::Real)
    total = max(0, floor(Int, seconds))
    total < 60 && return string(total, " s")
    hours, rest = divrem(total, 3600)
    minutes, seconds = divrem(rest, 60)
    hours == 0 ? string(minutes, ":", lpad(seconds, 2, '0')) :
                 string(hours, ":", lpad(minutes, 2, '0'), ":", lpad(seconds, 2, '0'))
end

"""
    format_assistant_start_time(time) -> String

When a conversation started, as the table of the assistants writes it: the hour
and the minute of a time of today, and the date before them for an earlier day.
Empty for `nothing`.
"""
function format_assistant_start_time(time)
    time === nothing && return ""
    clock = Libc.strftime("%H:%M", time)
    Libc.strftime("%Y-%m-%d", time) == Libc.strftime("%Y-%m-%d", Base.time()) ? clock :
        Libc.strftime("%Y-%m-%d ", time) * clock
end

# The elapsed time of a conversation. While a turn runs the label reads the clock
# of the editor, so it computes again on each frame; between turns it reads no
# clock, so it asks for no frame.
function _format_elapsed_time(a::Assistant, clock)
    is_assistant_turn_running(a) && clock !== nothing && get_reactive_clock_time(clock)
    elapsed = compute_assistant_elapsed_time(a)
    elapsed === nothing ? "" : format_assistant_duration(elapsed)
end

function _build_assistant_row(list::AssistantList, a::Assistant, clock)
    show = WidgetButton("Show"; action = editor -> open_assistant_tab(editor, list, a))
    work = WidgetBadge(() -> _format_work_state(a.work_state))
    set_cell_computation!(getfield(work, :role), () -> _get_work_state_role(a.work_state))
    turn = WidgetBadge(() -> compute_assistant_turn_side(a) === :assistant ? "assistant" : "you")
    set_cell_computation!(getfield(turn, :role), () -> compute_assistant_turn_side(a) === :assistant ? :accent : nothing)
    Any[show,
        WidgetLabel(() -> compute_assistant_overview_title(a)),
        work,
        turn,
        WidgetLabel(() -> describe_assistant_activity(a)),
        WidgetLabel(() -> string(compute_prompt_count(a))),
        WidgetLabel(() -> format_agent_usage(a.agent_usage)),
        WidgetLabel(() -> format_assistant_start_time(find_assistant_start_time(a))),
        WidgetLabel(() -> _format_elapsed_time(a, clock))]
end

function print_document(p::AssistantListToWidgetPane, recursion, list::AssistantList, ctx)
    clock = ctx === nothing ? nothing : ctx.clock
    heading = WidgetLabel(() -> begin
        assistants = list.assistants
        running = count(is_assistant_turn_running, assistants)
        string(length(assistants), length(assistants) == 1 ? " conversation" : " conversations",
               " · ", running, " running")
    end)
    body = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        assistants = list.assistants
        isempty(assistants) && return Cell[Cell(WidgetLabel("No assistant is open in this window.";
                                                            text_style = p.muted_color))]
        rows = Any[_build_assistant_row(list, a, clock) for a in assistants]
        Cell[Cell(WidgetTable(collect(Any, _ASSISTANT_LIST_COLUMNS), rows))]
    end)
    root = VerticalLayout(Any[heading, LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.stack_gap)
    ChildrenIoMap(p, list, root, Cell(Any[]))
end
