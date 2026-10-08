# The assistant

> **Kind:** design · **Status:** current · **Stands on:** [conversation.md](../conversation/conversation.md), [agent.md](../../kernel/agent.md), [anthropic.md](../../adapter/anthropic/anthropic.md), [ollama.md](../../adapter/ollama/ollama.md)

The assistant slice of `ProjecturedPlatform` puts a chat with a model beside the panes of a window: the `Assistant` document, the turn that streams a reply and runs tools, and the pane that shows the transcript over the composer. This document says how a turn uses the `tool`, `llm` and `agent` layers of the kernel, how a conversation becomes the messages of a request, and what does not work yet. [assistant-guide.md](../../../guide/assistant-guide.md) says how to run it.

<img width="396" alt="Assistant example" src="../../../asset/image/example/assistant.png">

## How it works

### The document

`Assistant` is one `@document` with these groups of fields:

| Fields | What they hold |
| --- | --- |
| `conversation`, `draft` | the history and the next message, documents of the [conversation slice](../conversation/conversation.md) |
| `backend`, `model`, `api_key`, `context`, `system` | the settings of a turn |
| `llm` | an `Llm` that replaces the backend; a test puts a `FakeLlm` or a `ScriptedLlm` there |
| `agent_command`, `agent_session_meta`, `agent_session` | the command that starts an external agent, the JSON `_meta` of its sessions, and the live link to it; see "The turn of an external agent" |
| `status` | `:idle`, `:streaming` or `:error` |
| `collapse_thinking` | whether a thinking part starts folded |
| `input` | a `PrimitiveString` that no printer shows; see Limits |

`backend` is `:ollama` by default, `:anthropic`, `:acp` for an external agent, or `:none`. An empty `model` and a `context` of `0` mean the default of the backend. The constructor sets `draft.assistant` to the new assistant, so Return and Alt+Return in the composer become operations of this assistant.

### A turn

Return in the composer makes `SubmitDraftTurnOperation(assistant)`. While a turn streams, it does nothing and the draft keeps its text. Otherwise it finalizes the draft, pushes it as a user turn, resets the draft in place, puts the caret back in it, and starts the turn on an `@async` task with `status = :streaming`. The task runs `_run_agent_loop!`:

1. It builds the backend at this point: `llm` when it is set, else `make_llm(backend; api_key, model, context)`. The key is `api_key`, or the `ANTHROPIC_API_KEY` environment variable when `api_key` is empty. With `backend = :none` and no `llm`, it throws an error that lists `get_llm_backend_names()`.
2. It calls `bind_meaning_model!(editor.tools, llm)`, so a search by description in this turn ranks by meaning when the backend has a meaning model.
3. It pushes an empty assistant turn, and calls `run_turn!` of the kernel with `Agent(llm, editor.tools; system, thinking = true)`.
4. `messages` builds the messages with `build_messages(assistant.conversation)` at the start of every round. The tool results of a round are parts of the conversation, so the next round sends them with no second list.
5. `on_event` turns each event into a part, so the reply draws while it streams. A text block becomes a text part, and `parse_markdown_blocks` reads it again when it ends. A fenced block becomes a document of its domain through the natural-format seam. Prose becomes a Markdown document when the Markdown parser is loaded. A thinking block becomes a thinking part. An `AgentToolResult` becomes an `EvaluatorForm` part that keeps the id, the name, the source and the input of the call, and the text of the tool in `output`. Its result is a document of the media type that the tool declares (`result_mime_type`): a `"text/markdown"` answer, such as a guide or a list of search hits, is a Markdown document when the Markdown parser is loaded, and the pane draws it as a page of rendered Markdown, as it draws the prose of the model. A table on the page is a grid whose columns share the width of the part. Any other answer, an error, and a text that the parser refuses are text. A `Document` that `execute_julia_code` returns is the result itself, drawn live.

