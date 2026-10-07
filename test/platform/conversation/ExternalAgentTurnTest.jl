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

        @testset "a second turn sends only what came since the last answer" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            _submit_to_agent!(a, "Second")
            @test connection.prompts == [Any[LlmText("First")], Any[LlmText("Second")]]
            @test length(connection.sessions) == 1
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
            escape = read_intent(AssistantToWidgetCard(), (input = a,), KeyDown(:escape, ModifierKeys(); time = 0.0))
            @test escape isa CancelAssistantTurnOperation
            evaluate_operation((document = a,), escape)
            _wait_for_idle(a)
            @test connection.answers == Any[nothing]
            @test request.answer == "Cancelled"
            last_turn = collect(a.conversation.turns)[end]
            @test last_turn.stop_reason === :cancelled
            # With no turn that runs, Escape is the composer's again.
            @test !(read_intent(AssistantToWidgetCard(), (input = a,),
                                KeyDown(:escape, ModifierKeys(); time = 0.0)) isa CancelAssistantTurnOperation)
        end

        @testset "a permission request draws one button for each answer" begin
            request = ConversationPermissionRequest("Run it?",
                [AgentPermissionOption("allow", "Allow", :allow_once),
                 AgentPermissionOption("reject", "Reject", :reject_once)]; reply = _ -> nothing)
            card = ConversationModule._permission_card(ConversationPartToWidget(), request,
                                                       ConversationPart(request))
            buttons = _collect_buttons(card)
            @test length(buttons) == 2
            @test all(button -> button.enabled, buttons)
            answer_permission_request!(request, "reject")
            @test !any(button -> button.enabled, buttons)
            @test request.answer == "Reject"
            # The copy of a request can not be answered.
            duplicate = copy_document(DuplicatePolicy(), ConversationPermissionRequest("Run it?",
                [AgentPermissionOption("allow", "Allow", :allow_once)]; reply = _ -> nothing))
            @test !is_permission_request_open(duplicate)
        end

        @testset "the duplicate starts a new session" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            fork = copy_document(DuplicatePolicy(), a)
            @test fork.agent_session === nothing
            @test fork.agent_command == a.agent_command
            note = collect(fork.conversation.turns)[end]
            @test note.role === :assistant
            @test AssistantModule._part_text(only(note.parts)) == AssistantModule.FORK_AGENT_NOTE
        end

        @testset "the backend :acp without its package says so" begin
            a = Assistant(; backend = :acp)
            _submit_to_agent!(a, "Hello")
            @test a.status === :error
            text = AssistantModule._part_text(only(collect(a.conversation.turns)[end].parts))
            @test occursin("The backend :acp needs the package ProjecturedACP", text)
        end

        @testset "the agent command is a setting that a save keeps" begin
            a = Assistant(; backend = :acp, agent_command = "my-agent --flag")
            _, keywords = pred_arguments(a)
            @test (:agent_command => "my-agent --flag") in keywords
            @test (:agent_session_meta => DEFAULT_AGENT_SESSION_META) in keywords
            @test Assistant().agent_command == DEFAULT_AGENT_COMMAND
            @test occursin("\"display\": \"summarized\"", Assistant().agent_session_meta)
        end
    end
end

_make_agent_assistant(connection) =
    Assistant(; backend = :acp, agent_session = ExternalAgentSession(connection))

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
