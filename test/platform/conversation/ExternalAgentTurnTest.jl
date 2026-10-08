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

        @testset "a reset of the conversation stops the agent" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "First")
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test a.agent_session === nothing
            @test isempty(collect(a.conversation.turns))
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
            @test format_agent_usage(a.agent_usage) == "Context: 36k of 1M tokens"
            # The two updates draw no part, and the text stays one part.
            @test length(collect(collect(a.conversation.turns)[end].parts)) == 1
            @test format_agent_usage(AgentUsageUpdate(1500, 200000, 0.456, "USD")) ==
                  "Context: 2k of 200k tokens · 0.46 USD"
            @test format_agent_usage(AgentUsageUpdate(10, 1_500_000, nothing, "")) ==
                  "Context: 10 of 1.5M tokens"
            @test format_agent_usage(nothing) == ""
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
            commands = collect(bar.elements)[end]
            @test string(commands.action.label) == "Commands"
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
            # The three option menus; the menu of the commands is the last item.
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

        @testset "the backend :acp without its package says so" begin
            a = Assistant(; backend = :acp)
            _submit_to_agent!(a, "Hello")
            @test a.status === :error
            text = AssistantModule._part_text(only(collect(a.conversation.turns)[end].parts))
            @test occursin("The backend :acp needs the package ProjecturedACP", text)
        end

        @testset "a save keeps no command and no session options" begin
            a = Assistant(; backend = :acp, agent_command = "my-agent --flag")
            _, keywords = pred_arguments(a)
            @test (:backend => :acp) in keywords
            @test !any(pair -> first(pair) in (:agent_command, :agent_session_meta), keywords)
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
