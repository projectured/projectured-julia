# The assistant talks to an ACP agent

> **Status (2026-10-08): PHASE 1 DONE and on `main` since 2026-10-07; phase 2
> partly done.** Steps 1.1 to 1.10, the command line, 2.1, 2.2, 2.3 and the
> request cancel of 2.7 are on `main`. Since the plan
> [acp-is-a-julia-package-and-claude-runs-without-node.md](../done/acp-is-a-julia-package-and-claude-runs-without-node.md),
> the built-in agent of `ProjecturedACP` runs Claude Code, and it is the
> default agent. 2.9 and 2.10 are done too. Open: 2.4, 2.5, 2.6, the prompt queue of 2.7,
> 2.8 and phase 3. The owner answered every question on 2026-10-07; see "Decisions".
> The feature comes in a release after the first one.

## Goal

A person picks an external agent for the assistant pane. The first agent is
Claude, through the adapter `@agentclientprotocol/claude-agent-acp`. The agent
runs its own loop: its model, its built-in tools, its subagents, its skills, its
memory and its extended thinking. The person uses their own Claude plan, or
their own API key.

Projectured keeps three things:

- **The transcript is a projectured document.** Every projection applies to it:
  folds, search, a diff as structure, a plan as a checklist.
- **The agent acts on the live editor through the projectured MCP server.**
  `execute_julia_code` and the other editor tools run on the editor task, so an
  edit stays an operation, and undo works.
- **The projectured loop stays.** `:ollama` and `:anthropic` keep working. An
  ACP agent is a second kind of turn, not a replacement.

The integration is generic. Claude is the first agent, and any agent that
speaks the Agent Client Protocol (ACP) version 1 can be the next one.

## Decisions

The owner answered these on 2026-10-07:

1. **The feature is for a public release.** So the rules of Anthropic about
   sign-in and credentials shape the design. See "The subscription and a public
   release".
2. **The projectured loop stays** beside the ACP agent.
3. **Node.js can be installed when necessary.** The adapter needs it.
4. **This plan is written** in `plan/pending/`.

The owner answered the open points on 2026-10-07. The owner chose two answers.
The owner took the recommendation for every other point:

5. **The mechanisms M1 to M4 are approved, with the proposed names (Q1).** M1
   uses `LlmTextDelta` and `LlmThinkingDelta` again. M2 is a card in the
   transcript. M3 is a token in `headers`. M4 is a group in the settings slice.
6. **Each assistant has its own adapter process (Q2)**, in a field that is not
   data, like `llm`.
7. **Past turns of an ACP assistant are read-only (Q3)** in phase 1. A branch
   from an edited turn can be a later feature.
8. **A duplicate starts a new session (Q4)**, and the transcript gets a note
   that the agent does not have the history. A fork waits until `session/fork`
   is stable.
9. **The list of agents is a group in the settings slice (Q5).**
10. **`ProjecturedACP` loads only when the person loads it (Q6).** The owner
    chose this. It has no AutoIntegration trigger.
11. **The servers of the person stay (Q7).** The projectured server has its own
    name, and the session does not send `strictMcpConfig`.
12. **Anthropic is not asked before the release (G1).** The owner chose this.
    The release follows R1 to R6.
13. **The feature comes in a release after the first one (Q8).** The first
    release does the core only.

## Facts (2026-10-07)

### The protocol

- ACP is JSON-RPC 2.0 over the stdin and stdout of a child process, one JSON
  message on each line. The editor is the client. The agent is the child.
- The stable wire version is `protocolVersion: 1`. The TypeScript SDK and the
  schema are at release 1.7.0 (SDK published 2026-10-02).
- ACP v2 is a draft since 2026-07-20. Its text says: "Don't ship it by default
  in production until we are closer to stabilization", and implementers must
  support v1 and v2 side by side. v2 changes a message, a tool call and its
  output into parts with stable ids that an update patches.
- Stable since v1 was published: `session/list` (2026-03-09),
  `session_info_update` (2026-03-09), `session/resume` (2026-04-22),
  `session/close` (2026-04-23), `logout` (2026-05-21), `additionalDirectories`
  (2026-06-01), `messageId`, `usage_update` and `session/delete` (2026-06-05),
  the `model_config` category (2026-06-24), `$/cancel_request` (2026-06-29),
  boolean config options (2026-07-06), elicitation (2026-07-22), and tool call
  names (2026-09-17).
- `session/fork` is not part of stable ACP v1.
- An HTTP entry of `mcpServers` in `session/new` has `type`, `name`, `url` and
  `headers`, a list of `name` and `value` pairs.
- "MCP over ACP" is a draft RFD. It lets a client give an MCP server through the
  ACP connection itself, with no port. It is not usable now.
- No Julia library for ACP exists. Projectured needs its own transport.

### The adapter, measured on this machine

A probe ran the adapter with the existing Claude sign-in of this machine. The
files are in `/var/tmp/acp-probe/`. The transcript holds the account email, so
it must not go into the repository as it is.

- **Versions.** `@agentclientprotocol/claude-agent-acp` 0.87.0 (published
  2026-10-07) needs Node.js 22 or newer. It uses
  `@anthropic-ai/claude-agent-sdk` 0.3.287 and `@agentclientprotocol/sdk` 1.7.0.
- **The Claude Code binary.** The SDK brings its own binary, Claude Code 2.1.287
  (244 MB, in the optional package `@anthropic-ai/claude-agent-sdk-linux-x64`).
  The adapter uses `CLAUDE_CODE_EXECUTABLE` when it is set, and the bundled
  binary otherwise. It does not use `/usr/bin/claude`.
- **Node.js.** Node.js 24.21.0 (LTS) is in `~/.local/opt/node`. No profile
  changed.
