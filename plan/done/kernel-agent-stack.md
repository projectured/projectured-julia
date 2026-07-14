# Kernel agent stack — split `agent/` into `tool` → `llm` → `agent`

Kernel layer 12 (`agent/`) holds three independent concerns under one name, and the names
lie about all three. Split it into the three layers they actually are, fix the two
architecture violations the split exposes, and fix every dependent so the tree loads and the
tests pass. Backward compatibility is **not** a concern. Downstream *restructuring* (the
visual slices, the domain source/composite/application layers) is explicitly **out of scope**
— see [plan/tentative/from-scratch-structure.md](../tentative/from-scratch-structure.md) for
that, of which this plan is the kernel third.

## The problem

`kernel/agent/` is four files, and three of the names are wrong:

| File | Claims to be | Actually is |
| --- | --- | --- |
| `Agent.jl` | the agent | the **inbound server-hosting seam** (`make_agent_server` / `start_` / `stop_`) |
| `Mcp.jl` | the MCP server | the **editor's tool implementations** — `execute_julia_code`, guide/doc/API search. Contains no MCP; the protocol is in `package/mcp`. |
| `ToolRegistry.jl` | a generic registry | a generic registry that **knows Anthropic's wire format** (`get_anthropic_tool_schema`) |
| `Llm.jl` | a provider seam | Anthropic with a function in front of it: `stream_turn` emits **Anthropic's SSE event names** and takes `api_key`/`model` as if they were universal |

And the actual agent — the loop — is `_run_agent_loop!`, stranded in
`domain/workbench/WorkbenchAssistant.jl` (1022 lines), where it is welded to the Workbench
document and the chat widget.

Two violations fall out of reading the layer:

- **AR-PER-EDITOR-STATE (no process-global state; one process must run many editors).**
  `ToolRegistryModule._TOOLS` / `._RESOURCES` are module-level `const` vectors;
  `McpModule._SCRATCH` is one shared scratch module for `execute_julia_code` and
  `LAST_VALUE` one shared last-value. Two editors in one process today share one tool set,
  one code-eval namespace, and one last result.
- **The seam is shaped like its one implementation.** A second provider (Ollama, Bedrock,
  OpenAI) would have to transcode *into* Anthropic's SSE event names and invent an
  `api_key` it does not have.

## Target structure

Three layers at three real heights. They are a genuine total order — an LLM request carries
tools, so `llm → tool`; the loop drives an LLM against a tool set, so `agent → {llm, tool}`.
MCP appears nowhere: it is a protocol, and protocols are opt-in packages.

```
…
11 projection/
12 tool/      the capability surface.      No LLM. No MCP.
13 llm/       the provider abstraction.    No MCP. No agent.
14 agent/     the glue: an Llm + a ToolSet + a target.
15 editor/    gains `tools::ToolSet`
```

### `kernel/tool/` — layer 12

| File | Module | Holds |
| --- | --- | --- |
| `ToolLayer.jl` | — (fragment) | the layer's include list |
| `Tool.jl` | `ToolModule` | ▸ interface: `Tool`, `Resource`, `ToolSet` |
| `ToolSet.jl` | fragment | `register_tool!` / `list_tools` / `find_tool` / `call_tool` / resources — **all taking a `ToolSet`**, no globals |
| `CodeExecution.jl` | fragment | `execute_julia_code`, the scratch module, `last_evaluated_value` — **per `ToolSet`** |
| `Documentation.jl` | fragment | guides, module/type/function docs, `search_documentation`, `search_api` |
| `DefaultTools.jl` | fragment | `register_default_tools!(::ToolSet)` |

`get_anthropic_tool_schema` **leaves the kernel** — rendering a `Tool` into a provider's
JSON is the provider adapter's job (`ProjecturedLlm`), exactly as rendering it into MCP's
wire format is already `ProjecturedMcp`'s (`mcp_tools`). The kernel declares `tool_schema`
as a generic on `Llm`; the two adapters become symmetric.

