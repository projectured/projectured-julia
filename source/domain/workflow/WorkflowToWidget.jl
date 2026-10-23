# Fragment of `WorkflowModule` — the outline of a workflow as widgets: the goal,
# then a row of the outline kit for each node of the tree under it, indented by
# its depth.
#
# The output holds the documents of the input that are not prose — the content of
# a card, the text of an entry in another domain — and the renderer draws each of
# them through the view of its own domain. So text, Markdown, syntax and widgets
# mix in one outline, and an edit in any of them edits the document itself. The
# maps of this file translate a path between the input and the output by the
# places where those documents sit.

# ── The projections ──────────────────────────────────────────────────────

"""
    WorkflowNodeToWidget(; outline)

Draw a node and the tree under it as an outline: its title, the counts of the
states of its steps, then a row for each node under it, indented by its depth.

A row shows the fold and the mark of a node: the state of a step as a ring, a
decision as a diamond, the state of an option. After the title stand the reason
of an option, "decided" or "undecided" after a decision, the count of the entries
of the journal and the time of the last one. The menu of the row holds every
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
    WorkflowCardToWidget(; outline)

Draw a card of a node: its title and its content, through the view of the domain
of the content, in a light inset.
"""
@projection UntrackedCell struct WorkflowCardToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

"""
    make_workflow_projections(; theme = nothing, outline_theme = nothing) -> NamedTuple

The projections of a workflow, `node`, `entry` and `card` of the outline, with
the values of the `OutlineTheme` `outline_theme`, and `journal` of the table of
its entries and `catalog` of the workflows of a folder, with the styles of
`theme`, a `WorkflowTheme`. Each theme is scaled or not, or the default for
`nothing`. Each projection makes widgets; a renderer chains it with
`VerticalLayoutToGraphicsCanvas`, as `make_workflow_graphics_entries` does.
"""
function make_workflow_projections(; theme = nothing, outline_theme = nothing)
    get_style(name) = get_workflow_style(theme, name)
    outline = make_theme_values_field(OutlineTheme, outline_theme)
    node = WorkflowNodeToWidget(; outline)
    entry = WorkflowEntryToWidget(; outline)
    card = WorkflowCardToWidget(; outline)
    journal = WorkflowJournalToWidget(; muted_text = get_style(:muted_text),
                                      assistant_text = get_style(:assistant_text),
                                      person_text = get_style(:person_text), gap = get_style(:gap))
    catalog = WorkflowCatalogToWidget(; muted_text = get_style(:muted_text), gap = get_style(:gap))
    (; node, entry, card, journal, catalog)
end

"""
    make_workflow_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

The rows of the renderer for the documents of a workflow: each projection of the
outline, chained with `VerticalLayoutToGraphicsCanvas`, so the widgets that it
makes come back through the renderer. The styles are those of the `OutlineTheme`
and the `WorkflowTheme` of `appearance`.
"""
function make_workflow_graphics_entries(; measure, appearance)
    projections = make_workflow_projections(; theme = get_scaled_theme!(appearance, WorkflowTheme),
                                            outline_theme = get_scaled_theme!(appearance, OutlineTheme))
    node = ChainingProjection(projections.node, VerticalLayoutToGraphicsCanvas())
    Pair{Type,Any}[WorkflowStep => node, WorkflowDecision => node, WorkflowOption => node,
                   WorkflowEntry => ChainingProjection(projections.entry, VerticalLayoutToGraphicsCanvas()),
                   WorkflowCard => ChainingProjection(projections.card, VerticalLayoutToGraphicsCanvas()),
                   WorkflowJournal => ChainingProjection(projections.journal, VerticalLayoutToGraphicsCanvas()),
                   WorkflowCatalog => ChainingProjection(projections.catalog, VerticalLayoutToGraphicsCanvas())]
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

const _WorkflowProjection = Union{WorkflowNodeToWidget, WorkflowEntryToWidget, WorkflowCardToWidget}

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

# The items of the menu that add a child to `node`.
_make_add_items(node::Union{WorkflowStep, WorkflowOption}) = Any[
    WidgetMenuItem("Add a step"; operation = make_insert_workflow_node_operation(
        node, length(node.children) + 1, WorkflowStep())),
    WidgetMenuItem("Add a decision"; operation = make_insert_workflow_node_operation(
        node, length(node.children) + 1, WorkflowDecision(options = [WorkflowOption()]))),
]
_make_add_items(node::WorkflowDecision) = Any[
    WidgetMenuItem("Add an option"; operation = make_insert_workflow_node_operation(
        node, length(node.options) + 1, WorkflowOption())),
]

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
        WidgetMenuItem("Comment"; operation = make_add_workflow_entry_operation(node, make_workflow_entry(""))),
        WidgetMenuItem("Add a card"; operation = make_add_workflow_card_operation(
            node, WorkflowCard(content = PrimitiveString(""))))])
    parent === nothing && return _make_grouped_menu(Any[state, adds])
    view = Any[WidgetMenuItem(node.collapsed ? "Unfold" : "Fold"; operation = ReplaceViewStateOperation(ToggleCollapseOperation(node)))]
    delete = Any[WidgetMenuItem("Delete"; operation = make_delete_workflow_node_operation(parent, index))]
    _make_grouped_menu(Any[state, adds, view, delete])
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

