# The MCP server

> **Kind:** reference · **Status:** current · **Stands on:** [concepts.md](../../design/concepts.md)

How an external client reaches a running editor: the server, what it offers, and the seam that keeps the editor free of the protocol. [mcp-guide.md](../../guide/mcp-guide.md) is the same subject for a person connecting a client.

## The seam

The editor has no reference to the Model Context Protocol. It gets an agent server by a name:

```julia
run_editor!(backend, projection, document; mcp = true)
```

`run_editor!` calls `make_agent_server(:mcp, editor)`, and `ProjecturedMcp` is the package that answers that call. Loading the package registers the method; not loading it means `mcp = true` finds nothing and the editor says so. So the kernel carries no protocol code and no HTTP dependency.

`start_agent_server!` and `stop_agent_server!` are the other two functions of the seam. The editor starts the server before the first frame and stops it when the loop ends.

## What the server offers

`_make_tools(editor)` and `_make_resources(editor)` call `register_default_tools!` on the tool set of the editor, and then render that set for the protocol:

- `render_mcp_tools(editor, tools)` makes one MCP tool for each `Tool` of the set.
- `render_mcp_resources(resources)` makes one MCP resource for each `Resource`, whose data provider answers the text.

**One tool set, two clients.** The assistant in the window reads the same set, so a tool that an application registers is there for both, with no second registration. That is the decision behind it: [architecture-decisions.md](../../design/architecture-decisions.md), section 12.

## The transport

```julia
transport = HttpTransport(host = "127.0.0.1", port = 9876, endpoint = "/mcp")
```

The server listens on the loopback address only, with no authentication, and it serves one editor. A plain GET answers a health check; a POST carries the JSON-RPC of the protocol. A client that speaks HTTP MCP connects with three facts: the transport, the address and the endpoint.

## What a client can change

The tool `execute_julia_code` runs in the process of the editor, with `editor` bound. A client reads the data, builds an `Operation` and applies it with `evaluate_operation(editor, operation)`, which is the same path a key press takes. There is no second way in, and no way that patches text.

## Where to look

| Name | What it does |
| --- | --- |
| `McpServer(editor; instructions)` | the server over one editor, with the prompt it gives a client |
| `start_mcp!`, `stop_mcp!` | start and stop it |
| `render_mcp_tools`, `render_mcp_resources` | the tool set, in the shape the protocol needs |

The whole slice is `source/mcp/Mcp.jl`, and `test/projectured/editor/McpTest.jl` drives it.
