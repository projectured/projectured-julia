# Fragment of `ExplorerModule` — the dashboard: a page of cards on which a person
# and an assistant put the documents that they want to see together.

"""
    DashboardCard(title, content)

One card of a [`Dashboard`](@ref): a title, and any document as its content, which
draws in the card by the view of its own type. The content is a document of its
own, or the same document as at another place, such as a chart that a page shows
too. `content_view` is the view document of the content
([`make_document_view`](@ref)), in a slot that a walk does not enter, or `nothing`
for a content that shows as itself. The card shows and holds the view, so the
card keeps its own place in a content that another place shows too. The dashboard
makes it when it is held, and a save writes none of it.

Use it to put a document on a dashboard.

# Example

    card_1 = DashboardCard("Runs", get_session_task_group_list())

See also `Dashboard`.

For the assistant.
"""
@document struct DashboardCard <: Document
    title::String
    content::Any
    content_view::Union{NavigatorViewSlot, Nothing} = nothing
end

# A card keeps the title and the content, and not the view that it shows.
get_view_state_fields(::Type{<:DashboardCard}) = (:content_view,)

get_document_title(card::DashboardCard) = card.title
format_tree_node_label(card::DashboardCard) = card.title
get_document_decoration(card::DashboardCard) =
    DocumentDecoration(; icon = :panel_top, tooltip = () -> _make_card_note(card))

# What a row of a card says when the pointer rests on it: the note of its
# content, under the title of the card.
function _make_card_note(card::DashboardCard)
    note = make_decoration_note(get_document_decoration(card.content))
    note isa Function && (note = note())
    note isa TooltipNote || return TooltipNote(; title = card.title, text = note)
    TooltipNote(; title = card.title, keys = note.keys, code = note.code, text = note.text, facts = note.facts,
                hint = note.hint, tone = note.tone)
end

"""
    Dashboard(title, cards = CellVector(Any[]))

A page of cards, each a [`DashboardCard`](@ref), in columns that follow the width
of the page: each card fills its cell, and its content gives its height. A person
adds a card with Insert or a paste on the page, and an assistant with an insert into `cards`,
which an undo takes back. The cards are the children of its node in an explorer.

Use it to keep the documents that a study needs on one page: a chart, a list of
runs, notes.

# Example

    dashboard_1 = Dashboard("Queue study", Any[DashboardCard("Tasks", get_session_task_group_list())])

See also `DashboardCard` and `find_explorer_content`.

For the assistant.
"""
@document struct Dashboard <: Document
    title::String
    cards::CellVector = CellVector(Any[])
end

get_document_title(dashboard::Dashboard) = dashboard.title
format_tree_node_label(dashboard::Dashboard) = dashboard.title
get_tree_children_steps(::Dashboard) = ((FieldReferenceStep("cards"),),)
get_document_decoration(dashboard::Dashboard) =
    DocumentDecoration(; icon = :layout_dashboard, counts = isempty(dashboard.cards) ? DocumentCount[] :
                                                            [DocumentCount(string(length(dashboard.cards)))],
                       tooltip = () -> TooltipNote(; title = dashboard.title,
                                                   facts = ["Cards" => string(length(dashboard.cards))]))

# A person adds a new empty dashboard by name, as an entry of an explorer or in a tab.
get_insertion_aliases(::Type{Dashboard}) = ["dashboard"]
make_insertion_document(::Type{Dashboard}) = Dashboard("New dashboard")
is_explorer_entry_type(::Type{Dashboard}) = true

# Insert on the page of a dashboard: a card at the end, whose content takes the
# name of a document. The key reaches the dashboard also from its row in an
# explorer, where no reader of its page answers, so the answer holds the view of
# the card itself.
@gestures Dashboard begin
    KeyDown(:insert) => "Add a card" =>
        _add_card_holds(doc, make_insert_elements_operation(
            extend_reference(EmptyReference(), FieldReferenceStep("cards")),
            length(doc.cards) + 1, Any[DashboardCard("New card", DocumentInsertion(""))]; root = doc))
end

# A document that is pasted while the dashboard is selected, as its row in an
# explorer is, or while the caret is on its page, such as in its title, is a new
# card at the end, with the title of the document. The answer holds the view of
# the card itself, as the answer to Insert does.
make_pasted_document_operation(dashboard::Dashboard, path, value) =
    value isa Document ?
        _add_card_holds(dashboard,
                        make_insert_elements_operation(extend_reference(EmptyReference(), FieldReferenceStep("cards")),
                                                       length(dashboard.cards) + 1,
                                                       Any[DashboardCard(format_tree_node_label(value), value)];
                                                       root = dashboard)) :
        nothing

