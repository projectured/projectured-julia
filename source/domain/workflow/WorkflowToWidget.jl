# Fragment of `WorkflowModule` — the outline of a workflow as widgets: a card for
# each node, with the node's own documents inside it.
#
# The output holds the documents of the input — a title, a reason, the text of
# an entry, the content of a card, a child node — and the renderer draws each of
# them through the view of its own domain. So text, Markdown, syntax and widgets
# mix in one outline, and an edit in any of them edits the document itself. The
# maps of this file translate a path between the input and the output by the
# places where those documents sit.

# ── The projections ──────────────────────────────────────────────────────

"""
    WorkflowNodeToWidget(; styles…)

Draw a step, a decision or an option as a card.

The header holds a button that folds the node, the state of a step or an option
as a badge with a button that steps it, the title or the question, and the time
of the last entry.
The body holds the reason of an option, the journal, the cards, the children and
a row of buttons that add a child, an entry and a card. A card and a child each
have a button that removes it. A press on the state button changes the state and
writes a `:state` entry, as `make_workflow_state_operation` does.
"""
@projection UntrackedCell struct WorkflowNodeToWidget <: Projection
    question_text::StyleText = get_workflow_style(nothing, :question_text)
    muted_text::StyleText = get_workflow_style(nothing, :muted_text)
    gap::Int = get_workflow_style(nothing, :gap)
end

"""
    WorkflowEntryToWidget(; styles…)

Draw an entry of a journal: a line with its time, its author and its kind, and
its text under that line, through the view of the domain of the text.
"""
@projection UntrackedCell struct WorkflowEntryToWidget <: Projection
    muted_text::StyleText = get_workflow_style(nothing, :muted_text)
    assistant_text::StyleText = get_workflow_style(nothing, :assistant_text)
    person_text::StyleText = get_workflow_style(nothing, :person_text)
    gap::Int = get_workflow_style(nothing, :gap)
end

"""
    WorkflowCardToWidget(; styles…)

Draw a card of a node: a card whose first row holds a button that folds it and
its title, and whose second row is its content, through the view of the domain of
the content.
"""
@projection UntrackedCell struct WorkflowCardToWidget <: Projection
    gap::Int = get_workflow_style(nothing, :gap)
end

"""
    make_workflow_projections(; theme = nothing) -> NamedTuple

The three projections of the outline, `node`, `entry` and `card`, with the styles
of `theme`: a `WorkflowTheme`, scaled or not, or the default styles for
`nothing`. Each one makes widgets; a renderer chains it with
`VerticalLayoutToGraphicsCanvas`, as `make_workflow_graphics_entries` does.
"""
function make_workflow_projections(; theme = nothing)
    get_style(name) = get_workflow_style(theme, name)
    node = WorkflowNodeToWidget(; question_text = get_style(:question_text),
                                muted_text = get_style(:muted_text), gap = get_style(:gap))
    entry = WorkflowEntryToWidget(; muted_text = get_style(:muted_text),
                                  assistant_text = get_style(:assistant_text),
                                  person_text = get_style(:person_text), gap = get_style(:gap))
    card = WorkflowCardToWidget(; gap = get_style(:gap))
    (; node, entry, card)
end

"""
    make_workflow_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

The rows of the renderer for the documents of a workflow: each projection of the
outline, chained with `VerticalLayoutToGraphicsCanvas`, so the widgets that it
makes come back through the renderer. The styles are those of the
`WorkflowTheme` of `appearance`.
"""
function make_workflow_graphics_entries(; measure, appearance)
    projections = make_workflow_projections(; theme = get_scaled_theme!(appearance, WorkflowTheme))
    node = ChainingProjection(projections.node, VerticalLayoutToGraphicsCanvas())
    Pair{Type,Any}[WorkflowStep => node, WorkflowDecision => node, WorkflowOption => node,
                   WorkflowEntry => ChainingProjection(projections.entry, VerticalLayoutToGraphicsCanvas()),
                   WorkflowCard => ChainingProjection(projections.card, VerticalLayoutToGraphicsCanvas())]
