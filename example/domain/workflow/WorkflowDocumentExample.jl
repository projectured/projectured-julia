# ── Atomic workflow documents — one meaningful instance each, for the catalog. ──

make_workflow_entry_document_example() =
    WorkflowEntry(time = "2026-10-09T13:40:00", author = :person, kind = :comment,
                  text = PrimitiveString("Keep the records readable in a text editor."))

make_workflow_card_document_example() =
    WorkflowCard(title = PrimitiveString("Notes"),
                 content = PrimitiveString("A card holds a document of any domain."))

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
that is open. Entries by the person and by the assistant, and a card.
"""
make_workflow_document_example() =
    WorkflowStep(
        title = PrimitiveString("Workflow domain"),
        state = :active,
        children = [
            make_workflow_step_document_example(),
            make_workflow_decision_document_example(),
            WorkflowStep(title = PrimitiveString("Outline view"), state = :active,
                         cards = [make_workflow_card_document_example()]),
            WorkflowStep(title = PrimitiveString("Assistant tools")),
        ],
        journal = [WorkflowEntry(time = "2026-10-09T13:00:00", author = :person, kind = :state,
                                 text = PrimitiveString("active"))])
