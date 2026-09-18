"""
    make_assistant_document_example(; backend = :none, model = "") -> Assistant

The assistant example: a full transcript, with one part of every kind the
transcript draws, so the first frame shows each header and each fold.

**It answers from a canned transcript.** `backend = :none` gives it a `FakeLlm`,
so the example runs offline, with no server and no key, which is what the test
sweeps need. `backend = :ollama` or `backend = :anthropic` gives it a real model
instead, and then a submit reaches that model. `model` names one, and an empty
`model` takes the default of the backend.
"""
function make_assistant_document_example(; backend::Symbol = :none,
                                           model::AbstractString = "")
    assistant = backend === :none ?
        Assistant(; llm = FakeLlm(),
                    conversation = make_assistant_conversation_document_example()) :
        Assistant(; backend = backend, model = String(model),
                    conversation = make_assistant_conversation_document_example())
    # Seed selection so the first KeyPress lands inside the input.
    assistant.input.selection = ConcreteReference(
        FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
    assistant
end
