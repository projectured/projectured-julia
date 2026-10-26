# Fragment of `WorkflowModule` — the outline of a workflow as widgets: the goal,
# then a row of the outline kit for each node of the tree under it, indented by
# its depth along the guide lines of the nodes above it.
#
# The output holds the documents of the input that are not prose — an element of
# a node, the text of an entry in another domain — and the renderer draws each of
# them through the view of its own domain. So text, Markdown, syntax and widgets
# mix in one outline, and an edit in any of them edits the document itself. The
# maps of this file translate a path between the input and the output by the
# places where those documents sit.

# ── The projections ──────────────────────────────────────────────────────

"""
    WorkflowNodeToWidget(; outline)

Draw a node and the tree under it as an outline: its title, the counts of the
states of its steps, then a row for each node under it, indented by its depth,
with a guide line under the mark of each node down along the rows under it.

A row shows the fold and the mark of a node: the state of a step as a ring, a
decision as a diamond, the state of an option. After the title stand the reason
of an option, "decided" or "undecided" after a decision, the count of the entries
of the journal and the time of the last one, and under it the elements of the node,
each through the view of its own domain. The menu of the row holds every
action of the node; a press on the mark of a step opens its states, and a press on
the mark of an option chooses it. `outline` holds the values of an `OutlineTheme`.
"""
@projection UntrackedCell struct WorkflowNodeToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

"""
    WorkflowEntryToWidget(; outline)

Draw an entry of a journal: its author, its time and its kind on a line, and its
text under that line, through the view of the domain of the text.
"""
@projection UntrackedCell struct WorkflowEntryToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

"""
    make_workflow_projections(; theme = nothing, outline_theme = nothing) -> NamedTuple

The projections of a workflow, `node` and `entry` of the outline and `journal` of
the timeline of its entries, with the values of the `OutlineTheme`
`outline_theme`, and `list` of the workflows of the open files, with the styles
of `theme`, a `WorkflowTheme`. Each theme is scaled or not, or the default for
`nothing`. Each projection makes
widgets; a renderer chains it with a layout to graphics, as
`make_workflow_graphics_entries` does.
"""
function make_workflow_projections(; theme = nothing, outline_theme = nothing)
    get_style(name) = get_workflow_style(theme, name)
    outline = make_theme_values_field(OutlineTheme, outline_theme)
    node = WorkflowNodeToWidget(; outline)
    entry = WorkflowEntryToWidget(; outline)
    journal = WorkflowJournalToWidget(; outline)
    list = WorkflowListToWidget(; gap = get_style(:gap))
    (; node, entry, journal, list)
end

"""
    make_workflow_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

The rows of the renderer for the documents of a workflow: each projection of the
outline, chained with `VerticalLayoutToGraphicsCanvas`, and the page of the list,
chained with `GridLayoutToGraphicsCanvas`, so the widgets that each makes come back
through the renderer. The styles are those of the `OutlineTheme` and the
`WorkflowTheme` of `appearance`.
"""
function make_workflow_graphics_entries(; measure, appearance)
    projections = make_workflow_projections(; theme = get_scaled_theme!(appearance, WorkflowTheme),
                                            outline_theme = get_scaled_theme!(appearance, OutlineTheme))
    node = ChainingProjection(projections.node, VerticalLayoutToGraphicsCanvas())
    Pair{Type,Any}[WorkflowStep => node, WorkflowDecision => node, WorkflowOption => node,
                   WorkflowEntry => ChainingProjection(projections.entry, VerticalLayoutToGraphicsCanvas()),
                   WorkflowJournal => ChainingProjection(projections.journal, VerticalLayoutToGraphicsCanvas()),
                   WorkflowList => ChainingProjection(projections.list, GridLayoutToGraphicsCanvas())]
end

# ── The IO map ───────────────────────────────────────────────────────────

# The places of the documents of the input in the output are `OutlineSlot`s of
# the outline kit, which one build makes with its output.
@iomap struct WorkflowToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    slots::Any
end