- **`initialize`.** The agent answered:
  - `promptCapabilities`: `image`, `embeddedContext`
  - `mcpCapabilities`: `http`, `sse`
  - `loadSession: true`
  - `sessionCapabilities`: `additionalDirectories`, `close`, `delete`, `fork`,
    `list`, `resume`, `subagents`
  - `auth.logout`
  - `agentInfo.title`: `"Claude Agent"`
  - one auth method: `claude-login`, of type `terminal`, args `["--cli"]`,
    description "Run `claude /login` in the terminal"
  - `_meta`: `claudeCode.promptQueueing`, `steering.supported`
- **`session/new`.** It answered in about 0.5 s with no auth error. The config
  options are:
  - `mode`: `default`, `acceptEdits`, `plan`, `auto`, `bypassPermissions`
  - `model`: `opus` (current), `sonnet`, `fable`, `haiku`, and older ids
  - `effort` (category `thought_level`): `low` to `max`, current `xhigh`
  - `fast`: on or off
  - `agent`: `default`, `claude-code-guide`
- **Prompts.** Three prompts ended with `end_turn` on the existing sign-in.
  - The updates were `agent_message_chunk`, `usage_update` (`used`, `size` =
    1000000), `available_commands_update` (the skills of the person) and
    `session_info_update` (a title).
  - The response carries `usage` with input, output and cache tokens.
- **Thought text did not arrive.** Three prompts gave no `agent_thought_chunk`,
  also with `showThinkingSummaries: true` in the project settings of the probe.
  - The adapter maps a `thinking_delta` to `agent_thought_chunk`.
  - Claude Code asks for thinking with `display: "omitted"` unless
    `showThinkingSummaries` or `--thinking-display` says otherwise.
  - Step 1.7 must find how a client gets the thought text.
- **The agent sends `_auth/status_update`.** It is a custom method that carries
  the plan name and the account email. Projectured must not log or store it.
- **File access.** The adapter has `readTextFile` and `writeTextFile`
  pass-throughs, but I found no built-in tool that calls them in 0.87.0. Claude
  reads and writes files with its own tools.
- **Session options from the client.** The adapter reads
  `_meta.claudeCode.options` in `session/new` and gives it to the SDK on top of
  its own options: `settings`, `strictMcpConfig`, `env`, `extraArgs`,
  `mcpServers` and more.
- **Fork.** The adapter answers a fork as `unstable_forkSession`.
- **Elicitation.** When the client advertises `elicitation.form`, the adapter
  shows the `AskUserQuestion` tool of Claude as a form elicitation. Without it,
  the adapter disables that tool. URL elicitation serves the OAuth of an MCP
  server.

### Projectured now

- The kernel agent stack has two directions
  ([agent.md](../../documentation/package/kernel/agent.md)):
  - **Inbound:** `make_agent_server(:mcp, …)` lets an outside agent drive the
    editor.
  - **Outbound:** `run_turn!` drives an `Llm`.
