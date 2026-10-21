# Fragment of `ExplorerModule` — the dashboard: a page of cards on which a person
# and an assistant put the documents that they want to see together.

"""
    DashboardCard(title, content)

One card of a [`Dashboard`](@ref): a title, and any document as its content, which
draws in the card by the view of its own type. The content is a document of its
own, or the same document as at another place, such as a chart that a page shows
too.

Use it to put a document on a dashboard.

# Example

    card_1 = DashboardCard("Runs", get_session_task_group_list())

See also `Dashboard`.
"""
@document struct DashboardCard <: Document
    title::String
    content::Any
end

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
adds a card with Insert on the page, and an assistant with an insert into `cards`,
which an undo takes back. The cards are the children of its node in an explorer.

Use it to keep the documents that a study needs on one page: a chart, a list of
runs, notes.

# Example

    dashboard_1 = Dashboard("Queue study", Any[DashboardCard("Tasks", get_session_task_group_list())])

See also `DashboardCard` and `Explorer`.
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
# name of a document.
@gestures Dashboard begin
    KeyDown(:insert) => "Add a card" =>
        make_insert_elements_operation(extend_reference(EmptyReference(), FieldReferenceStep("cards")),
                                       length(doc.cards) + 1, Any[DashboardCard("New card", DocumentInsertion(""))];
                                       root = doc)
end
