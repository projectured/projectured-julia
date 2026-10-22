# Fragment of `ResearchModule` — the outline of a study as widgets: a card for each
# item, with the item's own documents inside it, and the sections of a study.
#
# The output holds the documents of the input — a statement, the design of an
# experiment, the content of a result, an item of a study — and the renderer draws
# each of them through the view of its own domain. So text, Markdown, syntax and
# widgets mix in one outline, and an edit in any of them edits the document
# itself. The maps of this file translate a path between the input and the output
# by the places where those documents sit.
#
# The card of an item needs no study, so an item draws the same in a Markdown page,
# a workflow card or a vertex of a graph. What needs the study — a decision on an
# item, a new item linked to it, the fold of its card — is in the row of the
# outline around the card.

# ── The projections ──────────────────────────────────────────────────────

"""
    ResearchItemToWidget(; styles…)

Draw an item of a study as a card.

The first row holds the id, the status as a badge, the statement (the title of
an experiment, an analysis or a result, the citation of a source), the author and
the local time. Under it stand the other texts of the item, a line for each link
with the id and the text of the linked item, and the prediction, the design, the
method or the content through the view of its own domain.
"""
@projection UntrackedCell struct ResearchItemToWidget <: Projection
    heading_text::StyleText = get_research_style(nothing, :heading_text)
    muted_text::StyleText = get_research_style(nothing, :muted_text)
    assistant_text::StyleText = get_research_style(nothing, :assistant_text)
    person_text::StyleText = get_research_style(nothing, :person_text)
    gap::Int = get_research_style(nothing, :gap)
end

"""
    ResearchStudyToWidget(; styles…)

Draw a study as its outline: the title, then a section for each kind of item in
the order of the work, each with a button that adds an item and the cards of its
items.

Beside each card stand the buttons that need the study: "Accept" and "Reject",
which record a decision of the person about the item, the buttons that add an item
linked to it, and a button that folds the card to its first line.
"""
@projection UntrackedCell struct ResearchStudyToWidget <: Projection
    heading_text::StyleText = get_research_style(nothing, :heading_text)
    muted_text::StyleText = get_research_style(nothing, :muted_text)
    gap::Int = get_research_style(nothing, :gap)
end

"""
    make_research_projections(; theme = nothing) -> NamedTuple

The projections of a study, `item` for the card of an item and `study` for the
outline, with the styles of `theme`: a `ResearchTheme`, scaled or not, or the
default styles for `nothing`. Each one makes widgets; a renderer chains it with
`VerticalLayoutToGraphicsCanvas`, as `make_research_graphics_entries` does.
"""
function make_research_projections(; theme = nothing)
    get_style(name) = get_research_style(theme, name)
    item = ResearchItemToWidget(; heading_text = get_style(:heading_text),
                                muted_text = get_style(:muted_text),
                                assistant_text = get_style(:assistant_text),
                                person_text = get_style(:person_text), gap = get_style(:gap))
    study = ResearchStudyToWidget(; heading_text = get_style(:heading_text),
                                  muted_text = get_style(:muted_text), gap = get_style(:gap))
    (; item, study)
end

"""
    make_research_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

The rows of the renderer for the documents of a study: the outline of a study and
the card of each kind of item, each chained with `VerticalLayoutToGraphicsCanvas`,
so the widgets that it makes come back through the renderer, and the map of a
study through `make_research_map_projection`. The styles are those of the
`ResearchTheme` of `appearance`.
"""
function make_research_graphics_entries(; measure, appearance)
    projections = make_research_projections(; theme = get_scaled_theme!(appearance, ResearchTheme))
    item = ChainingProjection(projections.item, VerticalLayoutToGraphicsCanvas())
    entries = Pair{Type,Any}[ResearchStudy => ChainingProjection(projections.study, VerticalLayoutToGraphicsCanvas())]
    for kind in RESEARCH_KINDS
        push!(entries, kind.type => item)
    end
    push!(entries, ResearchMap => make_research_map_projection(; measure,
                                      theme = get_scaled_theme!(appearance, ResearchTheme)))
    entries
