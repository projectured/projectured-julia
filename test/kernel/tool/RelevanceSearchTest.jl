"""
The search by relevance: a `RelevanceModel` that a `ToolSet` holds reads a
description, its context and each thing the search could find, and ranks them.

The models here answer from the words of the texts, so the test reads no server.
"""

using Test
using ProjecturedKernel.ToolModule

const _RelevanceTools = ProjecturedKernel.ToolModule

# A declared API whose names share no word with the descriptions that find them.
module RelevanceToy
export measure_utilization, close_window, count_packets
"""
    measure_utilization(server) -> Float64

Give the share of time the server works.
"""
measure_utilization(server) = 0.5
"""
    close_window(window) -> Nothing

Remove the window from the screen.
"""
close_window(window) = nothing
"""
    count_packets(link) -> Int

Give the number of packets a link carried.
"""
count_packets(link) = 0
end

# A declaration larger than one choice holds.
module RelevanceBigToy
for index in 1:320
    name = Symbol("tool_", index)
    text = "    tool_$(index)()\n\nDo the step number $(index)."
    @eval begin
        export $name
        $name() = $index
        @doc $text $name
    end
end
end

# The first name of a list answer, or of an answer of one clear hit.
function _get_first_relevance_hit(answer::AbstractString)
    alone = match(r"^# `([^`(\s{]+)"m, answer)
    alone === nothing || return alone.captures[1]
    found = match(r"^- `([^`(\s{]+)"m, answer)
    found === nothing ? nothing : found.captures[1]
end

function test_relevance_search()
@testset "Relevance search" begin
    set = ToolSet()
    declare_api!(set, [RelevanceToy])
    asked = Ref{Any}(nothing)
    # A model that knows "busy" means the share of time a server works, and that
    # reads the context: "traffic" in it points to the packets.
    function score(query, context, texts)
        asked[] = (query = query, context = context, count = length(texts))
        [occursin("traffic", context) ? (occursin("packets", text) ? 0.9 : 0.1) :
         occursin("busy", query) && occursin("share of time", text) ? 0.9 : 0.1 for text in texts]
    end
    choose(query, context, options) = fill(1 / length(options), length(options))
    model = RelevanceModel("fake/relevance", score, choose)

    @testset "a tool set holds a relevance model" begin
        @test set.relevance_model === nothing
        @test set_relevance_model!(set, model) === set
        @test set.relevance_model === model
    end

    @testset "a description is ranked by the relevance model" begin
        answer = search_api(set, "how busy is the server"; mode = "description")
        @test _get_first_relevance_hit(answer) == "measure_utilization"
        @test asked[].query == "how busy is the server"
        @test asked[].context == ""
        # A declaration of up to 255 names is scored whole.
        @test asked[].count == 4
    end

    @testset "the context reaches the relevance model" begin
        answer = search_api(set, "how busy is the server"; mode = "description",
                            context = "The person looks at the traffic of a link.")
        @test _get_first_relevance_hit(answer) == "count_packets"
        @test asked[].context == "The person looks at the traffic of a link."
    end

    @testset "keywords that name one entry answer it, and do not ask the relevance model" begin
        asked[] = nothing
        answer = search_api(set, "close_window"; context = "traffic")
        @test _get_first_relevance_hit(answer) == "close_window"
        @test asked[] === nothing
    end

    @testset "other keywords are ranked by the relevance model, within their filters" begin
        answer = search_api(set, "busy server"; context = "The person looks at the traffic of a link.")
        @test _get_first_relevance_hit(answer) == "count_packets"
        @test asked[].query == "busy server"
        @test asked[].count == 4
        # `+window` lets one entry pass, and only that one is scored.
        search_api(set, "+window busy")
        @test asked[].count == 1
        # A pattern is not asked of it.
        asked[] = nothing
        search_api(set, r"count_"; context = "traffic")
        @test asked[] === nothing
    end

    @testset "a failed relevance model leaves the ranking to the meaning model" begin
        broken = RelevanceModel("fake/broken", (q, c, t) -> error("the server is down"), choose)
        set_relevance_model!(set, broken)
        answer = search_api(set, "remove the window"; mode = "description")
        @test startswith(answer, "The relevance model fake/broken failed")
        @test occursin("the server is down", first(split(answer, '\n')))
        @test _get_first_relevance_hit(answer) !== nothing
        set_relevance_model!(set, nothing)
        @test set.relevance_model === nothing
    end

    @testset "a large declaration is chosen from in groups, and the best few are scored" begin
        big = ToolSet()
        declare_api!(big, [RelevanceBigToy])
        groups = Int[]
        scored = Ref(0)
        big_choose(query, context, options) =
            (push!(groups, length(options));
             [endswith(first(option), "tool_277") ? 0.9 : 0.1 / length(options) for option in options])
        big_score(query, context, texts) =
            (scored[] = length(texts); [occursin("tool_277", text) ? 0.9 : 0.1 for text in texts])
        set_relevance_model!(big, RelevanceModel("fake/big", big_score, big_choose))
        answer = search_api(big, "the step two hundred and seventy-seven"; mode = "description")
        @test _get_first_relevance_hit(answer) == "tool_277"
        # 321 entries: the module and its 320 names, in groups of 255.
        @test sort(groups) == [66, 255]
        @test scored[] == 6
        # A miss lists the modules of a declaration too large to list by name.
        miss = search_api(big, "+zzqx")
        @test occursin("320 names in 1 modules, too many to list", miss)
        @test !occursin("tool_17", miss)
        small_miss = search_api(set, "+zzqx")
        @test occursin("measure_utilization", small_miss)
    end

    @testset "a guide search lets the relevance model order its first hits" begin
        guides = ToolSet()
        seen = Ref(0)
        function guide_score(query, context, texts)
            seen[] = length(texts)
            [occursin("guide: rule/naming-rules\nsection: Functions\n", text) ? 0.9 : 0.1
             for text in texts]
        end
        set_relevance_model!(guides, RelevanceModel("fake/guides", guide_score, choose))
        answer = search_guides(guides, "what must the name of a function start with";
                               mode = "description", detail = "names",
                               context = "I add a verb to a module.")
        first_hit = match(r"^- (resource://guide/\S+).*$"m, answer)
        @test first_hit !== nothing
        @test occursin("rule/naming-rules", first_hit.captures[1])
        @test endswith(first_hit.match, "— Functions")
        # The pool is the first hits of the words, since no meaning model is set.
        @test 0 < seen[] <= 50
        # Keywords go to it too.
        seen[] = 0
        answer = search_guides(guides, "function name verb"; detail = "names")
        first_hit = match(r"^- (resource://guide/\S+).*$"m, answer)
        @test occursin("rule/naming-rules", first_hit.captures[1])
        @test seen[] > 0
    end

    @testset "the search tools take no context, and a query can say what the step needs" begin
        tools = ToolSet()
        declare_api!(tools, [RelevanceToy])
        set_relevance_model!(tools, model)
        register_default_tools!(tools)
        for name in ("search_api", "search_guides")
            parameters = find_tool(tools, name).parameters
            @test !any(parameter -> parameter.name == "context", parameters)
        end
        answer = call_tool(tools, "search_api";
                           args = Dict("query" => "how busy is the server, for the traffic of a link",
                                       "mode" => "description"),
                           target = nothing)
        @test asked[].query == "how busy is the server, for the traffic of a link"
        @test asked[].context == ""
    end
end
end # test_relevance_search