At the end, the turn gets its stop reason, and an assistant turn with no parts is removed. When the task throws, `status` becomes `:error`, `record_fault!` writes the fault into the store of the editor, and an assistant turn shows the text of the error. So a failure shows in the chat and in the fault log. The loop itself, with its round limit and its tool dispatch, is the kernel's; [agent.md](../../kernel/agent.md) describes it.

**A stop.** `CancelAssistantTurnOperation(assistant)` stops the turn that runs, and `is_assistant_turn_running(assistant)` says whether one runs. `_launch_agent_turn!` gives each turn an `AssistantTurnControl` in `turn_control`, and the stop sets its `is_cancelled`. Then the next event of the stream, or the `messages` of the next round, throws a `TurnCancelledException`. That ends `stream_turn`, whose adapter closes the connection, so the model stops, and `run_turn!` with it. The result of a tool that ran during the stop is drawn first, so the transcript says what the tool did, and no other tool of the round runs. The turn closes the text and thinking blocks that streamed, keeps what it has, and ends with `:cancelled`. An exception that means stop, such as an interrupt, still goes on. For an external agent, a stop that comes before its session exists is in the control too, and the turn then sends no prompt. A failure that a backend throws while the flag is set counts as the stop too, because a backend can wrap the exception. The Stop button and Escape give the operation; see "The view".

The task of the turn writes the assistant only through `run_on_editor_task!`, because a frame of the editor reads and paints the assistant on the editor task. The empty assistant turn, each part, the stop reason and each change of `status` are posted, and the drain of the next frame applies them in the order they were posted. Many parts of a stream are applied in one frame. `messages` waits for its answer, so it reads the conversation after every part that came before it. When no loop runs, as in a test that calls `_run_agent_loop!`, each write happens at once. [editor.md](../../kernel/editor.md) describes the door.

Alt+Return on a Julia part makes `EvaluateDraftTurnOperation`. While a turn streams, it does nothing and the draft keeps its text, because a user turn in the middle of a streamed turn can come between a tool call and its result. Otherwise it runs the evaluation of the composer in place, and then pushes the whole draft as one user turn. No model runs. The next submit sends the evaluation to the model as part of the history.

### The tools

The model gets `list_tools(editor.tools)`, the tool set of the editor. The assistant keeps no registry of its own, and `run_turn!` registers the default tools. An MCP client gets the same set; see [mcp.md](../../adapter/mcp/mcp.md). A tool changes the document with `evaluate_operation(editor, operation)`, the same call that a key press makes. `run_turn!` runs each tool call on the editor task, as the MCP server does for a client, so a tool behaves the same for both.

### The API a loaded package offers

`register_assistant_api!(declaration)` and `get_registered_assistant_api()`, in `source/platform/assistant/AssistantApi.jl`, let a package offer names to the model of an assistant without a host naming that package. `declaration` is one entry or a vector of entries, in the form that `declare_api!` takes: a module, which offers every name it exports, or `module => (names...)`, which offers only those names. A package calls `register_assistant_api!` from its own `__init__`, so its names are offered exactly while the package is loaded, and an entry that is already registered is not added twice.

`get_registered_assistant_api()` answers every registered entry, in the order of the registrations. A host, such as the [application slice](../application/application.md), concatenates it with its own vocabularies and passes the whole list to `declare_api!`, so a domain that a session loads helps the model read and change the documents of that domain with no change to the host. The JSON domain registers its seven document types this way; see [json.md](../../domain/json/json.md).

### From the conversation to the messages

`build_messages(conversation)` makes the `LlmMessage`s of a request:

- It starts at the first user turn, because a provider answers HTTP 400 to a request whose first message is from the assistant. A greeting turn that a pane wrote on open is not sent. A conversation with no user turn is sent whole.
- A user turn becomes one text message, with its parts joined by a blank line. A code part is fenced with the name of its language, and a Markdown part is its source text. An evaluation that a person ran is written as text: "I ran the following Julia code: … Result: …".
- Consecutive assistant turns become one. It is then split at each run of evaluations into an assistant message of thinking, text and `tool_use` blocks, followed by a user message of `tool_result` blocks. The thinking comes first, with its signature unchanged, because a changed signature makes the provider answer HTTP 400.
- A form replays its own tool name and input. A form with no input replays as `execute_julia_code` with its code.
- A tool result is the text in `output`, as the tool wrote it. A form with no output, such as a live value, sends its result printed as text.

