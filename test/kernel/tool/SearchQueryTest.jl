"""
The three kinds of search query — keywords with their classes, a pattern, and a
description — as the search functions read them and as the two tools pass them.
"""

using Test
using ProjecturedKernel.ToolModule

# A declared API whose names share words in the ways a query must tell apart:
# `row` is inside `arrow`, and at the start of a word in `count_rows` and
# `table_row_height`.
module SearchToy
export arrange_panes, count_rows, draw_arrow, table_row_height, mark_whole_line
"""
    arrange_panes(window) -> String

Put every pane where the person asked for it.
"""
arrange_panes(window) = "arranged"
"""
    count_rows(table) -> Int

Count the rows of a table.
"""
count_rows(table) = 0
"""
    draw_arrow(canvas) -> Nothing

Draw an arrow between two boxes.
"""
draw_arrow(canvas) = nothing
"""
    table_row_height(table) -> Int

Give the height of one row of a table.
"""
table_row_height(table) = 1
"""
    mark_whole_line(text) -> Nothing

Select the whole line under the caret.
"""
mark_whole_line(text) = nothing
end

_get_written(terms) = [collect(term.written) for term in terms]

function test_search_query()
@testset "Search query" begin

    @testset "a keyword query is read into its three classes" begin
        query = parse_keyword_query("plot +vector -histogram")
        @test _get_written(query.should) == [["plot"]]
        @test _get_written(query.must) == [["vector"]]
        @test _get_written(query.must_not) == [["histogram"]]
        # A word counts with and without its final `s`, and only in prose.
        @test "vectors" in query.must[1].forms
        @test query.must[1].written == ["vector"]

        # Alternatives are one term.
        @test _get_written(parse_keyword_query("selection|caret").should) ==
              [["selection", "caret"]]
        # A phrase is one term, spelled as written and as a name spells it.
        @test _get_written(parse_keyword_query("\"Two  Words\"").should) ==
              [["two words", "two_words"]]
        # A plain piece of several words is one term per word, in its class.
        @test _get_written(parse_keyword_query("OperationModule.Replace").should) ==
              [["operationmodule"], ["replace"]]
        @test _get_written(parse_keyword_query("+Cell.value").must) == [["cell"], ["value"]]
        # A quote that is never closed runs to the end.
        @test _get_written(parse_keyword_query("\"open phrase").should) ==
              [["open phrase", "open_phrase"]]
    end

    @testset "a joining word is dropped only where it is optional" begin
        @test _get_written(parse_keyword_query("how to change the layout").should) ==
              [["change"], ["layout"]]
        # A query of nothing but joining words keeps them.
        @test _get_written(parse_keyword_query("how to").should) == [["how"], ["to"]]
        # A required word and a phrase are what the person asked for.
        @test _get_written(parse_keyword_query("+the layout").must) == [["the"]]
        @test _get_written(parse_keyword_query("\"the\" layout").should) == [["the"], ["layout"]]
        # A single character is dropped everywhere, so this query is empty.
        empty = parse_keyword_query("a +b -c")
        @test isempty(empty.must) && isempty(empty.should) && isempty(empty.must_not)
    end

    @testset "a forbidden word matches only where a word starts" begin
        forbid_row = parse_keyword_query("-row")
        @test !is_keyword_match(forbid_row, "count_rows")
        @test !is_keyword_match(forbid_row, "row height")
        @test is_keyword_match(forbid_row, "draw an arrow")
        # A required word matches anywhere, in any of the texts.
        require_row = parse_keyword_query("+row")
        @test is_keyword_match(require_row, "draw_arrow", "nothing here")
        @test !is_keyword_match(require_row, "draw_box", "nothing here")
    end

    api = ApiEntry[ApiEntry(SearchToy, nothing)]

    @testset "the classes filter the hits of search_api" begin
        found = search_api("row"; api = api)
        for name in ("count_rows", "table_row_height", "draw_arrow")
            @test occursin(name, found)
        end
        # `-row` drops the two names where a word starts with it, and keeps `arrow`.
        found = search_api("row -row"; api = api)
        @test occursin("draw_arrow", found)
        @test !occursin("count_rows", found)
        @test !occursin("table_row_height", found)
        # `+table` keeps what says "table" and drops the arrow.
        found = search_api("+table row"; api = api)
        @test occursin("count_rows", found)
        @test occursin("table_row_height", found)
        @test !occursin("draw_arrow", found)
        # Either alternative finds its entry.
        found = search_api("arrow|pane"; api = api)
        @test occursin("draw_arrow", found)
        @test occursin("arrange_panes", found)
        @test !occursin("count_rows", found)
    end

    @testset "a phrase matches its words together and in order" begin
        @test occursin("mark_whole_line", search_api("\"whole line\""; api = api))
        @test occursin("No API matches", search_api("\"line whole\""; api = api))
        # Two plain words match in any order.
        @test occursin("mark_whole_line", search_api("line whole"; api = api))
    end

    @testset "a query that can not search says why" begin
        @test occursin("Provide a search query", search_api("a"; api = api))
        @test occursin("Provide a word to look for", search_api("-row"; api = api))
        @test occursin("Unknown search mode \"fuzzy\"", search_api("row"; mode = "fuzzy", api = api))
        @test occursin("Provide a search query", search_guides("a"; mode = "description"))
    end

    @testset "the regex mode reads a string as a pattern" begin
        @test occursin("count_rows", search_api("^SearchToy\\.count"; mode = "regex", api = api))
        @test occursin("Invalid regex", search_api("(unclosed"; mode = "regex", api = api))
        @test occursin("Invalid regex", search_guides("(unclosed"; mode = :regex))
        # The mode is read without case.
        @test occursin("count_rows", search_api("^SearchToy\\.count"; mode = :Regex, api = api))
        # A `Regex` is a pattern whatever the mode says.
        @test occursin("count_rows", search_api(r"count_rows"; mode = "keywords", api = api))
    end

    @testset "a description without a meaning model is searched by its words" begin
        found = search_api("put the panes where the person wants them";
                           mode = "description", api = api)
        @test startswith(found, "No meaning model was given")
        @test occursin("arrange_panes", found)
        guides = search_guides("how the selection moves"; mode = "description")
        @test startswith(guides, "No meaning model was given")
        @test occursin("resource://guide/", guides)
    end

    @testset "the tools take a mode and no regex flag" begin
        set = register_default_tools!(ToolSet(; api = Module[SearchToy]))
        for name in ("search_api", "search_guides")
            tool = only(t for t in list_tools(set) if t.name == name)
            parameters = [p.name for p in tool.parameters]
            @test "mode" in parameters
            @test !("regex" in parameters)
        end
        search = only(t for t in list_tools(set) if t.name == "search_api")
        found = search.handler(nothing, Dict("query" => "row -row", "mode" => "keywords"))
        @test occursin("draw_arrow", found) && !occursin("count_rows", found)
        @test occursin("Invalid regex",
                       search.handler(nothing, Dict("query" => "(unclosed", "mode" => "regex")))
        @test occursin("Provide a search query", search.handler(nothing, Dict("query" => nothing)))
        @test occursin("Provide a search query", search.handler(nothing, Dict{String,Any}()))
        # A missing mode is the keyword mode.
        @test occursin("draw_arrow", search.handler(nothing, Dict("query" => "arrow")))
        @test startswith(search.handler(nothing, Dict("query" => "the arrow between boxes",
                                                      "mode" => "description")),
                         "No meaning model was given")
    end

    @testset "the code a model writes can not widen the declared search" begin
        set = ToolSet(; api = Module[SearchToy])
        @test occursin("No API matches",
                       execute_julia_code!(set, nothing, "search_api(\"CellVector\"; api = [])"))
        @test occursin("count_rows",
                       execute_julia_code!(set, nothing, "search_api(\"rows\"; mode = \"keywords\")"))
    end

    @testset "register_default_tools! carries its own documentation" begin
        @test occursin("Populate",
                       string(@doc ProjecturedKernel.ToolModule.register_default_tools!))
    end

end
end # test_search_query
