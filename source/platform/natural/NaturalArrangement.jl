# Fragment of `NaturalModule` — what the natural renderer draws of an
# arrangement: a bar of chips above each arranged place, whose chips a person
# takes away.

"""
    ArrangementBarProjection(entry)

The stage of the chain of `entry` that shows its chips. It puts the items of the
place second in a `VerticalLayout`, under the `ArrangementChips` of `entry`, and
the printer of the place prints that layout, so the layout routes a press and
maps a path. A path of the items goes below `children[2]`
(`get_arranged_wrap_steps`).
"""
struct ArrangementBarProjection <: Projection
    entry::Any
end

@iomap struct ArrangementBarIoMap
    projection::Any
    input::Any
    output::Any
end

get_arranged_wrap_steps(::ArrangementBarProjection) = (FieldReferenceStep("children"), ElementReferenceStep(2))

function print_document(p::ArrangementBarProjection, recursion, input, ctx)
    total = get_property(ctx, :arranged_count, nothing)
    chips = ArrangementChips(p.entry, 0, 0)
    set_cell_computation!(getfield(chips, :shown), () -> length(input))
    set_cell_computation!(getfield(chips, :total), () -> total === nothing ? length(input) : total[])
    layout = VerticalLayout(Any[chips, input])
    # The selection and the part under the pointer of the items go below
    # `children[2]`, so a caret in an item draws.
    set_output_path_computations!(layout, input, path -> _map_bar_forward(path))
    ArrangementBarIoMap(p, input, layout)
end

_map_bar_forward(path) =
    path isa Reference ? ConcreteReference(FieldReferenceStep("children"), ConcreteReference(ElementReferenceStep(2), path)) :
                         nothing

map_reference_forward(::ArrangementBarProjection, iomap::ArrangementBarIoMap, reference) =
    _map_bar_forward(reference)

function map_reference_backward(::ArrangementBarProjection, iomap::ArrangementBarIoMap, reference)
    @reference_case reference begin
        children[2].rest... => rest
        __ => nothing
    end
end

"""
    ArrangementChipsToGraphics()

Draws an `ArrangementChips` as a row of widgets: the count of the items, a chip
for each condition of a filter and each key of a sort, and Show all. A press on
the × of a chip answers the edit that takes its condition or its key away, a
press on Show all the edit that takes the entry away; each names its own
document, so a history records it as an edit of the person.
"""
struct ArrangementChipsToGraphics <: Projection end

@iomap struct ArrangementChipsToGraphicsIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    edits::Any          # the edit of each action of the row
end

function print_document(p::ArrangementChipsToGraphics, recursion, chips::ArrangementChips, ctx)
    edits = IdDict{Any,Any}()
    arranged = get_property(ctx, :arrangement, nothing)
    arrangement = arranged === nothing ? nothing : arranged.arrangement
    row = Cell(@computation _make_chips_row(chips, edits, arrangement))
    inner = make_reconciled_child_iomap_cell(() -> row[], widget -> print_child(recursion, widget, ctx))
    ArrangementChipsToGraphicsIoMap(p, chips, Cell(@computation inner[].output), inner, edits)
end

function read_intent(p::ArrangementChipsToGraphics, recursion, change::Intent,
                     iomap::ArrangementChipsToGraphicsIoMap)
    inner = iomap.inner_iomap
    answer = read_intent(get_iomap_projection(inner), recursion, change, inner)
    operation = answer isa Intent ? answer.operation : answer
    operation isa InvokeActionOperation || return Intent(change.gesture, operation)
    edit = get(iomap.edits, operation.action, nothing)
    Intent(change.gesture, edit === nothing ? operation : edit)
end

read_intent(p::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, reference) = nothing
map_reference_backward(::ArrangementChipsToGraphics, iomap::ArrangementChipsToGraphicsIoMap, reference) = nothing

# The row of `chips`, and in `edits` the edit of each of its actions.
function _make_chips_row(chips::ArrangementChips, edits::IdDict, arrangement)
    empty!(edits)
    entry = chips.entry
    widgets = Any[WidgetLabel(string(chips.shown, " of ", chips.total))]
    for (i, description) in enumerate(entry.projections)
        for (k, part) in enumerate(_get_chip_parts(description))
            action = Action(string(_describe_chip(part), " ×"))
            edits[action] = _make_chip_removal(arrangement, entry, i, description, k)
            push!(widgets, WidgetButton(action))
        end
    end
    show_all = Action("Show all")
    edits[show_all] = _make_entry_removal(arrangement, entry)
    push!(widgets, WidgetButton(show_all))
    HorizontalLayout(widgets; gap = 4, vertical_align = :center)
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
# numbers of its items, or "value" for the item itself.
function _describe_key(key)
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