end

# ── The IO map ───────────────────────────────────────────────────────────

# A place in the output that holds a document of the input. `input` is the path
# of that document from the input, `output` its path from the output. A slot of a
# collection has a `suffix`: the steps from the place of an element in the output
# to the element itself, inside the row that wraps it; a slot of a single
# document has none (`nothing`).
struct _WorkflowSlot
    input::Vector{Any}
    output::Vector{Any}
    suffix::Union{Nothing, Vector{Any}}
end

@iomap struct WorkflowToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    slots::Any
end

_field(name::AbstractString) = FieldReferenceStep(String(name))
_element(index::Integer) = RangeReferenceStep(index - 1, index)
_make_reference(steps) = foldr((step, tail) -> ConcreteReference(step, tail), steps;
                               init = EmptyReference())

_is_same_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_is_same_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_is_same_step(::Any, ::Any) = false

_starts_with(steps, prefix) =
    length(steps) >= length(prefix) && all(_is_same_step(steps[i], prefix[i]) for i in eachindex(prefix))

_is_element_step(step) = step isa RangeReferenceStep && step.stop == step.start + 1

# The path in the output of the place that `reference`, a path in the input, names.
function _map_workflow_forward(slots, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    isempty(steps) && return EmptyReference()
    for slot in slots
        _starts_with(steps, slot.input) || continue
        rest = steps[(length(slot.input) + 1):end]
        if slot.suffix !== nothing && !isempty(rest) && _is_element_step(rest[1]) && length(rest) > 1
            return _make_reference(vcat(slot.output, Any[rest[1]], slot.suffix, rest[2:end]))
        end
        return _make_reference(vcat(slot.output, rest))
    end
    nothing
end

# The path in the input of the place that `reference`, a path in the output, names,
# or `nothing` for a part that the view drew.
function _map_workflow_backward(slots, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    for slot in slots
        _starts_with(steps, slot.output) || continue
        rest = steps[(length(slot.output) + 1):end]
        if slot.suffix !== nothing && !isempty(rest) && _is_element_step(rest[1]) && length(rest) > 1
            inner = rest[2:end]
            # A press on the row of an element and not on the element itself, such
            # as the button that removes it, is a part that the view drew.
            _starts_with(inner, slot.suffix) || return nothing
            return _make_reference(vcat(slot.input, Any[rest[1]], inner[(length(slot.suffix) + 1):end]))
        end
        return _make_reference(vcat(slot.input, rest))
    end
    nothing
end

const _WorkflowProjection = Union{WorkflowNodeToWidget, WorkflowEntryToWidget, WorkflowCardToWidget}

function map_reference_forward(p::_WorkflowProjection, iomap::WorkflowToWidgetIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    _map_workflow_forward(iomap.slots, reference)
end

function map_reference_backward(p::_WorkflowProjection, iomap::WorkflowToWidgetIoMap, reference)
    reference isa Reference || return nothing
    found = _map_workflow_backward(iomap.slots, reference)
    found === nothing &&
        return invoke(map_reference_backward, Tuple{Projection, Any, Any}, p, iomap, reference)
    typed = try
        annotate_reference_types(iomap.input, found)
    catch
        found
    end
    typed
end

# Each container that one build of a view made routes a key by its selection: it
# holds the part of the image of the selection of the input below its own place.
# The image comes from the slots of the same build, so a build needs no IO map.
function _route_workflow_paths!(p, input, slots, containers)
    image(path) = something(find_introduced_path(p, path), _map_workflow_forward(slots, path), Some(nothing))
    for (container, prefix) in containers
        set_output_path_computations!(container, input, path -> begin
            r = image(path)
            r === nothing && return nothing
            steps = collect(get_reference_steps(strip_reference_types(r)))
            isempty(prefix) && return r
            _starts_with(steps, prefix) || return nothing
            _make_reference(steps[(length(prefix) + 1):end])
        end; dormant = false)
    end
    nothing
end

# The IO map of a view whose output and slots one computation builds: a change of
# what the build reads builds a new output, and the stage after this one prints it
# again.
function _make_workflow_iomap(p, input, build)
    built = Cell(@computation build())
    WorkflowToWidgetIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

# ── Texts ────────────────────────────────────────────────────────────────

# A field of the text of `text` that follows its value and says `placeholder` while
# it is empty. Its caret is a range of its `content`, which the slots of
# `_push_text_slots!` map to the same range of the value of `text`, so an edit in
# the field is an edit of `text`.
function _make_title_text(text::PrimitiveString, placeholder::AbstractString)
    widget = WidgetText(text.value; placeholder, border = inset_default, margin = inset_default)
    set_cell_computation!(getfield(widget, :content), () -> text.value)
    widget
end

# The slots of a text field at `place` that shows the field `field` of the input:
# a path into its value is a path into the content of the field, and the whole
# text is the whole field.
function _push_text_slots!(slots, field::AbstractString, place)
    push!(slots, _WorkflowSlot(Any[_field(field), _field("value")], vcat(place, Any[_field("content")]), nothing))
    push!(slots, _WorkflowSlot(Any[_field(field)], place, nothing))
end

# ── Buttons ──────────────────────────────────────────────────────────────

# A button whose press answers the operation that `make()` makes at the time of
# the press.
_make_workflow_button(text::AbstractString, tooltip::AbstractString, make) =
    WidgetButton(text; tooltip,
                 gestures = GestureBinding[
                     GestureBinding(MouseClickPattern(:left), (_, _) -> make();
                                    description = tooltip, domain = "workflow")])

_make_fold_button(document) =
    _make_workflow_button(document.collapsed ? "▸" : "▾",
                          document.collapsed ? "Unfold" : "Fold",
                          () -> ToggleCollapseOperation(document))

# The state of `node` as a badge in the colour of its role, and the button that
# steps it.
function _make_state_items(node)
    badge = WidgetBadge(() -> string(node.state))
    set_cell_computation!(getfield(badge, :role), () -> _get_state_badge_role(node.state))
    step = _make_workflow_button("›", "Step the state",
        () -> make_workflow_state_operation(node, get_next_workflow_state(node)))
    Any[badge, step]
end

_get_add_buttons(node::Union{WorkflowStep, WorkflowOption}) = Any[
    _make_workflow_button("+ step", "Add a step",
        () -> make_insert_workflow_node_operation(node, length(node.children) + 1, WorkflowStep())),
    _make_workflow_button("+ decision", "Add a decision",
        () -> make_insert_workflow_node_operation(node, length(node.children) + 1,
                  WorkflowDecision(options = [WorkflowOption()]))),
]
_get_add_buttons(node::WorkflowDecision) = Any[
    _make_workflow_button("+ option", "Add an option",
        () -> make_insert_workflow_node_operation(node, length(node.options) + 1, WorkflowOption())),
]

function _make_body_buttons(node, gap::Integer)
    buttons = _get_add_buttons(node)
    push!(buttons, _make_workflow_button("+ comment", "Add a comment to the journal",
        () -> make_add_workflow_entry_operation(node, make_workflow_entry(""))))
    push!(buttons, _make_workflow_button("+ card", "Add a card",
        () -> make_add_workflow_card_operation(node, WorkflowCard(content = PrimitiveString("")))))
    HorizontalLayout(buttons; gap, vertical_align = :center)
end

# The text of the time of the last entry of `node`, as a person reads it.
function _format_last_entry_time(node)
    length(node.journal) == 0 && return ""
    time = find_workflow_time(node.journal[end])
    time === nothing ? "" : Dates.format(time, "yyyy-mm-dd HH:MM")
end

# ── The printer of a node ────────────────────────────────────────────────

print_document(p::WorkflowNodeToWidget, recursion, node::Union{WorkflowStep, WorkflowDecision, WorkflowOption}, ctx) =
    _make_workflow_iomap(p, node, () -> _build_node_view(p, node))

# The card of `node`: what the outline shows of it, and the slots of its documents.
# The header row is the first row of the content of the card, and not its title,
# because a card gives a key only to its content: a title in the header must take
# the keys of its text.
function _build_node_view(p::WorkflowNodeToWidget, node)
    slots = Any[]
    containers = Any[]
    card_place = Any[_field("children"), _element(1)]
    content_place = vcat(card_place, Any[_field("content")])
    rows = Any[]
    # The place of the row that is pushed next.
    next_place() = vcat(content_place, Any[_field("children"), _element(length(rows) + 1)])

    title = get_workflow_node_title(node)
    title_field = node isa WorkflowDecision ? "question" : "title"
    header_items = Any[_make_fold_button(node)]
    node isa WorkflowDecision || append!(header_items, _make_state_items(node))
    node isa WorkflowDecision && push!(header_items, WidgetLabel("?"; text_style = p.question_text))
    title_text = _make_title_text(title, node isa WorkflowDecision ? "Question" : "Title")
    push!(header_items, title_text)
    header_place = next_place()
    title_place = vcat(header_place, Any[_field("children"), _element(length(header_items))])
    _push_text_slots!(slots, title_field, title_place)
    push!(containers, (title_text, title_place))
    push!(header_items, WidgetLabel(() -> _format_last_entry_time(node); text_style = p.muted_text))
    header = HorizontalLayout(header_items; gap = p.gap, vertical_align = :center)
    push!(containers, (header, header_place))
    push!(rows, header)

    if !node.collapsed
        if node isa WorkflowOption
            place = next_place()
            reason_text = _make_title_text(node.reason, "Reason")
            reason = HorizontalLayout(Any[WidgetLabel("because"; text_style = p.muted_text), reason_text];
                                      gap = p.gap, vertical_align = :center)
            reason_place = vcat(place, Any[_field("children"), _element(2)])
            _push_text_slots!(slots, "reason", reason_place)
            push!(containers, (reason_text, reason_place))
            push!(containers, (reason, place))
            push!(rows, reason)
        end
        for (field, elements, removable) in (("journal", node.journal, false),
                                             ("cards", node.cards, true),
                                             (String(_get_children_field(node)),
                                              get_workflow_node_children(node), true))
            length(elements) == 0 && continue
            place = next_place()
            items = Any[removable ? _make_removable_row(node, field, element, p.gap) : element
                        for element in elements]
            box = VerticalLayout(items; gap = p.gap, child_width = Fill)
            suffix = removable ? Any[_field("children"), _element(1), _field("child")] : nothing
            push!(slots, _WorkflowSlot(Any[_field(field)], vcat(place, Any[_field("children")]), suffix))
            push!(containers, (box, place))
            if removable
                for (index, item) in enumerate(items)
                    item_place = vcat(place, Any[_field("children"), _element(index)])
                    push!(containers, (item, item_place))
                    push!(containers, (item.children[1], vcat(item_place, Any[_field("children"), _element(1)])))
                end
            end
            push!(rows, box)
        end
        push!(rows, _make_body_buttons(node, p.gap))
    end

    content = VerticalLayout(rows; gap = p.gap, child_width = Fill)
    push!(containers, (content, content_place))
    card = WidgetCard(; content)
    push!(containers, (card, card_place))
    output = VerticalLayout(Any[card]; child_width = Fill)
    push!(containers, (output, Any[]))
    _route_workflow_paths!(p, node, slots, containers)
    (; output, slots)
end

# An element of a collection of `node` with a button that removes it: the element
# fills the row, and the button sits at its end.
function _make_removable_row(node, field::AbstractString, element, gap::Integer)
    remove = _make_workflow_button("×", "Remove",
        field == "cards" ?
            () -> make_delete_workflow_card_operation(node, _find_index(node.cards, element)) :
            () -> make_delete_workflow_node_operation(node,
                      _find_index(get_workflow_node_children(node), element)))
    HorizontalLayout(Any[LayoutConstraint(element; width = Fill), remove];
                     gap, vertical_align = :top)
end

# The index of `element` in `elements` at the time of a press, so a button removes
# the element that it stands beside after other edits moved it.
_find_index(elements, element) = something(findfirst(x -> x === element, collect(elements)), 0)

# ── The printer of an entry ──────────────────────────────────────────────

print_document(p::WorkflowEntryToWidget, recursion, entry::WorkflowEntry, ctx) =
    _make_workflow_iomap(p, entry, () -> _build_entry_view(p, entry))

function _build_entry_view(p::WorkflowEntryToWidget, entry::WorkflowEntry)
    time = find_workflow_time(entry)
    line = HorizontalLayout(Any[
            WidgetLabel(time === nothing ? entry.time : Dates.format(time, "yyyy-mm-dd HH:MM");
                        text_style = p.muted_text),
            WidgetLabel(string(entry.author);
                        text_style = entry.author === :assistant ? p.assistant_text : p.person_text),
            WidgetLabel(string(entry.kind); text_style = p.muted_text)];
        gap = p.gap, vertical_align = :center)
    # A text is a field of prose; a document of another domain shows through the
    # view of its domain.
    text = entry.text isa PrimitiveString ? _make_title_text(entry.text, "Text") : entry.text
    column = VerticalLayout(Any[line, text]; child_width = Fill)
    output = VerticalLayout(Any[column]; child_width = Fill)
    text_place = Any[_field("children"), _element(1), _field("children"), _element(2)]
    slots = Any[]
    containers = Any[(output, Any[]), (column, Any[_field("children"), _element(1)])]
    if entry.text isa PrimitiveString
        _push_text_slots!(slots, "text", text_place)
        push!(containers, (text, text_place))
    else
        push!(slots, _WorkflowSlot(Any[_field("text")], text_place, nothing))
    end
    _route_workflow_paths!(p, entry, slots, containers)
    (; output, slots)
end

# ── The printer of a card ────────────────────────────────────────────────

print_document(p::WorkflowCardToWidget, recursion, card::WorkflowCard, ctx) =
    _make_workflow_iomap(p, card, () -> _build_card_view(p, card))

function _build_card_view(p::WorkflowCardToWidget, card::WorkflowCard)
    title_text = _make_title_text(card.title, "Title")
    header = HorizontalLayout(Any[_make_fold_button(card), title_text]; gap = p.gap, vertical_align = :center)
    rows = Any[header]
    card.collapsed || card.content === nothing || push!(rows, card.content)
    content = VerticalLayout(rows; gap = p.gap, child_width = Fill)
    widget = WidgetCard(; content)
    output = VerticalLayout(Any[widget]; child_width = Fill)
    content_place = Any[_field("children"), _element(1), _field("content")]
    header_place = vcat(content_place, Any[_field("children"), _element(1)])
    slots = Any[]
    _push_text_slots!(slots, "title", vcat(header_place, Any[_field("children"), _element(2)]))
    length(rows) == 2 &&
        push!(slots, _WorkflowSlot(Any[_field("content")], vcat(content_place, Any[_field("children"), _element(2)]), nothing))
    title_place = vcat(header_place, Any[_field("children"), _element(2)])
    _route_workflow_paths!(p, card, slots, Any[(output, Any[]), (widget, Any[_field("children"), _element(1)]),
                                               (content, content_place), (header, header_place),
                                               (title_text, title_place)])
    (; output, slots)
end