`format_conversation` and `write_conversation` write the history as plain text, for a log.

### The view

`AssistantToWidgetSplitPane` makes a vertical `WidgetSplitPane`. The top is a `WidgetScrollPane` over the conversation with `follow_end = true`, so the newest part stays in view, and it takes the free height. The bottom is a scroll pane over the draft, at least 200 pixels high. Both scroll panes hold the documents and not a projection of them, so the renderer around the pane draws the conversation as a transcript and the draft as a composer. The `selection` cell of the split pane is the selection of the assistant mapped forward, so a key goes to the pane that the selection names.

Under the composer, a row of the height `option_bar_height` holds the Stop button, `make_assistant_stop_button(assistant)`, for every backend; for an external agent it also holds the menus of its options and the usage of its context. The button is enabled only while a turn runs, and a click evaluates `CancelAssistantTurnOperation`. Escape stops the turn too: in the split pane the composer's `ComposerRevertOperation` becomes the cancel while a turn runs, and in the card the reader of the card makes it. At any other time Escape reverts the draft.

`AssistantToWidgetCard(; title, transcript_height, cell_height)` shows the same two panes in a card of a fixed height, for a page that holds an assistant. Each half scrolls, so a new turn does not make the page longer. Each container of the card carries the selection down with its own prefix removed. While the selection is in the draft, the reader of the card gives a key that nothing below took to the table of the composer.

### The turn of an external agent

With `backend = :acp` the task of the turn runs `_run_external_agent_turn!` in place of `_run_agent_loop!`. The agent runs its own loop and its own tools, so the assistant builds no `Llm` and runs no `run_turn!`. [acp.md](../../adapter/acp/acp.md) describes the connection.

1. **The session starts at the first turn.** The package `ProjecturedACP` must be loaded; otherwise the turn shows an error that says `using ProjecturedACP`. The assistant splits `agent_command` into words (default `""`, which starts the built-in agent of `ProjecturedACP`), makes the connection with `make_agent_connection(:acp; command, directory = pwd(), session_meta = agent_session_meta)`, and keeps it in `agent_session`, an `ExternalAgentSession` with the connection, the `session_id` and the `tool_server`. The same connection serves the later turns. `agent_session` is no data: a save does not write it, and a duplicate does not share it.
2. **The agent gets the tools of the editor.** When `:mcp` is among `get_agent_server_names()`, the assistant makes the MCP server with `port = 0`, `secret = true` and `DEFAULT_AGENT_INSTRUCTIONS` as its instructions, starts it, and gives `get_agent_server_access(server)` to `open_agent_session!`. The same text goes to `open_agent_session!` as `instructions`, which an agent adds to its system prompt. It says that the agent runs inside the editor of the person, that the MCP server controls that editor, and that a request about what the editor shows goes through its tools, not into source files or a worktree; then it gives the guide to the tools that the native assistant gets, without its rule against files and shell commands. The agent then calls `execute_julia_code` and the other tools with the secret, and each call runs on the editor task, so an edit is an operation and undo works. Without `ProjecturedMCP` the agent has its own tools only.
3. **The prompt is what the agent has not seen.** `ExternalAgentSession` counts the turns of the conversation that the agent saw, `sent_turn_count`. A new session starts the count at the last assistant turn, so a greeting or the note of a duplicate is not sent. `_make_external_agent_prompt` takes each user turn after that count and makes one `LlmText` block from it with `_make_user_turn_text`, and the count moves when `send_agent_prompt!` returns. So a turn that never reached the agent, as when the start of the session failed, is in the next prompt, and a turn that the agent got is never sent twice. A local evaluation (Alt+Return) is in the prompt as text.
4. **Each event becomes a part.** The assistant posts the writes with `run_on_editor_task!(…; wait = false)`.

