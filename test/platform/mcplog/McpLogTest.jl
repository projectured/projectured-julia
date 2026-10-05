# The MCP log: the server task writes the store with no cell, the feed moves the
# calls into the log on the editor task, the log keeps the most recent ones and
# counts them all, and the pane draws a header, a choice and a block for each
# call, with the code of a call and an answer that folds.

# Every text that `node` draws, in the order of drawing.
function _collect_mcp_log_texts(node, found = String[])
    if node isa GraphicsCanvas
        foreach(element -> _collect_mcp_log_texts(element, found), node.elements)
    elseif node isa GraphicsViewport
        _collect_mcp_log_texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, String(node.text))
    end
    found
end

function test_mcp_log_pane()
@testset "MCP log" begin

@testset "a call goes from the store to the log through the feed" begin
    store = McpLogStore()
    log = McpLog(; capacity = 2)
    feed = McpLogFeed(; store, log)
    record_mcp_call!(store; method = "resources/read", name = "resource://guides", answer = "1. guides",
                     duration = 0.002)
    record_mcp_call!(store; method = "tools/call", name = "execute_julia_code", arguments = "1 + 1",
                     answer = "2", duration = 0.01)
    record_mcp_call!(store; method = "tools/call", name = "execute_julia_code", arguments = "error(1)",
                     answer = "ERROR: 1", duration = 0.02, fault = true)
    @test isempty(log.entries)
    @test drain_changes!(feed, nothing) == 3
    @test drain_changes!(feed, nothing) == 0
    # The log keeps the two most recent calls and counts all three.
    @test [e.arguments for e in log.entries] == ["1 + 1", "error(1)"]
    @test log.count == 3 && log.faults == 1
    @test log.held ≈ 0.032
end

@testset "the pane draws the header, the calls, the code and a folded answer" begin
    log = McpLog()
    long_answer = join(("line $i" for i in 1:20), "\n")
    record_mcp_call!(log, McpCallEntry(1.0e9, "tools/call", "execute_julia_code",
                                       "x = 1\nx + 1", long_answer, 0.25, false))
    record_mcp_call!(log, McpCallEntry(1.0e9, "resources/read", "resource://guides", "",
                                       "the guides", 1.5, true))
    projection = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
    pane = print_document(McpLogToWidget(), nothing, log,
                          with_exact_size(PrinterContext(); width = Cell(Int32(800)),
                                          height = Cell(Int32(900)))).output
    texts = _collect_mcp_log_texts(print_document(projection, pane).output)
    @test "2 calls · 1 fault · 1.8 s held the editor" in texts
    @test "execute_julia_code" in texts && "resource://guides" in texts
    @test "answered" in texts && "fault" in texts
    @test "x = 1" in texts && "x + 1" in texts
    @test "line 8" in texts && !("line 9" in texts) && "… 12 more lines" in texts
    # The choice of faults lists the one call that was a fault.
    log.shown.value = "faults"
    texts = _collect_mcp_log_texts(print_document(projection, pane).output)
    @test "resource://guides" in texts && !("execute_julia_code" in texts)
end

@testset "a person who types the name in an empty tab gets the log of the session" begin
    @test make_insertion_document(McpLog) === get_session_mcp_log()
    @test get_document_title(get_session_mcp_log()) == "MCP log"
end

end
end
