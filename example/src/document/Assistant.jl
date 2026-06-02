function make_assistant_document_example()
    assistant = WorkbenchAssistant()
    # Seed selection so the first KeyPress lands inside the input.
    assistant.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    assistant
end
