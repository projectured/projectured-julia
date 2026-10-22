# ── Atomic workflow documents — one meaningful instance each, for the catalog. ──

make_workflow_entry_document_example() =
    WorkflowEntry(time = "2026-10-09T13:40:00", author = :person, kind = :comment,
                  text = PrimitiveString("Keep the records readable in a text editor."))

make_workflow_element_document_example() =
    PrimitiveString("A node holds a document of any domain as an element.")

make_workflow_step_document_example() =
    WorkflowStep(title = PrimitiveString("Survey the literature"), state = :done,
                 journal = [make_workflow_entry_document_example()])

make_workflow_decision_document_example() =
    WorkflowDecision(
        question = PrimitiveString("How to store a workflow"),
        options = [
            WorkflowOption(title = PrimitiveString(".pdoc binary"), state = :rejected,
                           reason = PrimitiveString("Not diffable, and it breaks across Julia versions.")),
            WorkflowOption(title = PrimitiveString(".pred with markers"), state = :chosen,
                           reason = PrimitiveString("Text, and a reference into another file is durable.")),
            WorkflowOption(title = PrimitiveString("JSON"), state = :parked),
        ],
        journal = [WorkflowEntry(time = "2026-10-09T14:02:00", author = :assistant, kind = :decision,
                                 text = PrimitiveString("Store a workflow as .pred with markers."))])

# ── A whole workflow ───────────────────────────────────────────────────────

"""
    make_workflow_document_example() -> WorkflowStep

A workflow of three steps and a decision: the goal, one step done, a decision
with a chosen, a rejected and a parked option, a step that is active and a step
that is open. Entries by the person and by the assistant, and an element.
"""
make_workflow_document_example() =
    WorkflowStep(
        title = PrimitiveString("Workflow domain"),
        state = :active,
        children = [
            make_workflow_step_document_example(),
            make_workflow_decision_document_example(),
            WorkflowStep(title = PrimitiveString("Outline view"), state = :active,
                         elements = Any[make_workflow_element_document_example()]),
            WorkflowStep(title = PrimitiveString("Assistant tools")),
        ],
        journal = [WorkflowEntry(time = "2026-10-09T13:00:00", author = :person, kind = :state,
                                 text = PrimitiveString("active"))])

"""
    make_workflow_projection_example(; measure = FontFileMeasure()) -> Projection

The renderer that draws any document, which draws a workflow as its outline: the
rows that the workflow domain registers.
"""
make_workflow_projection_example(; measure = FontFileMeasure()) = NaturalToGraphics(; measure)

"""
    make_workflow_journal_document_example() -> WorkflowJournal

The journal of the workflow of `make_workflow_document_example`: every entry of
its tree as a table.
"""
make_workflow_journal_document_example() = WorkflowJournal(workflow = make_workflow_document_example())

# ── One workflow in stages ─────────────────────────────────────────────────
#
# One piece of work, "Ship the CSV importer", from its first line to a full record.
# Each stage adds one feature of the domain to the stage before it, so the
# examples read as a tour: a goal, steps, sub-steps, a decision, the branches that
# were tried, the journal, and the elements.

# The stages, in the order in which each one adds to the stage before it.
const _CSV_WORKFLOW_STAGES = (:goal, :steps, :substeps, :decision, :explored, :journal, :elements)

_make_csv_step(title; state = :open, children = Any[], journal = Any[], elements = Any[],
               journal_shown = false) =
    WorkflowStep(title = PrimitiveString(title), state = state, children = children,
                 journal = journal, elements = elements, journal_shown = journal_shown)

_make_csv_entry(time, author, kind, text) =
    WorkflowEntry(time = time, author = author, kind = kind, text = PrimitiveString(text))

_make_csv_option(title, state, reason; children = Any[]) =
    WorkflowOption(title = PrimitiveString(title), state = state, reason = PrimitiveString(reason),
                   children = children)

# The table of the sample files, an element of the step that collects them.
_make_csv_sample_table() =
    WidgetTable(Any[WidgetLabel("file"), WidgetLabel("rows"), WidgetLabel("separator")],
                Any[Any[WidgetLabel("orders.csv"), WidgetLabel("12 400"), WidgetLabel("comma")],
                    Any[WidgetLabel("stock.csv"), WidgetLabel("830"), WidgetLabel("semicolon")],
                    Any[WidgetLabel("prices.csv"), WidgetLabel("2 150"), WidgetLabel("semicolon")]])