end

# ── The IO map ───────────────────────────────────────────────────────────

# A place in the output that holds a document of the input. `input` is the path
# of that document from the input, `output` its path from the output. A slot of a
# collection has a `suffix`: the steps from the place of an element in the output
# to the element itself, inside the row that wraps it; a slot of a single
# document has none (`nothing`). `whole` holds the 1-based indices of the
# elements that the row shows as one line, such as a folded card: a place inside
# one of them is the element itself.
struct _ResearchSlot
    input::Vector{Any}
    output::Vector{Any}
    suffix::Union{Nothing, Vector{Any}}
    whole::Vector{Int}
end

_ResearchSlot(input, output, suffix) = _ResearchSlot(input, output, suffix, Int[])

_is_whole_element(slot, step) = step.stop in slot.whole

@iomap struct ResearchToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    slots::Any
end

_make_field_step(name::AbstractString) = FieldReferenceStep(String(name))
_make_field_step(name::Symbol) = FieldReferenceStep(String(name))
_make_element_step(index::Integer) = RangeReferenceStep(index - 1, index)
_make_reference(steps) = foldr((step, tail) -> ConcreteReference(step, tail), steps;
                               init = EmptyReference())

_is_same_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_is_same_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_is_same_step(::Any, ::Any) = false

_has_prefix(steps, prefix) =
    length(steps) >= length(prefix) && all(_is_same_step(steps[i], prefix[i]) for i in eachindex(prefix))

_is_element_step(step) = step isa RangeReferenceStep && step.stop == step.start + 1

# The steps of a child of a container in the output: its `children` field and its
# 1-based index.
_get_child_steps(index::Integer) = Any[_make_field_step("children"), _make_element_step(index)]

