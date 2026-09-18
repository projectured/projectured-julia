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
            make_conversation_thinking_part("The user wants a factorial function. A recursive one is " *
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


# The conversation the assistant example starts with: every kind of part the
# transcript draws, so a person who runs `run_example(assistant_example)` sees
# each header and each fold at once. The replies are made up; each evaluation
# holds the result it would give. A resource read starts folded, as the agent
# loop folds one; the failed evaluation starts with its error folded, as the
# form's own default says; every other fold starts open.
function make_assistant_conversation_document_example()
    ConversationConversation([
        ConversationTurn(:assistant, [
            ConversationPart(parse_markdown(
                "This transcript is canned: the replies below were written into the " *
                "example, and a submit answers from a `FakeLlm`. For a real model, " *
                "run `run_assistant_example(; backend = :ollama)` or " *
                "`run_assistant_example(; backend = :anthropic)`.")),
        ]),
        ConversationTurn(:user, [
            ConversationPart(parse_markdown("Can you write a factorial function in Julia and check that it works?")),
        ]),
        ConversationTurn(:assistant, [
            make_conversation_thinking_part(
                "The user wants a factorial function. A recursive one is the clearest. " *
                "I define it, evaluate it once, and read the guide before I touch the editor.";
                signature = "sig_example"),
            ConversationPart(parse_markdown("Sure. Here is a recursive version:")),
            ConversationPart(parse_julia("factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)")),
            ConversationPart(EvaluatorForm(parse_julia("factorial(5)");
                                           source = "factorial(5)",
                                           result = make_evaluator_result_text("120"),
                                           tool_use_id = "tu_1")),
            ConversationPart(EvaluatorForm(make_evaluator_arguments_text(Dict("uri" => "resource://guide/orientation"));
                                           tool_name = "read_resource",
                                           input = Dict{String,Any}("uri" => "resource://guide/orientation"),
                                           result = make_evaluator_result_text(
                                               "# Orientation\n\n" *
                                               "The editor holds one document and one projection. The projection " *
                                               "prints the document, and reads a gesture back into an operation."),
                                           tool_use_id = "tu_2");
                             collapsed = true),
            ConversationPart(EvaluatorForm(make_evaluator_arguments_text(Dict("query" => "make_child_context", "kind" => "function"));
                                           tool_name = "search_api",
                                           input = Dict{String,Any}("query" => "make_child_context", "kind" => "function"),
                                           result = make_evaluator_result_text(
                                               "ProjecturedKernel.ProjectionModule.make_child_context(ctx, reference)\n" *
                                               "  The context a child prints with: the parent's, with the reference extended."),
                                           tool_use_id = "tu_3")),
            ConversationPart(EvaluatorForm(parse_julia("sqrt(-1)");
                                           source = "sqrt(-1)",
                                           result = make_evaluator_result_text(
                                               "DomainError with -1.0:\n" *
                                               "sqrt was called with a negative real argument but will only return a " *
                                               "complex result if called with a complex argument. Try sqrt(Complex(x)).\n" *
                                               "Stacktrace:\n" *
                                               " [1] throw_complex_domainerror(f::Symbol, x::Float64)\n" *
                                               "   @ Base.Math ./math.jl:33"),
                                           is_error = true,
                                           tool_use_id = "tu_4")),
            ConversationPart(parse_markdown(
                "The function works: `factorial(5)` is 120. Two notes:\n\n" *
                "- It recurses, so a very large `n` overflows the stack.\n" *
                "- `sqrt(-1)` fails on purpose above, to show an error.")),
        ]),
        ConversationTurn(:user, [
            ConversationPart(EvaluatorForm(parse_julia("factorial(6)");
                                           source = "factorial(6)",
                                           result = make_evaluator_result_text("720"))),
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
