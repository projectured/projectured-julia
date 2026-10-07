# The MCP server

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../../kernel/agent.md), [editor.md](../../kernel/editor.md)

`ProjecturedMCP` lets a client outside the process drive a running editor over the Model Context Protocol (MCP). It renders the tool set of the editor in the form of the protocol and serves it over HTTP on the loopback address. This document says how the server connects to the editor loop, what it serves, where it catches a fault, and what no test covers; [mcp-guide.md](../../../guide/mcp-guide.md) says how a person connects a client.

## How it works

### The seam

The editor has no reference to the protocol. It gets a server by a name:

```julia
run_editor!(make_editor(document, projection; backend); mcp = true)
```

`run_editor!` calls `make_agent_server(:mcp, editor)` with the fields `instructions`, `host` and `port` of its argument `mcp`, each one only when the caller gives it: `mcp = true` for the defaults, or `mcp = (; host, port)`. It calls `start_agent_server!` after `on_start` and before the first frame, so a tool that `on_start` registers is served, and `stop_agent_server!` in a `finally` when the loop ends. `ProjecturedMCP` adds the three methods: `make_agent_server(::Val{:mcp}, editor; kwargs...)` makes an `McpServer`, and the other two call `start_mcp!` and `stop_mcp!`. The package adds `get_agent_server_access` too; see "What an agent needs to connect". When the package is not loaded, the fallback of the kernel throws an error that says no agent server is registered for `:mcp`. So the kernel holds no protocol code and no HTTP dependency. `run_editor!(document, projection; ...)` passes `mcp` to `run_editor!(editor)`.

### The server

`McpServer(editor; instructions, host, port)` makes a server of the `ModelContextProtocol` package with the resources of the tool set. The helper `mcp_server` of that package has no `instructions` keyword, so the constructor sets `instructions` on a new `ServerConfig`. The `initialize` answer of the protocol gives that text to the client. Its default is `DEFAULT_MCP_INSTRUCTIONS`, a short prompt that names no domain, because this package does not depend on the assistant.

`host` and `port` say where the server listens. A `port` of `0` takes a free port: `McpServer` finds one with `listenany` from 20000 and keeps its number, so `get_agent_server_access` can give the URL. Their defaults are `DEFAULT_MCP_HOST` and `DEFAULT_MCP_PORT`, `127.0.0.1` and `9876`. `start_mcp!` registers the tools, makes an `HttpTransport` at that host and port with the endpoint `/mcp`, connects it, and runs the server on an `@async` task. `start!` of the library installs a logger of its own as the global logger, and the library has no option to keep the logger that is there. So `start_mcp!` waits until the loop of the server runs, for at most 10 seconds, and then puts back the logger that was installed before. The task of the server runs under that logger as its task logger, which comes before the global logger. So the record that `start!` logs as its loop starts goes to that logger too, and the logger of the library writes nothing to stderr. The capture of the message log therefore keeps its records when the editor runs with `--mcp`; see [log.md](../../platform/log/log.md). `stop_mcp!` stops the server and closes the transport. `stop!` of the library only marks the server as stopped, and the loop of the server ends and the port is free only when the transport closes. `stop_mcp!` ignores only a `ServerError` of the library.

### The secret

`McpServer(editor; secret = true)` makes a random secret of 32 bytes, as 64 hexadecimal characters, from `RandomDevice`. The default is `secret = false`, which makes no secret. A server with a secret answers only a request with the header `Authorization: Bearer <secret>`. Any other request gets the status `401`, so a program of this machine that does not know the secret can not run a tool.

The library of the protocol has no place for a check of a header. So `start_mcp!` of a server with a secret connects the transport with `_connect_with_secret!`. It serves the requests with `HTTP.serve!`, compares the header with the expected value in constant time (`_is_secret_equal`), and hands only a request with the secret to `ModelContextProtocol.handle_request`. The comparison does not return at the first byte that differs, so the time of an answer depends on no byte of the secret. A value of another length gets `401` at once.

A server with a secret also sets `allowed_origins` of the transport to its own origin, `http://<host>:<port>`. A web page on another origin that reaches the loopback address, for example by DNS rebinding, is refused.

