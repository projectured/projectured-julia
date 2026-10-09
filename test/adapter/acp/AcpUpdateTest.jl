# The translation of a `session/update` into the events of the kernel: the frame
# that a chunk of text or of reasoning gets, the close of a block by a new
# message or a tool call, a tool call and its update, a diff, and a plan.

using ProjecturedACP.AcpModule: AcpTurn, _translate_session_update!, _close_open_block!,
                                _format_tool_content

_update(kind; fields...) = Dict{String,Any}("sessionUpdate" => kind,
                                            (String(key) => value for (key, value) in fields)...)
_text(text) = Dict{String,Any}("type" => "text", "text" => text)

function test_acp_update()
    @testset "a session update becomes kernel events" begin
        @testset "chunks of one message share one block" begin
            turn = AcpTurn(identity)
            first = _translate_session_update!(turn, _update("agent_message_chunk";
                                                             content = _text("Hel"), messageId = "m1"))
            second = _translate_session_update!(turn, _update("agent_message_chunk";
                                                              content = _text("lo"), messageId = "m1"))
            @test first == Any[LlmTextStart(), LlmTextDelta("Hel")]
            @test second == Any[LlmTextDelta("lo")]
            @test _close_open_block!(Any[], turn) == Any[LlmTextStop()]
            @test turn.open_block === :none
        end

        @testset "reasoning, then text, then a new message" begin
            turn = AcpTurn(identity)
            events = Any[]
            append!(events, _translate_session_update!(turn, _update("agent_thought_chunk"; content = _text("hmm"))))
            append!(events, _translate_session_update!(turn, _update("agent_message_chunk";
                                                                     content = _text("A"), messageId = "m1")))
            append!(events, _translate_session_update!(turn, _update("agent_message_chunk";
                                                                     content = _text("B"), messageId = "m2")))
            @test events == Any[LlmThinkingStart(), LlmThinkingDelta("hmm"), LlmThinkingStop(),
                                LlmTextStart(), LlmTextDelta("A"), LlmTextStop(),
                                LlmTextStart(), LlmTextDelta("B")]
        end

        @testset "a tool call closes the open block, and its update keeps the rest" begin
            turn = AcpTurn(identity)
            _translate_session_update!(turn, _update("agent_message_chunk"; content = _text("Let me look.")))
            call = _translate_session_update!(turn, _update("tool_call"; toolCallId = "t1",
                title = "Read file", kind = "read", status = "pending",
                rawInput = Dict{String,Any}("path" => "a.jl"),
                _meta = Dict{String,Any}("claudeCode" => Dict{String,Any}("toolName" => "Read"))))
            @test call[1] == LlmTextStop()
            event = call[2]
            @test event isa AgentToolCallUpdate
            @test (event.id, event.name, event.title, event.kind, event.status) ==
                  ("t1", "Read", "Read file", :read, :pending)
            @test event.input == Dict{String,Any}("path" => "a.jl")
            @test event.output === nothing
            update = only(_translate_session_update!(turn, _update("tool_call_update"; toolCallId = "t1",
                status = "completed",
                content = Any[Dict{String,Any}("type" => "content", "content" => _text("1 line"))])))
            @test (update.id, update.status, update.output) == ("t1", :completed, "1 line")
            @test update.title === nothing && update.kind === nothing && update.input === nothing
        end

        @testset "a resource gives its text, its media type and its uri" begin
            resource = Dict{String,Any}("type" => "resource", "resource" => Dict{String,Any}(
                "uri" => "file:///c.md", "mimeType" => "text/markdown", "text" => "# Title\n"))
            update = only(_translate_session_update!(AcpTurn(identity), _update("tool_call_update"; toolCallId = "t1",
                status = "completed", content = Any[Dict{String,Any}("type" => "content", "content" => resource)])))
            @test (update.output, update.output_mime_type, update.output_uri) == ("# Title\n", "text/markdown", "file:///c.md")
            # Text alone has no media type.
            plain = only(_translate_session_update!(AcpTurn(identity), _update("tool_call_update"; toolCallId = "t2",
                status = "completed", content = Any[Dict{String,Any}("type" => "content", "content" => _text("x"))])))
            @test plain.output_mime_type === nothing && plain.output_uri === nothing
        end

        @testset "a diff shows its path and its lines" begin
            text = _format_tool_content(Any[Dict{String,Any}(
                "type" => "diff", "path" => "/a.jl", "oldText" => "x = 1", "newText" => "x = 2\ny = 3")])
            @test text == "/a.jl\n-x = 1\n+x = 2\n+y = 3"
        end

        @testset "a plan replaces the plan" begin
            plan = only(_translate_session_update!(AcpTurn(identity), _update("plan"; entries = Any[
                Dict{String,Any}("content" => "Read", "priority" => "high", "status" => "completed"),
                Dict{String,Any}("content" => "Write", "priority" => "low", "status" => "pending")])))
            @test plan isa AgentPlanUpdate
            @test plan.entries == [AgentPlanEntry("Read", :high, :completed),
                                   AgentPlanEntry("Write", :low, :pending)]
        end

        @testset "an update the client does not show answers no event" begin
            turn = AcpTurn(identity)
            for kind in ("usage_update", "available_commands_update", "session_info_update",
                         "current_mode_update", "config_option_update", "user_message_chunk",
                         "an_update_from_the_future")
                @test isempty(_translate_session_update!(turn, _update(kind)))
            end
        end
    end
end
