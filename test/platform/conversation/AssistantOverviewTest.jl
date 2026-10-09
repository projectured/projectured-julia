"""
    test_assistant_overview()

What the table of the assistants reads from one assistant: what the person
writes about the conversation, and the times of its turns.
"""
function test_assistant_overview()
    @testset "the overview of an assistant" begin
        @testset "what the person writes about a conversation" begin
            a = Assistant()
            @test a.description.value == ""
            @test a.comment.value == ""
            @test a.work_state === :pending
            # A new assistant writes none of the three into its file.
            @test !occursin(r"\b(description|comment|work_state) =", print_pred_text(a))
            @test_throws ArgumentError Assistant(; work_state = :done)

            a = Assistant(; description = "Fix the table", comment = "Ask about the colors.",
                          work_state = :in_progress)
            @test a.description isa PrimitiveString
            @test (a.description.value, a.comment.value, a.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            # A native assistant keeps the three in its file too.
            text = print_pred_text(a)
            loaded = parse_pred_text(text)
            @test (loaded.description.value, loaded.comment.value, loaded.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            @test print_pred_text(loaded) == text
            # A fork copies the three, and an edit of the fork stays in the fork.
            fork = copy_document(DuplicatePolicy(), a)
            @test (fork.description.value, fork.comment.value, fork.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            fork.description.value = "Another table"
            @test a.description.value == "Fix the table"
        end

        @testset "the times of a turn" begin
            @testset "a native turn" begin
                a = Assistant(; llm = FakeLlm("ok"))
                a.input.value = "Hello"
                before = time()
                evaluate_operation((document = a, tools = register_default_tools!(ToolSet())),
                                   SubmitProseOperation(a))
                @test timedwait(() -> a.status !== :streaming, 10.0; pollint = 0.01) === :ok
                after = time()
                question, answer = collect(a.conversation.turns)
                @test question.role === :user
                @test before <= question.start_time == question.finish_time <= after
                @test answer.role === :assistant
                @test question.start_time <= answer.start_time <= answer.finish_time <= after
            end

            @testset "a turn of an external agent" begin
                connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Sure."), LlmTextStop()]])
                a = _make_agent_assistant(connection)
                before = time()
                _submit_to_agent!(a, "Hello")
                question, answer = collect(a.conversation.turns)
                @test before <= question.start_time == question.finish_time
                @test question.start_time <= answer.start_time <= answer.finish_time <= time()
            end

            @testset "a file keeps the times" begin
                turn = ConversationTurn(:user, [ConversationPart("Hello")]; start_time = 10.0, finish_time = 12.5)
                loaded = parse_pred_text(print_pred_text(turn))
                @test (loaded.start_time, loaded.finish_time) == (10.0, 12.5)
                # A file that kept no times builds a turn whose times are not known.
                old = make_pred_document(ConversationTurn, (),
                                         Pair{Symbol,Any}[:role => :user, :parts => Any[ConversationPart("Hello")],
                                                          :stop_reason => :complete, :collapsed => false])
                @test (old.start_time, old.finish_time) == (0.0, 0.0)
                @test (old.role, length(collect(old.parts))) == (:user, 1)
            end
        end
    end
end
