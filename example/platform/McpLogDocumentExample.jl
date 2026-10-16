# An MCP log of two calls: a tool that answered and a resource read that failed.
function make_mcp_log_document_example()
    log = McpLog()
    record_mcp_call!(log, McpCallEntry(0.0, "tools/call", "execute_julia_code", "1 + 1", "2", 0.01, false))
    record_mcp_call!(log, McpCallEntry(1.0, "resources/read", "resource://guide/missing", "", "not found", 0.002, true))
    log
end
