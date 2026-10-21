"""
    test_conversation_tree()

The nodes of a conversation in a tree: a turn has its parts as children, and is
known by its role and the first line of its first text; a turn that runs says
so; a part of text is known by its first line, cut at the length of a label; a
part has the children of its content; a thinking, a tool call and a request of
an agent say what they are and their state.
"""
function test_conversation_tree()
    @testset "the nodes of a conversation in a tree" begin
        @testset "a turn has its parts, its role and the first line of its first text" begin
            thinking = make_conversation_thinking_part("I read the file.")
            text = ConversationPart(make_text_block("\n  The first line.  \nThe second line."))
            turn = ConversationTurn(:assistant; parts = [thinking, text], start_time = 1000.0, finish_time = 1010.0)
            @test get_tree_children_steps(turn) == ((FieldReferenceStep("parts"),),)
            @test format_tree_node_label(turn) == "Assistant · The first line."
            decoration = get_document_decoration(turn)
            @test decoration.icon === :bot
            @test decoration.detail == "2 parts · " * Libc.strftime("%H:%M:%S", 1000.0)
            @test isempty(decoration.conditions)
            # A turn whose times are not known says no time.
            asked = ConversationTurn(:user, [ConversationPart("Can we make an outline?")])
            @test format_tree_node_label(asked) == "You · Can we make an outline?"
            @test get_document_decoration(asked).icon === :user
            @test get_document_decoration(asked).detail == "1 part"
            # A turn with no text says its role only.
            @test format_tree_node_label(ConversationTurn(:assistant; parts = [thinking])) == "Assistant"
        end

        @testset "a turn that runs says so, and reads no clock" begin
            turn = ConversationTurn(:assistant; start_time = 1000.0)
            decoration = get_document_decoration(turn)
            @test decoration.icon === :loader
            @test [condition.name for condition in decoration.conditions] == [:running]
            @test decoration.detail == "0 parts · " * Libc.strftime("%H:%M:%S", 1000.0)
            turn.finish_time = 1010.0
            @test get_document_decoration(turn).icon === :bot
            @test isempty(get_document_decoration(turn).conditions)
        end

        @testset "a part of text is known by its first line, cut at the length of a label" begin
            long = repeat("word ", 30)
            part = ConversationPart(make_text_block(long))
            label = format_tree_node_label(part)
            @test length(label) == 80
            @test label == first(strip(long), 79) * "…"
            @test get_document_decoration(part).icon === :pilcrow
            @test get_tree_children_steps(part) == ()
            # A part of blanks only is known as its content is.
            blank = ConversationPart(make_text_block("  \n "))
            @test format_tree_node_label(blank) == format_tree_node_label(blank.content)
            # A document with a natural notation is a text too.
            code = ConversationPart(parse_natural_text(:json, "\"Text of code\""))
            @test format_tree_node_label(code) == "\"Text of code\""
            @test get_document_decoration(code).icon === :pilcrow
        end

        @testset "a part has the children of its content, below the step content" begin
            section = ExplorerSection("Notes", Any[ExplorerSection("Inner")])
            part = ConversationPart(section)
            @test get_tree_children_steps(part) ==
                  ((FieldReferenceStep("content"), FieldReferenceStep("entries")),)
            @test format_tree_node_label(part) == "Notes"
            @test get_document_decoration(part).icon === :layers
        end

        @testset "a thinking and a tool call say what they are, and a tool call its state" begin
            thinking = make_conversation_thinking_part("I read the file.")
            @test format_tree_node_label(thinking) == "Thinking"
            @test get_document_decoration(thinking).icon === :circle_dashed
            form = EvaluatorForm(TextBlock(); tool_name = "Grep", input = Dict{String,Any}("pattern" => "outline"))
            part = ConversationPart(form)
            @test format_tree_node_label(part) == "tool · Grep \"outline\""
            @test get_document_decoration(part).icon === :terminal
            @test isempty(get_document_decoration(part).conditions)
            form.is_running = true
            @test [condition.name for condition in get_document_decoration(part).conditions] == [:running]
            form.is_running = false
            form.is_error = true
            @test [condition.name for condition in get_document_decoration(part).conditions] == [:failed]
            evaluation = EvaluatorForm(TextBlock())
            @test format_tree_node_label(evaluation) == "eval"
            @test get_document_decoration(evaluation).icon === :lambda
        end

        @testset "a request says its first line, and that it waits while it is open" begin
            permission = ConversationPermissionRequest("Run git status?\nIn the worktree.", Any[];
                                                       reply = _ -> true)
            @test format_tree_node_label(ConversationPart(permission)) == "Run git status?"
            decoration = get_document_decoration(permission)
            @test decoration.icon === :circle_help
            @test [(condition.name, condition.count) for condition in decoration.conditions] == [(:waiting, 1)]
            permission.answer = "Allow"
            @test isempty(get_document_decoration(permission).conditions)
            question = ConversationQuestionRequest("Which file?", Any[])
            @test format_tree_node_label(question) == "Which file?"
            @test isempty(get_document_decoration(question).conditions)
            @test format_tree_node_label(ConversationQuestionRequest("", Any[])) == "Question"
            sign_in = ConversationSignInRequest("Sign in to the agent.", Any[])
            @test format_tree_node_label(sign_in) == "Sign in to the agent."
            @test get_document_decoration(sign_in).icon === :lock
        end
    end
end
