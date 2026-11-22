# Fragment of `AssistantModule` — the card of a command that an external agent
# runs: its title, the state of its task and its row on one line, the command one
# time, and the last lines of its output.

"""
    AgentTerminalCommandToWidget(theme; widget_theme, task_theme)
    AgentTerminalCommandToWidget(; title_text, command_text, muted_color, error_color, label_gap, section_gap)

Draw an [`AgentTerminalCommand`](@ref) as a short card of a turn:

- the header: the title of the call, the state of the task (`DONE`, `ERROR`, or
  the state while it runs), the time it took or since when it runs, the name of
  its row, such as `T5`, which opens the page of the task, and Stop while the
  command runs;
- the error message of a task that ended with `ERROR`, such as `Non-zero exit
  code: 3`;
- the command, one time, after `\$ `; not when the title is the command itself;
- the last 8 lines of each stream that has lines, under the count of its lines,
  which opens the page of every line ([`make_task_output_preview`](@ref)).

A command that a file gave has no task: its header is its title, and the last 8
lines of the text that its call answered stand in place of the output. A click on
the chevron of the card writes the choice of the person into the `fold` of the
command. With no choice the card is open: the rule of the transcript, which folds
each part in an opened work line of a finished turn, does not reach it. Each value
follows the command and its task, without a new print.
"""
@projection UntrackedCell struct AgentTerminalCommandToWidget
    title_text::StyleText = get_conversation_style(nothing, :kind_text)
    command_text::StyleText = get_conversation_style(nothing, :prompt_text)
    muted_color::StyleColor = get_task_style(nothing, :muted_color)
    error_color::StyleColor = get_task_style(nothing, :error_color)
    label_gap::Int = get_widget_style(nothing, :label_gap)
    section_gap::Int = get_widget_style(nothing, :section_gap)
end

AgentTerminalCommandToWidget(theme::Union{ConversationTheme,ScaledConversationTheme}; widget_theme = nothing,
                     task_theme = nothing) =
    AgentTerminalCommandToWidget(; title_text = get_conversation_style(theme, :kind_text),
                           command_text = get_conversation_style(theme, :prompt_text),
                           muted_color = get_task_style(task_theme, :muted_color),
                           error_color = get_task_style(task_theme, :error_color),
                           label_gap = get_widget_style(widget_theme, :label_gap),
                           section_gap = get_widget_style(widget_theme, :section_gap))

function print_document(p::AgentTerminalCommandToWidget, recursion, command::AgentTerminalCommand, ctx)
    task = command.task
    header = Any[WidgetLabel(() -> get_evaluation_title(command.call); text_style = p.title_text)]
    body = Any[]
    if task isa TaskDocument
        append!(header, Any[make_task_state_badge(task),
                            WidgetLabel(() -> _format_terminal_command_time(task); text_style = p.muted_color),
                            WidgetLink(get_work_item_identifier(task), task; tooltip = "Open the page of the task."),
                            _make_terminal_command_stop_button(task)])
        push!(body, make_task_error_line(task; color = p.error_color, with_reason = true))
    end
    _shows_terminal_command_line(command) &&
        push!(body, WidgetLabel("\$ " * command.command; text_style = p.command_text))
    push!(body, task isa TaskDocument ? make_task_output_preview(task; gap = p.section_gap, color = p.muted_color) :
                                        _build_answered_lines(p, command.call))
    card = WidgetCard(; title = HorizontalLayout(header; vertical_align = :center, gap = p.label_gap),
                      content = VerticalLayout(body; gap = p.section_gap, child_width = Fill),
                      variant = :muted, collapsible = true)
    set_cell_computation!(getfield(card, :collapsed), () -> command.fold === :folded)
    # The card stands in a column, which its own canvas draws, as the page of a
    # subagent does; the renderer draws the widgets inside.
    ChildrenIoMap(p, command, VerticalLayout(Any[card]; child_width = Fill), Cell(Any[]))
end

# The card of a command, in the column that the print answered.
_find_terminal_command_card(iomap) = iomap.output.children[1]

# A click on the chevron of the card writes the choice of the person, the
# opposite of what the card shows, into the fold of the command.
function map_operation_backward(p::AgentTerminalCommandToWidget, iomap, op::ToggleCollapseOperation)
    card = _find_terminal_command_card(iomap)
    op.target === card || return op
    ReplaceConversationFoldOperation(iomap.input, :fold, card.collapsed === true ? :open : :folded)
end

# The time that the command took, as the page of a task writes it (`0.8 s`,
# `1:02.5`), or since when it runs; nothing before it starts. It reads no clock,
# so it changes only when the task does.
function _format_terminal_command_time(task::TaskDocument)
    current = get_current_task_execution(task)
    (current === nothing || current.start_time === nothing) && return ""
    current.end_time === nothing && return "since " * Libc.strftime("%H:%M:%S", current.start_time)
    text = format_elapsed_time(current.end_time - current.start_time; precision = 1)
    occursin(':', text) ? text : text * " s"
end

# Stop, which shows while the command runs and stops it, as Stop of a task alone
# on its page does.
function _make_terminal_command_stop_button(task::TaskDocument)
    stop = WidgetButton("Stop"; tooltip = "Stop the command.", action = _ -> (stop_task!(task); nothing))
    set_cell_computation!(getfield(stop, :visible), () -> get_task_document_status(task) === :running)
    stop
end

# The last lines of the text that the call answered, for a command that a file
# gave.
function _build_answered_lines(p::AgentTerminalCommandToWidget, call::EvaluatorForm)
    text = rstrip(call.output)
    lines = isempty(text) ? SubString{String}[] : split(text, '\n')
    kept = lines[max(1, end - TASK_PREVIEW_LINES + 1):end]
    VerticalLayout(Any[WidgetLabel(String(line); text_style = p.muted_color) for line in kept];
                   gap = 0, child_width = Fill)
end
