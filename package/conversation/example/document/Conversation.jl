# A standalone conversation document — the chat history on its own, with no
# Assistant wrapper / input box. Lets the conversation rendering be
# tested in isolation (`test_example(conversation_widget_example)`,
# `print_example(conversation_widget_example)`, `write_example_image(...)`).
#
# Uniform turn/part model: a user turn, an assistant turn whose parts mix prose
# and a Julia code part, and a user turn carrying a Julia evaluation
# (`EvaluatorForm` = code + result).
function make_conversation_document_example()
    ConversationConversation([
        ConversationTurn(:user, [
            ConversationPart("Can you write a factorial function in Julia?"),
        ]),
        ConversationTurn(:assistant, [
            thinking_part("The user wants a factorial function. A recursive one is " *
                          "clearest; I'll mention the iterative alternative too.";
                          signature = "sig_example"),
            ConversationPart("Sure! Here is a concise recursive version:"),
            ConversationPart(JuliaIdentifier("factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)")),
            ConversationPart("It recurses until n reaches 1. Want an iterative one?"),
        ]),
        ConversationTurn(:user, [
            ConversationPart(EvaluatorForm(JuliaIdentifier("factorial(5)");
                                           result = TextBlock(TextString("120")))),
        ]),
    ])
end

# A draft user turn for the composer (Stage 3b) — a single active text typein
# (`PrimitiveString`) the user grows part by part: type prose, INSERT to start a
# kind chooser, type `julia` + ENTER for a Julia source part, ALT+ENTER to
# evaluate it, etc. Rooted at the turn itself so the composer can be exercised in
# isolation (`run_example(conversation_editor_example)`).
make_conversation_editor_document_example() =
    ConversationDraft([ConversationPart(PrimitiveString(""))])

# Atomic documents for the catalog.
make_conversation_part_document_example()  = ConversationPart("Can you write a factorial function in Julia?")
make_conversation_turn_document_example()  = ConversationTurn(:user, [make_conversation_part_document_example()])
make_conversation_conversation_document_example() =
    ConversationConversation([make_conversation_turn_document_example()])
make_conversation_draft_document_example() = make_conversation_editor_document_example()
