# An external AI client over MCP

> **Kind:** procedure · **Status:** current · **Stands on:** [assistant-guide.md](assistant-guide.md)

How to let an external client, for example Claude Code, drive a running ProjecturEd over the Model Context Protocol (MCP). The client gets the same tools as the assistant inside the window.

## Start the server

From the application:

```sh
bin/projectured --mcp notes.md
```

From your own code, the same editor takes a keyword:

```julia
run_editor!(document, projection; window = (; title = "My data"), mcp = true)
```

By default, the server listens at `http://127.0.0.1:9876/mcp`, on the loopback address only. `ProjecturedMCP` must be loaded; the application holds it already.

To listen at another port, give it after `--mcp=`. To listen at another address too, give the host and the port:

```sh
bin/projectured --mcp=9900 notes.md            # http://127.0.0.1:9900/mcp
bin/projectured --mcp=localhost:9900 notes.md  # the host by its name
```

From code, `mcp = (; host, port)` says where the server listens, and a field that you do not give keeps its default.

**One server, one editor.** The server drives the editor it was started with. To serve two editors on one machine, give each one its own port.

## Connect a client

For Claude Code:

```sh
claude mcp add --transport http projectured http://127.0.0.1:9876/mcp
```

A generic client needs the same three facts: the transport is HTTP, the address is `http://127.0.0.1:9876`, and the endpoint is `/mcp`.

## What the client gets

The tools are the tool set of the kernel, so a client and the assistant in the window can do the same things.

| Tool | What it does |
| --- | --- |
| `search_api` | finds a module, a type or a function by name, by pattern or by description: in the API that the tool set declares, or in every loaded `Projectured` package when it declares none. The application declares its API. |
| `read_function_documentation` | reads the documentation of one name |
| `search_guides` | searches the guides of this repository |
| `list_resources`, `read_resource` | lists and reads the resources below |
| `execute_julia_code` | runs Julia in the running program, with `editor` bound to the editor; a verb acts on that editor, so the code does not pass it |

The application adds `undo` and `redo`, which take the last change back and put it back, as a person does.

The resources are named by a URI:

| Resource | What it holds |
| --- | --- |
| `resource://guides` | every guide, each with its summary |
| `resource://guide/<name>` | one guide in full |
| `resource://modules`, `resource://module/<name>` | the loaded modules |
| `resource://type/<name>`, `resource://function/<name>` | one type or one function |

A guide name comes from its path: `documentation/guide/setup-guide.md` is `guide/setup-guide`, and `documentation/package/kernel/reference.md` is `kernel/reference`. So the URI of the first one is `resource://guide/guide/setup-guide`.

## What a client can change

`execute_julia_code` runs in the process of the editor. A client can read the data, build an operation and apply it with `evaluate_operation(editor, operation)`, which is the one way to change the data. A change from a client is the same kind of change as a key press.

A tool runs on the task of the editor, between two frames, and the client gets the answer when the tool returns. So a change from a client never meets a frame half way, and the frame after the call draws it.

## The limits

- The server answers on the loopback address, with no authentication. Anything that runs on your machine can reach it. Do not start it on a machine you share.
- The server publishes the tools that the tool set has when the server starts, and the application starts it after it registered `undo` and `redo`. A tool that a program registers later reaches the assistant in the window and not an MCP client.
- The window draws nothing while a tool runs. A long evaluation holds the window for its whole time.
- The server stops when the editor stops.
