# The ACP agent connection

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../../kernel/agent.md), [assistant.md](../../platform/assistant/assistant.md), [mcp.md](../mcp/mcp.md)

`ProjecturedACP` connects the assistant to an external agent that speaks the Agent Client Protocol (ACP), version 1. Its built-in agent runs Claude Code: the package [ClaudeCodeACP.jl](https://github.com/projectured/ClaudeCodeACP.jl) runs in the process of the editor and starts the `claude` program that the person installed. Another agent, such as the adapter `claude-agent-acp`, runs in a child process. The agent owns its model, its tools and its history. It is an opt-in package that implements the external direction of the `agent` layer of the kernel. This document says how the package starts the agent, how it translates the messages of the agent into the events of the kernel, where an event goes during a prompt and between two prompts, how a permission request reaches a person, and why the package is built so.

## How it works

### The seam

The kernel declares the generics of a connection in `source/kernel/agent/AgentConnectionInterface.jl`; [agent.md](../../kernel/agent.md) describes them. The package adds a method to each one for `AcpConnection`.

| Generic | What the ACP connection does |
| --- | --- |
| `make_agent_connection(::Val{:acp}; command, environment, directory, session_meta, streams)` | makes an `AcpConnection`; it starts nothing |
| `start_agent_connection!` | starts the process of the agent and sends `initialize` with `protocolVersion: 1` |
| `open_agent_session!` | with a `session_id`, sends `session/resume` when the answer to `initialize` has `sessionCapabilities.resume`, and returns that id; else, or when the answer to the resume is an error, sends `session/new`. Either request goes with the working directory, the MCP servers and, in the `_meta`, the `instructions` as `claudeCode.options.systemPrompt.append`, the key where the Claude agents of ACP read an addition to the system prompt; gives the `configOptions` of the answer to `on_event`, keeps `events`, the queue of the session, and returns the session id |
| `send_agent_prompt!` | sends `session/prompt` and waits for its answer; returns the stop reason |
| `cancel_agent_prompt!` | sends the notification `session/cancel` and answers each waiting request as cancelled |
| `cancel_agent_subagent!` | sends the notification `session/cancel` with the session id of the child session of the subagent |
| `stop_agent_background_task!` | sends the extension request `_session/stop_background_task {sessionId, taskId}`; answers `true` for a result, `false` for an error answer |
| `set_agent_option!` | sends `session/set_config_option` and gives the options of the answer to `on_event` |
| `close_agent_session!` | sends `session/close`, when the agent lists that capability |
| `stop_agent_connection!` | ends the agent and its process group |

`command` is the program of the agent and its arguments, such as `["claude-agent-acp"]`. An empty `command` starts the built-in agent: `ClaudeCodeACP.serve_agent` on a task of this process, on two `Base.BufferStream`s, so the connection talks to it as to any other agent. The close of the connection ends the input of the built-in agent, which then ends each of its sessions and their `claude`. `environment` adds variables to the environment of the agent. `session_meta` is the `_meta` object that `session/new` sends, for an agent that reads options there: a dictionary, or its JSON text. `streams` is a pair of `IO` objects that replaces the process; a test uses it for an agent in the same process.

The capabilities of `initialize` give the agent no file access and no terminal: `fs.readTextFile`, `fs.writeTextFile` and `terminal` are `false`. A request for one of them gets the error "method not found". They take the work of an agent: `subagents: {}`, `plan: {}` and `session: {notices: {}, compaction: {}}`, which are unstable types of the schema, and `_meta.backgroundTasks: {}` for the extension notification `_session/background_task`. An agent sends these updates only to a client that advertises them. The client names itself `projectured` and sends its package version. When the agent answers with another protocol version, `start_agent_connection!` stops the agent and throws an error.

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

### A picture in a prompt

`_make_prompt_blocks(connection, prompt)` writes an `LlmImage` as `ACP.ImageContent(data = base64, mime_type)` when the agent advertises `promptCapabilities.image` (`_has_prompt_capability`). Otherwise it writes the text line "(A picture is left out: the agent takes no pictures.)". A prompt and a steer (`_session/steering`) both use it. ClaudeCodeACP 0.1.7 advertises `image = true` and gives Claude a png, jpeg, gif or webp picture as an image block of the user message. Another type gets `INVALID_PARAMS`.

### The translation of an update

The agent reports its work as `session/update` notifications. `AcpUpdate.jl` translates each one into the events of the kernel, so no caller reads the wire format.

| `sessionUpdate` | Events |
| --- | --- |
| `agent_message_chunk` | `LlmTextStart` at the first chunk, then `LlmTextDelta` |
| `agent_thought_chunk` | `LlmThinkingStart` at the first chunk, then `LlmThinkingDelta` |
| `tool_call`, `tool_call_update` | one `AgentToolCallUpdate` |
| `plan` | one `AgentPlanUpdate` with the whole plan and the empty id |
| `plan_update` | one `AgentPlanUpdate` with the `planId`: its `items` give `entries`, its `markdown` gives `markdown`, its `file` gives `uri` |
| `plan_removed` | one `AgentPlanUpdate` with the `planId` and `is_removed` |
| `notice` | one `AgentNoticeUpdate` |
| `compaction_update` | one `AgentCompactionUpdate`; its `summary` blocks are its text, one on each line |
| `subagent_update` | one `AgentSubagentUpdate`; the connection keeps its child session |
| a `session/update` of a child session | each of its events, as the `event` of an `AgentSubagentUpdate` of the child, one level for each parent |
| `user_message_chunk` of a child session | an `LlmMessage(:user, …)`, the prompt of the subagent |
| `session_info_update` | one `AgentSessionInfoUpdate` with its `title` and `_meta.processId` |
| the notification `_session/background_task` | one `AgentBackgroundTaskUpdate` |
| any other kind | no event |

ACP sends text with no frame around it, and the events of the kernel frame a block with a start and a stop. So an `AcpTurn` keeps the kind of the open block and the `messageId` of the message. A chunk of another kind or of another `messageId`, a new tool call and a plan close the open block first. Only the reader task changes this state. A permission request arrives on a task of its own and leaves it as it is; the assistant closes its own open block before it draws the card. The end of the prompt closes the last block. An `available_commands_update` becomes an `AgentCommandsUpdate`, with the `hint` of the `input` of each command as its `input_hint`.

**The usage and the title.** A `usage_update` becomes an `AgentUsageUpdate` with `used`, `size`, and the `amount` and `currency` of its optional `cost`. A `session_info_update` becomes an `AgentSessionInfoUpdate` with its `title`, and with the integer of its `_meta.processId` as `process_id`.

**The options of a session.** The connection reads the `configOptions` of `session/new`, of the answer to `session/set_config_option` and of a `config_option_update`, and keeps the last ones of each session, also outside a prompt. A group of values shows as values. A `current_mode_update` names only the new mode, so the connection answers it as the kept options with the option of the category `mode` set to it. Each of these updates reaches the prompt that runs as an `AgentOptionsUpdate`. The connection keeps no `on_event` of `open_agent_session!` or `set_agent_option!` after the call.

An `AgentToolCallUpdate` takes its `name` from the field `name`, or else from `_meta.claudeCode.toolName`, where `claude-agent-acp` and `claude-code-acp` put it. The `output` is the text of the content of the call. A diff becomes its path and its lines marked `-` and `+`. When the content is one `resource` block, the `output` is its `text`, and `output_mime_type` and `output_uri` are its `mimeType` and its `uri`. `claude-code-acp` gives the clean text of a file that `Read` read so, with the media type of its extension.

### Where an event goes

A connection keeps no `on_event` of a session, because the caller captures the editor in it. So an event of a session goes to one of two places:

- **During a prompt**, to the `on_event` of `send_agent_prompt!`.
- **Between two prompts**, to the `AgentEventQueue` that `open_agent_session!` took as `events`, after the same translation. The caller drains the queue. A session that opened with no queue drops these events. The options of a session stay current in the connection in either case, for `set_agent_option!` and a `current_mode_update`.

The text of a session between two prompts has its own frame, as an `AcpTurn` in `session_frames`, so `claude` that starts a turn by itself after a background task ends gives framed text to the queue. The start of the next prompt closes that frame, and its last stop goes to the queue.

An agent can send an update of a new session just after its answer to `session/new`, before the call of `open_agent_session!` has the id; `claude-agent-acp` sends its commands so. While an open waits for its answer, an update of a session with no queue and no parent waits in `opening_events`, and the open puts it into the queue of its session when it has the id. The end of the last open drops the rest.

### The work of an agent

**Subagents.** A `subagent_update` on a session announces or changes a child session, the session of a subagent. The connection keeps the parent of each child in `session_parents`. A `session/update` whose `sessionId` is a child goes, after its translation, to its parent as the `event` of an `AgentSubagentUpdate` of the child, and on up to the session that the client opened, one level for each parent; from there it goes where an event of that session goes. Each child has its own `AcpTurn`, so the frame of its text is its own. An idle state of a child closes the block that the child left open. The `user_message_chunk` of a child is the prompt of its subagent, an `LlmMessage` of the role `:user`; the chunk of a session of the client is the prompt that the client sent, and gives no event. A close of a session forgets its children.

The `state` of an `AgentSubagentUpdate` comes from `state.state` (`running`, `idle`, `requires_action`, `unknown`), its `stop_reason` from `state.stopReason`, and `can_cancel` from `capabilities.cancel`. A key that the update leaves out gives `nothing`, which keeps the value before.

**Background tasks.** ACP has no type for them, so the extension notification `_session/background_task` carries them, with the params `{sessionId, taskId, kind, title, status, startTime, canStop, toolCallId?, subagentId?, outputUri?, summary?, endTime?}`. The first notification of a task carries its whole state, and a later one only the keys that changed, so an absent key is `nothing`. The times come in milliseconds since 1970, and the event holds seconds. The handler takes it with the method of `ACP.receive_notification` for a method that the protocol does not name, and sends it where an update of its session goes.

**The process of a session.** `claude-code-acp` sends the process id of the `claude` of a session in `session_info_update._meta.processId`, in the first prompt after each start of `claude`. An agent in a child process (`command` not empty) gets the id of that process, once, as `AgentSessionInfoUpdate(nothing; process_id)` at the head of the queue of each session that opens. The built-in agent runs in this process, so it gets an id only from `_meta`.

### The keys of `_meta.claudeCode`

ACP has no field for some data that a Claude agent of ACP sends, and the agent puts it in `_meta.claudeCode`. The package reads these keys there, and no other:

| Object | Key | Gives |
| --- | --- | --- |
| a tool call | `toolName` | `name`, when the call has no field `name` |
| a plan entry | `taskId` | `id` of the `AgentPlanEntry` |
| | `description` | `description` |
| | `activeForm` | `active_title` |
| | `blockedBy` | `blocked_by` |
| a `subagent_update` | `usage.totalTokens` | `token_count`; else the `usage.totalTokens` of an idle state |
| | `usage.toolUses` | `tool_call_count` |
| | `usage.durationMs` | `duration`, in seconds |
| | `lastToolName` | `last_tool` |
| | `summary` | `summary` |

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

`session/new`, `session/resume` and `session/prompt` can answer the error code `-32000`. The package then throws an `AgentSignInException` with the title of the agent, the way to sign in that the agent gave in `initialize` as a sentence, for example "Run `claude /login` in the terminal", and one `AgentSignInMethod` for each method of the type `terminal`. The command of a method is the command of the agent with the `args` of the method added and its `env` over the environment of the agent, in the folder of the agent. The built-in agent runs in this process and has no command line. Its program answers the argument `--login` with the command of `ClaudeCodeACP.make_login_command()`, `claude auth login`, so that command stands for its method `claude-login`. The client says in `initialize` that it runs a sign-in in a terminal (`clientCapabilities.auth.terminal`). The package starts no sign-in itself.

`has_agent_sign_out` answers whether the agent advertises `agentCapabilities.auth.logout`, and `sign_out_agent!` then sends `logout`.

### A question in a form

The client advertises `clientCapabilities.elicitation.form`. An `elicitation/create` of the mode `form`, in the session of a prompt that runs, becomes an `AgentQuestionRequest`. Its fields come from the properties of the schema: a string with `oneOf`, `anyOf` or `enum` is a choice, an array of such items a choice of several, a number, an integer and a boolean are what they say, and any other property is a text. The library reads a JSON object into a `Dict`, which keeps no order, so the fields come in the order of their names. Values accept the form, `nothing` declines it, and a cancel of the turn or of the request cancels it. A form outside a prompt, and a request of the mode `url`, which the client does not offer, are cancelled.

## How it fits

The package depends on the kernel and on `AgentClientProtocol`, a package of its own repository in ProjecturedRegistry. It does not depend on `ProjecturedPlatform`: it translates to the events of the kernel, and the assistant draws them. The third-party dependency is the reason that it is an opt-in package; see [package-rules.md](../../../rule/package-rules.md). Its `Project.toml` has no `[auto-integration]` section, so the umbrella never loads it. A person loads it with `using ProjecturedACP`.

The assistant slice builds the connection and drives a turn; [assistant.md](../../platform/assistant/assistant.md) describes that. The agent reaches the tools of the editor through the MCP server of [mcp.md](../mcp/mcp.md). The assistant gives that server to `open_agent_session!` as an entry of `mcp_servers`: a named tuple `(name, url, headers)` that `get_agent_server_access` returns. The package renders each entry as `{"type": "http", "name", "url", "headers": [{"name", "value"}]}`. So ACP carries the conversation, and MCP carries the tools.

The test double `ScriptedAgentConnection` is in `ProjecturedKernelExample`, and never in a package of the main stack. It implements the same generics and keeps the queue of each session, so a test of the assistant needs no agent and no ACP.

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
- **The agent is not an `Llm`.** `stream_turn` answers one round, and `run_turn!` then runs the tool calls. An ACP agent runs its own tools, so an `Llm` wrapper would run each call twice. The connection is a separate direction of the `agent` layer. See [plan/done/the-assistant-talks-to-an-acp-agent.md](../../../../plan/done/the-assistant-talks-to-an-acp-agent.md).
- **The package has no AutoIntegration trigger.** The owner chose that a person loads it by name. The backend `:acp` without the package gives an error that says which package to load.
- **The package speaks version 1.** ACP v2 is a draft. The client sends `protocolVersion: 1` and stops when the agent answers another version.
- **Options of one agent are data, not code.** The `_meta` of a session is a setting of the assistant, `agent_session_meta`, as JSON text. The package reads no option of a particular agent, except the keys of `_meta.claudeCode` that its table lists and `_meta.processId` of a `session_info_update`.
- **One path for an event outside a prompt.** Every event between two prompts goes through the queue of its session, the options, the usage, the title and the commands as well as the work of a subagent or a background task. The queue holds no function, so the document that holds the connection does not hold the editor through it.
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

- `test_acp()` runs the layering guard, `test_acp_update()`, `test_acp_connection()` and `test_acp_transport()`. It needs no network, no Node.js, no `claude` and no sign-in. The transport test also starts the built-in agent and checks that it answers `initialize`, which starts no `claude`, and checks that a child agent gives the id of its process to the queue of a session.
- `ClaudeCodeACP` has its own tests: a fake `claude` that plays recorded turns, driven through ACP.
- `test/adapter/acp/FakeAcpAgent.jl` is a fake agent that runs in the test process, on two `Base.BufferStream`s. Each test gives it the handlers of its methods, so it can also ask the client a question.
- `AgentClientProtocol` has its own tests: the types, a client against an agent in one process, a process, and the recorded messages of `claude-agent-acp`.
- The transport test starts a small child agent written in Julia. It checks that a grandchild of the agent ends when the connection stops, also when the agent ends first, and that a start after the end of an agent starts a new one.
- The tests of the assistant turn use `ScriptedAgentConnection`; see [assistant.md](../../platform/assistant/assistant.md).

## Limits

- The package covers a turn and the state of a session: text, thinking, tool calls, the plans, permission requests, cancel, close, the config options (model, effort, mode), the slash commands, the usage meter and the session title; and the work of an agent: its subagents, its background tasks, its notices, its compactions and the process of a session. Saved sessions, the sign-in in a terminal, forms and an image in a prompt are not implemented.
- A `compaction_summary_chunk` gives no event, so a summary shows only when its `compaction_update` carries it.
- A permission request or a form of a child session finds no prompt, and is answered as cancelled. `claude-code-acp` asks in the session of the client.
- The thinking of Claude arrives only as a summary. The setting `showThinkingSummaries` of the built-in agent turns it on. For the adapter, the `_meta` of the session names it: `claude-agent-acp` spreads `_meta.claudeCode.options` of `session/new` over its own SDK options, and a recent model streams no text of its reasoning unless `thinking.display` is `"summarized"`. The assistant sends `{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}` by default (`agent_session_meta`). Another agent ignores this `_meta`.
- The prompt carries text only. `send_agent_prompt!` throws an `ArgumentError` for another kind of content.
- No test runs the real `claude` or the adapter. A change that only the real agent would catch needs a live check with a signed-in Claude Code.
- The agent edits files with its own tools, outside the operations of the editor.