_make_field_step(name::AbstractString) = FieldReferenceStep(String(name))
_make_field_step(name::Symbol) = FieldReferenceStep(String(name))
_make_element_step(index::Integer) = RangeReferenceStep(index - 1, index)

# The steps of a child of a container in the output: its `children` field and its
# 1-based index.
_get_child_steps(index::Integer) = Any[_make_field_step("children"), _make_element_step(index)]

const _WorkflowProjection = Union{WorkflowNodeToWidget, WorkflowEntryToWidget}

function map_reference_forward(p::_WorkflowProjection, iomap::WorkflowToWidgetIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    map_outline_forward(iomap.slots, reference)
end

function map_reference_backward(p::_WorkflowProjection, iomap::WorkflowToWidgetIoMap, reference)
    reference isa Reference || return nothing
    found = map_outline_backward(iomap.slots, reference)
    found === nothing &&
        return invoke(map_reference_backward, Tuple{Projection, Any, Any}, p, iomap, reference)
    try
        annotate_reference_types(iomap.input, found)
    catch
        found
    end
end

# Every document that one build made holds its part of the image of the selection
# and of the part under the pointer of the input, by the slots of the same build.
_route_workflow_paths!(p, input, slots, output, embedded) =
    route_outline_paths!(input, output,
                         path -> something(find_introduced_path(p, path), map_outline_forward(slots, path),
                                           Some(nothing));
                         embedded)

# The IO map of a view whose output and slots one computation builds: a change of
# what the build reads builds a new output, and the stage after this one prints it
# again.
function _make_workflow_iomap(p, input, build)
    built = Cell(@computation build())
    WorkflowToWidgetIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

# ── Texts ────────────────────────────────────────────────────────────────

# A quiet field of prose at `place` for the text field `field` of the document at
# `prefix`, with its slots: a path into its value is a path into the content of
# the field, and the whole text is the whole field.
function _make_workflow_text!(slots, outline, text::PrimitiveString, prefix, field, place;
                              role::Symbol = :text, line::Union{Nothing, Symbol} = :text_line,
                              placeholder = nothing)
    push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field), _make_field_step("value")]),
                             vcat(place, Any[_make_field_step("content")])))
    push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field)]), place))
    make_outline_text(outline, () -> something(text.value, ""); role, line, placeholder)
end

# ── Times ────────────────────────────────────────────────────────────────

# The time that the text `text` of the time of an entry names, or `nothing`.
_find_workflow_text_time(text::AbstractString) =
    isempty(text) ? nothing : find_workflow_time(WorkflowEntry(time = String(text)))

# The local day of the text of a time, as a key that compares, or `nothing`.
function _get_workflow_day(text::AbstractString)
    time = _find_workflow_text_time(text)
    time === nothing ? nothing : Dates.format(time, "yyyy-mm-dd")
end

# The text of a time as a row says it: the clock alone on the day of the row
# above, and the day and the clock where the day changes, as "9 Oct 13:40".
# The local day of the text of a time, as a section of an outline says it.
function _format_workflow_day(text::AbstractString)
    time = _find_workflow_text_time(text)
    time === nothing ? String(text) : Dates.format(time, "d u")
end

function _format_workflow_when(text::AbstractString, shows_date::Bool)
    time = _find_workflow_text_time(text)
    time === nothing && return String(text)
    shows_date ? Dates.format(time, "d u HH:MM") : Dates.format(time, "HH:MM")
end

# ── Marks and menus ──────────────────────────────────────────────────────

# The glyph of each state of a step and of an option.
const _WORKFLOW_STATE_ICONS = Dict(:open => :circle, :active => :circle_dot, :done => :circle_check,
                                   :dropped => :circle_slash, :chosen => :circle_check,
                                   :rejected => :circle_x, :parked => :circle_pause)

# Whether one of the options of `decision` is chosen.
_is_decided(decision::WorkflowDecision) = any(option -> option.state === :chosen, decision.options)

