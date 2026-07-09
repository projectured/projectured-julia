function make_assistant_document_example()
    # Example doc: pass a FakeLlm so `run_example` works offline with no API key.
    # Production `main` never fabricates a fake; examples opt in explicitly.
    assistant = WorkbenchAssistant(; llm = FakeLlm())
    # Seed selection so the first KeyPress lands inside the input.
    assistant.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    assistant
end
