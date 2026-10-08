# Drive the adapter's stream reader over recorded lines. Every line here was
# recorded from a real Ollama server (version 0.33), so the suite tests what the
# server sends and not what the adapter wishes it sent.
function _events_of(lines::AbstractVector{<:AbstractString})
    out = Any[]
    handle = ProjecturedOllama.OllamaModule._line_handler(ev -> push!(out, ev))
    buf = IOBuffer()
    for line in lines
        write(buf, line, '\n')
        ProjecturedOllama.OllamaModule._drain_lines!(buf, handle)
    end
    ProjecturedOllama.OllamaModule._drain_lines!(buf, handle; final = true)
    out
end

function test_ollama_request()
@testset "OllamaRequest" begin

# ── the tool schema is a function wrapper, not Anthropic's input_schema ──
llm  = OllamaLlm(; model = "mistral:latest")
tool = Tool("get_weather";
            description = "Get the weather for a city",
            parameters = NamedTuple[(name = "city", type = "string",
                                     description = "The city name", required = true),
                                    (name = "unit", type = "string",
                                     description = "celsius or fahrenheit")],
            handler = (args, target) -> "18 degrees")
schema = render_tool_schema(llm, [tool])
@test length(schema) == 1
@test schema[1]["type"] == "function"
@test schema[1]["function"]["name"] == "get_weather"
@test schema[1]["function"]["parameters"]["required"] == ["city"]
@test haskey(schema[1]["function"]["parameters"]["properties"], "unit")

# ── the system prompt is a message, not a field beside the messages ──
request = LlmRequest(system = "Be brief.",
                     messages = [LlmMessage(:user, "Hello.")])
wire = ProjecturedOllama.OllamaModule._wire_messages(request)
@test length(wire) == 2
@test wire[1]["role"] == "system"
@test wire[1]["content"] == "Be brief."
@test wire[2]["role"] == "user"
@test wire[2]["content"] == "Hello."

# ── a tool result is its own message, and it names the TOOL ──
# Our `LlmToolResult` carries the call's id, so the walk keeps an id-to-name map
# and the result that follows looks its name up there.
call = LlmToolUse("call_x1", "get_weather", Dict{String,Any}("city" => "Paris"))
request = LlmRequest(messages = [
    LlmMessage(:user, "Weather in Paris?"),
    LlmMessage(:assistant, LlmContent[LlmThinking("Ask the tool.", ""), call]),
    LlmMessage(:user, LlmContent[LlmToolResult("call_x1", "18 degrees", false)]),
])
wire = ProjecturedOllama.OllamaModule._wire_messages(request)
@test length(wire) == 3
@test wire[2]["role"] == "assistant"
@test wire[2]["thinking"] == "Ask the tool."
@test wire[2]["tool_calls"][1]["function"]["name"] == "get_weather"
@test wire[2]["tool_calls"][1]["function"]["arguments"]["city"] == "Paris"
@test wire[3]["role"] == "tool"
@test wire[3]["tool_name"] == "get_weather"
@test wire[3]["content"] == "18 degrees"

# A result whose call was never seen still reaches the model, as quoted text.
request = LlmRequest(messages = [
    LlmMessage(:user, LlmContent[LlmToolResult("unknown", "18 degrees", false)])])
wire = ProjecturedOllama.OllamaModule._wire_messages(request)
@test length(wire) == 1
@test wire[1]["role"] == "user"
@test occursin("18 degrees", wire[1]["content"])

# ── the token budget is an option, and an empty model is the default ──
@test OllamaLlm(; model = "").model == get_default_llm_model(:ollama)
@test OllamaLlm(; base_url = "http://host:1/").base_url == "http://host:1"

# ── the context window is sent only when a caller asked for a size ──
# Ollama's own answer comes from the model and the server's configuration, and an
# unasked-for `num_ctx` would take that away.
@test OllamaLlm().context == 0
@test OllamaLlm(; context = 8192).context == 8192
@test make_llm(:ollama; context = 8192).context == 8192

end
end

function test_ollama_stream()
@testset "OllamaStream" begin

# ── text: the adapter opens and closes a block Ollama never framed ──
evs = _events_of([
    """{"message":{"role":"assistant","content":" Hello"},"done":false}""",
    """{"message":{"role":"assistant","content":" there"},"done":false}""",
    """{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":42,"eval_count":7}""",
])
@test evs[1] isa LlmTextStart
@test evs[2] == LlmTextDelta(" Hello")
@test evs[3] == LlmTextDelta(" there")
@test evs[4] isa LlmTextStop
# The last line says what the round cost, and the turn end carries it.
@test evs[5] == LlmTurnEnd(:end_turn, 42, 7)
@test LlmTurnEnd(:end_turn) == LlmTurnEnd(:end_turn, 0, 0)