### What an agent needs to connect

`get_agent_server_access(server)` is the method of this package for the generic of the kernel. It answers `(name = "projectured", url = "http://<host>:<port>/mcp", headers)`. `headers` holds `"Authorization" => "Bearer <secret>"` for a server with a secret, and nothing for a server without one. The assistant gives this tuple to an external agent when it opens a session; see [acp.md](../acp/acp.md) and [assistant.md](../../platform/assistant/assistant.md).

### One tool set, rendered for the protocol

`_make_tools(editor)` and `_make_resources(editor)` call `register_default_tools!` on `editor.tools`, and then render that set:

- `render_mcp_tools(editor, tools)` makes one `MCPTool` for each `Tool`. The handler of each is a closure over the editor and the tool. It answers the text of the tool as a `TextContent`, which has no media type, so the `result_mime_type` of a tool does not reach the client.
- `render_mcp_resources(resources)` makes one `MCPResource` for each `Resource`. Its data provider calls the provider of the resource and returns the text as `TextResourceContents`.

The assistant in the window uses the same `ToolSet`, so a tool that a program registers before the server starts reaches both. The kernel `Tool` has no wire format: this package renders it for MCP, and each `Llm` adapter renders it for its provider; see [anthropic.md](../anthropic/anthropic.md) and [ollama.md](../ollama/ollama.md).

### On which task a tool runs

The handler runs on the task of the server, and a frame of the editor reads and paints the document on the editor task. So the handler runs the tool through `run_on_editor_task!(editor)`: the call waits in the inbox of the editor, the drain of the next frame runs it on the editor task, and the frame then paints what the tool changed. The server task waits for the answer. When no loop runs, as in a test that calls a handler, the tool runs at once. The turn of the assistant runs its tool calls through the same door, so a tool runs on the editor task for both callers. [editor.md](../../kernel/editor.md) describes the door.

### Where a fault stops

Inside the call on the editor task, the handler calls `tool.handler(editor, args)` inside a `try`. A tool that throws writes a fault record into `editor.faults` under the name of the tool, and the client gets the error text as the answer. So the client always gets an answer, the server task keeps running, and the fault log shows what the client ran into. A new fault record wakes the editor, so the fault draws on the next frame.

When `start_mcp!` can not connect the transport, it writes a fault record and a warning, and the editor runs with no server.

### The MCP log

Each handler writes the call it answered into the store of the MCP log of the
platform, `record_mcp_call!(get_session_mcp_log_store(); …)`: the method, the
tool or the URI, the arguments (the code alone for `execute_julia_code`), the
answer, the seconds the call held the editor, and whether it was a fault. A call
is a fault when its tool threw, or when the code of `execute_julia_code` threw,
which the tool answers as a message; the tool set counts such exceptions
(`get_evaluation_exception_count`), and a call that raises the count is a fault.
The count tells it and the last exception does not, because two
`ErrorException`s with one message are `===`. A
read of a resource is recorded the same way. The `mcp_log` wrapper moves the
calls into a document that a tab shows; [mcplog.md](../../platform/mcplog/mcplog.md)
describes it.

### What a client can change

The tool `execute_julia_code` runs Julia in the process of the editor, with `editor` bound. A client reads the data, makes an `Operation` and applies it with `evaluate_operation(editor, operation)`, the same call that a key press makes. No tool patches text.

## How it fits

The code is the slice `McpModule`, in `source/adapter/mcp/`: `McpModule.jl` holds its imports and its exports, and `ProjecturedMCP` includes that file and exports the same names.

`ProjecturedMCP` depends on `ModelContextProtocol`, on `HTTP`, `Random` and `Sockets` for the free port and the secret, on the kernel and on the platform, of which it uses the `mcplog` slice and the essential names. It declares the triggers `Projectured` and `ModelContextProtocol` with the default `auto`, so AutoIntegration loads it when both are loaded; see [autointegration.md](../../autointegration/autointegration.md). It re-exports the essential names of `ProjecturedPlatform.EssentialsModule`, which is why `using ProjecturedMCP` loads the platform; see [essentials.md](../../platform/essentials/essentials.md). From the kernel it takes the `agent` seam with `run_on_editor_task!`, `record_fault!` and the `tool` layer, from which it uses `Tool`, `Resource`, `ToolSet`, `list_tools`, `list_resources` and `register_default_tools!`. [agent.md](../../kernel/agent.md) describes those layers. The package has no `__init__`: its three methods are its registration.

