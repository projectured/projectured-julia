# ACP is a Julia package, and Claude runs without Node.js

> **Status (2026-10-08): STARTED.** The owner chose the way and the place, and
> took the recommendation of each question Q1 to Q6, on 2026-10-08; see
> "Decisions"; the name of the agent on 2026-10-08 too. Part C is done: `AgentClientProtocol.jl` 0.1.0 is on GitHub and
> in ProjecturedRegistry, and `ProjecturedACP` uses it. Part B is next. It follows
> [the-assistant-talks-to-an-acp-agent.md](the-assistant-talks-to-an-acp-agent.md),
> whose phase 1 and steps 2.1, 2.2 and 2.3 are on `main`.

## Goal

Two packages of their own, which also serve programs other than ProjecturEd:

- **C. `AgentClientProtocol.jl`**, a general Julia library for the Agent Client
  Protocol (ACP), version 1: the transport, the types of the schema, the client
  side and the agent side. It is to ACP what ModelContextProtocol.jl is to MCP.
  No Julia package for ACP exists today.
- **B. A Claude agent in Julia**, a program that speaks ACP on its standard
  input and output and drives the `claude` program through its documented
  headless interface, `claude -p`. Any ACP editor can start it: ProjecturEd,
  Zed, JetBrains, Neovim, Emacs.

With both, ProjecturEd uses Claude over ACP with no Node.js, no npm and no
JavaScript package. `ProjecturedACP` becomes a thin map from the library to
the kernel seam, and every other ACP agent keeps working through it.

The `claude` program itself stays a dependency. It is one native file with the
Bun runtime inside, which the person installs with the installer of Anthropic.
Every way to use Claude Code needs it, the ACP adapter of today too.

## Decisions

The owner decided on 2026-10-08:

1. **C first, then B.** Option A, a connection to `claude -p` inside
   ProjecturEd only, is not built, because nobody outside ProjecturEd could use
   it.
2. **The library lives in a repository of its own** and is registered in
   ProjecturedRegistry, as AutoIntegration.jl is.
3. **This plan comes first.** The owner approved it and said to start, on
   2026-10-08.
4. **The answers to Q1 to Q6 are the recommendations:** the library is
   `AgentClientProtocol.jl` (Q1); the agent has a repository of its own,
   registered in ProjecturedRegistry, with a neutral name that the owner
   chooses when B starts (Q2); it reaches other people as a Pkg app first and
   as a compiled program later (Q3); the licence is MIT (Q4); the types are
   generated from the schema (Q5); and ProjecturEd hosts the agent in its own
   process, with the program as the second way (Q6).
5. **The agent is `ClaudeCodeACP.jl`, and its command is `claude-code-acp`**
   (Q2, the owner, 2026-10-08). The name says what the agent is: it runs
   Claude Code, the `claude` program, over ACP. A name that says what a thing
   is does not say who made it, and the first line of the README says that
   Anthropic did not make it. Its repository is
   `projectured/ClaudeCodeACP.jl`, registered in ProjecturedRegistry.
6. **The cancel** (the owner, 2026-10-08, after B.1): the agent sends the
   interrupt message on standard input when `system/init` lists the
   capability `interrupt_receipt_v1`, so the process stays; else it sends
   SIGINT and starts the next prompt in a new process with `--resume`.
7. **The title** (the owner, 2026-10-08): the agent makes the title of a
   session from its first prompt, shortened, and uses no undocumented request.
8. **The configuration of the person** (the owner, 2026-10-08): a session
   loads it, as the normal `claude` does: settings, skills, commands,
   `CLAUDE.md` and the claude.ai connectors. An option of the agent passes
   `--strict-mcp-config`, so that only the MCP servers of the editor load.

## Decisions made in the implementation

