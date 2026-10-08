# The Claude adapter: which model a backend names, and what a request carries.
#
# Nothing here reaches the network, except the one test that asks the real API
# and skips itself when no key is exported.

# One answer of the Models API, as the documentation shows it: newest first, and
# each model with the capability block that says which thinking it takes. The
# second entry is the newest model that takes adaptive thinking, and the first
# one is a model that takes none.
const _RECORDED_MODELS = """
{
  "data": [
    {"type": "model", "id": "claude-batch-only-9", "created_at": "2026-09-01T00:00:00Z",
     "display_name": "Batch only",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"enabled": {"supported": true},
                                             "adaptive": {"supported": false}}}}},
    {"type": "model", "id": "claude-opus-5", "created_at": "2026-07-24T00:00:00Z",
     "display_name": "Claude Opus 5",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"enabled": {"supported": true},
                                             "adaptive": {"supported": true}}}}},
    {"type": "model", "id": "claude-sonnet-5", "created_at": "2026-05-01T00:00:00Z",
     "display_name": "Claude Sonnet 5",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"adaptive": {"supported": true}}}}}
  ],
  "has_more": false
}
"""

function test_anthropic_model()
    @testset "the model a backend names" begin
        @testset "the newest model that takes adaptive thinking" begin
            # The list is newest first, and the first two entries differ only in
            # that capability, so the answer says the choice reads it.
            @test find_adaptive_model(_RECORDED_MODELS) == "claude-opus-5"
            # An answer with no model, and one that is not JSON at all.
            @test find_adaptive_model("""{"data": [], "has_more": false}""") == ""
            @test find_adaptive_model("not json") == ""
            # A model with no capability block is left out rather than guessed
            # about.
            @test find_adaptive_model("""{"data": [{"id": "claude-old"}]}""") == ""
        end

        @testset "a backend with no key names the alias" begin
            # No key, no request: the alias is a name that keeps working after a
            # new model comes out.
            llm = AnthropicLlm(; api_key = "")
            @test llm.model == "claude-opus-5"
            @test get_default_llm_model(Val(:anthropic)) == "claude-opus-5"
            # A name a caller wrote wins over the choice.
            @test AnthropicLlm(; api_key = "", model = "claude-sonnet-5").model ==
                  "claude-sonnet-5"
        end

        @testset "each Models API address and key has its own answer" begin
            # The stand-in lists a newest adaptive model that is not the alias.
            # No server listens at the other address, so its answer is the alias.
            answer = """
            {"data": [{"id": "claude-sonnet-5",
                       "capabilities": {"thinking": {"types": {"adaptive":
                                                               {"supported": true}}}}}],
             "has_more": false}
            """
            unreachable = "http://127.0.0.1:1/v1/models"
            server = _serve_anthropic_answer(answer)
            listed = _get_local_url(server, "/v1/models")
            try
                @test get_newest_anthropic_model("key"; models_url = unreachable) ==
                      "claude-opus-5"
                @test get_newest_anthropic_model("key"; models_url = listed) ==
                      "claude-sonnet-5"
            finally
                close(server)
            end
            # The answer of each pair is kept, so a second ask sends no request.
            @test get_newest_anthropic_model("key"; models_url = listed) ==
                  "claude-sonnet-5"
        end

        @testset "the backend registers itself on the seam" begin
            @test :anthropic in get_llm_backend_names()
            @test make_llm(Val(:anthropic); api_key = "", model = "m") isa AnthropicLlm
        end

        @testset "a tool goes into the shape Anthropic reads" begin
            tool = Tool("count_words";
                        description = "Count the words of a text",
                        parameters = NamedTuple[(name = "text", type = "string",
                                                 description = "the text",
                                                 required = true)],
                        handler = (arguments, target) -> "3")
            rendered = only(render_tool_schema(AnthropicLlm(; api_key = ""), [tool]))
            @test rendered["name"] == "count_words"
            @test rendered["description"] == "Count the words of a text"
            @test rendered["input_schema"]["properties"]["text"]["type"] == "string"
            @test rendered["input_schema"]["required"] == ["text"]
        end

        @testset "the live Models API" begin
            key = get(ENV, "ANTHROPIC_API_KEY", "")
            if isempty(key)
                @test_skip "no ANTHROPIC_API_KEY"
            else
                model = get_newest_anthropic_model(key)
                @test startswith(model, "claude-")
            end
        end
    end
end

# One answer of the streaming Messages API, in the form that its documentation
# shows: the message starts with the input count, one text block streams, and
# the message delta carries the stop reason and the output count. The adapter
# translates no `ping`.
const _RECORDED_STREAM = """
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message",\
"role":"assistant","content":[],"model":"claude-opus-5","stop_reason":null,\
"usage":{"input_tokens":25,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,\
"content_block":{"type":"text","text":""}}

event: ping
data: {"type":"ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,\
"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,\
"delta":{"type":"text_delta","text":" there"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta",\
"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":7}}

event: message_stop
data: {"type":"message_stop"}

"""