| Event | Part of the assistant turn |
| --- | --- |
| `LlmTextStart`…`LlmTextStop` | a prose part |
| `LlmThinkingStart`…`LlmThinkingStop` | a `ConversationThinking` part |
| `AgentToolCallUpdate` | one `EvaluatorForm` for each call `id`; later updates fill its input, its output and its failure; the prefix `mcp__projectured__` of a tool name is removed |
| `AgentPlanUpdate` | one prose part with a checklist, which each update replaces |
| `AgentPermissionRequest` | a `ConversationPermissionRequest` |

A text or thinking block closes before a part of another kind comes, and text after it opens a new block.

**The permission card.** A `ConversationPermissionRequest` holds a title, the options of the agent, the `answer` and a `reply` function. The pane draws it as a card with one button for each option. A click calls `answer_permission_request!`, which sends the id of the option through `reply`, stores the name of the option, and disables the buttons. When `reply` answers `false`, the agent had its answer already from a cancel, and the request shows `"Cancelled"`. A request has one answer: a later call does nothing. A request that nobody answered when the turn ends gets the answer `"Cancelled"`. The `reply` is no data, so the duplicate of a request has none.

**A stop cancels the turn of the agent.** `CancelAssistantTurnOperation`, from the Stop button or from Escape in the composer, sets `is_cancelled` of the session, and it calls `cancel_agent_prompt!` on a task of its own when the session is open. The agent stops, each waiting request is answered as cancelled, and the turn ends with `:cancelled`. A turn that is still starting its session sends no prompt. The end of the turn clears the flag. At any other time Escape reverts the draft.

**The assistant keeps its session.** When the agent answers a prompt, the assistant keeps the session: `agent_session_id` holds its id, `agent_session_directory` its folder, and `agent_session_turn_count` how many turns of the conversation it saw. A `.pred` file keeps them with the conversation. A turn that starts the agent gives the id and the folder to `open_agent_session!` as `session_id` and `directory`, so the agent resumes the session with its history, when the folder still exists and the agent can resume. A resumed session counts the turns that it saw from `agent_session_turn_count`, so the prompt holds each turn that it did not see. When the agent opens a new session in its place, the assistant forgets the kept session and its title, and a note says "The agent could not resume its session, so the next answer comes from a new session, which does not have the history above." When the first prompt after a resume fails, the agent does not have the session, as for a session in which it never answered; the assistant then drops the folder of the kept session, so the next turn opens a new session with that note. An answer that comes after a reset keeps no session.

**A stop keeps the session.** A turn that throws stops the connection, and the next turn starts the agent again and resumes the session. The count of the turns that the agent saw stays. The close of the tab of an assistant stops the agent and its MCP server: the close ends with `ReleaseDocumentOperation`, and the method of `release_document!` for an `Assistant` calls `stop_external_agent!`, which keeps the id, the folder and the title. An undo of the close brings the tab and its conversation back, and the next turn resumes the session, which holds the earlier turns. A reset of the conversation (`ResetConversationOperation`) stops the agent and forgets the session, so the next turn opens a new one.

**The options of the agent.** `agent_options` holds the options of the session as the agent last listed them, and it is no data. Under the composer, a row of menus (`make_agent_option_bar`) shows the model, the effort and the mode of the agent, in a height that the `option_bar_height` of the `ConversationTheme` gives. Each menu says the value that holds, and a pick evaluates `SetAgentOptionOperation(assistant, option_id, value)`, which calls `set_agent_option!` on a task of its own; the answer of the agent replaces `agent_options`. Before a session is open the row is one item, "Start the agent", which evaluates `StartExternalAgentOperation(assistant)`: it starts the agent and opens its session with no prompt, so the options show before the first message. A lock in the session makes a turn and a start open one session. A failed start shows in the conversation, as a failed turn does. A pick holds for the session; a new session starts with the values that the agent gives. The row is the third child of the split pane, so the maps of the transcript and the composer stay as they are.

