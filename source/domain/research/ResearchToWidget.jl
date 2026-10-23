# Fragment of `ResearchModule` — the outline of a study as widgets: a row for each
# item, built of the parts of the outline kit, and the sections of a study.
#
# The output holds the documents of the input that are not prose — the design of
# an experiment, the content of a result — and the renderer draws each of them
# through the view of its own domain. So text, Markdown, syntax and widgets mix in
# one outline, and an edit in any of them edits the document itself. The maps of
# this file translate a path between the input and the output by the places where
# those documents sit.
#
# The row of an item needs no study, so an item draws the same in a Markdown page,
# a workflow element or a vertex of a graph. What needs the study — the fold of a
# row, the links into an item, the date of a row — is drawn only in the outline.

# ── The projections ──────────────────────────────────────────────────────

"""
    ResearchItemToWidget(; outline)

Draw an item of a study as one row of an outline.

The column of its facts holds its mark, the icon of its kind in the colour of its
status, its id, its author and its local time. Its text, the statement, the title
or the citation, stands beside them, and under it only the fields that hold a
value, each after the word of its meaning, the links of the item as chips, and
the prediction, the design, the method or the content through the view of its own
domain. `outline` holds the values of an `OutlineTheme`.
"""
@projection UntrackedCell struct ResearchItemToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

"""
    ResearchStudyToWidget(; outline)

Draw a study as its outline: the title, the counts of the statuses, then a section
for each kind of item that has items, in the order of the work, with a row for
each item.

A row shows its fold and its menu while the pointer is on it or the caret is in
it, the links into its item beside the links out of it, and its date where the
day differs from the day of the row above.
"""
@projection UntrackedCell struct ResearchStudyToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

"""
    make_research_projections(; theme = nothing) -> NamedTuple

The projections of a study, `item` for the row of an item and `study` for the
outline, with the values of the `OutlineTheme` `theme`, scaled or not, or of the
default theme for `nothing`. Each one makes widgets; a renderer chains it with
`VerticalLayoutToGraphicsCanvas`, as `make_research_graphics_entries` does.
"""
function make_research_projections(; theme = nothing)
    outline = make_theme_values_field(OutlineTheme, theme)
    (; item = ResearchItemToWidget(; outline), study = ResearchStudyToWidget(; outline))
end

"""
    make_research_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

The rows of the renderer for the documents of a study: the outline of a study and
the row of each kind of item, each chained with `VerticalLayoutToGraphicsCanvas`,
so the widgets that it makes come back through the renderer, and the map of a
study through `make_research_map_projection`. The styles are those of the
`OutlineTheme` and the `ResearchTheme` of `appearance`.
"""
function make_research_graphics_entries(; measure, appearance)
    projections = make_research_projections(; theme = get_scaled_theme!(appearance, OutlineTheme))
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

# The places of the documents of the input in the output are `OutlineSlot`s of
# the outline kit, which one build makes with its output.
@iomap struct ResearchToWidgetIoMap
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

const _ResearchProjection = Union{ResearchItemToWidget, ResearchStudyToWidget}

function map_reference_forward(p::_ResearchProjection, iomap::ResearchToWidgetIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    map_outline_forward(iomap.slots, reference)
end

function map_reference_backward(p::_ResearchProjection, iomap::ResearchToWidgetIoMap, reference)
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
_route_research_paths!(p, input, slots, output, embedded) =
    route_outline_paths!(input, output,
                         path -> something(find_introduced_path(p, path), map_outline_forward(slots, path),
                                           Some(nothing));
                         embedded)

# The IO map of a view whose output and slots one computation builds: a change of
# what the build reads builds a new output, and the stage after this one prints it
# again.
function _make_research_iomap(p, input, build)
    built = Cell(@computation build())
    ResearchToWidgetIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

# ── Texts ────────────────────────────────────────────────────────────────

# The slots of a text field at `place` that shows the field `field` of the item at
# `prefix`: a path into its value is a path into the content of the field, and the
# whole text is the whole field.
function _push_text_slots!(slots, prefix, field, place)
    push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field), _make_field_step("value")]),
                              vcat(place, Any[_make_field_step("content")])))
    push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field)]), place))
end

# The widget that shows the text field `field` of `document` at `place`, with its
# slots: a quiet field of prose for a `PrimitiveString`, and the document itself,
# drawn through the view of its domain, for any other document.
function _make_text_part!(slots, embedded, outline, document, prefix, field::Symbol, place;
                          role::Symbol = :text, line::Union{Nothing, Symbol} = :text_line,
                          placeholder = nothing)
    text = getproperty(document, field)
    if text isa PrimitiveString
        _push_text_slots!(slots, prefix, field, place)
        return make_outline_text(outline, () -> something(text.value, ""); role, line, placeholder)
    end
    push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field)]), place))
    text isa Document && push!(embedded, text)
    text
