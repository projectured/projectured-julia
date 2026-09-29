"""
The relevance model on the Decisions API: the requests it builds, the answers it
reads, its batches, its tries, and its memory of answers. A stand-in answers
every request from what it asks, so nothing reaches the network.
"""

# A stand-in for the network. It keeps every request it gets, and answers a
# `noul` with 0.9 when the text of the entry holds `liked` and 0.1 when not, and
# a `choice` with 0.8 for the options whose line holds `liked`.
function _make_decisions_stand_in(; liked = "busy", failures = Any[])
    sent = Any[]
    function send(url, headers, body)
        push!(sent, (url = url, headers = headers, body = JSON3.read(body)))
        isempty(failures) || (failure = popfirst!(failures); failure isa Exception ? throw(failure) :
                              return (failure, "{\"error\":\"busy\"}"))
        request = JSON3.read(body)
        answers = Dict{String,Any}()
        for (key, question) in pairs(request.questions)
            if question.type == "noul"
                answers[String(key)] = Dict("type" => "noul",
                                            "noul" => occursin(liked, question.instructions.api_entry) ? 0.9 : 0.1)
            else
                options = [String(option) for option in keys(question.criteria)]
                answers[String(key)] = Dict("type" => "choice", "probabilities" =>
                    Dict(option => occursin(liked, question.criteria[Symbol(option)]) ? 0.8 : 0.2 / length(options)
                         for option in options))
            end
        end
        (200, JSON3.write(Dict("answers" => answers, "usage" => Dict("input_tokens" => 1, "cost" => 0.0))))
    end
    send, sent
end

function test_openrouter_relevance()
    @testset "the relevance model on the Decisions API" begin
        @testset "no key, no model" begin
            error = try
                make_openrouter_relevance_model(; api_key = "")
                nothing
            catch err
                err
            end
            @test error isa ErrorException
            @test occursin("OPENROUTER_API_KEY", error.msg)
        end

        @testset "a score is one noul per text, 150 texts to a request" begin
            send, sent = _make_decisions_stand_in()
            model = make_openrouter_relevance_model(; api_key = "key", send = send)
            @test model isa RelevanceModel
            @test model.name == "openrouter/~typesafe/jev-latest"
            texts = [isodd(index) ? "an entry for busy servers" : "an entry for windows" for index in 1:320]
            probabilities = model.score("how busy is the server", "", texts)
            @test probabilities == [isodd(index) ? 0.9 : 0.1 for index in 1:320]
            @test [length(request.body.questions) for request in sent] == [150, 150, 20]
            first_request = first(sent)
            @test first_request.url == "https://openrouter.ai/api/alpha/decisions"
            @test ("Authorization" => "Bearer key") in first_request.headers
            @test first_request.body.model == "~typesafe/jev-latest"
            @test first_request.body.state.request == "how busy is the server"
            @test !haskey(first_request.body.state, :context)
            @test first_request.body.questions.c1.type == "noul"
            # A context a caller gives goes into the state.
            model.score("how busy is the server", "a link carries traffic", texts[1:2])
            @test last(sent).body.state.context == "a link carries traffic"
        end

        @testset "a choice is one question, answered in the order of the options" begin
            send, sent = _make_decisions_stand_in()
            model = make_openrouter_relevance_model(; api_key = "key", send = send)
            options = [("Servers.measure_busy", "Servers.measure_busy: the busy share"),
                       ("Panes.open_pane!", "Panes.open_pane!: a new tab")]
            probabilities = model.choose("how busy is the server", "", options)
            @test probabilities == [0.8, 0.1]
            @test only(sent).body.questions.which.type == "choice"
            @test Set(keys(only(sent).body.questions.which.criteria)) ==
                  Set([Symbol("Servers.measure_busy"), Symbol("Panes.open_pane!")])
        end

        @testset "the same request is answered from memory" begin
            send, sent = _make_decisions_stand_in()
            model = make_openrouter_relevance_model(; api_key = "key", send = send)
            model.score("how busy", "", ["busy", "idle"])
            model.score("how busy", "", ["busy", "idle"])
            @test length(sent) == 1
        end

        @testset "a busy server, a failed one and a broken connection are tried again" begin
            waits = Int[]
            failures = Any[429, 503, Base.IOError("the connection broke", 0)]
            send, sent = _make_decisions_stand_in(; failures = failures)
            model = make_openrouter_relevance_model(; api_key = "key", send = send,
                                                    wait = attempt -> push!(waits, attempt))
            @test model.score("how busy", "", ["busy"]) == [0.9]
            @test length(sent) == 4
            @test waits == [1, 2, 3]
            # A server that fails every time is the answer after six tries.
            send, sent = _make_decisions_stand_in(; failures = Any[500 for _ in 1:6])
            model = make_openrouter_relevance_model(; api_key = "key", send = send, wait = _ -> nothing)
            @test_throws ErrorException model.score("how busy", "", ["busy"])
            @test length(sent) == 6
        end

        @testset "a tool set ranks with it" begin
            send, _ = _make_decisions_stand_in(; liked = "utilization")
            set = ToolSet()
            declare_api!(set, [ProjecturedKernel.ToolModule])
            set_relevance_model!(set, make_openrouter_relevance_model(; api_key = "key", send = send))
            answer = search_api(set, "how much of the time is the server working"; mode = "description")
            @test !startswith(answer, "The relevance model")
        end
    end
end

"""
    test_openrouter_live()

One request to the real Decisions API, when `OPENROUTER_API_KEY` is exported;
skipped otherwise, so a run without a key stays offline.
"""
function test_openrouter_live()
    @testset "one request to the Decisions API" begin
        if isempty(get(ENV, "OPENROUTER_API_KEY", ""))
            @test_skip "OPENROUTER_API_KEY is not exported"
        else
            model = make_openrouter_relevance_model()
            probabilities = model.score("close the window", "",
                                        ["name: close_window\ndocumentation:\nRemove the window from the screen.",
                                         "name: count_packets\ndocumentation:\nGive the number of packets a link carried."])
            @test probabilities[1] > probabilities[2]
        end
    end
end
