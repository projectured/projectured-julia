# The connection against a fake agent in this process: the agreement on the
# protocol, a session with the MCP server of the editor, a prompt whose updates
# arrive as kernel events, a permission request that a person answers or a
# cancel ends, and the requests that the client refuses.

# Wait at most five seconds for `condition`, and answer whether it holds.
_wait_until(condition) = timedwait(condition, 5.0; pollint = 0.01) === :ok

function _make_fake_agent(extra = Dict{String,Function}())
    FakeAcpAgent(merge(make_fake_handlers(), extra))
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
            @test_throws ErrorException open_agent_session!(connection; session_id = "session-9")
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

        @testset "the usage and the title of a session, during and between prompts" begin
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
            # A title between two prompts waits for the next one, and comes first.
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "session_info_update", "title" => "Renamed"))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "available_commands_update",
                "availableCommands" => [Dict("name" => "review", "description" => "Review the changes",
                                             "input" => Dict("hint" => "a branch")),
                                        Dict("name" => "compact", "description" => "Compact the history")]))
            send_fake_update(agent, session_id, Dict("sessionUpdate" => "agent_message_chunk",
                                                     "content" => Dict("type" => "text", "text" => "late")))
            @test _wait_until(() -> haskey(connection.waiting_session_events, session_id))
            empty!(events)
            send_agent_prompt!(connection, session_id, [LlmText("Again")]; on_event = event -> push!(events, event))
            @test AgentSessionInfoUpdate("Renamed") in events[1:2]
            commands = only(event for event in events if event isa AgentCommandsUpdate).commands
            @test [(command.name, command.input_hint) for command in commands] ==
                  [("review", "a branch"), ("compact", "")]
            @test !any(event -> event isa LlmTextDelta && event.text == "late", events)
            @test isempty(connection.waiting_session_events)
            stop_agent_connection!(connection)
        end

        @testset "an agent that needs a sign-in says how" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/new" => (agent, params) -> throw(ProtocolException(-32000, "Authentication required"))))
            connection = make_fake_connection(agent)
            message = try
                open_agent_session!(connection)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("Fake Agent needs a sign-in. Run `fake /login` in the terminal.", message)
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

        @testset "a prompt takes text only" begin
            agent = _make_fake_agent()
            connection = make_fake_connection(agent)
            session_id = open_agent_session!(connection)
            @test_throws ArgumentError send_agent_prompt!(connection, session_id,
                [LlmToolUse("t1", "x", Dict{String,Any}())]; on_event = identity)
            stop_agent_connection!(connection)
        end
    end
end
