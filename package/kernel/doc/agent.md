# The agent stack — tool, llm, agent

Three kernel layers, not one. They are separate because they are separately
useful, and the shortest way to see that is to notice what each works without:

- an **MCP server** is useful with no LLM in the process at all;
- an **LLM** is an abstraction over providers, and has nothing to do with MCP;
- an **agent** is the glue — a model, some tools, and something to act on.

They meet at one place, and it is worth naming: **the tool surface is the pivot.**
An agent loop calls a `ToolSet`; an MCP server publishes one; a provider adapter
renders one into its own schema. Three consumers, three directions, and no
knowledge of each other.

```
layer 13  tool/    the capability surface     — no LLM, no MCP
layer 14  llm/     the provider abstraction   — no MCP, no agent
layer 15  agent/   the glue                   — llm + tools + a target
```

The order is a real one: an LLM request carries the tools the model may call, so
`llm` sits on `tool`; the loop drives a model against a tool set, so `agent` sits
on both.

## Layer 13 — `tool/`: what the editor can be asked to do

```
Tool.jl           Tool (an action), Resource (a read-only datum), ToolSet
ToolSet.jl        register / list / find / call — all on a ToolSet
CodeExecution.jl  execute_julia_code, and its persistent scratch namespace
Documentation.jl  guide / module / type / function docs, and search over them
DefaultTools.jl   register_default_tools!, which puts the above into a ToolSet
```

A `Tool` is a name, a description, abstractly-described parameters, and a handler
`(target, args) -> String`. It carries **no wire format**: rendering it into
Anthropic's `input_schema` is `ProjecturedLlm`'s job, rendering it into MCP's
parameter list is `ProjecturedMcp`'s, and neither is the tool's business.

**One `ToolSet` per editor** ([AR-PER-EDITOR-STATE](../../../documentation/architecture-requirements.md#ar-per-editor-state)).
`Editor` owns one. Nothing here is process-global: not the tool list, not the
resource list, not the scratch module `execute_julia_code` evaluates into, not its
last result. Two editors in one process therefore cannot see each other's tools or
evaluate code into each other's namespace.

*The one carve-out*, stated where it lives: the guide and API indexes are
process-global lazily-built caches. They are derived read-only from source files
that do not change while the process runs, and are identical for every editor —
the same principled exception AR-PER-EDITOR-STATE grants the wall clock.

## Layer 14 — `llm/`: how the editor talks to a model

```
Llm.jl         the Llm supertype; the stream_turn and tool_schema seams
LlmMessage.jl  LlmText / LlmThinking / LlmToolUse / LlmToolResult; LlmMessage; LlmRequest
LlmEvent.jl    LlmTextDelta, LlmToolUseStart, LlmTurnEnd, … — what streams back
```

**None of this is any provider's wire format.** The messages and events are the
project's own vocabulary, and an adapter translates its protocol into them. That is
the difference between an abstraction with implementations and a hook one
implementation leaks through: a second provider writes an adapter, rather than
transcoding its stream into the first provider's event names.

Provider *configuration* belongs to the provider, not to the seam:

```julia
stream_turn(llm::Llm, request::LlmRequest; on_event)
```

`LlmRequest` carries only what varies per turn — the system prompt, the messages,
the tools the model may call, and whether to ask for extended reasoning. The API
key, model name, endpoint, and token budget live on the concrete `Llm`, because
they are its identity and not parameters of "have a conversation": a local model
has no API key, and a hosted one may want a region.

A finished tool call arrives **already parsed**, in `LlmToolUseStop`. Turning
argument JSON into a `Dict` is the adapter's job and nobody else's — every adapter
necessarily has a JSON parser, because it speaks a JSON protocol, while the kernel
has no dependencies at all and so has none.

Concrete backends live outside `main`: `AnthropicLlm` in the opt-in
`ProjecturedLlm` (`package/llm`), and the `FakeLlm` / `ScriptedLlm` doubles in
`ProjecturedKernelExample` — never in a `main` package (AR-NO-TEST-DOUBLES-IN-MAIN). The workbench
assistant finds the real one by reflection when `ProjecturedLlm` is loaded, so
nothing in the core stack names a concrete backend.

## Layer 15 — `agent/`: the two directions

```
AgentServer.jl  (AgentServerModule)  inbound  — make/start/stop_agent_server!
Agent.jl        (AgentModule)        outbound — the Agent, and AgentToolResult
AgentLoop.jl    (AgentModule)        outbound — run_turn!
```

**Inbound** is something outside the process driving *this* editor. The editor loop
reaches it only through `make_agent_server(:mcp, editor)` and never names a concrete
server type — which is exactly what lets the MCP transport live in an optional
package whose types cannot be referenced at load time.

**Outbound** is this editor driving a model:

```julia
run_turn!(agent, target; messages, on_event) -> stop_reason
```

The loop owns a turn's **control flow** and nothing else: stream a round, collect the
tool calls the model made, dispatch them through the `ToolSet`, decide from the stop
reason whether to go again, and stop at the round cap. It owns nothing about
*conversations* — how a transcript is stored, how a message is built from one, and
how an answer is rendered are all the caller's, because they are the caller's domain
and not an agent's.

`messages` is a **callback**, called at the start of every round, rather than a list
the loop mutates. The caller already has the conversation, and each round's prompt is
simply that conversation as it now stands — including the tool results the previous
round appended to it. A message list inside the agent would be a second copy of the
transcript, free to drift from the real one.

`on_event` receives every `LlmEvent` as it streams, plus an `AgentToolResult` for
each tool that runs. The workbench assistant turns those into live conversation
parts; something else might simply print them.

## Who implements what

| Seam | Declared in | Implemented by |
| --- | --- | --- |
| `make_agent_server(:mcp, …)` | `agent/AgentServer.jl` | `ProjecturedMcp` (`package/mcp`) |
| `stream_turn`, `tool_schema` | `llm/Llm.jl` | `ProjecturedLlm` (`package/llm`); `FakeLlm` / `ScriptedLlm` in `ProjecturedKernelExample` |
| a `Tool`'s handler | `tool/Tool.jl` | `register_default_tools!`, and anyone else who registers one |
