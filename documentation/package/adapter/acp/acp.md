# The ACP agent connection

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../../kernel/agent.md), [assistant.md](../../platform/assistant/assistant.md), [mcp.md](../mcp/mcp.md)

`ProjecturedACP` connects the assistant to an external agent that speaks the Agent Client Protocol (ACP), version 1. Its built-in agent runs Claude Code: the package [ClaudeCodeACP.jl](https://github.com/projectured/ClaudeCodeACP.jl) runs in the process of the editor and starts the `claude` program that the person installed. Another agent, such as the adapter `claude-agent-acp`, runs in a child process. The agent owns its model, its tools and its history. It is an opt-in package that implements the external direction of the `agent` layer of the kernel. This document says how the package starts the agent, how it translates the messages of the agent into the events of the kernel, how a permission request reaches a person, and why the package is built so.

## How it works

### The seam

The kernel declares seven generics for a connection in `source/kernel/agent/AgentConnectionInterface.jl`; [agent.md](../../kernel/agent.md) describes them. The package adds a method to each one for `AcpConnection`.

| Generic | What the ACP connection does |
| --- | --- |
| `make_agent_connection(::Val{:acp}; command, environment, directory, session_meta, streams)` | makes an `AcpConnection`; it starts nothing |
| `start_agent_connection!` | starts the process of the agent and sends `initialize` with `protocolVersion: 1` |
| `open_agent_session!` | sends `session/new` with the working directory, the MCP servers and, in the `_meta`, the `instructions` as `claudeCode.options.systemPrompt.append`, the key where the Claude agents of ACP read an addition to the system prompt; gives the `configOptions` of the answer to `on_event`, and returns the session id |
| `send_agent_prompt!` | sends `session/prompt` and waits for its answer; returns the stop reason |
| `cancel_agent_prompt!` | sends the notification `session/cancel` and answers each waiting request as cancelled |
| `set_agent_option!` | sends `session/set_config_option` and gives the options of the answer to `on_event` |
| `close_agent_session!` | sends `session/close`, when the agent lists that capability |
| `stop_agent_connection!` | ends the agent and its process group |

`command` is the program of the agent and its arguments, such as `["claude-agent-acp"]`. An empty `command` starts the built-in agent: `ClaudeCodeACP.serve_agent` on a task of this process, on two `Base.BufferStream`s, so the connection talks to it as to any other agent. The close of the connection ends the input of the built-in agent, which then ends each of its sessions and their `claude`. `environment` adds variables to the environment of the agent. `session_meta` is the `_meta` object that `session/new` sends, for an agent that reads options there: a dictionary, or its JSON text. `streams` is a pair of `IO` objects that replaces the process; a test uses it for an agent in the same process.

The capabilities of `initialize` give the agent no file access and no terminal: `fs.readTextFile`, `fs.writeTextFile` and `terminal` are `false`. A request for one of them gets the error "method not found". The client names itself `projectured` and sends its package version. When the agent answers with another protocol version, `start_agent_connection!` stops the agent and throws an error.

**The registration is a method.** The package adds `make_agent_connection(::Val{:acp}; …)` and has no `__init__`. `get_agent_connection_names()` reads the loaded connections from the method table, so `:acp` exists exactly while the package is loaded. Without the package, `make_agent_connection(:acp)` throws an error that lists the loaded kinds and says to load the package.

### The transport

The package [`AgentClientProtocol`](https://github.com/projectured/AgentClientProtocol.jl) carries the messages. It holds the types of the protocol, generated from its schema, and a connection that talks JSON-RPC 2.0 over two streams, one JSON object on each line. `AcpConnection` keeps that connection in its field `transport`, and gives it an `AcpClientHandler`, which answers what the agent sends.

- **The reader task** of the connection reads the lines and hands each message to its place. A response goes to the request that waits for it. `send_request!` throws a `ProtocolException` for an error answer.
- **A notification of the agent** runs on the reader task, in order, so the chunks of an answer keep their order. The handler must not wait.
- **A request of the agent** runs on a task of its own, so it can wait for a person. A request that the handler does not serve, such as a file or a terminal request, gets the error "method not found".
- **The standard error of the agent** goes to the debug log. The connection logs no message content, because an agent can send account data.

The connection starts the agent in a process group of its own. `close_connection!` closes the input of the agent first, because an agent ends when its input ends. A process that still runs after 5 seconds gets `SIGTERM`, sent to the whole group. After 2 more seconds it gets `SIGKILL`. At the end the group gets `SIGTERM` in any case, because a child of the agent can outlive an agent that ended at the end of its input. So no child of the agent lives on. Each request that waits for an answer throws.

The end of the agent process closes the connection, so a request does not wait for an answer that can not come, even while a child of the agent keeps the output open. `start_agent_connection!` starts an agent again when its connection is closed or its reader ended; the sessions of the old agent ended with it.

The requests that the package sends are the typed requests of `AgentClientProtocol`, such as `PromptRequest`. The translation of the updates reads the JSON object of each update with the defaults of its fields, so a field that an agent leaves out gives no error.

### The translation of an update

The agent reports its work as `session/update` notifications. `AcpUpdate.jl` translates each one into the events of the kernel, so no caller reads the wire format.

| `sessionUpdate` | Events |
| --- | --- |
| `agent_message_chunk` | `LlmTextStart` at the first chunk, then `LlmTextDelta` |
| `agent_thought_chunk` | `LlmThinkingStart` at the first chunk, then `LlmThinkingDelta` |
| `tool_call`, `tool_call_update` | one `AgentToolCallUpdate` |
| `plan` | one `AgentPlanUpdate` with the whole plan |
| any other kind | no event |

ACP sends text with no frame around it, and the events of the kernel frame a block with a start and a stop. So an `AcpTurn` keeps the kind of the open block and the `messageId` of the message. A chunk of another kind or of another `messageId`, a new tool call and a plan close the open block first. Only the reader task changes this state. A permission request arrives on a task of its own and leaves it as it is; the assistant closes its own open block before it draws the card. The end of the prompt closes the last block. An `available_commands_update` becomes an `AgentCommandsUpdate`, with the `hint` of the `input` of each command as its `input_hint`.

**The usage and the title.** A `usage_update` becomes an `AgentUsageUpdate` with `used`, `size`, and the `amount` and `currency` of its optional `cost`. A `session_info_update` becomes an `AgentSessionInfoUpdate` with its `title`. Between two prompts, the connection keeps the latest update of each of the session kinds — options, usage, title, commands — in `waiting_session_events`, and gives them to the next prompt first, under the lock that registers the prompt, so a newer update comes after them.

**The options of a session.** The connection reads the `configOptions` of `session/new`, of the answer to `session/set_config_option` and of a `config_option_update`, and keeps the last ones of each session, also outside a prompt. A group of values shows as values. A `current_mode_update` names only the new mode, so the connection answers it as the kept options with the option of the category `mode` set to it. Each of these updates reaches the prompt that runs as an `AgentOptionsUpdate`. The connection keeps no `on_event` of `open_agent_session!` or `set_agent_option!` after the call.

An `AgentToolCallUpdate` takes its `name` from the field `name`, or else from `_meta.claudeCode.toolName`, where `claude-agent-acp` puts it. The `output` is the text of the content of the call. A diff becomes its path and its lines marked `-` and `+`.

### The permission request

A `session/request_permission` request of the agent waits on a task of its own. The method of `answer_request` for `AcpClientHandler` does this:

1. It looks for the prompt that runs in the session. A request outside a prompt is answered as cancelled.
2. It makes an `AgentPermissionRequest` with the tool call, the options of the agent and a `reply` function.
3. It sends the request to `on_event` and waits on a channel.
4. The first call of `reply` puts the id of the chosen option, or `nothing`, into the channel, and answers `true`. A later call does nothing and answers `false`, so the assistant can show that an answer came after a cancel.
5. The answer is `selected` with the option id, or `cancelled` for `nothing`.

The wait has a bound. `cancel_agent_prompt!`, the end of the prompt and `stop_agent_connection!` each call `reply(nothing)` for every request that waits. So a request never waits after its turn. The agent can also withdraw one request with the notification `$/cancel_request` and its JSON-RPC id: the handler gives `reply(nothing)` to `add_cancel_callback!` of the request, and the agent gets the valid answer `cancelled`. A request that the agent withdrew before the handler shows it does not reach the person.

A worked example: the agent asks to run `execute_julia_code` with the options `allow_once` and `reject_once`. The assistant draws a card with two buttons. The person clicks the first one, `reply("allow_once")` runs, and the agent gets `{"outcome": {"outcome": "selected", "optionId": "allow_once"}}`. If the person presses Escape before the click, the turn is cancelled, `reply(nothing)` runs, and the agent gets `{"outcome": {"outcome": "cancelled"}}`.

### A sign-in that is missing

`session/new` can answer the error code `-32000`. The package then throws an error with the title of the agent and the way to sign in that the agent gave in `initialize`, for example "Run `claude /login` in the terminal". The package starts no sign-in itself.

## How it fits

The package depends on the kernel and on `AgentClientProtocol`, a package of its own repository in ProjecturedRegistry. It does not depend on `ProjecturedPlatform`: it translates to the events of the kernel, and the assistant draws them. The third-party dependency is the reason that it is an opt-in package; see [package-rules.md](../../../rule/package-rules.md). Its `Project.toml` has no `[auto-integration]` section, so the umbrella never loads it. A person loads it with `using ProjecturedACP`.

The assistant slice builds the connection and drives a turn; [assistant.md](../../platform/assistant/assistant.md) describes that. The agent reaches the tools of the editor through the MCP server of [mcp.md](../mcp/mcp.md). The assistant gives that server to `open_agent_session!` as an entry of `mcp_servers`: a named tuple `(name, url, headers)` that `get_agent_server_access` returns. The package renders each entry as `{"type": "http", "name", "url", "headers": [{"name", "value"}]}`. So ACP carries the conversation, and MCP carries the tools.

The test double `ScriptedAgentConnection` is in `ProjecturedKernelExample`, and never in a package of the main stack. It implements the same seven generics, so a test of the assistant needs no agent and no ACP.

## Usage

```julia
using ProjecturedACP
get_agent_connection_names()                    # [:acp]
assistant = Assistant(; backend = :acp)         # the built-in agent: Claude Code
assistant = Assistant(; backend = :acp, agent_command = "my-agent --acp")
run_application(; assistant = :acp)
```

From the shell, `bin/projectured --assistant=acp` and a built `projectured` do the same: the program carries `ProjecturedACP`, and `--agent-command=COMMAND` names the command of the agent for one run.

The default `agent_command` is empty, which starts the built-in agent. It needs Claude Code installed and signed in: `claude auth login` in a terminal, or an existing sign-in of the machine. Another command must be installed; the adapter `@agentclientprotocol/claude-agent-acp`, for example, needs Node.js 22 or newer. The tab of the assistant shows an error turn that says how to sign in when the agent needs it.

## Design decisions

- **The client handles no credential.** It sends no key and reads no token. The agent signs in with its own flow. The agent can send the custom notification `_auth/status_update` with the plan name and the account email; the client drops it unread, and the transport logs no content.
- **ACP carries the conversation and MCP carries the tools.** The agent runs its own tools, but the edits of the editor must stay operations, so that undo works. The agent calls `execute_julia_code` and the other tools through the MCP server of the editor, which runs them on the editor task.
- **The MCP server of a session has a secret.** The server runs Julia code. The assistant starts it on a free port with a random secret, and gives the secret to the agent in the `headers` of the session. Without the secret, any program on the machine could run code. See [mcp.md](../mcp/mcp.md).
- **The agent is not an `Llm`.** `stream_turn` answers one round, and `run_turn!` then runs the tool calls. An ACP agent runs its own tools, so an `Llm` wrapper would run each call twice. The connection is a separate direction of the `agent` layer. See [plan/pending/the-assistant-talks-to-an-acp-agent.md](../../../../plan/pending/the-assistant-talks-to-an-acp-agent.md).
- **The package has no AutoIntegration trigger.** The owner chose that a person loads it by name. The backend `:acp` without the package gives an error that says which package to load.
- **The package speaks version 1.** ACP v2 is a draft. The client sends `protocolVersion: 1` and stops when the agent answers another version.
- **Options of one agent are data, not code.** The `_meta` of a session is a setting of the assistant, `agent_session_meta`, as JSON text. The package reads no option of a particular agent, except the name of a tool that `claude-agent-acp` gives in `_meta.claudeCode.toolName`.
- **The events are neutral.** The text and the thinking use `LlmTextDelta` and `LlmThinkingDelta`, so the handlers that draw a model answer also draw an agent answer.
- **Each connection has its own process.** Two assistants run two agents. The process group end makes sure that no agent outlives its connection.

## The use of a Claude subscription

The design follows six rules. They are facts of the code, and they are not legal advice.

- **R1.** The package reads, stores, logs and forwards no Claude credential, no session token and no account data. It shows no sign-in form.
- **R2.** The package bundles no Claude Code. The built-in agent starts the `claude` program that the person installed, unmodified, through its documented headless mode; another agent is the command that the person configured.
- **R3.** The sign-in completes in the flow of the agent: an existing sign-in, or the terminal command that the agent names.
- **R4.** The label of the agent is its own `agentInfo.title`: "Claude Code" for the built-in agent, whose name says what it runs, and "Claude Agent" for the adapter. The README of the built-in agent says first that Anthropic did not make it.
- **R5.** The integration is generic ACP. Any agent that speaks ACP version 1 can run in place of Claude.
- **R6.** How the use of a plan counts is decided by Anthropic, and it can change. Read the current terms of Anthropic before you rely on a plan.

## Tests

- `test_acp()` runs the layering guard, `test_acp_update()`, `test_acp_connection()` and `test_acp_transport()`. It needs no network, no Node.js, no `claude` and no sign-in. The transport test also starts the built-in agent and checks that it answers `initialize`, which starts no `claude`.
- `ClaudeCodeACP` has its own tests: a fake `claude` that plays recorded turns, driven through ACP.
- `test/adapter/acp/FakeAcpAgent.jl` is a fake agent that runs in the test process, on two `Base.BufferStream`s. Each test gives it the handlers of its methods, so it can also ask the client a question.
- `AgentClientProtocol` has its own tests: the types, a client against an agent in one process, a process, and the recorded messages of `claude-agent-acp`.
- The transport test starts a small child agent written in Julia. It checks that a grandchild of the agent ends when the connection stops, also when the agent ends first, and that a start after the end of an agent starts a new one.
- The tests of the assistant turn use `ScriptedAgentConnection`; see [assistant.md](../../platform/assistant/assistant.md).

## Limits

- The package covers a turn and the state of a session: text, thinking, tool calls, the plan, permission requests, cancel, close, the config options (model, effort, mode), the slash commands, the usage meter and the session title. Saved sessions, the sign-in in a terminal, forms and an image in a prompt are not implemented.
- The thinking of Claude arrives only as a summary. The setting `showThinkingSummaries` of the built-in agent turns it on. For the adapter, the `_meta` of the session names it: `claude-agent-acp` spreads `_meta.claudeCode.options` of `session/new` over its own SDK options, and a recent model streams no text of its reasoning unless `thinking.display` is `"summarized"`. The assistant sends `{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}` by default (`agent_session_meta`). Another agent ignores this `_meta`.
- The prompt carries text only. `send_agent_prompt!` throws an `ArgumentError` for another kind of content.
- No test runs the real `claude` or the adapter. A change that only the real agent would catch needs a live check with a signed-in Claude Code.
- The agent edits files with its own tools, outside the operations of the editor.