`run_editor!` uses it with `mcp = true`, and the application starts it with `--mcp`, or with `--mcp=PORT` or `--mcp=HOST:PORT` at another address. The package binds no meaning model to the tool set. An MCP client runs no turn of the assistant, so the application binds the meaning model of its backend in `on_start`, and a search by description ranks by meaning for the client too.

## Design decisions

- **The editor names the server by a symbol.** The kernel reaches the server through `make_agent_server`, `start_agent_server!` and `stop_agent_server!`, and never names `McpServer`, so the protocol and its HTTP dependency stay in an opt-in package. `make_llm` has the same shape. See [plan/done/kernel-agent-stack.md](../../../../plan/done/kernel-agent-stack.md).
- **One tool set serves the assistant and an external client.** Two sets would answer the same question in two ways, and a model would work in the window and fail over MCP. The cost is that each client gets the union of the tools that either one needs. See section 12 of [architecture-decisions.md](../../../design/architecture-decisions.md).
- **The fault barrier is in this package.** The handler is the one place that can both answer the client and write the fault, so the server does not depend on the library for its barrier. See [plan/done/the-editor-survives-a-fault.md](../../../../plan/done/the-editor-survives-a-fault.md), phase 6.
- **A change goes through `evaluate_operation`.** A client has no second way to change a document, so a change from a client is the same kind of change as a key press.
- **The whole tool call runs on the editor task.** A tool is any code, `execute_julia_code` above all, so the server can not tell which call writes a document. The cost is that the editor draws no frame while a tool runs.

## Usage

```julia
run_editor!(document, projection; window = (; title = "My data"), mcp = true)

mcp = McpServer(editor; instructions = "You operate a JSON editor.")
start_mcp!(mcp)                  # http://127.0.0.1:9876/mcp
stop_mcp!(mcp)

mcp = McpServer(editor; port = 9900)   # http://127.0.0.1:9900/mcp

mcp = McpServer(editor; port = 0, secret = true)   # a free port, and a bearer secret
get_agent_server_access(mcp)     # (name, url, headers) for an agent
```

- Tests: `test_mcp_tools()` and `test_mcp_resources()` in `test/projectured/editor/McpTest.jl` cover the tool set that the server renders: `execute_julia_code`, the searches and the documentation resources. `test_mcp_tool_runs_on_editor_task()` in the same file checks that a handler called from another task runs its tool only when the editor drains its inbox. `test_mcp_server()` starts a server at a free port and stops it, and checks that the port is free again. It checks that the global logger after the start is the capture of the message log that was installed before, that the record `start!` logs as its loop starts reaches the store of the capture, and that a message logged after the start reaches it too. It also runs `run_editor!` with a server, and a client lists over HTTP the tools of the set, with a tool that `on_start` registered, and calls that tool, which runs on the task of the loop. No test calls `render_mcp_resources`, or reads a resource over HTTP.

## Limits

- **A tool call holds the frame.** The editor draws no frame while a tool runs on its task. The first search by description of a build can wait up to 30 seconds for the vectors of the meaning model, and the window does not draw in that time.
- **A tool can not wait for a frame.** A tool runs between two frames on the editor task, and the next frame starts when the tool returns. So code in `execute_julia_code` that waits for a frame, or for a posted operation to be applied, does not see it before it returns.
- **The server renders the tool set once, when it starts.** `run_editor!` starts it when the loop starts, so the `undo` and `redo` tools that the application registers between `make_editor` and `run_editor!` are served. A tool that is registered after `start_mcp!` does not reach a client: the library of the protocol lists its own vector of tools, and it calls no code of this package when a client lists them.
- A server made with `secret = false`, the default, listens on the loopback address with no authentication. Every program on the machine can reach it. A server with `secret = true` answers `401` to a request without the secret.
- One server serves one editor.