# The mark of a node: the ring of the state of a step or an option, in the colour
# of its state, and a diamond for a decision, in the colour of a settled or an open
# question.
_make_workflow_icon(node::Union{WorkflowStep, WorkflowOption}) =
    WidgetIcon(_WORKFLOW_STATE_ICONS[node.state]; role = _get_state_badge_role(node.state))
_make_workflow_icon(node::WorkflowDecision) =
    WidgetIcon(:diamond; role = _is_decided(node) ? :success : :warning)

# The name of a node as a menu names it: its title, read when the menu opens, or
# its kind for an empty title.
_get_workflow_node_name(node) =
    (title = something(get_workflow_node_title(node).value, ""); isempty(title) ? _get_workflow_kind_name(node) : title)

# The kind of a node, as a control names the node it acts on. A build reads no
# title, so an edit of a title draws its text and builds no row.
_get_workflow_kind_name(::WorkflowStep) = "the step"
_get_workflow_kind_name(::WorkflowDecision) = "the decision"
_get_workflow_kind_name(::WorkflowOption) = "the option"

# The items of the menu that give a step one of its states, with the current one off.
_make_state_items(node::WorkflowStep) =
    Any[WidgetMenuItem(uppercasefirst(string(state)); icon = _WORKFLOW_STATE_ICONS[state],
                       operation = make_workflow_state_operation(node, state), enabled = node.state !== state)
        for state in get_workflow_states(node)]

# The items of the menu that change the state of an option.
function _make_option_items(decision, index::Integer, option::WorkflowOption)
    items = Any[WidgetMenuItem("Choose"; operation = make_choose_workflow_option_operation(decision, index),
                               enabled = option.state !== :chosen),
                WidgetMenuItem("Reject"; operation = make_workflow_state_operation(option, :rejected),
                               enabled = option.state !== :rejected),
                WidgetMenuItem("Park"; operation = make_workflow_state_operation(option, :parked),
                               enabled = option.state !== :parked)]
    option.state === :open ||
        push!(items, WidgetMenuItem("Reopen"; operation = make_workflow_state_operation(option, :open)))
    items
end

# The items of the menu that add a child to `node`. A new child takes the caret
# at its title, so the person types it in place.
_make_add_items(node::Union{WorkflowStep, WorkflowOption}) = Any[
    WidgetMenuItem("Add a step"; operation = _make_add_and_type_operation(node, WorkflowStep())),
    WidgetMenuItem("Add a decision"; operation = _make_add_and_type_operation(
        node, WorkflowDecision(options = [WorkflowOption()]))),
]
_make_add_items(node::WorkflowDecision) = Any[
    WidgetMenuItem("Add an option"; operation = _make_add_and_type_operation(node, WorkflowOption())),
]

# The insert of `child` at the end of the children of `node`, with the caret at the
# end of the title or the question of the child.
function _make_add_and_type_operation(node, child)
    field = child isa WorkflowDecision ? "question" : "title"
    count = length(something(get_workflow_node_title(child).value, ""))
    caret = Reference(FieldReferenceStep(field), FieldReferenceStep("value"), RangeReferenceStep(count, count))
    CompoundOperation(Any[make_insert_workflow_node_operation(node, length(get_workflow_node_children(node)) + 1, child),
                          SelectDocumentOperation(child, caret)])
end

# A menu of the groups of items `groups`, with a separator between two groups.
function _make_grouped_menu(groups)
    elements = Any[]
    for group in groups
        isempty(group) && continue
        isempty(elements) || push!(elements, WidgetSeparator())
        append!(elements, group)
    end
    WidgetMenu(elements)
end