# The path in the output of the place that `reference`, a path in the input, names.
function _map_research_forward(slots, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    isempty(steps) && return EmptyReference()
    for slot in slots
        _has_prefix(steps, slot.input) || continue
        rest = steps[(length(slot.input) + 1):end]
        # An element of a list, or a place inside it, is the element in its row,
        # not the row with its buttons.
        if slot.suffix !== nothing && !isempty(rest) && _is_element_step(rest[1])
            _is_whole_element(slot, rest[1]) && return _make_reference(vcat(slot.output, Any[rest[1]]))
            return _make_reference(vcat(slot.output, Any[rest[1]], slot.suffix, rest[2:end]))
        end
        return _make_reference(vcat(slot.output, rest))
    end
    nothing
end

# The path in the input of the place that `reference`, a path in the output, names,
# or `nothing` for a part that the view drew.
function _map_research_backward(slots, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    for slot in slots
        _has_prefix(steps, slot.output) || continue
        rest = steps[(length(slot.output) + 1):end]
        if slot.suffix !== nothing && !isempty(rest) && _is_element_step(rest[1]) && length(rest) > 1
            _is_whole_element(slot, rest[1]) && return _make_reference(vcat(slot.input, Any[rest[1]]))
            inner = rest[2:end]
            # A press on the row of an element and not on the element itself, such
            # as a button beside it, is a part that the view drew.
            _has_prefix(inner, slot.suffix) || return nothing
            return _make_reference(vcat(slot.input, Any[rest[1]], inner[(length(slot.suffix) + 1):end]))
        end
        return _make_reference(vcat(slot.input, rest))
    end
    nothing
end

const _ResearchProjection = Union{ResearchItemToWidget, ResearchStudyToWidget}

function map_reference_forward(p::_ResearchProjection, iomap::ResearchToWidgetIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    _map_research_forward(iomap.slots, reference)
end

function map_reference_backward(p::_ResearchProjection, iomap::ResearchToWidgetIoMap, reference)
    reference isa Reference || return nothing
    found = _map_research_backward(iomap.slots, reference)
    found === nothing &&
        return invoke(map_reference_backward, Tuple{Projection, Any, Any}, p, iomap, reference)
    try
        annotate_reference_types(iomap.input, found)
    catch
        found
    end
end

# Each container that one build of a view made routes a key by its selection: it
# holds the part of the image of the selection of the input below its own place.
# The image comes from the slots of the same build, so a build needs no IO map.
function _route_research_paths!(p, input, slots, containers)
    image(path) = something(find_introduced_path(p, path), _map_research_forward(slots, path), Some(nothing))
    for (container, prefix) in containers
        set_output_path_computations!(container, input, path -> begin
            r = image(path)
            r === nothing && return nothing
            steps = collect(get_reference_steps(strip_reference_types(r)))
            isempty(prefix) && return r
            _has_prefix(steps, prefix) || return nothing
            _make_reference(steps[(length(prefix) + 1):end])
        end; dormant = false)
    end
    nothing
end

# The IO map of a view whose output and slots one computation builds: a change of
# what the build reads builds a new output, and the stage after this one prints it
# again.
function _make_research_iomap(p, input, build)
    built = Cell(@computation build())
    ResearchToWidgetIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

# ── Texts and buttons ────────────────────────────────────────────────────

# A field of the text of `text` that follows its value and says `placeholder` while
# it is empty. Its caret is a range of its `content`, which the slots of
# `_push_text_slots!` map to the same range of the value of `text`, so an edit in
# the field is an edit of `text`.
function _make_text_field(text::PrimitiveString, placeholder::AbstractString)
    # The field reads the value in its own cell, so a key that changes the text
    # draws the field again and does not build the card again.
    widget = WidgetText(""; placeholder, border = inset_default, margin = inset_default)
    set_cell_computation!(getfield(widget, :content), () -> something(text.value, ""))
    widget
end

# The slots of a text field at `place` that shows the field `field` of the input:
# a path into its value is a path into the content of the field, and the whole
# text is the whole field.
function _push_text_slots!(slots, field, place)
    push!(slots, _ResearchSlot(Any[_make_field_step(field), _make_field_step("value")],
                               vcat(place, Any[_make_field_step("content")]), nothing))
    push!(slots, _ResearchSlot(Any[_make_field_step(field)], place, nothing))
end

# The widget that shows the text field `field` of `item` at `place`, and its slots
# and its container: a field of prose for a `PrimitiveString`, and the document
# itself, drawn through the view of its domain, for any other document.
function _make_text_part!(slots, containers, item, field::Symbol, placeholder, place)
    text = getproperty(item, field)
    if text isa PrimitiveString
        widget = _make_text_field(text, placeholder)
        _push_text_slots!(slots, field, place)
        push!(containers, (widget, place))
        return widget
    end
    push!(slots, _ResearchSlot(Any[_make_field_step(field)], place, nothing))
    text
end

# A button whose press answers the operation that `make()` makes at the time of
# the press. `name` says what the press does: it is the title of the tooltip and
# the description of the gesture.
_make_research_button(text::AbstractString, name::AbstractString, make) =
    WidgetButton(text; tooltip = TooltipNote(; title = name),
                 gestures = GestureBinding[
                     GestureBinding(MouseClickPattern(:left), (_, _) -> make();
                                    description = name, domain = "research")])

# ── The card of an item ──────────────────────────────────────────────────

# The field that names an item in the first row of its card, and the word that
# its empty field shows.
_get_name_field(::Union{ResearchExperiment, ResearchAnalysis, ResearchResult}) = (:title, "Title")
_get_name_field(::ResearchSource) = (:citation, "Citation")
_get_name_field(::ResearchItem) = (:statement, "Statement")

# The other texts of an item, each with the word before it and the name that its
# empty field shows, in the order of the card.
const _RESEARCH_TEXT_ROWS = ((:criterion, "answered by", "Criterion"), (:purpose, "decides", "Purpose"),
                             (:summary, "says", "Summary"), (:reason, "because", "Reason"),
                             (:caveats, "but", "Caveats"))

# The document of an item that the card shows under its texts.
const _RESEARCH_CONTENT_FIELDS = (:prediction, :design, :method, :content)

# The word for a link, as the card says it before the linked item.
_get_link_word(::ResearchAnswer, ::Val{:question}) = "answers"
_get_link_word(::ResearchItem, ::Val{:question}) = "addresses"
_get_link_word(::ResearchItem, ::Val{:parent}) = "refines"
_get_link_word(::ResearchItem, ::Val{:origin}) = "from"
_get_link_word(::ResearchItem, ::Val{:basis}) = "rests on"
_get_link_word(::ResearchItem, ::Val{name}) where {name} = string(name)

"""
    describe_research_link(item, name, linked) -> String

The line that the card of `item` shows for its link `name` to `linked`: the word of
the link, the id of the linked item and its text, as in
`"supports H1 A queue capacity of 13 is enough."`.
"""
describe_research_link(item::ResearchItem, name::Symbol, linked) =
    _get_link_word(item, Val(name)) * " " *
    (linked isa ResearchItem ? linked.id * " " * _format_plain_text(get_research_item_text(linked)) :
                               string(nameof(typeof(linked))))

"""
    describe_research_expectation(expectation) -> String

The line that a card shows for an expectation: the bounds, and what the check
reads, as in `"expects a value ≤ 0.01 of drop rate at K = 13"`.
"""
function describe_research_expectation(expectation::ResearchExpectation)
    bounds = if expectation.reference !== nothing
        "within " * string(something(expectation.tolerance, 0)) * " of " *
            (expectation.reference isa FormulaFormula ? expectation.reference.name : "its reference")
    elseif expectation.lower !== nothing && expectation.upper !== nothing
        "in [" * string(expectation.lower) * ", " * string(expectation.upper) * "]"
    elseif expectation.upper !== nothing
        "≤ " * string(expectation.upper)
    elseif expectation.lower !== nothing
        "≥ " * string(expectation.lower)
    else
        "with no bound"
    end
    selection = expectation.result_selection
    what = selection === nothing ? "nothing yet" :
           selection isa Document ? _format_plain_text(selection) : string(selection)
    "expects a value " * bounds * " of " * (isempty(what) ? string(nameof(typeof(selection))) : what)
end

print_document(p::ResearchItemToWidget, recursion, item::ResearchItem, ctx) =
    _make_research_iomap(p, item, () -> _build_item_view(p, item))

function _build_item_view(p::ResearchItemToWidget, item::ResearchItem)
    slots = Any[]
    containers = Any[]
    card_place = _get_child_steps(1)
    content_place = vcat(card_place, Any[_make_field_step("content")])
    rows = Any[]
    # The place of the row that is pushed next.
    next_place() = vcat(content_place, _get_child_steps(length(rows) + 1))

    header_place = next_place()
    header_items = Any[WidgetLabel(item.id; text_style = p.heading_text)]
    if has_research_status(item)
        badge = WidgetBadge(() -> string(item.status); variant = :outline)
        set_cell_computation!(getfield(badge, :role), () -> _get_status_badge_role(item.status))
        push!(header_items, badge)
    end
    (name_field, placeholder) = _get_name_field(item)
    name_place = vcat(header_place, _get_child_steps(length(header_items) + 1))
    push!(header_items, _make_text_part!(slots, containers, item, name_field, placeholder, name_place))
    push!(header_items, WidgetLabel(string(item.author);
                                    text_style = item.author === :assistant ? p.assistant_text : p.person_text))
    push!(header_items, WidgetLabel(_format_local_time(item.time); text_style = p.muted_text))
    header = HorizontalLayout(header_items; gap = p.gap, vertical_align = :center)
    push!(containers, (header, header_place))
    push!(rows, header)

    for (field, word, placeholder) in _RESEARCH_TEXT_ROWS
        hasfield(typeof(item), field) || continue
        place = next_place()
        text_place = vcat(place, _get_child_steps(2))
        text = _make_text_part!(slots, containers, item, field, placeholder, text_place)
        row = HorizontalLayout(Any[WidgetLabel(word; text_style = p.muted_text), text];
                               gap = p.gap, vertical_align = :center)
        push!(containers, (row, place))
        push!(rows, row)
    end
    if item isa ResearchSource && !isempty(item.link)
        push!(rows, WidgetLabel("at " * item.link; text_style = p.muted_text))
    end

    links = collect_research_links(item)
    if !isempty(links)
        lines = Any[WidgetLabel(() -> describe_research_link(item, name, linked); text_style = p.muted_text)
                    for (name, linked) in links]
        push!(rows, VerticalLayout(lines; child_width = Fill))
    end

    for field in _RESEARCH_CONTENT_FIELDS
        hasfield(typeof(item), field) || continue
        value = getproperty(item, field)
        value === nothing && continue
        if value isa ResearchExpectation
            push!(rows, WidgetLabel(() -> describe_research_expectation(value); text_style = p.muted_text))
        elseif value isa Document
            push!(slots, _ResearchSlot(Any[_make_field_step(field)], next_place(), nothing))
            push!(rows, value)
        else
            push!(rows, WidgetLabel(string(value); text_style = p.muted_text))
        end
    end

    content = VerticalLayout(rows; gap = p.gap, child_width = Fill)
    push!(containers, (content, content_place))
    card = WidgetCard(; content)
    push!(containers, (card, card_place))
    output = VerticalLayout(Any[card]; child_width = Fill)
    push!(containers, (output, Any[]))
    _route_research_paths!(p, item, slots, containers)
    (; output, slots)
end

# ── The outline of a study ───────────────────────────────────────────────

"The title of the section of each kind of item in the outline of a study."
_get_section_title(kind) =
    kind.field === :analyses ? "Analyses" :
    kind.field === :evidence ? "Evidence" :
    kind.field === :hypotheses ? "Hypotheses" :
    uppercase(kind.name[1:1]) * kind.name[2:end] * "s"

# The operation of a press on an add button: a new item of `type` by the person,
# with an empty text and the links of `fields`, at the end of its list.
_make_add_operation(study, type, fields...) =
    make_add_research_item_operation(study, make_research_item(study, type; author = :person, fields...))

# The operation of a press on "Accept" or "Reject": a decision of the person that
# names the item.
function _make_decide_operation(study, item, status::Symbol)
    verb = status === :accepted ? "Accept " : "Reject "
    decision = make_research_item(study, ResearchDecision; author = :person,
                                  statement = verb * item.id,
                                  accepts = status === :accepted ? Any[item] : Any[],
                                  rejects = status === :rejected ? Any[item] : Any[])
    make_record_decision_operation(study, decision)
end

# The operation of a press on the fold of the card of `item`: a write of view
# state, which a history does not record.
function _make_fold_operation(study, item)
    folded = String[id for id in study.folded if id != item.id]
    item.id in study.folded || push!(folded, item.id)
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(study, "folded", folded))
end

# The buttons that add an item linked to `item`.
_make_linked_add_buttons(study, item::ResearchQuestion) = Any[
    _make_research_button("+ hypothesis", "Add a hypothesis for " * item.id,
        () -> _make_add_operation(study, ResearchHypothesis, :question => item)),
    _make_research_button("+ answer", "Add an answer to " * item.id,
        () -> _make_add_operation(study, ResearchAnswer, :question => item)),
]
_make_linked_add_buttons(study, item::ResearchHypothesis) = Any[
    _make_research_button("+ experiment", "Add an experiment that tests " * item.id,
        () -> _make_add_operation(study, ResearchExperiment, :tests => Any[item])),
    _make_research_button("+ evidence", "Add evidence that supports " * item.id,
        () -> _make_add_operation(study, ResearchEvidence, :supports => Any[item])),
]
_make_linked_add_buttons(study, item::Union{ResearchExperiment, ResearchAnalysis}) = Any[
    _make_research_button("+ result", "Add a result of " * item.id,
        () -> _make_add_operation(study, ResearchResult, :origin => item)),
]
_make_linked_add_buttons(study, item::Union{ResearchResult, ResearchSource}) = Any[
    _make_research_button("+ evidence", "Add evidence from " * item.id,
        () -> _make_add_operation(study, ResearchEvidence, :basis => Any[item])),
]
_make_linked_add_buttons(study, ::ResearchItem) = Any[]

# The row of the outline that holds the card of `item`: the fold, the card or its
# first line, and the buttons that need the study.
function _make_item_row(p::ResearchStudyToWidget, study, item, folded::Bool)
    fold = _make_research_button(folded ? "▸" : "▾", folded ? "Unfold" : "Fold",
                                 () -> _make_fold_operation(study, item))
    shown = folded ?
        WidgetLabel(() -> item.id * " " * _format_plain_text(get_research_item_text(item))) : item
    buttons = Any[]
    if has_research_status(item)
        push!(buttons, _make_research_button("Accept", "Accept " * item.id,
                                             () -> _make_decide_operation(study, item, :accepted)))
        push!(buttons, _make_research_button("Reject", "Reject " * item.id,
                                             () -> _make_decide_operation(study, item, :rejected)))
    end
    append!(buttons, _make_linked_add_buttons(study, item))
    HorizontalLayout(Any[fold, LayoutConstraint(shown; width = Fill),
                         VerticalLayout(buttons; gap = p.gap)];
                     gap = p.gap, vertical_align = :top)
end

print_document(p::ResearchStudyToWidget, recursion, study::ResearchStudy, ctx) =
    _make_research_iomap(p, study, () -> _build_study_view(p, study))

function _build_study_view(p::ResearchStudyToWidget, study::ResearchStudy)
    slots = Any[]
    containers = Any[]
    rows = Any[]
    next_place() = _get_child_steps(length(rows) + 1)

    title_place = next_place()
    push!(rows, _make_text_part!(slots, containers, study, :title, "Title of the study", title_place))

    folded = Set{String}(study.folded)
    for kind in RESEARCH_KINDS
        items = collect(getproperty(study, kind.field))
        add = _make_research_button("+ " * kind.name, "Add a " * kind.name,
                                    () -> _make_add_operation(study, kind.type))
        push!(rows, HorizontalLayout(Any[WidgetLabel(_get_section_title(kind); text_style = p.heading_text), add];
                                     gap = p.gap, vertical_align = :center))
        isempty(items) && continue
        place = next_place()
        item_rows = Any[_make_item_row(p, study, item, item.id in folded) for item in items]
        box = VerticalLayout(item_rows; gap = p.gap, child_width = Fill)
        # The card of an item is the second child of its row, inside a constraint.
        suffix = vcat(_get_child_steps(2), Any[_make_field_step("child")])
        whole = Int[index for (index, item) in enumerate(items) if item.id in folded]
        push!(slots, _ResearchSlot(Any[_make_field_step(kind.field)],
                                   vcat(place, Any[_make_field_step("children")]), suffix, whole))
        push!(containers, (box, place))
        for (index, row) in enumerate(item_rows)
            row_place = vcat(place, _get_child_steps(index))
            push!(containers, (row, row_place))
            push!(containers, (row.children[2], vcat(row_place, _get_child_steps(2))))
        end
        push!(rows, box)
    end

    output = VerticalLayout(rows; gap = p.gap, child_width = Fill)
    push!(containers, (output, Any[]))
    _route_research_paths!(p, study, slots, containers)
    (; output, slots)
end
