# The connection against a fake agent in this process: the agreement on the
# protocol, a session with the MCP server of the editor, a prompt whose updates
# arrive as kernel events, the queue of the events between two prompts, a
# permission request that a person answers or a cancel ends, the requests that
# the client refuses, and the work of an agent: its subagents, its plans, its
# background tasks and the process of a session.

# Wait at most five seconds for `condition`, and answer whether it holds.
_wait_until(condition) = timedwait(condition, 5.0; pollint = 0.01) === :ok

function _make_fake_agent(extra = Dict{String,Function}())
    FakeAcpAgent(merge(make_fake_handlers(), extra))
end

# The ids of the subagents that an event comes through, from the outside in, and
# the event inside them.
function _unwrap_subagent_event(event)
    ids = String[]
    while event isa AgentSubagentUpdate && event.event !== nothing
        push!(ids, event.id)
        event = event.event
    end
    ids, event
end

function test_acp_connection()
    @testset "an ACP connection" begin
        @testset "the client and the agent agree on version 1" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            initialize = only(get_received(agent, "initialize"))["params"]
            @test initialize["protocolVersion"] == 1
            @test initialize["clientCapabilities"]["fs"] ==
                  Dict{String,Any}("readTextFile" => false, "writeTextFile" => false)
            @test initialize["clientCapabilities"]["terminal"] == false
            @test initialize["clientCapabilities"]["elicitation"]["form"] == Dict{String,Any}()
            # The client takes the work of an agent: its subagents, its plans with
            # an id, its notices, its compactions and its background tasks.
            @test initialize["clientCapabilities"]["subagents"] == Dict{String,Any}()
            @test initialize["clientCapabilities"]["plan"] == Dict{String,Any}()
            @test initialize["clientCapabilities"]["session"] ==
                  Dict{String,Any}("notices" => Dict{String,Any}(), "compaction" => Dict{String,Any}())
            @test initialize["clientCapabilities"]["_meta"] == Dict{String,Any}("backgroundTasks" => Dict{String,Any}())
            @test initialize["clientInfo"]["name"] == "projectured"
            @test connection.agent_info.title == "Fake Agent"
            @test connection.agent_capabilities.session_capabilities.close !== nothing
            stop_agent_connection!(connection)
            @test connection.transport === nothing
        end

        @testset "an agent of another version is refused" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT, Dict("protocolVersion" => 2))))
            message = try
                make_fake_connection(agent)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("ACP version 2", message)
        end

        @testset "a session names the MCP server, its headers and the _meta" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent;
                session_meta = Dict("claudeCode" => Dict("options" => Dict("settings" => Dict()))))
            session_id = open_agent_session!(connection; directory = "/work",
                mcp_servers = [(name = "projectured", url = "http://127.0.0.1:4000/mcp",
                                headers = ["Authorization" => "Bearer secret"])])
            @test session_id == "session-1"
            params = only(get_received(agent, "session/new"))["params"]
            @test params["cwd"] == "/work"
            @test params["mcpServers"] == Any[Dict{String,Any}(
                "type" => "http", "name" => "projectured", "url" => "http://127.0.0.1:4000/mcp",
                "headers" => Any[Dict{String,Any}("name" => "Authorization", "value" => "Bearer secret")])]
            @test haskey(params["_meta"], "claudeCode")
            stop_agent_connection!(connection)
        end

        @testset "the _meta of a session can be a JSON text" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent;
                session_meta = """{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}""")
            open_agent_session!(connection)
            meta = only(get_received(agent, "session/new"))["params"]["_meta"]
            @test meta["claudeCode"]["options"]["thinking"]["display"] == "summarized"
            stop_agent_connection!(connection)
            empty = make_fake_connection(_make_fake_agent(); session_meta = "  ")
            @test isempty(empty.session_meta)
            stop_agent_connection!(empty)
            @test_throws ErrorException make_agent_connection(:acp; session_meta = "[1, 2]")
            @test_throws ErrorException make_agent_connection(:acp; session_meta = "{not json")
        end

        @testset "the instructions of a session join its _meta, beside its options" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent;
                session_meta = """{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}""")
            open_agent_session!(connection; instructions = "You run inside the editor.")
            options = only(get_received(agent, "session/new"))["params"]["_meta"]["claudeCode"]["options"]
            @test options["thinking"]["display"] == "summarized"
            @test options["systemPrompt"] == Dict{String,Any}("type" => "preset", "preset" => "claude_code",
                                                              "append" => "You run inside the editor.")
            # The setting of the connection keeps no instructions.
            @test !haskey(connection.session_meta["claudeCode"]["options"], "systemPrompt")
            stop_agent_connection!(connection)
            # Without a `_meta`, the instructions make one.
            bare = _make_fake_agent()
            connection = make_fake_connection(bare)
            open_agent_session!(connection; instructions = "Host.")
            @test only(get_received(bare, "session/new"))["params"]["_meta"]["claudeCode"]["options"]["systemPrompt"]["append"] == "Host."
            stop_agent_connection!(connection)
        end

        @testset "a kept session resumes, and a session that the agent refuses opens anew" begin
            # The agent resumes the session, in its folder and with the instructions.
            agent = _make_fake_agent(Dict{String,Function}(
                "session/resume" => (agent, params) -> Dict("configOptions" => FAKE_CONFIG_OPTIONS)))
            connection = make_fake_connection(agent)
            events = Any[]
            @test open_agent_session!(connection; directory = "/work", session_id = "session-9",
                                      instructions = "Host.", on_event = event -> push!(events, event)) == "session-9"
            params = only(get_received(agent, "session/resume"))["params"]
            @test (params["sessionId"], params["cwd"]) == ("session-9", "/work")
            @test params["_meta"]["claudeCode"]["options"]["systemPrompt"]["append"] == "Host."
            @test isempty(get_received(agent, "session/new"))
            @test only(events) isa AgentOptionsUpdate
            stop_agent_connection!(connection)
            # An agent that refuses the resume opens a new session in its place.
            refusing = _make_fake_agent()
            connection = make_fake_connection(refusing)
            @test open_agent_session!(connection; directory = "/work", session_id = "session-9") == "session-1"
            @test length(get_received(refusing, "session/resume")) == 1
            @test only(get_received(refusing, "session/new"))["params"]["cwd"] == "/work"
            stop_agent_connection!(connection)
            # An agent that offers no resume gets no request for one.
            plain = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT, Dict("agentCapabilities" => Dict(
                    "sessionCapabilities" => Dict("close" => Dict()))))))
            connection = make_fake_connection(plain)
            @test open_agent_session!(connection; session_id = "session-9") == "session-1"
            @test isempty(get_received(plain, "session/resume"))
            stop_agent_connection!(connection)
            # A sign-in that the resume needs is no reason for a new session.
            signed_out = _make_fake_agent(Dict{String,Function}(
                "session/resume" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required"))))
            connection = make_fake_connection(signed_out)
            @test_throws AgentSignInException open_agent_session!(connection; session_id = "session-9")
            @test isempty(get_received(signed_out, "session/new"))
            stop_agent_connection!(connection)
        end

        @testset "the options of a session at the open, at a set, and in an update" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/set_config_option" => function (agent, params)
                    options = deepcopy(FAKE_CONFIG_OPTIONS)
                    only(o for o in options if o["id"] == params["configId"])["currentValue"] = params["value"]
                    Dict("configOptions" => options)
                end,
                "session/prompt" => function (agent, params)
                    session = params["sessionId"]
                    send_fake_update(agent, session, Dict("sessionUpdate" => "current_mode_update",
                                                          "currentModeId" => "plan"))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            events = Any[]
            session_id = open_agent_session!(connection; on_event = event -> push!(events, event))
            options = only(events).options
            @test [option.category for option in options] == [:mode, :model, :thought_level]
            model = options[2]
            @test (model.id, model.name, model.current_value) == ("model", "Model", "opus")
            # A group of values shows as values.
            @test [value.name for value in model.values] == ["Opus 5.5", "Sonnet 5.5"]
            empty!(events)
            set_agent_option!(connection, session_id, "effort", "max"; on_event = event -> push!(events, event))
            @test only(get_received(agent, "session/set_config_option"))["params"] ==
                  Dict{String,Any}("sessionId" => session_id, "configId" => "effort", "value" => "max")
            @test only(events).options[3].current_value == "max"
            # A new mode during a prompt reaches the prompt as all the options.
            prompt_events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Plan it")];
                               on_event = event -> push!(prompt_events, event))
            update = only(event for event in prompt_events if event isa AgentOptionsUpdate)
            @test update.options[1].current_value == "plan"
            @test update.options[3].current_value == "max"
            @test connection.session_options[session_id][1].current_value == "plan"
            stop_agent_connection!(connection)
        end

        @testset "the usage and the title of a session during a prompt" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    session = params["sessionId"]
                    send_fake_update(agent, session, Dict("sessionUpdate" => "usage_update",
                        "used" => 36012, "size" => 1000000, "cost" => Dict("amount" => 0.5, "currency" => "USD")))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "session_info_update",
                                                          "title" => "Reply with OK"))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Hi")]; on_event = event -> push!(events, event))
            usage = only(event for event in events if event isa AgentUsageUpdate)
            @test (usage.used, usage.size, usage.cost, usage.currency) == (36012, 1000000, 0.5, "USD")
            @test only(event for event in events if event isa AgentSessionInfoUpdate).title == "Reply with OK"
            stop_agent_connection!(connection)
        end

        @testset "the four kinds of the session and the text between two prompts reach the queue" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            queue = AgentEventQueue()
            session_id = open_agent_session!(connection; events = queue)
            send_agent_prompt!(connection, session_id, [LlmText("Hi")]; on_event = identity)
            @test isempty(take_agent_events!(queue))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "session_info_update", "title" => "Renamed"))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "available_commands_update",
                "availableCommands" => [Dict("name" => "review", "description" => "Review the changes",
                                             "input" => Dict("hint" => "a branch")),
                                        Dict("name" => "compact", "description" => "Compact the history")]))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "usage_update", "used" => 5, "size" => 10))
            options = deepcopy(FAKE_CONFIG_OPTIONS)
            options[1]["currentValue"] = "plan"
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "config_option_update",
                                                     "configOptions" => options))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "agent_message_chunk",
                                                     "content" => Dict("type" => "text", "text" => "late")))
            waiting = Any[]
            @test _wait_until(() -> (append!(waiting, take_agent_events!(queue)); length(waiting) >= 6))
            @test waiting[1] == AgentSessionInfoUpdate("Renamed")
            @test [(command.name, command.input_hint) for command in waiting[2].commands] ==
                  [("review", "a branch"), ("compact", "")]
            @test waiting[3] == AgentUsageUpdate(5, 10, nothing, "")
            @test waiting[4].options[1].current_value == "plan"
            @test waiting[5:6] == Any[LlmTextStart(), LlmTextDelta("late")]
            # The options stay current for the connection.
            @test connection.session_options[session_id][1].current_value == "plan"
            # The next prompt closes the block in the queue, and gets none of them.
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Again")]; on_event = event -> push!(events, event))
            @test take_agent_events!(queue) == Any[LlmTextStop()]
            @test isempty(events)
            stop_agent_connection!(connection)
        end

        @testset "a session with no queue drops the events between two prompts" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "session_info_update", "title" => "Lost"))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "agent_message_chunk",
                                                     "content" => Dict("type" => "text", "text" => "late")))
            options = deepcopy(FAKE_CONFIG_OPTIONS)
            options[1]["currentValue"] = "plan"
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "config_option_update",
                                                     "configOptions" => options))
            @test _wait_until(() -> connection.session_options[session_id][1].current_value == "plan")
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Again")]; on_event = event -> push!(events, event))
            @test isempty(events)
            @test isempty(connection.session_frames)
            stop_agent_connection!(connection)
        end

        @testset "an update that comes before the answer of an open reaches the queue" begin
            make_eager_agent() = _make_fake_agent(Dict{String,Function}(
                "session/new" => function (agent, params)
                    send_fake_update(agent, "session-1", Dict("sessionUpdate" => "available_commands_update",
                        "availableCommands" => [Dict("name" => "review", "description" => "Review")]))
                    Dict("sessionId" => "session-1", "configOptions" => FAKE_CONFIG_OPTIONS)
                end))
            connection = make_fake_connection(make_eager_agent())
            queue = AgentEventQueue()
            open_agent_session!(connection; events = queue)
            @test only(only(take_agent_events!(queue)).commands).name == "review"
            @test isempty(connection.opening_events) && connection.opening_count == 0
            stop_agent_connection!(connection)
            # Without a queue, the open drops them.
            connection = make_fake_connection(make_eager_agent())
            open_agent_session!(connection)
            @test isempty(connection.opening_events) && isempty(connection.session_frames)
            @test connection.session_queues == Dict{String,Union{Nothing,AgentEventQueue}}("session-1" => nothing)
            stop_agent_connection!(connection)
        end

        @testset "an agent that needs a sign-in says how" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/new" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required")),
                "session/prompt" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required"))))
            directory = mktempdir()
            connection = make_fake_connection(agent; command = ["fake-agent", "--stdio"],
                                              environment = Dict("FAKE_HOME" => "/h"), directory)
            # The client says that it runs a sign-in in a terminal.
            capabilities = only(get_received(agent, "initialize"))["params"]["clientCapabilities"]
            @test capabilities["auth"]["terminal"] === true
            failure = try
                open_agent_session!(connection)
            catch exception
                exception
            end
            @test failure isa AgentSignInException
            @test occursin("Fake Agent needs a sign-in. Run `fake /login` in the terminal.", sprint(showerror, failure))
            @test failure.agent_title == "Fake Agent"
            # The method runs the command of the agent with its arguments, in its folder.
            method = only(failure.methods)
            @test (method.id, method.name) == ("fake-login", "Log in")
            @test method.command.exec == ["fake-agent", "--stdio", "--cli"]
            @test method.command.dir == directory
            @test "FAKE_HOME=/h" in method.command.env
            # The built-in agent has no command line: its method `--login` runs the
            # sign-in command that its program runs.
            builtin = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT, Dict("authMethods" => [Dict(
                    "id" => "claude-login", "name" => "Sign in", "type" => "terminal", "args" => ["--login"])])),
                "session/new" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required"))))
            builtin_connection = make_fake_connection(builtin; directory)
            builtin_failure = try
                open_agent_session!(builtin_connection)
            catch exception
                exception
            end
            builtin_method = only(builtin_failure.methods)
            @test builtin_method.command.exec == ["claude", "auth", "login"]
            @test builtin_method.command.dir == directory
            stop_agent_connection!(builtin_connection)
            # A prompt that the agent refuses for a sign-in throws the same.
            @test_throws AgentSignInException send_agent_prompt!(connection, "session-1", [LlmText("Hi")];
                                                                 on_event = event -> nothing)
            stop_agent_connection!(connection)
        end

        @testset "an agent signs out when it says that it can" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT, Dict("agentCapabilities" => Dict(
                    "auth" => Dict("logout" => Dict())))),
                "logout" => (agent, params) -> Dict()))
            connection = make_fake_connection(agent)
            @test has_agent_sign_out(connection)
            @test sign_out_agent!(connection)
            @test length(get_received(agent, "logout")) == 1
            stop_agent_connection!(connection)
            @test !has_agent_sign_out(connection)
            # An agent that does not say so gets no request.
            plain = _make_fake_agent()
            connection = make_fake_connection(plain)
            @test !has_agent_sign_out(connection)
            @test !sign_out_agent!(connection)
            @test isempty(get_received(plain, "logout"))
            stop_agent_connection!(connection)
        end

        @testset "an agent whose initialize breaks the schema still starts" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> Dict(
                    "protocolVersion" => 1, "agentCapabilities" => [1], "authMethods" => [1],
                    "agentInfo" => Dict("title" => "Odd Agent")),
                "session/new" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required"))))
            connection = make_fake_connection(agent)
            @test !connection.agent_capabilities.load_session
            @test isempty(connection.auth_methods)
            message = try
                open_agent_session!(connection)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("Odd Agent needs a sign-in.", message)
            # An agent that lists no `close` gets no `session/close`.
            close_agent_session!(connection, "session-1")
            @test isempty(get_received(agent, "session/close"))
            stop_agent_connection!(connection)
        end

        @testset "the updates of a prompt arrive as events, in order" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    session = params["sessionId"]
                    send_fake_update(agent, session, Dict("sessionUpdate" => "agent_thought_chunk",
                                                          "content" => Dict("type" => "text", "text" => "think")))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "agent_message_chunk",
                                                          "content" => Dict("type" => "text", "text" => "Hi")))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "tool_call", "toolCallId" => "t1",
                                                          "title" => "Run", "kind" => "execute", "status" => "pending"))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "usage_update", "used" => 1, "size" => 2))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "agent_message_chunk",
                                                          "content" => Dict("type" => "text", "text" => "Done")))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            events = Any[]
            stop_reason = send_agent_prompt!(connection, session_id, [LlmText("Hello")];
                                             on_event = event -> push!(events, event))
            @test stop_reason === :end_turn
            prompt = only(get_received(agent, "session/prompt"))["params"]
            @test prompt["prompt"] == Any[Dict{String,Any}("type" => "text", "text" => "Hello")]
            @test events[1:6] == Any[LlmThinkingStart(), LlmThinkingDelta("think"), LlmThinkingStop(),
                                     LlmTextStart(), LlmTextDelta("Hi"), LlmTextStop()]
            @test events[7] isa AgentToolCallUpdate && events[7].id == "t1"
            @test events[8] == AgentUsageUpdate(1, 2, nothing, "")
            @test events[9:end] == Any[LlmTextStart(), LlmTextDelta("Done"), LlmTextStop()]
            @test isempty(connection.turns)
            stop_agent_connection!(connection)
        end

        @testset "a person answers a permission request" begin
            outcome = Ref{Any}(nothing)
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    answer = ask_fake_client(agent, "session/request_permission", Dict(
                        "sessionId" => params["sessionId"],
                        "toolCall" => Dict("toolCallId" => "t1", "title" => "Edit a.jl", "kind" => "edit"),
                        "options" => [Dict("optionId" => "allow", "name" => "Allow", "kind" => "allow_once"),
                                      Dict("optionId" => "reject", "name" => "Reject", "kind" => "reject_once")]))
                    outcome[] = answer["result"]["outcome"]
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            requests = AgentPermissionRequest[]
            on_event = function (event)
                event isa AgentPermissionRequest || return
                push!(requests, event)
                # A person answers later, from another task.
                @async event.reply("allow")
            end
            @test send_agent_prompt!(connection, session_id, [LlmText("Edit")]; on_event) === :end_turn
            request = only(requests)
            @test request.tool_call.title == "Edit a.jl"
            @test [option.kind for option in request.options] == [:allow_once, :reject_once]
            @test outcome[] == Dict{String,Any}("outcome" => "selected", "optionId" => "allow")
            # A second reply does nothing, and says so.
            @test request.reply("reject") == false
            @test outcome[]["optionId"] == "allow"
            stop_agent_connection!(connection)
        end

        @testset "a cancel answers the waiting request as cancelled" begin
            outcome = Ref{Any}(nothing)
            asked = Threads.Event()
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    answer = ask_fake_client(agent, "session/request_permission", Dict(
                        "sessionId" => params["sessionId"],
                        "toolCall" => Dict("toolCallId" => "t1"),
                        "options" => [Dict("optionId" => "allow", "name" => "Allow", "kind" => "allow_once")]))
                    outcome[] = answer["result"]["outcome"]
                    Dict("stopReason" => "cancelled")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            task = @async send_agent_prompt!(connection, session_id, [LlmText("Edit")];
                                             on_event = event -> event isa AgentPermissionRequest && notify(asked))
            wait(asked)
            cancel_agent_prompt!(connection, session_id)
            @test _wait_until(() -> istaskdone(task))
            @test fetch(task) === :cancelled
            @test outcome[] == Dict{String,Any}("outcome" => "cancelled")
            @test only(get_received(agent, "session/cancel"))["params"]["sessionId"] == session_id
            stop_agent_connection!(connection)
        end

        @testset "a person answers, declines, or a cancel ends a question form" begin
            schema = Dict(
                "type" => "object", "required" => ["question_1"],
                "properties" => Dict(
                    "question_2" => Dict("type" => "array", "title" => "Parts",
                                         "items" => Dict("anyOf" => [Dict("const" => "a", "title" => "A"),
                                                                     Dict("const" => "b", "title" => "B")])),
                    "question_1" => Dict("type" => "string", "title" => "Colour", "description" => "Which colour?",
                                         "oneOf" => [Dict("const" => "Red", "title" => "Red", "description" => "warm"),
                                                     Dict("const" => "Blue", "title" => "Blue")]),
                    "question_1_other" => Dict("type" => "string", "title" => "Other"),
                    "size" => Dict("type" => "integer"),
                    "plain" => Dict("type" => "string", "enum" => ["x", "y"]),
                    "odd" => Dict("type" => "object")))
            answers = Any[]
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    answer = ask_fake_client(agent, "elicitation/create", Dict(
                        "sessionId" => params["sessionId"], "mode" => "form",
                        "message" => "Answer, please.", "requestedSchema" => schema))
                    push!(answers, answer["result"])
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            requests = AgentQuestionRequest[]
            choose(values) = event -> event isa AgentQuestionRequest &&
                                      (push!(requests, event); @async event.reply(values))
            values = Dict{String,Any}("question_1" => "Red", "question_2" => ["a", "b"], "unknown" => 1)
            @test send_agent_prompt!(connection, session_id, [LlmText("Ask")]; on_event = choose(values)) === :end_turn
            request = only(requests)
            @test request.message == "Answer, please."
            # The fields in the order of their names, each of the kind that its schema says.
            @test [(field.name, field.kind) for field in request.fields] ==
                  [("odd", :text), ("plain", :choice), ("question_1", :choice), ("question_1_other", :text),
                   ("question_2", :choices), ("size", :integer)]
            colour = request.fields[3]
            @test (colour.title, colour.description, colour.is_required) == ("Colour", "Which colour?", true)
            @test [(option.value, option.name, option.description) for option in colour.options] ==
                  [("Red", "Red", "warm"), ("Blue", "Blue", "")]
            @test [option.value for option in request.fields[2].options] == ["x", "y"]
            @test only(answers) == Dict{String,Any}("action" => "accept",
                "content" => Dict{String,Any}("question_1" => "Red", "question_2" => ["a", "b"]))
            @test request.reply(Dict{String,Any}()) == false
            # A decline.
            @test send_agent_prompt!(connection, session_id, [LlmText("Ask")]; on_event = choose(nothing)) === :end_turn
            @test answers[2] == Dict{String,Any}("action" => "decline")
            # A cancel of the turn cancels the form that waits.
            asked = Threads.Event()
            task = @async send_agent_prompt!(connection, session_id, [LlmText("Ask")];
                                             on_event = event -> event isa AgentQuestionRequest && notify(asked))
            wait(asked)
            cancel_agent_prompt!(connection, session_id)
            @test _wait_until(() -> istaskdone(task))
            @test answers[3] == Dict{String,Any}("action" => "cancel")
            stop_agent_connection!(connection)
        end

        @testset "an agent that says so takes a prompt into the turn that runs" begin
            steered = Any[]
            agent = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT,
                    Dict("_meta" => Dict("steering" => Dict("supported" => true)))),
                "_session/steering" => function (agent, params)
                    push!(steered, params)
                    Dict("outcome" => length(steered) == 1 ? "injected" : "failed")
                end))
            connection = make_fake_connection(agent)
            @test has_agent_steering(connection)
            @test steer_agent_prompt!(connection, "session-1", [LlmText("Also this")])
            @test steered[1]["sessionId"] == "session-1"
            @test steered[1]["prompt"] == Any[Dict{String,Any}("type" => "text", "text" => "Also this")]
            # An outcome that is not a delivery is a prompt that the agent did not take.
            @test !steer_agent_prompt!(connection, "session-1", [LlmText("Again")])
            stop_agent_connection!(connection)
            @test !has_agent_steering(connection)
            # An agent that does not say so gets no request.
            plain = _make_fake_agent()
            connection = make_fake_connection(plain)
            @test !has_agent_steering(connection)
            @test !steer_agent_prompt!(connection, "session-1", [LlmText("x")])
            @test isempty(get_received(plain, "_session/steering"))
            stop_agent_connection!(connection)
        end

        @testset "the agent withdraws a request that waits" begin
            outcome = Ref{Any}(nothing)
            requests = AgentPermissionRequest[]
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    asked = @async ask_fake_client(agent, "session/request_permission", Dict(
                        "sessionId" => params["sessionId"],
                        "toolCall" => Dict("toolCallId" => "t1"),
                        "options" => [Dict("optionId" => "allow", "name" => "Allow", "kind" => "allow_once")]))
                    _wait_until(() -> !isempty(requests))
                    send_fake_message(agent, Dict("jsonrpc" => "2.0", "method" => "\$/cancel_request",
                                                  "params" => Dict("requestId" => agent.next_id)))
                    outcome[] = fetch(asked)["result"]["outcome"]
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            send_agent_prompt!(connection, session_id, [LlmText("Edit")];
                               on_event = event -> event isa AgentPermissionRequest && push!(requests, event))
            @test outcome[] == Dict{String,Any}("outcome" => "cancelled")
            @test only(requests).reply("allow") == false
            stop_agent_connection!(connection)
        end

        @testset "the client refuses a file and a terminal" begin
            answers = Dict{String,Any}()
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    for method in ("fs/read_text_file", "terminal/create")
                        answers[method] = ask_fake_client(agent, method, Dict("sessionId" => params["sessionId"]))
                    end
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            send_agent_prompt!(connection, session_id, [LlmText("Read")]; on_event = identity)
            for method in ("fs/read_text_file", "terminal/create")
                @test answers[method]["error"]["code"] == -32601
            end
            stop_agent_connection!(connection)
        end

        @testset "a session closes when the agent can close it" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            close_agent_session!(connection, session_id)
            @test only(get_received(agent, "session/close"))["params"]["sessionId"] == session_id
            stop_agent_connection!(connection)
        end

        @testset "a request waits no more when the agent ends" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => (agent, params) -> (close(agent.to_client); Dict("stopReason" => "end_turn"))))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            @test_throws ProtocolException send_agent_prompt!(connection, session_id, [LlmText("Hi")];
                                                                on_event = identity)
            stop_agent_connection!(connection)
        end

        @testset "a prompt takes text and pictures" begin
            picture = LlmImage("image/png", UInt8[1, 2, 3])
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            send_agent_prompt!(connection, session_id, [LlmText("See"), picture]; on_event = identity)
            prompt = only(get_received(agent, "session/prompt"))["params"]["prompt"]
            @test prompt[2] == Dict{String,Any}("type" => "image", "mimeType" => "image/png", "data" => "AQID")
            @test_throws ArgumentError send_agent_prompt!(connection, session_id,
                [LlmToolUse("t1", "x", Dict{String,Any}())]; on_event = identity)
            stop_agent_connection!(connection)
            # An agent that takes no images gets a line in place of the picture.
            agent = _make_fake_agent(Dict{String,Function}(
                "initialize" => (agent, params) -> merge(FAKE_INITIALIZE_RESULT,
                                                         Dict("agentCapabilities" => Dict()))))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            send_agent_prompt!(connection, session_id, [picture]; on_event = identity)
            block = only(only(get_received(agent, "session/prompt"))["params"]["prompt"])
            @test block["type"] == "text"
            @test occursin("picture is left out", block["text"])
            stop_agent_connection!(connection)
        end

        @testset "a child and a child of a child reach the prompt through their parents" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    session = params["sessionId"]
                    send_fake_update(agent, session, Dict("sessionUpdate" => "subagent_update",
                        "sessionId" => "child-1", "title" => "Explore", "description" => "general-purpose",
                        "state" => Dict("state" => "running"), "capabilities" => Dict("cancel" => Dict())))
                    send_fake_update(agent, "child-1", Dict("sessionUpdate" => "user_message_chunk",
                        "content" => Dict("type" => "text", "text" => "Find the bug")))
                    send_fake_update(agent, "child-1", Dict("sessionUpdate" => "agent_message_chunk",
                        "content" => Dict("type" => "text", "text" => "Looking"), "messageId" => "m1"))
                    send_fake_update(agent, "child-1", Dict("sessionUpdate" => "tool_call", "toolCallId" => "t1",
                        "title" => "Read a.jl", "kind" => "read", "status" => "pending"))
                    send_fake_update(agent, "child-1", Dict("sessionUpdate" => "subagent_update",
                        "sessionId" => "child-2", "title" => "Deeper", "state" => Dict("state" => "running")))
                    send_fake_update(agent, "child-2", Dict("sessionUpdate" => "agent_message_chunk",
                        "content" => Dict("type" => "text", "text" => "Deep")))
                    send_fake_update(agent, "child-1", Dict("sessionUpdate" => "subagent_update",
                        "sessionId" => "child-2", "state" => Dict("state" => "idle", "stopReason" => "end_turn",
                            "usage" => Dict("totalTokens" => 50, "inputTokens" => 40, "outputTokens" => 10))))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "subagent_update",
                        "sessionId" => "child-1", "state" => Dict("state" => "idle", "stopReason" => "end_turn"),
                        "_meta" => Dict("claudeCode" => Dict("usage" => Dict("totalTokens" => 1200,
                            "toolUses" => 3, "durationMs" => 4500), "lastToolName" => "Read",
                            "summary" => "Found it"))))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "agent_message_chunk",
                        "content" => Dict("type" => "text", "text" => "Done")))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            queue = AgentEventQueue()
            session_id = open_agent_session!(connection; events = queue)
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Look")]; on_event = event -> push!(events, event))
            unwrapped = [_unwrap_subagent_event(event) for event in events]
            @test [first(pair) for pair in unwrapped] == [
                String[], ["child-1"], ["child-1"], ["child-1"], ["child-1"], ["child-1"], ["child-1"],
                ["child-1", "child-2"], ["child-1", "child-2"], ["child-1", "child-2"], ["child-1"], String[],
                String[], String[], String[]]
            inner = [last(pair) for pair in unwrapped]
            started = inner[1]
            @test (started.id, started.title, started.description, started.state, started.can_cancel) ==
                  ("child-1", "Explore", "general-purpose", :running, true)
            # The prompt of the subagent is a message of the person.
            @test inner[2] isa LlmMessage && inner[2].role === :user && only(inner[2].content) == LlmText("Find the bug")
            # A child has its own frame: the tool call closes its block.
            @test inner[3:5] == Any[LlmTextStart(), LlmTextDelta("Looking"), LlmTextStop()]
            @test inner[6] isa AgentToolCallUpdate && (inner[6].id, inner[6].kind) == ("t1", :read)
            @test inner[7] isa AgentSubagentUpdate && (inner[7].id, inner[7].state) == ("child-2", :running)
            # The idle state of a child closes the block that it left open.
            @test inner[8:10] == Any[LlmTextStart(), LlmTextDelta("Deep"), LlmTextStop()]
            @test (inner[11].id, inner[11].state, inner[11].stop_reason, inner[11].token_count) ==
                  ("child-2", :idle, :end_turn, 50)
            idle = inner[12]
            @test (idle.id, idle.state, idle.stop_reason, idle.token_count, idle.tool_call_count, idle.duration) ==
                  ("child-1", :idle, :end_turn, 1200, 3, 4.5)
            @test (idle.last_tool, idle.summary) == ("Read", "Found it")
            # The text of the session has a frame of its own.
            @test inner[13:15] == Any[LlmTextStart(), LlmTextDelta("Done"), LlmTextStop()]
            @test connection.session_parents == Dict("child-1" => session_id, "child-2" => "child-1")
            # A child that works after the prompt reaches the queue of the session.
            send_fake_update(agent, "child-2", Dict("sessionUpdate" => "agent_message_chunk",
                "content" => Dict("type" => "text", "text" => "Later")))
            waiting = Any[]
            @test _wait_until(() -> (append!(waiting, take_agent_events!(queue)); length(waiting) >= 2))
            @test [_unwrap_subagent_event(event) for event in waiting] ==
                  [(["child-1", "child-2"], LlmTextStart()), (["child-1", "child-2"], LlmTextDelta("Later"))]
            # The close of the session forgets its children.
            close_agent_session!(connection, session_id)
            @test isempty(connection.session_parents) && isempty(connection.session_frames)
            stop_agent_connection!(connection)
        end

        @testset "two plans, a Markdown plan and a removal reach the prompt" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    session = params["sessionId"]
                    entry(content, status; meta...) = Dict("content" => content, "priority" => "medium",
                        "status" => status, "_meta" => Dict("claudeCode" => Dict(String(key) => value
                                                                                 for (key, value) in meta)))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "plan_update", "plan" => Dict(
                        "type" => "items", "planId" => "tasks", "entries" => [
                            entry("Read", "completed"; taskId = "1"),
                            entry("Write", "in_progress"; taskId = "2", activeForm = "Writing",
                                  description = "Write a.jl", blockedBy = ["1"])])))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "plan_update", "plan" => Dict(
                        "type" => "items", "planId" => "child-tasks", "entries" => [entry("Test", "pending")])))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "plan_update", "plan" => Dict(
                        "type" => "markdown", "planId" => "plan-mode", "content" => "# Plan\n\n1. Read")))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "plan_removed", "planId" => "child-tasks"))
                    send_fake_update(agent, session, Dict("sessionUpdate" => "plan", "entries" => [
                        Dict("content" => "Old", "priority" => "low", "status" => "pending")]))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Plan")]; on_event = event -> push!(events, event))
            plans = AgentPlanUpdate[event for event in events if event isa AgentPlanUpdate]
            @test [(plan.id, length(plan.entries), plan.markdown, plan.is_removed) for plan in plans] ==
                  [("tasks", 2, nothing, false), ("child-tasks", 1, nothing, false),
                   ("plan-mode", 0, "# Plan\n\n1. Read", false), ("child-tasks", 0, nothing, true),
                   ("", 1, nothing, false)]
            write = plans[1].entries[2]
            @test (write.id, write.active_title, write.description, write.blocked_by) ==
                  ("2", "Writing", "Write a.jl", ["1"])
            @test plans[1].entries[1].id == "1" && isempty(plans[1].entries[1].blocked_by)
            stop_agent_connection!(connection)
        end

        @testset "a background task, and its patch between two prompts, which reaches the queue" begin
            send_task(agent, params) = send_fake_message(agent, Dict("jsonrpc" => "2.0",
                "method" => "_session/background_task", "params" => params))
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    send_task(agent, Dict("sessionId" => params["sessionId"], "taskId" => "task-1",
                        "kind" => "local_bash", "title" => "sleep 10", "status" => "running",
                        "startTime" => 1_700_000_000_000, "canStop" => true, "toolCallId" => "t1"))
                    Dict("stopReason" => "end_turn")
                end))
            connection = make_fake_connection(agent)
            queue = AgentEventQueue()
            session_id = open_agent_session!(connection; events = queue)
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Sleep")]; on_event = event -> push!(events, event))
            started = only(events)
            @test started isa AgentBackgroundTaskUpdate
            @test (started.id, started.kind, started.title, started.status, started.start_time, started.can_stop) ==
                  ("task-1", :local_bash, "sleep 10", :running, 1.7e9, true)
            # The task ends after the prompt: a patch with the keys that changed.
            send_task(agent, Dict("sessionId" => session_id, "taskId" => "task-1", "status" => "completed",
                                  "endTime" => 1_700_000_010_000, "canStop" => false,
                                  "outputUri" => "file:///tmp/task-1.output"))
            waiting = Any[]
            @test _wait_until(() -> (append!(waiting, take_agent_events!(queue)); !isempty(waiting)))
            ended = only(waiting)
            @test (ended.id, ended.status, ended.end_time, ended.can_stop, ended.output_uri) ==
                  ("task-1", :completed, 1.70000001e9, false, "file:///tmp/task-1.output")
            @test ended.kind === nothing && ended.title === nothing && ended.start_time === nothing
            stop_agent_connection!(connection)
        end

        @testset "a stop of a background task, and a cancel of a child" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "_session/stop_background_task" => (agent, params) -> params["taskId"] == "task-1" ? Dict() :
                    throw(ProtocolException(-32602, "No background task `$(params["taskId"])` runs."))))
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            @test stop_agent_background_task!(connection, session_id, "task-1") === true
            @test stop_agent_background_task!(connection, session_id, "task-9") === false
            @test [message["params"] for message in get_received(agent, "_session/stop_background_task")] ==
                  [Dict{String,Any}("sessionId" => session_id, "taskId" => "task-1"),
                   Dict{String,Any}("sessionId" => session_id, "taskId" => "task-9")]
            # A cancel of a child is a `session/cancel` of the child session.
            @test cancel_agent_subagent!(connection, session_id, "child-1") === nothing
            @test _wait_until(() -> !isempty(get_received(agent, "session/cancel")))
            @test only(get_received(agent, "session/cancel"))["params"]["sessionId"] == "child-1"
            stop_agent_connection!(connection)
        end

        @testset "the process id of a session comes from _meta" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/prompt" => function (agent, params)
                    send_fake_update(agent, params["sessionId"], Dict("sessionUpdate" => "session_info_update",
                                                                      "_meta" => Dict("processId" => 4242)))
                    Dict("stopReason" => "end_turn")
                end))
            # The command of the agent here talks on streams and has no process, so
            # only `_meta` names one.
            connection = make_fake_connection(agent; command = ["fake-agent"])
            queue = AgentEventQueue()
            session_id = open_agent_session!(connection; events = queue)
            @test isempty(take_agent_events!(queue))
            events = Any[]
            send_agent_prompt!(connection, session_id, [LlmText("Hi")]; on_event = event -> push!(events, event))
            @test only(events) == AgentSessionInfoUpdate(nothing; process_id = 4242)
            stop_agent_connection!(connection)
        end
    end
end
