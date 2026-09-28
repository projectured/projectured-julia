# A local classifier on Ollama for `make_classifier_ranker`: the probability that
# an entry does what a question asks is p(yes) / (p(yes) + p(no)), read from the
# top log probabilities of the first answer token, with thinking off.
#
# Include it in a script that has loaded `ProjecturedOllama`; it takes `HTTP` and
# `JSON3` from there. Every answer is kept in a file by the hash of its request,
# so a second run of a measurement asks the model nothing.
# See plan/pending/a-classifier-ranks-the-search.md.

using SHA: sha256
import ProjecturedOllama
const _HTTP = ProjecturedOllama.HTTP
const _JSON3 = ProjecturedOllama.JSON3

const OLLAMA_CLASSIFIER_SYSTEM =
    "You judge whether an API entry of a Julia library helps a programmer to do a " *
    "request. Answer with one word: yes or no."
const OLLAMA_CLASSIFIER_QUESTION =
    "Would a programmer call or use this API entry to do what the request asks, " *
    "or one step of it? Answer yes or no."

# The user message of one candidate. The context and the request come first, so
# every candidate of one question shares the start of the prompt, which the
# server computes once.
function make_ollama_classifier_prompt(question, text::AbstractString)
    io = IOBuffer()
    isempty(question.context) || print(io, "Context:\n", question.context, "\n\n")
    print(io, "Request: ", question.sentence, "\n\nAPI entry:\n", text, "\n\n",
          OLLAMA_CLASSIFIER_QUESTION)
    String(take!(io))
end

function _read_classifier_cache(path::AbstractString)
    cache = Dict{String,Tuple{Float64,Int}}()
    isfile(path) || return cache
    for line in eachline(path)
        isempty(line) && continue
        record = _JSON3.read(line)
        cache[String(record.key)] = (Float64(record.noul), Int(record.tokens))
    end
    cache
end

# The probability of "yes" against "no" among the top tokens of the first
# position; the forms "Yes", " yes" and "YES" count as "yes". 0 when neither is
# there.
function _read_yes_probability(answer)
    positions = get(answer, :logprobs, nothing)
    (positions === nothing || isempty(positions)) && return 0.0
    yes = no = 0.0
    for candidate in get(positions[1], :top_logprobs, [])
        word = lowercase(strip(String(candidate.token)))
        word == "yes" && (yes += exp(candidate.logprob))
        word == "no" && (no += exp(candidate.logprob))
    end
    yes + no > 0 ? yes / (yes + no) : 0.0
end

"""
    make_ollama_noul_score(; model = "qwen3.8:27b", cache_path, url = "http://localhost:11434")
        -> Function

A `score(question, texts)` for `make_classifier_ranker`: one request per text,
answered from `cache_path` when it was asked before. It answers the
probabilities and the prompt tokens the server evaluated.
"""
function make_ollama_noul_score(; model::AbstractString = "qwen3.8:27b",
                                cache_path::AbstractString,
                                url::AbstractString = "http://localhost:11434")
    cache = _read_classifier_cache(cache_path)
    mkpath(dirname(cache_path))
    function score(question, texts)
        probabilities = Float64[]
        tokens = 0
        for text in texts
            prompt = make_ollama_classifier_prompt(question, text)
            key = bytes2hex(sha256(model * "\0" * OLLAMA_CLASSIFIER_SYSTEM * "\0" * prompt))
            if haskey(cache, key)
                push!(probabilities, first(cache[key]))
                continue
            end
            body = Dict("model" => model, "stream" => false, "think" => false,
                        "logprobs" => true, "top_logprobs" => 20, "keep_alive" => "10m",
                        "options" => Dict("temperature" => 0, "num_predict" => 1,
                                          "num_ctx" => 8192),
                        "messages" => [Dict("role" => "system", "content" => OLLAMA_CLASSIFIER_SYSTEM),
                                       Dict("role" => "user", "content" => prompt)])
            response = _HTTP.post(url * "/api/chat", ["Content-Type" => "application/json"],
                                  _JSON3.write(body); readtimeout = 600)
            answer = _JSON3.read(response.body)
            noul = _read_yes_probability(answer)
            evaluated = Int(get(answer, :prompt_eval_count, 0))
            tokens += evaluated
            cache[key] = (noul, evaluated)
            open(cache_path, "a") do io
                println(io, _JSON3.write(Dict("key" => key, "noul" => noul, "tokens" => evaluated)))
            end
            push!(probabilities, noul)
        end
        (probabilities, tokens)
    end
end