end

# Whether the text field `field` of `item` holds a value. The answer is a cell of
# its own, which stops at the same answer, so a key that adds a character to a
# value that has one builds no outline.
function _is_filled(item, field::Symbol)
    filled = Cell(@computation !isempty(_format_plain_text(getproperty(item, field))))
    filled[]
end

# ── Times ────────────────────────────────────────────────────────────────

# The local time of the moment that the text `text` names, or `nothing`.
function _find_research_local_time(text::AbstractString)
    time = find_research_time(text)
    time === nothing ? nothing : Libc.TmStruct(Dates.datetime2unix(time))
end

# The local time of an item to the minute, as "07:12".
function _format_research_clock(text::AbstractString)
    local_time = _find_research_local_time(text)
    local_time === nothing ? "" : Libc.strftime("%H:%M", local_time)
end

# The local day of an item, as a key that compares, or `nothing`.
function _get_research_day(text::AbstractString)
    local_time = _find_research_local_time(text)
    local_time === nothing ? nothing : Libc.strftime("%Y-%m-%d", local_time)
end

# The local day of an item as a person reads it, as "22 Oct".
function _format_research_day(text::AbstractString)
    local_time = _find_research_local_time(text)
    local_time === nothing ? "" : lstrip(Libc.strftime("%d %b", local_time), '0')
end

# ── The row of an item ───────────────────────────────────────────────────

# The field that names an item on the first line of its row, and the word that
# its empty field shows.
_get_name_field(::Union{ResearchExperiment, ResearchAnalysis, ResearchResult}) = (:title, "Title")
_get_name_field(::ResearchSource) = (:citation, "Citation")
_get_name_field(::ResearchItem) = (:statement, "Statement")

# The other texts of an item, each with the word before it and the name that its
# empty field shows, in the order of the row.
const _RESEARCH_TEXT_ROWS = ((:criterion, "answered by", "Criterion"), (:purpose, "decides", "Purpose"),
                             (:summary, "says", "Summary"), (:reason, "because", "Reason"),
                             (:caveats, "but", "Caveats"))

# The document of an item that the row shows under its texts.
const _RESEARCH_CONTENT_FIELDS = (:prediction, :design, :method, :content)

# The word for a link, as the row says it before the linked item.
_get_link_word(::ResearchAnswer, ::Val{:question}) = "answers"
_get_link_word(::ResearchItem, ::Val{:question}) = "addresses"
_get_link_word(::ResearchItem, ::Val{:parent}) = "refines"
_get_link_word(::ResearchItem, ::Val{:origin}) = "from"
_get_link_word(::ResearchItem, ::Val{:basis}) = "rests on"
_get_link_word(::ResearchItem, ::Val{name}) where {name} = string(name)

# The word for a link into an item, as the row of the linked item says it before
# the item that links to it.
_get_back_link_word(::ResearchAnswer, ::Val{:question}) = "answered in"
_get_back_link_word(::ResearchItem, ::Val{:question}) = "addressed by"
_get_back_link_word(::ResearchItem, ::Val{:parent}) = "refined by"
_get_back_link_word(::ResearchItem, ::Val{:origin}) = "gives"
_get_back_link_word(::ResearchItem, ::Val{:basis}) = "basis of"
_get_back_link_word(::ResearchItem, ::Val{:tests}) = "tested by"
_get_back_link_word(::ResearchItem, ::Val{:uses}) = "used by"
_get_back_link_word(::ResearchItem, ::Val{:supports}) = "supported by"
_get_back_link_word(::ResearchItem, ::Val{:opposes}) = "opposed by"
_get_back_link_word(::ResearchItem, ::Val{:accepts}) = "accepted by"
_get_back_link_word(::ResearchItem, ::Val{:rejects}) = "rejected by"
_get_back_link_word(::ResearchItem, ::Val{name}) where {name} = string(name) * " of"

"""
    describe_research_link(item, name, linked) -> String

The line that a reader of `item` says for its link `name` to `linked`: the word of
the link, the id of the linked item and its text, as in
`"supports H1 A queue capacity of 13 is enough."`.
"""
describe_research_link(item::ResearchItem, name::Symbol, linked) =
    _get_link_word(item, Val(name)) * " " *
    (linked isa ResearchItem ? linked.id * " " * _format_plain_text(get_research_item_text(linked)) :
                               string(nameof(typeof(linked))))

