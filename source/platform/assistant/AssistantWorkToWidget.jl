# Fragment of `AssistantModule` — what the work page of an assistant shows: a
# column of cards in a scroll pane of its own. A card of a plan and a card of a
# tree hold that document, and the maps of the page lead a path of the page to
# the document and back, so a double click on a node of a tree opens the page of
# the node in the navigator around the page.

"""
    AssistantWorkToWidget(theme)

Draw an [`AssistantWork`](@ref) as a column of cards, in a scroll pane:

- **The job**: the title of the assistant and its first prompt, and below it the
  plan of the plan mode when the agent made one.
- **Now**: what the turn that runs does, the step in progress of the first plan
  with steps, how long the turn runs, and how much of its context the session
  uses. The time reads the clock of the editor only while a turn runs, so an
  idle page draws no frame.
- **The plans**: each other plan of the agent, with the view of a plan.
- **Work**: the tree of the work: the session, its subagents, their
  background tasks and the turns of each subagent, at every depth. A double click on a node opens its page.
- **Processes**: the tree of the processes of the session, or a line that says
  that the agent gives none.
- **Notices**: the notices of the agent, the newest first, each with its time
  and its severity.

Each value reads the cells of the assistant and of its work, so the page follows
the agent. With no theme it takes the values of the default theme.
"""
@projection UntrackedCell struct AssistantWorkToWidget
    stack_gap::Int = get_conversation_style(nothing, :section_gap)
    muted_color::StyleColor = get_conversation_style(nothing, :placeholder_color)
end

AssistantWorkToWidget(theme::Union{ConversationTheme,ScaledConversationTheme}) =
    AssistantWorkToWidget(; stack_gap = get_conversation_style(theme, :section_gap),
                          muted_color = get_conversation_style(theme, :placeholder_color))

# The steps from the root of a page to its column of cards: the scroll pane stands
# in a constraint, and the column is its content.
const _PAGE_COLUMN_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(1),
                            FieldReferenceStep("child"), FieldReferenceStep("content"))