# ── a tool call: three events out of one line, arguments already parsed ──
evs = _events_of([
    """{"message":{"role":"assistant","content":"","tool_calls":[{"id":"call_xdzs68uo","function":{"index":0,"name":"get_weather","arguments":{"city":"Paris"}}}]},"done":false}""",
    """{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}""",
])
@test evs[1] == LlmToolUseStart("call_xdzs68uo", "get_weather")
@test evs[2] isa LlmToolInputDelta
@test occursin("Paris", evs[2].json)
@test evs[3] isa LlmToolUseStop
@test evs[3].tool_use.name == "get_weather"
@test evs[3].tool_use.input == Dict{String,Any}("city" => "Paris")

# **The turn that made a tool call ends in `:tool_use`, though the server said
# "stop".** The agent loop runs a tool only on that reason, so without this the
# assistant would show the call and never run it.
@test evs[4] == LlmTurnEnd(:tool_use)

# ── reasoning, then prose: the first closes when the second opens ──
evs = _events_of([
    """{"message":{"role":"assistant","content":"","thinking":"Let me"},"done":false}""",
    """{"message":{"role":"assistant","content":"","thinking":" think."},"done":false}""",
    """{"message":{"role":"assistant","content":"Yes"},"done":false}""",
    """{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}""",
])
@test evs[1] isa LlmThinkingStart
@test evs[2] == LlmThinkingDelta("Let me")
@test evs[3] == LlmThinkingDelta(" think.")
@test evs[4] isa LlmThinkingStop
@test evs[5] isa LlmTextStart
@test evs[6] == LlmTextDelta("Yes")
@test evs[7] isa LlmTextStop
@test evs[8] == LlmTurnEnd(:end_turn)

# ── a budget that ran out ──
evs = _events_of([
    """{"message":{"role":"assistant","content":"a"},"done":false}""",
    """{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length"}""",
])
@test evs[end] == LlmTurnEnd(:max_tokens)

# ── an error inside the stream is an event; a dead socket would throw ──
evs = _events_of(["""{"error":"model runner has unexpectedly stopped"}"""])
@test length(evs) == 1
@test evs[1] isa LlmFailure
@test occursin("unexpectedly stopped", evs[1].message)

# ── a stream that ends before its `done` line throws, as a dead socket does ──
request = LlmRequest(messages = [LlmMessage(:user, "Say hello.")])
first_line = """{"message":{"role":"assistant","content":"Hel"},"done":false}\n"""
last_line = """{"message":{"role":"assistant","content":""},"done":true}\n"""
for (body, is_whole) in ((first_line * last_line, true), (first_line, false))
    server, _ = _serve_json_requests(_ -> HTTP.Response(200, body))
    try
        llm = OllamaLlm(; base_url = _get_local_url(server), model = "m",
                          thinking = false)
        evs = Any[]
        record = ev -> push!(evs, ev)
        if is_whole
            stream_turn(llm, request; on_event = record)
            @test evs[end] == LlmTurnEnd(:end_turn)
        else
            @test_throws ErrorException stream_turn(llm, request; on_event = record)
            @test evs[end] == LlmTextDelta("Hel")
        end
    finally
        close(server)
    end
end

# ── a stop throws from `on_event`, and the connection closes at once, while the
#    server would write its answer for five seconds more ──
server = HTTP.serve!("127.0.0.1", 0; listenany = true, stream = true) do http
    read(http)
    HTTP.setstatus(http, 200)
    HTTP.startwrite(http)
    try
        for index in 1:50
            write(http, """{"message":{"role":"assistant","content":"w$index "},"done":false}\n""")
            sleep(0.1)
        end
        write(http, last_line)
    catch exception
        exception isa Base.IOError || rethrow()
    end
end
try
    llm = OllamaLlm(; base_url = _get_local_url(server), model = "m", thinking = false)
    deltas, stopped_at = Ref(0), Ref(0.0)
    stop = ev -> (ev isa LlmTextDelta && (deltas[] += 1) >= 2 &&
                  (stopped_at[] = time(); error("The person stopped the turn.")))
    @test_throws Exception stream_turn(llm, request; on_event = stop)
    # The time from the stop, so the compilation of the first call does not count.
    @test time() - stopped_at[] < 1.0
    @test deltas[] == 2
finally
    close(server)
end

# ── a line split across two reads is one event, not two ──
out = Any[]
handle = ProjecturedOllama.OllamaModule._line_handler(ev -> push!(out, ev))
buf = IOBuffer()
write(buf, """{"message":{"role":"assist""")
ProjecturedOllama.OllamaModule._drain_lines!(buf, handle)
@test isempty(out)
write(buf, """ant","content":"split"},"done":false}\n""")
ProjecturedOllama.OllamaModule._drain_lines!(buf, handle)
@test out[2] == LlmTextDelta("split")