# The menu of the row of `node`, whose parent is `parent` at `index`, or of the
# header for the root, whose parent is `nothing`: what changes its state, what
# adds to it, what changes the view, and last the delete. The operations are made
# when the menu opens.
function _make_workflow_menu(node, parent, index)
    state = node isa WorkflowStep ? _make_state_items(node) :
            node isa WorkflowOption && parent isa WorkflowDecision ? _make_option_items(parent, index, node) : Any[]
    adds = vcat(_make_add_items(node), Any[
        WidgetMenuItem("Comment"; operation = _make_comment_operation(node)),
        WidgetMenuItem("Add an element"; operation = make_new_element_operation(node))])
    parent === nothing && return _make_grouped_menu(Any[state, adds])
    siblings = get_workflow_node_children(parent)
    view = Any[WidgetMenuItem(node.collapsed ? "Unfold" : "Fold"; operation = ReplaceViewStateOperation(ToggleCollapseOperation(node))),
               WidgetMenuItem(node.journal_shown ? "Hide the journal" : "Show the journal";
                              operation = _make_show_journal_operation(node, !node.journal_shown)),
               WidgetMenuItem("Move up"; enabled = index > 1,
                              operation = index > 1 ? _make_move_node_operation(node, parent, index, parent, index - 1) : nothing),
               WidgetMenuItem("Move down"; enabled = index < length(siblings),
                              operation = index < length(siblings) ?
                                  _make_move_node_operation(node, parent, index, parent, index + 1) : nothing)]
    delete = Any[WidgetMenuItem("Delete"; operation = make_delete_workflow_node_operation(parent, index))]
    _make_grouped_menu(Any[state, adds, view, delete])
end

# The write that shows or hides the journal of `node` under its row: view state.
_make_show_journal_operation(node, shown::Bool) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(node, "journal_shown", shown))

# The operation of "Comment": a new comment at the end of the journal of `node`, the
# journal shown under the row, and the caret in the comment.
function _make_comment_operation(node)
    entry = make_workflow_entry("")
    CompoundOperation(Any[make_add_workflow_entry_operation(node, entry), _make_show_journal_operation(node, true),
                          SelectDocumentOperation(entry, Reference(FieldReferenceStep("text"), FieldReferenceStep("value"),
                                                                   RangeReferenceStep(0, 0)))])
end

# The answer of a press on the mark of `node`: the menu of the states of a step,
# the choice of an option, and the menu of the row of a decision.
function _make_mark_operation(node, parent, index)
    node isa WorkflowStep &&
        return make_outline_menu_operation(_get_workflow_node_name(node), () -> WidgetMenu(_make_state_items(node)))
    node isa WorkflowOption && parent isa WorkflowDecision &&
        return node.state === :chosen ? nothing : make_choose_workflow_option_operation(parent, index)
    make_outline_menu_operation(_get_workflow_node_name(node), () -> _make_workflow_menu(node, parent, index))
end

# ── The outline of a node ────────────────────────────────────────────────

# The counts of the steps under `root`, of those done and of those active, and of
# the decisions and of those settled.
function _count_workflow_progress(root)
    steps = 0; done = 0; active = 0; decisions = 0; decided = 0
    visit(node) = begin
        if node isa WorkflowStep
            steps += 1
            node.state === :done && (done += 1)
            node.state === :active && (active += 1)
        elseif node isa WorkflowDecision
            decisions += 1
            _is_decided(node) && (decided += 1)
        end
        foreach(visit, get_workflow_node_children(node))
    end
    foreach(visit, get_workflow_node_children(root))
    (; steps, done, active, decisions, decided)
end

# The counts of the states of the steps and of the decisions under `root`, as the
# header says them.
function _describe_workflow_progress(root)
    (; steps, done, active, decisions, decided) = _count_workflow_progress(root)
    parts = String[string(done, " of ", steps, steps == 1 ? " step done" : " steps done")]
    active > 0 && push!(parts, string(active, " active"))
    decisions > 0 && push!(parts, string(decided, " of ", decisions, decisions == 1 ? " decision settled" :
                                                                                     " decisions settled"))
    join(parts, " · ")
end

