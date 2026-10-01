# Layer 19 — llm (`source/kernel/llm/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 6).

## Verdict

The kernel part of the layer is small and has no state, and its contract file holds no body. The most
important defect is on the far side of the seam: since commit a44e10c3 (2026-09-16) the Anthropic
adapter throws `UndefVarError` on the first event of each stream, so no Claude turn can finish, and no
test reads the stream parser (L19-1). The `stream_turn` contract makes promises that the two adapters
do not keep: a terminal event, stop reasons in four normal symbols, and a read that ends (L19-2). The
other findings are small: a seam function with no production caller and a false answer, a
process-global cache in the Anthropic adapter, stale file maps, and consumer names in docstrings. The
layer has no test folder of its own.

## Shape

- Purpose: the provider abstraction. It holds the `Llm` supertype and the generics a provider answers,
  the message and event vocabulary of a turn, the `make_llm` factory keyed by symbol, and the bind of a
  backend's meaning model to a `ToolSet`.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `LlmModule.jl` | 54 | ⬜ | module head: docstring, `using ..DocumentModule`, `using ..ToolModule`, one export statement, five includes |
  | `LlmInterface.jl` | 115 | ⬜ | contract: `Llm`, `stream_turn`, `render_tool_schema`, `has_meaning_model`, `get_meaning_model_name`, `compute_meaning_vectors`, `make_llm`, `default_llm_model` (bodiless) |
  | `LlmDefaults.jl` | 28 | ⬜ | the fallbacks: no meaning model, the `Symbol` → `Val` redispatch, the error for a kind that no package answers |
  | `Llm.jl` | 48 | ⬜ | `is_walk_opaque(::Llm) = true`, `bind_meaning_model!`, `get_llm_backend_names` (reads the method table of `make_llm`) |
  | `LlmMessage.jl` | 110 | ⬜ | `LlmContent` and five block types, `LlmMessage`, `LlmRequest` |
  | `LlmEvent.jl` | 156 | ⬜ | `LlmEvent` and thirteen event types |

- Imports: `DocumentModule` (for `is_walk_opaque`), `ToolModule` (`Tool`, `ToolSet`, `MeaningModel`,
  `set_meaning_model!`). Imported by: `AgentModule` (kernel), `AssistantModule`
  (`source/platform/assistant/`), `ProjecturedAnthropic`, `ProjecturedOllama`, `ProjecturedKernelExample`
  (`FakeLlm`, `ScriptedLlm`), the two adapter test packages, and omnet-julia
  (`source/campaign/CampaignWindow.jl` calls `make_llm` and `bind_meaning_model!`; `OmnetIdeTest`
  reads the events). inet-julia does not use the layer.
- Public surface: 32 exported names. All of them have a user outside the kernel. `default_llm_model`
  has no caller in production code: the two adapters define a method, and only their tests call it
  (L19-3).
- Implementers of the seam: `AnthropicLlm` (`source/adapter/anthropic/AnthropicLlm.jl`), `OllamaLlm`
  (`source/adapter/ollama/OllamaLlm.jl`), and the doubles `FakeLlm` and `ScriptedLlm` in
  `ProjecturedKernelExample`. Each real adapter answers `stream_turn`, `render_tool_schema`,
  `make_llm` and `default_llm_model`; `OllamaLlm` and `FakeLlm` also answer the three meaning-model
  generics. The seam is complete, and it is used.
- State: none in the layer. The factory registry is the method table of `make_llm`, which is the same
  for every editor.
- Tests: there is no `test/kernel/llm/`. `bind_meaning_model!` is tested in
  `test/kernel/tool/MeaningSearchTest.jl`; `make_llm`, `get_llm_backend_names` and
  `default_llm_model` in `test/adapter/anthropic/AnthropicLlmTest.jl` and `test/adapter/ollama/OllamaLlmTest.jl`; the error
  for a kind that no package answers in the umbrella (`test/projectured/editor/AssistantMvpTest.jl:223`).
  The Anthropic stream parser has no test (L19-1).

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 1 | 0 |
| Shape | 0 | 0 | 2 |
| State | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 2 |
| Tests | 0 | 0 | 1 |

## Findings

### L19-1 The Anthropic adapter throws on the first event of every stream

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `input_tokens` at `Anthropic.jl:389` is a local of `stream_turn` (line 276), not a parameter of `_drain_sse_events!` (line 364).
- Where: [Anthropic.jl:389](../../../source/adapter/anthropic/AnthropicLlm.jl#L389) (outside the kernel; the
  only Claude implementer of `stream_turn`)
