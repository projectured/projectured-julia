# A fork of ModelContextProtocol.jl

> **Status (2026-10-09): DONE.** The owner decided the base, the identity and
> the repository on 2026-10-08; see "Decisions". It is the first of the three
> later options of step 2.12 of
> [the-assistant-talks-to-an-acp-agent.md](../pending/the-assistant-talks-to-an-acp-agent.md).
> F.1 to F.7 are done; the owner deferred F.8, the pull request for upstream, on
> 2026-10-09.

## Goal

In a turn of an agent, the card of an `execute_julia_code` call shows the live
document that the code returned, as a turn of a model does. For that, the editor
must tie the value of an evaluation to the call that made it. Claude Code sends
the id of each call in the `_meta` of an MCP `tools/call`, and ClaudeCodeACP
gives the ACP tool call the same id. The MCP library of the editor drops that
`_meta`. The owner wants a fork of the library that colleagues can install.

## Decisions

The owner decided on 2026-10-08:

1. **The base is upstream 0.7.0.** `ProjecturedMCP` moves from 0.4.1 to the fork.
2. **The same name, a new UUID.** The package keeps the name
   `ModelContextProtocol`, so every `using` stays, and it gets a UUID of its
   own, so no version of ProjecturedRegistry can clash with one of General. It
   is registered in ProjecturedRegistry.
3. **The repository is `github.com/projectured/ModelContextProtocol.jl`**, a fork
   of the repository of JuliaSMLM. The owner creates and pushes it.

The owner chose this way over a guess by the code text (option B), and over a
pull request alone (option 1 of the answer), so that colleagues can share it.

## Facts (2026-10-08)

- A probe with `claude` 2.1.285 and a small MCP server: the params of
  `tools/call` are `name`, `arguments` and
  `_meta = {"claudecode/toolUseId": "toolu_…", "progressToken": 2}`.
- 0.4.1, which the editor uses: `CallToolParams` holds only `name` and
  `arguments`, and the library calls `tool.handler(args)`.
- 0.7.0, the newest upstream version: the library calls
  `tool.handler(args, ctx)` when the handler takes two arguments. `ctx` is a
  `RequestContext`, which keeps the protocol version and the client
  capabilities of a `_meta`, but not the `_meta` itself.
- The adapter uses `HttpTransport`, `MCPTool`, `ToolParameter`, `MCPResource`,
  `mcp_server`, `TextContent`, `connect`, `close`, `handle_request` and
  `ServerError`. Each exists in 0.7.0.
- Three files name the UUID: `package/ProjecturedMCP/Project.toml`,
  `package/ProjecturedIntegrations/Project.toml` (the weak dependency of the
  extension that AutoIntegration loads) and `environment/all/Project.toml`. The
  copies in `Projectured.jl` come from the release build.
- The licence is MIT, copyright klidke@unm.edu. The licence file stays.

## Steps

- [x] **F.1 The clone.** `/home/projectured/workspace/model-context-protocol`,
  from upstream `v0.7.0` (`827ae74`), with a new UUID and the version 0.7.1:
  upstream 0.7.0 and one change. The UUID is
  `318f8e74-e016-4659-bb5b-d8af92946dd5`. Its `main` holds `35ad57e` (the
  change) and `0d33aeb` (the UUID, the version, the README and the
  CHANGELOG).
- [x] **F.2 The change.** `RequestContext` gets `meta`, the `_meta` of the params
  of the request, and `request_meta(ctx)` reads it. A test, and a note in the
  README that says what the fork adds. Done as the conventions of the
  repository ask: `RequestMeta` keeps the object as `raw` where the parser
  reads `progressToken`, the three places that make a `RequestContext` pass it
  on, `RequestContext` stays unexported, and `request_meta` is exported beside
  `send_progress`. A test group "Request _meta" with 6 assertions.
- [x] **F.3 The tests of the fork** pass, as its CI runs them: `Pkg.test()` 2016 of
  2016. On the fork, the workflows of the docs deploy, TagBot and CompatHelper
  need secrets of upstream or do not fit; the owner can switch them off.