# The nodes of the tree under `root` that the outline shows, in the order of the
# rows, each with its parent, its index in its parent, its depth and its path from
# `root`: a folded node shows no node under it.
function _collect_workflow_rows(root)
    rows = Any[]
    visit(node, parent, index, grand, parent_index, depth, prefix) = begin
        push!(rows, (; node, parent, index, grand, parent_index, depth, prefix))
        node.collapsed && return
        # Local, so the walk under a child does not change the field of its siblings.
        local field = _get_children_field(node)
        for (child_index, child) in enumerate(get_workflow_node_children(node))
            visit(child, node, child_index, parent, index, depth + 1,
                  vcat(prefix, Any[_make_field_step(field), _make_element_step(child_index)]))
        end
    end
    root_field = _get_children_field(root)
    for (index, child) in enumerate(get_workflow_node_children(root))
        visit(child, root, index, nothing, 0, 0, Any[_make_field_step(root_field), _make_element_step(index)])
    end
    rows
end

# ── The keys of a row ────────────────────────────────────────────────────

# The new sibling that Return at the end of the title of `node` adds.
_make_sibling(::WorkflowStep) = WorkflowStep()
_make_sibling(::WorkflowDecision) = WorkflowDecision(options = [WorkflowOption()])
_make_sibling(::WorkflowOption) = WorkflowOption()

# Whether the caret of `node` stands at the end of its title or its question.
function _is_caret_at_title_end(node)
    selection = get_selection(node)
    selection isa Reference || return false
    steps = collect(get_reference_steps(strip_reference_types(selection)))
    field = node isa WorkflowDecision ? "question" : "title"
    count = length(something(get_workflow_node_title(node).value, ""))
    length(steps) == 3 && steps[1] isa FieldReferenceStep && steps[1].name == field &&
        steps[3] isa RangeReferenceStep && steps[3].start == steps[3].stop == count
end

# The move of `node` from the children of `parent` at `index` into the children of
# `target` at `at`, with the caret where it was in the node.
function _make_move_node_operation(node, parent, index, target, at)
    caret = something(get_selection(node), EmptyReference())
    CompoundOperation(Any[make_delete_workflow_node_operation(parent, index),
                          make_insert_workflow_node_operation(target, at, node),
                          SelectDocumentOperation(node, copy_reference(strip_reference_types(caret)))])
end

# The keys of the row of a node, as the design of the outline gives them: Return at
# the end of the title adds a sibling after it, Alt+Up and Alt+Down move it among
# its siblings, Tab makes it the last child of the step or option before it, and
# Shift+Tab makes it the sibling after its parent.
function _make_workflow_row_keys(row)
    node, parent, index = row.node, row.parent, row.index
    siblings() = get_workflow_node_children(parent)
    add_sibling = (_, _) -> begin
        _is_caret_at_title_end(node) || return nothing
        sibling = _make_sibling(node)
        field = sibling isa WorkflowDecision ? "question" : "title"
        CompoundOperation(Any[make_insert_workflow_node_operation(parent, index + 1, sibling),
                              SelectDocumentOperation(sibling, Reference(FieldReferenceStep(field),
                                                                         FieldReferenceStep("value"),
                                                                         RangeReferenceStep(0, 0)))])
    end
    move_up = (_, _) -> index > 1 ? _make_move_node_operation(node, parent, index, parent, index - 1) : nothing
    move_down = (_, _) -> index < length(siblings()) ?
        _make_move_node_operation(node, parent, index, parent, index + 1) : nothing
    indent = (_, _) -> begin
        index > 1 || return nothing
        before = siblings()[index - 1]
        (node isa Union{WorkflowStep, WorkflowDecision} && before isa Union{WorkflowStep, WorkflowOption}) ||
            return nothing
        _make_move_node_operation(node, parent, index, before, length(before.children) + 1)
    end
    outdent = (_, _) -> begin
        grand = row.grand
        (node isa Union{WorkflowStep, WorkflowDecision} && grand isa Union{WorkflowStep, WorkflowOption}) ||
            return nothing
        _make_move_node_operation(node, parent, index, grand, row.parent_index + 1)
    end
    binding(pattern, make, description) = GestureBinding(pattern, make; description, domain = "workflow")
    GestureBinding[
        binding(KeyPressPattern('\n'; modifiers = Symbol[]), add_sibling, "Add a sibling after the node"),
        binding(KeyDownPattern(:up; modifiers = [:alt]), move_up, "Move the node up"),
        binding(KeyDownPattern(:down; modifiers = [:alt]), move_down, "Move the node down"),
        binding(KeyPressPattern('\t'; modifiers = Symbol[]), indent, "Indent the node"),
        binding(KeyPressPattern('\t'; modifiers = [:shift]), outdent, "Outdent the node"),
    ]
