# The MCP server

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../kernel/agent.md), [editor.md](../kernel/editor.md)

`ProjecturedMcp` lets a client outside the process drive a running editor over the Model Context Protocol (MCP). It renders the tool set of the editor in the form of the protocol and serves it over HTTP on the loopback address. This document says how the server connects to the editor loop, what it serves, where it catches a fault, and what no test covers; [mcp-guide.md](../../guide/mcp-guide.md) says how a person connects a client.

## How it works

### The seam

The editor has no reference to the protocol. It gets a server by a name:

```julia
run_editor!(backend, projection, document; mcp = true)
```

`run_editor!` calls `make_agent_server(:mcp, editor)`, with `instructions = mcp_instructions` when the caller gives a prompt. It calls `start_agent_server!` before `on_start` and before the first frame, and `stop_agent_server!` in a `finally` when the loop ends. `ProjecturedMcp` adds the three methods: `make_agent_server(::Val{:mcp}, editor; kwargs...)` makes an `McpServer`, and the other two call `start_mcp!` and `stop_mcp!`. When the package is not loaded, the fallback of the kernel throws an error that says no agent server is registered for `:mcp`. So the kernel holds no protocol code and no HTTP dependency. `run_window_editor` passes `mcp` and `mcp_instructions` to `run_editor!`.

### The server

`McpServer(editor; instructions)` makes a server of the `ModelContextProtocol` package with the resources of the tool set. The helper `mcp_server` of that package has no `instructions` keyword, so the constructor sets `instructions` on a new `ServerConfig`. The `initialize` answer of the protocol gives that text to the client. Its default is `DEFAULT_MCP_INSTRUCTIONS`, a short prompt that names no domain, because this package does not depend on the assistant.

`start_mcp!` registers the tools, makes `HttpTransport(host = "127.0.0.1", port = 9876, endpoint = "/mcp")`, connects it, and runs the server on an `@async` task. `stop_mcp!` stops the server and ignores only a `ServerError` of the library.

### One tool set, rendered for the protocol

`_make_tools(editor)` and `_make_resources(editor)` call `register_default_tools!` on `editor.tools`, and then render that set:

- `render_mcp_tools(editor, tools)` makes one `MCPTool` for each `Tool`. The handler of each is a closure over the editor and the tool.
- `render_mcp_resources(resources)` makes one `MCPResource` for each `Resource`. Its data provider calls the provider of the resource and returns the text as `TextResourceContents`.

The assistant in the window uses the same `ToolSet`, so a tool that a program registers before the server starts reaches both. The kernel `Tool` has no wire format: this package renders it for MCP, and each `Llm` adapter renders it for its provider; see [llm.md](../llm/llm.md).

### Where a fault stops

The handler of each tool calls `tool.handler(editor, args)` inside a `try`. A tool that throws writes a fault record into `editor.faults` under the name of the tool, and the client gets the error text as the answer. So the client always gets an answer, the server task keeps running, and the fault log shows what the client ran into. After each call, the handler calls `wake_editor!`, so a change that the tool made, or its fault, draws on the next frame.

When `start_mcp!` can not connect the transport, it writes a fault record and a warning, and the editor runs with no server.

### What a client can change

The tool `execute_julia_code` runs Julia in the process of the editor, with `editor` bound. A client reads the data, makes an `Operation` and applies it with `evaluate_operation(editor, operation)`, the same call that a key press makes. No tool patches text.

## How it fits

`ProjecturedMcp` depends on `ModelContextProtocol` and on the kernel. From the kernel it takes the `agent` seam, `record_fault!`, `wake_editor!` and the `tool` layer, from which it uses `Tool`, `Resource`, `ToolSet`, `list_tools`, `list_resources` and `register_default_tools!`. [agent.md](../kernel/agent.md) describes those layers. The package has no `__init__`: its three methods are its registration.

`run_editor!` and `run_window_editor` use it with `mcp = true`, and the application starts it with `--mcp`. The package binds no meaning model to the tool set. An MCP client runs no turn of the assistant, so the application binds the meaning model of its backend in `on_start`, and a search by description ranks by meaning for the client too.

## Design decisions

- **The editor names the server by a symbol.** The kernel reaches the server through `make_agent_server`, `start_agent_server!` and `stop_agent_server!`, and never names `McpServer`, so the protocol and its HTTP dependency stay in an opt-in package. `make_llm` has the same shape. See `plan/done/kernel-agent-stack.md`.
- **One tool set serves the assistant and an external client.** Two sets would answer the same question in two ways, and a model would work in the window and fail over MCP. The cost is that each client gets the union of the tools that either one needs. See section 12 of [architecture-decisions.md](../../design/architecture-decisions.md).
- **The fault barrier is in this package.** The handler is the one place that can both answer the client and write the fault, so the server does not depend on the library for its barrier. See `plan/done/the-editor-survives-a-fault.md`, phase 6.
- **A change goes through `evaluate_operation`.** A client has no second way to change a document, so a change from a client is the same kind of change as a key press.

## Usage

```julia
run_window_editor(document, projection, "My data"; backend = SdlBackend(), mcp = true)

mcp = McpServer(editor; instructions = "You operate a JSON editor.")
start_mcp!(mcp)                  # http://127.0.0.1:9876/mcp
stop_mcp!(mcp)
```

- Tests: `test_mcp_tools()` and `test_mcp_resources()` in `test/projectured/editor/McpTest.jl` cover the tool set that the server renders: `execute_julia_code`, the searches and the documentation resources. No test makes an `McpServer`, calls `start_mcp!`, `stop_mcp!`, `render_mcp_tools` or `render_mcp_resources`, or connects a client.

## Limits

- **A tool writes the document from the server task.** The handler runs on the `@async` task of the server, and `execute_julia_code` changes `editor.document` there directly, and not through `post_operation!`, the inbox that orders such writes with the frame. A frame that runs between two writes can read a state that is half done. `plan/done/the-editor-survives-a-fault.md`, section 9, records this as open work. The assistant turn has the same fault.
- **The server renders the tool set once, when it starts.** A tool that is registered after `start_mcp!` does not reach a client. `run_editor!` starts the server before it calls `on_start`, so the `undo` and `redo` tools that the application registers in `on_start` are not served over MCP.
- The server listens on the loopback address with no authentication. Every program on the machine can reach it.
- The port is 9876 in `start_mcp!`, and no keyword changes it. So only one server can listen on a machine.
- One server serves one editor.