- [x] **F.4 ProjecturedMCP moves to the fork.** The UUID, the compat and a path
  source in the three files; the CI places the fork beside the repository; the
  builder gets its URL for the release workflow. `test_mcp()` and a live check
  with the built-in agent. Done on the branch `mcp-fork`:
  - The adapter needed no change of code from 0.4.1 to 0.7.1: `test_mcp()` 476
    of 476, with no warning.
  - `environment/all` takes the fork by `Pkg.develop` of its folder, because
    `Pkg.resolve` looks for an unregistered UUID in a registry. `Pkg.develop`
    sorts some entries again and writes an absolute path, so the
    `Project.toml` stays as written, and the manifest gets the relative path,
    as for AgentClientProtocol.
  - The CI places the fork beside the repository for `environment/all` and for
    the job of `ProjecturedMCPTest`, whose `ProjecturedMCP` names the folder.
  - The builder has `MODEL_CONTEXT_PROTOCOL_URL` and a row in the README of the
    release; the release workflow takes the fork from ProjecturedRegistry.
  - Found: the application environment of `bin/projectured` follows the path
    sources of the packages, so a fresh clone needs AgentClientProtocol,
    ClaudeCodeACP and now the fork beside the repository, but the setup
    guide, the guide of an own project and the README named only
    AutoIntegration. They now name all four, and the README lists the three
    repositories.
  - Tests: the application 359 with the 2 known broken; the builder 529 with
    one failure that is on `main` too: a test of the release expects the bound
    `0.1.0` for AutoIntegration, and the manifest of `main` names 0.1.1 since
    the release of AutoIntegration 0.1.1 on 2026-10-08. Live with the built-in
    agent: the documentation tools through the MCP server on the fork gave
    Markdown pages.
- [x] **F.5 The editor ties the document of an evaluation to its call.** The
  owner agreed on 2026-10-09 with the design: the tool handler of the adapter
  reads `request_meta(ctx)["claudecode/toolUseId"]`; the tool set of the kernel
  keeps the document of an evaluation under that id for a short time; the turn
  of the agent takes it when the result of the call comes. Done on the branch
  `tool-call-values`. Decisions made in the implementation:
  - No scoped value and no change of `call_tool`: the MCP handler runs the tool
    on the editor task, so right after the tool, in the same function,
    `get_last_evaluated_value` is the value of exactly that call.
  - `ToolSet` gets the field `call_values`, and the tool layer gets
    `keep_tool_call_value!` and `take_tool_call_value!`, with
    `TOOL_CALL_VALUE_CAPACITY` 32; the oldest goes first.
  - The handler takes the context as an optional second argument, so a call
    with one argument, as a test makes it, keeps nothing.
  - The turn keeps the ids that got a live result, so an update that repeats
    the output does not turn the result back into text. The card keeps the
    text of the tool in `output` beside the live result.
  - Tests: `test_code_execution()` 71 of 71, the turn of an external agent 186
    of 186, `test_mcp()` 479 of 479, `test_kernel()` 4223 with the 2 known
    broken, the conversation suite 244 of 244, `test_assistant_mvp()` 155 with
    its 4 known broken, the application 359 with the 2 known broken; the
    static guards as on `main`. Live with the built-in agent: the code
    `WidgetLabel("a live label")` through the MCP server gave the card a live
    `WidgetLabel`, and the conversation saved (20781 characters).
- [x] **F.6 A `.pred` file writes a result that its notation can not write** as
  the text of the tool, so the save of a conversation of an agent with a live
  document does not fail. The file form of `EvaluatorForm` tries
  `print_pred_text` of the result, and a `FileCutException` gives the text of
  `output`.
- [x] **F.7 The registration in ProjecturedRegistry**, in a clone, after the owner
  pushed the fork; the owner pushes the registry branch. The owner made the
  fork with the account `projectured` on 2026-10-09 (a first fork under a
  personal account was not the place) and pushed `main` (`0d33aeb`). The
  registration is done in a clone: "New package: ModelContextProtocol
  v0.7.1" (`a8cf3ee`, tree `0f74c0ed`, the tree of `0d33aeb`), on the branch
  `model-context-protocol-0.7.1` of the local registry. The owner pushed it to
  `main` of ProjecturedRegistry on 2026-10-09, and started the CI of the fork
  by hand, because its workflows were switched on only after the push.
- [ ] **F.8 Optional: the same change as a pull request** for JuliaSMLM, so the fork
  can end when upstream has it. Deferred by the owner on 2026-10-09.
