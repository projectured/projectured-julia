# The assistant talks to an ACP agent

> **Status (2026-10-07): NOT STARTED.** Nothing is implemented. The owner
> answered the first four questions on 2026-10-07; see "Decisions". The
> mechanisms M1 to M4 and the questions Q1 to Q7 are open. Gate G1 must close
> before a public release.

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

### Gate G1 (the owner)

Before the public release, the owner decides whether to ask Anthropic (contact
sales) if a release that starts `claude-agent-acp` with the plan of the person
needs approval. R1 to R5 follow the text, but the line "offer claude.ai login"
is thin, because projectured shows the auth method of the agent.

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

- An edit of a past turn does not reach the agent. See Q3.
- A reset of the conversation starts a new session.
- A save keeps the session id, and a load resumes the session (phase 2).
- A duplicate forks the session when the agent advertises `fork`. See Q4.
- A local evaluation (ALT+ENTER, `EvaluateDraftTurnOperation`) puts a form and
  its result into the transcript, but the agent does not see it. The next prompt
  carries every user part that came after the last agent turn, as text or
  resource blocks.

## New mechanisms (the owner approves each one)

- **M1. A kernel seam for an external agent.** These are generics in `agent/`
  with no body, like `make_agent_server`, and the adapter answers them. Each
  name is a proposal, and it follows
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
    ModelContextProtocol.jl does not have now.
- **M4. The list of agents.** It is a settings document, data only. Each entry
  has a name, a command, args and env. The first entry is
  `claude-agent-acp`. Phase 2 can fill the list from the ACP Registry.

## The package

The names are proposals:

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
- **The load** follows the MCP package: AutoIntegration loads it, or the person
  loads it. See Q6.

The assistant gets `backend = :acp`, and two data fields:

- `agent`: the name of an entry in the list of agents
- `session_id`: empty until the first turn

The live connection follows the field `llm`. It is no data: a save does not
write it, and a duplicate does not share it. See Q2.

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
| `session/list`, `resume`, `delete`, `fork` | 2 | save, load and duplicate |
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

- [ ] **1.1 The transport.** JSON-RPC 2.0 over stdio, a reader task, ids,
  notifications, answers to the requests of the agent, and stderr to the log.
  The close ends the process group, because a child of the adapter must not
  live on. Test it against a fake agent.
- [ ] **1.2 The fake agent.** A Julia script that answers from a recorded
  transcript. Remove the account data from the record. The tests run with no
  network and no Node.js.
- [ ] **1.3 The kernel seam (M1)**, after the owner approves the names.
- [ ] **1.4 The connection.** `initialize`, `session/new`, `session/prompt`,
  `session/cancel` and `session/close`, on top of 1.1.
- [ ] **1.5 The assistant turn.** `backend = :acp` branches in
  `_launch_agent_turn!`. The prompt blocks come from the user parts since the
  last agent turn. Each event becomes a part, posted with
  `run_on_editor_task!(…; wait = false)`.
- [ ] **1.6 The permission card (M2).**
- [ ] **1.7 The thought text.** Find the setting, flag or option that makes the
  agent send `agent_thought_chunk`. Then map it to `ConversationThinking`.
- [ ] **1.8 The MCP server of the session (M3).**
- [ ] **1.9 The list of agents (M4)**, with one entry for this machine.
- [ ] **1.10 A live check.** Use the real adapter and the plan of the owner. One
  turn calls `execute_julia_code` through MCP, and one undo reverts it. The
  check also renders the pane, and runs in a fresh process.

### Phase 2: the agent as a full partner

- [ ] 2.1 Config options as a card: model, effort, mode.
- [ ] 2.2 Slash commands in the composer.
- [ ] 2.3 Usage meter and tab title.
- [ ] 2.4 Save, load, resume, delete and fork.
- [ ] 2.5 Terminal sign-in and logout (R3).
- [ ] 2.6 Elicitation forms.
- [ ] 2.7 Request cancel, and the prompt queue.
- [ ] 2.8 The ACP Registry as a source for the list of agents.

### Phase 3: the agent sees what projectured sees

- [ ] 3.1 A view as an image in the prompt.
- [ ] 3.2 File access through the editor, if an agent calls `fs/*`.

## Questions for the owner

- **Q1.** Do you approve M1 to M4, and the names?
- **Q2.** Where does the live connection live? My recommendation: one adapter
  process for each assistant, in a field like `llm`. The first turn starts it,
  and the close of the tab or the editor stops it.
- **Q3.** Can a person edit a past turn of an ACP assistant? My recommendation:
  no. The past turns are read-only, because the agent does not see an edit.
- **Q4.** What does a duplicate of an ACP assistant do? My recommendation: a
  `session/fork` when the agent advertises it, and else a new session with a
  note in the transcript.
- **Q5.** Where is the list of agents kept: a settings document, a `.pred` file,
  or the environment?
- **Q6.** Does `ProjecturedACP` load by AutoIntegration, like the MCP package,
  or only when the person loads it?
- **Q7.** Is the duplicate `omnet-ide` entry in `~/.claude.json` a problem?
  The agent then sees the same tools twice, when an editor also runs `--mcp` on
  port 9876.

## Risks

- **The adapter changes often.** It is at 0.87 with a preview channel. Pin the
  version, and test against a recorded transcript.
- **The rules and the billing can change**, with notice (G1, R6).
- **Local access.** The MCP server runs Julia code. Without M3, any program on
  this machine, or a web page through DNS rebinding, can call it.
- **Files on disk.** The agent edits files with its own tools, outside
  projectured operations. The permission card shows each edit in `default`
  mode. A document that projectured shows from a file needs a reload after an
  edit.
- **Node.js** is one more dependency for the person.
- **Memory.** Each session runs a Claude Code binary of 244 MB on disk. Measure
  the memory of one assistant before phase 2.