# The events of a stream `body` that arrives in two reads, split after byte
# `split_at`. `nothing` stands for a block stop: `stream_turn` turns it into the
# typed stop of the open block.
function _get_anthropic_stream_events(body::AbstractString;
                                      split_at::Integer = ncodeunits(body))
    events = Any[]
    emit = event -> push!(events, event)
    input_tokens = Ref(0)
    buffer = IOBuffer()
    write(buffer, SubString(body, 1, split_at))
    ProjecturedAnthropic.AnthropicModule._drain_sse_events!(buffer, emit; input_tokens)
    write(buffer, SubString(body, split_at + 1))
    ProjecturedAnthropic.AnthropicModule._drain_sse_events!(buffer, emit; final = true, input_tokens)
    events
end

# A server on this machine that answers each request with `body`.
_serve_anthropic_answer(body::AbstractString) =
    HTTP.serve!(request -> HTTP.Response(200, body), "127.0.0.1", 0; listenany = true)

_get_local_url(server, path::AbstractString) =
    "http://127.0.0.1:" * string(HTTP.port(server)) * path

function test_anthropic_stream()
    @testset "the stream of a turn" begin
        @testset "a stream in two reads keeps the input count to the turn end" begin
            # The first read ends in the middle of the text, after `message_start`.
            text_start = findfirst("event: content_block_delta", _RECORDED_STREAM)
            split_at = first(text_start) + 9
            events = _get_anthropic_stream_events(_RECORDED_STREAM; split_at)
            @test length(events) == 5
            @test events[1] isa LlmTextStart
            @test events[2] == LlmTextDelta("Hello")
            @test events[3] == LlmTextDelta(" there")
            @test events[4] === nothing
            @test events[5] == LlmTurnEnd(:end_turn, 25, 7)
        end

        @testset "each stop reason of the API maps to one of the four" begin
            for (word, reason) in ("end_turn" => :end_turn, "tool_use" => :tool_use,
                                   "max_tokens" => :max_tokens,
                                   "stop_sequence" => :end_turn,
                                   "refusal" => :end_turn, "pause_turn" => :end_turn)
                body = "event: message_delta\n" *
                       "data: {\"type\":\"message_delta\"," *
                       "\"delta\":{\"stop_reason\":\"$word\"}," *
                       "\"usage\":{\"output_tokens\":3}}\n\n"
                @test only(_get_anthropic_stream_events(body)) == LlmTurnEnd(reason, 0, 3)
            end
        end

        @testset "a stream that ends before its turn end throws" begin
            request = LlmRequest(messages = [LlmMessage(:user, "Say hello.")])
            cut = first(_RECORDED_STREAM,
                        first(findfirst("event: message_delta", _RECORDED_STREAM)) - 1)
            for (body, is_whole) in ((_RECORDED_STREAM, true), (cut, false))
                server = _serve_anthropic_answer(body)
                try
                    url = _get_local_url(server, "/v1/messages")
                    llm = AnthropicLlm(; api_key = "key", model = "claude-opus-5",
                                         base_url = url)
                    events = Any[]
                    record = event -> push!(events, event)
                    if is_whole
                        stream_turn(llm, request; on_event = record)
                        @test events[end] == LlmTurnEnd(:end_turn, 25, 7)
                    else
                        @test_throws ErrorException stream_turn(llm, request;
                                                                on_event = record)
                        @test events[end] == LlmTextStop()
                    end
                finally
                    close(server)
                end
            end
        end

        @testset "a stop closes the connection, and the model writes no more" begin
            request = LlmRequest(messages = [LlmMessage(:user, "Say hello.")])
            head = first(_RECORDED_STREAM,
                         first(findfirst("event: content_block_delta", _RECORDED_STREAM)) - 1)
            delta(index) = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\"," *
                           "\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"w$index \"}}\n\n"
            server = HTTP.serve!("127.0.0.1", 0; listenany = true, stream = true) do http
                read(http)
                HTTP.setstatus(http, 200)
                HTTP.startwrite(http)
                try
                    write(http, head)
                    for index in 1:50
                        write(http, delta(index))
                        sleep(0.1)
                    end
                catch exception
                    exception isa Base.IOError || rethrow()
                end
            end
            try
                llm = AnthropicLlm(; api_key = "key", model = "claude-opus-5",
                                     base_url = _get_local_url(server, "/v1/messages"))
                deltas, stopped_at = Ref(0), Ref(0.0)
                stop = event -> (event isa LlmTextDelta && (deltas[] += 1) >= 2 &&
                                 (stopped_at[] = time(); error("The person stopped the turn.")))
                @test_throws Exception stream_turn(llm, request; on_event = stop)
                # The time from the stop, so the compilation of the first call does
                # not count.
                @test time() - stopped_at[] < 1.0
                @test deltas[] == 2
            finally
                close(server)
            end
        end

        @testset "a thinking block with no signature is left out of a request" begin
            wire = ProjecturedAnthropic.AnthropicModule._wire
            message = LlmMessage(:assistant, LlmContent[LlmThinking("cut", ""), LlmText("Hello")])
            @test [block["type"] for block in wire(message)["content"]] == ["text"]
            signed = LlmMessage(:assistant, LlmContent[LlmThinking("whole", "sig")])
            @test only(wire(signed)["content"])["signature"] == "sig"
        end
    end
end