- **A type is a view of a JSON object, not a struct with typed fields.** The
  schema has unions in seven forms, and some objects hold common fields and a
  union part together (`SetSessionConfigOptionRequest`, `SessionConfigOption`,
  `CreateElicitationRequest`). A struct for each form made the generator large
  and fragile. A view holds the `Dict{String,Any}` of the object, and its
  properties read the fields with their snake case names and their Julia types.
  So the round trip is exact by construction, an unknown field travels without
  a field `extra`, and a mixed form is only a list of properties. A property
  reads its field when it is used; the connection checks the required fields
  of the parameters of a message when the message comes.
- **The forms of the generator:** an object; a tagged union (an abstract type,
  a type for each tag, and `Other<Union>` for a tag that the schema does not
  name); a structural union, which the required fields pick; a flat union,
  whose alternatives only add optional fields (one type); a primitive union
  (a Julia `Union`); an enum (an alias of `String` or `Int`, its values in the
  documentation, named constants for `ErrorCode`); an alias. 207 objects, 15
  tagged unions, 2 structural, 3 flat, 3 primitive, 19 enums, 18 aliases.
- **A variant reuses the type of the definition that it references** when only
  this alternative references it as a variant, as `ToolCall` and `TextContent`
  do. Its tag is written when a field of the union holds it, because the same
  type is also a plain field (`RequestPermissionRequest.toolCall` is a
  `ToolCallUpdate` without a tag). The three variants of `ContentChunk` get
  their own types, `UserMessageChunk`, `AgentMessageChunk` and
  `AgentThoughtChunk`; another variant of its own is `<Union><Tag>`.
- **The unstable definitions are not in a module of their own.** The schema
  marks them with `**UNSTABLE**` in the description, and the generator copies
  the description into the docstring. A module of their own would split a union
  whose stable and unstable variants share one abstract type.
- **The types are public, not exported.** Many names are short and general
  (`Content`, `Diff`, `Range`, `Terminal`). The examples name them with the
  module, `import AgentClientProtocol as ACP`.
- **JSON.jl, not JSON3.** The General registry marks JSON3 as deprecated, with
  JSON.jl as the alternative. JSON.jl 1.x is the one dependency of the library.
  `ProjecturedACPTest` keeps JSON3 for its fake agent, whose wire code is an
  independent check of the library.
- **The handler API:** a `ClientHandler` or an `AgentHandler` with methods of
  `answer_request(handler, request, context)` and
  `receive_notification(handler, notification, connection)`, and the forms
  with a method name for an extension method. A method that the handler does
  not serve gets `METHOD_NOT_FOUND` before its fields are checked, so the
  library asks the method table whether a method beside the default exists.
- **`$/cancel_request` both ways:** `start_request!`, `wait_for_answer` and
  `cancel_request!` on the sending side; `add_cancel_callback!` and
  `is_request_cancelled` on the receiving side. The other side still answers a
  withdrawn request.
- **The recorded messages of `claude-agent-acp` 0.87.0** are one message of each
  kind from the probe transcripts, without the `_auth/status_update`
  notifications, which hold the account, and with only built-in commands and
  agents in the lists.
- **The library commits are on the branch `first-release`**, not on `main`,
  because the landing is the owner's decision; the repository has no `main`
  yet.
- **C.7 comes after C.8.** The registry names the git tree of the released
  commit, and C.8 changed the library once more.
- **`ProjecturedACP` keeps its translation on plain JSON.** `AcpUpdate.jl` reads
  the JSON object of each update with the defaults of its fields, so an agent
  that leaves out a field gives no error; its tests stay as they are. The
  requests that it sends are typed. The field `transport` holds the
  `AgentClientProtocol.Connection`, and `AcpClientHandler` answers the agent.
  `AcpRequestException` is gone; the package exports `ProtocolException` of the
  library.
- **A review of both branches (2026-10-08)** found three faults on the error
  paths of the library and some differences of behaviour in `ProjecturedACP`.
  The library now always answers a request, refuses a request after the end of
  its reader, keeps its reader on a bad message, delivers each answer once,
  withdraws the requests of the other side at a close, and ends
  `wait(connection)` at a close; each fault has a test. `ProjecturedACP` reads
  `initialize` with the old tolerance: a field that breaks the schema reads as
  absent. These differences stay, because they follow the protocol:
  - A request of the agent without a required field, such as a
    `session/request_permission` without `options`, gets `INVALID_PARAMS`; the
    old client asked the person.
  - A `session/update` without `update` logs a warning; the old client dropped
    it without a word.
  - The person sees "The connection closed before the answer came." where the
    old text was "The agent ended before it answered.", and other words for a
    timeout.
  - A prompt with content that is not text throws before the turn starts, so
    the waiting updates of the session stay for the next prompt.
