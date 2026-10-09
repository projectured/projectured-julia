# Fragment of `WorkflowModule` — the journal of a workflow as a table: one row for
# each entry of the tree, the newest first, under a choice of the kind of entry.

"""
    WorkflowJournalToWidget(; styles…)

Draw a [`WorkflowJournal`](@ref): a choice of the kind of entry that the table
shows, and a table with one row for each entry of the tree of its workflow, the
newest first. A row says the time, the author, the kind, the node that holds the
entry and its text.

Read only: the table is the record of what happened, and an entry is edited in
the outline. A pick of a kind writes the `kind` of the journal.
"""
@projection UntrackedCell struct WorkflowJournalToWidget <: Projection
    muted_text::StyleText = get_workflow_style(nothing, :muted_text)
    assistant_text::StyleText = get_workflow_style(nothing, :assistant_text)
    person_text::StyleText = get_workflow_style(nothing, :person_text)
    gap::Int = get_workflow_style(nothing, :gap)
end

# The choices of the kind of entry that the table shows, in the order of the choice.
const _JOURNAL_KINDS = (:all, :decision, :comment, :state, :link)

print_document(p::WorkflowJournalToWidget, recursion, journal::WorkflowJournal, ctx) =
    SimpleIoMap(p, journal, Cell(@computation _build_journal_view(p, journal)))

function _build_journal_view(p::WorkflowJournalToWidget, journal::WorkflowJournal)
    kind = journal.kind
    choice = WidgetToggleGroup(Any[string(k) for k in _JOURNAL_KINDS]; values = Any[_JOURNAL_KINDS...],
                               target = journal, field = "kind",
                               selected = something(findfirst(==(kind), _JOURNAL_KINDS), 1))
    workflow = journal.workflow
    entries = workflow === nothing ? Pair{Any, WorkflowEntry}[] :
              reverse(collect_workflow_entries(workflow; kind = kind === :all ? nothing : kind))
    headers = Any[WidgetLabel(text) for text in ("time", "author", "kind", "node", "text")]
    rows = Any[_make_journal_row(p, node, entry) for (node, entry) in entries]
    isempty(rows) && push!(rows, Any[WidgetLabel(""), WidgetLabel(""), WidgetLabel(""), WidgetLabel(""),
                                    WidgetLabel("no entry"; text_style = p.muted_text)])
    table = WidgetTable(headers, rows)
    VerticalLayout(Any[choice, table]; gap = p.gap, child_width = Fill)
end

function _make_journal_row(p::WorkflowJournalToWidget, node, entry::WorkflowEntry)
    time = find_workflow_time(entry)
    Any[WidgetLabel(time === nothing ? entry.time : Dates.format(time, "yyyy-mm-dd HH:MM"); text_style = p.muted_text),
        WidgetLabel(string(entry.author); text_style = entry.author === :assistant ? p.assistant_text : p.person_text),
        WidgetLabel(string(entry.kind); text_style = p.muted_text),
        WidgetLabel(get_workflow_node_title(node).value),
        WidgetLabel(_get_entry_text(entry))]
end

map_reference_forward(p::WorkflowJournalToWidget, iomap, reference) = find_introduced_path(p, reference)
