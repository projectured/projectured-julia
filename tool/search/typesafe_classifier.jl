# TypeSafe Jev for the rankers of `SearchRanking.jl`: a `noul` per candidate for
# `score`, and a `choice` over short lines for `choose`. The model is served by
# the Decisions API of OpenRouter, with the request shape of TypeSafe.
#
# Include it in a script that has loaded `ProjecturedOllama`; it takes `HTTP` and
# `JSON3` from there. The key is an OpenRouter key in `ENV["TYPESAFE_API_KEY"]`,
# which a run reads from `~/.config/typesafe/api.env`; it is never printed. Every answer is kept in
# a file by the hash of its request, and every request adds its input tokens to
# a ledger that the Python probes share, so the limit of cost holds for both.
# See plan/pending/a-classifier-ranks-the-search.md.

using SHA: sha256
import ProjecturedKernel
import ProjecturedOllama
const _TYPESAFE_HTTP = ProjecturedOllama.HTTP
const _TYPESAFE_JSON3 = ProjecturedOllama.JSON3

const TYPESAFE_URL = "https://openrouter.ai/api/alpha/decisions"
const TYPESAFE_DOLLARS_PER_TOKEN = 0.042 / 1_000_000
const TYPESAFE_NOUL_INSTRUCTIONS =
    "Would a programmer call or use this API entry to do what the request asks, or one step of it?"
const TYPESAFE_NOUL_CRITERIA = Dict(
    "true" => "The entry does what the request asks, or a necessary step of it.",
    "false" => "The entry is about a similar topic, but it does not do what the request asks.")
const TYPESAFE_CHOICE_INSTRUCTIONS =
    "Which option holds the API entry a programmer would call to do what the request asks?"

"""
    TypeSafeBudgetExceeded(spent, limit)

The ledger holds as many tokens as the limit of cost allows, and no request more
is sent.
"""
struct TypeSafeBudgetExceeded <: Exception
    spent::Float64
    limit::Float64
end

Base.showerror(io::IO, err::TypeSafeBudgetExceeded) =
    print(io, "The TypeSafe ledger holds \$", round(err.spent; digits = 4),
          " of the limit of \$", err.limit, "; no request is sent.")

# The dollars the ledger holds: the cost the server reported, or the price of the
# input tokens where it reported none.
function get_typesafe_spent_dollars(ledger::AbstractString)
    isfile(ledger) || return 0.0
    dollars = 0.0
    for line in eachline(ledger)
        isempty(line) && continue
        record = _TYPESAFE_JSON3.read(line)
        cost = get(record, :cost, nothing)
        dollars += cost === nothing ? record.input_tokens * TYPESAFE_DOLLARS_PER_TOKEN : Float64(cost)
    end
    dollars
end

# The state of a request: the request of the question, its context when it has
# one, and what else the layout puts there.
function _make_typesafe_state(question; extra = nothing)
    state = Dict{String,Any}("request" => question.sentence)
    isempty(question.context) || (state["context"] = question.context)
    extra === nothing || merge!(state, extra)
    state
end

"""
    make_typesafe_client(; ledger, cache_path, limit_dollars, model = "typesafe/jev-1.13")
        -> Function

A function `ask(state, questions; label)` that answers the `answers` of one
request and its input tokens: from `cache_path` when it was asked before, else
from the server, after it checks the ledger against `limit_dollars`.
"""
function make_typesafe_client(; ledger::AbstractString, cache_path::AbstractString,
                              limit_dollars::Real, model::AbstractString = "typesafe/jev-1.13")
    cache = Dict{String,Any}()
    if isfile(cache_path)
        for line in eachline(cache_path)
            isempty(line) && continue
            record = _TYPESAFE_JSON3.read(line)
            cache[String(record.key)] = record.answer
        end
    end
    mkpath(dirname(cache_path))
    function ask(state, questions; label::AbstractString = "")
        body = _TYPESAFE_JSON3.write(Dict("model" => model, "state" => state,
                                          "questions" => questions))
        key = bytes2hex(sha256(body))
        haskey(cache, key) && return (cache[key], 0)
        spent = get_typesafe_spent_dollars(ledger)
        spent >= limit_dollars && throw(TypeSafeBudgetExceeded(spent, Float64(limit_dollars)))
        headers = ["Authorization" => "Bearer " * ENV["TYPESAFE_API_KEY"],
                   "Content-Type" => "application/json"]
        # A refused connection or a cut answer is tried again, as a busy server
        # (429, 529) and a failed one (5xx) are; each wait doubles.
        response = nothing
        for attempt in 1:6
            response = try
                _TYPESAFE_HTTP.post(TYPESAFE_URL, headers, body; status_exception = false,
                                    readtimeout = 180, retry = false)
            catch err
                (err isa _TYPESAFE_HTTP.RequestError || err isa Base.IOError ||
                 err isa EOFError) && attempt < 6 || rethrow()
                nothing
            end
            response !== nothing && !(response.status == 429 || response.status >= 500) && break
            sleep(2.0^attempt)
        end
        response.status == 200 ||
            error("TypeSafe answered HTTP ", response.status, ": ", first(String(response.body), 500))
        answer = _TYPESAFE_JSON3.read(response.body)
        tokens = Int(answer.usage.input_tokens)
        open(ledger, "a") do io
            println(io, _TYPESAFE_JSON3.write(Dict("time" => time(), "label" => label, "key" => key,
                                                   "input_tokens" => tokens,
                                                   "output_tokens" => Int(answer.usage.output_tokens),
                                                   "cost" => get(answer.usage, :cost, nothing))))
        end
        cache[key] = answer.answers
        open(cache_path, "a") do io
            println(io, _TYPESAFE_JSON3.write(Dict("key" => key, "answer" => answer.answers)))
        end
        (answer.answers, tokens)
    end