# ── a call the server did not name still gets an id, because the result pairs by it ──
evs = _events_of([
    """{"message":{"role":"assistant","tool_calls":[{"function":{"name":"t","arguments":{}}}]},"done":false}""",
])
@test evs[1] isa LlmToolUseStart
@test !isempty(evs[1].id)

end
end

function test_ollama_backend()
@testset "OllamaBackend" begin

# The three keywords every backend accepts. Ollama uses `model` and `context`, and
# ignores `api_key` because a server on this machine asks for none.
@test make_llm(:ollama; model = "m", api_key = "ignored", context = 4096) isa OllamaLlm

# The package registers itself, so the kernel's factory answers for it.
@test :ollama in get_llm_backend_names()
@test get_default_llm_model(:ollama) == "qwen3.8:27b"
llm = make_llm(:ollama; model = "mistral:latest", api_key = "ignored")
@test llm isa OllamaLlm
@test llm.model == "mistral:latest"

# `thinking` said outright is never asked about.
@test ProjecturedOllama.OllamaModule._supports_thinking(OllamaLlm(; thinking = true))
@test !ProjecturedOllama.OllamaModule._supports_thinking(OllamaLlm(; thinking = false))

end
end

# Is a server answering? The live test needs one, and skips itself otherwise, so
# the suite passes on a machine with no Ollama installed.
function _ollama_is_up(base_url::AbstractString = "http://localhost:11434")
    try
        HTTP.get(base_url * "/api/version"; status_exception = false,
                 readtimeout = 2, retry = false).status == 200
    catch
        false
    end
end

# A model the server already holds in memory and that can chat, or nothing.
#
# **The suite must not load a second model.** A model is gigabytes, and a machine
# that is already running one for an editor has no room for the test's own choice —
# naming a favourite here once took a 61 GB machine down to 3 GB free. Whatever is
# resident answers "Say OK." as well as any other.
#
# **A resident model is not always a chat model.** A meaning model stays in
# memory after a search by description, and the server refuses it a chat with
# HTTP 400, so only a model whose capabilities say `completion` is taken.
function _ollama_resident_model(base_url::AbstractString = "http://localhost:11434")
    try
        r = HTTP.get(base_url * "/api/ps"; status_exception = false,
                     readtimeout = 2, retry = false)
        r.status == 200 || return nothing
        for model in get(JSON3.read(r.body), :models, ())
            name = String(get(model, :name, ""))
            isempty(name) && continue
            _ollama_can_chat(name, base_url) && return name
        end
        nothing
    catch
        nothing
    end
end

function _ollama_can_chat(model::AbstractString, base_url::AbstractString)
    r = HTTP.post(base_url * "/api/show", ["content-type" => "application/json"],
                  JSON3.write(Dict("model" => model));
                  status_exception = false, readtimeout = 5, retry = false)
    r.status == 200 || return false
    any(c -> String(c) == "completion", get(JSON3.read(r.body), :capabilities, ()))
end

function test_ollama_live(; model::Union{Nothing,AbstractString} = nothing)
@testset "OllamaLive" begin

if !_ollama_is_up()
    @info "[ollama] no server on http://localhost:11434; skipping the live test"
    @test true
    return
end

model = model === nothing ? _ollama_resident_model() : model
if model === nothing || isempty(model)
    @info "[ollama] the server holds no model in memory; skipping the live test " *
          "rather than loading gigabytes of one"
    @test true
    return
end
@info "[ollama] the live test uses the model the server already holds" model

llm = make_llm(:ollama; model = model)
evs = Any[]
stream_turn(llm, LlmRequest(system = "Answer in three words.",
                            messages = [LlmMessage(:user, "Say hello.")]);
            on_event = ev -> push!(evs, ev))
# A reasoning model puts its reasoning in its own block, so the text is what is
# left; either way the turn ends and prose arrives.
@test any(e -> e isa LlmTextDelta, evs)
@test evs[end].stop_reason == :end_turn
# A real server counts what it read and wrote.
@test evs[end].input_tokens > 0 && evs[end].output_tokens > 0

end
end

# A server on this machine that answers each request with `answer(body)`, where
# `body` is the JSON of the request, and keeps every request it was sent.
function _serve_json_requests(answer::Function)
    requests = Any[]
    server = HTTP.serve!("127.0.0.1", 0; listenany = true) do request
        body = JSON3.read(request.body)
        push!(requests, (target = request.target, body = body))
        answer(body)
    end
    (server, requests)
end

_get_local_url(server) = "http://127.0.0.1:$(HTTP.port(server))"

function test_ollama_meaning()
@testset "OllamaMeaning" begin

