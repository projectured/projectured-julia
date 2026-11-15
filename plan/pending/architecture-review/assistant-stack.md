# Architecture review: the assistant — tool set, models, agents, conversation, MCP and ACP

Commit 3a9b4fae4. Reviewer area key: assistant-stack.

## Scope

Paths: `source/kernel/{tool,llm,agent,feed}`, `source/platform/{assistant,conversation,mcplog,help}`,
`source/adapter/{acp,mcp,ollama,anthropic,openrouter}`, `tool/assistant`. The area holds about 24 400 lines
(corrected from 23 900 by the check).

**Read in full (about 8 100 lines of code and 1 000 lines of documents):**

- Documents: `documentation/design/concepts.md`, `documentation/design/architecture-decisions.md`,
  `documentation/package/kernel/agent.md`, and the two guides `assistant-guide.md` and `mcp-guide.md`.
  Of `architecture-invariants.md`: the index, PAR-PER-EDITOR-STATE, PAR-NO-EDITOR-IN-DOCUMENT,
  PAR-ONE-WAY-TO-EDIT and PAR-AI-SAME-GUARANTEES.
- Kernel tool layer: `Tool.jl`, `ToolSet.jl`, `DefaultTools.jl`, `ToolModule.jl`, `BackgroundWork.jl`, `AssistantMark.jl`.
- Kernel llm layer: all five fragments.
- Kernel agent layer: `AgentLoop.jl`, `Agent.jl`, `AgentInterface.jl`, `AgentDefaults.jl`,
  `AgentConnectionInterface.jl`, `AgentConnectionDefaults.jl`.
- Platform assistant: `AssistantModule.jl`, `AssistantDocument.jl`, `AssistantTurn.jl`, `ExternalAgentTurn.jl`,
  `AgentEventFeed.jl`, `AssistantApi.jl`.
- Platform conversation: `ConversationDocument.jl`. Platform mcplog: `McpLogStore.jl`, `McpLogFeed.jl`.
- Adapters: `AnthropicLlm.jl`, `McpServer.jl`.

**Sampled (outline by `grep`, and the passages that a candidate needed):** `Documentation.jl` (1 823 lines),
`CodeExecution.jl`, `AgentConnectionEvent.jl`, `AssistantToWidget.jl` (the first 330 of 569 lines),
`AgentWorkDocument.jl`, `AssistantWorkDocument.jl`, `ConversationToWidget.jl` (about 150 of 1 309 lines),
`ConversationEditor.jl`, `Evaluator.jl` (about 280 of 981 lines), `EvaluatorToWidget.jl`, `OllamaLlm.jl` (about 180
of 574 lines), `OpenRouterRelevance.jl`, the help slice, and the parts of
`source/platform/application/Application.jl` that put the instructions together.

**Not read:** `MeaningSearch.jl`, `RelevanceSearch.jl`, `SearchQuery.jl`, `CodeUnit.jl`, the feed layer of the kernel,
`AcpConnection.jl` and `AcpUpdate.jl` beyond their outline, `AssistantList*.jl`, `AssistantOverview.jl`,
`AssistantWake.jl`, `AgentTerminal.jl`, `tool/assistant/rehearsal.jl` beyond one `grep`. The 419 names with the mark
`For the assistant.` belong to other areas, and I did not review them one by one.

**Plans:** I read the head of each of the twelve plans named for the area, the kernel audit files `18-tool.md`,
`19-llm.md`, `20-agent.md` (titles and the findings near a candidate) and the matching entries of
`kernel-audit-fixes.md`.

## State

The kernel half of the area is sound. Three small layers have clear seams: a `Tool` and a `ToolSet` (the tools of one
editor), an `Llm` (a model backend) with its own events, and an `Agent` with a loop, a server seam and a connection
seam. No wire format of a provider appears above an adapter. Every direction reaches the documents through one door,
`run_on_editor_task!`. The names that a model may write come from reflection, by one mark in a docstring.

The main weakness is that the same job exists twice wherever a second client or a second driver arrived later. The
kernel loop and the MCP server each run a tool call with their own code, and they follow different rules, because the
result of a tool is a bare string and its value and its failure travel beside it. The platform drives a turn with two
runners, one for a model in the process and one for an external agent, with two event shapes for a tool call. The
session of an agent has one document shape at the root and another for a subagent. The transcript draws seven kinds of
part inside one projection by a type switch, and an evaluation becomes a form in five places.

The smaller weaknesses have the same cause: two views of the assistant, two ways to send a message, search models that
reach a tool set as a side effect of a turn, adapters that repeat the HTTP skeleton, and state of one editor in tables
of the process.

## Inventory

### I1. Every way a model is driven

