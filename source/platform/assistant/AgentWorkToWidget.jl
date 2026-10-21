# Fragment of `AssistantModule` — the page of a subagent: what it is and how it
# runs, its plans, its transcript, and a link to each of its subagents and its
# background tasks. The page keeps no view state: the links open pages of the
# navigator around it.

"""
    AgentWorkToWidget(theme)

Draw an [`AgentWork`](@ref) as the page of a subagent, a column of cards in a
scroll pane:

- a header: its title, its type, its state, its tokens, its tool calls and how
  long it worked, its last tool and its summary, and Cancel while it runs and
  can be cancelled;
- each of its plans, with the view of a plan;
- its transcript: its prompt, its text, its reasoning and its tool calls, drawn
  as the transcript of an assistant;
- a link to each of its subagents and its background tasks, which opens its
  page.

Each value reads the cells of the work, so the page follows the subagent.
"""
@projection UntrackedCell struct AgentWorkToWidget
    stack_gap::Int = get_conversation_style(nothing, :section_gap)
    muted_color::StyleColor = get_conversation_style(nothing, :placeholder_color)
end

AgentWorkToWidget(theme::Union{ConversationTheme,ScaledConversationTheme}) =
    AgentWorkToWidget(; stack_gap = get_conversation_style(theme, :section_gap),
                        muted_color = get_conversation_style(theme, :placeholder_color))

function print_document(p::AgentWorkToWidget, recursion, work::AgentWork, context)
    root, column = _make_page_column(p)
    iomap = ChildrenIoMap(p, work, root, Cell(Any[]))
    set_output_path_computations!(root, work,
                                  path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    _follow_page_column!(root)
    set_cell_computation!(getfield(column.children, :elements), () -> begin
        parts = _collect_agent_page_parts(work)
        # The links follow the lists of the work, and their words follow each part.
        children = (collect(work.subagents), collect(work.background_tasks))
        cards = Any[_build_agent_page_card(p, work, part, children) for part in parts]
        run_without_cell_tracking() do
            for place in eachindex(parts)
                _follow_agent_page_card!(column, cards[place], parts[place], place)
            end
        end
        Cell[Cell(card) for card in cards]
    end)
    iomap
end

# The cards of the page, in order: each a kind, and the index of its plan in
# `plans` for the card of a plan.
function _collect_agent_page_parts(work::AgentWork)
    plans = [(kind = :plan, index = index) for index in eachindex(work.plans)]
    Any[(kind = :header, index = 0), plans..., (kind = :transcript, index = 0),
        (kind = :links, index = 0)]
end

function _build_agent_page_card(p, work::AgentWork, part, children)
    if part.kind === :plan
        plan = work.plans[part.index]
        return make_embed_card(plan, get_document_title(plan))
    end
    part.kind === :transcript && return make_embed_card(work.conversation, "Transcript")
    lines = part.kind === :header ? _build_agent_header_lines(work) :
            _build_agent_link_lines(p, work, children...)
    title = part.kind === :header ? "Subagent" : "Subagents and background tasks"
    WidgetCard(; title = WidgetLabel(title),
               content = VerticalLayout(lines; child_width = Fill))
end

function _build_agent_header_lines(work::AgentWork)
    cancel = WidgetButton("Cancel"; tooltip = "Stop the work of the subagent.",
                          action = editor -> _cancel_agent_subagent_work(editor, work))
    set_cell_computation!(getfield(cancel, :visible),
                          () -> work.state === :running && work.can_cancel)
    Any[WidgetLabel(() -> get_document_title(work)),
        _make_shown_label(() -> _format_agent_fact("Type: ", work.description)),
        WidgetLabel(() -> "State: " * _describe_agent_work_state(work.state) *
                          _format_agent_start(work) *
                          _format_agent_stop_reason(work.stop_reason)),
        _make_shown_label(() -> _format_agent_work_use(work)),
        _make_shown_label(() -> _format_agent_fact("Last tool: ", work.last_tool)),
        _build_agent_summary_lines(work),
        cancel]
end

# `prefix` and `fact` in one line, or nothing while the fact is empty.
_format_agent_fact(prefix::AbstractString, fact::AbstractString) =
    isempty(fact) ? "" : prefix * _format_one_line(fact)

# When a subagent that runs started; it reads no clock.
_format_agent_start(work::AgentWork) =
    work.state === :running && work.start_time !== nothing ?
        " since " * Libc.strftime("%H:%M:%S", work.start_time) : ""

# The summary of the work as a block of its lines under the word `Summary`, or
# nothing while it is empty.
function _build_agent_summary_lines(work::AgentWork)
    lines = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () -> begin
        summary = strip(work.summary)
        isempty(summary) && return Cell[]
        texts = ["Summary:"; split(summary, r"\R")]
        Cell[Cell(WidgetLabel(String(rstrip(text)))) for text in texts]
    end)
    lines
end

_format_agent_stop_reason(reason) = reason === nothing ? "" : " · ended " * String(reason)

