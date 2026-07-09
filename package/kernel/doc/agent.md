# The agent layer

Layer 8 of the kernel — the **AI control surface** (side-stack). Independent
of the editor loop itself: the editor reaches this layer only through
`make_agent_server(:kind, editor)`, so no concrete agent-server type is named
by the editor and the real transports live in optional opt-in packages
(`ProjecturedLlm`, `ProjecturedMcp`).

The layer lives in [main/agent/](../main/agent/):

```
Agent.jl         (AgentModule)        — make_agent_server + start/stop generics
Llm.jl           (LlmModule)          — pluggable LLM backend seam (stream_turn)
  LlmApi.jl                           — abstract Llm + stream_turn generic (the seam)
  LlmAnthropic.jl                     — AnthropicLlm (real-Claude struct)
  LlmFake.jl                          — FakeLlm (in-process canned reply)
  LlmScripted.jl                      — ScriptedLlm + scripted-round builders
ToolRegistry.jl  (ToolRegistryModule) — in-process registry of Tools + Resources
Mcp.jl           (McpModule)          — MCP server skeleton + doc-introspection tools
```

`Llm.jl` is the `LlmModule` wrapper: it declares the module and its exports,
then `include`s the interface fragment (`LlmApi.jl`) and one file per concrete
backend (`LlmAnthropic.jl`, `LlmFake.jl`, `LlmScripted.jl`) that share its
namespace.

## AgentModule

The `Backend`-style seam: `make_agent_server(kind::Symbol, editor; kwargs...)`
dispatches on `Val(kind)`; concrete servers register `Val{:mcp}` etc. in
their opt-in packages. Missing methods raise a helpful error. `start_agent_server!`
and `stop_agent_server!` are the lifecycle generics the editor drives.

## Downward edges

The whole layer is dependency-free from the rest of the kernel:

- `Agent.jl`, `ToolRegistry.jl`, `Llm.jl` — no `..XxxModule` imports.
- `Mcp.jl` — imports `..ToolRegistryModule` for `Tool`, `Resource`,
  `register_tool!`, `register_resource!`, `list_tools`, `list_resources`.

That's the only intra-layer edge. The editor imports `..AgentModule` to drive
the seam; the opt-in packages (mcp/, llm/) import
`ProjecturedKernel.AgentModule` for the same generics and
`ProjecturedKernel.ToolRegistryModule` / `McpModule` for the shared pieces.