end

"""
    make_typesafe_noul_score(ask; layout = :fanout, batch = 150) -> Function

A `score(question, texts)` for the rankers. `layout = :fanout` sends the question
and its context once as the state, and one `noul` per text, `batch` texts per
request; `layout = :single` sends one request per text, with the text in the
state, as the re-rank cookbook of TypeSafe does.
"""
function make_typesafe_noul_score(ask::Function; layout::Symbol = :fanout, batch::Int = 150)
    function score(question, texts)
        probabilities = zeros(Float64, length(texts))
        tokens = 0
        if layout === :single
            for (index, text) in enumerate(texts)
                answers, used = ask(_make_typesafe_state(question; extra = Dict("api_entry" => text)),
                                    Dict("relevant" => Dict("type" => "noul",
                                                            "instructions" => TYPESAFE_NOUL_INSTRUCTIONS,
                                                            "criteria" => TYPESAFE_NOUL_CRITERIA));
                                    label = "noul-single")
                probabilities[index] = Float64(answers.relevant.noul)
                tokens += used
            end
        else
            for range in Iterators.partition(eachindex(texts), batch)
                questions = Dict("c$index" => Dict("type" => "noul",
                                                   "instructions" => Dict("question" => TYPESAFE_NOUL_INSTRUCTIONS,
                                                                          "api_entry" => texts[index]),
                                                   "criteria" => TYPESAFE_NOUL_CRITERIA)
                                 for index in range)
                answers, used = ask(_make_typesafe_state(question), questions; label = "noul-fanout")
                for index in range
                    probabilities[index] = Float64(answers[Symbol("c$index")].noul)
                end
                tokens += used
            end
        end
        (probabilities, tokens)
    end
end

"""
    make_typesafe_choose(ask) -> Function

A `choose(question, options)` for the cascade and the tree: one `choice` whose
options are the identifiers of `options`, each with its line.
"""
function make_typesafe_choose(ask::Function)
    function choose(question, options)
        criteria = Dict(String(first(option)) => String(last(option)) for option in options)
        answers, used = ask(_make_typesafe_state(question),
                            Dict("which" => Dict("type" => "choice",
                                                 "instructions" => TYPESAFE_CHOICE_INSTRUCTIONS,
                                                 "criteria" => criteria)); label = "choice")
        probabilities = answers.which.probabilities
        ([Float64(get(probabilities, Symbol(first(option)), 0.0)) for option in options], used)
    end
end

"""
    make_jev_relevance_model(ask) -> RelevanceModel

The kernel's `RelevanceModel` on Jev: its `score` sends a `noul` per text, and
its `choose` one `choice`, through `ask` of [`make_typesafe_client`](@ref).
"""
function make_jev_relevance_model(ask::Function)
    noul_score = make_typesafe_noul_score(ask)
    choice = make_typesafe_choose(ask)
    question(query, context) = (sentence = String(query), context = String(context))
    ProjecturedKernel.ToolModule.RelevanceModel("openrouter/typesafe/jev-1.13",
                   (query, context, texts) -> first(noul_score(question(query, context), texts)),
                   (query, context, options) -> first(choice(question(query, context), options)))
end
