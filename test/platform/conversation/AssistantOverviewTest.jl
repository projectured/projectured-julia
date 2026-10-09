"""
    test_assistant_overview()

What the table of the assistants reads from one assistant: what the person
writes about the conversation, the times of its turns, and the values of its row.
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

        @testset "the values of a row" begin
            @testset "before the first prompt" begin
                a = Assistant()
                @test compute_assistant_overview_title(a) == "Assistant"
                @test find_first_prompt(a) === nothing
                @test find_last_prompt(a) === nothing
                @test compute_prompt_count(a) == 0
                @test compute_assistant_turn_side(a) === :person
                @test describe_assistant_activity(a) == ""
                @test find_assistant_start_time(a) === nothing
                @test find_assistant_last_activity_time(a) === nothing
                @test compute_assistant_elapsed_time(a) === nothing
                @test compute_assistant_busy_time(a) == 0.0
            end

            @testset "after two prompts" begin
                a = Assistant(; llm = FakeLlm("ok"))
                editor = (document = a, tools = register_default_tools!(ToolSet()))
                for prompt in ("\nFix the table\nwith the colors", "Second")
                    a.input.value = prompt
                    evaluate_operation(editor, SubmitProseOperation(a))
                    @test timedwait(() -> a.status !== :streaming, 10.0; pollint = 0.01) === :ok
                end
                # The title is the first line of the first prompt that holds text.
                @test compute_assistant_overview_title(a) == "Fix the table"
                @test find_first_prompt(a) == "\nFix the table\nwith the colors"
                @test find_last_prompt(a) == "Second"
                @test compute_prompt_count(a) == 2
                @test compute_assistant_turn_side(a) === :person
                @test describe_assistant_activity(a) == ""
                turns = collect(a.conversation.turns)
                @test find_assistant_start_time(a) == first(turns).start_time
                @test find_assistant_last_activity_time(a) == last(turns).finish_time
                @test compute_assistant_elapsed_time(a) == last(turns).finish_time - first(turns).start_time
                # The title that the agent gave its session wins.
                a.agent_title = "Colors of the table"
                @test compute_assistant_overview_title(a) == "Colors of the table"
            end

            @testset "the times, with a turn that runs" begin
                a = Assistant(; conversation = ConversationConversation([
                    ConversationTurn(:user, [ConversationPart("One")]; start_time = 10.0, finish_time = 10.0),
                    ConversationTurn(:assistant, [ConversationPart("Done.")]; start_time = 11.0, finish_time = 20.0),
                    ConversationTurn(:user, [ConversationPart("Two")]; start_time = 30.0, finish_time = 30.0),
                    ConversationTurn(:assistant; start_time = 31.0)]))
                @test compute_assistant_elapsed_time(a; now = 40.0) == 20.0
                @test compute_assistant_busy_time(a; now = 40.0) == 9.0
                a.status = :streaming
                @test compute_assistant_elapsed_time(a; now = 40.0) == 30.0
                @test compute_assistant_busy_time(a; now = 40.0) == 18.0
                @test find_assistant_last_activity_time(a) == 30.0
            end

            @testset "what the turn that runs does" begin
                turn = ConversationTurn(:assistant; start_time = 1.0)
                a = Assistant(; conversation = ConversationConversation([
                    ConversationTurn(:user, [ConversationPart("Go")]; start_time = 1.0, finish_time = 1.0), turn]))
                a.status = :streaming
                @test compute_assistant_turn_side(a) === :assistant
                @test describe_assistant_activity(a) == "starts"
                push!(turn.parts, Cell(make_conversation_thinking_part("I look.")))
                @test describe_assistant_activity(a) == "thinks"
                push!(turn.parts, Cell(ConversationPart(EvaluatorForm(PrimitiveString("1"); tool_name = "search_api"))))
                @test describe_assistant_activity(a) == "runs search_api"
                push!(turn.parts, Cell(ConversationPart("It is there.")))
                @test describe_assistant_activity(a) == "writes"
                a.status = :error
                @test describe_assistant_activity(a) == "failed"
                @test compute_assistant_turn_side(a) === :person
            end

            @testset "a question of the agent is the turn of the person" begin
                connection = ScriptedAgentConnection([Any[
                    make_scripted_permission_step(AgentToolCallUpdate("t1"; title = "Bash"),
                        [AgentPermissionOption("allow", "Allow", :allow_once)]),
                    LlmTextStart(), LlmTextDelta("Done."), LlmTextStop()]])
                a = _make_agent_assistant(connection)
                _submit_to_agent!(a, "List the files"; wait = false)
                request = _wait_for_permission_request(a)
                @test compute_assistant_turn_side(a) === :person
                @test describe_assistant_activity(a) == request.title
                answer_permission_request!(request, "allow")
                _wait_for_idle(a)
                @test compute_assistant_turn_side(a) === :person
                @test describe_assistant_activity(a) == ""
            end
        end
    end
end
