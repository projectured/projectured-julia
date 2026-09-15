function make_assistant_document_example()
    # Example doc: pass a FakeLlm so `run_example` works offline with no API key.
    # Production `main` never fabricates a fake; examples opt in explicitly.
    # The transcript starts full, with one part of every kind the transcript
    # draws, so the example shows each header and each fold on the first frame.
    assistant = Assistant(; llm = FakeLlm(),
                            conversation = make_assistant_conversation_document_example())
    # Seed selection so the first KeyPress lands inside the input.
    assistant.input.selection = ConcreteReference(
        FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
    assistant
end