- **The live check with the real `claude-agent-acp` passed on the branch** on
  2026-10-08: 9 tool calls, 9 permission requests answered, 9 thought parts,
  the edit through MCP, and undo took it back.
- **The order of the pushes:** `AgentClientProtocol.jl` must be on GitHub, on
  its default branch, before projectured-julia pushes this branch, because the
  CI checks it out and the release workflow adds it by its URL.
- **CI:** the jobs on `environment/all` check out `AgentClientProtocol.jl`
  beside the repository, as they do `AutoIntegration.jl`. The release workflow
  that the builder writes adds both packages by their URLs, and the front page
  of the release names the repository.

## Facts (2026-10-08)

### Why JavaScript is in the chain now

```
projectured (Julia, ACP client) ──ACP──▶ claude-agent-acp (Node.js) ──▶ Agent SDK (Node.js) ──▶ claude (native)
```

- `claude-agent-acp` 0.87.0 is 16,240 lines of compiled JavaScript in 38
  files, under Apache-2.0. A port is allowed, with attribution.
- The Agent SDK under it says "© Anthropic PBC. All rights reserved." Its code
  must not be ported. It drives `claude` through a protocol of its own, which
  is not public.
- `claude` is `/usr/bin/claude` on this machine, 240 MB, version 2.1.285, and
  the owner is signed in. The string "Bun v" is in the file.

### The schema of ACP

- The TypeScript SDK `@agentclientprotocol/sdk` 1.7.0 carries
  `schema/schema.json` (v1) and `schema/v2/schema.unstable.json`, under
  Apache-2.0.
- The v1 schema has 276 type definitions. 58 of them name an unstable part:
  providers, next-edit suggestions, MCP over ACP and others.

### The headless interface of `claude`

