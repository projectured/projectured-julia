# ACP is a Julia package, and Claude runs without Node.js

> **Status (2026-10-08): STARTED.** The owner chose the way and the place, and
> took the recommendation of each question Q1 to Q6, on 2026-10-08; see
> "Decisions". It follows
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
  The unstable definitions go into a module of their own. A NOTICE names the
  Apache-2.0 source of the schema.
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

- [ ] **C.1 The repository.** `AgentClientProtocol.jl` in
  `/home/projectured/workspace/agent-client-protocol`, shaped like
  AutoIntegration.jl: `Project.toml` with JSON3, `src/`, `test/`, a README with
  the install from ProjecturedRegistry, the licence (Q4), CI.
- [ ] **C.2 The generator and the types** of schema v1 1.7.0, with the NOTICE.
- [ ] **C.3 The transport**, moved from `ProjecturedACP` and made general:
  requests and notifications in both directions, the end of the process group,
  `$/cancel_request` sent and received.
- [ ] **C.4 The client side**, with a handler type for the requests of the
  agent.
- [ ] **C.5 The agent side**, with a handler type for the requests of the
  client.
- [ ] **C.6 The tests**: client against agent in one process, the cases of
  `test_acp()`, and the recorded answers of `claude-agent-acp` 0.87.0 without
  account data.
- [ ] **C.7 The release 0.1.0 in ProjecturedRegistry.** The owner pushes the
  repository and the registry.
- [ ] **C.8 `ProjecturedACP` on the library.** The map to the kernel seam
  stays; the transport and the connection come from the library. `test_acp()`
  and the assistant tests pass with no change of behavior.

### B. The Claude agent

- [ ] **B.1 A live check of the contracts that the documentation does not
  give**: the JSON of a permission tool, the shape of a user message on
  standard input, where a title comes from, the event after a SIGINT, the
  thinking text with and without a display setting, and the state of `--bare`
  for `-p`. Record each answer here.
- [ ] **B.2 The repository** (Q2), on `AgentClientProtocol.jl`, with
  ModelContextProtocol.jl and HTTP for the permission tool.
- [ ] **B.3 The session**: one `claude -p` process for each session, its
  start, its end, `--resume`.
- [ ] **B.4 The translation** of the stream events into `session/update`.
- [ ] **B.5 The questions for the person**, through the permission tool.
- [ ] **B.6 The options**, the commands, the usage and, when B.1 finds one,
  the title.
- [ ] **B.7 The cancel** by SIGINT, and the waiting requests answered as
  cancelled.
- [ ] **B.8 The sign-in** as a terminal auth method.
- [ ] **B.9 The tests**: a fake `claude`, a script that answers from a
  recorded stream, so no test needs the network or a sign-in.
- [ ] **B.10 The program**: a Pkg app (`[apps]` in `Project.toml`, Julia 1.12
  and later), and a compiled program with the builder of ProjecturEd (Q3).
- [ ] **B.11 ProjecturEd uses it**: the default agent command, or the agent
  in the process of the editor, and a live check with the real `claude`.

## Questions for the owner

- **Q1. The name of the library.** My recommendation:
  `AgentClientProtocol.jl`, beside ModelContextProtocol.jl.
- **Q2. The name and the place of the agent.** The name must not suggest that
  Anthropic made it, and "Claude Code" must not be in it. My recommendation: a
  repository of its own, registered in ProjecturedRegistry, with a neutral
  name that you choose.
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
- **The schema has unstable parts**, which the library keeps in a module of
  their own.
