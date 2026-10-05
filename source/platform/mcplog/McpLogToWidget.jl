# Fragment of `McpLogModule` — the MCP log drawn as widgets: a header that counts
# the calls, a choice of what the list shows, and one block for each call, in a
# pane that follows the end.

"""
    McpLogToWidget(; theme styles…, answer_lines = 8)

Draw a [`McpLog`](@ref): a header with the count of the calls, of the faults and
the time that the calls held the editor; a choice of all calls, the tool calls
only, or the faults only; and one block for each call, oldest first, in a pane
that follows the end. A block says the time, the method, the tool or the URI,
the duration and whether the call was answered or a fault; then the code of
`execute_julia_code` as Julia, one field of code for each line, or the other
arguments; then the answer, folded after `answer_lines` lines.

Read only: a log is what happened, and a person edits nothing of it.
"""
@projection UntrackedCell struct McpLogToWidget <: Projection
    heading_text::StyleText = get_mcp_log_style(nothing, :heading_text)
    call_text::StyleText = get_mcp_log_style(nothing, :call_text)
    answered_text::StyleText = get_mcp_log_style(nothing, :answered_text)
    fault_text::StyleText = get_mcp_log_style(nothing, :fault_text)
    muted_text::StyleText = get_mcp_log_style(nothing, :muted_text)
    gap::Int = get_mcp_log_style(nothing, :gap)
    answer_lines::Int = 8
end

"""
    make_mcp_log_projection(; theme = nothing) -> McpLogToWidget

The projection of the MCP log with the styles of `theme`: a `McpLogTheme`,
scaled or not, or the default styles for `nothing`.
"""
function make_mcp_log_projection(; theme = nothing)
    get_style(name) = get_mcp_log_style(theme, name)
    McpLogToWidget(; heading_text = get_style(:heading_text), call_text = get_style(:call_text),
                   answered_text = get_style(:answered_text), fault_text = get_style(:fault_text),
                   muted_text = get_style(:muted_text), gap = get_style(:gap))
end

const _MCP_LOG_CHOICES = ("all", "tools", "faults")

# A duration as a person reads it: `120 ms`, `1.4 s`.
_format_mcp_duration(seconds::Real) =
    seconds < 1 ? string(round(Int, 1000 * seconds), " ms") : string(round(seconds; digits = 1), " s")

# Whether the choice of the pane shows `entry`.
function _is_shown_mcp_call(choice, entry::McpCallEntry)
    choice == "tools" && return entry.method == "tools/call"
    choice == "faults" && return entry.fault
    true
end

# An answer folded after `count` lines, with a line that says how many it hides.
function _fold_mcp_answer(answer::AbstractString, count::Integer)
    lines = split(answer, '\n')
    length(lines) <= count && return String(answer)
    join([lines[1:count]; "… $(length(lines) - count) more lines"], "\n")
end

function _build_mcp_call_block(p::McpLogToWidget, entry::McpCallEntry)
    line = HorizontalLayout(Any[
            WidgetLabel(Libc.strftime("%H:%M:%S", entry.time); text_style = p.muted_text),
            WidgetLabel(entry.method; text_style = p.muted_text),
            WidgetLabel(entry.name; text_style = p.call_text),
            WidgetLabel(_format_mcp_duration(entry.duration); text_style = p.muted_text),
            WidgetLabel(entry.fault ? "fault" : "answered";
                        text_style = entry.fault ? p.fault_text : p.answered_text)];
        vertical_align = :center, gap = 2 * p.gap)
    parts = Any[line]
    if entry.name == "execute_julia_code" && !isempty(entry.arguments)
        for code in split(entry.arguments, '\n')
            push!(parts, WidgetText(String(code); language = :julia))
        end
    elseif !isempty(entry.arguments)
        push!(parts, WidgetLabel(entry.arguments; text_style = p.muted_text))
    end
    isempty(entry.answer) ||
        push!(parts, WidgetTextarea(_fold_mcp_answer(entry.answer, p.answer_lines); rows = 0))
    VerticalLayout(parts; horizontal_align = :left, gap = p.gap, child_width = Fill)
end

function print_document(p::McpLogToWidget, recursion, log::McpLog, ctx)
    heading = WidgetLabel(() -> string(log.count, log.count == 1 ? " call · " : " calls · ",
                                       log.faults, log.faults == 1 ? " fault · " : " faults · ",
                                       _format_mcp_duration(log.held), " held the editor");
                          text_style = p.heading_text)
    choice = WidgetToggleGroup(Any[_MCP_LOG_CHOICES...]; values = Any[_MCP_LOG_CHOICES...],
                               target = log.shown, field = "value")
    set_cell_computation!(getfield(choice, :selected),
                          () -> something(findfirst(==(log.shown.value), _MCP_LOG_CHOICES), 1))
    calls = VerticalLayout(Any[]; horizontal_align = :left, gap = 2 * p.gap, child_width = Fill)
    set_cell_computation!(getfield(calls.children, :elements), () -> begin
        choice_value = log.shown.value
        shown = [entry for entry in log.entries if _is_shown_mcp_call(choice_value, entry)]
        isempty(shown) && return Cell[Cell(WidgetLabel("no call yet"; text_style = p.muted_text))]
        Cell[Cell(_build_mcp_call_block(p, entry)) for entry in shown]
    end)
    root = VerticalLayout(Any[heading, choice,
                              LayoutConstraint(WidgetScrollPane(calls; follow_end = true);
                                               width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.gap)
    ChildrenIoMap(p, log, root, Cell(Any[]))
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw the MCP log. The widgets it builds come back
# through the renderer, which draws them with the rows of the widgets.

function __init__()
    register_natural_graphics!(:mcplog, (; measure, appearance) -> Pair{Type,Any}[
        McpLog => ChainingProjection(make_mcp_log_projection(; theme = get_scaled_theme!(appearance, McpLogTheme)),
                                     VerticalLayoutToGraphicsCanvas())])
end
