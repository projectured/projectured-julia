# A standalone conversation document — the chat history on its own, with no
# WorkbenchAssistant wrapper / input box. Lets the conversation rendering be
# tested in isolation (`test_example(conversation_example)`,
# `print_example(conversation_example)`, `write_image_example(...)`).
#
# Covers every part type: a user message, an assistant message whose blocks mix
# prose and a real `JuliaDocument` (parsed, not a string placeholder) code
# block, and a code execution.
function make_conversation_document_example()
    code = juliaparse("factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)")
    ConversationConversation([
        ConversationUserMessage("Can you write a factorial function in Julia?"),
        ConversationAssistantMessage(blocks = [
            ConversationTextBlock("Sure! Here is a concise recursive version:"),
            ConversationCodeBlock("julia", code),
            ConversationTextBlock("It recurses until n reaches 1. Want an iterative one?"),
        ]),
        ConversationCodeExecution(:user, "factorial(5)", "120"),
    ])
end
