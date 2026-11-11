"""
    test_external_agent_turn()

A turn of an external agent, against a scripted connection: what the person
said becomes the prompt, the events of the agent become parts, a question of
the agent waits for the person or for a cancel, a duplicate starts a new
session, and a backend whose package is not loaded says so.
"""
function test_external_agent_turn()
    @testset "a turn of an external agent" begin
        @testset "the events of the agent become parts" begin
            connection = ScriptedAgentConnection([Any[
                LlmThinkingStart(), LlmThinkingDelta("I add."), LlmThinkingStop(),
                LlmTextStart(), LlmTextDelta("Let me run it."), LlmTextStop(),
                AgentToolCallUpdate("t1"; name = "mcp__projectured__execute_julia_code", title = "Run",
                                    kind = :execute, status = :pending,
                                    input = Dict{String,Any}("code" => "1 + 1")),
                AgentPlanUpdate([AgentPlanEntry("Add", :high, :in_progress)]),
                AgentToolCallUpdate("t1"; status = :completed, output = "2"),
                AgentPlanUpdate([AgentPlanEntry("Add", :high, :completed)]),
                LlmTextStart(), LlmTextDelta("It is 2."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "What is 1 + 1?")
            @test a.status === :idle
            @test only(connection.sessions).mcp_servers == Any[]
            # The agent learns that it runs inside the editor, and reads the text of
            # its window, as the built-in loop does.
            @test only(connection.sessions).instructions == DEFAULT_AGENT_INSTRUCTIONS * "\n\n" * a.system
            @test occursin(ASSISTANT_ANSWER_INSTRUCTIONS, only(connection.sessions).instructions)
            @test only(connection.prompts) == Any[LlmText("What is 1 + 1?")]
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            parts = collect(turns[2].parts)
            @test parts[1].content isa ConversationThinking
            form = only(part.content for part in parts if part.content isa EvaluatorForm)
            @test form.tool_name == "execute_julia_code"
            @test form.source == "1 + 1"
            @test form.output == "2"
            @test !form.is_error
            # One plan part, which the second update replaced.
            plans = [part for part in parts if occursin("Plan", AssistantModule._part_text(part))]
            @test length(plans) == 1
            @test occursin("[x] Add", AssistantModule._part_text(only(plans)))
            # The text after the tool call is a part of its own, after the form.
            texts = [AssistantModule._part_text(part) for part in parts]
            @test findfirst(text -> occursin("It is 2.", text), texts) >
                  findfirst(part -> part.content isa EvaluatorForm, parts)
        end

        @testset "a call that fails folds its result once" begin
            connection = ScriptedAgentConnection([Any[
                AgentToolCallUpdate("t1"; name = "mcp__projectured__execute_julia_code", title = "Run",
                                    kind = :execute, status = :pending,
                                    input = Dict{String,Any}("code" => "error(\"x\")")),
                AgentToolCallUpdate("t1"; status = :failed, output = "ERROR: x")]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Throw an error.")
            turn = collect(a.conversation.turns)[2]
            form = only(part.content for part in collect(turn.parts) if part.content isa EvaluatorForm)
            # The form was made while the call was pending, and the failure folds it.
            @test form.is_error && form.result_collapsed
            # A person opens the result, and a later update of the call keeps it open.
            form.result_collapsed = false
            state = AssistantModule._make_agent_turn_state(turn)
            state[:tool_forms]["t1"] = form
            AssistantModule._apply_tool_call_update!(turn, state,
                AgentToolCallUpdate("t1"; status = :failed, output = "ERROR: x"), nothing)
            @test form.is_error && !form.result_collapsed
        end

        @testset "a warm-up gives the feed one turn with each kind of part, and no agent" begin
            a = Assistant(; backend = :acp)
            editor = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
                            feeds = Feed[AgentEventFeed(), TaskFeed()])
            @test warm_assistant_turn!(editor, a) === a
            # The events wait in the queue of the session until the feed applies them.
            @test a.agent_session.connection === nothing
            @test editor.wake_pending[]
            @test length(collect(a.conversation.turns)) == 1
            drain_feeds!(editor)
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns[end - 1:end]] == [:user, :assistant]
            @test turns[end].stop_reason === :end_turn
            parts = collect(turns[end].parts)
            @test parts[1].content isa ConversationThinking
            forms = [part.content for part in parts if part.content isa EvaluatorForm]
            @test [form.tool_name for form in forms] == ["search_api", "Bash", "execute_julia_code"]
            @test forms[3].source == AssistantModule._WARM_CODE
            @test forms[3].output == AssistantModule._WARM_CODE_OUTPUT
            # The request stays open, so a workload can draw its options and click one.
            request = only(part.content for part in parts if part.content isa ConversationPermissionRequest)
            @test is_permission_request_open(request)
            texts = [AssistantModule._part_text(part) for part in parts]
            @test any(text -> occursin("33.5", text), texts)
        end

        @testset "the turn says that the agent starts until its session is open" begin
            gate = Channel{Nothing}(1)
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Hi."), LlmTextStop()]];
                                                 on_start = connection -> take!(gate))
            a = _make_agent_assistant(connection)
            is_starting() = any(part -> AssistantModule._part_text(part) == "Starting Claude Code…",
                                [part for turn in collect(a.conversation.turns) for part in collect(turn.parts)])
            _submit_to_agent!(a, "Hello"; wait = false)
            @test timedwait(is_starting, 10.0; pollint = 0.01) === :ok
            @test [turn.role for turn in collect(a.conversation.turns)] == [:user, :assistant]
            put!(gate, nothing)
            _wait_for_idle(a)
            @test !is_starting()
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            @test occursin("Hi.", AssistantModule._part_text(only(collect(turns[2].parts))))
            # A start that fails leaves no turn of its own.
            failing = ScriptedAgentConnection([Any[]]; failing_opens = 1)
            b = _make_agent_assistant(failing)
            _submit_to_agent!(b, "Hello")
            @test b.status === :error
            @test !any(turn -> turn.role === :assistant && isempty(collect(turn.parts)), collect(b.conversation.turns))
        end

        @testset "a second turn sends only what came since the last answer" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            _submit_to_agent!(a, "Second")
            @test connection.prompts == [Any[LlmText("First")], Any[LlmText("Second")]]
            @test length(connection.sessions) == 1
        end

        @testset "a turn that never reached the agent is in the next prompt" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Sure."), LlmTextStop()]];
                                                 failing_opens = 1)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Explain X")
            @test a.status === :error
            @test isempty(connection.prompts)
            _submit_to_agent!(a, "Try again")
            @test a.status === :idle
            @test only(connection.prompts) == Any[LlmText("Explain X"), LlmText("Try again")]
        end

        @testset "a picture of a user turn goes as an image between its texts" begin
            file = joinpath(mktempdir(), "picture.png")
            write(file, UInt8[1, 2, 3])
            conversation = ConversationConversation([ConversationTurn(:user, [
                ConversationPart("See"), ConversationPart(ImageFile(file)), ConversationPart("and this")])])
            prompt, count = AssistantModule._make_external_agent_prompt(conversation, 0)
            @test count == 1
            @test length(prompt) == 3
            @test prompt[1] == LlmText("See") && prompt[3] == LlmText("and this")
            @test prompt[2] isa LlmImage
            @test (prompt[2].media_type, prompt[2].data) == ("image/png", UInt8[1, 2, 3])
            # A model gets the same content in its user message.
            message = only(build_messages(conversation))
            @test message.role === :user && length(message.content) == 3 && message.content[2] isa LlmImage
            # A picture whose file is gone is a line of the text.
            rm(file)
            prompt, _ = AssistantModule._make_external_agent_prompt(conversation, 0)
            @test length(prompt) == 1
            @test occursin("See\n\n(A picture is left out", only(prompt).text)
        end

        @testset "a draft takes a pasted document with no text form as a part before the text" begin
            draft = make_conversation_draft()
            result = AgentTurnLiveResult(() -> 1)
            @test !has_text_form(result)
            @test has_text_form(PrimitiveString("x")) && has_text_form(TextBlock(TextLine(TextString("t"))))
            @test make_pasted_document_operation(draft, EmptyReference(), PrimitiveString("x")) === nothing
            operation = make_pasted_document_operation(draft, EmptyReference(), result)
            @test operation isa InsertDraftDocumentOperation
            evaluate_operation((document = draft,), operation)
            parts = collect(draft.parts)
            @test length(parts) == 2
            @test parts[1].content === result && parts[2].content isa PrimitiveString
        end

        @testset "a picture is a card with its image, at most as high as the theme says" begin
            part = ConversationPart(ImageFile(joinpath(mktempdir(), "gone.png")))
            card = print_document(ConversationPartToWidget(), nothing, part, nothing).output
            @test card isa WidgetCard
            @test card.title.content == "picture"
            constraint = only(card.content.children)
            label = constraint.child
            @test label isa WidgetLabel && label.content isa ImageFile
            height = ConversationPartToWidget().picture_height
            @test constraint.max_height == height
            # A picture that is not read yet is a box of the shape 4:3 that fits the height.
            @test constraint.max_width === nothing
            images = GraphicsImage[]
            find_images!(node) = node isa GraphicsImage ? push!(images, node) :
                                 node isa GraphicsCanvas ? foreach(e -> find_images!(e isa Cell ? e[] : e), node.elements) :
                                 node isa GraphicsViewport ? find_images!(node.content) : nothing
            find_images!(print_document(
                RecursiveProjection(TypeDispatchingProjection(
                    WidgetToGraphics(; measure = FixedMeasure(8, 12, 4, 0)).dispatch)),
                nothing, card, with_exact_size(PrinterContext(); width = Cell(Int32(800)),
                                               height = Cell(Int32(600)))).output)
            @test length(images) == 1 && (Int(images[1].w), Int(images[1].h)) == (4 * height ÷ 3, height)
        end

        @testset "an agent that needs a sign-in gives a request, and a retry starts it" begin
            method = AgentSignInMethod("login", "Sign in", "Run the sign-in.", `true`)
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Hi."), LlmTextStop()]];
                                                 is_signed_in = false, sign_in_methods = [method],
                                                 can_sign_out = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            # A sign-in is no fault: the turn ends, and a request says how to sign in.
            @test a.status === :idle
            request = only(part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                           if part.content isa ConversationSignInRequest)
            @test request.message == "The scripted agent needs a sign-in."
            @test [m.id for m in request.methods] == ["login"]
            @test request.start !== nothing && request.retry !== nothing
            @test !any(part -> part.content isa AbstractString && startswith(part.content, "Error"),
                       part for turn in collect(a.conversation.turns) for part in collect(turn.parts))
            # A sign-in that ends with 0 starts the agent again. Its program reads
            # a code and ends with 0 for the right one.
            signer = AgentSignInMethod("code", "Sign in with a code", "",
                                       `sh -c "printf 'Code > '; read code; test \"\$code\" = right"`)
            push!(request.methods, signer)
            request.start((document = a,), "code")
            terminal = request.terminal
            @test terminal isa TerminalDocument && request.is_signing_in
            @test timedwait(() -> "Code > " in [line.text for line in terminal.lines], 10.0; pollint = 0.01) === :ok
            connection.is_signed_in = true
            @test send_terminal_input!(terminal, "right")
            @test timedwait(() -> length(connection.sessions) == 1, 10.0; pollint = 0.01) === :ok
            @test request.state == "Signed in." && !request.is_signing_in
            # A sign-in that a person stopped is no sign-in, even with the status 0.
            trap = AgentSignInMethod("trap", "Sign in and stop", "",
                                     `sh -c "trap 'exit 0' INT; printf 'Code > '; read code"`)
            push!(request.methods, trap)
            request.start((document = a,), "trap")
            stopped = request.terminal
            @test timedwait(() -> "Code > " in [line.text for line in stopped.lines], 10.0; pollint = 0.01) === :ok
            stop_terminal!(stopped)
            @test timedwait(() -> !request.is_signing_in, 10.0; pollint = 0.01) === :ok
            @test stopped.status == 0 && request.state == "The sign-in was stopped."
            @test length(connection.sessions) == 1
            # A retry when the session is open does nothing more.
            request.retry((document = a,))
            @test length(connection.sessions) == 1
            # A copy of the request has no live function.
            copied = copy_document(DuplicatePolicy(), request)
            @test copied.start === nothing && copied.retry === nothing && copied.terminal === nothing
            # The agent signs out on request, and a note says so.
            @test AssistantModule._has_agent_sign_out(a)
            evaluate_operation((document = a,), SignOutAgentOperation(a))
            @test timedwait(() -> !connection.is_signed_in, 10.0; pollint = 0.01) === :ok
            @test timedwait(() -> any(part -> AssistantModule._part_text(part) == "Signed out. The next message needs a sign-in.",
                                      collect(last(collect(a.conversation.turns)).parts)), 10.0; pollint = 0.01) === :ok
        end

        @testset "an agent that runs its own sign-in signs in from the request" begin
            browser = AgentSignInMethod("chat-gpt", "ChatGPT", "Use ChatGPT to authenticate", nothing)
            # The start of the agent waits for the test, as a sign-in in the
            # browser waits for the person.
            gate = Channel{Nothing}(1)
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Hi."), LlmTextStop()]];
                                                 is_signed_in = false, sign_in_methods = [browser])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            request = only(part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                           if part.content isa ConversationSignInRequest)
            @test only(request.methods).command === nothing
            # The method asks the agent and opens no terminal.
            is_starting = Threads.Atomic{Bool}(false)
            connection.on_start = connection -> (is_starting[] = true; take!(gate))
            request.start((document = a,), "chat-gpt")
            @test request.is_signing_in && request.terminal === nothing
            @test request.state == "The agent runs the sign-in, such as in the browser. Finish it there."
            @test timedwait(() -> is_starting[], 10.0; pollint = 0.01) === :ok
            connection.on_start = nothing
            # A message meanwhile waits for the sign-in, where its start would end
            # the agent that runs the sign-in, and runs after it.
            _submit_to_agent!(a, "Hello again"; wait = false)
            sleep(0.2)
            @test isempty(connection.sessions) && isempty(connection.prompts)
            put!(gate, nothing)
            @test timedwait(() -> length(connection.prompts) == 1, 10.0; pollint = 0.01) === :ok
            _wait_for_idle(a)
            @test connection.agent_sign_ins == ["chat-gpt"]
            @test request.state == "Signed in." && !request.is_signing_in
            @test length(connection.sessions) == 1
            # A method that the agent does not run says so, and starts nothing.
            push!(request.methods, AgentSignInMethod("other", "Other", "", nothing))
            request.start((document = a,), "other")
            @test timedwait(() -> !request.is_signing_in, 10.0; pollint = 0.01) === :ok
            @test request.state == "The agent can not run this sign-in."
            @test connection.agent_sign_ins == ["chat-gpt", "other"]
            @test length(connection.sessions) == 1
            # A window that stops the agent ends the sign-in, which then starts nothing.
            is_starting[] = false
            connection.on_start = connection -> (is_starting[] = true; take!(gate))
            request.start((document = a,), "chat-gpt")
            @test timedwait(() -> is_starting[], 10.0; pollint = 0.01) === :ok
            connection.on_start = nothing
            stop_external_agent!(a)
            put!(gate, nothing)
            @test timedwait(() -> !request.is_signing_in, 10.0; pollint = 0.01) === :ok
            @test request.state == "The sign-in was stopped."
            @test connection.agent_sign_ins == ["chat-gpt", "other"]
            @test a.agent_session === nothing && length(connection.sessions) == 1
            # With no agent, the sign-in makes one, and here says why it can not.
            request.start((document = a,), "chat-gpt")
            @test timedwait(() -> !request.is_signing_in, 10.0; pollint = 0.01) === :ok
            @test startswith(request.state, "The sign-in failed: The backend :acp needs the package ProjecturedACP.")
        end

        @testset "a question of the agent is a form, and its values go back" begin
            fields = [AgentQuestionField("question_1", "Colour", "Which colour?", :choice,
                                         [AgentOptionValue("Red", "Red", "warm"), AgentOptionValue("Blue", "Blue", "")], true),
                      AgentQuestionField("question_1_other", "Other", "", :text, AgentOptionValue[], false),
                      AgentQuestionField("parts", "Parts", "", :choices,
                                         [AgentOptionValue("a", "A", ""), AgentOptionValue("b", "B", "")], false),
                      AgentQuestionField("size", "Size", "", :integer, AgentOptionValue[], false)]
            connection = ScriptedAgentConnection([
                Any[make_scripted_question_step("Answer, please.", fields), LlmTextStart(), LlmTextDelta("Thanks."), LlmTextStop()],
                Any[make_scripted_question_step("Once more?", fields[1:1])]])
            a = _make_agent_assistant(connection)
            requests() = [part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                          if part.content isa ConversationQuestionRequest]
            _submit_to_agent!(a, "Ask me"; wait = false)
            @test timedwait(() -> length(requests()) == 1, 10.0; pollint = 0.01) === :ok
            request = only(requests())
            @test request.message == "Answer, please." && is_question_request_open(request)
            # The form says what it still needs.
            @test find_question_values(request) == "Fill in: Colour"
            values = collect(request.form.values)
            values[1].value = "Red"
            values[3].value = "a\nb"
            values[4].value = "many"
            @test find_question_values(request) == "Size needs a whole number"
            values[4].value = "3"
            answer_question_request!(request, find_question_values(request))
            _wait_for_idle(a)
            @test only(connection.answers) == Dict{String,Any}("question_1" => "Red", "parts" => ["a", "b"], "size" => 3)
            @test request.answer == "Answered: Colour: Red; Parts: A, B; Size: 3"
            @test !is_question_request_open(request)
            # A second answer does nothing.
            answer_question_request!(request, nothing)
            @test length(connection.answers) == 1
            # A decline.
            _submit_to_agent!(a, "Again"; wait = false)
            @test timedwait(() -> length(requests()) == 2, 10.0; pollint = 0.01) === :ok
            answer_question_request!(requests()[2], nothing)
            _wait_for_idle(a)
            @test connection.answers[2] === nothing && requests()[2].answer == "Declined"
            # A file keeps the message, the fields and the answer, and no reply.
            _, keywords = pred_arguments(request)
            read_back = make_pred_document(ConversationQuestionRequest, (), keywords)
            @test read_back.message == request.message && read_back.answer == request.answer
            @test [(field.name, field.kind, length(field.options)) for field in read_back.fields] ==
                  [(field.name, field.kind, length(field.options)) for field in fields]
            @test read_back.reply === nothing
            @test copy_document(DuplicatePolicy(), request).reply === nothing
        end

        @testset "a message while the agent works goes into its turn, and the answer goes on below it" begin
            # The agent answers, waits until it took the second message, and answers on.
            wait_for_steer = (connection, on_event) -> timedwait(() -> !isempty(connection.steered), 10.0; pollint = 0.01)
            connection = ScriptedAgentConnection([
                Any[LlmTextStart(), LlmTextDelta("Working."), LlmTextStop(), wait_for_steer,
                    LlmTextStart(), LlmTextDelta("Also done."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Third answer."), LlmTextStop()]]; can_steer = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First"; wait = false)
            @test timedwait(() -> any(turn -> turn.role === :assistant && !isempty(turn.parts),
                                      collect(a.conversation.turns)), 10.0; pollint = 0.01) === :ok
            _submit_to_agent!(a, "Second")
            @test connection.steered == [Any[LlmText("Second")]]
            @test length(connection.prompts) == 1
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant, :user, :assistant]
            @test occursin("Working.", AssistantModule._part_text(only(turns[2].parts)))
            @test occursin("Also done.", AssistantModule._part_text(only(turns[4].parts)))
            # The agent saw the second message, so the next prompt holds only the third.
            _submit_to_agent!(a, "Third")
            @test connection.prompts[2] == Any[LlmText("Third")]
        end

        @testset "a message while an agent without steering works waits, and a turn of its own follows" begin
            release = Ref(false)
            wait_for_release = (connection, on_event) -> timedwait(() -> release[], 10.0; pollint = 0.01)
            connection = ScriptedAgentConnection([
                Any[wait_for_release, LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First"; wait = false)
            @test timedwait(() -> length(connection.prompts) == 1, 10.0; pollint = 0.01) === :ok
            _submit_to_agent!(a, "Second"; wait = false)
            # The message shows at once below the turn that runs.
            @test [turn.role for turn in collect(a.conversation.turns)] == [:user, :assistant, :user]
            release[] = true
            @test timedwait(() -> length(connection.prompts) == 2 && a.status !== :streaming, 10.0;
                            pollint = 0.01) === :ok
            @test connection.prompts[2] == Any[LlmText("Second")]
            @test [turn.role for turn in collect(a.conversation.turns)] == [:user, :assistant, :user, :assistant]
            # A stop does not start the next turn: the waiting message goes with the next Return.
            release[] = false
            connection = ScriptedAgentConnection([Any[wait_for_release, LlmTextStart(), LlmTextDelta("x"), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("y"), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First"; wait = false)
            @test timedwait(() -> length(connection.prompts) == 1, 10.0; pollint = 0.01) === :ok
            _submit_to_agent!(a, "Second"; wait = false)
            evaluate_operation((document = a,), CancelAssistantTurnOperation(a))
            release[] = true
            _wait_for_idle(a)
            sleep(0.2)
            @test length(connection.prompts) == 1
            @test last(collect(a.conversation.turns)).role === :user
        end

        @testset "a turn that the person cancelled is not sent again" begin
            connection = ScriptedAgentConnection([
                Any[(connection, on_event) -> timedwait(() -> connection.is_cancelled, 10.0; pollint = 0.01)],
                Any[LlmTextStart(), LlmTextDelta("B."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "A"; wait = false)
            @test timedwait(() -> length(connection.prompts) == 1, 10.0; pollint = 0.01) === :ok
            evaluate_operation((document = a,), CancelAssistantTurnOperation(a))
            _wait_for_idle(a)
            # The cancelled turn drew nothing, so it is gone.
            @test [turn.role for turn in collect(a.conversation.turns)] == [:user]
            _submit_to_agent!(a, "B")
            @test connection.prompts == [Any[LlmText("A")], Any[LlmText("B")]]
        end

        @testset "a cancel while the session starts sends no prompt" begin
            assistant = Ref{Any}(nothing)
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Late."), LlmTextStop()]];
                on_start = _ -> timedwait(() -> assistant[].agent_session.is_cancelled, 10.0; pollint = 0.01))
            a = _make_agent_assistant(connection)
            assistant[] = a
            _submit_to_agent!(a, "Slow"; wait = false)
            @test is_external_agent_turn_running(a)
            evaluate_operation((document = a,), CancelAssistantTurnOperation(a))
            _wait_for_idle(a)
            @test isempty(connection.prompts)
            connection.on_start = nothing
            _submit_to_agent!(a, "Next")
            @test only(connection.prompts) == Any[LlmText("Next")]
        end

        @testset "an update can name a tool that an earlier one left unnamed" begin
            connection = ScriptedAgentConnection([Any[
                AgentToolCallUpdate("t1"; status = :in_progress),
                AgentToolCallUpdate("t1"; name = "mcp__projectured__execute_julia_code",
                                    input = Dict{String,Any}("code" => "2 + 2"))]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Add")
            form = only(part.content for part in collect(collect(a.conversation.turns)[end].parts)
                        if part.content isa EvaluatorForm)
            @test form.tool_name == "execute_julia_code"
            @test form.source == "2 + 2"
        end

        @testset "a list or a dictionary in the input of a tool is JSON text" begin
            todo(content, status) =
                Dict{String,Any}("content" => content, "status" => status)
            todos = Any[todo("Read the code", "completed"),
                        todo("Write the code", "pending")]
            input = Dict{String,Any}("todos" => todos, "files" => Any["a.jl", 2, nothing],
                                     "note" => "say \"hi\"")
            connection = ScriptedAgentConnection([Any[
                AgentToolCallUpdate("t1"; name = "TodoWrite", status = :completed,
                                    input = input)]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Plan")
            parts = collect(collect(a.conversation.turns)[end].parts)
            form = only(part.content for part in parts if part.content isa EvaluatorForm)
            # A short value is one line; a long one is indented over several lines.
            @test get_flat_string(form.form) == """
                files: ["a.jl", 2, null]
                note: say "hi"
                todos: [
                  {
                    "content": "Read the code",
                    "status": "completed"
                  },
                  {
                    "content": "Write the code",
                    "status": "pending"
                  }
                ]"""
        end

        @testset "a reset of the conversation stops the agent" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            @test a.agent_session_id == "scripted-session-1"
            conversation = a.conversation
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test a.agent_session === nothing
            @test isempty(collect(a.conversation.turns))
            # The new conversation is no part of the old session.
            @test a.agent_session_id == "" && a.agent_session_directory == ""
            # An answer that comes for the old conversation keeps no session.
            AssistantModule._keep_agent_session!(a, conversation, ExternalAgentSession(connection; session_id = "old"))
            @test a.agent_session_id == ""
        end

        @testset "the options of the agent arrive at the open and change by a pick" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]];
                                                 options = make_scripted_agent_options())
            a = _make_agent_assistant(connection)
            @test isempty(a.agent_options)
            # A start with no message opens the session and shows the options.
            evaluate_operation((document = a,), StartExternalAgentOperation(a))
            @test timedwait(() -> length(a.agent_options) == 3, 10.0; pollint = 0.01) === :ok
            @test isempty(connection.prompts) && length(connection.sessions) == 1
            # A second start does nothing, and the first message uses the same session.
            evaluate_operation((document = a,), StartExternalAgentOperation(a))
            _submit_to_agent!(a, "Hello")
            @test length(connection.sessions) == 1
            @test only(connection.prompts) == Any[LlmText("Hello")]
            evaluate_operation((document = a,), SetAgentOptionOperation(a, "effort", "max"))
            @test timedwait(() -> a.agent_options[2].current_value == "max", 10.0; pollint = 0.01) === :ok
            @test connection.option_sets == ["effort" => "max"]
            # A reset forgets the options with the session.
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test isempty(a.agent_options)
        end

        @testset "a session starts in the mode of the assistant when the agent offers it" begin
            with_auto_mode(options) = AgentOption[option.category === :mode ?
                AgentOption(option.id, option.name, option.description, option.category, option.current_value,
                            vcat(option.values, AgentOptionValue("auto", "Auto", ""))) :
                option for option in options]
            turn = Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]
            connection = ScriptedAgentConnection([turn]; options = with_auto_mode(make_scripted_agent_options()))
            a = _make_agent_assistant(connection)
            @test a.agent_mode == DEFAULT_AGENT_MODE == "auto"
            _submit_to_agent!(a, "Hello")
            @test connection.option_sets == ["mode" => "auto"]
            @test only(connection.prompts) == Any[LlmText("Hello")]
            @test timedwait(() -> a.agent_options[3].current_value == "auto", 10.0; pollint = 0.01) === :ok
            # An agent that offers no mode "auto" keeps its own mode.
            connection = ScriptedAgentConnection([turn]; options = make_scripted_agent_options())
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            @test isempty(connection.option_sets) && length(connection.prompts) == 1
            # An empty mode leaves the mode to the agent.
            connection = ScriptedAgentConnection([turn]; options = with_auto_mode(make_scripted_agent_options()))
            a = Assistant(; backend = :acp, agent_session = ExternalAgentSession(connection), agent_mode = "")
            _submit_to_agent!(a, "Hello")
            @test isempty(connection.option_sets) && length(connection.prompts) == 1
        end

        @testset "an update of the options during a turn draws no part" begin
            options = make_scripted_agent_options()
            planned = AgentOption[option.id == "mode" ?
                AgentOption(option.id, option.name, option.description, option.category, "plan", option.values) :
                option for option in options]
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("I plan."), AgentOptionsUpdate(planned), LlmTextDelta(" Done."), LlmTextStop()]];
                options)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Plan")
            @test a.agent_options[3].current_value == "plan"
            parts = collect(collect(a.conversation.turns)[end].parts)
            @test length(parts) == 1
            @test occursin("I plan. Done.", AssistantModule._part_text(only(parts)))
        end

        @testset "the title and the usage of the session" begin
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("OK"),
                AgentUsageUpdate(36012, 1000000, nothing, ""),
                AgentSessionInfoUpdate("Reply with OK"),
                LlmTextDelta("."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            @test get_document_title(a) == "Assistant"
            _submit_to_agent!(a, "Reply with OK")
            @test a.agent_title == "Reply with OK"
            @test get_document_title(a) == "Reply with OK"
            @test format_agent_usage(a.agent_usage) == "36k / 1M"
            @test describe_agent_usage(a.agent_usage) == "The session uses 36k of the 1M tokens of its context."
            # The two updates draw no part, and the text stays one part.
            @test length(collect(collect(a.conversation.turns)[end].parts)) == 1
            @test format_agent_usage(AgentUsageUpdate(1500, 200000, 0.456, "USD")) == "2k / 200k · 0.46 USD"
            @test describe_agent_usage(AgentUsageUpdate(1500, 200000, 0.456, "USD")) ==
                  "The session uses 2k of the 200k tokens of its context. It has cost 0.46 USD."
            @test format_agent_usage(AgentUsageUpdate(10, 1_500_000, nothing, "")) == "10 / 1.5M"
            @test format_agent_usage(nothing) == "" && describe_agent_usage(nothing) === nothing
            # A reset forgets them with the session, and the tab is the assistant again.
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test a.agent_title == "" && a.agent_usage === nothing
            @test get_document_title(a) == "Assistant"
        end

        @testset "the commands of the agent show in a menu, and a pick writes one into the draft" begin
            connection = ScriptedAgentConnection([Any[
                AgentCommandsUpdate([AgentCommand("review", "Review the changes", "a branch"),
                                     AgentCommand("compact", "", "")]),
                LlmTextStart(), LlmTextDelta("Ready."), LlmTextStop()]];
                options = make_scripted_agent_options())
            a = _make_agent_assistant(connection)
            bar = make_agent_option_bar(a)
            # The menu of the commands, before the sign-out, which an agent that
            # can not sign out does not show.
            commands, sign_out = collect(bar.elements)[(end - 1):end]
            @test string(commands.action.label) == "Commands"
            @test string(sign_out.action.label) == "Sign out" && !sign_out.visible
            @test !commands.visible && commands.submenu === nothing
            _submit_to_agent!(a, "Hello")
            @test [command.name for command in a.agent_commands] == ["review", "compact"]
            @test commands.visible
            items = collect(commands.submenu.elements)
            @test [string(item.action.label) for item in items] == ["/review", "/compact"]
            @test items[1].tooltip == "Review the changes"
            items[1].action.callback((document = a,))
            @test AssistantModule._text_to_string(collect(a.draft.parts)[end].content) == "/review "
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test isempty(a.agent_commands)
        end

        @testset "the option bar says the value that holds, and a pick sets another" begin
            connection = ScriptedAgentConnection(Any[]; options = make_scripted_agent_options())
            a = _make_agent_assistant(connection)
            bar = make_agent_option_bar(a)
            # The three option menus; the menu of the commands and the sign-out
            # are the last items.
            items = collect(bar.elements)[1:3]
            label(item) = string(item.action.label)
            @test label(items[1]) == "Start the agent"
            @test [item.visible for item in items] == [true, false, false]
            @test items[1].submenu === nothing
            # The first item starts the agent when there are no options.
            items[1].action.callback((document = a,))
            @test timedwait(() -> length(a.agent_options) == 3, 10.0; pollint = 0.01) === :ok
            @test [label(item) for item in items] == ["Model: Opus 5.5", "Effort: High", "Mode: Manual"]
            @test all(item -> item.visible, items)
            effort = collect(items[2].submenu.elements)
            @test [label(item) for item in effort] == ["✓ High", "   Max"]
            effort[2].action.callback((document = a,))
            @test timedwait(() -> label(items[2]) == "Effort: Max", 10.0; pollint = 0.01) === :ok
            @test connection.option_sets == ["effort" => "max"]
        end

        @testset "a question of the agent waits for the person" begin
            options = [AgentPermissionOption("allow", "Allow", :allow_once),
                       AgentPermissionOption("reject", "Reject", :reject_once)]
            connection = ScriptedAgentConnection([Any[make_scripted_permission_step(
                AgentToolCallUpdate("t1"; title = "mcp__projectured__execute_julia_code"), options)]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Edit"; wait = false)
            request = _wait_for_permission_request(a)
            @test request.title == "The agent asks to run: execute_julia_code"
            @test is_permission_request_open(request)
            answer_permission_request!(request, "allow")
            _wait_for_idle(a)
            @test connection.answers == Any["allow"]
            @test request.answer == "Allow"
            @test !is_permission_request_open(request)
            # A second answer does nothing.
            answer_permission_request!(request, "reject")
            @test request.answer == "Allow"
        end

        @testset "Escape cancels the turn and the question that waits" begin
            connection = ScriptedAgentConnection([Any[make_scripted_permission_step(
                AgentToolCallUpdate("t1"; title = "Edit a.jl"),
                [AgentPermissionOption("allow", "Allow", :allow_once)])]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Edit"; wait = false)
            request = _wait_for_permission_request(a)
            @test is_external_agent_turn_running(a)
            button = make_assistant_stop_button(a)
            @test button.enabled
            escape = read_intent(AssistantToWidgetCard(), (input = a,), KeyDown(:escape, ModifierKeys(); time = 0.0))
            @test escape isa CancelAssistantTurnOperation
            evaluate_operation((document = a,), escape)
            _wait_for_idle(a)
            @test connection.answers == Any[nothing]
            @test request.answer == "Cancelled"
            last_turn = collect(a.conversation.turns)[end]
            @test last_turn.stop_reason === :cancelled
            @test !button.enabled
            # With no turn that runs, Escape is the composer's again.
            @test !(read_intent(AssistantToWidgetCard(), (input = a,),
                                KeyDown(:escape, ModifierKeys(); time = 0.0)) isa CancelAssistantTurnOperation)
        end

        @testset "a permission request draws one button for each answer" begin
            request = ConversationPermissionRequest("Run it?",
                [AgentPermissionOption("allow", "Allow", :allow_once),
                 AgentPermissionOption("reject", "Reject", :reject_once)]; reply = _ -> nothing)
            card = ConversationModule._permission_card(ConversationPartToWidget(), request)
            buttons = _collect_buttons(card)
            @test length(buttons) == 2
            @test all(button -> button.enabled, buttons)
            answer_permission_request!(request, "reject")
            @test !any(button -> button.enabled, buttons)
            @test request.answer == "Reject"
            # A reply that comes after a cancel shows as cancelled.
            late = ConversationPermissionRequest("Run it?",
                [AgentPermissionOption("allow", "Allow", :allow_once)]; reply = _ -> false)
            answer_permission_request!(late, "allow")
            @test late.answer == "Cancelled"
            # The copy of a request can not be answered.
            duplicate = copy_document(DuplicatePolicy(), ConversationPermissionRequest("Run it?",
                [AgentPermissionOption("allow", "Allow", :allow_once)]; reply = _ -> nothing))
            @test !is_permission_request_open(duplicate)
        end

        @testset "the duplicate forks the session of the agent when its tab opens" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]];
                                                 can_fork = true, options = make_scripted_agent_options())
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            evaluate_operation((document = a,), SetAgentOptionOperation(a, "effort", "max"))
            @test timedwait(() -> a.agent_options[2].current_value == "max", 10.0; pollint = 0.01) === :ok
            fork = copy_document(DuplicatePolicy(), a)
            @test fork.agent_session === nothing
            @test fork.agent_session_id == "" && fork.agent_session_directory == ""
            @test fork.agent_command == a.agent_command
            source = fork.agent_fork
            @test (source.session_id, source.directory, source.turn_count) == ("scripted-session-1", pwd(), 1)
            @test [option.current_value for option in source.options] == ["opus", "max", "default"]
            # The agent of the copy gets the history, so no note says otherwise.
            @test !any(turn -> occursin("does not have the history",
                                        join(AssistantModule._part_text.(collect(turn.parts)))),
                       collect(fork.conversation.turns))
            # The acquire, as the open of its tab makes it, forks the session at
            # once. A new session of the agent starts with the default options,
            # and the fork takes the effort of its source; the mode follows
            # `agent_mode`, which this agent does not offer.
            connection.options = make_scripted_agent_options()
            fork.agent_session = ExternalAgentSession(connection)
            evaluate_operation((document = fork,), AcquireDocumentOperation(fork))
            @test timedwait(() -> fork.agent_session.session_id == "scripted-fork-2", 10.0; pollint = 0.01) === :ok
            @test connection.sessions[2].fork_session_id == "scripted-session-1"
            @test connection.sessions[2].directory == pwd()
            @test timedwait(() -> length(connection.option_sets) == 2, 10.0; pollint = 0.01) === :ok
            @test connection.option_sets == ["effort" => "max", "effort" => "max"]
            @test length(connection.prompts) == 1
            # The undo of the duplicate releases the copy and stops its agent.
            # Before its first answer, the agent keeps no session of the fork, so
            # the redo forks the source again.
            evaluate_operation((document = fork,), ReleaseDocumentOperation(fork))
            @test fork.agent_session === nothing
            @test fork.agent_session_id == "" && fork.agent_fork === source
            fork.agent_session = ExternalAgentSession(connection)
            evaluate_operation((document = fork,), AcquireDocumentOperation(fork))
            @test timedwait(() -> fork.agent_session.session_id == "scripted-fork-3", 10.0; pollint = 0.01) === :ok
            @test connection.sessions[3].fork_session_id == "scripted-session-1"
            # The next prompt of the copy sends only the new message, and the
            # answer makes the fork a session of its own.
            _submit_to_agent!(fork, "Second")
            @test connection.prompts[end] == [LlmText("Second")]
            @test (fork.agent_session_id, fork.agent_session_turn_count) == ("scripted-fork-3", 3)
            @test fork.agent_fork === nothing
            # The original keeps its session, and its copy of a copy forks the fork.
            @test a.agent_session_id == "scripted-session-1"
            @test copy_document(DuplicatePolicy(), fork).agent_fork.session_id == "scripted-fork-3"
        end

        @testset "a duplicate whose agent can not fork starts a new session with a note" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Three."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            has_note(assistant) = any(turn -> any(part -> AssistantModule._part_text(part) ==
                                                          AssistantModule.FORK_AGENT_NOTE, collect(turn.parts)),
                                      collect(assistant.conversation.turns))
            # A copy that is not acquired forks at its first message.
            fork = copy_document(DuplicatePolicy(), a)
            fork.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(fork, "Second")
            @test connection.sessions[2].fork_session_id == "" && connection.sessions[2].session_id == ""
            @test connection.prompts[end] == [LlmText("Second")]
            @test timedwait(() -> has_note(fork), 10.0; pollint = 0.01) === :ok
            @test fork.agent_fork === nothing
            # A source whose folder is gone gives a new session with the note too.
            lost = copy_document(DuplicatePolicy(), a)
            lost.agent_fork = AssistantModule.AgentSessionFork("scripted-session-1", joinpath(pwd(), "no-such-folder"),
                                                               1, AgentOption[])
            lost.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(lost, "Third")
            @test connection.sessions[3].directory == pwd()
            @test timedwait(() -> has_note(lost), 10.0; pollint = 0.01) === :ok
            @test !has_note(a)
        end

        @testset "a duplicate of an assistant that answers starts a new session with a note" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]];
                                                 can_fork = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            # The answer that streams stays with the original.
            push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("Go on")]))
            push!(a.conversation.turns, ConversationTurn(:assistant, [ConversationPart("Half an answer")]))
            a.status = :streaming
            fork = copy_document(DuplicatePolicy(), a)
            a.status = :idle
            @test fork.agent_fork === nothing
            turns = collect(fork.conversation.turns)
            @test length(turns) == 4
            @test AssistantModule._part_text(only(turns[3].parts)) == "Go on"
            @test AssistantModule._part_text(only(turns[4].parts)) == AssistantModule.FORK_DURING_ANSWER_NOTE
        end

        @testset "a release, as the close of its tab makes, stops the agent" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            @test a.agent_session isa ExternalAgentSession
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            @test a.agent_session === nothing
            # A document that holds nothing outside the tree releases nothing.
            @test release_document!(nothing, Assistant()) === nothing
        end

        @testset "the end of a window stops the agent of each open session, and waits for the stop" begin
            connection = ScriptedAgentConnection([Any[]])
            server = _SlowStopAgentServer(false)
            a = Assistant(; backend = :acp)
            session = ExternalAgentSession(connection; tool_server = server)
            a.agent_session = session
            editor = build_editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
                                  window = false, tabs = false, appearance = false, settings = false)
            # The queue of the session joins the feed of the window, as an open session does.
            queue = AgentEventQueue()
            session.events = queue
            AssistantModule._register_agent_event_queue!(editor, a, session, queue)
            foreach(step -> step(editor), editor.stop_steps)
            @test a.agent_session === nothing && session.is_stopped
            # The server takes a time to stop, and the end of the window waited for it.
            @test server.is_stopped
            @test istaskdone(session.stop_task)
        end

        @testset "after a release, the next turn resumes the session" begin
            connection = ScriptedAgentConnection([
                Any[AgentSessionInfoUpdate("Hello"), LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]]; can_resume = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            @test (a.agent_session_id, a.agent_session_directory) == ("scripted-session-1", pwd())
            @test a.agent_session_turn_count == 1
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            # The stop keeps the session, and its title stays on the tab.
            @test a.agent_session === nothing
            @test a.agent_session_id == "scripted-session-1" && a.agent_title == "Hello"
            # The agent starts again, as the next turn of an editor starts it.
            a.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(a, "Again")
            @test connection.sessions[2].session_id == "scripted-session-1"
            @test connection.sessions[2].directory == pwd()
            @test a.agent_session_id == "scripted-session-1"
            @test !any(turn -> occursin("does not have the history",
                                        join(AssistantModule._part_text.(collect(turn.parts)))),
                       collect(a.conversation.turns))
            @test connection.prompts[2] == [LlmText("Again")]
        end

        @testset "a resume sends the turns that the kept session did not see" begin
            connection = ScriptedAgentConnection([
                Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[(connection, on_event) -> error("The agent stopped.")],
                Any[LlmTextStart(), LlmTextDelta("Three."), LlmTextStop()]]; can_resume = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "A")
            _submit_to_agent!(a, "B")
            @test a.status === :error
            @test a.agent_session_turn_count == 1
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            a.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(a, "C")
            @test connection.sessions[2].session_id == "scripted-session-1"
            @test connection.prompts[end] == [LlmText("B"), LlmText("C")]
        end

        @testset "a resumed session whose first prompt fails does not resume again" begin
            connection = ScriptedAgentConnection([
                Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[(connection, on_event) -> error("Claude Code ended before the end of the turn.")],
                Any[LlmTextStart(), LlmTextDelta("Three."), LlmTextStop()]]; can_resume = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            a.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(a, "Again")
            @test a.status === :error
            @test connection.sessions[2].session_id == "scripted-session-1"
            # The agent did not answer in the resumed session, so it does not have it.
            @test a.agent_session_id == "scripted-session-1" && a.agent_session_directory == ""
            _submit_to_agent!(a, "Third")
            @test connection.sessions[3].session_id == ""
            @test a.agent_session_id == "scripted-session-3"
            @test any(turn -> any(part -> AssistantModule._part_text(part) == AssistantModule.NEW_SESSION_AGENT_NOTE,
                                  collect(turn.parts)),
                      collect(a.conversation.turns))
        end

        @testset "an agent that can not resume opens a new session, and a note says so" begin
            connection = ScriptedAgentConnection([
                Any[AgentSessionInfoUpdate("Hello"), LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Hello")
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            a.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(a, "Again")
            @test connection.sessions[2].session_id == "scripted-session-1"
            @test a.agent_session_id == "scripted-session-2"
            # The title of the old session goes, and the note comes before the answer.
            @test a.agent_title == ""
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns[end-2:end]] == [:user, :assistant, :assistant]
            @test AssistantModule._part_text(only(turns[end-1].parts)) == AssistantModule.NEW_SESSION_AGENT_NOTE
            # A session whose folder is gone does not resume, and a new one opens.
            evaluate_operation((document = a,), ReleaseDocumentOperation(a))
            a.agent_session_directory = joinpath(pwd(), "no-such-folder")
            a.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(a, "Third")
            @test connection.sessions[3].session_id == ""
            @test connection.sessions[3].directory == pwd()
        end

        @testset "the document of an evaluation through the MCP server of the editor is the live result" begin
            tools = ToolSet()
            made = TextBlock(TextLine(TextString("made")))
            connection = ScriptedAgentConnection([Any[
                AgentToolCallUpdate("t1"; name = "mcp__projectured__execute_julia_code", status = :pending,
                                    input = Dict{String,Any}("code" => "make()")),
                # The MCP server of the editor keeps the document under the id of the call.
                (connection, on_event) -> keep_tool_call_value!(tools, "t1", made),
                AgentToolCallUpdate("t1"; status = :completed, output = "made"),
                AgentToolCallUpdate("t1"; status = :completed, output = "made"),
                AgentToolCallUpdate("t2"; name = "mcp__projectured__execute_julia_code", status = :pending,
                                    input = Dict{String,Any}("code" => "1")),
                AgentToolCallUpdate("t2"; status = :completed, output = "1")]])
            a = _make_agent_assistant(connection)
            a.input.value = "Go"
            evaluate_operation((document = a, tools = tools), SubmitProseOperation(a))
            _wait_for_idle(a)
            live, plain = [part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                           if part.content isa EvaluatorForm]
            # The repeated output keeps the live result, and the text stays beside it.
            @test live.result === made && live.output == "made"
            @test plain.result isa TextBlock && plain.result !== made
            @test isempty(tools.call_values)
            # A save writes a result that its notation can not write as the text of the tool.
            form = EvaluatorForm(TextBlock(TextLine(TextString("make()"))); result = AgentTurnLiveResult(() -> 1),
                                 output = "made by the code", tool_name = "execute_julia_code")
            written = print_pred_text(form)
            @test occursin("made by the code", written)
            @test parse_pred_text(written).result isa TextBlock
        end

        @testset "the backend :acp without its package says so" begin
            a = Assistant(; backend = :acp)
            _submit_to_agent!(a, "Hello")
            @test a.status === :error
            text = AssistantModule._part_text(only(collect(a.conversation.turns)[end].parts))
            @test occursin("The backend :acp needs the package ProjecturedACP", text)
        end

        @testset "a save keeps no command, no session options and no mode" begin
            a = Assistant(; backend = :acp, agent_command = "my-agent --flag", agent_mode = "bypassPermissions")
            _, keywords = pred_arguments(a)
            @test (:backend => :acp) in keywords
            @test !any(pair -> first(pair) in (:agent_command, :agent_session_meta, :agent_mode), keywords)
            @test Assistant().agent_command == DEFAULT_AGENT_COMMAND
            @test occursin("\"display\": \"summarized\"", Assistant().agent_session_meta)
            # Without a kept session, the file keeps no conversation.
            @test !any(pair -> first(pair) === :conversation, last(pred_arguments(Assistant(; backend = :acp))))
        end

        @testset "a save keeps the conversation of a kept session, and the next turn after a load resumes it" begin
            input = Dict{String,Any}("code" => "1 + 1", "options" => Dict{String,Any}("a-b" => Any[1, 2.5, nothing, true]))
            connection = ScriptedAgentConnection([
                Any[LlmThinkingStart(), LlmThinkingDelta("I add."), LlmThinkingStop(),
                    LlmTextStart(), LlmTextDelta("Let me run it."), LlmTextStop(),
                    AgentToolCallUpdate("t1"; name = "mcp__projectured__execute_julia_code", title = "Run",
                                        kind = :execute, status = :pending, input),
                    AgentPlanUpdate([AgentPlanEntry("Add", :high, :in_progress)]),
                    make_scripted_permission_step(AgentToolCallUpdate("t2"; title = "mcp__projectured__execute_julia_code"),
                        [AgentPermissionOption("allow", "Allow", :allow_once),
                         AgentPermissionOption("reject", "Reject", :reject_once)]),
                    AgentToolCallUpdate("t1"; status = :completed, output = "2"),
                    AgentSessionInfoUpdate("Add two numbers"),
                    LlmTextStart(), LlmTextDelta("It is 2."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Again."), LlmTextStop()]]; can_resume = true)
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "What is 1 + 1?"; wait = false)
            answer_permission_request!(_wait_for_permission_request(a), "allow")
            _wait_for_idle(a)
            text = print_pred_text(a)
            loaded = parse_pred_text(text)
            @test loaded isa Assistant
            @test print_pred_text(loaded) == text
            @test (loaded.agent_session_id, loaded.agent_session_directory) == ("scripted-session-1", pwd())
            @test loaded.agent_session_turn_count == a.agent_session_turn_count
            @test get_document_title(loaded) == "Add two numbers"
            @test loaded.agent_session === nothing
            @test length(collect(loaded.conversation.turns)) == length(collect(a.conversation.turns))
            parts = [part.content for part in collect(collect(loaded.conversation.turns)[end].parts)]
            @test only(part for part in parts if part isa EvaluatorForm).input == input
            request = only(part for part in parts if part isa ConversationPermissionRequest)
            @test request.answer == "Allow" && !is_permission_request_open(request)
            # The next turn resumes the session, and the prompt holds only the new message.
            loaded.agent_session = ExternalAgentSession(connection)
            _submit_to_agent!(loaded, "Again")
            @test connection.sessions[end].session_id == "scripted-session-1"
            @test connection.prompts[end] == [LlmText("Again")]
        end
    end
end

# A result that the notation of a file can not write, as a live document of a
# session can be: a document that holds a function.
@document struct AgentTurnLiveResult
    run::Any
end

_make_agent_assistant(connection) =
    Assistant(; backend = :acp, agent_session = ExternalAgentSession(connection))

# An MCP server of an agent that takes a time to stop.
mutable struct _SlowStopAgentServer
    is_stopped::Bool
end

function AgentModule.stop_agent_server!(server::_SlowStopAgentServer)
    sleep(0.3)
    server.is_stopped = true
    nothing
end

# Submit `text` as a prose turn, with the assistant as its own editor, and wait
# for the turn to end unless `wait` is false.
function _submit_to_agent!(a::Assistant, text::AbstractString; wait::Bool = true)
    a.input.value = text
    evaluate_operation((document = a,), SubmitProseOperation(a))
    wait && _wait_for_idle(a)
    nothing
end

function _wait_for_idle(a::Assistant)
    @test timedwait(() -> a.status !== :streaming, 10.0; pollint = 0.01) === :ok
end

function _wait_for_permission_request(a::Assistant)
    find_request() = (turns = collect(a.conversation.turns);
                      isempty(turns) ? nothing :
                      findfirst(part -> part.content isa ConversationPermissionRequest, collect(turns[end].parts)))
    @test timedwait(() -> find_request() !== nothing, 10.0; pollint = 0.01) === :ok
    collect(collect(a.conversation.turns)[end].parts)[find_request()].content
end

# The buttons of a widget tree, in order.
function _collect_buttons(node, found = Any[])
    node isa WidgetButton && push!(found, node)
    for name in (:content, :title, :children)
        hasproperty(node, name) || continue
        child = getproperty(node, name)
        child isa AbstractVector || child isa CellVector ?
            foreach(item -> _collect_buttons(item, found), collect(child)) :
            _collect_buttons(child, found)
    end
    found
end