**The title and the usage of the session.** `agent_title` holds the title that the agent gave its session, and `get_document_title` of the assistant answers it, or "Assistant" when there is none. The application opens the assistant in a tab with no name of its own, so the tab asks at each draw and shows the title of the session. A tab that the toolbar opens takes its name when it opens and keeps "Assistant". `agent_usage` holds the last `AgentUsageUpdate`, and a line beside the option menus says it with `format_agent_usage`, as "Context: 36k of 1M tokens", with the cost when the agent says. Both are no data; a reset and a duplicate start without them.

**The commands of the agent.** `agent_commands` holds the commands that the agent offers, and the last menu of the row, "Commands", lists them as `/name`, each with its description as the tooltip. A pick writes `/name ` into the draft with `ComposerInputOperation`, and the person completes and sends the command; the agent reads it at the start of the prompt. The agent gives its commands with the first prompt, so the menu shows from then on. A completion of `/` while the person types is not built.

**A duplicate starts a new session.** A copy of an assistant with a live `agent_session` or a kept session has `agent_session = nothing` and no kept session, so its first turn starts a new connection and a new session. It ends its conversation with the note "This copy talks to the agent in a new session. The agent does not have the history above."

### When a turn fails

- **No backend.** With `backend = :none` and no `llm`, a submit shows an error turn that names the backends whose packages are loaded.
- **No server, or no model on the server.** The error of the adapter shows in an error turn. A connection error names the address, and the Ollama adapter gives the `ollama pull` command for a model that the server does not have.
- **A tool throws.** The tool result carries the error text, the model gets it, and the form of the call is marked `is_error`.

### A copy and a save

A copy of an assistant is a fork: it has the conversation so far and a draft of its own, and it starts idle. A reply that streams stays with the original. `pred_arguments` saves only `backend`, `model`, `system`, `context` and `collapse_thinking`. A key is never written to a file. A command is never written either: a file that named the program of an external agent, or the options of its sessions, would start it at the next message, and a `.pred` file runs no code. So `agent_command` and `agent_session_meta` come from `StartSettings` of the application, and a loaded assistant starts with an empty conversation. An assistant with `backend = :acp` that keeps a session is the exception, because the agent holds the history of its conversation: its file also keeps the conversation, `agent_session_id`, `agent_session_directory`, `agent_session_turn_count` and `agent_title`, so the tab shows the conversation and its title after a load, and the next turn resumes the session. An id is no command and no credential, and the agent still comes from the settings. `accepts_pasted_document` and `accepts_opened_file` return `false`, so a paste or an opened file does not replace the assistant.

## How it fits

The assistant slice depends on the kernel and on the conversation, collection, domain, natural, layout, primitive, projection, serialization, style, text and widget slices of `ProjecturedPlatform`. From the kernel it takes the `tool`, `llm` and `agent` layers, which [agent.md](../../kernel/agent.md) describes, and the `fault` layer. It does not depend on a backend package: a session loads `ProjecturedOllama` or `ProjecturedAnthropic`, which [ollama.md](../../adapter/ollama/ollama.md) and [anthropic.md](../../adapter/anthropic/anthropic.md) describe.

The shell slice puts an Assistant button on the toolbar, and the host gives the function that makes the assistant, with its backend and its greeting; see [shell.md](../shell/shell.md). The [application slice](../application/application.md) puts the explorer, the files and the assistant in one pane tree.

The package registers the natural row `:assistant`, `Assistant => AssistantToWidgetSplitPane()`. It adds the methods `make_submit_operation(::Assistant)` and `make_evaluate_operation(::Assistant)` to the conversation package.

## Design decisions