# The workflow "Ship the CSV importer" as it is at `stage`, one of
# `_CSV_WORKFLOW_STAGES`.
function _make_csv_workflow(stage::Symbol)
    level = something(findfirst(==(stage), _CSV_WORKFLOW_STAGES), 0)
    level > 0 || throw(ArgumentError("No stage :" * string(stage) * "."))
    has(feature) = level >= findfirst(==(feature), _CSV_WORKFLOW_STAGES)
    has(:steps) || return _make_csv_step("Ship the CSV importer")
    journal(entries...) = has(:journal) ? Any[entries...] : Any[]
    elements(made...) = has(:elements) ? Any[made...] : Any[]
    # The stage of the journal shows the entries under each node that has some;
    # the later stages keep the journal folded, as a new outline shows it.
    shown = stage === :journal

    # The decision of the parser: open from :decision, settled from :explored. A
    # settled decision keeps the branch that was tried and rejected, and the
    # option that waits.
    parser = Any[]
    if has(:decision)
        settled = has(:explored)
        options = settled ? Any[
            _make_csv_option("CSV.jl", :rejected, "The platform takes no new dependency.";
                children = Any[_make_csv_step("Try CSV.jl in a branch"; state = :done)]),
            _make_csv_option("A parser of our own", :chosen, "Small, and it reads the cells lazily.";
                children = Any[_make_csv_step("Write a tokenizer for quoted fields"; state = :active)]),
            _make_csv_option("Arrow files only", :parked, "Later, for files too large for memory."),
        ] : Any[
            _make_csv_option("CSV.jl", :open, ""),
            _make_csv_option("A parser of our own", :open, ""),
            _make_csv_option("Arrow files only", :open, ""),
        ]
        push!(parser, WorkflowDecision(question = PrimitiveString("How to read a CSV file"),
            options = options, journal_shown = shown,
            journal = journal(_make_csv_entry("2026-10-14T10:20:00", :assistant, :decision,
                                              "Chose a parser of our own: small, and it reads the cells lazily."))))
    end
    if has(:substeps)
        append!(parser, Any[
            _make_csv_step("Read the header"; state = :done, journal_shown = shown,
                journal = journal(_make_csv_entry("2026-10-15T16:05:00", :person, :state, "done"))),
            _make_csv_step("Infer the column types"; state = :active),
            _make_csv_step("Handle quoted fields"),
        ])
    end
    release = has(:substeps) ? Any[_make_csv_step("Write the release notes"), _make_csv_step("Tag the version")] : Any[]

    _make_csv_step("Ship the CSV importer"; state = :active, journal_shown = shown,
        journal = journal(
            _make_csv_entry("2026-10-12T09:00:00", :person, :state, "active"),
            _make_csv_entry("2026-10-12T09:05:00", :person, :comment, "Start with the files that the users sent.")),
        children = Any[
            _make_csv_step("Collect sample files"; state = :done, journal_shown = shown,
                journal = journal(
                    _make_csv_entry("2026-10-13T11:30:00", :assistant, :comment,
                                    "Two of the three files use a semicolon as the separator."),
                    _make_csv_entry("2026-10-13T11:45:00", :person, :state, "done")),
                elements = elements(_make_csv_sample_table())),
            _make_csv_step("Write the parser"; state = :active, children = parser,
                elements = elements(TextBlock(TextLine(TextString("A quoted field can hold a line break, so a row is not a line."))))),
            _make_csv_step("Write the tests"),
            _make_csv_step("Release"; children = release),
        ])
end

"""
    make_workflow_goal_document_example() -> WorkflowStep

Stage 1 of "Ship the CSV importer": a new workflow, its goal and nothing else.
"""
make_workflow_goal_document_example() = _make_csv_workflow(:goal)

"""
    make_workflow_steps_document_example() -> WorkflowStep

Stage 2: the goal is active and has four steps in order, one done, one active and
two open.
"""
make_workflow_steps_document_example() = _make_csv_workflow(:steps)

"""
    make_workflow_substeps_document_example() -> WorkflowStep

Stage 3: the step that writes the parser and the release have sub-steps.
"""
make_workflow_substeps_document_example() = _make_csv_workflow(:substeps)

"""
    make_workflow_open_decision_document_example() -> WorkflowStep

Stage 4: before the sub-steps of the parser stands a decision, "How to read a CSV
file", with three options and none chosen yet.
"""
make_workflow_open_decision_document_example() = _make_csv_workflow(:decision)

"""
    make_workflow_explored_document_example() -> WorkflowStep

Stage 5: the decision is settled. The option that was tried and rejected keeps its
step and its reason, the chosen option has the step that follows it, and the third
option is parked with its reason.
"""
make_workflow_explored_document_example() = _make_csv_workflow(:explored)

"""
    make_workflow_recorded_document_example() -> WorkflowStep

Stage 6: the journal records the work over four days: a change of state, the
comments of the person, a finding of the assistant, and the decision that the
assistant wrote. Each node that has entries shows them open under its row.
"""
make_workflow_recorded_document_example() = _make_csv_workflow(:journal)

"""
    make_workflow_elements_document_example() -> WorkflowStep

Stage 7: elements keep documents in view: the table of the sample files under the
step that collected them, and a note of styled text under the parser. The journal
is folded again, as a new outline shows it: the count of the entries of a node
stands after its title.
"""
make_workflow_elements_document_example() = _make_csv_workflow(:elements)

"""
    make_workflow_list_document_example() -> WorkflowList

A list of the open workflows with no editor: its file list is empty, so the page
draws the line that says that no workflow is open and a table with no row, the
same on every machine.
"""
make_workflow_list_document_example() = WorkflowList()