end

# The count of the entries of the journal of `node`, a chip that shows or hides
# them, and the time of the last entry; nothing for a node with no entry.
function _make_journal_facts(outline, node, shows_date::Bool)
    entries = length(node.journal)
    entries == 0 && return Any[]
    shown = node.journal_shown
    count = make_outline_chip(outline, string(entries), shown ? "Hide the journal" : "Show the journal",
                              () -> _make_show_journal_operation(node, !shown))
    Any[HorizontalLayout(Any[WidgetIcon(:message_square; size = outline.fold_size), count];
                         gap = outline.meta_gap, vertical_align = :center),
        make_outline_label(outline, _format_workflow_when(node.journal[entries].time, shows_date), :time_text)]
end

# The entries of the journal of `node` while it is shown, the oldest first, each
# through the view of an entry, and then the elements of `node`, each through the
# view of its own domain in a light inset with a menu of its own. Each goes into
# `rows` at the place that `next_place()` gives, with its slots; `prefix` is the
# path of `node` from the root.
function _push_journal_and_elements!(slots, embedded, outline, node, prefix, rows, next_place)
    if node.journal_shown
        for (entry_index, entry) in enumerate(node.journal)
            push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step("journal"), _make_element_step(entry_index)]),
                                     next_place()))
            push!(embedded, entry)
            push!(rows, entry)
        end
    end
    for (element_index, element) in enumerate(node.elements)
        block_place = next_place()
        element_path = vcat(prefix, Any[_make_field_step("elements"), _make_element_step(element_index)])
        push!(slots, OutlineSlot(element_path, vcat(block_place, get_outline_element_steps())))
        push!(slots, OutlineSlot(element_path, block_place; whole = true))
        element isa Document && push!(embedded, element)
        kind = string(nameof(typeof(element)))
        control = make_outline_control(outline, :ellipsis, "The menu of the element",
                                       () -> make_outline_menu_operation(kind,
                                                 () -> make_element_menu(node, element_index));
                                       size = :avatar_size)
        push!(rows, make_outline_element(outline; content = element, menu = control,
                                         revealed = Any[control]))
    end
    rows
end