# ── What a dashboard holds ───────────────────────────────────────────────────

# The view that `card` shows: the view in its slot while it shows the content of
# the card, and the content itself otherwise.
function _get_card_view(card::DashboardCard)
    slot = card.content_view
    slot === nothing && return card.content
    field = get_edited_field(slot.view)
    (field !== nothing && getproperty(slot.view, field) === card.content) ? slot.view : card.content
end

# The slot for the view of `content`, which follows the selection of the content,
# or `nothing` for a content that shows as itself.
function _make_card_view_slot(content)
    view = make_document_view(content)
    view === content ? nothing : NavigatorViewSlot(follow_content_selection!(view))
end

# A dashboard holds the view of the content of each of its cards, and the view
# holds the content, so a content starts what it needs, such as the read of a
# file, while the dashboard is shown. It makes the view of a card that has none of
# its content, and of a card whose view another holder holds, as the duplicate of
# a tab leaves. An edit of `cards` changes what it holds (`_add_card_holds`).
function acquire_document!(editor, dashboard::Dashboard)
    for card in dashboard.cards
        card isa DashboardCard || continue
        view = _get_card_view(card)
        (view === card.content || is_document_held(editor, view)) || continue
        slot = _make_card_view_slot(card.content)
        slot === nothing || set_cell_value!(getfield(card, :content_view), slot)
    end
    hold_documents!(editor, dashboard, _collect_held_cards(dashboard))
end

release_document!(editor, dashboard::Dashboard) =
    release_held_documents!(editor, dashboard, _collect_held_cards(dashboard))

# The views that `dashboard` holds: that of each card.
_collect_held_cards(dashboard::Dashboard) =
    Any[_get_card_view(card) for card in dashboard.cards if card isa DashboardCard]

# Whether `operation` changes what `dashboard` holds, as a member of a compound.
_has_card_hold(dashboard::Dashboard, operation::CompoundOperation) =
    any(member -> _has_card_hold(dashboard, member), operation.operations)
_has_card_hold(dashboard::Dashboard, operation::ChangeHeldDocumentsOperation) = operation.holder === dashboard
_has_card_hold(::Dashboard, ::Any) = false

# The edits of the cards of a dashboard that `operation` holds, each as `(dashboard,
# range, values)`: a write that replaces a range of `cards`, alone or among the
# members of a compound. A write that carries no root is rooted at `root`, the
# document that the reader answers for, so the dashboard is the part of `root` that
# its path names, and is `root` itself for a reader of the page of the dashboard.
function _collect_card_edits(root, operation)
    operation isa CompoundOperation && return Any[edit for member in operation.operations
                                                  for edit in _collect_card_edits(root, member)]
    operation isa ReplaceReferencedValueOperation || return Any[]
    steps = get_reference_steps(strip_reference_types(operation.reference))
    (length(steps) >= 2 && steps[end - 1] == FieldReferenceStep("cards") && steps[end] isa RangeReferenceStep) ||
        return Any[]
    dashboard = try_evaluate_reference(operation.document === nothing ? root : operation.document,
                                       extend_reference(EmptyReference(), steps[1:(end - 2)]...), nothing)
    dashboard isa Dashboard ? Any[(dashboard, steps[end], operation.value)] : Any[]
end

# `operation` with the change of what each dashboard holds that its edits of `cards`
# make: the views of the cards that leave are released, and the views of the cards
# that come are acquired, each with a view that its card keeps. The makes of the
# views are view state, which an undo does not record, and the change of the hold
# is recorded, so an undo of the edit gives back what the dashboard held. An
# operation that edits no card, and a dashboard whose hold the operation changes
# already, stay as they are.
function _add_card_holds(root, operation)
    holds = Any[]
    slots = Any[]
    for (dashboard, range, values) in _collect_card_edits(root, operation)
        _has_card_hold(dashboard, operation) && continue
        released = Any[_get_card_view(card) for card in dashboard.cards[(range.start + 1):range.stop]
                       if card isa DashboardCard]
        acquired = Any[]
        for card in values
            card isa DashboardCard || continue
            view = _get_card_view(card)
            if view === card.content
                slot = _make_card_view_slot(card.content)
                slot === nothing || (push!(slots, ReplaceReferencedValueOperation(card, "content_view", slot));
                                     view = slot.view)
            end
            push!(acquired, view)
        end
        push!(holds, ChangeHeldDocumentsOperation(dashboard, released, acquired))
    end
    isempty(holds) && return operation
    CompoundOperation(Any[operation,
                          (isempty(slots) ? () : (ReplaceViewStateOperation(CompoundOperation(slots)),))...,
                          holds...])
end
