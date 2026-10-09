# Fragment of `NaturalModule` — what the natural renderer draws of an
# arrangement: the chips of the bar above each arranged place, which a person
# takes away, and the menu of a value in an arranged document.

"""
    ArrangementChipsToGraphics()

Draws an `ArrangementChips` as a row of widgets: the count of the items, a chip
for each condition of a filter and each key of a sort, a text field for each
quick text condition (`is_quick_text_condition`) at the end, and Show all. A
press on the × of a chip answers the edit that takes its condition or its key
away, a press on Show all the edit that takes the entry away; each names its own
document, so a history records it as an edit of the person.

The text of a field is the value of its condition, at the path
`.entry.projections[i].conditions[k].value` of the chips, which the maps send to
the field and back. An edit of the field is a write of that value, which names
the condition, and the caret after it.
"""
struct ArrangementChipsToGraphics <: Projection end

@iomap struct ArrangementChipsToGraphicsIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    edits::Any          # the edit of each action of the row
    fields::Any         # the place `(i, k, condition)` of the condition of each field, by its index in the row
end

function print_document(p::ArrangementChipsToGraphics, recursion, chips::ArrangementChips, ctx)
    edits = IdDict{Any,Any}()
    fields = Dict{Int,Any}()
    arranged = get_property(ctx, :arrangement, nothing)
    arrangement = arranged === nothing ? nothing : arranged.arrangement
    row = Cell(@computation _make_chips_row(chips, edits, fields, arrangement))
    inner = make_reconciled_child_iomap_cell(() -> row[], widget -> print_child(recursion, widget, ctx))
    ArrangementChipsToGraphicsIoMap(p, chips, Cell(@computation inner[].output), inner, edits, fields)
end

# A key with a route goes to the field that the route names. The answer of the
# row becomes an answer of the chips: the edit of an action, the write of the
# value of a field, or a path of a field as a path in the chips.
function read_intent(p::ArrangementChipsToGraphics, recursion, change::Intent,
                     iomap::ArrangementChipsToGraphicsIoMap)
    inner = iomap.inner_iomap
    if change.route !== nothing
        route = _map_chips_to_row(iomap, change.route)
        route === nothing && return Intent(change.gesture, nothing)
        change = Intent(change.gesture, change.operation, change.description, change.domain, route)
    end
    answer = read_intent(get_iomap_projection(inner), recursion, change, inner)
    operation = answer isa Intent ? answer.operation : answer
    Intent(change.gesture, _read_chips_operation(iomap, operation))
end