# ── the backend has a meaning model unless it is told it has none ──
@test OllamaLlm().meaning_model == "nomic-embed-text"
@test has_meaning_model(OllamaLlm())
@test get_meaning_model_name(OllamaLlm()) == "ollama/nomic-embed-text"
@test !has_meaning_model(OllamaLlm(; meaning_model = ""))
@test_throws ErrorException compute_meaning_vectors(OllamaLlm(; meaning_model = ""), ["x"])
@test make_llm(:ollama; meaning_model = "mxbai-embed-large").meaning_model == "mxbai-embed-large"

# ── each model family gets its own prefixes, and an unknown model none ──
prefix = ProjecturedOllama.OllamaModule._get_meaning_prefix
@test prefix("nomic-embed-text", :query) == "search_query: "
@test prefix("library/nomic-embed-text:latest", :document) == "search_document: "
@test startswith(prefix("mxbai-embed-large:335m", :query), "Represent this sentence")
@test prefix("mxbai-embed-large", :document) == ""
@test prefix("all-minilm", :query) == ""

# ── the request: the model, the texts with their prefix, batches of 64 ──
server, requests = _serve_json_requests(body ->
    HTTP.Response(200, JSON3.write(Dict("embeddings" => [[1.0, 2.0] for _ in body.input]))))
try
    llm = OllamaLlm(; base_url = _get_local_url(server))
    vectors = compute_meaning_vectors(llm, ["text $i" for i in 1:70])
    @test size(vectors) == (2, 70)
    @test eltype(vectors) == Float32
    @test length(requests) == 2
    @test all(request -> request.target == "/api/embed", requests)
    @test requests[1].body.model == "nomic-embed-text"
    @test length(requests[1].body.input) == 64
    @test length(requests[2].body.input) == 6
    @test requests[1].body.input[1] == "search_document: text 1"
    @test size(compute_meaning_vectors(llm, ["busy"]; purpose = :query)) == (2, 1)
    @test collect(requests[3].body.input) == ["search_query: busy"]
    @test size(compute_meaning_vectors(llm, String[])) == (0, 0)
    @test length(requests) == 3
    @test_throws ErrorException compute_meaning_vectors(llm, ["x"]; purpose = :answer)
finally
    close(server)
end

# ── a server that answers too few vectors is refused ──
short, _ = _serve_json_requests(body ->
    HTTP.Response(200, JSON3.write(Dict("embeddings" => [[1.0]]))))
try
    llm = OllamaLlm(; base_url = _get_local_url(short))
    @test_throws ErrorException compute_meaning_vectors(llm, ["a", "b"])
finally
    close(short)
end

# ── a model that is not pulled: the error says how to pull it ──
refusing, _ = _serve_json_requests(body ->
    HTTP.Response(404, JSON3.write(Dict(
        "error" => "model \"$(body.model)\" not found, try pulling it first"))))
try
    llm = OllamaLlm(; base_url = _get_local_url(refusing))
    failure = try
        compute_meaning_vectors(llm, ["x"])
        ""
    catch err
        sprint(showerror, err)
    end
    @test occursin("Run `ollama pull nomic-embed-text`", failure)
finally
    close(refusing)
end

# ── a server that does not answer throws ──
@test_throws Exception compute_meaning_vectors(OllamaLlm(; base_url = "http://127.0.0.1:1"), ["x"])

end
end

# Whether the server lists `model`, with or without a tag.
function _ollama_has_model(model::AbstractString, base_url::AbstractString = "http://localhost:11434")
    try
        r = HTTP.get(base_url * "/api/tags"; status_exception = false,
                     readtimeout = 2, retry = false)
        r.status == 200 || return false
        names = [String(get(one, :name, "")) for one in get(JSON3.read(r.body), :models, ())]
        any(name -> name == model || startswith(name, model * ":"), names)
    catch
        false
    end
end

function test_ollama_meaning_live(; model::AbstractString = "nomic-embed-text")
@testset "OllamaMeaningLive" begin

if !_ollama_is_up()
    @info "[ollama] no server on http://localhost:11434; skipping the live meaning test"
    @test true
    return
end
if !_ollama_has_model(model)
    @info "[ollama] the meaning model is not pulled; skipping the live meaning test" model
    @test true
    return
end

llm = OllamaLlm(; meaning_model = model)
vectors = compute_meaning_vectors(llm, ["plot a value over time",
                                        "draw a chart of a time series",
                                        "close the window"])
cosine(a, b) = sum(a .* b) / sqrt(sum(abs2, a) * sum(abs2, b))
@test cosine(vectors[:, 1], vectors[:, 2]) > cosine(vectors[:, 1], vectors[:, 3])
query = compute_meaning_vectors(llm, ["show how a number changes"]; purpose = :query)
@test size(query) == (size(vectors, 1), 1)

end
end