- `_run_agent_loop!`
  ([AssistantTurn.jl:654](../../source/platform/assistant/AssistantTurn.jl#L654))
  builds the `Llm` for each turn. It derives the messages from the conversation
  at each round, and it posts each part with
  `run_on_editor_task!(…; wait = false)`.
- The MCP server
  ([McpServer.jl](../../source/adapter/mcp/McpServer.jl)) listens at
  `http://127.0.0.1:9876/mcp` by default. The port is a keyword. The transport
  of ModelContextProtocol.jl 0.4.1 can check `Origin` (`allowed_origins`), but I
  found no check of an authorization header.
- `~/.claude.json` names an MCP server `omnet-ide` at the same default URL. The
  agent loads that file too.
- The settings slice
  ([Settings.jl](../../source/platform/settings/Settings.jl)) keeps typed
  groups. Its file is in `~/.config/projectured`, and it has Save and Load.
- `ProjecturedOllama` and `ProjecturedAnthropic` load by AutoIntegration with
  the trigger `Projectured` alone.

## The subscription and a public release

### What Anthropic says

- [Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
  says: "Anthropic does not permit third-party developers to offer Claude.ai
  login into their own applications, or to route requests through Free, Pro, or
  Max plan credentials on behalf of their users. Moreover, developers may not
  collect, store, or intermediate Claude.ai credentials or session tokens —
  sign-in to a Claude account must complete through Anthropic's own flow."
- The same page says: "Nor does it prevent an end user from signing in to the
  unmodified Claude Code binary with their own Claude subscription".
- The same page says that preinstalling or running Claude Code in a product
  needs the Commercial Terms. The binary must not be modified, and each end user
  signs in with their own credentials.
- The [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)
  says: "Unless previously approved, Anthropic does not allow third party
  developers to offer claude.ai login or rate limits for their products,
  including agents built on the Claude Agent SDK."
- **Branding.** The same overview allows "Claude Agent" in a menu and "Claude"
  in a menu that is already named "Agents". It does not allow "Claude Code" as a
  name, or visuals that copy Claude Code.
- **Billing.** On 2026-06-16, Zed wrote that "ACP usage, `claude -p`, the Claude
  Agent SDK, and third-party apps built on the Agent SDK continue to work with
  Claude subscriptions exactly as they did before". Anthropic paused a plan that
  moved this use to a monthly credit at API rates, and it said that it will give
  advance notice of a revised plan.

### Rules for the design

- **R1.** Projectured never reads, stores, logs or forwards a Claude credential,
  a session token or the account data of `_auth/status_update`. It shows no
  sign-in form of its own.
- **R2.** Projectured does not bundle the adapter or Claude Code. The person
  installs the agent. Projectured starts the command that the person configured,
  unmodified.
- **R3.** The sign-in completes in the flow of the agent. That is a sign-in that
  already exists, or the `terminal` auth method in a terminal window that
  projectured opens for the person.
- **R4.** The label of the agent is its `agentInfo.title` ("Claude Agent").
  Projectured never calls the feature "Claude Code".
- **R5.** The feature is generic ACP. The documentation says "bring your own ACP
  agent", and Claude is one example.
- **R6.** The documentation says that the use of the plan counts as Anthropic
  decides, and that this can change.

### Gate G1: decided

The owner decided on 2026-10-07 not to ask Anthropic before the release. The
release follows R1 to R6. The line "offer claude.ai login" is thin, because
projectured shows the auth method of the agent. So R3 must hold: the sign-in
form is the form of the agent, in a terminal, and never a form of projectured.

## How it fits

```
projectured (ACP client)                          ACP agent (child process, Node.js)
  assistant pane, Conversation document  <-- session/update: message, thought, tool_call, plan, usage
  composer                               --> session/prompt, session/cancel
  permission card, elicitation form      <-- session/request_permission, elicitation/create
                                                 └─ Agent SDK → Claude Code binary → Claude (the plan of the person)
  ProjecturedMCP (own port, secret)      <-- tool calls: execute_julia_code, search_api, undo, ...
```

ACP carries the conversation. MCP carries the tools. Projectured has the MCP
half already.

### A third direction, not an `Llm`

An ACP agent is not an `Llm` backend. `stream_turn` answers one round, and
`run_turn!` then runs the tool calls itself. An ACP agent runs its own tools, so
an `Llm` wrapper would run them twice, or lie about them. The kernel `agent/`
gets a third direction: outbound to an agent that owns its loop.

### The history lives in the agent

With the projectured loop, the conversation is the only truth.
`build_messages` derives the prompt from it at each round. With ACP, the
session of the agent holds the history, and the transcript shows it. So:

- An edit of a past turn does not reach the agent, so past turns are read-only
  (Q3).
- A reset of the conversation starts a new session.
- A save keeps the session id, and a load resumes the session (phase 2).
- A duplicate starts a new session, and the transcript gets a note that the
  agent does not have the history (Q4).
- A local evaluation (ALT+ENTER, `EvaluateDraftTurnOperation`) puts a form and
  its result into the transcript, but the agent does not see it. The next prompt
  carries every user part that came after the last agent turn, as text or
  resource blocks.

## New mechanisms (approved 2026-10-07)

- **M1. A kernel seam for an external agent.** These are generics in `agent/`
  with no body, like `make_agent_server`, and the adapter answers them. The
  owner approved the names. They follow
  [naming-rules.md](../../documentation/rule/naming-rules.md):
  - `make_agent_connection(kind::Symbol; command, args, env)`
  - `start_agent_connection!(connection)`, which sends `initialize`
  - `open_agent_session!(connection; directory, mcp_servers) -> session_id`
  - `send_agent_prompt!(connection, session_id, blocks; on_event) -> stop_reason`
  - `cancel_agent_prompt!(connection, session_id)`
  - `set_agent_option!(connection, session_id, option_id, value)`
  - `close_agent_session!(connection, session_id)`
  - `stop_agent_connection!(connection)`

  The events are neutral, so the assistant never sees ACP:
  - `LlmTextDelta` and `LlmThinkingDelta` are used again, so the handlers that
    exist now draw the text and the thinking.
  - New types are `AgentToolCallUpdate`, `AgentPlanUpdate`, `AgentUsageUpdate`,
    `AgentCommandsUpdate`, `AgentPermissionRequest` and
    `AgentElicitationRequest`.
- **M2. A person answers a waiting request.**
  - A `session/request_permission` or an `elicitation/create` waits on the
    reader task. The transcript shows a card.
  - The click of an option evaluates an operation, for example
    `AnswerPermissionRequestOperation`. The operation puts the answer into the
    channel that the request waits on.
  - The wait has a bound: a cancel from the agent, `session/cancel`, the close
    of the assistant, or the close of the editor ends it with `cancelled`.
- **M3. A secret for the MCP server of a session.**
  - Projectured starts its MCP server on a free port, with a random token for
    each connection.
  - It gives the token in the `headers` of the `mcpServers` entry of
    `session/new`, and it sets `allowed_origins`.
  - The server refuses a request without the token. This needs a check that
    ModelContextProtocol.jl does not have now. ProjecturedMCP wraps the handler,
    or the change goes upstream.
- **M4. The list of agents.** It is a group in the settings slice, data only,
  saved in the settings file. Each entry has a name, a command, args, env and
  the `_meta` that `session/new` sends. The default entry is
  `claude-agent-acp`. Phase 2 can fill the list from the ACP Registry.

## The package

- **The package** is `ProjecturedACP` in `package/ProjecturedACP/`. The slice is
  `source/adapter/acp/`, and the module is `AcpModule`.
- **The dependencies** are JSON3 and ProjecturedKernel. The adapter translates to
  the kernel events, so it does not need ProjecturedPlatform.
- **The files:**
  - `AcpModule.jl`
  - `AcpTransport.jl`: the JSON-RPC 2.0 framing over stdio, the ids, the reader
    task, stderr to the log, and the end of the process group
  - `AcpConnection.jl`: the client methods, and the answers to the requests of
    the agent
  - `AcpUpdate.jl`: from `session/update` to the kernel events
- **The tests** are `ProjecturedACPTest`, with `test_acp()` and
  `test_acp_layering()`.
- **The load.** The person loads the package with `using ProjecturedACP`. Its
  `Project.toml` has no `[auto-integration]` section (Q6). Without the package,
  `backend = :acp` answers an error that says which package to load.

The assistant gets `backend = :acp`, and two data fields:

- `agent`: the name of an entry in the list of agents
- `session_id`: empty until the first turn

Each assistant has its own adapter process (Q2). The live connection follows the
field `llm`. It is no data: a save does not write it, and a duplicate does not
share it. The first turn starts it. The close of the tab or of the editor stops
it. The connection keeps the callback of a turn only while the turn runs, so the
document never holds the editor.

## Capabilities by phase

| Capability | Phase | Note |
|---|---|---|
| `initialize` v1 with `clientInfo` | 1 | `fs`, `terminal` and `auth.terminal` false in phase 1 |
| `session/new` with `cwd` and `mcpServers` | 1 | the MCP server of M3 |
| `session/prompt`: text and embedded resource | 1 | the user parts since the last agent turn |
| `agent_message_chunk`, `tool_call`, `tool_call_update`, `plan` | 1 | a tool part keyed by `toolCallId` |
| `agent_thought_chunk` | 1 | into `ConversationThinking`, folded; step 1.7 finds how to get it |
| `session/request_permission` | 1 | M2; without it a tool waits |
| `session/cancel` | 1 | Escape in the pane |
| `session/close` | 1 | at the close of the assistant |
| config options: `model`, `effort`, `mode` | 2 | a card made from the options that the agent lists |
| `available_commands_update` | 2 | `/` completion in the composer |
| `usage_update` | 2 | a meter of the context window |
| `session_info_update` | 2 | the title of the tab |
| `session/list`, `resume`, `delete` | 2 | save and load |
| `session/fork` | when stable | a duplicate starts a new session until then (Q4) |
| `auth.terminal`, `logout` | 2 | R3 |
| `elicitation.form` | 2 | after [a-form-edits-a-plain-value.md](a-form-edits-a-plain-value.md); turns on `AskUserQuestion` |
| `$/cancel_request` | 2 | |
| prompt queue (`_meta.steering`) | 2 | only when the agent advertises it |
| `image` in a prompt | 3 | a view as an image |
| `fs/read_text_file`, `fs/write_text_file` | 3 | no built-in tool of the adapter calls them now |
| `terminal/*` | later | Claude has its own Bash tool |
| subagent transcripts | later | a nested transcript is a tree document |
| MCP over ACP | when stable | removes the port of M3 |
| ACP v2 | when stable | side by side with v1; keep parts patchable by id |

## Steps

### Phase 1: one turn, end to end

- [x] **1.1 The transport.** Done: `AcpTransport.jl`. Decisions made in the
  step:
  - The agent starts with `detach = true`, so it has a process group of its
    own. The close ends its input first, because an agent ends at the end of its
    input. After 5 s the group gets `SIGTERM`, and after 2 s more `SIGKILL`. A
    test checks that a grandchild of the agent ends too.
  - A notification of the agent runs on the reader task, in order, so the text
    of an answer keeps its order. A request of the agent runs on a task of its
    own, so it can wait for a person.
  - The transport logs no message content, because an agent can send account
    data. The standard error of the agent goes to the debug log.
- [x] **1.2 The fake agent.** Done: `test/adapter/acp/FakeAcpAgent.jl`. The
  fake agent is not a script that replays the record of the probe. It runs in
  the test process, on two `Base.BufferStream`s, and each test gives it the
  handlers of its methods. This is faster, it can ask the client, and it holds
  no data of the account. The tests of a real process start a small child agent
  in plain Julia. `test_acp()` passes 71 of 71, with no network and no Node.js.
- [x] **1.3 The kernel seam (M1).** Done. Three fragments of `AgentModule`:
  `AgentConnectionInterface.jl`, `AgentConnectionDefaults.jl` and
  `AgentConnectionEvent.jl`. Decisions made in the step:
  - `set_agent_option!` waits for phase 2, because nothing calls it before the
    config options of step 2.1. A generic with no method is a promise.
  - The private `_get_agent_server_names` became the exported
    `get_agent_server_names`, beside the new `get_agent_connection_names`, as
    `get_llm_backend_names` is. The assistant asks with it whether `:mcp` is
    loaded. Both read the method table with `_collect_val_kinds`.
  - `send_agent_prompt!` takes a vector of `LlmContent`. Phase 1 sends
    `LlmText` only.
- [x] **1.4 The connection.** Done: `AcpConnection.jl` and `AcpUpdate.jl`.
  Decisions made in the step:
  - `initialize` offers no `fs`, no `terminal` and no `auth.terminal` in
    phase 1.
  - A chunk of another kind, of another `messageId`, or a new tool call closes
    the open text or thinking block. The end of a prompt closes the last one.
  - A tool call takes its `name` from `name`, or else from
    `_meta.claudeCode.toolName`, where `claude-agent-acp` puts it.
  - An update that phase 1 does not show is dropped: usage, commands, modes,
    config options and session information.
  - The package registers in `environment/all`, in `ProjecturedTest`, in the
    loading test, which checks that the umbrella does not load it, and in
    `PROJECTURED_PACKAGE_READMES`.
- [x] **1.5 The assistant turn.** Done: `ExternalAgentTurn.jl` in the
  assistant slice. Decisions made in the step:
  - The assistant has two new fields: `agent_command`, data that a save keeps,
    and `agent_session`, a live `ExternalAgentSession` like `llm`, which holds
    the connection, the session id and the MCP server. The session id is not
    data yet, because save and load wait for step 2.4.
  - The prompt is the text of each user turn after the last assistant turn.
    `_make_user_turn_text` is the loop body of `build_messages`, so a local
    evaluation reads the same in both kinds of turn.
  - A tool call becomes an `EvaluatorForm`, and its updates fill it. A tool of
    the server `projectured` comes back as `mcp__projectured__<name>`, and the
    turn draws it as `<name>`, so `execute_julia_code` shows its code.
  - The plan is one Markdown part with a checklist, which each update replaces.
  - The stop of a text block reads the text part again in place of the last
    part. So both sides close an open block before any other part: the adapter
    before a tool call, a plan and a permission request, and the turn before a
    new part of another kind. Text after such a part opens a new block.
  - Escape stops a turn of an external agent with
    `CancelAssistantTurnOperation`. At any other time Escape stays the
    composer's revert.
  - The duplicate of an assistant gets no session, and a note turn says that
    the agent does not have the history above it (Q4).
- [x] **1.6 The permission card (M2).** Done: `ConversationPermissionRequest`
  in the conversation slice, drawn by `_permission_card` with one
  `WidgetButton` for each option. A click runs `InvokeActionOperation` with
  `answer_permission_request!`, so no new operation type was needed. The
  buttons work while `is_permission_request_open`, and a line says the answer.
  The end of a turn answers an open request as cancelled. The duplicate of a
  request has no reply.
- [x] **1.7 The thought text.** Done. Found on 2026-10-07: `claude-agent-acp` spreads
  `_meta.claudeCode.options` of `session/new` over its own SDK options, and
  `{"thinking": {"type": "adaptive", "display": "summarized"}}` there brings
  `agent_thought_chunk` updates with a summary of the reasoning (38 chunks in a
  probe). `showThinkingSummaries` in `settings`, in the project settings, or
  with `MAX_THINKING_TOKENS` gave none. The adapter says why: recent models
  default `thinking.display` to `"omitted"`. The setting `agent_session_meta`
  carries this `_meta` as JSON, with that value as its default, and
  `make_agent_connection(:acp; session_meta)` takes it as a dictionary or as
  its JSON text. The live check of step 1.10 got 8 or 9 thinking parts in each
  turn.
- [x] **1.8 The MCP server of the session (M3).** Done in ProjecturedMCP.
  Decisions made in the step:
  - `McpServer` takes `port = 0` for a free port and `secret = true` for a
    random secret of 32 bytes. ProjecturedMCP gets HTTP, Random and Sockets as
    dependencies.
  - The library has no hook for a header check. So a server with a secret
    serves the requests itself with `HTTP.serve!`, checks
    `Authorization: Bearer <secret>` in constant time, answers `401` without
    it, and hands the request to `ModelContextProtocol.handle_request`. It also
    sets `allowed_origins`.
  - A new kernel generic, `get_agent_server_access(server) -> (name, url,
    headers)`, gives a caller the address and the header without the type of
    the server. It is not in the list of M1. It belongs to M3, because the
    assistant must give the agent the secret, and the tuple has the shape that
    `open_agent_session!` takes.
- [x] **1.9 The list of agents (M4).** Done in `StartSettings` of the
  application slice, not in a new group of the settings slice. The layering
  table of the platform does not let the assistant slice use the settings
  slices, and the application already reads the backend of the assistant from
  `StartSettings`. A setting holds only `Bool`, `Int`, `Float64`, `Symbol` or
  `String`, so phase 1 has one agent, not a list: `assistant = :acp` and
  `agent_command = "claude-agent-acp"`. A list waits for phase 2.
- [x] **1.10 A live check.** Done on 2026-10-07 with `claude-agent-acp` 0.87.0
  (Node.js 24.21.0) and the Claude sign-in of the owner, in a fresh process with
  an application editor on a `HeadlessBackend`. The script is
  `/var/tmp/acp-work/live-check.jl`, outside the repository. Results:
  - The prompt asked to change `count` from 1 to 2 in an open `data.json`. The
    agent found the tools of the MCP server with the secret, asked 8 or 9
    times for permission, which the script answered with "Yes", and called
    `search_api`, `search_guides` and `execute_julia_code`. It wrote the value
    with `replace_referenced_value!`, an operation.
  - The tab showed `{ "count": 2 }` after the turn, and `{ "count": 1 }` after
    one `undo`, as Ctrl+Z. The turn ended with `end_turn` in 60 to 80 s.
  - One frame drew the thinking parts, the permission cards with their
    buttons, and the line `Answer: Yes`. A search of the drawn tree with
    `search_documents` misses the elements of a reactive canvas, such as the
    label of a button; a walk that reads each `ReactiveCell` finds them.
  - The editor that `build_editor` makes has no `undo` tool; the application
    registers it with `register_undo_tools!` at its start, and the check does
    the same.
  - No agent process lived on after the stop.
  - A permission card showed the raw tool name `mcp__projectured__…`. The
    card now removes the prefix, as the form does.
  - A fourth run, after the fixes of the review, passed the turn, the edit, the
    thinking parts and the cards. But its undo answered "There is nothing to
    take back": this time the agent called `evaluate_operation(editor,
    ReplaceReferencedValueOperation(…))` itself, and the history did not record
    the edit. The three runs before used `replace_referenced_value!`, which the
    history records. **A finding for the owner, outside this plan:** the tool
    surface lets a model make an edit that undo can not take back. The
    assistant with its own loop and any MCP client can do the same, so the fix
    belongs to the tool surface or the undo slice, not to ACP.

### The review of phase 1 (2026-10-07)

A code review of the branch found nine faults and some names that broke the
naming law. All are fixed except one part of #3, which phase 2 keeps:

1. **A `.pred` file could start any program.** `pred_arguments` saved
   `agent_command` and `agent_session_meta`, so an opened file could name a
   program that the next message started. A `.pred` file runs no code. Both
   fields are no longer saved, and they come from `StartSettings`.
2. **A dead agent was never started again.** `start_agent_connection!` now
   starts an agent again when its transport is closed or its reader ended, and
   a task that waits for the end of the agent process closes the transport, also
   when a child of the agent keeps the output open. A failed turn stops the
   connection and forgets the session id.
3. **The agent and its MCP server outlived the assistant.** The group now gets
   `SIGTERM` at every close, also after the agent ended by itself, and a reset of
   the conversation stops the agent with `stop_external_agent!`. **Open:** the
   close of a tab does not stop its agent, because projectured has no hook for
   the close of a document. The agent ends with the editor process, at the end
   of its input, so the leak is bounded. Phase 2 needs a close hook.
4. **The prompt boundary was a guess from the roles of the turns.** The session
   now counts the turns that the agent saw, `sent_turn_count`, and the count moves
   only when `send_agent_prompt!` returns.
5. **Escape during the start of a session did nothing.** The session now has an
   `is_cancelled` flag that holds for one turn; a turn that is still starting
   sends no prompt.
6. **A card could show an answer that came after a cancel.** `reply` now answers
   `true` when it reached the agent and `false` after; the card then shows
   `"Cancelled"`.
7. **A refused request was logged as an error.** The server now reads the body
   of a refused request before its `401`.
8. **An update before its `tool_call` fixed a wrong name.** A later update with
   a name now renames the form.
9. **Two tasks changed the open block.** The request task no longer closes a
   block; the assistant does it.
10. **Names.** A function with an external effect got `!`
    (`send_acp_request!`, `send_acp_notification!` and four private ones),
    `_find_object` became `_get_object`, and `_find_free_port` became
    `_choose_free_port`, because neither answers `nothing`.

### The command line (the owner, 2026-10-07)

The owner asked on 2026-10-07, when phase 1 landed, for a way to use the agent
from the command line of the projectured UI.

- [x] **C.1 `--assistant=acp` and `--agent-command`.** Done.
  `parse_application_arguments` takes `--agent-command=COMMAND`, one argument
  that the shell quotes, and `run_application` and `make_application_settings`
  take `agent_command`. The command line wins over `StartSettings` for its run,
  as `--model` does. The program of `bin/projectured` and of a build carries
  `ProjecturedACP` beside the other model adapters, so `--assistant=acp` works
  in both. This is no AutoIntegration: a binary holds a fixed set of packages,
  and Q6 is about the umbrella in a Julia session. `PROJECTURED_OPTIONS`,
  `PROJECTURED_REQUIREMENTS`, the option table of application.md, the assistant
  guide and the README say how.
- On this machine the adapter is in the Node.js prefix of the home folder, so
  `PATH="$HOME/.local/opt/node/bin:$PATH" bin/projectured --assistant=acp`
  starts it.

### Phase 2: the agent as a full partner

- [x] **2.1 Config options: model, effort, mode.** Done. The owner approved on
  2026-10-07 the path for session events and three menus in the pane.
  Decisions made in the step:
  - **No stored `on_event`.** A handler that the connection keeps for the whole
    session would hold a closure with the editor inside the assistant, and no
    document holds the editor, not even in a closure. So `on_event` of
    `open_agent_session!` and of the new `set_agent_option!` lives only for the
    call. An update that the agent sends during a prompt reaches the `on_event`
    of the prompt; one outside a call and a prompt is dropped. The connection
    keeps the last options of each session, also outside a prompt, and answers
    a `current_mode_update` from them.
  - The kernel gets `set_agent_option!` (an approved name), `AgentOption`,
    `AgentOptionValue` and `AgentOptionsUpdate`.
  - The assistant gets `agent_options`, live and not saved, and
    `StartExternalAgentOperation`, which opens the session with no prompt, and
    `SetAgentOptionOperation`. A lock in `ExternalAgentSession` makes a turn
    and a start open one session.
  - The row is `make_agent_option_bar`: a horizontal `WidgetMenu` under the
    composer, the third child of the split pane, so the maps of the transcript
    and the composer stay as they are. Before a session it is one item, "Start
    the agent". A split pane prints a child at the height of its slot, so the
    row has a height of its own, the new `option_bar_height` of
    `ConversationTheme`.
  - **A fix outside the step:** a submenu inside a pane did not open, because
    the default reader of a projection dropped `OpenPopupOperation`, which
    names no reference. `OpenPopupOperation` is now self-contained, as
    `CloseWindowOperation` is. Every popup test passes, and a `WidgetSelect`
    in a pane can now open its list too.
  - A pick holds for the session. A new session starts with the values that
    the agent gives; a pick that lasts across sessions is not built.
  - Tests: ACP 93 of 93, the platform conversation suite 153 of 153, the
    application test 355 with 2 known broken, with a press on "Start the
    agent" and on "Effort: High" at their drawn places.
- [x] **2.2 Slash commands.** Done as a menu, with no new mechanism. The kernel
  gets `AgentCommand` and `AgentCommandsUpdate`, and the adapter translates
  `available_commands_update`, a session kind that waits between prompts. The
  row of the assistant gets a last menu, "Commands": each command is
  `/name` with its description as the tooltip, and a pick writes `/name ` into
  the draft with the `ComposerInputOperation` that the composer already has.
  The agent sends its commands after the open of the session, so they reach the
  assistant with the first prompt. A completion of `/` while the person types
  would be new interaction design, and it is not built. Tests: ACP 101 of 101,
  the platform conversation suite 173 of 173, the application test 357 with 2
  known broken.
- [x] **2.3 Usage meter and tab title.** Done. The owner decided on
  2026-10-07 that the tab shows the title from the agent. Decisions made in
  the step:
  - The kernel gets `AgentUsageUpdate` and `AgentSessionInfoUpdate`.
  - **An update between prompts waits.** The agent can name its session just
    after a prompt ends. So the connection keeps the latest update of each
    session kind — options, usage, title — and the next prompt gets them
    first, under the lock that registers it. This replaces "dropped" from step
    2.1.
  - `get_document_title` of the assistant answers `agent_title`, else
    "Assistant". The pane rules say that a tab never renames itself; this tab
    is the exception that the owner chose. The application opens the
    assistant in a tab with an empty name, so the tab asks at each draw. A tab
    that the toolbar opens takes its name at the open and keeps "Assistant";
    to follow the title there, the pane slice would need a trait for a live
    title.
  - A line beside the option menus says the usage with `format_agent_usage`,
    as "Context: 36k of 1M tokens", with the cost when the agent gives one.
  - Tests: ACP 100 of 100, the platform conversation suite 164 of 164, the
    application test 357 with 2 known broken, the history sweep 136 of 136.
- [ ] 2.4 Save, load, resume and delete. Split on 2026-10-08 into three parts.
  Facts found on 2026-10-08:
  - `ClaudeCodeACP` answers `session/resume` and `session/close`, and not
    `session/load`, `session/list` or `session/delete`. The schema 1.7.0 marks
    none of the five as unstable. A resume must give the `cwd` of the session.
  - In print mode `claude` has no documented way to list or delete a session:
    `--resume` with no id opens an interactive picker, and `claude rm` deletes
    only a background session. `--resume <id> --fork-session` forks a session.
  - Today the close of a tab forgets the session. The undo brings the
    conversation back, and the next turn opens a new session, so the agent does
    not have the history that the tab shows. A restart after a failure does the
    same.
  - [x] **2.4a Resume the same session.** The owner agreed on 2026-10-08 ("I
    agree", the answer to this question and to the fix of the style fault).
    The assistant keeps `agent_session_id` and
    `agent_session_directory`, data that a stop keeps and a reset of the
    conversation and a duplicate clear. `open_agent_session!` takes a keyword
    `session_id`: with an id, the connection resumes that session when the
    agent offers `sessionCapabilities.resume`, and else, or when the resume
    fails, it opens a new session. It answers the id of the session, so a
    different id tells the turn to add the note that the agent does not have
    the history above. This uses the function that exists, as `instructions`
    did, in place of the two new functions of the first proposal.
    Decisions made in the implementation:
    - A stop keeps the title of the session too, so the tab that an undo
      brings back keeps its name. A new session in place of the kept one
      clears it.
    - A turn that failed and stopped the connection also resumes at the next
      turn, because the stop keeps the session.
    - A session whose folder is gone does not resume: the folder of a new
      session is `pwd()`, and the note comes.
    - The note of a new session is an assistant turn after the message of the
      person. The prompt takes the user turns by their index, so the note
      does not hide that message.
    - `AcpConnection` asks for the resume only when the agent offers
      `sessionCapabilities.resume`. A refusal (a `ProtocolException`) opens a
      new session, and a needed sign-in still goes to the caller.
    - `ScriptedAgentConnection` gets `can_resume`, and each record of a session
      keeps the asked `session_id`.
    - A review of the first version found that a resume that the agent accepts
      but whose prompt fails made every later turn fail: `ClaudeCodeACP` accepts
      any resume, and Claude Code writes a session only at its first message,
      so a session opened by "Start the agent" and closed before a prompt can
      not resume. It also found that a resumed session could lose a turn that
      never reached the agent, and that an answer after a reset could bring the
      old session back. So the model is now: the assistant keeps a session only
      when the agent answered a prompt in it, with a third field,
      `agent_session_turn_count`, the count of the turns that it saw, which a
      resumed session takes as its `sent_turn_count`. When the first prompt
      after a resume fails, the assistant drops the folder of the kept session,
      so the next turn opens a new session with the note. A write after an
      answer applies only to the conversation in which the turn began, so a
      reset wins. One case stays: after a turn fails, the next prompt holds its
      message again, which a resumed agent can have seen already; a lost
      message is worse than one that comes twice.
    Live check on 2026-10-08 with the built-in agent and the real `claude`, in
    the headless editor loop: the agent remembered a word, the agent stopped as
    at the close of a tab, and the next turn resumed the same session with no
    note; the answer was the word, 3.5 s after the prompt.
    Tests: the ACP suite 124 of 124, the turn of an external agent 161 of 161
    alone, the conversation suite 219 of 219, the application 357 with the 2
    known broken; the static guards as on `main`.
    Open: `ClaudeCodeACP` makes the title of a resumed session again from the
    first prompt after the resume, so the tab takes a new name then. A fix
    there needs a release 0.1.3: a resumed session makes no title.
  - [x] **2.4b Save and load in a `.pred` file.** The owner agreed on
    2026-10-08: for an assistant with an agent session, the file keeps the
    session id, its folder and the conversation; a load shows the
    conversation, and the next turn resumes the session. It needs 2.4a.
    Found on 2026-10-08: no part of an agent turn makes the round trip through
    a `.pred` file now.
    - A text part writes, but its read fails: the writer writes the style of a
      `TextString` as `ACStyleFont(family = …)`, the name of the cell layout of
      the value document `StyleFont`, and `ACStyleFont` has no keyword
      constructor. This is a fault on `main` for every `.pred` file with styled
      text, and no test covers it. **Fixed on 2026-10-08**, first and in its own
      commit, as the owner agreed. The cause: the forward that `[DC]` gives the
      concrete spelling took every keyword, so `hasmethod` promised a keyword
      form that `StyleFont` does not have, and `make_pred_document` called it.
      The forward now takes keywords only when the schema has a keyword form,
      and the read builds the value from its fields. Only `StyleColor`,
      `StyleFont`, `StyleText` and, in inet-julia, `TagSet` and `RegionTag` are
      `[DC]` schemas, none has a default, and no code calls them with keywords.
      Tests: `test_document_macro()` 118 of 118, the new `test_pred_file()` 7
      of 7, `test_kernel()` 4218 with the 2 known broken.
    - An `EvaluatorForm` can not write its `input::Dict{String,Any}`.
    - A `ConversationPermissionRequest` can not write its
      `AgentPermissionOption` values, and its `reply` is a live value.
    - A tool result is any document, which the notation can refuse.
    - Found when the round trip ran again after the fix of the style: a part of
      Julia code, and so the form of each `execute_julia_code` card, can not
      be written. The writer refused a symbol whose name is not an identifier,
      such as the operator `:+` or `:(=)`, and the reader refused a quoted
      operator. Text, thinking, the plan, Markdown and JSON make the round
      trip. **Fixed on 2026-10-08** in its own commit, as a fault on `main`:
      the writer prints a symbol as `repr` when that text reads back as the
      same symbol, and the reader takes every quoted symbol, which is data and
      no call. `Symbol("a b")` and a dotted operator stay refused.
      `test_pred_file()` 16 of 16, `test_marker_language()` 22 of 22,
      `test_text_file()` 34 of 34.
    Done on 2026-10-08. Decisions made in the implementation:
    - The file forms of the two conversation types live in the conversation
      slice, which now depends on the serialization slice, as the widget, the
      pane and the navigator slices do. Serialization depends on no slice, so
      the edge makes no cycle.
    - `EvaluatorForm` writes its `input` as a group of `(key, value)` pairs in
      the order of the keys, an array as a vector, and a value as it is. A key
      of a tool input can be any text, so a mapping of names can not hold it,
      and the platform has no JSON library.
    - `ConversationPermissionRequest` writes its options as groups of named
      values, so the kernel type of an option needs no place among the types
      that a file may build. It writes no `reply`, and a request that waits
      reads back as `"Cancelled"`.
    - An assistant with `backend = :acp` and a kept session also writes the
      conversation, the id, the folder, the count of turns and the title of
      the session, so the tab shows its title after a load. Another assistant
      writes its settings as before.
    Tests: the turn of an external agent 176 of 176 alone, the conversation
    suite 234 of 234, the layering guards of the platform, the application 357
    with the 2 known broken; the static guards as on `main`. Live check with the
    built-in agent and every domain loaded: an answer with an
    `execute_julia_code` call and a remembered word made 21449 characters with
    two tool forms; the text was the same after the load; the loaded
    assistant resumed the same session with no note and answered "The word was
    HERON, and the result was 42."
  - **2.4c List and delete: later.** The owner agreed on 2026-10-08. The only way
    for `ClaudeCodeACP` is to read and delete the transcript files of Claude
    Code under `~/.claude/projects`, which Anthropic does not document.
    `session/load` has the same problem.
- [ ] 2.5 Terminal sign-in and logout (R3).
- [ ] 2.6 Elicitation forms.
- [ ] 2.7 Request cancel, and the prompt queue. **The request cancel is done:**
  the agent withdraws a permission request with `$/cancel_request` and its
  JSON-RPC id, the connection replies `nothing`, and the agent gets the valid
  answer `cancelled`. The transport gives the handler the id of each request.
  The prompt queue is open.
- [ ] 2.8 The ACP Registry as a source for the list of agents.
- [x] 2.9 A hook for the close of a document, so the close of a tab stops its
  agent and its MCP server (review #3). Done on 2026-10-08, as the owner
  approved: `release_document!(editor, document)` and `ReleaseDocumentOperation`
  in `DomainModule`; the close of a tab ends with the release of the document
  of the tab, whose inverse is `DoNothingOperation()`; the method for an
  `Assistant` calls `stop_external_agent!`. An undo of the close brings the
  tab back, and the next turn starts a new agent without the memory of the
  agent; a resume of the same session waits for 2.4.

- [x] 2.10 The agent knows that it runs inside the editor (the owner,
  2026-10-08). Started in the repository, the built-in agent followed the
  `CLAUDE.md` files there, and "add a table widget to the tab pane" became a
  change of code in a new worktree. `DEFAULT_AGENT_INSTRUCTIONS` now says that
  the agent runs inside the editor and that its MCP server controls that
  editor, with the guide to the tools of the native assistant. The MCP server
  of the agent gives it as its instructions, and `open_agent_session!` takes
  it as `instructions`, which `AcpConnection` puts in the `_meta` as
  `claudeCode.options.systemPrompt.append`; `ClaudeCodeACP` 0.1.2 passes it
  with `--append-system-prompt-file`. Live check in the repository: the same
  request used only the tools of the editor (11 questions, all of its MCP
  server), opened a tab "Widgets" with a `WidgetTable` of 9 example widgets,
  and changed no file and no worktree.

### Phase 3: the agent sees what projectured sees

- [ ] 3.1 A view as an image in the prompt.
- [ ] 3.2 File access through the editor, if an agent calls `fs/*`.

## The questions and their answers

The owner answered each question on 2026-10-07. The decisions are in
"Decisions" above. This list keeps the options that the owner did not choose.

- **Q1. M1 to M4 and the names.** Approved. M1 could also be in the platform
  `assistant/`, but the adapter then needs the platform. M2 could be a popup
  window, but the popup loses the context and records no answer. M3 could be a
  relay over a Unix socket, which adds a program. M4 could use environment
  variables.
- **Q2. The live connection.** One process for each assistant. One process for
  each editor saves little, because each Claude session runs its own Claude
  Code process anyway. It also needs an owner that knows ACP.
- **Q3. An edit of a past turn.** Read-only. A mark "the agent does not see
  this" was the other option. A branch from an edited turn can be a later
  feature.
- **Q4. A duplicate.** A new session with a note. `session/fork` is unstable
  now. "No duplicate" was the third option.
- **Q5. The list of agents.** The settings slice.
- **Q6. The load.** Only when the person loads it. The owner chose this over
  AutoIntegration.
- **Q7. The `omnet-ide` entry.** The servers of the person stay. With two
  editors, `omnet-ide` can reach the other editor; the owner changes the entry
  on the machine when that matters. `strictMcpConfig` was the other option. It
  also removes the other servers of the person, and it works only for Claude.
- **Q8. The release.** A release after the first one.
- **G1. Ask Anthropic.** No. The owner chose this.

## Risks

- **The adapter changes often.** It is at 0.87 with a preview channel. Pin the
  version, and test against a recorded transcript.
- **The rules and the billing can change**, with notice (R6). Read the legal
  page of Claude Code again before the release.
- **Local access.** The MCP server runs Julia code. Without M3, any program on
  this machine, or a web page through DNS rebinding, can call it.
- **Files on disk.** The agent edits files with its own tools, outside
  projectured operations. The permission card shows each edit in `default`
  mode. A document that projectured shows from a file needs a reload after an
  edit.
- **Node.js** is one more dependency for the person.
- **Memory.** Each session runs a Claude Code binary of 244 MB on disk. Measure
  the memory of one assistant before phase 2.