# The row at `place` of a node of the outline, with its slots. `row` holds the
# node, its parent, its index in its parent, its depth and its path from the root.
function _make_workflow_row!(slots, embedded, outline, row, place, shows_date::Bool)
    node, parent, index, prefix = row.node, row.parent, row.index, row.prefix
    body_place = vcat(place, Any[_make_field_step("content")], _get_child_steps(2), Any[_make_field_step("child")])
    body_rows = Any[]
    next_body_place() = vcat(body_place, _get_child_steps(length(body_rows) + 1))
    name = _get_workflow_kind_name(node)
    compute_menu = () -> _make_workflow_menu(node, parent, index)

    # The fold and the mark.
    revealed = Any[]
    has_under = length(get_workflow_node_children(node)) > 0 || length(node.elements) > 0
    fold = if has_under || node.collapsed
        control = make_outline_control(outline, node.collapsed ? :chevron_right : :chevron_down,
                                       (node.collapsed ? "Unfold " : "Fold ") * name,
                                       () -> ReplaceViewStateOperation(ToggleCollapseOperation(node)))
        push!(revealed, control)
        control
    else
        make_outline_spacer(outline)
    end
    mark_name = node isa WorkflowStep ? "The state of " * name :
                node isa WorkflowOption ? "Choose " * name : "The menu of " * name
    mark = make_outline_mark(outline, _make_workflow_icon(node), mark_name,
                             () -> _make_mark_operation(node, parent, index))

    # The title, and what follows it on its line.
    line_place = next_body_place()
    title_field = node isa WorkflowDecision ? "question" : "title"
    settled = node isa Union{WorkflowStep, WorkflowOption} && node.state in (:done, :dropped, :rejected, :parked)
    title = _make_workflow_text!(slots, outline, get_workflow_node_title(node), prefix, title_field,
                                 vcat(line_place, _get_child_steps(1));
                                 role = settled ? :quiet_text : :text,
                                 placeholder = node isa WorkflowDecision ? "Question" : "Title")
    line = Any[title]
    if node isa WorkflowOption && !isempty(something(node.reason.value, ""))
        push!(line, _make_workflow_text!(slots, outline, node.reason, prefix, "reason",
                                         vcat(line_place, _get_child_steps(length(line) + 1));
                                         role = :word_text))
    end
    node isa WorkflowDecision &&
        push!(line, make_outline_label(outline, _is_decided(node) ? "decided" : "undecided", :relation_text))
    append!(line, _make_journal_facts(outline, node, shows_date))
    push!(body_rows, FlowLayout(line; horizontal_gap = outline.column_gap, vertical_align = :center))

    node.collapsed || _push_journal_and_elements!(slots, embedded, outline, node, prefix, body_rows,
                                                  next_body_place)

    menu = make_outline_control(outline, :ellipsis, "The menu of " * name,
                                () -> make_outline_menu_operation(_get_workflow_node_name(node), compute_menu);
                                size = :avatar_size)
    push!(revealed, menu)
    push!(slots, OutlineSlot(prefix, place; whole = true))
    make_outline_row(outline; facts = make_outline_facts(outline, [Any[fold, mark]]),
                     body = VerticalLayout(body_rows; child_width = Fill), menu, revealed,
                     title = name, compute_menu,
                     facts_width = outline.tree_meta_width, keys = _make_workflow_row_keys(row))
end

print_document(p::WorkflowNodeToWidget, recursion, node::Union{WorkflowStep, WorkflowDecision, WorkflowOption}, ctx) =
    _make_workflow_iomap(p, node, () -> _build_node_view(p, node))

function _build_node_view(p::WorkflowNodeToWidget, root)
    outline = unwrap_cell(p.outline)
    slots = Any[]
    embedded = Base.IdSet{Any}()
    rows = Any[]
    next_place() = _get_child_steps(length(rows) + 1)

    title_field = root isa WorkflowDecision ? "question" : "title"
    push!(rows, _make_workflow_text!(slots, outline, get_workflow_node_title(root), Any[], title_field,
                                     next_place(); role = :title_text, line = nothing,
                                     placeholder = root isa WorkflowDecision ? "Question" : "Goal"))
    # The counts of the states, and the menu of the root, which adds the steps of
    # the first level.
    header_menu = make_outline_control(outline, :ellipsis, "The menu of the workflow",
                                       () -> make_outline_menu_operation(_get_workflow_node_name(root),
                                                () -> _make_workflow_menu(root, nothing, nothing));
                                       size = :avatar_size)
    # A place of the header that no other slot holds is the root, so the menu of the
    # header belongs to the root.
    push!(slots, OutlineSlot(Any[], next_place(); whole = true))
    push!(rows, FlowLayout(Any[make_outline_label(outline, () -> _describe_workflow_progress(root), :relation_text),
                               _make_journal_facts(outline, root, true)..., header_menu];
                           horizontal_gap = outline.column_gap, vertical_align = :center))
    # The journal and the elements of the root stand under its header, as those of
    # a node stand under its row, because its menu adds both.
    _push_journal_and_elements!(slots, embedded, outline, root, Any[], rows, next_place)

    listed = _collect_workflow_rows(root)
    days = [length(row.node.journal) == 0 ? nothing : _get_workflow_day(row.node.journal[end].time)
            for row in listed]
    for (row, shows_date) in zip(listed, compute_shown_dates(days))
        place = vcat(next_place(), get_outline_guide_steps(row.depth))
        push!(rows, make_outline_guides(outline, _make_workflow_row!(slots, embedded, outline, row, place, shows_date),
                                        row.depth))
    end
    # A workflow with no step shows a quiet row, where the first key makes the
    # first step.
    if isempty(listed) && root isa WorkflowStep
        place = next_place()
        body_place = vcat(place, Any[_make_field_step("content")], _get_child_steps(2), Any[_make_field_step("child")])
        text = _make_workflow_text!(slots, outline, root.first_text, Any[], "first_text", body_place;
                                    role = :quiet_text, placeholder = "The first step")
        mark = WidgetIcon(_WORKFLOW_STATE_ICONS[:open]; size = outline.mark_size)
        push!(rows, make_outline_row(outline; facts = make_outline_facts(outline, [Any[make_outline_spacer(outline), mark]]),
                                     body = text, title = "The first step"))
    end

    output = VerticalLayout(rows; child_width = Fill)
    _route_workflow_paths!(p, root, slots, output, embedded)
    (; output, slots)
