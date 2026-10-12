# The assistant talks to an ACP agent

> **Status (2026-10-08): PHASE 1 DONE and on `main` since 2026-10-07; phase 2
> partly done.** Steps 1.1 to 1.10, the command line, 2.1, 2.2, 2.3 and the
> request cancel of 2.7 are on `main`. Since the plan
> [acp-is-a-julia-package-and-claude-runs-without-node.md](../done/acp-is-a-julia-package-and-claude-runs-without-node.md),
> the built-in agent of `ProjecturedACP` runs Claude Code, and it is the
> default agent. 2.9 and 2.10 are done too, and 2.4a and 2.4b on the branch
> `assistant-resume`. Open: the list and the delete of 2.4c, which wait, 2.5,
> 2.6, the prompt queue of 2.7, 2.8 and phase 3. The owner answered every question on 2026-10-07; see "Decisions".
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
| `elicitation.form` | 2 | after [a-form-edits-a-plain-value.md](../done/a-form-edits-a-plain-value.md); turns on `AskUserQuestion` |
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
- [ ] 2.4 Save, load, resume and delete. Split on 2026-10-08 into three parts:
  2.4a and 2.4b are done, and 2.4c waits.
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
    there needs a release 0.1.3: a resumed session makes no title. The owner
    said on 2026-10-08: no release yet. On 2026-10-09 the owner said yes to the
    fix in the release 0.1.3 of step 2.13, where it is done.
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
- [x] 2.5 Terminal sign-in and logout (R3). The owner chose 2.5 and then 2.6
  on 2026-10-09, and answered the questions of the design on 2026-10-09:
  Q1 a simple terminal domain in the editor, "but don't overdo it. it's worth
  its own plan"; Q2 yes; Q3 agreed; Q4 yes; Q5 yes. So the terminal of the
  sign-in is that domain, from its own plan
  [a-terminal-runs-a-program-in-the-editor.md](../done/a-terminal-runs-a-program-in-the-editor.md),
  and 2.5d below does not apply.
  - [x] 2.5a done on the `ClaudeCodeACP` branch `sign-in`, commit `e9dd893`,
    not released: `claude-login` only for a client that sends
    `auth.terminal = true`; `auth.logout`, answered by `claude auth logout`
    (`run_claude_sign_out`, a setting `run_sign_out` for a fake); a sign-out
    marks each session for a restart, and a restart checks the sign-in (0.09 s),
    so the next prompt fails with `AUTHENTICATION_REQUIRED`. 143 tests pass.
  - [x] 2.5b done on the branch `acp-sign-in`, commit `589e6a7b3`:
    `AgentSignInException(agent_title, methods, message)`,
    `AgentSignInMethod(id, name, description, command::Cmd)`, and the generics
    `has_agent_sign_out` and `sign_out_agent!` (defaults `false`). The types
    are in `AgentConnectionEvent.jl`, not in a new file, so the inventory of
    `SEALING.md` does not change. Kernel guard 10 of 10, agent defaults 16 of 16.
  - [x] 2.5c done on the branch `acp-sign-in`, commit `83971bed7`, except the
    command of the built-in agent: the client sends `auth.terminal = true`;
    `-32000` from `session/new`, `session/resume` and `session/prompt` throws
    the exception; the command of a method is the command of the agent with its
    `args` and `env`, in its folder; `sign_out_agent!` sends `logout`.
    `test_acp()` 141 of 141, the turn of an external agent 186 of 186.
    **Found while writing it:** `bin/build_projectured` compiles the program
    with PackageCompiler (`create_app`), and a compiled program has no `julia`
    that can run other code. So Q3, the program of `ClaudeCodeACP` through the
    `julia` of this process, works from the checkout but not in the compiled
    program. The built-in agent gives no method until the owner answers Q6.
  - **Q6 (2026-10-09).** The command of the sign-in of the built-in agent.
    (a) `ClaudeCodeACP` gives the command of its own sign-in as a value, a new
    function that its `--login` uses too (`claude auth login` with the
    `claude` command and the environment of its settings); the editor runs that
    command. It works from the checkout and in the compiled program, and the
    editor does not name Claude Code. (b) The `julia` of this process, as
    agreed in Q3: no compiled program. Recommended: (a). The owner agreed to (a)
    on 2026-10-09, and to the recommendations Q1 to Q3 of the terminal plan.
  - **Q10 (2026-10-09).** Found while 2.5e was built: the transcript is read
    only by design (`ConversationToWidget.jl` declines every edit, and a plain
    press selects at most a part), so a person can not type into a terminal in
    a card. (A) an exception in the transcript for a live document in a part;
    (B) the composer sends to the sign-in program while it runs; (C) the
    terminal in a tab of its own (recommended then). The owner chose (A) on
    2026-10-11: "The AI should be able to bring up UI for asking a question
    anyway, so there will be exceptions either way". So the exception is
    general: a request part names its live field, and presses, keys and edits
    inside that field go through; the elicitation forms of 2.6 use the same.
  - [x] 2.5e done on the branch `acp-sign-in` (`34cf84b91`, `20f64db73`): a
    `ConversationSignInRequest` in place of the error, with a button for each
    method, "Try again", a state line, and the terminal of the sign-in in the
    card as the live field of the part (`_find_live_field`); the three levels
    of the transcript let an edit into a live field go on, and the cut of a
    click to its part keeps such a path. On the status 0 the assistant starts
    the agent again. A "Sign out" item in the option bar, and
    `SignOutAgentOperation`. A sign-in that a prompt of a resumed session needs
    keeps the session. **Found in the live check:** `claude auth login` ends
    with the status 0 at Ctrl+C, so a stopped sign-in looked like one that
    worked; `is_terminal_stopped` now says that a person stopped it, and the
    assistant starts no agent then. Tests: the terminal 53 of 53, the turn of
    an external agent 207 of 207, the conversation 265 of 265, the composer
    panel 76 of 76 (a press, the keys and Return in the terminal of a sign-in
    in the transcript). Live with the built-in agent and an empty
    `CLAUDE_CONFIG_DIR`, no display and `BROWSER=/bin/true`: the card came with
    "Claude Code needs a sign-in", the method ran `claude auth login`, the
    terminal showed the URL and "Paste code here if prompted >", a wrong code
    gave "Invalid code" on the standard error, and the stop gave "The sign-in
    was stopped."
  - [x] 2.5f The release: `ClaudeCodeACP` 0.1.4 (`fee4813` on its branch
    `sign-in`, with `e9dd893` and `a965bcd`), registered on the branch
    `claude-code-acp-0.1.4` of the clone of ProjecturedRegistry (`668dd5b`,
    with the tree of `fee4813`). `ProjecturedACP` needs 0.1.4 (`9aa731ec8`),
    because the editor calls `make_login_command`. The branch `acp-sign-in`,
    rebased onto `main` `5fb39c8b0` (two conflicts: the edges of the assistant
    slice, and `_make_instant_turn` of main for the new turns), passes: the
    kernel guard 10, the agent defaults 16, the platform guard 7, the terminal
    53, the turn of an external agent 207, the conversation 377, `test_acp()`
    143, the composer panel 76, `test_assistant_mvp()` 170 with its 4 known
    broken, the application 372 with its 2 known broken, the builder 529 with
    its known failure (the compat of AutoIntegration); the static guards as on
    `main`. The owner said yes on 2026-10-11: `ClaudeCodeACP` `main` and the
    registry were pushed first, then the branch landed on `main` and was
    pushed.

  **Facts (2026-10-09).**
  - ACP: an agent can advertise a `terminal` auth method with `args` and `env`.
    The client runs "the configured agent invocation" with them in an
    interactive terminal; an exit status of 0 is success. The client must not
    send that method to `authenticate`. An agent advertises it only when the
    client sends `clientCapabilities.auth.terminal = true`. `logout` is a
    request that the agent advertises with `agentCapabilities.auth.logout`.
  - `ClaudeCodeACP` 0.1.3 advertises the method `claude-login` with the
    argument `--login` always, also to a client that did not ask for it. Its
    program runs `claude auth login` for `--login`. It has no `logout`.
  - `claude auth login` opens the sign-in page of Anthropic in a browser. When
    the browser can not report back, it asks for a code in the terminal. So the
    sign-in needs an interactive terminal. `claude auth logout` needs no input.
  - The editor sends no `auth` capability. `_send_session_request!` turns
    `AUTHENTICATION_REQUIRED` into the error text "<agent> needs a sign-in.
    <description of the method>", and the assistant shows it as "Error: …" in
    the conversation. The editor has no terminal, and no code that starts an
    external program in a window or opens a URL.
  - The environment of `claude` passes through `ClaudeCodeACP`. So a test can
    use an empty `CLAUDE_CONFIG_DIR`, where `claude auth status` says "not
    signed in", and the account of the person does not change. **A test must
    never run `claude auth logout` with the real configuration: it signs out
    every Claude Code session of the person.**

  **Design (a proposal; the parts marked "new" need the word of the owner).**
  - 2.5a `ClaudeCodeACP` 0.1.4: advertise `claude-login` only when the client
    sends `auth.terminal = true`; advertise `auth.logout` and answer `logout`
    with `claude auth logout`.
  - 2.5b Kernel, agent layer (new): `AgentSignInException(agent_title, methods)`
    with one `AgentSignInMethod(id, name, description, command::Cmd)` for each
    terminal method. `open_agent_session!` throws it in place of the plain error,
    with the same message, so a caller that shows only text does not change.
    `sign_out_agent!(connection) -> Bool` sends `logout` when the agent
    advertises it, and `has_agent_sign_out(connection)` says whether it does.
  - 2.5c ACP adapter: send `auth.terminal = true`. The command of a method is
    the invocation of the agent with `args` added and `env` merged. For an
    agent with a command, that is its command. For the built-in agent, it is
    the `julia` of this process with the active project, running the program
    of `ClaudeCodeACP` (`ClaudeCodeACP.main`).
  - 2.5d (replaced by the terminal domain, Q1) Platform: a function that runs
    a `Cmd` in a terminal window of the system and gives its exit status. Linux: `$TERMINAL`, else
    `x-terminal-emulator`, `gnome-terminal`, `konsole`, `kitty`, `xterm`. macOS:
    Terminal through `osascript`. Windows: `cmd` through `start`. Some terminal
    programs return at once, so the window runs a shell that writes the exit
    status of the command into a file, and the editor waits for that file, with
    a time limit.
  - 2.5e Assistant (new): a conversation part `ConversationSignInRequest`, a
    card like the permission card. It shows "<agent> needs a sign-in", one
    button for each method, and "Try again". A method button opens the terminal;
    on exit status 0 the assistant starts the agent again by itself. "Try again"
    covers a terminal that gives no status. A "Sign out" item in the option bar
    of the agent appears when the agent advertises `logout`.
  - Tests: `ClaudeCodeACP` with the fake `claude`; the card with a scripted
    connection that throws `AgentSignInException`; the terminal function with a
    fake terminal program through `TERMINAL`. Live: the built-in agent with an
    empty `CLAUDE_CONFIG_DIR` shows the card, and the button opens a terminal
    window with `claude auth login`; the owner finishes or closes it.

  **Questions for the owner.**
  - Q1. The terminal: a terminal program of the system (recommended), or a
    terminal inside the editor (a new domain with a pseudo terminal and an
    emulator, much larger work)?
  - Q2. The new kernel names and mechanism of 2.5b: `AgentSignInException`,
    `AgentSignInMethod`, `sign_out_agent!`, `has_agent_sign_out`.
  - Q3. The invocation of the built-in agent: the program of `ClaudeCodeACP`
    through the `julia` of this process (recommended, it follows the protocol
    for every agent), or `claude auth login` directly (simpler, but the editor
    then names Claude Code)?
  - Q4. After the terminal: wait for the exit status and start again on 0, with
    "Try again" for the other cases?
  - Q5. The place of "Sign out": an item in the option bar of the agent, beside
    "Commands"?
