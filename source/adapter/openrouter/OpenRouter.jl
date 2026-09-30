# Fragment of `ProjecturedOpenRouter` — the Decisions API of OpenRouter as a
# relevance model: a `noul` per text for `score`, and one `choice` for `choose`.

const _DECISIONS_URL = "https://openrouter.ai/api/alpha/decisions"

# The alias follows the new versions of the model.
const _DEFAULT_DECISION_MODEL = "~typesafe/jev-latest"

# How many texts one request scores. A request holds up to 64,000 tokens, and the
# text of an entry is a few hundred.
const _NOUL_BATCH = 150

# How often a request is sent before its failure is the answer.
const _ATTEMPTS = 6

const _NOUL_INSTRUCTIONS =
    "Would a programmer call or use this API entry to do what the request asks, or one step of it?"
const _NOUL_CRITERIA = Dict(
    "true" => "The entry does what the request asks, or a necessary step of it.",
    "false" => "The entry is about a similar topic, but it does not do what the request asks.")
const _CHOICE_INSTRUCTIONS =
    "Which option holds the API entry a programmer would call to do what the request asks?"

# Send one request, and answer its status and its body. A refused connection or a
# cut answer throws.
function _post_decision_request(url::AbstractString, headers, body::AbstractString)
    response = HTTP.post(url, headers, body; status_exception = false, readtimeout = 180,
                         retry = false)
    (Int(response.status), String(response.body))
end

_is_connection_failure(err) = err isa HTTP.RequestError || err isa Base.IOError || err isa EOFError

# The answers of one request: from the cache when it was asked before, else from
# the server, tried again when the server is busy (429), fails (5xx) or the
# connection breaks, with a wait that doubles.
function _ask_decisions(send::Function, wait::Function, api_key::AbstractString,
                        model::AbstractString, state, questions, cache, cache_lock)
    body = JSON3.write(Dict("model" => model, "state" => state, "questions" => questions))
    key = hash(body)
    cached = lock(() -> get(cache, key, nothing), cache_lock)
    cached === nothing || return cached
    headers = ["Authorization" => "Bearer " * api_key, "Content-Type" => "application/json"]
    status, text = 0, ""
    for attempt in 1:_ATTEMPTS
        answered = try
            status, text = send(_DECISIONS_URL, headers, body)
            true
        catch err
            (_is_connection_failure(err) && attempt < _ATTEMPTS) || rethrow()
            false
        end
        answered && !(status == 429 || status >= 500) && break
        attempt < _ATTEMPTS && wait(attempt)
    end
    status == 200 || error("OpenRouter answered HTTP ", status, ": ", first(text, 300))
    answers = JSON3.read(text).answers
    lock(() -> (cache[key] = answers), cache_lock)
    answers
end

# The state of a request: the query, and the context when a caller gives one.
function _make_decision_state(query::AbstractString, context::AbstractString)
    state = Dict{String,Any}("request" => String(query))
    isempty(context) || (state["context"] = String(context))
    state
end

"""
    make_openrouter_relevance_model(; api_key = get(ENV, "OPENROUTER_API_KEY", ""),
                                    model = "~typesafe/jev-latest") -> RelevanceModel

The relevance model of a `ToolSet` on the Decisions API of OpenRouter, with the
decision model `model`: Jev of TypeSafe by default, through the alias that
follows its new versions. Give it to a tool set with `set_relevance_model!`.

- `score(query, context, texts)` asks one `noul` per text, 150 texts to a
  request, and answers the probability of each that its entry does what the
  query asks.
- `choose(query, context, options)` asks one `choice` among the options, each an
  identifier and a line, and answers the probability of each.

A request that the server finds busy, that fails on the server, or whose
connection breaks is sent again, six times at most, with a wait that doubles;
then the model throws, and the search ranks by meaning and says why. The same
request is answered once per model and then from memory, because the answer of
a decision model to one request does not change.

Without a key it throws at once, and the message names `OPENROUTER_API_KEY`.
The keywords `send` and `wait` replace the request and the wait between two
tries, for a test that must not reach the network.
"""
function make_openrouter_relevance_model(; api_key::AbstractString = get(ENV, "OPENROUTER_API_KEY", ""),
                                         model::AbstractString = _DEFAULT_DECISION_MODEL,
                                         send::Function = _post_decision_request,
                                         wait::Function = attempt -> sleep(2.0^attempt))
    isempty(api_key) &&
        error("No OpenRouter key: export OPENROUTER_API_KEY, or pass `api_key`.")
    cache = Dict{UInt,Any}()
    cache_lock = ReentrantLock()
    ask(state, questions) = _ask_decisions(send, wait, api_key, model, state, questions, cache,
                                           cache_lock)
    function score(query, context, texts)
        probabilities = zeros(Float64, length(texts))
        state = _make_decision_state(query, context)
        for range in Iterators.partition(eachindex(texts), _NOUL_BATCH)
            questions = Dict("c$index" => Dict("type" => "noul",
                                               "instructions" => Dict("question" => _NOUL_INSTRUCTIONS,
                                                                      "api_entry" => texts[index]),
                                               "criteria" => _NOUL_CRITERIA)
                             for index in range)
            answers = ask(state, questions)
            for index in range
                probabilities[index] = Float64(answers[Symbol("c$index")].noul)
            end
        end
        probabilities
    end
    function choose(query, context, options)
        criteria = Dict(String(first(option)) => String(last(option)) for option in options)
        answers = ask(_make_decision_state(query, context),
                      Dict("which" => Dict("type" => "choice", "instructions" => _CHOICE_INSTRUCTIONS,
                                           "criteria" => criteria)))
        probabilities = answers.which.probabilities
        Float64[Float64(get(probabilities, Symbol(first(option)), 0.0)) for option in options]
    end
    RelevanceModel("openrouter/" * model, score, choose)
end