| | Model in the process (Ollama, Anthropic) | External agent (ACP) | Outside client (MCP) | Relevance model (OpenRouter) |
| --- | --- | --- | --- | --- |
| Seam of the kernel | `Llm` and `stream_turn` ([LlmInterface.jl:38](../../../source/kernel/llm/LlmInterface.jl#L38)); the loop `run_turn!` ([AgentLoop.jl:71](../../../source/kernel/agent/AgentLoop.jl#L71)) | 16 generics ([AgentConnectionInterface.jl:21](../../../source/kernel/agent/AgentConnectionInterface.jl#L21)) | `make_agent_server` ([AgentInterface.jl:21](../../../source/kernel/agent/AgentInterface.jl#L21)) | `RelevanceModel`, a struct of two functions ([Tool.jl:198](../../../source/kernel/tool/Tool.jl#L198)) |
| Who runs the loop | the kernel | the agent | the client | no loop |
| The tool set | `list_tools` at each turn, plus tools of the turn | through an MCP server with a secret ([ExternalAgentTurn.jl:761](../../../source/platform/assistant/ExternalAgentTurn.jl#L761)) | the MCP server; the list is fixed at its start ([McpServer.jl:127](../../../source/adapter/mcp/McpServer.jl#L127)) | none |
| Who runs a tool call | `run_turn!` ([AgentLoop.jl:114](../../../source/kernel/agent/AgentLoop.jl#L114)) | `render_mcp_tools` ([McpServer.jl:285](../../../source/adapter/mcp/McpServer.jl#L285)) | `render_mcp_tools` | none |
| The conversation document | the source of the messages (`build_messages`, [AssistantTurn.jl:607](../../../source/platform/assistant/AssistantTurn.jl#L607)) | a drawing of what the agent reports; the agent holds the history | none; the MCP log only | none |
| Events of a turn | `LlmEvent` and `AgentToolResult` ([Agent.jl:56](../../../source/kernel/agent/Agent.jl#L56)) | `LlmEvent` for text and reasoning, `AgentToolCallUpdate` ([AgentConnectionEvent.jl:33](../../../source/kernel/agent/AgentConnectionEvent.jl#L33)) and 12 more event types | none | none |
| How a streamed part enters the document | queue, `_TurnEventSource`, `_handle_agent_event!` ([AgentEventFeed.jl:228](../../../source/platform/assistant/AgentEventFeed.jl#L228)) | queue, session source, `apply_agent_event!` ([AgentEventFeed.jl:40](../../../source/platform/assistant/AgentEventFeed.jl#L40)) | — | — |
| Cancel | a flag, and an exception from the callbacks ([AssistantTurn.jl:951](../../../source/platform/assistant/AssistantTurn.jl#L951)) | `cancel_agent_prompt!` ([ExternalAgentTurn.jl:101](../../../source/platform/assistant/ExternalAgentTurn.jl#L101)) | the client's own | — |
| A question to the person | the turn tool `ask_person` ([AssistantTurn.jl:1004](../../../source/platform/assistant/AssistantTurn.jl#L1004)) | `AgentQuestionRequest`, `AgentPermissionRequest` | the client's own | — |
| Instructions | the `system` of the assistant, then the answer rules ([AssistantTurn.jl:941](../../../source/platform/assistant/AssistantTurn.jl#L941)) | the agent rules, then `system` ([ExternalAgentTurn.jl:290](../../../source/platform/assistant/ExternalAgentTurn.jl#L290)) | the `instructions` of the server ([Application.jl:622](../../../source/platform/application/Application.jl#L622)) | fixed texts in the adapter |
| HTTP and JSON | by hand in each adapter | a library | a library | by hand |
| Token counts | in `LlmTurnEnd`; no code of the pane reads them | `AgentUsageUpdate`, shown in the row under the composer | — | — |

### I2. What one turn can do, by driver

| Capability | Model in the process | External agent |
| --- | --- | --- |
| Text and reasoning stream into parts | yes ([AssistantTurn.jl:1185](../../../source/platform/assistant/AssistantTurn.jl#L1185)) | yes, through the same function ([ExternalAgentTurn.jl:823](../../../source/platform/assistant/ExternalAgentTurn.jl#L823)) |
| A tool call shows while it runs | no: the form is made when the result comes ([AssistantTurn.jl:1154](../../../source/platform/assistant/AssistantTurn.jl#L1154)) | yes: a form at the first update ([ExternalAgentTurn.jl:870](../../../source/platform/assistant/ExternalAgentTurn.jl#L870)) |
| Runs of deltas joined once per frame | yes ([AgentEventFeed.jl:261](../../../source/platform/assistant/AgentEventFeed.jl#L261)) | no |
| Usage shown | no | yes ([AssistantToWidget.jl:115](../../../source/platform/assistant/AssistantToWidget.jl#L115)) |
| A message into a running turn | waits for the next turn | yes, when the agent can ([ExternalAgentTurn.jl:476](../../../source/platform/assistant/ExternalAgentTurn.jl#L476)) |
| A note when the budget of the turn ran out | yes, `:round_limit` ([AssistantTurn.jl:1069](../../../source/platform/assistant/AssistantTurn.jl#L1069)) | no: `:max_turn_requests` gets no note |
| The conversation in a saved file | no | yes, with a kept session ([AssistantDocument.jl:404](../../../source/platform/assistant/AssistantDocument.jl#L404)) |
| A picture from `take_picture` reaches the model | no: one line of text ([AgentLoop.jl:128](../../../source/kernel/agent/AgentLoop.jl#L128)) | yes ([McpServer.jl:361](../../../source/adapter/mcp/McpServer.jl#L361)) |

### I3. The run of one tool call, in its two places

| Duty | `run_turn!` ([AgentLoop.jl:114](../../../source/kernel/agent/AgentLoop.jl#L114)) | `render_mcp_tools` ([McpServer.jl:285](../../../source/adapter/mcp/McpServer.jl#L285)) |
| --- | --- | --- |
| Bind the starter of the call | line 153 | line 335 |
| A tool that reads no document runs off the editor | on the task of the turn (155) | on the default pool (339) |
| Run on the editor task, with a time limit to start | 159 to 166 | 342 to 349 |
| Catch a throw, record the fault, make the text | 130 to 150 | 313 to 327 |
| Wait for background work | `_wait_for_tool_work` (184) | `_wait_for_mcp_work` (420) |
| Keep the value of an evaluation | any value that is not `nothing` (200) | a `Document` only, for `execute_julia_code` only, and only when the client names the call (410) |
| Decide `is_error` | the words "ERROR" or "Error" in the text (8) | the handler threw, or the evaluation kept an exception (331) |
| A picture | replaced by a line of text (128) | sent as an image (361) |
| A `Task` as the answer | waited for (169) | not handled |
| A tool registered after the start | seen at the next turn (76) | not seen (127) |
| A log of the call | `@info` | the MCP log store (357) |

### I4. The tools, and how a package adds to what a model can do

Ten tools exist. Six come from `register_default_tools!` ([DefaultTools.jl:402](../../../source/kernel/tool/DefaultTools.jl#L402)):
`execute_julia_code`, `search_guides`, `search_api`, `read_function_documentation`, `list_resources`, `read_resource`.
The application adds `undo`, `redo` and `take_picture` ([Application.jl:875](../../../source/platform/application/Application.jl#L875)).
A turn of a model in the process adds `ask_person`.

| What is added | Mechanism | Scope |
| --- | --- | --- |
| A name that a model may write | the line `For the assistant.` in a docstring, read by `collect_marked_api` ([AssistantMark.jl:48](../../../source/kernel/tool/AssistantMark.jl#L48)); 419 marks | reflection |
| The names of a foreign package | `register_assistant_api!` from `__init__` ([AssistantApi.jl:32](../../../source/platform/assistant/AssistantApi.jl#L32)); one caller | a list of the process |
| A sentence about a domain | `register_assistant_api!(Any[]; description)` from `__init__`; eight domains | a list of the process |
| The declared list | `declare_api!` ([ToolSet.jl:39](../../../source/kernel/tool/ToolSet.jl#L39)) | one editor |
| A folder of guides | `register_guide_root!` ([Documentation.jl:32](../../../source/kernel/tool/Documentation.jl#L32)) | a list of the process |
| A tool | `register_tool!` ([ToolSet.jl:85](../../../source/kernel/tool/ToolSet.jl#L85)) | one editor |
| A tool of one turn | the keyword `tools` of `run_turn!` | one turn, model in the process only |

### I5. The conversation

- **Documents.** `ConversationConversation` holds turns. A `ConversationTurn` has a role, parts, a stop reason, times, a
  backend and a model. A `ConversationPart` wraps one content document. The content is plain text while it streams, a
  Markdown or domain document after, a `ConversationThinking`, an `EvaluatorForm` (a tool call or an evaluation), a
  `ConversationPermissionRequest`, a `ConversationQuestionRequest`, a `ConversationSignInRequest`, a
  `ConversationNote` or a picture. `ConversationDraft` is the message that a person composes.
- **Views.** The transcript has three rows in its dispatch table: conversation, turn and part
  ([ConversationToWidget.jl:1288](../../../source/platform/conversation/ConversationToWidget.jl#L1288)). The composer, the
  evaluator and the assistant have their own projections.
- **How a streamed answer enters.** `LlmTextStart` adds a part with an empty plain text. Each delta appends to it.
  `LlmTextStop` parses the text and puts Markdown and domain documents in its place
  ([AssistantTurn.jl:1185](../../../source/platform/assistant/AssistantTurn.jl#L1185)).
- **Save.** A `.pred` file keeps the settings of an assistant. It keeps the conversation only for an external agent
  with a kept session.

### I6. The instructions

| Text | Where | Who reads it |
| --- | --- | --- |
| `DEFAULT_ASSISTANT_SYSTEM` | [AssistantDocument.jl:17](../../../source/platform/assistant/AssistantDocument.jl#L17) | a model, when the host gives no text |
| `ASSISTANT_ANSWER_INSTRUCTIONS` | [AssistantDocument.jl:36](../../../source/platform/assistant/AssistantDocument.jl#L36) | every model of the pane |
| `DEFAULT_AGENT_INSTRUCTIONS` | [AssistantDocument.jl:56](../../../source/platform/assistant/AssistantDocument.jl#L56) | an external agent |
| `_AGENT_SERVER_INSTRUCTIONS` | [ExternalAgentTurn.jl:750](../../../source/platform/assistant/ExternalAgentTurn.jl#L750) | an external agent, from its MCP server |
| `DEFAULT_MCP_INSTRUCTIONS` | [McpServer.jl:6](../../../source/adapter/mcp/McpServer.jl#L6) | an outside client, when the host gives no text |
| `EDITOR_SYSTEM`, `APPLICATION_SYSTEM`, the domain sentences, the index of the names | [Application.jl:398](../../../source/platform/application/Application.jl#L398), [Application.jl:481](../../../source/platform/application/Application.jl#L481) | all three, through `make_assistant_system` |
| The description of `execute_julia_code` | [DefaultTools.jl:123](../../../source/kernel/tool/DefaultTools.jl#L123) | every client, with each request |

All three clients start from `make_assistant_system`. The differences are per driver and small. I raise no finding here.

## Findings

### AI-1 A tool call has two runners, and its result has no type

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** decision 12 of `architecture-decisions.md` (one tool set for the assistant and for an external
  client, so that they do not answer differently); first principle 7 (one mechanism).
- **Today:** A `Tool` is a name, a description, parameters and a handler. The handler answers a `String`, or a `Task`,
  or `BackgroundWork` (code that runs beside the editor), or an `LlmImage` (a picture)
  ([Tool.jl:15](../../../source/kernel/tool/Tool.jl#L15)). Two places run a handler: the loop of the kernel
  ([AgentLoop.jl:114](../../../source/kernel/agent/AgentLoop.jl#L114)) and the MCP server
  ([McpServer.jl:285](../../../source/adapter/mcp/McpServer.jl#L285)). Each one has about 60 lines for the same eleven duties,
  and table I3 shows that they differ in at least six of them. The value of an evaluation and its failure are not in the
  answer. A caller finds them in the `ToolSet`: it compares `find_last_evaluation_result` before and after the call
  ([AgentLoop.jl:200](../../../source/kernel/agent/AgentLoop.jl#L200), [McpServer.jl:330](../../../source/adapter/mcp/McpServer.jl#L330)),
  and it keeps the value under the id of the call for another caller to take
  ([CodeExecution.jl:302](../../../source/kernel/tool/CodeExecution.jl#L302)). Four files decide a failure by the words "ERROR"
  or "Error" in the text ([AgentLoop.jl:8](../../../source/kernel/agent/AgentLoop.jl#L8),
  [AssistantTurn.jl:306](../../../source/platform/assistant/AssistantTurn.jl#L306),
  [ConversationEditor.jl:391](../../../source/platform/conversation/ConversationEditor.jl#L391),
  [Evaluator.jl:637](../../../source/platform/conversation/Evaluator.jl#L637)). The last one holds an `EvaluationResult` with the
  exception in it and still reads the text.
- **Example:**
  ```julia
  # today, in the loop and again in the MCP server
  before = find_last_evaluation_result(set)
  text = tool.handler(target, args)        # String, Task, BackgroundWork or LlmImage
  _keep_evaluated_value!(set, call.id, before)
  is_error = occursin("ERROR", text) || occursin("Error", text)

  # after
  result = run_tool_call!(set, target, call; starter, stop)   # one function for both clients
  result.content     # Vector{LlmContent}: a text, or a picture
  result.value       # the value of an evaluation, or nothing
  result.is_error    # the handler threw, or the code threw
  ```
- **Problem:** The same tool fails for one client and succeeds for the other: `println("Error budget: 3")` is a failure
  in the loop and a success over MCP. A model in the process never sees a picture, because `LlmToolResult` holds a
  `String` ([LlmMessage.jl:78](../../../source/kernel/llm/LlmMessage.jl#L78)), while `EDITOR_SYSTEM` tells every model that
  `take_picture` "shows you what the window draws"
  ([Application.jl:415](../../../source/platform/application/Application.jl#L415)). A tool that a program registers after the
  server started reaches one client only. Each new return kind of a handler, and each new duty of a call, must be
  written twice.
- **Proposal:** Give the result a type, `ToolResult(content, value, is_error)`, where `content` is a vector of
  `LlmContent`. A handler answers it; a handler that answers a `String` is wrapped. One function of the agent layer,
  `run_tool_call!`, does the eleven duties and answers a `ToolResult`. The loop puts it into `AgentToolResult`, and the
  MCP server writes it on the wire and reads the list of tools when the client asks. `LlmToolResult.content` becomes a
  vector of `LlmContent`, so an adapter sends a picture when its provider takes one.
- **What goes away:** About 80 lines of `McpServer.jl`; `_keep_evaluated_value!`, `_keep_evaluated_document!`,
  `_wait_for_tool_work`, `_wait_for_mcp_work`, `_is_error_output` and its three copies, `_PICTURE_RESULT_TEXT`; the
  field `last_results` of `ToolSet` with `find_last_evaluation_result`, `get_last_evaluated_value` and
  `get_last_evaluation_exception`.
- **What stays:** The six default tools and their texts. The fault record of a tool that throws. Background work. The
  value under the id of a call (`keep_tool_call_value!`) stays for one case: an external agent, where the MCP server
  runs the tool and the ACP connection reports the call.
- **Risk and open questions:** The loop today marks a result as failed when its text says "Error" also when nothing
  threw; a model may rely on that. `omnet-julia` reads `AgentToolResult` in a test. The layer of `run_tool_call!` is
  the agent layer, because it needs `run_on_editor_task!`.
- **Related plans:** `kernel-audit/20-agent.md`, findings L20-6 and L20-3. `kernel-audit-fixes.md` closed L20-6 by a
  patch of both copies and says: "The shared exported helper of the report is left out: it needs a new public name and
  a choice of layer." This finding is that open choice, and the two copies grew from one `catch` arm to eleven duties
  since.
- **Check:** confirmed-with-corrections. I opened `AgentLoop.jl` 114 to 224, `McpServer.jl` 268 to 437, `Tool.jl`,
  `LlmMessage.jl:78`, `CodeExecution.jl` and the four text checks; every row of table I3 holds, and decision 12 names
  exactly this risk. Three differences have a stated reason, and the one runner must keep them as arguments or as an
  owner's choice. (1) The generous text check of the loop is on purpose (the comment at `AgentLoop.jl:3` and "Accepted
  before" in `kernel-audit/20-agent.md`): the precise rule of the MCP path changes what a model in the process is told,
  so the owner chooses the rule. (2) The MCP server lists its tools once because the protocol library lists its own
  vector and calls no code of the package (`mcp.md`, the limit "The server renders the tool set once"); "reads the list
  when the client asks" needs a change of the library or a second registration at `register_tool!`. (3) A tool that
  reads no document goes to the default pool in the MCP server because HTTP serves a request on the thread of the
  editor loop; the turn already runs off that thread. The picture for a model in the process is a stated limit
  (`Tool.jl:22`, `agent.md`), and to lift it widens `LlmToolResult` and both chat adapters: it is the one part of the
  proposal that adds a capability. No feature is lost when `stop`, the running work of the server and the MCP log stay
  with the caller.

### AI-2 A turn has two drivers that share the conversation and little else

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** first principle 7 (generic before special; a missing case gets its row); first principle 3 (one way).
- **Today:** `_launch_agent_turn!` chooses between two runners by the literal `:acp`
  ([AssistantTurn.jl:339](../../../source/platform/assistant/AssistantTurn.jl#L339)): `_run_agent_loop!` for a model in the
  process ([AssistantTurn.jl:872](../../../source/platform/assistant/AssistantTurn.jl#L872)) and `_run_external_agent_turn!`
  for an agent ([ExternalAgentTurn.jl:124](../../../source/platform/assistant/ExternalAgentTurn.jl#L124)). The kernel has two
  events for a tool call, both below `AgentEvent`: `AgentToolResult` from the loop, and `AgentToolCallUpdate` from a
  connection. The platform has two functions that turn them into a form
  ([AssistantTurn.jl:1154](../../../source/platform/assistant/AssistantTurn.jl#L1154),
  [ExternalAgentTurn.jl:870](../../../source/platform/assistant/ExternalAgentTurn.jl#L870)). The feed of the window, which
  applies the events on the editor task, has two kinds of source, and six places treat a `_TurnEventSource` apart:
  three functions have a second method for it, one function exists only for it, and two loops skip it
  ([AgentEventFeed.jl:686](../../../source/platform/assistant/AgentEventFeed.jl#L686) to line 713, and lines 734 and 775). Nine
  lines outside the ACP adapter compare the backend with `:acp`, and the platform names the kind in the call
  `make_agent_connection(:acp)` ([ExternalAgentTurn.jl:245](../../../source/platform/assistant/ExternalAgentTurn.jl#L245)),
  though the kernel offers `get_agent_connection_names()`. Of the 32 fields of the `Assistant` document, 13 are
  `agent_…` ([AssistantDocument.jl:195](../../../source/platform/assistant/AssistantDocument.jl#L195)). A table of the process,
  `_TURN_WORKS`, ties a running turn to its work ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)).
- **Example:**
  ```julia
  # today
  is_external ? _run_external_agent_turn!(editor, a; control) : _run_agent_loop!(editor, a; control)
  a.backend === :acp ? _cancel_external_agent_turn!(a) : _decline_open_questions!(a)

  # after
  driver = make_turn_driver(a)     # a model, or a connection of any loaded kind
  run_turn!(driver, editor, a)     # one runner; every event goes to apply_agent_event!
  cancel_turn!(driver, a)
  ```
- **Problem:** Table I2 shows a gap on each side. A tool call of a model in the process shows only when it has ended,
  so a long call shows nothing. The token counts of a model are counted and not shown. The deltas of an agent are not
  joined per frame. A second kind of connection can not be chosen. Each new capability of a turn must be written
  twice, or it works for one driver.
- **Proposal:** Keep both loops, and give them one shape toward the platform. The loop of the kernel reports a tool
  call as `AgentToolCallUpdate`s (pending with its input, in progress, completed or failed with its output), the cost
  of a round as an `AgentUsageUpdate`, and the question of `ask_person` as an `AgentQuestionRequest`. The platform
  then has one applier (`apply_agent_event!`), one state of a turn, and one kind of feed source, which also holds the
  work of the turn. A small driver seam in the platform holds what differs: start, send, cancel, steer and close. The
  backend symbol picks the driver through the two method tables of the kernel.
- **What goes away:** `AgentToolResult`; `_handle_agent_event!` for it; `_TurnEventSource` and its six methods;
  `_decline_open_questions!`; the hand-made reply of `_make_ask_person_tool`; `_TURN_WORKS`; the nine `:acp` tests.
  Roughly 200 lines, and one of every two code paths of table I2.
- **What stays:** A model in the process still reads its messages from the conversation at each round (`messages` is
  a callback, a decision of `agent.md`). An external agent still holds its history, with resume, fork and sign-in.
  The budget of rounds, the wakes and `ask_person` stay.
- **Risk and open questions:** `AgentToolCallUpdate` is documented as an event "of an external agent"; its meaning
  widens. Tests of two repositories read `AgentToolResult`. Should the fields `agent_options`, `agent_usage`,
  `agent_title` move from the assistant into a session document (see AI-4)?
- **Related plans:** `plan/done/an-answer-streams-in-without-holding-the-window.md` (done) added `_TurnEventSource` as
  a second source kind. No pending plan covers the join.
- **Check:** confirmed-with-corrections. I opened `AssistantTurn.jl` 330 to 460 and 866 to 1075,
  `ExternalAgentTurn.jl` 810 to 960, `AgentEventFeed.jl` 20 to 290 and 686 to 775, and counted again: nine lines
  compare the backend with `:acp`, the `Assistant` has 32 fields and 13 are `agent_…`, and six places treat
  `_TurnEventSource` apart. Text and reasoning already share one handler, and the two form builders share
  `_make_tool_result_document`. Corrections: (1) only three of the nine `:acp` lines choose a code path of a turn
  (lines 339, 399 and 450 of `AssistantTurn.jl`); the other six ask whether the assistant has a session (the save, the
  row of controls, the settings) and become a question to the driver, they do not go away. (2) `ask_person` is a tool
  of the platform, so the platform posts its question as an event; the loop of the kernel knows no such tool. (3) The
  usage of a model in the pane is a new capability, not a join. The proposal must keep that the end of a text block,
  the end of a round and the result of a tool apply in a call that waits (`_run_turn_call!` with no time limit), so the
  next round reads a conversation that holds them. No pending plan covers it; open question L20-9 of
  `kernel-audit-fixes.md` ("does `AgentEvent` stay") is answered by this finding and should be closed with it.

### AI-3 The transcript draws seven kinds of part inside one projection

- **Kind:** special-case · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 2 (projections compose by dispatch on type); PAR-DELEGATE-ONE-LEVEL;
  first principle 7.
- **Today:** The dispatch table of the transcript has three rows: conversation, turn and part
  ([ConversationToWidget.jl:1288](../../../source/platform/conversation/ConversationToWidget.jl#L1288)). The printer of a part,
  `ConversationPartToWidget`, chooses the body by a chain of seven `isa` tests on the content
  ([ConversationToWidget.jl:423](../../../source/platform/conversation/ConversationToWidget.jl#L423)), then three more for the
  selection (lines 440 to 442), and its two mappers test the kind again (lines 1011 and 1032). The file holds 27 such
  tests (corrected from 24). `EvaluatorForm`, the document of a tool call, has a projection of its own for the evaluator
  ([EvaluatorToWidget.jl:21](../../../source/platform/conversation/EvaluatorToWidget.jl#L21)) and a second drawing inside the
  part ([ConversationToWidget.jl:779](../../../source/platform/conversation/ConversationToWidget.jl#L779)); the map of its two
  sections is written twice ([EvaluatorToWidget.jl:35](../../../source/platform/conversation/EvaluatorToWidget.jl#L35),
  [ConversationToWidget.jl:1005](../../../source/platform/conversation/ConversationToWidget.jl#L1005)).
- **Example:**
  ```julia
  # today, in print_document(::ConversationPartToWidget, …)
  card = content isa EvaluatorForm                 ? _eval_card(projection, content, folds) :
         content isa ConversationThinking          ? _thinking_card(projection, content, text) :
         content isa ConversationPermissionRequest ? _permission_card(projection, content) : …

  # after
  TypeDispatchingProjection(
      ConversationPart             => ConversationPartToWidget(…),      # the fold and the frame only
      EvaluatorForm                => EvaluatorFormToWidgetCard(…),
      ConversationThinking         => ConversationThinkingToWidget(…),
      ConversationQuestionRequest  => ConversationQuestionToWidget(…), …)
  ```
- **Problem:** A new kind of part needs an arm in the printer, in the forward map, in the backward map and in the
  selection wiring of one projection. A card of a question or of a sign-in can not be shown outside a transcript,
  because it has no projection of its own. The same switch on the kind repeats in `build_messages`,
  `format_conversation` and the overview (11 tests in `AssistantTurn.jl`).
- **Proposal:** The part prints its fold and its frame, and prints its content as a child through the recursion. Each
  kind of content gets its row in the dispatch table, with its own IO map and its own mappers. The part maps a
  reference by the IO map of its child.
- **What goes away:** The arms of the chain for the kinds that the conversation owns, the three selection arms and
  the per-kind branches of the two mappers of the part. (Corrected: both drawings of `EvaluatorForm` stay, see the
  check.)
- **What stays:** Every card as it looks today; the fold of a part; the rule that a finished turn folds its work.
- **Risk and open questions:** The frame of a part depends on the kind (a card for code, none for prose). The content
  projection can say it through its IO map, or the part can ask a function of the content type.
- **Related plans:** `conversation-flat-transcript.md` (pending; its header says not started, its text says items 3
  and 4 are not done) changes the chrome of the same projection. `an-assistant-shows-its-turns-in-the-tree.md` (in
  progress) adds tree labels per kind of content, which is one more switch on the kind.
- **Check:** confirmed-with-corrections. I opened `ConversationToWidget.jl` 395 to 470, 770 to 800, 995 to 1045 and
  1275 to 1309, and `EvaluatorToWidget.jl` 1 to 75. The chain has seven arms, three selection arms follow, and both
  mappers test the kind; `AssistantTurn.jl` holds 11 such tests. Corrections: (1) the two drawings of `EvaluatorForm`
  are two looks, not one job done twice: the evaluator draws a `>` row and a `=` row that a person edits, and the
  transcript draws a card with a header and two sections that fold. Both stay, so no drawing goes away, and
  `_FORM_ROWS` and `_PART_SECTIONS` map two different layouts. The composer already shares `_eval_sections` with the
  transcript. (2) Only the kinds that the conversation owns can get a row (the thinking, the three requests, the note,
  the evaluation). Code is known by its natural format (`_is_code`) and a picture is an `ImageFile` of another slice,
  so the part still decides the frame of a foreign content, by a function of the content type and not by a row.
  (3) `transcript.md` ("What a part draws") and stage 3 of `conversation-flat-transcript.md` chose that the part gives
  the chrome by the kind of its content; the proposal keeps that rule and changes only how it is written. The proposal
  loses no card. It also removes a projection that the part builds at each print
  (`PrimitiveStringToTextBlock(; style = …)` at line 463), which the owner's rule on projections forbids.

### AI-4 The session of an agent has one shape at the root and another for a subagent

- **Kind:** special-case · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** first principle 1 (data is a tree of typed documents); first principle 2 (recursion).
- **Today:** `AgentWork` is the document of the work of a session or of a subagent: title, state, stop reason, token
  count, conversation, plans, background tasks, subagents, notices, processes
  ([AgentWorkDocument.jl:57](../../../source/platform/assistant/AgentWorkDocument.jl#L57)). At the root its docstring says that
  the conversation "stays empty, and so do the title, the state and the usage, which the assistant holds"
  ([AgentWorkDocument.jl:41](../../../source/platform/assistant/AgentWorkDocument.jl#L41)). So the root keeps these in fields
  of `Assistant` (`conversation`, `agent_title`, `agent_usage`, `status`), and a subagent keeps them in `AgentWork`.
  The feed has one function for an event of the root and one for an event of a subagent, with the same branches
  ([AgentEventFeed.jl:40](../../../source/platform/assistant/AgentEventFeed.jl#L40),
  [AgentEventFeed.jl:350](../../../source/platform/assistant/AgentEventFeed.jl#L350)), and two sets of functions that find and
  end the open turn (lines 76 and 118, lines 374 and 385). The root has one page projection, `AssistantWorkToWidget`
  ([AssistantWorkToWidget.jl:30](../../../source/platform/assistant/AssistantWorkToWidget.jl#L30)), and a subagent another,
  `AgentWorkToWidget` ([AgentWorkToWidget.jl:23](../../../source/platform/assistant/AgentWorkToWidget.jl#L23)).
- **Example:**
  ```julia
  # today
  a.agent_title;  a.agent_usage;      a.conversation;      a.agent_work.subagents   # the root
  child.title;    child.token_count;  child.conversation;  child.subagents          # a subagent

  # after: the root is a node of the same type
  a.session.title;  a.session.usage;  a.session.conversation;  a.session.subagents
  child.title;      child.usage;      child.conversation;      child.subagents
  ```
- **Problem:** A capability of the root does not reach a subagent, and the reverse. The page of a subagent and the
  page of the root are written apart. A subagent of a subagent works only because the second function calls itself.
- **Proposal:** One document type for a session node, used at the root and at each subagent. The assistant holds its
  settings, its draft and the root node. One function applies an event to the node that the event names, at any
  depth. One page projection shows a node.
- **What goes away:** `_apply_subagent_event!`, `_find_subagent_turn!`, `_end_subagent_turn!` or their root twins; one
  of the two page projections (243 and 306 lines); six fields of `Assistant`.
- **What stays:** The transcript of the assistant in its pane; the work page; the tree of subagents; the tasks of the
  agent in the task list.
- **Risk and open questions:** The path `Assistant.conversation` is in the maps of both views of the assistant and in
  saved files. A model in the process has no subagents; its root node has an empty list.
- **Related plans:** `an-assistant-shows-its-turns-in-the-tree.md` (in progress) gives both shapes the same children
  in the tree, by two methods.
- **Check:** weakened. I opened `AgentWorkDocument.jl` 20 to 80, `AgentEventFeed.jl` 40 to 130 and 292 to 428, and
  the heads of the two page projections. The two shapes are real, and the docstring of `AgentWork` states them as
  the design. Three statements are too strong. (1) "The same branches": the branches that are the same already call
  shared functions (`_apply_agent_work_update!`, `_handle_external_agent_event!`, `_open_agent_turn!`,
  `_end_agent_turn_state!`). What differs follows the protocol: the root gets its options, usage, title and commands as
  events of the session, and a subagent gets them as fields of its update; the root has a turn of a prompt, a turn that
  the agent starts by itself and the split of a steered turn, and a subagent has one open turn. (2) The two pages do
  not show the same thing: the page of the root shows the job, "Now", the tree of the work, the processes and the
  notices, and no transcript; the page of a subagent shows a header with Cancel, the transcript and links. They share
  `_make_page_column` and `_follow_page_column!`. One page for both needs a switch on root or child, or it loses
  cards. (3) The two halves have different lives: the conversation of the root is the source of the messages of a
  model and goes into a saved file, and `AgentWork` is live state that no file keeps and that a new session replaces
  as a whole (`ResetConversationOperation`). One node type must split these rules inside the node. What is left of
  the finding: fields of `AgentWork` that stay empty at the root, and two methods for the children in the tree.

### AI-5 An evaluation becomes a form in five places

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 7 (one mechanism); first principle 3 (a person and the assistant do the same).
- **Today:** `EvaluatorForm` is the document of a piece of code with its result, and of any tool call. Five places
  build one from an answer: the Julia submit of the assistant
  ([AssistantTurn.jl:293](../../../source/platform/assistant/AssistantTurn.jl#L293)), Alt+Enter in the composer
  ([ConversationEditor.jl:378](../../../source/platform/conversation/ConversationEditor.jl#L378)), the evaluator
  ([Evaluator.jl:634](../../../source/platform/conversation/Evaluator.jl#L634)), a tool call of a model
  ([AssistantTurn.jl:1154](../../../source/platform/assistant/AssistantTurn.jl#L1154)) and a tool call of an agent
  ([ExternalAgentTurn.jl:870](../../../source/platform/assistant/ExternalAgentTurn.jl#L870)). Their rules differ: only the
  evaluator hides a value after `;` and shows nothing for `nothing`; the composer and the evaluator strip the end of
  the text, and the Julia submit of the assistant does not (corrected: not only the composer);
  only the two tool paths make a Markdown result from the media type of the tool. Eleven lines in five files outside
  the tool layer compare a tool name with the literal `"execute_julia_code"` to know that a call holds code.
- **Example:**
  ```julia
  # today (one of five)
  output = execute_julia_code!(set, editor, code; describe_value = describe_value_for_person)
  is_error = occursin("ERROR", output) || occursin("Error", output)
  value = get_last_evaluated_value(set)
  result = value isa Document ? value : make_evaluator_result_text(output)
  EvaluatorForm(_eval_form_doc(code); source = code, result, is_error)

  # after
  result = run_julia_code!(set, editor, code; describe_value = describe_value_for_person)
  make_evaluation_form(code, result)      # one function, beside EvaluatorForm
  ```
- **Problem:** The same line of code gives a different form in the composer and in the evaluator of the same window.
  A fix of one rule reaches one of five places.
- **Proposal:** One function beside `EvaluatorForm` makes or fills a form from a call and its result (the
  `EvaluationResult` of today, the `ToolResult` of AI-1). A `Tool` says which parameter holds code and in which
  format, as it says the media type of its result today, so no caller compares a name.
- **What goes away:** Four of the five bodies, about 80 lines; the eleven name tests.
- **What stays:** The two namespaces: the evaluator runs in a namespace with no declared limit, and the composer runs
  in the namespace of the model. That difference has a stated reason
  ([Evaluator.jl:511](../../../source/platform/conversation/Evaluator.jl#L511)).
- **Risk and open questions:** Should Alt+Enter in the composer hide a value after `;`? Today it does not.
- **Related plans:** `kernel-audit-fixes.md` notes under L20-3 that the assistant keeps its own copy of the text
  check and that this half is in no plan.
- **Check:** confirmed-with-corrections. I opened the five places and counted again: 11 lines in 5 files outside the
  tool layer compare a name with `"execute_julia_code"`. Correction: the evaluator strips the end of the text too
  (`Evaluator.jl:641`), so the three paths of a person differ in the `;` rule, the `nothing` rule and one strip. The
  two tool paths already share `_make_tool_result_document`; they differ because a model gives one result and an
  agent gives updates, which is AI-2. After AI-1, AI-2 and AI-6 three builders are left (the composer, the evaluator,
  a tool call), so part of the value is counted in those findings. Whether Alt+Enter hides a value after `;` is a
  change that a person sees, and the owner decides it. A parameter of a `Tool` that says "this is code of format X"
  is a new field of a kernel type; it is generic, and it keeps "a `Tool` carries no wire format".

### AI-6 A person sends a message by the draft, and a test sends it by another field

- **Kind:** redundant · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 3 (a person, the assistant and a test make the same operations).
- **Today:** The `Assistant` has two places for the next message: `input`, a plain text
  ([AssistantDocument.jl:197](../../../source/platform/assistant/AssistantDocument.jl#L197)), and `draft`, the document that
  the composer edits. No view prints `input`. Three operations work on it: `SubmitProseOperation`,
  `SubmitJuliaOperation` and `ClearInputOperation`
  ([AssistantTurn.jl:405](../../../source/platform/assistant/AssistantTurn.jl#L405), lines 293 and 271). A person sends with
  `SubmitDraftTurnOperation` ([AssistantTurn.jl:430](../../../source/platform/assistant/AssistantTurn.jl#L430)). The tests use
  `SubmitProseOperation` 37 times in 14 files (corrected from 35 in 12) and `SubmitDraftTurnOperation` 11 times in
  3 files; the rehearsal tool
  uses the first ([rehearsal.jl:265](../../../tool/assistant/rehearsal.jl#L265)). `ClearInputOperation` has no caller in any
  test or tool, and `SubmitJuliaOperation` has one test file (`test/adapter/mcp/McpTest.jl`). A fourth sender, `send_go_on!`, pushes a turn with no operation
  ([AssistantTurn.jl:1098](../../../source/platform/assistant/AssistantTurn.jl#L1098)).
- **Example:**
  ```julia
  # today, in a test
  a.input.value = "Probe it."
  evaluate_operation(editor, SubmitProseOperation(a))
  # a person: Return in the composer makes SubmitDraftTurnOperation(a), which reads a.draft

  # after
  evaluate_operation(editor, SubmitTurnOperation(a, "Probe it."))
  # Return in the composer makes the same operation with the parts of the draft
  ```
- **Problem:** Most tests of a turn do not run the operation that a person makes, so the path of pictures, of a
  message into a running turn and of the reset of the draft has little cover. The document carries a field that no
  person can see or fill.
- **Proposal:** One operation adds a user turn from given parts and starts or steers a turn. The composer makes it
  from the draft, `send_go_on!` makes it with its fixed text, and a test makes it with a text. The field `input` and
  its three operations go.
- **What goes away:** `input`, `SubmitProseOperation`, `SubmitJuliaOperation`, `ClearInputOperation`, `_set_input!`;
  about 70 lines, and one of the five form builders of AI-5.
- **What stays:** Return and Alt+Enter in the composer; the evaluation of Julia by `EvaluateDraftTurnOperation`.
- **Risk and open questions:** About 40 test lines and three files of `omnet-julia` name the old operations.
- **Related plans:** none pending. `documentation-rewrite-survey.md` lists `input` and `SubmitJuliaOperation` as the
  surface of the assistant.
- **Check:** confirmed-with-corrections; the value goes down to low. I opened `AssistantTurn.jl` 36 to 70, 262 to
  312, 396 to 452 and 1085 to 1107 and counted the tests again (counts corrected above). `assistant.md` already lists
  the field and its operations under its limits ("no printer shows `input` and no reader makes these operations"),
  and no plan removes them. The senders are less apart than the text says: all four end in the one function
  `_send_user_turn!`, with `_make_instant_turn` and `_raise_wakes_left!`, so what repeats is four openings of five
  lines. A test that makes the new operation with a text still does not run the path of the draft (its finalize, its
  pictures, its reset); only a test that fills the draft does. The proposal loses nothing that a person can reach.
  The next feature is not simpler after it: it removes about 70 dead lines and one field.

### AI-7 The assistant has two views with two sets of maps, and the card has no controls

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 8 (reuse an existing view); first principle 7.
- **Today:** `AssistantToWidgetSplitPane` shows the transcript over the composer and a row of controls: the stop
  button, the picture button, the count of wakes, and for an agent its options and its usage
  ([AssistantToWidget.jl:77](../../../source/platform/assistant/AssistantToWidget.jl#L77)). `AssistantToWidgetCard` shows the
  same two panes in a card of a fixed height, with no row
  ([AssistantToWidget.jl:146](../../../source/platform/assistant/AssistantToWidget.jl#L146)). The first writes its two maps
  with the reference macro (lines 247 and 256). The second builds a prefix of six steps by hand and sets five path
  computations with counted depths (lines 164 to 186 and 196). The readers differ too: the split pane takes the
  submit operation of the composer ([AssistantTurn.jl:1357](../../../source/platform/assistant/AssistantTurn.jl#L1357)), and
  the card reads raw key events ([AssistantTurn.jl:1381](../../../source/platform/assistant/AssistantTurn.jl#L1381)).
- **Example:**
  ```julia
  # today
  Assistant => AssistantToWidgetSplitPane(theme)                                    # the application
  Assistant => AssistantToWidgetCard(; transcript_height = 460, cell_height = 120)  # a page

  # after: one printer of the three parts, in a container that the caller chooses
  Assistant => AssistantToWidget(theme; container = :split)
  Assistant => AssistantToWidget(theme; container = :card, transcript_height = 460, cell_height = 120)
  ```
- **Problem:** An assistant in a page has no stop button, no picture button, no options of its agent and no usage
  line. A change of the layout of one view must be made again in the other, with other code for the paths.
- **Proposal:** One projection prints the transcript, the composer and the row of controls, and maps `conversation`
  and `draft` once. The container (a split pane that fills, or a card of fixed heights) is a parameter, or a layout
  step around the same three children.
- **What goes away:** One printer, one pair of mappers and three reader methods; about 120 lines.
- **What stays:** Both looks; the fixed height of the card, which a page needs.
- **Risk and open questions:** `omnet-julia` uses the card in its notebook page.
- **Related plans:** `conversation-flat-transcript.md` (pending) names the "hand-counted container depths" of the card
  as the reason that two of its items are not done.
- **Check:** confirmed. I opened `AssistantToWidget.jl` 60 to 265 and `AssistantTurn.jl` 1346 to 1406. Both views
  hold the same two scroll panes; the split pane maps them with the reference macro and the card with a prefix of six
  steps and counted depths, and only the split pane has the row. No document gives a reason for a card without the
  row. Two small corrections: Escape in the card stops a running turn (`AssistantTurn.jl:1387`), so the card lacks the
  stop button, not the stop; and the card has four reader methods, not three (the fourth is at
  `AssistantToWidget.jl:237`). The example `container = :card` is a flag on one projection; the other form of the
  proposal, a layout step around the same three children, fits "generic before special" better. The fixed heights of
  the card stay, and `omnet-julia` (`Notebook.jl`) and three test files name the card.

### AI-8 The search models reach a tool set in three ways, one of them as a side effect of a turn

- **Kind:** partial-feature · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 7 (one mechanism); first principle 6 (state belongs to an editor, set once).
- **Today:** A `ToolSet` holds two models for its searches: a `MeaningModel`, which turns a text into a vector, and a
  `RelevanceModel`, a classifier. The meaning model is a capability of a chat backend: three generics on `Llm` and the
  binder `bind_meaning_model!` ([Llm.jl:20](../../../source/kernel/llm/Llm.jl#L20)). The turn of a model in the process binds
  it at each turn ([AssistantTurn.jl:902](../../../source/platform/assistant/AssistantTurn.jl#L902)). The application binds it
  once more, only with `--mcp`, by building a chat backend of the kind of the assistant
  ([Application.jl:920](../../../source/platform/application/Application.jl#L920)); for `:acp` that call throws and the
  application warns. The relevance model comes from a plain factory of its adapter
  ([OpenRouterRelevance.jl:93](../../../source/adapter/openrouter/OpenRouterRelevance.jl#L93)), and no code under `source/`
  calls `set_relevance_model!`.
- **Example:**
  ```julia
  # today
  bind_meaning_model!(editor.tools, make_llm(:ollama))                    # needs a chat backend
  set_relevance_model!(editor.tools, make_openrouter_relevance_model())   # by hand; no setting names it

  # after
  set_meaning_model!(editor.tools, make_meaning_model(:ollama; model = "nomic-embed-text"))
  set_relevance_model!(editor.tools, make_relevance_model(:openrouter))
  # the settings of the window choose both, for every backend
  ```
- **Problem:** A window whose assistant is an external agent gets no meaning model, so its searches by description
  rank by words. A window with Claude as its model gets none either, because that
  backend has no meaning model. The relevance model has no path from a setting to a window.
- **Proposal:** Both search models come from a factory by a symbol, as a chat backend does, and the host sets them
  once from its settings. `Llm` loses its three meaning generics and `bind_meaning_model!`.
- **What goes away:** `has_meaning_model`, `get_meaning_model_name`, `compute_meaning_vectors` on `Llm`,
  `bind_meaning_model!`, the bind in each turn and the bind of `start_application!`.
- **What stays:** The vectors, their files and the ranking; Ollama as the source of the meaning model.
- **Risk and open questions:** A new setting for the meaning model. `omnet-julia` binds by hand in
  `CampaignWindow.jl`.
- **Related plans:** `the-relevance-model-reads-code-and-call-sites.md` (deferred) changes what the relevance model
  reads, not how it is bound. Audit finding L18-24 names the cost of the bind in each turn.
- **Check:** confirmed-with-corrections. I opened `Llm.jl`, `AssistantTurn.jl:902`, `Application.jl` 918 to 925,
  `OpenRouterRelevance.jl` and the documents. The half on the meaning model holds: it is bound in each turn of a model
  in the process and once more with `--mcp`, and a window with an agent or with Claude gets none. This binding is the
  written design (`plan/done/three-kinds-of-search.md`, "The connection"; `agent.md`: "The assistant binds at every
  turn, and a window that serves MCP binds when it starts"), so the proposal changes a design, it does not repair a
  slip. The half on the relevance model is a stated choice and no gap: `openrouter.md` says "Nothing binds the model
  by itself. A window, or a person at the REPL, asks for it", for a paid service with an address marked alpha. A
  setting for it is a new feature. What the proposal must keep: an Ollama window gets its meaning model with no
  setting, as today, and `FakeLlm` keeps a meaning model for the tests that run offline. `omnet-julia` binds in
  `CampaignWindow.jl:365`.

### AI-9 The provider adapters repeat the stream skeleton, the schema of a tool and the JSON conversion

- **Kind:** repeated-by-hand · **Value:** low · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 7; the settled decision that a third-party dependency comes from an adapter package.
- **Today:** The two chat adapters each hold the same 40 lines around `HTTP.open`: write the body, check the status,
  read chunks with a guard for the end, close the connection when a callback throws, and throw when no terminal event
  came ([AnthropicLlm.jl:345](../../../source/adapter/anthropic/AnthropicLlm.jl#L345),
  [OllamaLlm.jl:387](../../../source/adapter/ollama/OllamaLlm.jl#L387)). Each renders the parameters of a `Tool` into the same
  JSON Schema object and differs only in the envelope
  ([AnthropicLlm.jl:129](../../../source/adapter/anthropic/AnthropicLlm.jl#L129),
  [OllamaLlm.jl:99](../../../source/adapter/ollama/OllamaLlm.jl#L99)); the MCP adapter walks the same parameters a third time
  ([McpServer.jl:274](../../../source/adapter/mcp/McpServer.jl#L274)). Each holds the same three lines that turn a JSON value
  into a `Dict` (lines 394 and 238). The kernel reads the loaded kinds from a method table with one loop written
  twice ([Llm.jl:33](../../../source/kernel/llm/Llm.jl#L33), [AgentDefaults.jl:32](../../../source/kernel/agent/AgentDefaults.jl#L32)).
- **Example:**
  ```julia
  # today, in each adapter
  HTTP.open("POST", url, headers; status_exception = false, decompress = false) do io
      …                                   # 40 lines
  end

  # after
  stream_http_records(url, headers, body; separator = "\n\n") do record
      translate(record)                   # what differs per provider
  end
  ```
- **Problem:** A third chat provider repeats about 100 lines, and a fix of the read loop must be made in each adapter.
- **Proposal:** A small support package of the adapters holds the HTTP stream and the JSON conversion. The tool layer
  gives the parameters of a `Tool` as one plain `Dict` in the shape of JSON Schema, which needs no JSON parser. The
  kind collector moves to the lowest layer that both callers see.
- **What goes away:** About 100 lines of the two adapters, and one of the two collectors.
- **What stays:** Each adapter's translation of its own stream into `LlmEvent`s, which is what really differs.
- **Risk and open questions:** A `Dict` in the shape of JSON Schema in the kernel is close to the line "a `Tool`
  carries no wire format" of `agent.md`. A shared support package is a new package of the adapter layer.
- **Related plans:** none.
- **Check:** weakened; the value stays low. I opened both chat adapters at the cited lines, `McpServer.jl:274`,
  `Llm.jl:33` and `AgentDefaults.jl:32`. The facts hold for the two chat adapters: the same skeleton around
  `HTTP.open`, the same inner schema object and the same three lines of `_native`. Three parts of the proposal are
  weaker than written. (1) The MCP adapter does not render the same thing a third time: it fills the `ToolParameter`
  of its library, so a `Dict` in the shape of JSON Schema does not serve it. (2) That `Dict` in the tool layer goes
  against a written choice: the docstring of `Tool` and `agent.md` say that a `Tool` carries no wire format and that
  the rendering is the job of the adapter. (3) A support package for two adapters is a new package for about 50
  shared lines, and the third user, the OpenRouter adapter, makes a plain `HTTP.post` with no stream. The part that
  holds with no cost is the collector of the kinds: `get_llm_backend_names` repeats the body of `_collect_val_kinds`,
  and the helper can move to the llm layer, which the agent layer sees.

### AI-10 State of one editor sits in tables of the process, beside the slot that an editor has for it

- **Kind:** wrong-place · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** the settled decision that no registry and no session document is global to the process;
  PAR-PER-EDITOR-STATE.
- **Today:** An editor has a slot for the documents of its session, `get_session_document!`
  ([Editor.jl:262](../../../source/kernel/editor/Editor.jl#L262)), and the assistant list uses it. Four values of this area do
  not. The MCP server writes every call into one store of the process
  ([McpLogStore.jl:114](../../../source/platform/mcplog/McpLogStore.jl#L114),
  [McpServer.jl:357](../../../source/adapter/mcp/McpServer.jl#L357)), though the server holds its editor; the docstring of the
  feed says that two editors each get every call. `_TURN_WORKS` maps a running turn to its work
  ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)). `_EVALUATOR_SESSIONS` maps a tool set to
  the namespace of its evaluators ([Evaluator.jl:537](../../../source/platform/conversation/Evaluator.jl#L537)).
  `_ASSISTANT_API` and `_ASSISTANT_API_DESCRIPTIONS` are lists that packages fill from `__init__`
  ([AssistantApi.jl:6](../../../source/platform/assistant/AssistantApi.jl#L6)).
- **Example:**
  ```julia
  # today
  record_mcp_call!(get_session_mcp_log_store(); method = "tools/call", name = tool.name, …)

  # after
  record_mcp_call!(get_mcp_log_store(mcp.editor); method = "tools/call", name = tool.name, …)
  ```
- **Problem:** With two windows that each serve MCP on a port of their own, the MCP log of each window shows the
  calls of both. The guide says "One server, one editor". The two tables need a lock and a rule for their removal that
  a value on the editor would not need.
- **Proposal:** The store of the MCP log, the work of a running turn and the session of the evaluators live in the
  session slot of their editor. The sentence of a domain moves into the docstring of its module, as
  `plan/done/the-assistant-finds-its-names-by-reflection.md` designed it in its section 4.2. (Corrected: the plan did
  not leave it unbuilt by chance. Its record of the work says "`register_assistant_api!` keeps that job and the
  sentence of each domain", so this part reopens a recorded choice.)
- **What goes away:** Three global tables with their locks; the eight `__init__` calls that give a sentence.
- **What stays:** The MCP log tab; the names of `DataFrames`, which no mark can reach, keep one declaration.
- **Risk and open questions:** The store of the MCP log is written from the task of the server, so it must stay a
  plain struct with a lock, not a document. The registries of the domains (`register_natural_syntax!`,
  `register_file_document_type!`) have the same shape and belong to another area.
- **Related plans:** `kernel-audit/21-feed.md` L21-1 and `kernel-audit/18-tool.md` L18-13 name the shared feed
  documents and the guide roots; neither names these four.
- **Check:** confirmed-with-corrections; the value stays low. I opened `Editor.jl` 250 to 263, `McpLogStore.jl`,
  `McpLogFeed.jl`, `AssistantTurn.jl` 125 to 140, `Evaluator.jl` 510 to 560, `AssistantApi.jl` and
  PAR-PER-EDITOR-STATE. Only one of the four values lets one editor see the state of another: the store of the MCP
  log, whose feed says that two editors each get every call. The other three do not. `_TURN_WORKS` is keyed by the
  control of one turn, and its comment gives the reason for its place ("the work holds the editor, and no document
  holds an editor"). `_EVALUATOR_SESSIONS` is a weak table keyed by the tool set of one editor. `_ASSISTANT_API` and
  the sentences are not state of one editor at all: the loaded packages fill them, so they are the same for every
  editor, which is the kind of value that the rule accepts; the title of the finding is wrong for them. The slot
  `session_documents` is an `IdDict{Type,Any}`, so it can hold a plain store or a table of works, but its docstring
  says "documents", and the proposal must say that it widens the slot. The 8 calls that give a sentence and the 1
  call that gives names are counted right. The proposal loses nothing; the part on the sentences goes against the
  choice that the reflection plan recorded (see the correction above).

## Covered by plans

- `kernel-audit/20-agent.md` L20-4 and `18-tool.md` L18-24: each turn registers the default tools again. Open.
- `kernel-audit-fixes.md`, group 6: the time bounds of a round and of a tool call, and the cancel of a turn.
- `kernel-audit/18-tool.md` L18-13: the guide roots are a list of the process.
- `conversation-flat-transcript.md` (pending): the nested cards and the chrome of a turn and of a part.
- `an-assistant-shows-its-turns-in-the-tree.md` (in progress, steps 3 to 5 open): turns and parts as tree nodes.
- `assistant-api-consolidation.md` (pending, stale): the verbs make, view and place. Its stages are unchecked, but
  `open_pane!`, `focus_pane!`, `show_pane!` and `describe_document` are on main.
- `any-acp-agent-gets-the-instructions-and-a-sign-in.md` (steps 1 and 2 done, step 3 waits): agents that are not Claude.
- `an-assistant-carries-a-long-study-to-its-end.md` (built on a branch): the budget of rounds, the wakes, the plan of work.
- `a-fast-loop-for-the-assistant.md` (step 1 done): the rehearsal with a real model.
- `the-assistant-reaches-a-referenced-document.md`, `the-assistant-does-what-a-person-asks-of-a-pivot.md`,
  `the-assistant-fills-a-live-table.md`: verbs of other areas that a model calls.
- `the-relevance-model-reads-code-and-call-sites.md` (deferred): the text that the relevance model reads.

## Examined and sound

- `messages` is a callback of `run_turn!`, and an `Agent` holds no transcript: the conversation stays the one copy.
- Text and reasoning use the same `LlmEvent`s and one handler for both drivers.
- `make_llm`, `make_agent_connection` and `make_agent_server` dispatch on `Val`: the method table is the registry.
- The assistant names no domain: a fenced block and a tool result go through the natural-format seam.
- One list, `ToolSet.api`, decides what code resolves and what the searches find, and the marks fill it by reflection.
- `run_on_editor_task!` is the one door for the loop, the MCP server and the events of an agent.
- A connection keeps no `on_event` after a call, and `AgentEventQueue` holds no editor (PAR-NO-EDITOR-IN-DOCUMENT).
- The indexes of the guides and of the API and the stores of vectors are global: the accepted exception of
  PAR-PER-EDITOR-STATE for data that is the same for every editor.
- The three clients get their instructions from one function, `make_assistant_system`. The description of
  `execute_julia_code` repeats some rules, because an MCP client may read only the descriptions.
- A person's code runs in two namespaces, the evaluator's and the model's, for a stated reason.
- `search_api` and `search_guides` stay two tools: a measured decision of `agent.md`.
- The help slice builds its tree as documents and takes the docstring text from the tool layer of the kernel.

## Check of the report

A second agent tried to refute each finding at commit 3a9b4fae4. It opened the cited files and lines, counted again,
and searched the documents and the plan folders for a reason or a plan. It ran no code.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| AI-1 | confirmed-with-corrections | high |
| AI-2 | confirmed-with-corrections | high |
| AI-3 | confirmed-with-corrections | medium |
| AI-4 | weakened | low |
| AI-5 | confirmed-with-corrections | medium |
| AI-6 | confirmed-with-corrections | low |
| AI-7 | confirmed | medium |
| AI-8 | confirmed-with-corrections | medium |
| AI-9 | weakened | low |
| AI-10 | confirmed-with-corrections | low |

Notes of the check:

- No finding is covered by a pending plan, and none goes against a settled decision of the owner. Two parts reopen a
  written choice: the sentence of a domain in AI-10 (the reflection plan kept `register_assistant_api!` for it), and a
  `Dict` in the shape of JSON Schema in the tool layer in AI-9 ("a `Tool` carries no wire format").
- Three parts add a capability and are not a join: a picture for a model in the process (AI-1), the usage of a model
  in the pane (AI-2), and a setting for the relevance model (AI-8).
- AI-5 overlaps AI-1, AI-2 and AI-6: after those three, three of its five builders are left.
- Seen during the check and not in the report: the printer of a part builds a projection at each print and calls
  its printer directly, `print_document(PrimitiveStringToTextBlock(; style = p.message_text), …)` at
  `source/platform/conversation/ConversationToWidget.jl:463`. The owner's rule is that no projection is built per
  print and that a child printer comes from the dispatch. The change of AI-3 removes it.