- [x] 2.6 Elicitation forms: a question of the agent as a form in the
  conversation. The owner chose this step after 2.5 on 2026-10-09, and said on
  2026-10-11: "The AI should be able to bring up UI for asking a question
  anyway". The owner answered the questions of the design on 2026-10-11.

  **Facts (2026-10-11).**
  - Live with the built-in agent: Claude Code in print mode sends its tool
    `AskUserQuestion` through the permission tool. `ClaudeCodeACP` showed the
    card "The agent asks to run: AskUserQuestion"; after "Allow" the tool
    answered "The user did not answer the questions." The input was
    `questions`: each a `question`, a `header` (at most 12 characters),
    `options` (2 to 4, each a `label` and a `description`) and `multiSelect`;
    1 to 4 questions in a call.
  - The Agent SDK documentation (code.claude.com, "Handle approvals and user
    input"): the host answers the permission request with `behavior: "allow"`
    and `updatedInput` = the `questions` and `answers`, an object from the text
    of each question to the label of the chosen option; for several options an
    array of labels or the labels joined with ", "; a text of the person, such
    as an "Other" choice, as it is. A `deny` with a message tells Claude why.
  - ACP: `elicitation/create` with the mode `form` sends a message and a JSON
    schema (string with `enum` or `oneOf` titles, number, integer, boolean, an
    array of enum values for several choices). The client answers `accept` with
    the values, `decline` or `cancel`. The client advertises
    `clientCapabilities.elicitation.form`. Not marked unstable in schema 1.7.0.
  - The editor: the toggle group writes the chosen value into a field of a
    target document (`target`, `field`), and a `PrimitiveString` in the output
    of a view is a text field, as in the terminal. Such a write names a
    document and not a path, so the live-field rule of the transcript must
    also pass a write to a document inside a live field.

  **Design (a proposal; "new" parts need the word of the owner).**
  - 2.6a `ClaudeCodeACP`: for `AskUserQuestion`, when the editor advertises
    `elicitation.form`, send `elicitation/create` with one field for each
    question (one choice: a string with the labels as `oneOf`; several: an
    array of them) and one optional text field for each question, "Other";
    `accept` gives `allow` with `updatedInput` = `questions` and `answers`
    (the text of "Other" when it is not empty, else the label or labels);
    `decline` or `cancel` gives `deny` with "The person declined to answer.".
    An editor without the capability gets no `AskUserQuestion`
    (`--disallowedTools`), so Claude asks in its text, as `claude-agent-acp`
    does.
  - 2.6b Kernel (new): an event `AgentQuestionRequest(message, fields, reply)`,
    like `AgentPermissionRequest`, with `AgentQuestionField(name, title,
    description, kind, options, is_required)`, where `kind` is `:choice`,
    `:choices`, `:text`, `:number`, `:integer` or `:boolean`. `reply(values)`
    answers with a `Dict` of the values, or `nothing` for a decline.
  - 2.6c ACP adapter: advertise `elicitation.form`; read a form request into
    the event, and the reply into `accept`, `decline` or `cancel`. A schema
    part that it can not read becomes a text field.
  - 2.6d Conversation (new): a part `ConversationQuestionRequest` with the
    message, the fields, a form document of the values, and the reply; the
    card shows one control for each field (a toggle group for one choice,
    toggles for several, a text field, a check box), a "Send" and a "Decline"
    button, and the answer after it. The form is the live field of the part;
    the transcript rule also passes a write that names a document inside a
    live field. A cancel of the turn answers an open form with `nothing`.
  - 2.6e Later, a second step: the same card for a question of the models of
    this editor (Anthropic, Ollama), through a tool of the editor that asks the
    person.

  **2.6e design (2026-10-11, a proposal; waits for the owner).**
  - Facts: `run_turn!` runs each tool call through `run_on_editor_task!`, and a
    handler answers its text at once. A handler that waited for a person would
    hold every frame of the editor. The parameters of a tool are flat (`name`,
    `type`, `description`, `required`), and the adapters write them as an
    object of plain properties. The MCP server serves every tool of the tool
    set of the editor.
  - Kernel (new): a handler can answer a `Task` in place of its text. The loop
    then waits for the task on its own task, not on the editor task, and the
    value of the task is the text of the tool. So a tool that waits for a
    person holds no frame.
  - Assistant: the tool set of a native turn is the tool set of the editor with
    one more tool, `ask_person`, so an ACP agent, which has its own question
    tool, and an MCP client do not see it. Its parameters: `question` (a
    string, required), `options` (a string, one option a line, optional), and
    `multiple` (a boolean: the person can choose several). Its handler adds a
    `ConversationQuestionRequest` to the turn, with a choice (or a choice of
    several) of the options and an "Other" text field, or only a text field
    when there are no options, and answers a task that waits for the reply.
    The text for the model: "The person answered: …", or "The person declined
    to answer.". A stop of the turn declines an open question.
  - Questions: Q15, the new kernel mechanism (a handler answers a `Task`)?
    Q16, the name `ask_person`, and one question for each call (several
    questions in one call need array parameters, which the tool layer does not
    describe)? Recommended: yes to both.
  - The owner agreed to Q15 and Q16 on 2026-10-11.
  - [x] 2.6e done on the branch `assistant-questions`: `run_turn!` takes
    `tools`, the tools of a turn beside the tool set, and waits for a `Task`
    that a handler answers on the task of the loop (`_wait_for_tool_task`).
    **Found:** a tool set for the turn as a copy of the tool set of the
    editor does not work, because `run_turn!` registers the default tools
    again on the set that it gets, and their handlers keep the state of
    evaluation in the set that their closures capture; so the tool of the turn
    is a keyword of `run_turn!` (part of the kernel change of Q15).
    `ask_person` is made for each native turn by `_make_ask_person_tool`; a
    stop declines the open question (`_decline_open_questions!`), and
    `build_messages` skips the request parts of an assistant turn. Tests: the
    agent loop 44 of 44 (a task that the loop waits for, a task that throws),
    `test_assistant_mvp()` 183 with its 4 known broken (a question, its answer
    as the result of the tool, the card not in the messages, a stop that
    declines). No live check with a model of this editor: no Anthropic key is
    set, and a local Ollama model needs more memory than the machine has free.
    The owner pushed 2.6a to 2.6d with `ClaudeCodeACP` 0.1.5 and the registry,
    and said yes on 2026-10-12 to land and push 2.6e.

  **Questions for the owner.**
  - Q11. The scope: 2.6a to 2.6d now, and 2.6e (a tool for the models of this
    editor) as the next step? Recommended: yes.
  - Q12. The new names: `AgentQuestionRequest`, `AgentQuestionField`,
    `ConversationQuestionRequest` ("question", which a person sees, not
    "elicitation", the word of the protocol)?
  - Q13. An "Other" text field for each question, as the SDK documentation
    recommends? Recommended: yes.
  - Q14. An editor without forms: `ClaudeCodeACP` turns `AskUserQuestion` off,
    so Claude asks in its text? Recommended: yes.

  The owner asked what "forms" means in Q14 (the ACP capability
  `elicitation.form` of an editor), and then agreed to the recommendations of
  Q11 to Q14 on 2026-10-11: 2.6a to 2.6d now and 2.6e as the next step; the
  names `AgentQuestionRequest`, `AgentQuestionField` and
  `ConversationQuestionRequest`; an "Other" text field for each question; and
  no `AskUserQuestion` for an editor that can not show a form.

  **Done on the branches `acp-questions` (projectured) and `questions`
  (`ClaudeCodeACP`), 2026-10-11:**
  - [x] 2.6b `cbd4a9d75`: `AgentQuestionRequest(message, fields, reply)` and
    `AgentQuestionField(name, title, description, kind, options, is_required)`.
    The options of a choice are `AgentOptionValue`s, the type of the values of
    a session option (value, name, description), so no third type came.
  - [x] 2.6c `33f7acd75`: the client advertises `elicitation.form`; a form of
    the session of a prompt becomes the event; values accept, `nothing`
    declines, a cancel cancels. **Found:** the protocol library reads a JSON
    object into a `Dict`, which keeps no order, so the fields come in the order
    of their names; `ClaudeCodeACP` names them `question_1`,
    `question_1_other`, … so that order is the order of the questions.
    `test_acp()` 156 of 156.
  - [x] 2.6d `a26d74876`: `ConversationQuestionRequest` with a
    `ConversationQuestionForm` of one `PrimitiveString` for each value; the
    card has a toggle group for one choice and yes or no, a button for each
    option of several (`✓` before a chosen one), a text field for a text and a
    number, "Send", "Decline", and a line that says what the form still needs.
    The form is the live field of the part; the transcript also passes a write
    that names a document inside a live field, which a toggle group makes.
    **Found:** a `WidgetText` whose content is a document draws no placeholder,
    so the field shows as an empty box. Tests: the turn of an external agent
    223 of 223, the conversation 393 of 393, the composer panel 84 of 84 (a
    press on an option, a press on a choice, a number typed, Send).
  - [x] 2.6a `ClaudeCodeACP` `0f15686`: `AskUserQuestion` goes to an editor
    with forms as one `elicitation/create` form (a choice or several for each
    question, and an "Other" text field); the values come back as the
    `answers` (the text of the person, else the label, else the labels joined
    with ", "); a decline or a cancel is a deny with a message; an editor
    without forms gets `--disallowedTools=AskUserQuestion`. 155 tests pass.
    Version 0.1.5 (`12da337`), registered on the branch
    `claude-code-acp-0.1.5` of the registry clone (`1ed3f8f`).
  - Live with the built-in agent from the branch `questions` (the worktree
    environment pointed to it; the clone stayed on `main`, because a Revise
    session of the owner loads it and a struct of it changed): Claude asked
    with `AskUserQuestion`, the form came with Red, Blue and "Other", the
    script chose Blue, the tool answered `"Which colour do you prefer?"="Blue"`,
    and the answer of Claude named Blue. No permission card came for the tool.
  - [x] Landing: the owner said "land and continue" on 2026-10-11. The clone
    of `ClaudeCodeACP` moved to 0.1.5 on its `main`, the manifest of
    `environment/all` names 0.1.5, and the branch landed on `main`. Not
    pushed: `ClaudeCodeACP`, the registry branch and `main` wait for the word
    of the owner, in that order.
- [x] 2.7 Request cancel, and the prompt queue. **The request cancel is done:**
  the agent withdraws a permission request with `$/cancel_request` and its
  JSON-RPC id, the connection replies `nothing`, and the agent gets the valid
  answer `cancelled`. The transport gives the handler the id of each request.
  The prompt queue is open. The owner said on 2026-10-12 that 2.7 and 3.1 are
  important and the rest can be deferred: 2.4c, 2.8 and 3.2 wait.

  **Facts (2026-10-12).**
  - Claude Code in print mode with `--input-format stream-json` takes a user
    message that comes while a turn runs into that turn, at its next call of
    the model: a message sent during a tool call gave one `result`, whose text
    answered both messages. A message that comes after the last call of the
    model of a turn starts a new turn after the `result`: a second
    `system/init`, the message, and a second `result`. With
    `--replay-user-messages`, Claude Code echoes each user message when it
    takes it, as a `user` event with `"isReplay": true`, so an agent can count
    which messages a turn took.
  - `claude-agent-acp` and `codex-acp` have the extension method
    `_session/steering` with `{sessionId, prompt}` and the result `{outcome}`:
    `injected` (the prompt went into the running turn) or `startedNewTurn`
    (that turn had ended, and a new one began); any other outcome is a failure,
    and the client falls back. They advertise it as `_meta.steering.supported`
    in the answer to `initialize`. (Source: the pull request block/buzz#3007.)
  - `AgentClientProtocol.jl` answers an extension method
    (`answer_request(handler, method, params, context)`) and sends one
    (`start_request!(connection, method, params)`).
  - Now: Return while a turn runs does nothing, and the draft keeps its text.

  **Design (a proposal; waits for the owner).**
  - The person: Return while a turn runs sends the message. It shows at once
    as a user turn below the answer that streams, and the answer goes on in a
    new assistant turn below it, as in a chat.
  - An ACP agent that advertises `_meta.steering.supported` gets the message
    in the running turn, through `_session/steering`. Another agent, a failed
    steering, and a model of this editor get it as a queue: the message waits
    in the conversation, and the next turn starts with it when the running
    turn ends. Several waiting messages go in that one next turn. A stop does
    not start the next turn; the waiting messages go with the next Return.
  - Kernel (new): `has_agent_steering(connection) -> Bool` and
    `steer_agent_prompt!(connection, session_id, prompt) -> Bool`, `false`
    when the agent did not take the prompt.
  - `ClaudeCodeACP` 0.1.6: advertise `_meta.steering.supported`, start `claude`
    with `--replay-user-messages`, answer `_session/steering` by writing the
    message to `claude` (`injected`, or `failed` when no prompt runs), and end
    a prompt only after the `result` that follows the echo of every message
    that went into it.
  - Questions: Q17, the behaviour above (steer when the agent can, else a
    queue)? Q18, the chat order (the message below the answer, the answer
    going on below it)? Q19, the kernel names `has_agent_steering` and
    `steer_agent_prompt!`? Recommended: yes to all three. The owner agreed on
    2026-10-12.

  **Done on the branches `acp-queue` (projectured) and `steering`
  (`ClaudeCodeACP`), 2026-10-12:**
  - [x] 2.7a `7235f6f75`: `has_agent_steering` and `steer_agent_prompt!`, with
    defaults that answer `false`.
  - [x] 2.7b `e89dc016e`: the ACP connection reads `_meta.steering.supported`
    and sends `_session/steering`. **Found:** `ACP.get_json` of a content block
    has no `type`, which the library writes only in a field of the abstract
    type; the params of `_session/steering` have the shape of a
    `session/prompt`, so a `PromptRequest` writes them. `test_acp()` 165 of 165.
  - [x] 2.7d `8faf60358`: Return and the prose submit send a message while a
    turn runs; it shows at once. A steered message: the session counts it as
    seen (`steered_turn_count`), and the answer goes on in a new assistant turn
    below it (`AssistantTurnControl.is_split_asked`, `_split_steered_turn!`;
    an empty turn above goes, and the counts move down). A waiting message:
    `AssistantTurnControl.seen_turn_count` counts the turns that the running
    turn read; when the turn ends idle and not stopped, a turn of its own starts.
    A native turn reads the conversation up to itself
    (`build_messages(conversation; until = turn)`). **Found:** a message that
    comes before the turn has pushed its answer turn sits above it, and the
    turn reads it; a check of "the last turn is a user turn" alone would start
    turns without end after an empty answer, because an empty answer turn is
    removed. Alt+Return keeps its guard. Tests: the turn of an external agent
    241 of 241, the conversation 411 of 411, `test_assistant_mvp()` 186 with its
    4 known broken (two old tests now check the new behaviour), the composer
    panel 84 of 84, the application 372 with its 2 known broken.
  - [x] 2.7c `ClaudeCodeACP` `59c7b5e`: `_meta.steering.supported`,
    `--replay-user-messages`, `_session/steering`, and a prompt that ends only
    after the `result` that follows the echo of every message that went into
    it; the check for a message and the end of the prompt share one lock. 162
    tests pass. Version 0.1.6 (`dc137b3`), registered on the branch
    `claude-code-acp-0.1.6` of the registry clone (`aee6169`).
  - Live with the built-in agent from the branch `steering` (the worktree
    environment pointed to it for the check): during `sleep 6` the message
    "Also, at the very end, say the word PELICAN." went in; the conversation
    shows the turn with the shell call, the message, and a new turn "DONE
    PELICAN"; the session counts the message as seen; no extra turn started.
  - [x] Landing: the owner said "do the pushes and land it" on 2026-10-12.
    `ClaudeCodeACP` 0.1.6 and the registry were pushed, the clone moved to it,
    the manifest of `environment/all` names 0.1.6, and the branch landed and
    was pushed.
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

- [x] 2.11 A stop button for the assistant (the owner asked on 2026-10-08:
  "we also need a stop button for the assistant, no?"; after 2.4, "land it and
  continue"). Done on the branch `assistant-stop`:
  - A row under the composer holds a "Stop" button for every backend, which
    is enabled only while a turn runs; for an external agent the row also
    holds its options. A click evaluates `CancelAssistantTurnOperation`, which
    now stops a turn of a model too.
  - A turn of a model has an `AssistantTurnControl` in the new live field
    `turn_control` of the assistant. A stop sets its flag, and the callbacks
    of `_run_agent_loop!` (`on_event` and `messages`) then throw a
    `TurnCancelledException`. That ends `stream_turn`, which closes the HTTP
    connection, so the model stops; the kernel loop needs no change, because
    `on_event` of a tool result is outside the guard of the tool call. The turn
    keeps what it streamed, closes its open blocks, and ends with
    `:cancelled`. Because a backend can wrap the exception, any failure while
    the flag is set counts as the stop.
  - Found: Escape stopped a turn only in the card. The application uses the
    split pane, where Escape reached the composer and reverted the draft. The
    split pane now turns the composer's `ComposerRevertOperation` into the
    cancel while a turn runs, as it turns the composer's submit into its own.
  - Limits: a model that reads a long prompt sends no event for a while, and
    the stop waits for its first event; a tool call that runs is not stopped.
  - The button shows the Lucide stop icon and no word, with the tooltip "Stop
    the turn", so the row of an agent keeps its room. In a narrow pane the
    line of the usage still wrapped onto two lines inside the row. The owner
    chose on 2026-10-08 a shorter line: it is now "36k / 1M", with the cost
    after it when the agent gives one, and its tooltip says it in words
    ("The session uses 36k of the 1M tokens of its context."). The line fits
    on one line again; tests: the turn of an external agent 180 of 180, the
    application 357 with the 2 known broken.
  - A review of the first version found that a stop did not stop the model:
    when the code in an HTTP stream throws, HTTP.jl reads the rest of the
    answer before it closes the stream, so the turn ran to the end of the
    answer, and Anthropic billed all of it. Measured: the call ended 4 s
    after the stop. Fixes: each adapter (Ollama, Anthropic) closes the
    connection when `on_event` throws, and then the call ends 0.15 s after
    the stop. The review also found: a stop during a tool call lost the
    record of the tool, so the result of a tool now passes and the loop ends
    after it; a thinking block that a stop cut has no signature, which the
    Anthropic API refuses, so the Anthropic adapter leaves out a thinking
    block with no signature, and a message that is then empty; the catch
    now lets an exception that means stop go on; and a stop of an external
    turn before its session existed was lost, so that turn reads the control
    too. `AssistantTurnControl` is no export.
  - Tests: the turn of an external agent 178 of 178, the conversation suite
    236 of 236, `test_assistant_mvp()` 148 with its 4 known broken (two
    markers in a loop over two widths), the application 357 with the 2 known
    broken, the icons 364 of 364, `test_ollama_stream()` 35 of 35 (the live
    Ollama tests not run), `test_anthropic()` 43 with the skip of its live test;
    the static guards as on `main`. Run the MVP
    suite and the application test apart: in one process the start of the
    agent in the application test timed out.

- [x] 2.12 The result of a tool of the editor in a turn of an agent (the owner
  asked on 2026-10-08 why the ACP conversation parses no Markdown in resource
  responses, and chose item 1 of the answer). Found: the text of an answer,
  the code of `execute_julia_code` and the plan parse the same way in both
  kinds of turn, but the turn of an agent made every tool result plain text,
  while a turn of a model makes a Markdown page for a tool that declares
  `text/markdown`, which the documentation tools of the editor do. Done on the
  branch `assistant-tool-results`: the turn keeps the tool set of the editor
  in its state, and a tool of the editor, found by its name without the prefix
  `mcp__projectured__`, gets `_make_tool_result_document` as in a turn of a
  model. A tool of the agent, such as `Read` of Claude Code, and an error keep
  their text. The first later option, the live document of `execute_julia_code`
  through MCP, is done by
  [a-fork-of-model-context-protocol.md](../done/a-fork-of-model-context-protocol.md):
  a fork of ModelContextProtocol.jl gives a tool handler the `_meta` of its
  request, where Claude Code names its call. Tests: `test_assistant_mvp()` 155 with its 4 known broken, the
  turn of an external agent 180 of 180, the conversation suite 238 of 238,
  the application 359 with the 2 known broken. Live with the built-in agent:
  `list_resources`, `read_function_documentation` and `search_api` gave
  Markdown pages, and `ToolSearch` of Claude Code gave text. The two other
  later options, the media type of a resource block and `Read` of a `.md` or
  `.jl` file as a document, are step 2.13.

- [x] 2.13 The file that an agent read is a document of its format (the owner
  combined the second and the third later option of 2.12 on 2026-10-09, and
  said "yes, do it now"). The owner asked how the parse of Markdown and Julia
  can go in `ClaudeCodeACP`; the answer: it can not, because that package has
  no parsers. The work divides at the protocol:
  - [x] `ClaudeCodeACP`, branch `read-resource`, commit `8f63b24`: the result
    of `Read` is one resource block. Its `text` is the clean content of the
    file from `tool_use_result.file.content` (the text for the model has line
    numbers), its `uri` is `file://` and the path, and its `mimeType` comes
    from the extension (`find_media_type`, a table of twelve extensions; an
    unknown extension gives no media type). An image and an error keep their
    text. 130 tests pass.
  - [x] The kernel event `AgentToolCallUpdate` gets `output_mime_type` and
    `output_uri`, both `nothing` by default. The ACP adapter fills them when
    the content of the update is exactly one `resource` block
    (`_find_content_resource`); with more blocks, the output is text as before.
  - [x] The turn of an agent decides the result in this order: the live value
    that the MCP server kept for the call; then a document of the format of the
    resource, from the media type (`_find_result_format`, a table of seven
    media types in `AssistantTurn.jl`) or else from the extension of the uri,
    when `has_natural_parser` says yes; then `_make_tool_result_document` as
    before. An error and a parse that fails give text. This works for every
    ACP agent that sends a resource block, not only for `ClaudeCodeACP`.
  - [x] Tests, on the branch `agent-resource`: `test_acp()` 126 of 126 (a
    resource block gives its text, its media type and its uri; text alone gives
    neither), the turn of an external agent 186 of 186, `test_assistant_mvp()`
    170 with its 4 known broken (a Markdown file by its media type is a
    `MarkdownRoot` with its table, a Julia file by its uri alone is Julia code,
    `text/plain` stays a `TextBlock`); the static guards as on `main`. Live
    with the built-in agent from the branch `read-resource`: `Read` of a `.md`
    file gave a `MarkdownRoot` with a heading and a table, and `Read` of a
    `.jl` file gave a `JuliaAssignment`, from the text with no line numbers.
    The editor has parsers for `jl`, `json`, `md`, `rst`, `sql`, `xml` and
    `yaml`. `ClaudeCodeACP` gives no media type for `.sql` and `.rst`, so the
    extension of the uri finds them.
  - [x] A release `0.1.3` of `ClaudeCodeACP`, pushed on 2026-10-09. The owner
    said yes on 2026-10-09 to the fix of the title of a resumed session in this
    release. ClaudeCodeACP `main` = `7fd9e35`: `6c53237` makes a title only from
    the first prompt of a session (`!session.has_history`), so a resumed
    session sends no title and the editor keeps the title that it saved; then
    the version 0.1.3. 133 tests pass; the new test fails without the fix. The
    registry commit `8b9ddcf` is on the branch `claude-code-acp-0.1.3` of the
    clone of ProjecturedRegistry, with the tree of `7fd9e35`. The manifest of
    `environment/all` names 0.1.3. Live with the built-in agent: after a stop
    and a resume, the agent answered from the history of the session, and the
    title stayed the one from the first prompt. The CI of ClaudeCodeACP passed
    on Julia 1.12 and 1. An environment that has the released 0.1.2 sends the
    text of `Read` with line numbers and no resource, and the editor shows it
    as text.

### Phase 3: the agent sees what projectured sees

- [ ] 3.1 A view as an image in the prompt (important, the owner 2026-10-12).

  **Facts (2026-10-12).**
  - `write_image(canvas, filename; width, height, supersample, density)` of the
    SDL backend renders a `GraphicsCanvas` with a software renderer, with no
    window and no display, to a PNG file; `write_image(document, projection,
    filename)` prints a document first. Nothing reads the pixels of the window
    on the screen back, so a picture of what a person sees is a second render of
    the canvas that the editor drew for the window.
  - The platform has `ImageFile(filename)`, an `ImageDocument`, which a
    conversation part and a draft part can hold.
  - The kernel has no image content: `LlmContent` is text, thinking, a tool
    use and a tool result, and a tool result is a `String`. The Anthropic and
    Ollama adapters write no image; the ACP adapter converts text only.
  - ACP has `ImageContent(data, mime_type)` (base64); an agent advertises
    `promptCapabilities.image`. `ClaudeCodeACP` advertises `image = false`, and
    refuses an image block. Claude takes an image as
    `{"type": "image", "source": {"type": "base64", ...}}` in a user message.
  - The fork of ModelContextProtocol.jl answers an image in a tool result
    (`ImageContent`); the MCP server of the editor answers text only.
  - A user turn becomes one text (`_make_user_turn_text`) in three places:
    `build_messages`, the prompt of an external agent, and steering.

  **Design (a proposal; waits for the owner).**
  - 3.1a Kernel (new): `LlmImage(media_type, data)`, a kind of `LlmContent`
    with the bytes of a PNG. The Anthropic and Ollama adapters write it, and the
    ACP adapter writes it as `ImageContent` when the agent advertises
    `promptCapabilities.image`; else the image is left out, and a line in the
    prompt says so.
  - 3.1b Assistant: a user turn becomes text and images
    (`_make_user_turn_content`), in the three places above. A command
    "Picture" in the option bar of the assistant renders the window, the
    canvas that the editor drew, to a PNG and adds it to the draft as an
    `ImageFile` part, which shows as a small image; the person sends it with
    the message.
  - 3.1c `ClaudeCodeACP` 0.1.7: `promptCapabilities.image = true`, and an
    `ImageContent` becomes an image of the user message for Claude.
  - 3.1d (a question) A tool for the agent: `take_picture` of the MCP server of
    the editor answers the picture of the window as an image, so an ACP agent
    looks when it wants; Claude Code asks the person before it calls a tool of
    an MCP server that no setting allows. A model of this editor gets such a
    tool later, because the result of a tool of the kernel is text.

  **Answers (the owner, 2026-10-12).** Q20-Q23: as recommended, and "pictures
  of any smaller part should also be possible".

  **A smaller part (facts, 2026-10-12).**
  - The editor prints its document to a screen: `editor.iomap` has the screen as
    its output, and each `WindowDocument` of it holds the `GraphicsCanvas` that
    the backend draws. The SDL backend keeps no other copy that the platform
    can read, and it reads no pixels back.
  - `find_reference_box(document, reference; visible = true)` gives the box of
    any printed node, clipped by the panes that scroll; `find_part_place` maps a
    part forward and reads its box, for a tooltip and a context menu.
  - Alt+click selects any part as a whole: the selection of the window ends at
    the part. A press that a button takes does not move the focus or the
    selection, so the selection stays on the part.
  - The items of a context menu come from the type of each document, so a
    "Picture" item on every part needs a new mechanism; the selection does not.

  **The design of a picture (proposal).**
  - The command renders a window again from its canvas, with `write_image`,
    at its size and at the density 1. For a part, it maps the selection forward
    through the projection of the editor, reads the box of the part, and renders
    only that box: the canvas of the window goes into a canvas of the size of the
    box, moved by the corner of the box.
  - The "Picture" button (a camera icon) in the row under the composer takes the
    part that the person selected with Alt+click, else the window of the
    assistant. Its tooltip says so. The picture goes into the draft as an
    `ImageFile` part.
  - The tool `take_picture` of the MCP server (3.1d) takes `part`: `"window"`
    (the default) or `"selection"`.
  - A picture is a PNG file in `$XDG_CACHE_HOME/projectured/pictures`, so a saved
    conversation still names it. A picture whose file is gone shows as an empty
    box, and the prompt says that it is gone.

  **Progress.**
  - [x] 3.1a `LlmImage(media_type, data)` holds the bytes. The Anthropic adapter
    writes an image block; the Ollama adapter puts the picture in `images` when
    `/api/show` lists "vision" for the model (it asks once, only for a request
    with a picture), else a line; the ACP adapter writes `ImageContent` when
    `promptCapabilities.image` is true, else a line. The three adapter packages
    take `Base64`, a standard library, in their `[deps]`.
  - [x] 3.1c `ClaudeCodeACP` 0.1.7 on the branch `image` of its worktree
    `claude-code-acp-image`: `image = true`, and an `ImageContent` of the type
    png, jpeg, gif or webp becomes an image block of the user message; another
    type is `INVALID_PARAMS`. Not released.
  - [x] 3.1b The content of a user turn: `_make_user_turn_content` gives
    the text of the parts and each `ImageFile` part as an `LlmImage` where it
    stands, for a model, a prompt and a steer; a file that is gone or of another
    type is a line. A picture part shows as a card with the tag "picture", in the
    transcript and in the draft, at most `picture_height` (160) high: the view
    decodes the file with `decode_image`, so the part keeps only the name.
    The picture itself (after Q24 and Q25): `write_part_picture(editor, source,
    filename)` and `write_window_picture(editor, source, filename)` in the screen
    slice map `source` forward through the projection of the editor and write the
    `GraphicsCanvas` that it reaches with the backend's `write_image`, at its own
    size, moved to the origin. A part whose view has no canvas of its own, such
    as a file under the wrapper of its undo, takes the nearest part above it that
    has one. The button "Picture" (the Lucide `camera`, `0xe064`) beside the stop
    button gives `AddDraftPictureOperation`: the part when the selection is whole
    (`is_whole_selection`), else the window; the picture goes into the draft
    before the text. The files are in `$XDG_CACHE_HOME/projectured/pictures`. At
    the submit, a part with no text form (no `:string` projection) becomes a
    picture of it, written with `write_image(document, NaturalToGraphics(…))`,
    as a tab draws it, and the part becomes that `ImageFile`; a chart, which has
    no notation, has no `make_natural_projection(…, :graphics)`, so the picture
    takes `NaturalToGraphics`. A prose part (`MarkdownRoot`) and a JSON part keep
    their text.
    Found on the way: `_map_child_forward` of the widget views dropped the types
    of the rest of a reference, and a child that reads with `@reference_case`,
    such as the assistant, threw "under-typed @reference"; the rest is now typed
    again against the input of the child.
  - [x] 3.1d `register_picture_tools!(set)` adds `take_picture` (`part`:
    `"window"` or `"selection"`), which answers an `LlmImage`; the application
    registers it beside the undo tools. The MCP server answers a picture as an
    `ImageContent`, and its log says "A picture of N bytes". The loop of a turn
    gives the model of the editor a line of text in place of a picture.
  - [ ] 3.1e A paste of a document into the draft waits for Q26.

  **Checks (2026-10-12).** A script without a window, on the SDL backend, built
  the window of the application with an assistant: the window picture is the
  window at 1600 × 1000 with the new button; an Alt+click on the assistant gives
  the picture of the part of the conversation; the file of a tab, under the
  wrapper of its undo, gives the picture of the page of the tab; the button puts
  the picture into the draft before the text; a chart part becomes a picture at
  the submit. Tests: `test_part_picture` (SDL), `test_agent_loop`, the MCP tests
  of a tool, `test_conversation` and the layering guard alone, `test_assistant_mvp`
  with `test_assistant_composer_panel`, and `test_application` pass; the broken
  counts match their markers. `test_platform` passes but for the two failures of
  `test_interface_api` that main has since 8353fc722.

  **Answers (the owner, 2026-10-12).** Q24: "taking a picture of anything could
  be done by mapping it forward using the iomap and writing the part into an
  image using the backend". Q25: "yes, the selection can be shown to the agent or
  the whole screen but the user should be able to copy-paste into the draft and
  submit, so that should also be possible to turn into an image if there's no
  text representation for it (e.g. a plot)".

  **Q26 (open).** A paste into the draft does not work for a document: the caret
  of the draft is a text target, so the clipboard pastes text (the text of the
  operating system first, then the text of the copied document), and a plot has
  no text. The proposal: one new generic of the domain slice,
  `make_pasted_document_operation(document, path, value) -> Operation | nothing`,
  which the clipboard asks before the text paste when it holds a document with no
  text: each document on the path of the selection, from the deepest, can take
  the document in its own way. The draft answers an insertion of a part with the
  document before the text that the person types.

  **Questions for the owner (2026-10-12, answered).**
  - Q24. A new channel: the picture command reads the screen that the editor
    printed (`editor.iomap`), as the backend does, and no projection reads it.
    Agreed?
  - Q25. The part is the one that the person selected with Alt+click; with no
    such selection, the picture is the whole window. Agreed? The other way, a
    mode after the press of the button in which the next press picks a part,
    needs a new gesture mode.

  **Questions for the owner (answered above).**
  - Q20. Who takes the picture: the person with the command (3.1b), and also
    the agent with the tool (3.1d)? Recommended: both.
  - Q21. What the picture shows: the whole window, exactly the canvas that the
    person sees; or one tab, rendered again on its own? Recommended: the whole
    window first.
  - Q22. The kernel type `LlmImage(media_type, data)`, and `ClaudeCodeACP` 0.1.7
    with images?
  - Q23. The command "Picture" in the option bar of the assistant, which adds
    the picture to the draft?
  - The picture holds all that the window shows, files included, and goes to
    the provider of the model; only the person or a call that the person allows
    takes it.
- [ ] 3.2 File access through the editor, if an agent calls `fs/*`. Deferred by
  the owner on 2026-10-12.

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