# The counts of the states of the steps and of the decisions under `root`, as the
# header says them.
function _describe_workflow_progress(root)
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
    visit(node, parent, index, depth, prefix) = begin
        push!(rows, (; node, parent, index, depth, prefix))
        node.collapsed && return
        field = _get_children_field(node)
        for (child_index, child) in enumerate(get_workflow_node_children(node))
            visit(child, node, child_index, depth + 1,
                  vcat(prefix, Any[_make_field_step(field), _make_element_step(child_index)]))
        end
    end
    field = _get_children_field(root)
    for (index, child) in enumerate(get_workflow_node_children(root))
        visit(child, root, index, 0, Any[_make_field_step(field), _make_element_step(index)])
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
    has_under = length(get_workflow_node_children(node)) > 0 || length(node.cards) > 0
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
    entries = length(node.journal)
    if entries > 0
        push!(line, HorizontalLayout(Any[WidgetIcon(:message_square; size = outline.fold_size),
                                         make_outline_label(outline, string(entries), :relation_text)];
                                     gap = outline.meta_gap, vertical_align = :center))
        push!(line, make_outline_label(outline, _format_workflow_when(node.journal[entries].time, shows_date),
                                       :time_text))
    end
    push!(body_rows, FlowLayout(line; horizontal_gap = outline.column_gap, vertical_align = :center))

    # The cards, each through its own view.
    if !node.collapsed
        for (card_index, card) in enumerate(node.cards)
            push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step("cards"), _make_element_step(card_index)]),
                                     next_body_place()))
            push!(embedded, card)
            push!(body_rows, card)
        end
    end

    menu = make_outline_control(outline, :ellipsis, "The menu of " * name,
                                () -> make_outline_menu_operation(_get_workflow_node_name(node), compute_menu);
                                size = :avatar_size)
    push!(revealed, menu)
    push!(slots, OutlineSlot(prefix, place; whole = true))
    make_outline_row(outline; facts = make_outline_facts(outline, [Any[fold, mark]]),
                     body = VerticalLayout(body_rows; child_width = Fill), menu, revealed,
                     indent = row.depth * outline.indent, title = name, compute_menu,
                     facts_width = outline.tree_meta_width)
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
                               header_menu]; horizontal_gap = outline.column_gap, vertical_align = :center))

    listed = _collect_workflow_rows(root)
    days = [length(row.node.journal) == 0 ? nothing : _get_workflow_day(row.node.journal[end].time)
            for row in listed]
    for (row, shows_date) in zip(listed, compute_shown_dates(days))
        push!(rows, _make_workflow_row!(slots, embedded, outline, row, next_place(), shows_date))
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

# ── The printer of a card ────────────────────────────────────────────────

print_document(p::WorkflowCardToWidget, recursion, card::WorkflowCard, ctx) =
    _make_workflow_iomap(p, card, () -> _build_card_view(p, card))

function _build_card_view(p::WorkflowCardToWidget, card::WorkflowCard)
    outline = unwrap_cell(p.outline)
    slots = Any[]
    embedded = Base.IdSet{Any}()
    content_place = Any[_make_field_step("children"), _make_element_step(1), _make_field_step("content")]
    title = _make_workflow_text!(slots, outline, card.title, Any[], "title",
                                 vcat(content_place, _get_child_steps(1));
                                 role = :section_text, line = nothing, placeholder = "Title")
    rows = Any[title]
    if !card.collapsed && card.content !== nothing
        push!(slots, OutlineSlot(Any[_make_field_step("content")], vcat(content_place, _get_child_steps(2))))
        card.content isa Document && push!(embedded, card.content)
        push!(rows, card.content)
    end
    inset = WidgetCard(; variant = :muted, content = VerticalLayout(rows; child_width = Fill),
                       margin = inset_default, border = inset_default, padding = outline.inset_padding)
    output = VerticalLayout(Any[inset]; child_width = Fill)
    _route_workflow_paths!(p, card, slots, output, embedded)
    (; output, slots)
end
