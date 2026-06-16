# A standalone conversation document — the chat history on its own, with no
# WorkbenchAssistant wrapper / input box. Lets the conversation rendering be
# tested in isolation (`test_example(conversation_example)`,
# `print_example(conversation_example)`, `write_example_image(...)`).
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
            ConversationPart("Sure! Here is a concise recursive version:"),
            ConversationPart(JuliaIdentifier("factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)")),
            ConversationPart("It recurses until n reaches 1. Want an iterative one?"),
        ]),
        ConversationTurn(:user, [
            ConversationPart(EvaluatorForm(JuliaIdentifier("factorial(5)");
                                           result = TextText(TextString("120")))),
        ]),
    ])
end