`list_resources` / `read_resource` stop being special "bridging tools" the assistant
hand-builds schemas for, and become **ordinary registered tools** in `DefaultTools.jl`.
That deletes `assistant_tool_schemas` and `dispatch_assistant_tool` from the domain.

**AR-PER-EDITOR-STATE.** State that was process-global moves onto the `ToolSet` instance:

```julia
mutable struct ToolSet
    tools::Vector{Tool}
    resources::Vector{Resource}
    scratch::Union{Module,Nothing}     # execute_julia_code's persistent namespace
    last_value::Any                    # its last result, for live Document embedding
end
```

The default tools' handlers **close over their `ToolSet`** at registration, so the handler
signature stays `(target, args) -> String` and nothing needs a context argument threaded
through it. `Editor` gains `tools::ToolSet`, constructed per editor.

*Accepted carve-out:* `_GUIDE_INDEX` / `_API_INDEX` stay process-global lazily-built caches.
They are derived read-only from source files on disk, identical for every editor — the same
principled exception AR-PER-EDITOR-STATE already grants the wall clock (one writer, read-only, a genuine
singleton). Stated in the file, not silently kept.

### `kernel/llm/` — layer 13

| File | Module | Holds |
| --- | --- | --- |
| `LlmLayer.jl` | — (fragment) | include list |
| `Llm.jl` | `LlmModule` | ▸ interface: `abstract type Llm`, `stream_turn`, `tool_schema` |
| `LlmMessage.jl` | fragment | the neutral message model |
| `LlmEvent.jl` | fragment | the neutral event model |

**The neutral message model** — the domain stops building Anthropic JSON dicts:

```julia
abstract type LlmContent end
struct LlmText            <: LlmContent; text::String end
struct LlmThinking        <: LlmContent; text::String; signature::String end
struct LlmRedactedThinking<: LlmContent; data::String end
struct LlmToolUse         <: LlmContent; id::String; name::String; input::Dict{String,Any} end
struct LlmToolResult      <: LlmContent; tool_use_id::String; content::String; is_error::Bool end
struct LlmMessage; role::Symbol; content::Vector{LlmContent} end
```

**The neutral event model** — `TextStart/TextDelta/TextStop`,
`ThinkingStart/ThinkingDelta/ThinkingSignature/ThinkingStop`, `RedactedThinking`,
`ToolUseStart/ToolInputDelta/ToolUseStop`, `TurnEnd(stop_reason)`, `LlmFailure(message)`.
Each adapter maps its own stream into these; nobody downstream ever sees an SSE name again.

**The request**, with provider config where it belongs — on the provider:

```julia
struct LlmRequest
    system::String
    messages::Vector{LlmMessage}
    tools::Vector{Tool}
    thinking::Bool                    # request extended reasoning if the provider has it
end

stream_turn(llm::Llm, request::LlmRequest; on_event) -> nothing
```

`api_key`, `model`, `max_tokens`, `base_url` fold into `AnthropicLlm` (a local Ollama has no
API key; Bedrock wants a region). `_thinking_config(model)` — which is Anthropic's
`{"type":"adaptive","display":"summarized"}` — moves into `ProjecturedLlm` with it.

### `kernel/agent/` — layer 14