read_intent(p::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

function _read_chips_operation(iomap::ArrangementChipsToGraphicsIoMap, operation)
    if operation isa InvokeActionOperation
        edit = get(iomap.edits, operation.action, nothing)
        return edit === nothing ? operation : edit
    end
    operation isa ReplaceStringRangeOperation && return _make_field_edit(iomap, operation)
    operation isa CompoundOperation &&
        return join_move_answers((_read_chips_operation(iomap, member) for member in operation.operations)...)
    if operation isa ReplacePathOperation
        path = _map_row_to_chips(iomap, get_operation_path(operation))
        return path === nothing ? nothing : make_path_operation(operation, path)
    end
    operation
end

# The write of the value of the condition of a field that an edit of the text of
# the field makes, and the caret after the text that it puts in.
function _make_field_edit(iomap::ArrangementChipsToGraphicsIoMap, operation::ReplaceStringRangeOperation)
    found = @reference_case strip_reference_types(operation.reference) begin
        children[f].content{a:b} => (f, a, b)
        __ => nothing
    end
    found === nothing && return nothing
    (f, a, b) = found
    place = get(iomap.fields, f, nothing)
    place === nothing && return nothing
    old = string(place.condition.value)
    new = string(first(old, a), operation.replacement, chop(old; head = b, tail = 0))
    caret = a + length(operation.replacement)
    CompoundOperation(Any[ReplaceReferencedValueOperation(place.condition, "value", new),
                          ReplaceSelectionOperation(_make_field_value_path(place, RangeReferenceStep(caret, caret)))])
end

# The path in the chips of the value of the condition of a field, then `rest`.
_make_field_value_path(place, rest...) =
    extend_reference(EmptyReference(), FieldReferenceStep("entry"), FieldReferenceStep("projections"),
                     ElementReferenceStep(place.i), FieldReferenceStep("conditions"), ElementReferenceStep(place.k),
                     FieldReferenceStep("value"), rest...)

# The path in the row of a path in the chips: the text of a field for the value
# of its condition, and `nothing` for any other path.
function _map_chips_to_row(iomap::ArrangementChipsToGraphicsIoMap, reference)
    reference isa Reference || return nothing
    inner = iomap.inner_iomap
    @reference_case strip_reference_types(reference) begin
        entry.projections[i].conditions[k].value.rest... => begin
            f = findfirst(place -> place.i == i && place.k == k, iomap.fields)
            f === nothing ? nothing :
                concat_references(extend_reference(EmptyReference(), FieldReferenceStep("children"),
                                                   ElementReferenceStep(f), FieldReferenceStep("content")), rest)
        end
        __ => nothing
    end
end

# The path in the chips of a path in the row: the value of the condition of a
# field for its text, and `nothing` for any other path.
function _map_row_to_chips(iomap::ArrangementChipsToGraphicsIoMap, reference)
    reference isa Reference || return nothing
    @reference_case strip_reference_types(reference) begin
        children[f].content.rest... => begin
            place = get(iomap.fields, f, nothing)
            place === nothing ? nothing : concat_references(_make_field_value_path(place), rest)
        end
        __ => nothing
    end
end

function map_reference_forward(::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, reference)
    path = _map_chips_to_row(iomap, reference)
    path === nothing && return nothing
    inner = iomap.inner_iomap
    map_reference_forward(get_iomap_projection(inner), inner, path)
end

function map_reference_backward(::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, reference)
    inner = iomap.inner_iomap
    path = map_reference_backward(get_iomap_projection(inner), inner, reference)
    path === nothing ? nothing : _map_row_to_chips(iomap, path)
end

# The row of `chips`: in `edits` the edit of each of its actions, and in `fields`
# the place of the condition of each text field. The fields come after the
# chips, so the quick text is at the end of the bar.
function _make_chips_row(chips::ArrangementChips, edits::IdDict, fields::Dict, arrangement)
    empty!(edits)
    empty!(fields)
    entry = chips.entry
    widgets = Any[WidgetLabel(string(chips.shown, " of ", chips.total))]
    quick = Any[]
    for (i, description) in enumerate(entry.projections)
        for (k, part) in enumerate(_get_chip_parts(description))
            removal = _make_chip_removal(arrangement, entry, i, description, k)
            if is_quick_text_condition(part)
                push!(quick, (i = i, k = k, condition = part, removal = removal))
                continue
            end
            action = Action(string(_describe_chip(part), " ×"))
            edits[action] = removal
            push!(widgets, WidgetButton(action))
        end
    end
    for place in quick
        push!(widgets, _make_quick_text_field(chips, place))
        fields[length(widgets)] = (i = place.i, k = place.k, condition = place.condition)
        action = Action("×")
        edits[action] = place.removal
        push!(widgets, WidgetButton(action))
    end
    show_all = Action("Show all")
    edits[show_all] = _make_entry_removal(arrangement, entry)
    push!(widgets, WidgetButton(show_all))
    row = HorizontalLayout(widgets; gap = 4, vertical_align = :center)
    # The row routes a key to the field that holds the caret.
    set_cell_computation!(getfield(row, :selection), () -> _find_row_caret(chips.selection, fields))
    row
end

# The selection of the row for the selection of the chips: the field whose
# condition holds the caret, then the caret in it; `nothing` when the caret is in
# no field.
function _find_row_caret(selection, fields::Dict)
    for (f, place) in fields
        caret = _find_field_caret(selection, place)
        caret === nothing && continue
        return ConcreteReference(FieldReferenceStep("children"), ConcreteReference(ElementReferenceStep(f), caret))
    end
    nothing
end

# The text field of a quick text condition: its text is the value of the
# condition, and its caret the selection of the chips in that value.
function _make_quick_text_field(chips::ArrangementChips, place)
    field = WidgetText(""; width = 16, placeholder = "Filter by text")
    set_cell_computation!(getfield(field, :content), () -> string(place.condition.value))
    set_cell_computation!(getfield(field, :selection), () -> _find_field_caret(chips.selection, place))
    field
end

# The caret of the field of the condition at `place` for the selection of the
# chips: `.content` and the rest of the selection below the value of the
# condition, or `nothing` when the selection is elsewhere.
function _find_field_caret(selection, place)
    selection isa Reference || return nothing
    @reference_case strip_reference_types(selection) begin
        entry.projections[i].conditions[k].value.rest... =>
            (i == place.i && k == place.k) ? ConcreteReference(FieldReferenceStep("content"), rest) : nothing
        __ => nothing
    end
end

_get_chip_parts(filter::ArrangementFilter) = Any[condition for condition in filter.conditions]
_get_chip_parts(sort::ArrangementSort) = Any[key for key in sort.keys]
_get_chip_parts(description) = Any[]

const _CHIP_OPERATORS = Dict(:equal => "=", :not_equal => "≠", :less => "<", :greater => ">",
                             :at_most => "≤", :at_least => "≥", :contains => "contains")

_describe_chip(condition::ArrangementCondition) =
    string(_describe_key(condition.key), " ", get(_CHIP_OPERATORS, condition.operator, string(condition.operator)),
           " ", condition.value isa AbstractString ? repr(condition.value) : string(condition.value))
_describe_chip(key::ArrangementSortKey) =
    string(key.direction === :descending ? "↓ " : "↑ ", _describe_key(key.key))

# The path of a key as a person reads it: the names of its fields and the
# numbers of its items, "value" for the item itself, or "any value" for the key
# of a quick text condition.
function _describe_key(key)
    key === nothing && return "any value"
    key isa EmptyReference && return "value"
    key isa Reference || return string(key)
    parts = String[]
    for step in get_reference_steps(strip_reference_types(key))
        if step isa FieldReferenceStep
            push!(parts, step.name)
        elseif step isa RangeReferenceStep
            push!(parts, string("[", step.start + 1, "]"))
        end
    end
    replace(join(parts, "."), ".[" => "[")
end

# The edit that takes part `k` of `description`, the `i`-th projection of
# `entry`, away: the part alone, or the projection when it is its last part,
# or the entry when that is its last projection.
function _make_chip_removal(arrangement, entry, i::Int, description, k::Int)
    parts = _get_chip_parts(description)
    if length(parts) > 1
        field = description isa ArrangementFilter ? "conditions" : "keys"
        return ReplaceReferencedValueOperation(description,
            extend_reference(EmptyReference(), FieldReferenceStep(field), RangeReferenceStep(k - 1, k)), Any[])
    end
    length(entry.projections) > 1 &&
        return ReplaceReferencedValueOperation(entry,
            extend_reference(EmptyReference(), FieldReferenceStep("projections"), RangeReferenceStep(i - 1, i)), Any[])
    _make_entry_removal(arrangement, entry)
end

# The edit that takes `entry` away from `arrangement`, which is `nothing` when the
# bar prints outside an arrangement.
_make_entry_removal(arrangement, entry) =
    arrangement === nothing ? nothing : make_entry_removal_edit(arrangement, entry)

# The menu of an arranged document on a right click: the edits of the value under
# the pointer, which filter or sort the collection that holds it.
get_document_gesture_bindings_own(::Type{<:ArrangementDocument}) =
    GestureBinding[make_context_menu_binding(_make_arrangement_menu; description = "Show the arrangement menu")]

function _make_arrangement_menu(arranged::ArrangementDocument)
    path = get_mouse_target(arranged)
    path isa Reference || return nothing
    rest = @reference_case strip_reference_types(path) begin
        document.rest... => rest
        __ => nothing
    end
    rest === nothing && return nothing
    item = find_arranged_item(arranged.document, rest)
    item === nothing && return nothing
    WidgetMenu(Any[WidgetMenuItem(label; operation) for (label, operation) in make_arrangement_edits(arranged, item)])
end
