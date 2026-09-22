# The assistant

> **Kind:** design · **Status:** current · **Stands on:** [conversation.md](../conversation/conversation.md), [agent.md](../kernel/agent.md), [llm.md](../llm/llm.md)

`ProjecturedAssistant` puts a chat with a model beside the panes of a window: the `Assistant` document, the turn that streams a reply and runs tools, and the pane that shows the transcript over the composer. This document says how a turn uses the `tool`, `llm` and `agent` layers of the kernel, how a conversation becomes the messages of a request, and what does not work yet. [assistant-guide.md](../../guide/assistant-guide.md) says how to run it.

<img width="396" alt="Assistant example" src="../../../asset/image/example/assistant.png">

## How it works

### The document

`Assistant` is one `@document` with these groups of fields:

| Fields | What they hold |
| --- | --- |
| `conversation`, `draft` | the history and the next message, documents of the [conversation domain](../conversation/conversation.md) |
| `backend`, `model`, `api_key`, `context`, `system` | the settings of a turn |
| `llm` | an `Llm` that replaces the backend; a test puts a `FakeLlm` or a `ScriptedLlm` there |
| `status` | `:idle`, `:streaming` or `:error` |
| `collapse_thinking` | whether a thinking part starts folded |
| `input` | a `PrimitiveString` that no printer shows; see Limits |

`backend` is `:ollama` by default, `:anthropic`, or `:none`. An empty `model` and a `context` of `0` mean the default of the backend. The constructor sets `draft.assistant` to the new assistant, so Return and Alt+Return in the composer become operations of this assistant.

### A turn

Return in the composer makes `SubmitDraftTurnOperation(assistant)`. While a turn streams, it does nothing and the draft keeps its text. Otherwise it finalizes the draft, pushes it as a user turn, resets the draft in place, puts the caret back in it, and starts the turn on an `@async` task with `status = :streaming`. The task runs `_run_agent_loop!`:

1. It builds the backend at this point: `llm` when it is set, else `make_llm(backend; api_key, model, context)`. The key is `api_key`, or the `ANTHROPIC_API_KEY` environment variable when `api_key` is empty. With `backend = :none` and no `llm`, it throws an error that lists `get_llm_backend_names()`.
2. It calls `bind_meaning_model!(editor.tools, llm)`, so a search by description in this turn ranks by meaning when the backend has a meaning model.
3. It pushes an empty assistant turn, and calls `run_turn!` of the kernel with `Agent(llm, editor.tools; system, thinking = true)`.
4. `messages` is `() -> build_messages(assistant.conversation)`, called at the start of every round. The tool results of a round are parts of the conversation, so the next round sends them with no second list.
5. `on_event` turns each event into a part and calls `wake_editor!`, so the reply draws while it streams. A text block becomes a text part, and `parse_markdown_blocks` reads it again when it ends. A fenced block becomes a document of its domain through the natural-format seam. Prose becomes a Markdown document when the Markdown parser is loaded. A thinking block becomes a thinking part. An `AgentToolResult` becomes an `EvaluatorForm` part that keeps the id, the name, the source and the input of the call.

At the end, an assistant turn with no parts is removed. When the task throws, `status` becomes `:error`, `record_fault!` writes the fault into the store of the editor, and an assistant turn shows the text of the error. So a failure shows in the chat and in the fault log. The loop itself, with its round limit and its tool dispatch, is the kernel's; [agent.md](../kernel/agent.md) describes it.

Alt+Return on a Julia part makes `EvaluateDraftTurnOperation`. It runs the evaluation of the composer in place, and then pushes the whole draft as one user turn. No model runs. The next submit sends the evaluation to the model as part of the history.

### The tools

The model gets `list_tools(editor.tools)`, the tool set of the editor. The assistant keeps no registry of its own, and `run_turn!` registers the default tools. An MCP client gets the same set; see [mcp.md](../mcp/mcp.md). A tool changes the document with `evaluate_operation(editor, operation)`, the same call that a key press makes.

### From the conversation to the messages

`build_messages(conversation)` makes the `LlmMessage`s of a request:

- It starts at the first user turn, because a provider answers HTTP 400 to a request whose first message is from the assistant. A greeting turn that a pane wrote on open is not sent. A conversation with no user turn is sent whole.
- A user turn becomes one text message, with its parts joined by a blank line. A code part is fenced with the name of its language, and a Markdown part is its source text. An evaluation that a person ran is written as text: "I ran the following Julia code: … Result: …".
- Consecutive assistant turns become one. It is then split at each run of evaluations into an assistant message of thinking, text and `tool_use` blocks, followed by a user message of `tool_result` blocks. The thinking comes first, with its signature unchanged, because a changed signature makes the provider answer HTTP 400.
- A form replays its own tool name and input. A form with no input replays as `execute_julia_code` with its code.

`format_conversation` and `write_conversation` write the history as plain text, for a log.

### The view

`AssistantToWidgetSplitPane` makes a vertical `WidgetSplitPane`. The top is a `WidgetScrollPane` over the conversation with `follow_end = true`, so the newest part stays in view, and it takes the free height. The bottom is a scroll pane over the draft, at least 200 pixels high. Both scroll panes hold the documents and not a projection of them, so the renderer around the pane draws the conversation as a transcript and the draft as a composer. The `selection` cell of the split pane is the selection of the assistant mapped forward, so a key goes to the pane that the selection names.

