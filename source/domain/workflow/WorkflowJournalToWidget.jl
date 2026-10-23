# Fragment of `WorkflowModule` — the journal of a workflow as a timeline: a group
# for each local day, the newest first, and a row of the outline kit for each entry
# of the tree, under a choice of the kind of entry.

"""
    WorkflowJournalToWidget(; outline)

Draw a [`WorkflowJournal`](@ref) as a timeline: a choice of the kind of entry that
it shows, then a group for each local day, the newest first, and a row for each
entry of the tree of its workflow: the author and the time of the entry beside its
text, and under the text the node that holds it and its kind. `outline` holds the
values of an `OutlineTheme`.

Read only: the timeline is the record of what happened, and an entry is edited in
the outline. A pick of a kind writes the `kind` of the journal.
"""
@projection UntrackedCell struct WorkflowJournalToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

# The choices of the kind of entry that the table shows, in the order of the choice.
const _JOURNAL_KINDS = (:all, :decision, :comment, :state, :link)

print_document(p::WorkflowJournalToWidget, recursion, journal::WorkflowJournal, ctx) =
    SimpleIoMap(p, journal, Cell(@computation _build_journal_view(p, journal)))

function _build_journal_view(p::WorkflowJournalToWidget, journal::WorkflowJournal)
    outline = unwrap_cell(p.outline)
    kind = journal.kind
    choice = WidgetToggleGroup(Any[string(k) for k in _JOURNAL_KINDS]; values = Any[_JOURNAL_KINDS...],
                               target = journal, field = "kind",
                               selected = something(findfirst(==(kind), _JOURNAL_KINDS), 1))
    workflow = journal.workflow
    entries = workflow === nothing ? Pair{Any, WorkflowEntry}[] :
              reverse(collect_workflow_entries(workflow; kind = kind === :all ? nothing : kind))
    rows = Any[choice]
    isempty(entries) && push!(rows, make_outline_label(outline, "No entry", :quiet_text))
    current = missing
    for (node, entry) in entries
        day = _get_workflow_day(entry.time)
        if !isequal(day, current)
            push!(rows, make_outline_section(outline, day === nothing ? "No date" : _format_workflow_day(entry.time)))
            current = day
        end
        push!(rows, _make_journal_row(outline, node, entry))
    end
    VerticalLayout(rows; child_width = Fill)
end

# The row of an entry: the author and the time, the text, and the node that holds
# the entry with the kind of the entry.
function _make_journal_row(outline, node, entry::WorkflowEntry)
    avatar = entry.author === :assistant ?
        make_outline_avatar(outline, :sparkle; color = outline.assistant_color,
                            tooltip = TooltipNote(; title = "The assistant")) :
        make_outline_avatar(outline, :user; tooltip = TooltipNote(; title = "The person"))
    clock = make_outline_label(outline, _format_workflow_when(entry.time, false), :time_text)
    text = make_outline_label(outline, _get_entry_text(entry), :text; line = :text_line)
    about = make_outline_label(outline, something(get_workflow_node_title(node).value, "") * " · " * string(entry.kind),
                               :relation_text)
    make_outline_row(outline; facts = make_outline_facts(outline, [Any[avatar, clock]]),
                     body = VerticalLayout(Any[text, about]; child_width = Fill))
end

map_reference_forward(p::WorkflowJournalToWidget, iomap, reference) = find_introduced_path(p, reference)
