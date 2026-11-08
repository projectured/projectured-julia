# Fragment of `TaskModule` — the cards that the pane of a group remembers. The
# pane of a group draws a different detail for each row, so the state of a card
# is not the card's own: it is a view field of the group, `collapsed_cards`,
# which maps the name of a card to whether it is collapsed. A page of a task
# type, drawn inside the detail, makes its cards with `make_collapsible_card`
# and so shares the field; a page in a navigator, which has no group around
# it, makes cards that keep their own state.

# What the pane gives to everything it prints: the group whose field holds the
# state, and the name of each card that a print made, so the reader of the pane
# can turn a press on the chevron of a card into a write of the field.
struct TaskCardScope
    document::TaskGroupDocument
    names::IdDict{Any,String}
end

const _CARD_SCOPE_PROPERTY = :task_card_scope

# The IO map of the pane of a group with the scope that its print gave, so the
# reader can turn the press on a chevron into a write. The output is the output of
# `inner_iomap`.
@iomap struct TaskCardScopeIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    scope::Any
end

# The pane of a group, printed with a `TaskCardScope` in its printer context. A
# press on the chevron of a card that the print made is answered as the write of
# the state of that card; every other answer, and every map, is that of `inner`.
struct TaskCardScopeProjection <: Projection
    inner::Any
end

function print_document(p::TaskCardScopeProjection, recursion, input::TaskGroupDocument, ctx)
    scope = TaskCardScope(input, IdDict{Any,String}())
    inner = print_document(p.inner, recursion, input, with_property(ctx, _CARD_SCOPE_PROPERTY, scope))
    TaskCardScopeIoMap(p, input, Cell(@computation inner.output), inner, scope)
end

function read_intent(p::TaskCardScopeProjection, recursion, change::Intent, iomap::TaskCardScopeIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    answer isa Intent || return answer
    operation = _translate_card_operation(iomap.scope, answer.operation)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end

read_intent(p::TaskCardScopeProjection, iomap::TaskCardScopeIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
map_reference_forward(p::TaskCardScopeProjection, iomap::TaskCardScopeIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)
map_reference_backward(p::TaskCardScopeProjection, iomap::TaskCardScopeIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

_find_card_scope(ctx) = ctx === nothing ? nothing : get_property(ctx, _CARD_SCOPE_PROPERTY, nothing)

"""
    make_collapsible_card(ctx; title, content, collapsed = false, name = nothing) -> WidgetCard

A card that a person can fold, which keeps its state when the pane around it
draws another row. In the pane of a group, `ctx` holds the group, and the card
is collapsed or open as the field `collapsed_cards` of the group says for its
name, or as `collapsed` says when the field holds no state for that name; a
press on its chevron writes the field. Without a group around it, as in a
navigator, the card keeps its own state.

The name of a card is `name`, or its `title` when that is a string. A card whose
title changes, such as one that counts lines, gives a `name` that does not. Two
cards of one pane with one name share their state.

Use it in a page of a task, so its cards fold and stay folded.

# Example

    make_collapsible_card(ctx; title = "Command", content = command, collapsed = true)

See also `TaskGroupDocument` and `WidgetCard`.
"""
function make_collapsible_card(ctx; title, content, collapsed::Bool = false, name = nothing)
    card = WidgetCard(; title, content, collapsible = true, collapsed)
    scope = _find_card_scope(ctx)
    key = name !== nothing ? String(name) : title isa AbstractString ? String(title) : nothing
    (scope === nothing || key === nothing) && return card
    set_cell_computation!(getfield(card, :collapsed),
                          () -> get(getfield(scope.document, :collapsed_cards)[], key, collapsed))
    scope.names[card] = key
    card
end

# The write of the field `collapsed_cards` that folds the card `key` of `document`
# when it is open, and opens it when it is folded. It is view state, so the undo
# does not record it.
function _make_card_fold_operation(document::TaskGroupDocument, key::String, collapsed::Bool)
    cards = copy(getfield(document, :collapsed_cards)[])
    cards[key] = !collapsed
    _make_view_write_operation(document, "collapsed_cards", cards)
end

# `operation`, with each press on the chevron of a card that the pane made
# answered as the write of the state of that card.
function _translate_card_operation(scope::TaskCardScope, operation::ToggleCollapseOperation)
    key = get(scope.names, operation.target, nothing)
    key === nothing && return operation
    card = operation.target
    _make_card_fold_operation(scope.document, key, getfield(card, :collapsed)[])
end
function _translate_card_operation(scope::TaskCardScope, operation::CompoundOperation)
    parts = Any[_translate_card_operation(scope, part) for part in operation.operations]
    all(k -> parts[k] === operation.operations[k], eachindex(parts)) ? operation : CompoundOperation(parts)
end
function _translate_card_operation(scope::TaskCardScope, operation::WrappingOperation)
    inner = get_wrapped_operation(operation)
    translated = _translate_card_operation(scope, inner)
    translated === inner ? operation : rewrap_operation(operation, translated)
end
_translate_card_operation(scope::TaskCardScope, operation) = operation