`AssistantToWidgetCard(; title, transcript_height, cell_height)` shows the same two panes in a card of a fixed height, for a page that holds an assistant. Each half scrolls, so a new turn does not make the page longer. Each container of the card carries the selection down with its own prefix removed. While the selection is in the draft, the reader of the card gives a key that nothing below took to the table of the composer.

### When a turn fails

- **No backend.** With `backend = :none` and no `llm`, a submit shows an error turn that names the backends whose packages are loaded.
- **No server, or no model on the server.** The error of the adapter shows in an error turn. A connection error names the address, and the Ollama adapter gives the `ollama pull` command for a model that the server does not have.
- **A tool throws.** The tool result carries the error text, the model gets it, and the form of the call is marked `is_error`.

### A copy and a save

A copy of an assistant is a fork: it has the conversation so far and a draft of its own, and it starts idle. A reply that streams stays with the original. `pred_arguments` saves only `backend`, `model`, `system`, `context` and `collapse_thinking`. A key is never written to a file, and a loaded assistant starts with an empty conversation. `accepts_pasted_document` and `accepts_opened_file` return `false`, so a paste or an opened file does not replace the assistant.

## How it fits

`ProjecturedAssistant` depends on `ProjecturedConversation`, `ProjecturedCollection`, `ProjecturedDomain`, `ProjecturedNatural`, `ProjecturedLayout`, `ProjecturedPrimitive`, `ProjecturedProjection`, `ProjecturedSerialization`, `ProjecturedStyle`, `ProjecturedText`, `ProjecturedWidget` and the kernel. From the kernel it takes the `tool`, `llm` and `agent` layers, which [agent.md](../kernel/agent.md) describes, and the `fault` layer. It does not depend on a backend package: a session loads `ProjecturedOllama` or `ProjecturedAnthropic`, and [llm.md](../llm/llm.md) describes both.

`ProjecturedShell` puts an Assistant button on the toolbar, and the host gives the function that makes the assistant, with its backend and its greeting; see [shell.md](../shell/shell.md). `example/projectured/Application.jl` puts the explorer, the files and the assistant in one pane tree.

The package registers the natural row `:assistant`, `Assistant => AssistantToWidgetSplitPane()`, and `Assistant` as a `.pred` type. It adds the methods `make_submit_operation(::Assistant)` and `make_evaluate_operation(::Assistant)` to the conversation package.

## Design decisions

- **A person names the backend, and a local model is the default.** Nothing guesses a backend, because a guess is right only while one backend exists. See `plan/done/ollama-backend.md`.
- **The backend is built at each turn.** A document is built into a constant during precompilation, when no key exists, and a cached backend would keep the first model after a person changed `model`. The reasons are in the docstring of `Assistant` and in the comment on `_build_llm`.
- **The conversation is the one source of the prompt.** `messages` is a function, and not a list that the loop keeps, so the prompt can not differ from the transcript. See `plan/done/kernel-agent-stack.md`.
- **An evaluation that a person ran goes to the model as text.** A `tool_use` block would put a call into the history that the model did not make.
- **A tool gets the editor through `evaluate_operation(editor, operation)`.** The rejected options were an `editor` field on the assistant, an ambient `Ref`, task-local storage and a late-bound handler. See `plan/done/assistant-editor-reference.md`.
- **A resource read starts folded, and an evaluation starts open.** A read is lookup work of the model and less important than the answer. See `plan/done/assistant-collapse-layout.md`.

## Usage

```julia
assistant = Assistant(; backend = :ollama)                   # a local model, the default
assistant = Assistant(; backend = :anthropic, model = "")    # Claude, with ANTHROPIC_API_KEY
assistant = Assistant(; llm = FakeLlm())                     # a canned reply, for a test
run_assistant_example(; backend = :ollama)                   # the example with a real model
```

- Example: `assistant_example` shows a canned transcript with one part of every kind and answers from a `FakeLlm`, so it needs no server and no key. The factories are `make_assistant_document_example` and `make_assistant_projection_example` in `example/conversation/`.
- Tests, in `test/projectured/editor/`: `test_assistant_mvp()` drives a whole turn with a scripted model, `test_assistant_duplicate()` covers the fork, and `test_assistant_composer_panel()` covers the composer in the pane. `test_assistant_editor_reference()` and `test_assistant_turn_binds_meaning_model()` are in `McpTest.jl`, and `test_conversation_serialization()` covers `build_messages`.

## Limits

- **The turn task writes the document from outside the frame.** It pushes turns and parts and sets `status` on `editor.document` directly, and not through `post_operation!`, the inbox that orders such writes with the frame. A frame that runs between two writes can read a state that is half done. `plan/done/the-editor-survives-a-fault.md`, section 9, records this as open work. The MCP server has the same fault.
- No view draws `status`. A person sees a running turn only by the parts that arrive.
- `input`, `SubmitProseOperation`, `SubmitJuliaOperation`, `ClearInputOperation` and `ResetConversationOperation` are exported, but no printer shows `input` and no reader makes these operations. Only the tests call two of them.
- The natural row gives a pane tab a widget and not graphics. A host that shows an assistant in a tab chains `AssistantToWidgetSplitPane` to `NaturalToGraphics` with the rows of the conversation, as `make_application_content_projections` in `example/projectured/Application.jl` does.
- The draft has no frame, no focus ring and no hint line. Stage 4 of `plan/pending/conversation-flat-transcript.md` puts them on this pane, and they are not done.
- `DEFAULT_ASSISTANT_SYSTEM` is written for Claude and is long. A small local model can follow it less well, and `plan/done/ollama-backend.md` keeps this as an open question.
- No test is marked `@test_broken`.