- Evidence: `_drain_sse_events!(buf::IOBuffer, emit::Function; final::Bool = false)` (line 364) calls
  `_translate_sse!(emit, type, parsed; input_tokens = input_tokens)` (line 389). `input_tokens` is a
  local of `stream_turn` (line 276). It is not a parameter of `_drain_sse_events!`, and the module has
  no global of that name (`grep input_tokens` finds lines 188, 190, 194, 230, 276 and 389 only). So the
  first complete SSE event, `message_start`, raises `UndefVarError`. The error leaves `stream_turn`,
  `run_turn!` throws it again, and the assistant shows "Error: UndefVarError …" instead of an answer.
  Commit a44e10c3 added the keyword to the call and did not pass the value in. `AnthropicTest.jl`
  tests the model lookup and the tool schema, and no test sends an SSE body through the parser.
- Rule: bug; PAR-NEW-CODE-SHIPS-TESTS (the parser has no test).
- Fix: give `_drain_sse_events!` an `input_tokens` keyword and pass the `Ref` from `stream_turn`
  (lines 335 and 337). Add a test that sends a recorded SSE body through `_drain_sse_events!` and
  checks the events.
- Reach: `source/adapter/anthropic/AnthropicLlm.jl`, `test/adapter/anthropic/AnthropicLlmTest.jl`. No kernel file.