"""
    describe_research_expectation(expectation) -> String

The line that a row shows for an expectation: the bounds, and what the check
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

# The links of `item` as groups of a word and the linked documents, in the order of
# its fields, then the links into it from the other items of `study`, which the
# outline shows and the row of an item alone does not.
function _collect_relation_groups(item::ResearchItem, study)
    groups = Pair{String, Vector{Any}}[]
    add!(word, linked) = (index = findfirst(group -> group.first == word, groups);
                          index === nothing ? push!(groups, word => Any[linked]) : push!(groups[index].second, linked))
    for (name, linked) in collect_research_links(item)
        add!(_get_link_word(item, Val(name)), linked)
    end
    study === nothing && return groups
    for other in collect_study_items(study)
        other === item && continue
        for (name, linked) in collect_research_links(other)
            linked === item && add!(_get_back_link_word(other, Val(name)), other)
        end
    end
    groups
end

# The chip of a linked document: the id of an item, whose text the pointer shows,
# or the name of the type of any other document.
# The text of the tooltip is a live label, so an edit of the linked text draws
# the tooltip again and builds no outline.
_make_relation_chip(outline, linked::ResearchItem) =
    make_outline_chip(outline, linked.id, "Go to " * linked.id, () -> nothing;
                      tooltip = TooltipNote(; title = linked.id,
                                            text = WidgetLabel(() -> _format_plain_text(get_research_item_text(linked)))))
_make_relation_chip(outline, linked) =
    make_outline_label(outline, string(nameof(typeof(linked))), :relation_text)

# The mark of an item: the icon of its kind in the colour of its status, with a dot
# once a decision settled it.
function _make_research_icon(item::ResearchItem)
    icon = _RESEARCH_ICONS[get_research_kind(typeof(item)).field]
    has_research_status(item) || return WidgetIcon(icon)
    role = _get_status_badge_role(item.status)
    WidgetIcon(icon; role, bottom_right = item.status === :open ? nothing : WidgetIconMark(:dot; role))
end

# The author of an item as an avatar, and its local time.
function _make_research_when(outline, item::ResearchItem)
    avatar = item.author === :assistant ?
        make_outline_avatar(outline, :sparkle; color = outline.assistant_color,
                            tooltip = TooltipNote(; title = "The assistant")) :
        make_outline_avatar(outline, :user; tooltip = TooltipNote(; title = "The person"))
    Any[avatar, make_outline_label(outline, _format_research_clock(item.time), :time_text)]
end

# The row of `item`, at `place` in the output, with its slots: the column of its
# facts, its text and what stands under it, and its menu. `prefix` is the path of
# the item from the input. `study` is `nothing` for the row of an item alone, which
# has no fold, no menu, no links into it and no date. `shows_date` puts the local
# day of the item among its facts.
function _make_research_row!(slots, embedded, outline, item::ResearchItem, study, prefix, place;
                             folded::Bool = false, shows_date::Bool = false)
    body_place = vcat(place, Any[_make_field_step("content")], _get_child_steps(2), Any[_make_field_step("child")])
    body_rows = Any[]
    next_body_place() = vcat(body_place, _get_child_steps(length(body_rows) + 1))

    # What stands under the text: the fields that hold a value, the links and the
    # documents. A folded row shows none of them.
    fields = folded ? Any[] : Any[(field, word) for (field, word, _) in _RESEARCH_TEXT_ROWS
                                   if hasfield(typeof(item), field) && _is_filled(item, field)]
    groups = folded ? Pair{String, Vector{Any}}[] : _collect_relation_groups(item, study)
    contents = folded ? Any[] : Any[field for field in _RESEARCH_CONTENT_FIELDS
                                    if hasfield(typeof(item), field) && getproperty(item, field) !== nothing]
    has_link = !folded && item isa ResearchSource && !isempty(item.link)
    has_under = !isempty(fields) || !isempty(groups) || !isempty(contents) || has_link

    # The facts: the fold, the mark and the id on the first line; the author and
    # the time on the second, and the day on the third. A row of one line keeps
    # only the first, and its author, time and day follow its text.
    revealed = Any[]
    fold = if study === nothing
        nothing
    elseif has_under || folded
        control = make_outline_control(outline, folded ? :chevron_right : :chevron_down,
                                       (folded ? "Unfold " : "Fold ") * item.id,
                                       () -> _make_fold_operation(study, item))
        push!(revealed, control)
        control
    else
        make_outline_spacer(outline)
    end
    compute_menu = study === nothing ? nothing : () -> _make_research_menu(study, item, folded)
    open_menu = compute_menu === nothing ? (() -> nothing) : () -> make_outline_menu_operation(item.id, compute_menu)
    mark = make_outline_mark(outline, _make_research_icon(item), "The menu of " * item.id, open_menu)
    id = make_outline_label(outline, item.id, :id_text)
    first_line = Any[part for part in (fold, mark, id) if part !== nothing]
    when = _make_research_when(outline, item)
    day = shows_date ? Any[make_outline_label(outline, _format_research_day(item.time), :time_text)] : Any[]
    lines = has_under ? filter(!isempty, Any[first_line, when, day]) : Any[first_line]
    trailing = has_under ? nothing :
        HorizontalLayout(vcat(when, day); gap = outline.meta_gap, vertical_align = :center)

    # The text, with the author and the time after it when nothing stands under it.
    (name_field, placeholder) = _get_name_field(item)
    role = has_research_status(item) && item.status === :rejected ? :quiet_text : :text
    line_place = next_body_place()
    if trailing === nothing
        push!(body_rows, _make_text_part!(slots, embedded, outline, item, prefix, name_field, line_place;
                                          role, placeholder))
    else
        text = _make_text_part!(slots, embedded, outline, item, prefix, name_field,
                                vcat(line_place, _get_child_steps(1)); role, placeholder)
        push!(body_rows, FlowLayout(Any[text, trailing]; horizontal_gap = outline.column_gap,
                                    vertical_align = :center))
    end

    for (field, word) in fields
        value_place = vcat(next_body_place(), _get_child_steps(2), Any[_make_field_step("child")])
        value = _make_text_part!(slots, embedded, outline, item, prefix, field, value_place;
                                 role = :field_text, line = :field_line)
        push!(body_rows, make_outline_field(outline, word, value))
    end
    has_link && push!(body_rows, make_outline_field(outline, "at",
                                                    make_outline_label(outline, item.link, :field_text;
                                                                       line = :field_line)))
    if !isempty(groups)
        push!(body_rows, make_outline_relations(outline,
            [word => Any[_make_relation_chip(outline, linked) for linked in linked_items]
             for (word, linked_items) in groups]))
    end
    for field in contents
        value = getproperty(item, field)
        if value isa ResearchExpectation
            push!(body_rows, make_outline_field(outline, "predicts",
                make_outline_label(outline, () -> replace(describe_research_expectation(value), r"^expects " => ""),
                                   :field_text; line = :field_line)))
        elseif value isa Document
            push!(slots, OutlineSlot(vcat(prefix, Any[_make_field_step(field)]), next_body_place()))
            push!(embedded, value)
            push!(body_rows, value)
        else
            push!(body_rows, make_outline_label(outline, string(value), :field_text))
        end
    end

    menu = nothing
    if study !== nothing
        menu = make_outline_control(outline, :ellipsis, "The menu of " * item.id, open_menu;
                                    size = :avatar_size)
        push!(revealed, menu)
    end
    isempty(prefix) || push!(slots, OutlineSlot(prefix, place; whole = true))
    make_outline_row(outline; facts = make_outline_facts(outline, lines),
                     body = VerticalLayout(body_rows; child_width = Fill), menu, revealed,
                     title = item.id, compute_menu)
end

print_document(p::ResearchItemToWidget, recursion, item::ResearchItem, ctx) =
    _make_research_iomap(p, item, () -> _build_item_view(p, item))

function _build_item_view(p::ResearchItemToWidget, item::ResearchItem)
    outline = unwrap_cell(p.outline)
    slots = Any[]
    embedded = Base.IdSet{Any}()
    row = _make_research_row!(slots, embedded, outline, item, nothing, Any[], _get_child_steps(1))
    output = VerticalLayout(Any[row]; child_width = Fill)
    _route_research_paths!(p, item, slots, output, embedded)
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

# The operation of a press on the fold of the row of `item`: a write of view
# state, which a history does not record.
function _make_fold_operation(study, item)
    folded = String[id for id in study.folded if id != item.id]
    item.id in study.folded || push!(folded, item.id)
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(study, "folded", folded))
end

# The items of the menu that add an item linked to `item`, each with the operation
# that adds it, worded by the link.
_make_linked_add_items(study, item::ResearchQuestion) = Any[
    WidgetMenuItem("Add a hypothesis for " * item.id;
                   operation = _make_add_operation(study, ResearchHypothesis, :question => item)),
    WidgetMenuItem("Add an answer to " * item.id;
                   operation = _make_add_operation(study, ResearchAnswer, :question => item)),
]
_make_linked_add_items(study, item::ResearchHypothesis) = Any[
    WidgetMenuItem("Add an experiment that tests " * item.id;
                   operation = _make_add_operation(study, ResearchExperiment, :tests => Any[item])),
    WidgetMenuItem("Add evidence that supports " * item.id;
                   operation = _make_add_operation(study, ResearchEvidence, :supports => Any[item])),
]
_make_linked_add_items(study, item::Union{ResearchExperiment, ResearchAnalysis}) = Any[
    WidgetMenuItem("Add a result of " * item.id;
                   operation = _make_add_operation(study, ResearchResult, :origin => item)),
]
_make_linked_add_items(study, item::Union{ResearchResult, ResearchSource}) = Any[
    WidgetMenuItem("Add evidence from " * item.id;
                   operation = _make_add_operation(study, ResearchEvidence, :basis => Any[item])),
]
_make_linked_add_items(study, ::ResearchItem) = Any[]

# The menu of the row of `item`, in one order: what changes its status, what adds
# a linked item, what changes the view, and last the delete. The operations are
# made when the menu opens, so each names the study as it is then.
function _make_research_menu(study, item::ResearchItem, folded::Bool)
    groups = Any[]
    has_research_status(item) && push!(groups, Any[
        WidgetMenuItem("Accept " * item.id; operation = _make_decide_operation(study, item, :accepted),
                       enabled = item.status !== :accepted),
        WidgetMenuItem("Reject " * item.id; operation = _make_decide_operation(study, item, :rejected),
                       enabled = item.status !== :rejected)])
    adds = _make_linked_add_items(study, item)
    isempty(adds) || push!(groups, adds)
    push!(groups, Any[WidgetMenuItem(folded ? "Unfold" : "Fold"; operation = _make_fold_operation(study, item))])
    delete = try
        make_delete_research_item_operation(study, item)
    catch exception
        exception isa ArgumentError || rethrow()
        nothing
    end
    push!(groups, Any[WidgetMenuItem("Delete " * item.id; operation = delete, enabled = delete !== nothing)])
    elements = Any[]
    for group in groups
        isempty(elements) || push!(elements, WidgetSeparator())
        append!(elements, group)
    end
    WidgetMenu(elements)
end

# The counts of the statuses of the items of `study`, as the header says them.
function _describe_study_counts(study::ResearchStudy)
    items = collect_study_items(study)
    counts = Dict{Symbol, Int}()
    for item in items
        has_research_status(item) && (counts[item.status] = get(counts, item.status, 0) + 1)
    end
    parts = String[string(length(items), length(items) == 1 ? " item" : " items")]
    for status in RESEARCH_STATUSES
        count = get(counts, status, 0)
        count > 0 && push!(parts, string(count, " ", status))
    end
    join(parts, " · ")
end

print_document(p::ResearchStudyToWidget, recursion, study::ResearchStudy, ctx) =
    _make_research_iomap(p, study, () -> _build_study_view(p, study))

function _build_study_view(p::ResearchStudyToWidget, study::ResearchStudy)
    outline = unwrap_cell(p.outline)
    slots = Any[]
    embedded = Base.IdSet{Any}()
    rows = Any[]
    next_place() = _get_child_steps(length(rows) + 1)

    push!(rows, _make_text_part!(slots, embedded, outline, study, Any[], :title, next_place();
                                 role = :title_text, line = nothing, placeholder = "Title of the study"))
    push!(rows, make_outline_label(outline, () -> _describe_study_counts(study), :relation_text))

    folded = Set{String}(study.folded)
    listed = [(kind, index, item) for kind in RESEARCH_KINDS
              for (index, item) in enumerate(collect(getproperty(study, kind.field)))]
    shown_dates = compute_shown_dates([_get_research_day(item.time) for (_, _, item) in listed])
    current = nothing
    for ((kind, index, item), shows_date) in zip(listed, shown_dates)
        if kind !== current
            push!(rows, make_outline_section(outline, _get_section_title(kind)))
            current = kind
        end
        prefix = Any[_make_field_step(kind.field), _make_element_step(index)]
        push!(rows, _make_research_row!(slots, embedded, outline, item, study, prefix, next_place();
                                        folded = item.id in folded, shows_date))
    end

    output = VerticalLayout(rows; child_width = Fill)
    _route_research_paths!(p, study, slots, output, embedded)
    (; output, slots)
end