function print_document(p::AssistantWorkToWidget, recursion, work::AssistantWork, context)
    clock = context === nothing ? nothing : context.clock
    root, column = _make_page_column(p)
    iomap = ChildrenIoMap(p, work, root, Cell(Any[]))
    set_output_path_computations!(root, work,
                                  path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    _follow_page_column!(root)
    set_cell_computation!(getfield(column.children, :elements), () -> begin
        parts = _collect_work_page_parts(work)
        cards = Any[_build_work_page_card(p, work, part, clock) for part in parts]
        run_without_cell_tracking() do
            for place in eachindex(parts)
                _follow_work_page_card!(column, cards[place], parts[place], place)
            end
        end
        Cell[Cell(card) for card in cards]
    end)
    iomap
end

# A root that holds a scroll pane over a column, which fill the page; the column
# and the root.
function _make_page_column(p)
    column = VerticalLayout(Any[]; gap = p.stack_gap, child_width = Fill)
    scroll = LayoutConstraint(WidgetScrollPane(column); width = Fill, height = Fill)
    (VerticalLayout(Any[scroll]; child_width = Fill), column)
end

# The constraint, the scroll pane and the column each hold their part of the paths
# of the root.
function _follow_page_column!(root)
    constraint = root.children[1]
    scroll = constraint.child
    column = scroll.content
    for (output, input, steps) in ((constraint, root, _PAGE_COLUMN_STEPS[1:2]),
                                   (scroll, constraint, _PAGE_COLUMN_STEPS[3:3]),
                                   (column, scroll, _PAGE_COLUMN_STEPS[4:4]))
        set_output_path_computations!(output, input,
                                      path -> _find_path_below(path, steps))
    end
    root
end

# The cards of the page, in order: each a kind, and the index of its plan in
# `plans` for the card of a plan.
function _collect_work_page_parts(work::AssistantWork)
    plans = collect(work.plans)
    plan_mode = findfirst(plan -> plan.id == "plan-mode", plans)
    parts = Any[(kind = :job, index = 0)]
    plan_mode === nothing || push!(parts, (kind = :plan, index = plan_mode))
    push!(parts, (kind = :now, index = 0))
    others = [(kind = :plan, index = index)
              for index in eachindex(plans) if index != plan_mode]
    append!(parts, others)
    push!(parts, (kind = :work, index = 0))
    processes = work.processes === nothing ? :no_processes : :processes
    push!(parts, (kind = processes, index = 0))
    push!(parts, (kind = :notices, index = 0))
    parts
end

function _build_work_page_card(p, work::AssistantWork, part, clock)
    a = work.assistant
    kind = part.kind
    kind === :plan &&
        return make_embed_card(work.plans[part.index], _get_plan_card_title(work, part))
    kind === :work && return make_embed_card(work.work_tree, "Work")
    kind === :processes && return make_embed_card(work.process_tree, "Processes")
    labels = kind === :job ? Any[
                 WidgetLabel(() -> compute_assistant_overview_title(a)),
                 WidgetLabel(() -> "First prompt: " *
                                   something(find_first_prompt(a), "none"))] :
             kind === :now ? Any[
                 WidgetLabel(() -> "Activity: " * _describe_work_activity(a)),
                 _make_shown_label(() -> _describe_active_work_step(work)),
                 _make_shown_label(() -> _format_running_turn_time(a, clock)),
                 WidgetLabel(() -> "Context: " * _format_context_use(a))] :
             kind === :no_processes ?
                 Any[WidgetLabel("The agent gives no process.";
                                 text_style = p.muted_color)] :
             Any[_build_notice_lines(p, work)]
    WidgetCard(; title = WidgetLabel(_WORK_CARD_TITLES[kind]),
               content = VerticalLayout(labels; child_width = Fill))
end

# The title of each card of the page that holds no document.
const _WORK_CARD_TITLES =
    Dict(:job => "The job", :now => "Now", :notices => "Notices",
         :no_processes => "Processes")

# The title of the card of a plan: the plan of the plan mode, or the title of the
# plan.
function _get_plan_card_title(work::AssistantWork, part)
    plan = work.plans[part.index]
    plan.id == "plan-mode" ? "Plan of the plan mode" : get_document_title(plan)
end

# A label that shows only while its text is not empty.
function _make_shown_label(text::Function)
    label = WidgetLabel(text)
    set_cell_computation!(getfield(label, :visible), () -> !isempty(text()))
    label
end

# What the turn that runs does, or that none runs.
function _describe_work_activity(a::Assistant)
    activity = describe_assistant_activity(a)
    isempty(activity) ? "no turn runs" : activity
end

# The step in progress of the first plan with steps, with what it shows while it
# runs; empty without one.
function _describe_active_work_step(work::AssistantWork)
    for plan in collect(work.plans)
        isempty(plan.steps) && continue
        step = _find_running_plan_step(plan.steps)
        step === nothing && return ""
        shown = isempty(step.active_title) ? step.title : step.active_title
        return "Step: " * _format_one_line(shown)
    end
    ""
end

function _find_running_plan_step(steps)
    for step in collect(steps)
        step.status === :in_progress && return step
        found = _find_running_plan_step(step.children)
        found === nothing || return found
    end
    nothing
end

# How long the turn that runs runs. While a turn runs the label reads the clock of
# the editor, so it computes again on each frame; between turns it reads no clock.
function _format_running_turn_time(a::Assistant, clock)
    is_assistant_turn_running(a) || return ""
    clock === nothing || get_reactive_clock_time(clock)
    turns = collect(a.conversation.turns)
    index = findlast(turn -> turn.role === :assistant && turn.start_time > 0, turns)
    index === nothing && return ""
    "The turn runs for " * _format_assistant_duration(time() - turns[index].start_time)
end

# How much of its context the session uses, as far as the agent says.
_format_context_use(a::Assistant) =
    a.agent_usage === nothing ? "not known yet" : format_agent_usage(a.agent_usage)

# The notices of the work, the newest first, a line each.
function _build_notice_lines(p, work::AssistantWork)
    lines = VerticalLayout(Any[]; child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () -> begin
        notices = reverse(collect(work.assistant.agent_work.notices))
        isempty(notices) &&
            return Cell[Cell(WidgetLabel("No notice."; text_style = p.muted_color))]
        Cell[Cell(WidgetLabel(_format_agent_notice(notice))) for notice in notices]
    end)
    lines
end

# A notice in a line: `18:40:01 · warning · Retrying — The model is busy`.
function _format_agent_notice(notice::AgentNotice)
    line = string(Libc.strftime("%H:%M:%S", notice.time), " · ", notice.severity, " · ",
                  notice.title)
    line = isempty(notice.description) ? line : line * " — " * notice.description
    _format_one_line(line)
end

# ── The paths of the cards ───────────────────────────────────────────────────

# A card holds its part of the paths of the column, and the documents below it.
# The card of a plan follows the paths of its plan (`make_embed_card`), which
# holds its own. The page made the trees, so a tree takes its part of the paths
# of its card, as the view of a plan leads the paths of its tree of steps.
function _follow_work_page_card!(column, card, part, place::Int)
    part.kind === :plan && return card
    steps = (FieldReferenceStep("children"), ElementReferenceStep(place))
    set_output_path_computations!(card, column, path -> _find_path_below(path, steps))
    if part.kind === :work || part.kind === :processes
        content = (FieldReferenceStep("content"),)
        set_output_path_computations!(card.content, card,
                                      path -> _find_path_below(path, content))
    else
        set_output_tree_path_computations!(card)
    end
    card
end

# The path in the tree of `kind` of a path from the page: a part of the work is the
# same path below the root of the tree of the work, and a part of `processes` is
# the same path below the root of the tree of the processes. `nothing` for a path
# that the tree does not show.
function _map_into_work_tree(kind::Symbol, path::ConcreteReference)
    steps = get_reference_steps(strip_reference_types(path))
    root = FieldReferenceStep("root")
    if kind === :work
        is_work = steps[1] in (FieldReferenceStep("subagents"),
                               FieldReferenceStep("background_tasks"))
        return is_work ? extend_reference(EmptyReference(), root, steps...) : nothing
    end
    steps[1] == FieldReferenceStep("processes") || return nothing
    extend_reference(EmptyReference(), root, steps[2:end]...)
end

# The path from the page of a path inside the card of `part`, or `nothing` for a
# part of a tree that is no document of the work.
function _map_from_work_card(part, inside::Reference)
    steps = get_reference_steps(inside)
    part.kind === :plan &&
        return extend_reference(EmptyReference(), FieldReferenceStep("plans"),
                                ElementReferenceStep(part.index), steps...)
    (isempty(steps) || steps[1] != FieldReferenceStep("root")) && return nothing
    part.kind === :work && return extend_reference(EmptyReference(), steps[2:end]...)
    extend_reference(EmptyReference(), FieldReferenceStep("processes"), steps[2:end]...)
end

# The steps from the root of the page to the card at `place`.
_get_work_card_steps(place::Int) =
    (_PAGE_COLUMN_STEPS..., FieldReferenceStep("children"), ElementReferenceStep(place))

# A part of the work, a part of the processes and a part of a plan are the same
# path in the card of their document. A part that the page drew is named by its
# introduced path.
function map_reference_forward(p::AssistantWorkToWidget, iomap, reference)
    reference isa Reference || return nothing
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    steps = get_reference_steps(path)
    for (place, part) in enumerate(_collect_work_page_parts(iomap.input))
        inside = if part.kind === :plan
            is_plan = steps[1] == FieldReferenceStep("plans") && length(steps) >= 2 &&
                      steps[2] isa RangeReferenceStep && steps[2].stop == part.index
            is_plan ? extend_reference(EmptyReference(), steps[3:end]...) : nothing
        elseif part.kind === :work || part.kind === :processes
            _map_into_work_tree(part.kind, path)
        else
            nothing
        end
        inside === nothing && continue
        card = extend_reference(EmptyReference(), _get_work_card_steps(place)...)
        return concat_references(card, make_embed_card_path(inside))
    end
    nothing
end

function map_reference_backward(p::AssistantWorkToWidget, iomap, reference)
    reference isa Reference || return nothing
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    for (place, part) in enumerate(_collect_work_page_parts(iomap.input))
        part.kind in (:plan, :work, :processes) || continue
        below = _find_path_below(path, _get_work_card_steps(place))
        inside = below === nothing ? nothing : find_embed_card_path_inside(below)
        inside === nothing && continue
        mapped = _map_from_work_card(part, inside)
        mapped === nothing || return mapped
        break
    end
    make_introduced_reference(p, iomap, path)
end