The documentation of
[headless mode](https://code.claude.com/docs/en/headless) and of the
[CLI](https://code.claude.com/docs/en/cli-reference) gives these, and the
Agent SDK page says: "To drive the same agent loop from a language other than
Python or TypeScript, run the CLI as a subprocess with the `-p` flag."

| Need of the agent | Documented in `claude -p` |
|---|---|
| a session of many turns | `--input-format stream-json --output-format stream-json --verbose`, `--session-id <uuid>`, `--resume <id>`, `--fork-session` |
| text and thinking as they stream | `--include-partial-messages`: `stream_event` with `text_delta` and `thinking_delta` |
| tool calls and their results | `tool_use` and `tool_result` blocks in the messages |
| the plan | the input of the `TodoWrite` tool |
| a question for the person | `--permission-prompt-tool <mcp tool>`, and `--permission-prompts host` |
| a cancel | SIGINT "ends the turn"; `system/init` names `interrupt_receipt_v1` in `capabilities` |
| model, effort, mode | `--model`, `--effort`, `--permission-mode`; `/model …` and `/effort …` as a prompt during a session |
| commands | the commands in `system/init` |
| usage | `usage` and the cost in the `result` event |
| the tools of the editor | `--mcp-config` with a server of type `http` and its headers |
| the sign-in | the sign-in of the person; `claude auth login` and `claude auth status` |

Not found in the documentation:

- the JSON that a permission tool receives and answers;
- the shape of a user message on standard input (the SDK pages give it);
- a title of the session.

### The terms of use

On the reading of 2026-10-08, B is in the same position as the ACP path of
today: it starts the unmodified `claude` that the person installed and signed
into, it shows no sign-in form of its own, and it reads no token. See the rules
R1 to R6 of the plan before this one. The headless page calls `claude -p` "the
Agent SDK via the CLI", and use through it counts as the Agent SDK does.

### The package of the precedent

AutoIntegration.jl lives in `/home/projectured/workspace/auto-integration`
(`git@github.com:projectured/AutoIntegration.jl.git`): `Project.toml`,
`src/`, `test/runtests.jl`, `README.md`, an MIT `LICENSE` and
`.github/workflows/CI.yml`. ProjecturedRegistry holds it as
`A/AutoIntegration`, and `environment/all` reaches the checkout by a path in
`[sources]`.

## Design

### C. `AgentClientProtocol.jl`

```
AgentClientProtocol.jl
├── the types       generated from schema.json v1, one Julia type for each definition
├── the transport   JSON-RPC 2.0 over two streams, one message on each line;
│                   a process in a group of its own; $/cancel_request both ways
├── the client side connect to an agent: initialize, session/*, and a handler
│                   for what the agent asks (permission, file, terminal, form)
└── the agent side  serve an editor: a handler for each request of the client,
                    and the notifications of a session
```

- **The types are generated.** A generator in the repository reads
  `schema.json` and writes the Julia types and their JSON mapping. A new
  release of the schema is a run of the generator and a review of the diff.
  The unstable definitions carry the mark of the schema in their docstrings
  (see "Decisions made in the implementation"). A NOTICE names the Apache-2.0
  source of the schema.
- **Unknown data travels.** Each type keeps `_meta`, and a field or a variant
  that the generator does not know is kept, not dropped, because the protocol
  grows by fields.
- **Both sides in one package.** A test runs a client of the library against
  an agent of the library in one process, over two streams. So the package
  tests itself, and needs no Node.js.
- **The code of `ProjecturedACP` is the start.** Its transport, its
  connection, the wait for a person, the withdrawn request, the waiting
  session updates and the end of the process group move to the library.
  `ProjecturedACP` keeps the map to the kernel seam: from the types of the
  library to `LlmTextDelta` and the `Agent…` events.

### B. The Claude agent in Julia

```
editor ──ACP──▶ the agent (Julia) ──stream-json──▶ claude -p (one process for each session)
                     │
                     └── MCP server on 127.0.0.1, with a secret: the permission tool
```

- **One `claude -p` process for each ACP session**, started with
  `--session-id`, and with `--resume` for `session/load` and
  `session/resume`.
- **The translation** turns the stream events into `session/update`: a text
  or thinking delta into a chunk, a `tool_use` into a `tool_call`, a
  `tool_result` into a `tool_call_update`, the input of `TodoWrite` into a
  `plan`, the commands of `system/init` into `available_commands_update`, and
  the `result` into `usage_update` and the stop reason.
- **A question for the person:** the agent serves its own MCP server on
  loopback with a secret, and gives `claude` its permission tool with
  `--permission-prompt-tool`. A call of the tool becomes
  `session/request_permission` to the editor, and the answer goes back as allow
  or deny.
- **The tools of the editor:** the `mcpServers` of `session/new` become the
  `--mcp-config` of `claude`, with their headers.
- **The options:** the model, the effort and the mode as config options of
  the session. A change goes to `claude` as `/model …` or `/effort …`, or as a
  new process with `--resume` and the new flags.
- **The sign-in:** a terminal auth method that runs `claude auth login`. The
  agent reads no credential.
- **ProjecturEd can host it in its own process.** The connection of
  `ProjecturedACP` already talks over two streams for a test. So ProjecturEd
  can run the agent on a task of its own, with no extra process and no start
  time of a second Julia. Any other editor starts it as a program.

## Steps

### C. The library

- [x] **C.1 The repository.** `AgentClientProtocol.jl` in
  `/home/projectured/workspace/agent-client-protocol`, shaped like
  AutoIntegration.jl: `Project.toml` with JSON3, `src/`, `test/`, a README with
  the install from ProjecturedRegistry, the licence (Q4), CI.
- [x] **C.2 The generator and the types** of schema v1 1.7.0, with the NOTICE.
  Done: commit `1d45016` of the library, 10,989 generated lines.
- [x] **C.3 The transport**, moved from `ProjecturedACP` and made general:
  requests and notifications in both directions, the end of the process group,
  `$/cancel_request` sent and received.
- [x] **C.4 The client side**, with a handler type for the requests of the
  agent.
- [x] **C.5 The agent side**, with a handler type for the requests of the
  client.
- [x] **C.6 The tests**: client against agent in one process, the cases of
  `test_acp()`, and the recorded answers of `claude-agent-acp` 0.87.0 without
  account data. Done: C.3 to C.5 in `fe95afa`, C.6 in `c06b335` and
  `e4aa4a6`; 138 tests pass in about 14 s. The README examples run against
  each other over a process.
- [x] **C.7 The release 0.1.0 in ProjecturedRegistry.** The owner pushes the
  repository and the registry. Done on 2026-10-08: the owner made the public
  repository `projectured/AgentClientProtocol.jl` and pushed `main` at
  `65060d3`, whose CI passed on Julia 1.12 and 1. The registry `main` holds
  "New package: AgentClientProtocol v0.1.0" (`7fb829a`), with the tree
  `8456021c`. The local registry checkout held an old history of 2026-10-04
  without a common commit with GitHub, so the entry was made again on the
  GitHub history.
- [x] **C.8 `ProjecturedACP` on the library.** The map to the kernel seam
  stays; the transport and the connection come from the library. `test_acp()`
  and the assistant tests pass with no change of behavior. Done on the branch
  `acp-library`: `test_acp()` 104 of 104 (101 before, one private check gone,
  four new assertions for an agent whose `initialize` breaks the schema); the
  builder suite 507 of 507 (506 on `main`); the six standalone guards give the
  same output as on `main`; the live check with the real adapter passes.

### B. The Claude agent

- [x] **B.1 A live check of the contracts that the documentation does not
  give**: the JSON of a permission tool, the shape of a user message on
  standard input, where a title comes from, the event after a SIGINT, the
  thinking text with and without a display setting, and the state of `--bare`
  for `-p`. Done on 2026-10-08 with `claude` 2.1.285; the answers are in
  "The answers of B.1" below.
- [x] **B.2 The repository** `ClaudeCodeACP.jl` (decision 5) in
  `/home/projectured/workspace/claude-code-acp`, branch `first-release`, on
  `AgentClientProtocol.jl` from ProjecturedRegistry, with HTTP and JSON. MIT.
- [x] **B.3 The session**: one `claude -p` process for each session, its
  start, its end, `--resume`. `session/new` and `session/resume`; `session/close`.
- [x] **B.4 The translation** of the stream events into `session/update`.
- [x] **B.5 The questions for the person**, through the permission tool.
- [x] **B.6 The options**, the commands, the usage and the title (decision 7).
- [x] **B.7 The cancel** by the interrupt message or SIGINT (decision 6), and
  the waiting questions withdrawn.
- [x] **B.8 The sign-in** as a terminal auth method: `claude-code-acp --login`
  runs `claude auth login`.
- [x] **B.9 The tests**: a fake `claude` in the test process that plays turns
  recorded from `claude` 2.1.285 without account data, a client of
  AgentClientProtocol through ACP, and a shell script as a process. 96 tests,
  about 12 s.
- [x] **B.10 The program**: a Pkg app (`[apps]` in `Project.toml`). The
  compiled program with the builder of ProjecturEd is not made yet.
  Done in the commits `b35bf25` to `9d570bd` of the agent. Live checks with the
  real `claude` on 2026-10-08: a prompt with a permission question and a
  second prompt that remembers the first; a cancel of a long answer, and a
  cancel while a question waits, each with a next prompt in the same process;
  and the app as a process: `initialize` after 2.6 s, a first prompt after
  7.6 s.
- [x] **The release of ClaudeCodeACP 0.1.0** (2026-10-08): the owner made the
  public repository `projectured/ClaudeCodeACP.jl` and pushed `main`. The CI
  needed ProjecturedRegistry beside General, because AgentClientProtocol is
  only there; with that step (`1f81220`) it passes on Julia 1.12 and 1. The
  registry `main` holds "New package: ClaudeCodeACP v0.1.0" (`4e0c116`), with
  the tree `33eb42c5`. On a fresh depot, `pkg> app add ClaudeCodeACP` installs
  the program, which answered a prompt with the real `claude`.
- [ ] **B.11 ProjecturEd uses it**: the default agent command, or the agent
  in the process of the editor, and a live check with the real `claude`.

## Decisions made in the implementation of B

- **The permission server is a small MCP server on HTTP.jl**, not
  ModelContextProtocol.jl. It serves one tool, `permission`, answers each POST
  with JSON, and needs no stream; a GET gets 405. The bearer secret of a
  session also names the session, and the server compares it in constant
  time. So the agent has fewer dependencies, and it controls the check.
- **A change of an option restarts `claude` at the next prompt**, with
  `--resume` and the new flag, for the mode, the model and the effort alike.
  So the agent uses only documented flags, and no `/model` message whose
  answer the stream does not document.
- **The values of the options:** the mode `default`, `acceptEdits`, `plan`,
  `auto`, `bypassPermissions`; the mode `default` that a person chooses is
  `--permission-mode manual`, and the first value comes from `permissionMode`
  of `system/init`. The models are the aliases `default`, `opus`, `sonnet`,
  `haiku`, `fable`, and the efforts `default`, `low`, `medium`, `high`,
  `xhigh`, `max`. The value `default` gives no flag.
- **The sign-in:** `session/new` and `session/resume` run `claude auth status
  --json` and read only `loggedIn`; `false` answers `AUTHENTICATION_REQUIRED`.
- **A tool call** names its tool in `name`, which schema 1.7.0 has, and in
  `_meta.claudeCode.toolName`, which `ProjecturedACP` and other clients of
  `claude-agent-acp` read. An edit and a write show a diff, and a file tool its
  location.
- **The plan comes from the task tools.** `claude` 2.1.285 has `TaskCreate`
  and `TaskUpdate`, and no `TodoWrite`. The agent keeps the tasks of a session
  from their results, and sends the whole list after each change.
- **The commands** of `system/init` are names only, so each one has an empty
  description.
- **The environment of `claude`** has no variable that ties a process to a
  session of Claude Code that runs it, such as `CLAUDECODE` and the messaging
  socket, because the agent can itself run inside Claude Code.
- **No `session/load`.** Resume works with `--resume`; a load must also replay
  the history, which needs the transcript files, and waits for a need.
- **A prompt takes text, links and embedded text**, and no image, so the agent
  says `image: false`.
- **A review of the agent (2026-10-08)** found four bugs and six risks, all
  fixed in the commit `a05b7a1` of the agent, each with a test: a close now
  cancels the prompt; a cancel or a close during the start of `claude` ends
  the prompt before `claude` gets it; the MCP configuration with the secrets is
  a private file, not a part of the command line; a failed start names only the
  error of the system; a failure of the permission tool logs nothing of the
  request; the end of a process counts also when a child keeps its output
  open; a failed turn starts `claude` again. The cost needs no change: the
  headless page says that a run with `--resume` reports the whole conversation.
  115 tests pass, and the live checks pass again.

## The answers of B.1 (2026-10-08, `claude` 2.1.285)

Each probe started `claude -p --input-format stream-json --output-format
stream-json --verbose` from a clean environment (only `HOME`, `PATH`,
`LANG`) in an empty folder, with the model `haiku`.

- **A user message on standard input** is
  `{"type": "user", "message": {"role": "user", "content": [{"type": "text",
  "text": "…"}]}}`. One process carries many turns. Each turn sends its own
  `system/init`, its events and one `result`. The end of standard input ends
  the process with code 0.
- **The session.** `--session-id <uuid>` keeps the id that the agent gives.
  `--resume <id>` brings back the whole history, also after an interrupted
  turn.
- **The sign-in.** Without `--bare`, `system/init` says `apiKeySource:
  "none"`, which is the sign-in of the person, and a `rate_limit_event` gives
  the use of the windows of the plan. `--bare` is not the default yet, but the
  headless page says again that it "will become the default for `-p` in a
  future release", and bare mode reads no OAuth sign-in. The agent reads
  `apiKeySource` and the error of a failed start at each start.
- **The permission tool** (`--permission-prompt-tool mcp__<server>__<tool>`)
  gets `{"tool_name", "input", "tool_use_id"}`, and `_meta` with
  `claudecode/toolUseId`. It answers a text block with
  `{"behavior": "allow", "updatedInput": <input>}` or
  `{"behavior": "deny", "message": "…"}`. A deny becomes a `tool_result` with
  `is_error: true` and the message as its content, and the `result` lists the
  call in `permission_denials`.
- **The thinking text.** By default a thinking block streams no text: each
  `thinking_delta` is empty, with an estimate of its tokens, and a signature.
  The documented setting `showThinkingSummaries`, given as
  `--settings '{"showThinkingSummaries": true}'`, makes the deltas carry the
  text.
- **A cancel.** SIGINT ends the turn: a user message
  "[Request interrupted by user]", then a `result` with the subtype
  `error_during_execution`, `terminal_reason: "aborted_streaming"` and
  `is_error: true`. Then the process ends with code 0 and reads no more input,
  so the next prompt needs a new process with `--resume`. The message
  `{"type": "control_request", "request_id": "…", "request": {"subtype":
  "interrupt"}}` on standard input gives a `control_response` with `success`,
  the same `result`, and the process stays for the next message. It is the wire
  form of the `interrupt()` of the Agent SDK, which the headless page names
  beside SIGINT and the capability `interrupt_receipt_v1` announces, but no
  page gives its JSON.
- **The title.** No documented event gives a generated title. `/rename
  <name>` as a prompt sets the name of a session (v2.1.205 and later).
  `claude-agent-acp` asks for a generated title with the control request
  `generate_session_title`, which no page documents.
- **The usage.** The `result` gives `usage`, `total_cost_usd` (an estimate of
  the client), and `modelUsage[<model>]` with `contextWindow` and the token
  counts, from which a `usage_update` gets `used` and `size`.
- **The configuration of the person loads.** Without `--bare`, a session reads
  the settings of the person (in the probes its output style), its skills and
  commands (67 in `slash_commands`), its `CLAUDE.md`, and the connectors of
  its claude.ai account as MCP servers. `--strict-mcp-config` keeps only the
  servers of `--mcp-config`.

## Questions for the owner

- **Q1. The name of the library.** My recommendation:
  `AgentClientProtocol.jl`, beside ModelContextProtocol.jl.
- **Q2. The name and the place of the agent.** Answered: `ClaudeCodeACP.jl`,
  a repository of its own, registered in ProjecturedRegistry (decision 5).
- **Q3. How the agent reaches a person who does not use ProjecturEd.** My
  recommendation: a Pkg app first, then a compiled program.
- **Q4. The licence.** AutoIntegration.jl is under MIT, and ProjecturEd under
  the Mozilla Public License 2.0. My recommendation: MIT, as for
  AutoIntegration.jl.
- **Q5. The types: generated, or written by hand for the part that is used.**
  My recommendation: generated, because 276 definitions are too many to keep in
  step by hand.
- **Q6. Does ProjecturEd host the agent in its own process?** My
  recommendation: yes, with the program as the second way.

## Risks

- **`--bare` will become the default for `-p`**, the documentation says, and
  bare mode does not read the subscription sign-in. If that release gives no
  flag for the normal mode, the agent loses the subscription and works only
  with an API key. The agent must check the mode at each start, from
  `system/init`.
- **The stream events follow the SDK message types**, which change with
  releases. A recorded stream for each release in the tests finds a change.
- **The contracts that B.1 checks** can differ from what the SDK pages say.
- **ACP v2** is a draft. The library starts with v1 and keeps v2 apart until
  it is stable.
- **The schema has unstable parts.** The library generates them with the
  rest, and their docstrings carry the mark of the schema.
