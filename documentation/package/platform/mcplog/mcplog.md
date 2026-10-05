# MCP log

> **Kind:** design · **Status:** current · **Stands on:** [log.md](../log/log.md), [mcp.md](../../adapter/mcp/mcp.md), [editor.md](../../kernel/editor.md)

The mcplog slice of `ProjecturedPlatform` shows each call that a client made over MCP, and that the server of the editor answered, as a document in a tab. A person reads in it what an agent did: which tool or resource it used, with which arguments, what it got back, how long the call held the editor, and whether the call was a fault. This document says how a call reaches the document from the task of the server.

## How it works

A call travels through three parts, as a message of the [message log](../log/log.md) does.

1. **`McpLogStore`** is a plain object with a lock and a ring of up to 1000 calls. The MCP adapter writes it with `record_mcp_call!(store; method, name, arguments, answer, duration, fault)` when it has answered a call, on the task of the server. The write touches no cell, and it calls the wake function of the editor outside the lock.
2. **`McpLogFeed`** empties the store once per frame, on the editor task, into the `McpLog` document.
3. **`McpLog`** holds `entries`, a `capacity` of 500, and the counts of every call so far: `count`, `faults`, and `held`, the seconds that the calls held the editor. `shown` is what the pane lists. One log exists for each session, `get_session_mcp_log()`, and the insertion name `mcp log` gives it.

A call that the adapter records is one of two: `tools/call`, with the name of the tool, its arguments, its answer and the time it held the editor; or `resources/read`, with the URI and the answer. A call is a fault when its tool threw, or when the code of `execute_julia_code` threw: such code answers the message of its exception, as the REPL does, and the tool set counts such exceptions (`get_evaluation_exception_count`). A call that raises the count is a fault, which is how the adapter tells the two apart. The last exception can not tell it, because two `ErrorException`s with one message are `===`. The protocol library keeps no client name from `initialize`, so the log names no client.

`McpLogToWidget` draws the log as widgets: a header with the counts, a choice of all calls, the tool calls only or the faults only, and one block for each call in a pane that follows the end. A block says the time, the method, the tool or the URI, the duration and `answered` or `fault`; then the code of `execute_julia_code`, one field of Julia code for each line; then the answer, folded after eight lines. A log is read and not edited.

### The theme

`McpLogTheme` holds the texts of the header, of a call, of `answered` and `fault`, of a quiet text, and the gap between the parts. `make_mcp_log_projection(; theme)` fills the styles of the projection with `get_mcp_log_style`.

## How it fits

The slice depends on the kernel for the feed contract, and on the layout, widget and shell slices for the view and the button. Its `__init__` registers the view with `register_natural_graphics!(:mcplog, …)`; the widgets it builds come back through the renderer. `pred_arguments` saves only the capacity.

The `mcp_log` wrapper of `build_editor` gives the editor a `McpLogFeed`. `make_mcp_log_tool()` is the button of the toolbar that opens the log; a host passes it to the `tools` of the `shell` wrapper when its editor serves MCP, because the shell names no tool of an adapter.

The MCP adapter (`ProjecturedMCP`) depends on this slice, and on no other slice of the platform. The slice names no part of the adapter.
