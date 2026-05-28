"""
    make_assistant_document_example()

A bare `WorkbenchAssistant` document with a small pre-seeded conversation
and the input cursor placed at offset 0. Intended for the `assistant`
example — exercises the assistant chat surface in isolation, without
the surrounding workbench.
"""
function make_assistant_document_example()
    assistant = WorkbenchAssistant()
    # Seed selection so the first KeyPress lands inside the input.
    assistant.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    assistant
end