# The tokens, the tool calls and the time of the work, as far as the agent says.
function _format_agent_work_use(work::AgentWork)
    words = String[]
    tokens = work.token_count
    tokens === nothing || push!(words, _format_token_count(tokens) * " tokens")
    calls = work.tool_call_count
    calls === nothing || push!(words, string(calls, " tool calls"))
    work.duration === nothing || push!(words, _format_assistant_duration(work.duration))
    join(words, " · ")
end

# A link to each subagent and each background task of the work: a press opens its
# page in the navigator around the page.
function _build_agent_link_lines(p, work::AgentWork, subagents, background_tasks)
    lines = Any[]
    for (field, children) in (("subagents", subagents),
                              ("background_tasks", background_tasks))
        for index in eachindex(children)
            push!(lines, _make_agent_work_link(work, field, index, children[index]))
        end
    end
    isempty(lines) &&
        push!(lines, WidgetLabel("No subagent and no background task.";
                                 text_style = p.muted_color))
    lines
end

# The text of the link of a part of the work: its label, and the detail of its
# decoration after it, as a row of a tree shows them.
function _join_label_and_detail(child)
    label = format_tree_node_label(child)
    detail = get_document_decoration(child).detail
    isempty(detail) ? label : label * " · " * detail
end

function _make_agent_work_link(work::AgentWork, field::AbstractString, index::Int, child)
    reference = extend_reference(EmptyReference(), FieldReferenceStep(field),
                                 ElementReferenceStep(index))
    open = (_, _) -> OpenPageOperation(work, reference)
    binding = GestureBinding(MouseClickPattern(:left), open;
                             description = "Open the page of a part of the work",
                             domain = "assistant")
    link = WidgetButton(""; tooltip = "Open the page of this part of the work.", gestures = GestureBinding[binding])
    set_cell_computation!(link, () -> _format_one_line(_join_label_and_detail(child)))
end

# A press of Cancel: the assistant whose session runs the subagent asks its agent
# to stop the work of the subagent, as background work, as Stop of a background
# task finds the session at the press. With no loop, the work runs on the thread
# of the press, as a turn does.
function _cancel_agent_subagent_work(editor, work::AgentWork)
    a = _find_subagent_assistant(editor, work)
    a === nothing && return nothing
    session = a.agent_session
    cancel = () -> try
        Base.invokelatest(cancel_agent_subagent!, session.connection, session.session_id,
                          work.id)
    catch exception
        is_fault_exception(exception) || rethrow()
        @warn("The agent did not cancel its subagent.", subagent = work.id, exception)
    end
    start_background_work(cancel; description = "the cancel of a subagent", editor,
                          parent = nothing, is_sticky = !is_editor_loop_running(editor))
    nothing
end

# The assistant of the list of the assistants of `editor` whose session holds the
# subagent `work`, at any depth, or `nothing`.
function _find_subagent_assistant(editor, work::AgentWork)
    for a in collect(get_session_assistant_list(; editor).assistants)
        a.agent_session isa ExternalAgentSession || continue
        _holds_agent_work(a.agent_work, work) && return a
    end
    nothing
end

_holds_agent_work(parent::AgentWork, work::AgentWork) =
    any(child -> child === work || _holds_agent_work(child, work),
        collect(parent.subagents))

# ── The paths of the cards ───────────────────────────────────────────────────

# A card holds its part of the paths of the column, and so do its lines; the card
# of a plan and the card of the transcript follow their documents.
function _follow_agent_page_card!(column, card, part, place::Int)
    part.kind in (:plan, :transcript) && return card
    steps = (FieldReferenceStep("children"), ElementReferenceStep(place))
    set_output_path_computations!(card, column, path -> _find_path_below(path, steps))
    set_output_tree_path_computations!(card)
    card
end

# The steps from the work to the document that the card of `part` holds:
# `plans[i]` for a plan and `conversation` for the transcript.
function _get_agent_card_steps(part)
    part.kind === :plan &&
        return (FieldReferenceStep("plans"), ElementReferenceStep(part.index))
    part.kind === :transcript ? (FieldReferenceStep("conversation"),) : nothing
end

# A part of a plan and a part of the transcript are the same path in the card of
# their document; a part that the page drew is named by its introduced path.
function map_reference_forward(p::AgentWorkToWidget, iomap, reference)
    reference isa Reference || return nothing
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    for (place, part) in enumerate(_collect_agent_page_parts(iomap.input))
        steps = _get_agent_card_steps(part)
        inside = steps === nothing ? nothing : _find_path_below(path, steps)
        inside === nothing && continue
        card = extend_reference(EmptyReference(), _get_work_card_steps(place)...)
        return concat_references(card, make_embed_card_path(inside))
    end
    nothing
end

function map_reference_backward(p::AgentWorkToWidget, iomap, reference)
    reference isa Reference || return nothing
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    for (place, part) in enumerate(_collect_agent_page_parts(iomap.input))
        steps = _get_agent_card_steps(part)
        steps === nothing && continue
        below = _find_path_below(path, _get_work_card_steps(place))
        inside = below === nothing ? nothing : find_embed_card_path_inside(below)
        inside === nothing && continue
        return extend_reference(EmptyReference(), steps...,
                                get_reference_steps(inside)...)
    end
    make_introduced_reference(p, iomap, path)
end