- **A person names the backend, and a local model is the default.** Nothing guesses a backend, because a guess is right only while one backend exists. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The backend is built at each turn.** A document is built into a constant during precompilation, when no key exists, and a cached backend would keep the first model after a person changed `model`. The reasons are in the docstring of `Assistant` and in the comment on `_build_llm`.
- **The conversation is the one source of the prompt.** `messages` is a function, and not a list that the loop keeps, so the prompt can not differ from the transcript. See [plan/done/kernel-agent-stack.md](../../../../plan/done/kernel-agent-stack.md).
- **An evaluation that a person ran goes to the model as text.** A `tool_use` block would put a call into the history that the model did not make.
- **A tool gets the editor through `evaluate_operation(editor, operation)`.** The rejected options were an `editor` field on the assistant, an ambient `Ref`, task-local storage and a late-bound handler. See [plan/done/assistant-editor-reference.md](../../../../plan/done/assistant-editor-reference.md). The code that the tool runs passes no editor to a verb: `execute_julia_code!` binds the editor it gets as the editor of the evaluation, which the verb takes as the default of its `editor` keyword (PAR-PER-EDITOR-STATE).
- **The pane draws a result, and the model reads the text.** A Markdown page printed back is not the text it was read from, so the form keeps the text in `output`, as it keeps the call in `source`. The tool declares its media type, so the assistant keeps no list of tool names. See [plan/done/documentation-tool-results-as-markdown.md](../../../../plan/done/documentation-tool-results-as-markdown.md).
- **A resource read starts folded, and an evaluation starts open.** A read is lookup work of the model and less important than the answer. See [plan/done/assistant-collapse-layout.md](../../../../plan/done/assistant-collapse-layout.md).

## Usage

```julia
assistant = Assistant(; backend = :ollama)                   # a local model, the default
assistant = Assistant(; backend = :anthropic, model = "")    # Claude, with ANTHROPIC_API_KEY
assistant = Assistant(; backend = :acp)                       # an external agent; needs using ProjecturedACP
assistant = Assistant(; llm = FakeLlm())                     # a canned reply, for a test
run_assistant_example(; backend = :ollama)                   # the example with a real model
```

- Example: `assistant_example` shows a canned transcript with one part of every kind and answers from a `FakeLlm`, so it needs no server and no key. The factories are `make_assistant_document_example` and `make_assistant_projection_example` in `example/platform/conversation/`.
- Tests, in `test/projectured/editor/`: `test_assistant_mvp()` drives a whole turn with a scripted model, checks that Return, Alt+Return and `SubmitProseOperation` while a turn streams do nothing, and checks that the writes of a turn and its tool call wait for the drain of the editor. `test_assistant_duplicate()` covers the fork, and `test_assistant_composer_panel()` covers the composer in the pane. `test_assistant_editor_reference()` and `test_assistant_turn_binds_meaning_model()` are in `McpTest.jl`, and `test_conversation_serialization()` covers `build_messages`.

## Limits

- **A tool call holds the frame.** A tool call of the model runs on the editor task, and the editor draws no frame until it returns. The first search by description of a build can wait up to 30 seconds for the vectors of the meaning model.
- **A part that fails to apply does not end the turn.** A streamed part is posted and not waited for, so an exception while the drain applies it goes to the fault log of the editor, and the turn goes on.
- No view draws `status`, except the Stop button, which is enabled only while a turn runs. A person sees a running turn by that button and by the parts that arrive.
- **A stop of a turn of a model waits for the next event.** A model that reads a long prompt sends no event for a while, and the stop takes effect only at its first event. A tool call that runs is not stopped, and the turn ends after it.
- `input`, `SubmitProseOperation`, `SubmitJuliaOperation`, `ClearInputOperation` and `ResetConversationOperation` are exported, but no printer shows `input` and no reader makes these operations. Only the tests call two of them. `SubmitProseOperation` does nothing while a turn streams, as Return does.
- The natural row gives a pane tab a widget and not graphics. A host that shows an assistant in a tab chains `AssistantToWidgetSplitPane` to `NaturalToGraphics` with the rows of the conversation, as `make_application_content_projections` of the [application slice](../application/application.md) does.
- The draft has no frame, no focus ring and no hint line. Stage 4 of [plan/pending/conversation-flat-transcript.md](../../../../plan/pending/conversation-flat-transcript.md) puts them on this pane, and they are not done.
- `DEFAULT_ASSISTANT_SYSTEM` is written for Claude and is long. A small local model can follow it less well, and [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md) keeps this as an open question.
- No test is marked `@test_broken`.
