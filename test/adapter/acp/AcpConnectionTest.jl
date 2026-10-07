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
            @test connection.agent_info["title"] == "Fake Agent"
            @test haskey(connection.agent_capabilities, "sessionCapabilities")
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

        @testset "an agent that needs a sign-in says how" begin
            agent = _make_fake_agent(Dict{String,Function}(
                "session/new" => (agent, params) -> throw(AcpRequestException(-32000, "Authentication required"))))
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
            @test events[8:end] == Any[LlmTextStart(), LlmTextDelta("Done"), LlmTextStop()]
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
            @test_throws AcpRequestException send_agent_prompt!(connection, session_id, [LlmText("Hi")];
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
