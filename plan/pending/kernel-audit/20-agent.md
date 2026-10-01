# Layer 20 — agent (`source/kernel/agent/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 5).

## Verdict

The layer holds both directions of the AI control surface in one module: the agent-server seam that
an MCP transport answers, and the loop `run_turn!` that drives a model over the editor's tools. The
seams are complete and used, and the layer holds no process-global state. The loop has no time bound
and no cancel: one provider that sends no more data in a stream makes the assistant refuse all input until the process
restarts (L20-1, L20-2). Its tool barrier catches the exceptions that mean stop and marks a thrown
`error(...)` as a success (L20-3, L20-6), each turn replaces tools the caller registered (L20-4), and a
stream that ends early counts as a finished turn (L20-5). None of this has a kernel test: the kernel
suite runs 2 assertions for the layer (L20-7).

## Shape

- Purpose: the inbound half (`make_agent_server`, `start_agent_server!`, `stop_agent_server!`, the
  seams an agent server answers) and the outbound half (`Agent`, `run_turn!`, `AgentToolResult`), and
  `run_on_editor_task!`, the one door that both halves use to run a tool on the editor task.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `AgentModule.jl` | 47 | ⬜ | module head: docstring, three `using`, two export statements, four includes |
  | `AgentInterface.jl` | 68 | ⬜ | contract: `make_agent_server`, `start_agent_server!`, `stop_agent_server!`, `run_on_editor_task!` (bodiless) |
  | `AgentDefaults.jl` | 17 | ⬜ | the `Symbol` → `Val` redispatch, the error for an unknown kind, `run_on_editor_task!` that runs at once |
  | `Agent.jl` | 57 | ⬜ | `Agent` (mutable), `AgentEvent`, `AgentToolResult` |
  | `AgentLoop.jl` | 96 | ⬜ | `_is_error_output`, `run_turn!` |

- Imports: `FaultModule` (`record_fault!`, `get_fault_store`), `ToolModule` (`register_default_tools!`,
  `list_tools`, `call_tool`, `ToolSet`), `LlmModule`. Imported by: `EditorModule` (answers
  `run_on_editor_task!` for an `Editor` in `editor/Inbox.jl:106`, drives the server in
  `editor/EditorLoop.jl:150-152, 194`), `AssistantModule` (`source/platform/assistant/AssistantTurn.jl:707-715`),
  `ProjecturedMcp` (`source/adapter/mcp/McpServer.jl:64-66, 155`), `ProjecturedKernelExample` and
  `example/platform/fault/FaultExamples.jl:204-206`, and omnet-julia `OmnetIdeTest` (reads `AgentToolResult`).
  inet-julia does not use the layer.
- Public surface: 8 exported names. `AgentEvent` has no user outside the layer; the other 7 have users
  outside the kernel.
- State: no global. The assistant builds an `Agent` per turn. The loop keeps its round state in
  locals. The one write to shared state is `register_default_tools!` on the editor's `ToolSet`, from
  the turn's task (L20-4).
- Bounds: `max_rounds` (default 8) bounds the rounds of a turn. Nothing bounds the time of a round, the
  wait for the editor's answer, or the turn (L20-1).
- Tests: `test/kernel/agent/AgentDefaultsTest.jl` (2 assertions, `make_agent_server` only; the baseline log
  shows "Agent seam | 2"). `run_on_editor_task!` is tested in `test/kernel/editor/InboxTest.jl:86-130`.
  `run_turn!` runs only through the assistant in the umbrella (`AssistantMvpTest.jl:423-460, 811-855`)
  and in `example/platform/fault/FaultExamples.jl:196-207`.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 4 | 1 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 0 | 2 |
| Documentation | 0 | 0 | 2 |
| Tests | 0 | 1 | 0 |

## Findings

### L20-1 A turn has no time bound, so one silent provider locks the assistant

- Category: Correctness · Severity: High · Confidence: Confirmed (the race at the end of the loop is
  Suspected)