| File | Module | Holds |
| --- | --- | --- |
| `AgentLayer.jl` | — (fragment) | include list |
| `Agent.jl` | `AgentModule` | `Agent`: `llm`, `tools`, `system`, `model`, `max_rounds` |
| `AgentLoop.jl` | fragment | `run_turn!` — the loop |
| `AgentServer.jl` | `AgentServerModule` | ▸ interface: `make_agent_server` / `start_agent_server!` / `stop_agent_server!` (today's `Agent.jl`) |

**What the kernel loop is, and what it is not.** The loop owns the *control flow* of an agent
turn — round, stream, collect tool uses, dispatch them, decide whether to go again, cap the
rounds, report the stop reason. It does **not** own conversation serialization or rendering:
`build_messages` (a `ConversationConversation` → `Vector{LlmMessage}`) and
`parse_markdown_blocks` are domain knowledge and stay in the domain. The seam:

```julia
run_turn!(agent, target; messages, on_event) -> stop_reason
#   messages()  -> Vector{LlmMessage}   called at the start of each round, so the caller
#                                       keeps ONE source of truth (its conversation document)
#   on_event(ev::LlmEvent)              every stream event, plus a synthesized ToolResult
```

Keeping `messages` a *callback* rather than a list the loop mutates is deliberate: the
domain re-derives the prompt from the conversation each round today (*"its trailing
tool_results are exactly the continuation prompt"*), and that keeps the conversation the
single source of truth instead of a view that can drift from a parallel message list.

### What leaves the domain

`WorkbenchAssistant.jl` keeps its operations, its conversation ↔ message serialization, and
its markdown parsing. It loses:

- `_run_agent_loop!` → `kernel/agent/AgentLoop.jl` (the rounds, the cap, the tool dispatch)
- `_handle_sse_event!` → becomes a neutral `LlmEvent` sink; all Anthropic SSE knowledge goes
- `assistant_tool_schemas` / `dispatch_assistant_tool` → deleted (they were compensating for
  `list_resources`/`read_resource` not being real tools)
- `_thinking_config` → `ProjecturedLlm`
- `build_messages` returns `Vector{LlmMessage}`, not `Vector{Dict}` — the domain stops
  knowing Anthropic's wire shape at all

## Phases

One commit per phase; each phase leaves the tree loading and its tests green.

### Phase 1 — `tool/` layer, and the ToolSet ✅ done (`999a98ce`)

- [x] New `kernel/tool/` (7 files: layer fragment, module, and five fragments).
      `agent/ToolRegistry.jl` and `agent/Mcp.jl` are deleted.
- [x] `ToolSet` instance replaces `_TOOLS` / `_RESOURCES` / `_SCRATCH` / `LAST_VALUE` (AR-PER-EDITOR-STATE).
- [x] `list_resources` / `read_resource` become registered tools.
- [x] `Editor` gains `tools::ToolSet`.
- [x] Updated: `ProjecturedMcp`, `WorkbenchAssistant`, `ConversationEditor`, the package alias
      blocks, `McpTest`, `AssistantMvpTest`.
- Verified: `test_kernel` 425/425, `test_kernel_layering` 10/10, `test_mcp_tools` 118/1 broken,
  `test_mcp_resources` 22/22, `test_assistant_mvp` 62/7 broken — 0 fail, 0 error. The broken
  counts are exactly the pre-existing `@test_broken` markers.

**Decisions taken during the phase:**

- **No interface file.** The plan called `tool/Tool.jl` a contract file, but AR-INTERFACE-DECLARES-ONLY forbids an
  interface file from holding concrete structs, and `Tool`/`Resource`/`ToolSet` are concrete.
  The layer therefore declares no contract (as `binding/` already does), and the guard's
  `interface_files` map is unchanged. Same for `agent/AgentServer.jl`, whose `Val` dispatch and
  error fallback are method bodies.
- **`get_anthropic_tool_schema` parked in `LlmModule` for one phase** rather than deleted, so
  the tree stays green: the domain still drove the Anthropic-shaped `stream_turn` until Phase 2
  replaced it. Phase 2 deleted it.
- **The tests' stand-in editors now carry a `tools` field.** No test constructs a real `Editor`
  (they pass `Dict`, `nothing`, or `(document = a,)`), so `editor.tools` had to be provided:
  `(document = a, tools = register_default_tools!(ToolSet()))`. This is the honest consequence
  of AR-PER-EDITOR-STATE — a stand-in must now supply what a real editor supplies.
- **`clear_registry!` deleted, not ported.** It existed for test isolation and had zero call
  sites; a fresh `ToolSet()` is the isolation now.

### Phase 2 — `llm/` layer, and the neutral seam ✅ done (`9ea13892`)

- [x] New `kernel/llm/` (5 files): `Llm` + `stream_turn` + `tool_schema`, the `LlmMessage` /
      `LlmContent` model, the `LlmEvent` model, `LlmRequest`.
- [x] `ProjecturedLlm` rewritten: `AnthropicLlm` holds `api_key`/`model`/`base_url`/`max_tokens`;
      translates SSE → `LlmEvent`; renders `LlmMessage` → JSON and `Tool` → schema; owns the
      thinking parameter. **Every trace of Anthropic's protocol is now inside `package/llm`.**
- [x] The example doubles (`FakeLlm` / `ScriptedLlm`) emit `LlmEvent`s; the scripted builders lose
      the `message_start`/`message_stop` envelope.
- [x] `build_messages` returns `Vector{LlmMessage}`; `_handle_sse_event!` becomes
      `_handle_llm_event!`, dispatching on event types instead of poking at
      `ev.data[:delta][:partial_json]`.
- Verified: `test_kernel` 425/425, guard 10/10, `test_assistant_mvp` 62/7 broken, `test_mcp_tools`
  118/1 broken, `test_mcp_resources` 22/22 — 0 fail, 0 error. `ProjecturedLlm` loads and renders.

**Decisions taken during the phase:**

- **The backend is built per turn, not cached on the document.** With the model on the backend,
  writing the resolved `AnthropicLlm` back to `assistant.llm` (as the old code did) would freeze
  whichever model was first selected, and editing `assistant.model` would silently stop working.
  `assistant.llm` stays the *injection* point for tests/examples; production resolves per turn.
- **A known gap is held constant, not fixed.** `build_messages` replays every tool call as
  `execute_julia_code` with a `code` argument, whatever tool it actually was — so a
  `read_resource` call re-serialises with an empty code string. Fixing it needs `EvaluatorForm`
  to keep the tool's raw input, which is a behaviour change, not a move. Marked in the source.

### Phase 3 — `agent/` layer, and the loop ✅ done (`3d66cb93`)

- [x] **`LlmToolUseStop` carries the parsed call** — `LlmToolUseStop(tool_use::LlmToolUse)`
      instead of an empty marker. *Discovered while starting the phase:* the loop must turn a
      tool call's argument JSON into a `Dict` to invoke `call_tool`, and **the kernel has no JSON
      parser** (it has zero dependencies; the domain reaches for its own `jsonparse`, which the
      kernel cannot). Every provider adapter necessarily owns one — it speaks a JSON protocol —
      so the adapter assembles the `input_json` fragments and delivers a *parsed* call. The
      kernel never sees JSON, and the domain's `_json_native(jsonparse(raw))` buffering is gone.
      `LlmToolInputDelta` stays — arguments really do stream, and a UI may want to show them —
      but the loop ignores it.
- [x] `agent/AgentServer.jl` (`AgentServerModule`, the inbound seam — today's misnamed
      `Agent.jl`) + `agent/Agent.jl` and `agent/AgentLoop.jl` (`AgentModule`: the `Agent`, the
      `AgentToolResult` event, and `run_turn!`).
- [x] `run_turn!(agent, target; messages, on_event) -> stop_reason` owns the *control flow*:
      rounds, the cap, collecting tool calls, dispatching them through the `ToolSet`, and the
      stop-reason decision. It emits an `AgentToolResult` so the caller can materialise the
      result. It owns no conversation serialization and no rendering.
- [x] `_run_agent_loop!` is now a thin adapter: build the `Agent`, pass
      `messages = () -> build_messages(a.conversation)`, sink events into the conversation.
      `_PendingToolUse` is deleted — `LlmToolUse` is the thing it was standing in for.
- Verified: `test_domain()` **125963 pass / 93 fail / 1 error / 15 broken — identical to clean
  main**, which is the number that matters (the fails and the one error are the pre-existing
  baseline). `test_kernel` 425/425, guard 10/10, `test_base` 97/97, `test_visual` 51858/1 broken.

**Decisions taken during the phase:**

- **`messages` is a callback, not a list.** The loop could have owned a message list and
  appended to it. It does not: the caller already has the conversation, each round's prompt is
  that conversation as it now stands, and a second copy inside the agent could only drift from
  it. The old code re-derived the prompt each round for exactly this reason; the seam preserves
  the property instead of quietly dropping it.
- **The `Agent` holds no transcript**, for the same reason.
- **Two test files were migrated, not weakened.** `ConversationSerializationTest` asserted on
  `build_messages` output in the old Anthropic-dict shape (`msgs[1]["content"][1]["type"] ==
  "text"`); it now asserts on typed content blocks (`blocks[1] isa LlmText`), which is a
  stronger check of the same behaviour. `ConversationEditorTest`'s stand-in editor was
  `nothing`; it now carries a `ToolSet`. **These two were missed by the Phase-1 call-site sweep**
  because neither names a tool-API symbol — they were caught only by running the full
  `test_domain()` against a clean-main baseline, which is the lesson: for a change this wide,
  the targeted tests are not sufficient evidence.

### Phase 4 — docs, guard, seal list ✅ done

- [x] Guard: the kernel's `layers` list gains `tool`, `llm`, `agent`
      (`ProjecturedKernelTest.jl`). **Amended from the plan:** `interface_files` does *not*
      gain `tool/Tool.jl` / `llm/Llm.jl` / `agent/AgentServer.jl` — Phase 1 already decided
      against it (AR-INTERFACE-DECLARES-ONLY forbids an interface file holding concrete structs, and
      `Tool`/`Resource`/`ToolSet` are concrete; `agent/AgentServer.jl`'s `Val` dispatch and
      error fallback are method bodies, not a contract). Both landed in Phase 1/3, ahead of
      this phase's docs sweep.
- [x] `ProjecturedKernel.jl`'s layer diagram and `CLAUDE.md`'s seal inventory already carried
      the 15-layer / tool-llm-agent shape (landed with Phases 1/3) — verified, no change
      needed.
- [x] `package/kernel/doc/agent.md` — already rewritten (the authority this sweep worked
      from). Docs sweep (this phase): `documentation/terminology.md`, `documentation/architecture.md`,
      `package/kernel/doc/architecture.md`, `package/kernel/doc/editor.md` — every layer-count,
      layer-list, folder-table, and seam reference updated from 13/`agent` to 15/`tool`+`llm`+`agent`.
      Also found and fixed by grep (not in the original file list): `README.md` (stale
      `agent/Mcp.jl` / `agent/ToolRegistry.jl` links and "tool registry" wording in the
      AI-assisted-editing section) and `documentation/projectured-overview.md` (a slide citing
      `agent/Mcp.jl · ToolRegistry.jl`). `plan/done/*.md` and `plan/pending/kernel-cleanup.md`
      left untouched — they are historical/superseded records of prior states, not current docs.
- Verify: `test_kernel_layering()` — not run this phase (docs-only sweep, no `.jl` touched).

## Non-goals

- The visual and domain restructures (slices, the three domain layers, `gesturemap` moving to
  visual, `insertion` dissolving). Out of scope by explicit instruction.
- `HeadlessBackend`'s scripted event queue (AR-NO-TEST-DOUBLES-IN-MAIN) and `base/backend/DefaultBackend.jl`'s sink
  into the kernel — kernel changes, but orthogonal to the agent stack, and deferred.
- Any change to what the assistant *does*. Every phase is structure; the existing assistant
  tests are the oracle.

## Verification

| Phase | Narrowest sufficient test |
| --- | --- |
| 1 | `test_kernel_layering()` → `test_kernel()` → `test_domain()` → full-stack load |
| 2 | `test_domain()` + load with `ProjecturedLlm` |
| 3 | `test_domain()`, `AssistantMvpTest`, live `run_example("workbench")` |
| 4 | `test_kernel_layering()` |