end

# ── The printer of an entry ──────────────────────────────────────────────

print_document(p::WorkflowEntryToWidget, recursion, entry::WorkflowEntry, ctx) =
    _make_workflow_iomap(p, entry, () -> _build_entry_view(p, entry))

function _build_entry_view(p::WorkflowEntryToWidget, entry::WorkflowEntry)
    outline = unwrap_cell(p.outline)
    avatar = entry.author === :assistant ?
        make_outline_avatar(outline, :sparkle; color = outline.assistant_color,
                            tooltip = TooltipNote(; title = "The assistant")) :
        make_outline_avatar(outline, :user; tooltip = TooltipNote(; title = "The person"))
    line = HorizontalLayout(Any[avatar,
                                make_outline_label(outline, _format_workflow_when(entry.time, true), :time_text),
                                make_outline_label(outline, string(entry.kind), :relation_text)];
                            gap = outline.meta_gap, vertical_align = :center)
    slots = Any[]
    embedded = Base.IdSet{Any}()
    text_place = Any[_make_field_step("children"), _make_element_step(1), _make_field_step("children"),
                     _make_element_step(2)]
    # A text is a field of prose; a document of another domain shows through the
    # view of its domain.
    text = if entry.text isa PrimitiveString
        _make_workflow_text!(slots, outline, entry.text, Any[], "text", text_place;
                             role = :field_text, line = :field_line, placeholder = "Text")
    else
        push!(slots, OutlineSlot(Any[_make_field_step("text")], text_place))
        entry.text isa Document && push!(embedded, entry.text)
        entry.text
    end
    column = VerticalLayout(Any[line, text]; child_width = Fill)
    output = VerticalLayout(Any[column]; child_width = Fill)
    _route_workflow_paths!(p, entry, slots, output, embedded)
    (; output, slots)
end

# The first key in the quiet row of a workflow with no step adds the first step,
# whose title is what the key typed, and the caret goes on after it.
function read_intent(p::WorkflowNodeToWidget, iomap::WorkflowToWidgetIoMap, operation::ReplaceStringRangeOperation)
    answer = invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation)
    root = iomap.input
    answer isa ReplaceStringRangeOperation && root isa WorkflowStep || return answer
    steps = collect(get_reference_steps(strip_reference_types(answer.reference)))
    (!isempty(steps) && first(steps) isa FieldReferenceStep && first(steps).name == "first_text") || return answer
    isempty(answer.replacement) && return nothing
    _make_add_and_type_operation(root, WorkflowStep(title = PrimitiveString(answer.replacement)))
end

# An Escape in the type-in of a new element of a node removes the element.
read_intent(p::WorkflowNodeToWidget, iomap::WorkflowToWidgetIoMap, operation::CompoundOperation) =
    make_element_cancel_operation(iomap.input, invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation))

# A document that is pasted while the caret is in the row of a node is an element
# of the node: the document itself after a note, or a copy.
make_pasted_document_operation(node::Union{WorkflowStep, WorkflowDecision, WorkflowOption}, path, value) =
    value isa Document ? make_add_element_operation(node, value) : nothing