- Checked by the lead on 2026-09-27: Read the code: `take!(answer)` at `Inbox.jl:115` has no bound, and `AgentLoop.jl` has no timeout.
- Where: [AgentLoop.jl:42-47](../../../source/kernel/agent/AgentLoop.jl#L42) ⬜,
  [AgentLoop.jl:55](../../../source/kernel/agent/AgentLoop.jl#L55) ⬜,
  [AgentLoop.jl:77](../../../source/kernel/agent/AgentLoop.jl#L77) ⬜,
  [AgentInterface.jl:44-68](../../../source/kernel/agent/AgentInterface.jl#L44) ⬜;
  [Inbox.jl:115](../../../source/kernel/editor/Inbox.jl#L115) ⬜ (layer 22)
- Evidence: the only bound of the loop is `round > agent.max_rounds`. A round waits on `stream_turn`,
  which has no timeout in either adapter (L19-2), and each tool call waits on
  `run_on_editor_task!`, whose editor method waits with `take!(answer)` and no timeout. The assistant
  runs the turn on an `@async` task (AssistantTurn.jl:242) and returns `nothing` for every submit while
  `status === :streaming` (AssistantTurn.jl:271, 297, 343). `ResetConversationOperation`
  (AssistantTurn.jl:199) does not change the status. So when a local Ollama server stops in the
  middle of a stream, the assistant refuses all input until the process restarts.
  Suspected, needs a run with a full inbox: at the end of the loop the editor sets `loop_task` to
  `nothing` and then answers the calls in the inbox (EditorLoop.jl:192-193). A call whose `put!` waited
  on a full inbox (capacity 64) and completes after that drain is never answered, so its caller waits
  for ever.
- Rule: bug (a wait with no bound).
- Fix: give each wait its own timeout. Require a read timeout in the adapters (L19-2); give `Agent` a
  time limit per round that the `on_event` wrapper checks, and end the round with `:error` when the
  limit passes; give `run_on_editor_task!` a `timeout` keyword that throws after it.
- Reach: `AgentLoop.jl`, `Agent.jl`, `AgentInterface.jl`, `AgentDefaults.jl`, `editor/Inbox.jl`
  (layer 22), `source/adapter/anthropic/AnthropicLlm.jl`, `source/adapter/ollama/OllamaLlm.jl`,
  `source/platform/assistant/AssistantTurn.jl`. None is sealed.

### L20-2 A turn can not be cancelled

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [AgentLoop.jl:36](../../../source/kernel/agent/AgentLoop.jl#L36) ⬜,
  [Agent.jl:22-28](../../../source/kernel/agent/Agent.jl#L22) ⬜
- Evidence: `run_turn!(agent, target; messages, on_event)` takes no stop signal, and the loop checks
  none before a round, between events, or before a tool call. `Agent` has no flag either. The only
  ways out are the round cap and an exception from a callback. The assistant has no stop operation. A
  person who sees the model repeat a wrong tool call waits for up to 8 rounds, and with L20-1 a round
  that hangs can not be ended at all.
- Rule: bug.
- Fix: add a `cancel` keyword to `run_turn!` (a `Threads.Atomic{Bool}` or a function that answers a
  `Bool`). Check it before each round, in the `on_event` wrapper, and before each tool call, and
  return `:cancelled`.
- Reach: `AgentLoop.jl`, the `run_turn!` docstring and agent.md, `source/platform/assistant/AssistantTurn.jl`
  (a stop operation that sets the flag).

### L20-3 A tool that throws `error(...)` is reported with `is_error = false`

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [AgentLoop.jl:8-9](../../../source/kernel/agent/AgentLoop.jl#L8) ⬜,
  [AgentLoop.jl:86-92](../../../source/kernel/agent/AgentLoop.jl#L86) ⬜
- Evidence: the `catch` arm knows that the call failed, but its text goes through `_is_error_output`,
  which looks for `"ERROR"` or `"Error"`. Julia prints an `ErrorException` as its message only
  (`showerror(io::IO, ex::ErrorException) = print(io, ex.msg)`, base/errorshow.jl:164), and the frames
  after it (`error(s::String)`, `./error.jl`) hold neither word. So `error("no such pane")` in a
  handler gives `AgentToolResult(call, text, false)`. The assistant copies the flag into
  `EvaluatorForm.is_error` and `LlmToolResult.is_error` (AssistantTurn.jl:529, 774), and it parses the
  text of a failed Markdown tool as Markdown (AssistantTurn.jl:741-742). The fault example throws in
  exactly this way (FaultExamples.jl:193). The umbrella test throws an `ArgumentError` on purpose, "so
  the exception says 'Error' in its name" (AssistantMvpTest.jl:431). The docstring of the heuristic
  itself says that a false negative "lets the model build on a stack trace it thinks succeeded". The
  assistant repeats the heuristic in its own code (AssistantTurn.jl:218).
- Rule: bug.
- Fix: the `catch` arm answers `(text, true)`; only the normal arm uses the heuristic. The assistant
  then reads the flag that the loop gives and drops its copy.
- Reach: `AgentLoop.jl`; `source/platform/assistant/AssistantTurn.jl:218`.

### L20-4 Every turn registers the default tools again and replaces a caller's tool of the same name

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [AgentLoop.jl:37](../../../source/kernel/agent/AgentLoop.jl#L37) ⬜
- Evidence: `register_default_tools!(agent.tools)` runs at the start of every turn, and
  `register_tool!` replaces a tool that has the same name (`tool/ToolSet.jl:67-71`). A caller that puts
  its own `execute_julia_code`, `search_api`, `search_guides`, `read_function_documentation`,
  `list_resources` or `read_resource` into the editor's `ToolSet` gets the default back at the next
  turn, with no message. The write runs on the turn's task, not through `run_on_editor_task!`, which
  the layer names as the one door for a write from another task (AgentInterface.jl:8-12). No caller in
  projectured-julia or omnet-julia replaces a default name today. A probable reason for the call is to
  refresh the tool descriptions after `declare_api!`.
- Rule: bug.
- Fix: leave the registration to the owner of the `ToolSet` (the editor or the caller), or register
  only the default names that the set does not hold. If the descriptions must follow `declare_api!`,
  make `declare_api!` refresh them.
- Reach: `AgentLoop.jl`; possibly `tool/DefaultTools.jl`, `tool/ToolSet.jl` (layer 18).

### L20-5 A stream that ends with no terminal event counts as a finished turn

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [AgentLoop.jl:49-52](../../../source/kernel/agent/AgentLoop.jl#L49) ⬜,
  [AgentLoop.jl:70](../../../source/kernel/agent/AgentLoop.jl#L70) ⬜
- Evidence: each round sets `stop = :end_turn` before the stream, and only an `LlmTurnEnd` or an
  `LlmFailure` changes it. Both adapters end a stream at an early end of the connection with no
  terminal event (L19-2). The loop then returns `:end_turn`: the caller shows a cut answer as complete,
  and a tool call whose block did not close is dropped with no event.
- Rule: bug.
- Fix: start each round with `stop = nothing`. After `stream_turn` returns, a round with no terminal
  event sets `stop = :error` and sends `LlmFailure("the stream ended with no turn end")` to `on_event`.
- Reach: `AgentLoop.jl`.

### L20-6 The tool barrier catches the exceptions that mean stop, and it exists twice

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [AgentLoop.jl:78-90](../../../source/kernel/agent/AgentLoop.jl#L78) ⬜;
  [Mcp.jl:162-169](../../../source/adapter/mcp/McpServer.jl#L162) (the copy, outside the kernel)
- Evidence: `catch e` has no `is_passthrough_exception(e) && rethrow()`. A `QuitEditorException` from a
  tool (marked passthrough at `operation/Operations.jl:74`), or an `InterruptException` while a tool
  waits, becomes tool text, and the turn and the editor go on. `RunFunctionOperation` rethrows a
  passthrough exception (Inbox.jl:101), but the catch inside the function runs first. The same arm also
  calls `sprint(showerror, e, traceback)` with no guard; a `showerror` method that throws leaves the
  barrier, while `fault/FaultRecord.jl:74-102` guards the same call. `Mcp.jl` holds the same
  catch-record-print block, with the same two gaps.
- Rule: PAR-REPORT-NEVER-THROWS ("An exception that means the program is to stop or can not go on is
  never caught"; "A fault report never throws").
- Fix: one exported function that calls a tool inside the barrier. It rethrows a passthrough
  exception, guards `showerror`, records the fault, and answers `(text, is_error)`. The loop and the
  MCP handler call it. This also fixes L20-3.
- Reach: `AgentLoop.jl` (or `tool/ToolSet.jl`, layer 18, for the helper); `source/adapter/mcp/McpServer.jl`.

### L20-7 The agent loop has no kernel test

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: `test/kernel/agent/AgentDefaultsTest.jl`
- Evidence: the kernel suite runs 2 assertions for the layer, both on `make_agent_server`. No kernel
  test covers `run_turn!`: the round cap and its return value, `LlmFailure` → `:error`, a tool that
  throws (the fault record and `is_error`), a tool name that no tool answers (`KeyError`), a stream with
  no terminal event, or the order of `AgentToolResult` events. The only runs of the loop are the
  assistant tests in the umbrella and one example. `ScriptedLlm` is in `ProjecturedKernelExample`,
  which `ProjecturedKernelTest` already loads. The file name `AgentSeamTest.jl` names no file of the
  layer (naming-rules.md: `<Thing>Test.jl`, where `<Thing>` is the file it tests).
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add `test/kernel/agent/AgentLoopTest.jl` with `ScriptedLlm` and a `NamedTuple` target, and
  rename `AgentSeamTest.jl` to `AgentDefaultsTest.jl`.
- Reach: `test/kernel/agent/`, `package/ProjecturedKernelTest`, `test/kernel/KernelSuite.jl`.

### L20-8 A round cap of zero or less ends the turn at once and answers `:end_turn`

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Agent.jl:30-32](../../../source/kernel/agent/Agent.jl#L30) ⬜,
  [AgentLoop.jl:40-47](../../../source/kernel/agent/AgentLoop.jl#L40) ⬜
- Evidence: the constructor accepts any integer. With `max_rounds = 0` the first check `1 > 0` logs
  "hit the round cap" and breaks, and `run_turn!` returns `:end_turn`, which the docstring gives for a
  model that finished. No round ran.
- Rule: bug.
- Fix: `max_rounds >= 1 || throw(ArgumentError("max_rounds must be at least 1"))` in the constructor.
- Reach: `Agent.jl`.

### L20-9 Small parts of the surface are loose or unused

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Agent.jl:22](../../../source/kernel/agent/Agent.jl#L22) ⬜,
  [Agent.jl:40](../../../source/kernel/agent/Agent.jl#L40) ⬜,
  [AgentLoop.jl:36](../../../source/kernel/agent/AgentLoop.jl#L36) ⬜,
  [AgentDefaults.jl:11-13](../../../source/kernel/agent/AgentDefaults.jl#L11) ⬜
- Evidence:
  - `Agent` is a `mutable struct`, and no code in projectured-julia or omnet-julia writes a field.
  - `AgentEvent` has one subtype and no user: no method dispatches on it, in any repository.
  - `run_turn!` types its callbacks `messages::Function, on_event::Function`, so a callable struct is
    refused.
  - The error of `make_agent_server` for an unknown kind does not list the loaded servers; the error of
    `make_llm` does (`LlmDefaults.jl:21-25`).
- Rule: architecture-rules.md "No orphans shape the structure"; consistency of the two factory seams.
- Fix: make `Agent` a `struct`; remove `AgentEvent` or dispatch on it; drop the `::Function`
  restrictions; list the loaded servers in the error, read off the method table as
  `get_llm_backend_names` does.
- Reach: `Agent.jl`, `AgentLoop.jl`, `AgentDefaults.jl`, `AgentModule.jl` (export).

### L20-10 The module header is out of order, and the export block mixes fragments

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [AgentModule.jl:35-40](../../../source/kernel/agent/AgentModule.jl#L35) ⬜
- Evidence: the `using` lines are `FaultModule`, `ToolModule`, `LlmModule`, not sorted by name. The first
  export statement mixes `Agent.jl` (`Agent`, `AgentEvent`, `AgentToolResult`) and `AgentLoop.jl`
  (`run_turn!`), and the statement of the interface comes last, although `AgentInterface.jl` is the
  first include. The file is on the list of modules that are not migrated in `test/suite/exports.jl:52`.
- Rule: code-quality-rules.md §1.
- Fix: sort the `using` lines; one export statement each for `AgentInterface.jl`, `Agent.jl` and
  `AgentLoop.jl`, in include order.
- Reach: `AgentModule.jl`, `test/suite/exports.jl`.
- Planned: plan/pending/export-block-rule.md (row `source/kernel/agent/AgentModule.jl`, 2 findings,
  open). The order of the `using` lines is not in that plan.

### L20-11 Four documents give a wrong file map of the layer

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [AgentModule.jl:4-6](../../../source/kernel/agent/AgentModule.jl#L4) ⬜;
  `documentation/design/system-anatomy.md:327`, `:395-396`;
  `documentation/package/kernel/agent.md:395-398`, `:456`
- Evidence:
  - The module docstring opens with "The **outbound** half of the agent layer". The module holds both
    halves; `AgentInterface.jl` is the inbound contract.
  - system-anatomy.md:395-396 says "AgentModule (inbound, the MCP seam) and AgentModule (outbound, the
    Agent and run_turn! loop)": one module, named twice. The text is left from two modules that are now
    one. system-anatomy.md:327 puts the MCP seam in `agent/AgentModule.jl`.
  - agent.md:395-398 lists `AgentModule.jl` as the file of `make/start/stop_agent_server!` and
    `run_on_editor_task!`, and does not name `AgentInterface.jl` or `AgentDefaults.jl`. agent.md:456
    says the seam is "Declared in `agent/AgentModule.jl`"; it is declared in `AgentInterface.jl`.
- Rule: PAR-MODULE-DOCSTRING, PAR-HONEST-DOCS.
- Fix: say that the module holds both halves; correct the file map in system-anatomy.md and agent.md.
- Reach: `AgentModule.jl`, two documents.

### L20-12 Docstrings name consumers, repeat each other, and give the loop a will

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [AgentInterface.jl:5-16](../../../source/kernel/agent/AgentInterface.jl#L5),
  [AgentInterface.jl:65-66](../../../source/kernel/agent/AgentInterface.jl#L65),
  [Agent.jl:10-13](../../../source/kernel/agent/Agent.jl#L10),
  [AgentLoop.jl:11-35](../../../source/kernel/agent/AgentLoop.jl#L11),
  [AgentLoop.jl:76](../../../source/kernel/agent/AgentLoop.jl#L76),
  [AgentLoop.jl:83](../../../source/kernel/agent/AgentLoop.jl#L83),
  [AgentModule.jl:21](../../../source/kernel/agent/AgentModule.jl#L21) ⬜
- Evidence:
  - PAR-NO-CONSUMER-DOCS: "which the editor layer answers" (AgentInterface.jl:12), "The editor layer
    answers an `Editor` whose loop runs on another task" (:65-66), "Independent of the editor loop,
    which reaches it only through `make_agent_server`" (:5-6, :15-16), "in practice an editor's own"
    (Agent.jl:10), "(an `Editor`, in practice)" (AgentLoop.jl:19), "as the call of an MCP client does"
    (AgentLoop.jl:76).
  - PAR-TIGHT-COMMENTS: the fragment header of AgentInterface.jl:8-12 repeats AgentModule.jl:28-31
    (the two halves are mirror images).
  - writing-rules.md: "decides whether to go around again" (AgentLoop.jl:33, AgentModule.jl:21) gives
    the loop a will; "can never run away" (Agent.jl:13) and "the whole point" (AgentLoop.jl:83) are
    idioms.
  - The `run_turn!` docstring does not say that it throws what `stream_turn`, `messages` and
    `on_event` throw. The assistant depends on that (AssistantTurn.jl:243-256).
  - AgentLoop.jl:45 has 98 characters and :87 has 93 (budget 90).
- Rule: PAR-NO-CONSUMER-DOCS, PAR-TIGHT-COMMENTS, writing-rules.md, code-quality-rules.md §5.
- Fix: describe the contract without the layer above; keep one statement of the two halves in the
  module docstring; say "the loop streams, runs the tools, and stops when the model asks for no tool";
  add a "Throws" line to `run_turn!`; wrap the two lines.
- Reach: `AgentInterface.jl`, `Agent.jl`, `AgentLoop.jl`, `AgentModule.jl`.

## Accepted before, not raised again

- There is no prior audit of this layer.
- `Agent` holds no transcript, and `messages` is a callback: a design decision in
  plan/done/kernel-agent-stack.md and agent.md.
- `_is_error_output` is generous on purpose: a false positive costs an extra round (AgentLoop.jl:3-7).
  Only the false negative on the thrown path is raised (L20-3).
- The round cap of 8 is a documented choice (Agent.jl:12-16). Whether the application sets it is item
  A4 of plan/pending/feature-video-screenplays.md.
- The 7 keywords of `run_fault_barrier` (accepted 2026-09-24) do not apply here.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `AgentInterface.jl` holds four bodiless generics, all exported; the
  guard lists the file.
- PAR-OPT-IN-DEPENDENCY: `make_agent_server(:mcp, editor)` dispatches on `Val`; `ProjecturedMcp`
  answers it and `start_agent_server!` / `stop_agent_server!`; the editor never names `McpServer`.
- PAR-PER-EDITOR-STATE: no global in the layer; the target and the tool set come from the caller.
- PAR-AI-SAME-GUARANTEES and PAR-STORE-THEN-DRAIN: every tool call of the loop and of the MCP server
  runs on the editor task through `run_on_editor_task!`; the default runs a target that has no loop at
  once.
- PAR-QUALIFIED-EXTENSION and PAR-MODULE-BOUNDARY-IS-API: the fragments define the module's own
  generics; `editor/Inbox.jl:106` extends `AgentModule.run_on_editor_task!` by qualification; no code
  reaches a private name of `AgentModule`.
- PAR-NO-TEST-DOUBLES-IN-MAIN: the test server `ToyServer` is in the test file.
- Naming of `run_turn!`, `run_on_editor_task!`, `make_agent_server`, `start_agent_server!`,
  `stop_agent_server!`, `AgentToolResult`; no history comment.
