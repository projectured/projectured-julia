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
run_window_editor(document, projection, "My data"; backend = SdlBackend(), mcp = true)
```

The server listens at `http://127.0.0.1:9876/mcp`, on the loopback address only. `ProjecturedMcp` must be loaded; the application holds it already.

**One server, one editor.** The server drives the editor it was started with. Two editors need two processes, and the second one needs another port.

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
| `search_api` | finds a module, a type or a function of the loaded packages, by name, by pattern or by description |
| `read_function_documentation` | reads the documentation of one name |
| `search_guides` | searches the guides of this repository |
| `list_resources`, `read_resource` | lists and reads the resources below |
| `execute_julia_code` | runs Julia in the running program, with `editor` bound to the editor |

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

## The limits

- The server answers on the loopback address, with no authentication. Anything that runs on your machine can reach it. Do not start it on a machine you share.
- A client can take a change back with the `undo` tool, and put it back with `redo`, in an editor that keeps a history. The application keeps one; an editor a program builds itself keeps one when it puts an `UndoBuffer` around its document.
- The server stops when the editor stops.