### L19-2 The adapters do not keep the promises of the stream contract

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [LlmInterface.jl:26-38](../../../source/kernel/llm/LlmInterface.jl#L26) ⬜,
  [LlmEvent.jl:123-143](../../../source/kernel/llm/LlmEvent.jl#L123) ⬜,
  [Anthropic.jl:230](../../../source/adapter/anthropic/AnthropicLlm.jl#L230),
  [Anthropic.jl:308](../../../source/adapter/anthropic/AnthropicLlm.jl#L308),
  [Ollama.jl:363](../../../source/adapter/ollama/OllamaLlm.jl#L363)
- Evidence:
  1. `stream_turn` promises "the last event is an `LlmTurnEnd` … (or an `LlmFailure`)". Both adapters
     take an early end of the connection as a clean end (`e isa EOFError ? UInt8[] : rethrow()`,
     Anthropic.jl:331, Ollama.jl:388) and then send no terminal event. L20-5 shows what the loop does
     with that.
  2. `LlmTurnEnd` promises that `stop_reason` "is normalised across providers" to `:end_turn`,
     `:tool_use`, `:max_tokens` and `:error`. The Anthropic adapter sends the provider's word on,
     `emit(LlmTurnEnd(Symbol(sr), …))`, so `:pause_turn`, `:refusal` and `:stop_sequence` reach the
     loop. `:pause_turn` asks the caller to continue the turn, and `run_turn!` ends it instead.
  3. The contract says nothing about time, and neither stream request sets `readtimeout`
     (Anthropic.jl:308, Ollama.jl:363; the capability request at Ollama.jl:199 also has none). The
     default of HTTP.jl is `readtimeout::Int=0`, which is no read timeout
     (`HTTP/src/clientlayers/ConnectionRequest.jl:60` in the depot). A server that sends no more data holds
     the turn for ever (L20-1).
- Rule: bug. PAR-BACKEND-SEAM by analogy: the same loop must run unchanged over each provider.
- Fix: write in the `stream_turn` docstring that an adapter ends every stream with `LlmTurnEnd` or
  `LlmFailure` (an early end is an `LlmFailure`), maps each stop reason of its provider to the four
  symbols, and bounds each read with a timeout. Make both adapters do so.
- Reach: `LlmInterface.jl`, `LlmEvent.jl` (docstrings only); `source/adapter/anthropic/AnthropicLlm.jl`;
  `source/adapter/ollama/OllamaLlm.jl`; a test in each adapter test package.

### L19-3 `default_llm_model` has no production caller, and its Anthropic answer is false

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [LlmInterface.jl:108-115](../../../source/kernel/llm/LlmInterface.jl#L108) ⬜,
  [LlmDefaults.jl:27-28](../../../source/kernel/llm/LlmDefaults.jl#L27) ⬜,
  [Anthropic.jl:97](../../../source/adapter/anthropic/AnthropicLlm.jl#L97),
  [Anthropic.jl:108](../../../source/adapter/anthropic/AnthropicLlm.jl#L108)
- Evidence: the docstring says "The model this backend talks to when nobody names one".
  `default_llm_model(::Val{:anthropic})` answers `"claude-opus-5"`, but `AnthropicLlm(; model = "")`
  asks the Models API for the newest model with adaptive thinking (line 97), and it uses the fallback
  only when that request fails. A search of `source/`, `package/`, `example/` and omnet-julia finds no
  call outside the adapters and their tests (`OllamaTest.jl:72, 178`, `AnthropicTest.jl:51`).
- Rule: architecture-rules.md "No orphans shape the structure" (by analogy for a generic); PAR-HONEST-DOCS.
- Fix: remove the generic, its fallback and the two adapter methods, or keep it and say that it answers
  the fallback model, not the model a backend with an empty name uses.
- Reach: `LlmInterface.jl`, `LlmDefaults.jl`, `LlmModule.jl` (export), the two adapters and their
  tests, `documentation/package/kernel/agent.md:287`.

### L19-4 The export block is one statement over four fragments

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [LlmModule.jl:36-46](../../../source/kernel/llm/LlmModule.jl#L36) ⬜
- Evidence: one `export` names the names of `LlmInterface.jl`, `Llm.jl`, `LlmMessage.jl` and
  `LlmEvent.jl` together, and puts `bind_meaning_model!` (from `Llm.jl`) between the interface names.
  code-quality-rules.md §1 asks for one statement per fragment, in the order of the includes. The file
  is on the list of modules that are not migrated in `test/suite/exports.jl:60`.
- Rule: code-quality-rules.md §1.
- Fix: one statement for each of `LlmInterface.jl`, `Llm.jl`, `LlmMessage.jl`, `LlmEvent.jl`, in
  include order, and remove the file from the list.
- Reach: `LlmModule.jl`, `test/suite/exports.jl`.
- Planned: plan/pending/export-block-rule.md (row `source/kernel/llm/LlmModule.jl`, 1 finding, open).

### L19-5 The newest-model cache of the Anthropic adapter is process-global and ignores the key

- Category: State · Severity: Low · Confidence: Confirmed
- Where: [Anthropic.jl:9](../../../source/adapter/anthropic/AnthropicLlm.jl#L9),
  [Anthropic.jl:30-44](../../../source/adapter/anthropic/AnthropicLlm.jl#L30)
- Evidence: `const _NEWEST_MODEL = Ref{String}("")`. `get_newest_anthropic_model(api_key; models_url)`
  answers the stored value when it is not empty, whatever key or URL the caller gives. A request that
  fails stores the fallback, and the process keeps it. A second editor with another key, or another
  `models_url`, gets the answer of the first.
- Rule: PAR-PER-EDITOR-STATE. The carve-out covers only a value that is the same for every editor, and
  this value depends on the key.
- Fix: keep the answer per `(models_url, key)` pair, or on the backend instance, and do not store the
  answer of a request that failed.
- Reach: `source/adapter/anthropic/AnthropicLlm.jl`. No kernel file.

### L19-6 `default_llm_model` does not start with a verb

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [LlmInterface.jl:115](../../../source/kernel/llm/LlmInterface.jl#L115) ⬜
- Evidence: naming-rules.md: "Every function name starts with a verb". The value sits at a known place,
  so the name is `get_default_llm_model`. If L19-3 removes the function, this finding closes too.
- Rule: naming-rules.md "Functions"; PAR-NAMING-LAW.
- Fix: rename with `workspace/bin/julia-rename.jl` to `get_default_llm_model`.
- Reach: `LlmInterface.jl`, `LlmDefaults.jl`, `LlmModule.jl`, both adapters and their test packages,
  agent.md.

### L19-7 The module docstring and three guides give a wrong file map

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [LlmModule.jl:5-11](../../../source/kernel/llm/LlmModule.jl#L5) ⬜;
  `documentation/package/kernel/agent.md:213-217`, `:282`;
  `documentation/design/system-anatomy.md:178`, `:344`;
  `documentation/rule/architecture-rules.md:82`, `:105`; `documentation/rule/division-terminology.md:16`
- Evidence:
  - The module docstring says "Three fragments share this namespace" and puts "the `stream_turn` /
    `render_tool_schema` seams" in `Llm.jl`. The module includes five fragments, and the seams are in
    `LlmInterface.jl` (since 4c067207). `LlmDefaults.jl` is not named.
  - agent.md:213-217 gives the same three-file map. agent.md:282 says that `make_llm`,
    `default_llm_model` and `get_llm_backend_names` "all three live in `llm/LlmInterface.jl`";
    `get_llm_backend_names` is in `Llm.jl:33`.
  - system-anatomy.md:178 and :344, architecture-rules.md:82 and :105, and division-terminology.md:16
    name an opt-in package `Llm` or `llm`. No such package exists; the adapters are
    `ProjecturedAnthropic` and `ProjecturedOllama`, as package-rules.md:210-211 says.
- Rule: PAR-MODULE-DOCSTRING ("a docstring that names a function that no longer exists is a defect"),
  PAR-HONEST-DOCS.
- Fix: list the five fragments in the module docstring; correct the two agent.md passages; replace
  `Llm`/`llm` with the two adapter packages in the three rule and design documents.
- Reach: `LlmModule.jl`, four documents.

### L19-8 Contract docstrings name consumers and give objects a will

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [LlmInterface.jl:43-44](../../../source/kernel/llm/LlmInterface.jl#L43),
  [LlmInterface.jl:83](../../../source/kernel/llm/LlmInterface.jl#L83),
  [LlmInterface.jl:100-101](../../../source/kernel/llm/LlmInterface.jl#L100),
  [LlmEvent.jl:12-13](../../../source/kernel/llm/LlmEvent.jl#L12),
  [LlmEvent.jl:115-117](../../../source/kernel/llm/LlmEvent.jl#L115),
  [LlmModule.jl:27](../../../source/kernel/llm/LlmModule.jl#L27) ⬜
- Evidence:
  - PAR-NO-CONSUMER-DOCS: "(for Anthropic, a JSON-Schema-shaped `Vector{Dict}`)", "(`:anthropic`,
    `:ollama`)", "exactly as `make_agent_server(:mcp, editor)` is" (a function of the agent layer
    above), "the agent loop needs the tool-use events", "what lets the agent loop dispatch a tool", and
    `make_llm(:ollama)` in the module docstring. The seam carve-out allows the kinds of value on each
    side of a seam, not a named provider or a higher layer.
  - writing-rules.md "No personification": "A `Tool` … knows no wire format at all"
    (LlmInterface.jl:47), "whatever shape this provider's API wants" (:15), "the parts a provider may
    decline" (:4).
  - Line 110 of `LlmMessage.jl` has 93 characters (budget 90).
- Rule: PAR-NO-CONSUMER-DOCS; writing-rules.md; code-quality-rules.md §5.
- Fix: name the kind of value ("a provider-specific tool list", "a caller that runs tools"), and say
  what the code does ("a `Tool` holds no wire format").
- Reach: `LlmInterface.jl`, `LlmEvent.jl`, `LlmModule.jl`, `LlmMessage.jl`.

### L19-9 The layer has no kernel test

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/` (no `llm/` folder)
- Evidence: the behaviour of the layer is tested only from packages above it, or not at all. Not
  tested anywhere: the error of `default_llm_model` for a kind that no package answers, the answer of
  `get_llm_backend_names()` when no adapter is loaded, `is_walk_opaque(::Llm)`, and the conversions of
  the `LlmRequest` and `LlmMessage` convenience constructors. `ProjecturedKernelTest` already loads
  `ProjecturedKernelExample` (`test/kernel/editor/FeedsTest.jl:49`), so `FakeLlm` is at hand.
- Rule: PAR-NEW-CODE-SHIPS-TESTS (the lowest test package that can express the test).
- Fix: add `test/kernel/llm/LlmDefaultsTest.jl` for the fallbacks and the registry, and move the error
  check of AssistantMvpTest.jl:223 there.
- Reach: `test/kernel/llm/`, `package/ProjecturedKernelTest`, `test/kernel/KernelSuite.jl`.

## Accepted before, not raised again

- There is no prior audit of this layer.
- `get_llm_backend_names` loops over the method table and keeps the `get_` verb: the owner agreed the
  name in plan/pending/naming-rule-renames.md:407.
- The kernel has no JSON parser, so an adapter parses the tool arguments and `LlmToolUseStop` carries
  a parsed `LlmToolUse` (a design decision in plan/done/kernel-agent-stack.md and agent.md).

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `LlmInterface.jl` holds only the abstract type and bodiless
  generics, and `LlmModule` exports every name it declares; the guard lists the file.
- PAR-OPT-IN-DEPENDENCY: the kernel names no provider type; `make_llm(:kind)` dispatches on `Val`; a
  kind that no package answers raises an error that lists the loaded backends.
- PAR-NO-TEST-DOUBLES-IN-MAIN: `FakeLlm` and `ScriptedLlm` live in `ProjecturedKernelExample`; no
  main code path builds one (the assistant raises an error for backend `:none`).
- PAR-PER-EDITOR-STATE in the kernel part: no global, no `Ref`, no cache.
- PAR-FRAMEWORKS-SINK: `bind_meaning_model!` gives the `ToolSet` a `MeaningModel` (a name and a
  function), never the backend, so the tool layer stays below the llm layer.
- PAR-QUALIFIED-EXTENSION and PAR-MODULE-BOUNDARY-IS-API: `Llm.jl` extends
  `DocumentModule.is_walk_opaque` by qualification, and the name is exported; no code reaches a private
  name of `LlmModule`, and the layer reaches none.
- PAR-LOWEST-PACKAGE and the layer order: `llm` sits on `tool` (a request carries tools) and below
  `agent` (the loop drives a model).
- Naming of the other 31 exported names; no history comment (the grep of code-quality-rules.md §2
  finds none).
