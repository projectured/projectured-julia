# The assistant

> **Kind:** design · **Status:** current · **Stands on:** [conversation.md](../conversation/conversation.md), [agent.md](../../kernel/agent.md), [anthropic.md](../../adapter/anthropic/anthropic.md), [ollama.md](../../adapter/ollama/ollama.md), [task.md](../task/task.md), [tree.md](../tree/tree.md), [workplan.md](../workplan/workplan.md), [systemprocess.md](../systemprocess/systemprocess.md), [navigator.md](../navigator/navigator.md)

The assistant slice of `ProjecturedPlatform` puts a chat with a model beside the panes of a window: the `Assistant` document, the turn that streams a reply and runs tools, and the pane that shows the transcript over the composer. This document says how a turn uses the `tool`, `llm` and `agent` layers of the kernel, how a conversation becomes the messages of a request, how the work of an external agent (its subagents, its plans and its background tasks) becomes documents and a page, and what does not work yet. [assistant-guide.md](../../../guide/assistant-guide.md) says how to run it.

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
| `agent_work` | the work of the session of the agent, an `AgentWork`; see "The work of an agent". It is live state: a file does not keep it, and a duplicate and a reset start with an empty one |
| `status` | `:idle`, `:streaming` or `:error` |
| `collapse_thinking` | whether a thinking part starts folded |
| `input` | a `PrimitiveString` that no printer shows; see Limits |
| `description`, `comment` | what the person writes about the conversation, each a `PrimitiveString` that the detail of the Assistants pane edits |
| `work_state` | the state of the work that the person sets: `:pending` (the default), `:in_progress`, `:complete` or `:abandoned` (`ASSISTANT_WORK_STATES`) |

`backend` is `:ollama` by default, `:anthropic`, `:acp` for an external agent, or `:none`. An empty `model` and a `context` of `0` mean the default of the backend. The constructor sets `draft.assistant` to the new assistant, so Return and Alt+Return in the composer become operations of this assistant.

### A turn

Return in the composer makes `SubmitDraftTurnOperation(assistant)`. It finalizes the draft, pushes it as a user turn, resets the draft in place, and puts the caret back in it. With no turn that runs, it starts the turn on an `@async` task with `status = :streaming`. While a turn runs, the message shows at once below the answer that streams: an external agent that takes a prompt into a turn that runs (`has_agent_steering`) gets it there through `steer_agent_prompt!`, and the answer goes on in a new assistant turn below the message; else the message waits, and when the running turn ends, a turn of its own starts with it, unless a person stopped the running turn. A turn reads the conversation up to itself (`build_messages(conversation; until = turn)`), and `AssistantTurnControl.seen_turn_count` counts the turns that it read, so a user turn after them is a message that waits. A message that comes before the turn has pushed its answer turn sits above it, and the turn reads it. `SubmitProseOperation` does the same with the input line. The task runs `_run_agent_loop!`:

1. It builds the backend at this point: `llm` when it is set, else `make_llm(backend; api_key, model, context)`. The key is `api_key`, or the `ANTHROPIC_API_KEY` environment variable when `api_key` is empty. With `backend = :none` and no `llm`, it throws an error that lists `get_llm_backend_names()`.
2. It calls `bind_meaning_model!(editor.tools, llm)`, so a search by description in this turn ranks by meaning when the backend has a meaning model.
3. It pushes an empty assistant turn, and calls `run_turn!` of the kernel with `Agent(llm, editor.tools; system, thinking = true)` and one tool of the turn, `ask_person`, which an ACP agent and an MCP client do not see. Its parameters are `question`, `options` (one option a line) and `multiple`. Its handler adds a `ConversationQuestionRequest` to the turn, with a choice (or a choice of several) of the options and an "Other" text field, or only a text field for a question with no options, and answers a task that waits for the reply, so the turn waits and the editor does not. The model reads "The person chose: …", "The person answered: …" or "The person declined to answer." A stop of the turn declines the open question. `build_messages` skips a question, a permission and a sign-in part of an assistant turn, because they are for the person, and the answer reaches the model in the result of the tool.
4. `messages` builds the messages with `build_messages(assistant.conversation)` at the start of every round. The tool results of a round are parts of the conversation, so the next round sends them with no second list.
5. `on_event` turns each event into a part, so the reply draws while it streams. A text block becomes a text part, and `parse_markdown_blocks` reads it again when it ends. A fenced block becomes a document of its domain through the natural-format seam. Prose becomes a Markdown document when the Markdown parser is loaded. A thinking block becomes a thinking part. An `AgentToolResult` becomes an `EvaluatorForm` part that keeps the id, the name, the source and the input of the call, and the text of the tool in `output`. Its result is a document of the media type that the tool declares (`result_mime_type`): a `"text/markdown"` answer, such as a guide or a list of search hits, is a Markdown document when the Markdown parser is loaded, and the pane draws it as a page of rendered Markdown, as it draws the prose of the model. A table on the page is a grid whose columns share the width of the part. Any other answer, an error, and a text that the parser refuses are text. A `Document` that `execute_julia_code` returns is the result itself, drawn live.

At the end, the turn gets its stop reason, and an assistant turn with no parts is removed. When the task throws, `status` becomes `:error`, `record_fault!` writes the fault into the store of the editor, and an assistant turn shows the text of the error. So a failure shows in the chat and in the fault log. The loop itself, with its round limit and its tool dispatch, is the kernel's; [agent.md](../../kernel/agent.md) describes it.

**A stop.** `CancelAssistantTurnOperation(assistant)` stops the turn that runs, and `is_assistant_turn_running(assistant)` says whether one runs. `_launch_agent_turn!` gives each turn an `AssistantTurnControl` in `turn_control`, and the stop sets its `is_cancelled`. Then the next event of the stream, or the `messages` of the next round, throws a `TurnCancelledException`. That ends `stream_turn`, whose adapter closes the connection, so the model stops, and `run_turn!` with it. The result of a tool that ran during the stop is drawn first, so the transcript says what the tool did, and no other tool of the round runs. The turn closes the text and thinking blocks that streamed, keeps what it has, and ends with `:cancelled`. An exception that means stop, such as an interrupt, still goes on. For an external agent, a stop that comes before its session exists is in the control too, and the turn then sends no prompt. A failure that a backend throws while the flag is set counts as the stop too, because a backend can wrap the exception. The Stop button and Escape give the operation; see "The view".

The task of the turn writes the assistant only through `run_on_editor_task!`, because a frame of the editor reads and paints the assistant on the editor task. The empty assistant turn, each part, the stop reason and each change of `status` are posted, and the drain of the next frame applies them in the order they were posted. Many parts of a stream are applied in one frame. `messages` waits for its answer, so it reads the conversation after every part that came before it. When no loop runs, as in a test that calls `_run_agent_loop!`, each write happens at once. [editor.md](../../kernel/editor.md) describes the door.

Alt+Return on a Julia part makes `EvaluateDraftTurnOperation`. While a turn streams, it does nothing and the draft keeps its text, because a user turn in the middle of a streamed turn can come between a tool call and its result. Otherwise it runs the evaluation of the composer in place, and then pushes the whole draft as one user turn. No model runs. The next submit sends the evaluation to the model as part of the history.

### The tools

The model gets `list_tools(editor.tools)`, the tool set of the editor. The assistant keeps no registry of its own, and `run_turn!` registers the default tools. An MCP client gets the same set; see [mcp.md](../../adapter/mcp/mcp.md). A tool changes the document with `evaluate_operation(editor, operation)`, the same call that a key press makes. `run_turn!` runs each tool call on the editor task, as the MCP server does for a client, so a tool behaves the same for both.

### Pictures

The Picture button evaluates `AddDraftPictureOperation(assistant)`, in `source/platform/assistant/AssistantPicture.jl`. The picture is of the part that the person selected as a whole with Alt+click (`is_whole_selection`), else of the window that shows the selection. The picture goes into the draft as an `ImageFile` part, before the text that the person types, with `InsertDraftDocumentOperation` of the conversation slice, as a pasted plot does. A picture is a PNG file in `$XDG_CACHE_HOME/projectured/pictures` (by default `~/.cache/projectured/pictures`), named `picture-<date>-<time>.png`.

At the submit (`SubmitDraftTurnOperation`), a part with no text form becomes a picture of it. A part has a text form (`has_text_form` of the conversation slice) when it has a `:string` natural projection, or when it is text, a form or thinking; a picture is left as it is. The picture is written with `write_image(document, NaturalToGraphics(; measure = FontFileMeasure()), filename)`, and the part becomes that `ImageFile`. A part that the backend can not write stays as it is.

`register_picture_tools!(set)` adds the tool `take_picture` to the tool set. Its argument `part` is `"window"` (the default) or `"selection"`, and it answers an `LlmImage`. The application registers it beside the undo tools in `start_application!` (`source/platform/application/Application.jl`).

### The API a loaded package offers

`register_assistant_api!(declaration)` and `get_registered_assistant_api()`, in `source/platform/assistant/AssistantApi.jl`, let a package offer names to the model of an assistant without a host naming that package. `declaration` is one entry or a vector of entries, in the form that `declare_api!` takes: a module, which offers every name it exports, or `module => (names...)`, which offers only those names. A package calls `register_assistant_api!` from its own `__init__`, so its names are offered exactly while the package is loaded, and an entry that is already registered is not added twice.

`get_registered_assistant_api()` answers every registered entry, in the order of the registrations. A host, such as the [application slice](../application/application.md), concatenates it with its own vocabularies and passes the whole list to `declare_api!`, so a domain that a session loads helps the model read and change the documents of that domain with no change to the host. The JSON domain registers its seven document types this way; see [json.md](../../domain/json/json.md).

### From the conversation to the messages

`build_messages(conversation)` makes the `LlmMessage`s of a request:

- It starts at the first user turn, because a provider answers HTTP 400 to a request whose first message is from the assistant. A greeting turn that a pane wrote on open is not sent. A conversation with no user turn is sent whole.
- A user turn becomes text and pictures (`_make_user_turn_content`): the text of its parts in one block, and each `ImageFile` part as an `LlmImage` where it stands (png, jpeg, gif or webp, by the extension). A file that is gone, or of another type, is a line of the text. The same content goes to a model (`build_messages`), to an agent prompt and to a steer. The text of a user turn is its parts joined by a blank line. A code part is fenced with the name of its language, and a Markdown part is its source text. An evaluation that a person ran is written as text: "I ran the following Julia code: … Result: …".
- Consecutive assistant turns become one. It is then split at each run of evaluations into an assistant message of thinking, text and `tool_use` blocks, followed by a user message of `tool_result` blocks. The thinking comes first, with its signature unchanged, because a changed signature makes the provider answer HTTP 400.
- A form replays its own tool name and input. A form with no input replays as `execute_julia_code` with its code.
- A tool result is the text in `output`, as the tool wrote it. A form with no output, such as a live value, sends its result printed as text.

`format_conversation` and `write_conversation` write the history as plain text, for a log.

### The view

`AssistantToWidgetSplitPane` makes a vertical `WidgetSplitPane`. The top is a `WidgetScrollPane` over the conversation with `follow_end = true`, so the newest part stays in view, and it takes the free height. The bottom is a scroll pane over the draft, at least 200 pixels high. Both scroll panes hold the documents and not a projection of them, so the renderer around the pane draws the conversation as a transcript and the draft as a composer. The `selection` cell of the split pane is the selection of the assistant mapped forward, so a key goes to the pane that the selection names.

Under the composer, a row of the height `option_bar_height` holds the Stop button, `make_assistant_stop_button(assistant)`, and the Picture button, `make_assistant_picture_button(assistant)` (the Lucide icon `:camera`), for every backend; for an external agent it also holds the menus of its options and the usage of its context. The Stop button is enabled only while a turn runs, and a click evaluates `CancelAssistantTurnOperation`. Escape stops the turn too: in the split pane the composer's `ComposerRevertOperation` becomes the cancel while a turn runs, and in the card the reader of the card makes it. At any other time Escape reverts the draft.

`AssistantToWidgetCard(; title, transcript_height, cell_height)` shows the same two panes in a card of a fixed height, for a page that holds an assistant. Each half scrolls, so a new turn does not make the page longer. Each container of the card carries the selection down with its own prefix removed. While the selection is in the draft, the reader of the card gives a key that nothing below took to the table of the composer.

### The Assistants pane

`AssistantList` is the list of the open assistants of the session of an editor,
and `get_session_assistant_list(; editor)` answers it. Each editor has its own. Its `assistants` compute from a
source that the application gives with `set_assistant_list_source!`: a function
that answers the open assistants. `link_assistant_list!(list, tree)` of the
[application slice](../application/application.md) gives a source that reads
the tabs of the pane tree with `collect_pane_tab_contents(tree, Assistant)`, and
`run_application` links the list of the session of its editor to its window. A
file that loads before the editor exists gives a new list; the window links it
too, and the first such list is the list of the session. The read depends
only on the structure of the panes, so a tab that opens, closes or comes back
with an undo changes the rows, an empty assistant tab gets a row, and an edit
inside an assistant computes nothing again. A row leaves when its tab closes.
The list is opaque to the walk of the documents, so a search reaches an
assistant through its tab and not through the list. A file writes no arguments
for the list, and its load, a name typed into an empty tab and the toolbar all
give the list of the session.

The values of a row come from `source/platform/assistant/AssistantOverview.jl`:
`compute_assistant_overview_title` (the title of the session of the agent, else
the first line of the first prompt), `find_first_prompt`, `find_last_prompt`,
`compute_prompt_count`, `compute_assistant_turn_side` (`:assistant` while a turn
runs and no question of the agent waits, else `:person`),
`describe_assistant_activity` ("thinks", "writes", "runs <tool>", the question
of the agent, or "failed"), and the times: `find_assistant_start_time`,
`find_assistant_last_activity_time`, `compute_assistant_elapsed_time` and
`compute_assistant_busy_time`. The times come from the `start_time` and the
`finish_time` of each `ConversationTurn`; a submit gives a turn of the person
both, and a turn of the assistant gets its start when it is pushed and its end
in `_finish_turn!`.

`AssistantListToWidgetPane` draws the list: a heading, a table of one row for
each assistant, and below it, in a split that the person can drag, the detail of
the assistant that the person picked with `›`. A row has `›`, Show and Work, then
the title, the work state, whose turn it is, the activity, the count of prompts, the
usage of the context (`format_agent_usage`), the three columns of the work of the
agent (`plan`, `subagents` and `tasks`), the start time and the elapsed
time. Work shows the work page of the agent ([The work page](#the-work-page)).
Each value is a label that reads cells, so a row follows its assistant while a
turn streams. While a turn runs, the elapsed time reads the clock of the editor
(`ctx.clock`), which the frame loop writes. Between turns no label reads the
clock, so the editor draws no frame for the table. Show calls the opener of the list, which the application
sets to `show_document!`; that focuses the tab that shows the assistant, whatever
its title, or opens it again.

The detail holds the title, a line of facts, the description and the comment in
the cards of embedded documents (`make_embed_card`), a row of toggles for the
work state, the first and the last prompt, and the session of an agent. The pane
maps `assistants[i].description` and `assistants[i].comment`, for the row `i`
of the picked assistant, to their cards and back, as the detail of a task maps
the document of a result. A key edits the document there, and Ctrl+Z of the
window takes the edit back. A pick of another row takes a caret in a card out
of the detail. The toggles write `work_state` of the assistant.

`run_application` calls `unlink_assistant_list!` when its loop ends, so the list
of the session holds no document of a closed window.

The application puts an "Assistants" button with the icon `:chats` on the
toolbar, with the `tools` of the shell wrapper.

### The turn of an external agent

With `backend = :acp` the task of the turn runs `_run_external_agent_turn!` in place of `_run_agent_loop!`. The agent runs its own loop and its own tools, so the assistant builds no `Llm` and runs no `run_turn!`. [acp.md](../../adapter/acp/acp.md) describes the connection.

1. **The session starts at the first turn.** The package `ProjecturedACP` must be loaded; otherwise the turn shows an error that says `using ProjecturedACP`. The assistant splits `agent_command` into words (default `""`, which starts the built-in agent of `ProjecturedACP`), makes the connection with `make_agent_connection(:acp; command, directory = pwd(), session_meta = agent_session_meta)`, and keeps it in `agent_session`, an `ExternalAgentSession` with the connection, the `session_id` and the `tool_server`. The same connection serves the later turns. `agent_session` is no data: a save does not write it, and a duplicate does not share it. While the agent starts, the turn shows at once with one part, "Starting Claude Code…" (or "Starting the agent…" for an agent of `agent_command`); when the session is open, the turn leaves the conversation and comes back after the prompt, so a message that the person sends meanwhile stays above the answer, and a start that fails leaves no turn.
2. **The agent gets the tools of the editor.** When `:mcp` is among `get_agent_server_names()`, the assistant makes the MCP server with `port = 0`, `secret = true` and `DEFAULT_AGENT_INSTRUCTIONS` as its instructions, starts it, and gives `get_agent_server_access(server)` to `open_agent_session!`. The same text goes to `open_agent_session!` as `instructions`, which an agent adds to its system prompt. It says that the agent runs inside the editor of the person, that the MCP server controls that editor, and that a request about what the editor shows goes through its tools, not into source files or a worktree; then it gives the guide to the tools that the native assistant gets, without its rule against files and shell commands. The agent then calls `execute_julia_code` and the other tools with the secret, and each call runs on the editor task, so an edit is an operation and undo works. Without `ProjecturedMCP` the agent has its own tools only.
3. **The prompt is what the agent has not seen.** `ExternalAgentSession` counts the turns of the conversation that the agent saw, `sent_turn_count`. A new session starts the count at the last assistant turn, so a greeting or the note of a duplicate is not sent. `_make_external_agent_prompt` takes each user turn after that count and makes one `LlmText` block from it with `_make_user_turn_text`, and the count moves when `send_agent_prompt!` returns. So a turn that never reached the agent, as when the start of the session failed, is in the next prompt, and a turn that the agent got is never sent twice. A local evaluation (Alt+Return) is in the prompt as text.
4. **Each event becomes a part, or a change of the work.** Each event of the session goes into the queue of the session, and the feed of the window applies it on the editor task with `apply_agent_event!`; see "The work of an agent".

| Event | Part of the assistant turn |
| --- | --- |
| `LlmTextStart`…`LlmTextStop` | a prose part |
| `LlmThinkingStart`…`LlmThinkingStop` | a `ConversationThinking` part |
| `AgentToolCallUpdate` | one `EvaluatorForm` for each call `id`; later updates fill its input, its output and its failure; the prefix `mcp__projectured__` of a tool name is removed. The result of a tool of this editor is made as in a turn of a model: the document that an `execute_julia_code` call returned, which the MCP server kept under the id of the call, is the live result, and else the media type of the tool decides, so a documentation tool gives a Markdown page. The result of another tool is a document of its format when the update names the format, by `output_mime_type` or else by the extension of `output_uri`, and this editor has a parser for that format: the text of a Markdown file that the agent read is a Markdown page, and a Julia file is Julia code. Else the result, and an error, is its text. A `.pred` file writes a result that its notation can not write as the text of the tool |
| `AgentPlanUpdate` | one prose part for each plan id, which each update of that plan replaces: a checklist of the steps, or the Markdown text of the plan. A plan in a file and a removal change no part. The plan goes into the work as a `WorkPlan` too |
| `AgentSubagentUpdate`, `AgentBackgroundTaskUpdate`, `AgentNoticeUpdate`, `AgentCompactionUpdate` | no part of the turn: they go into the work of the agent. An event of a subagent fills the transcript of that subagent |
| `AgentPermissionRequest` | a `ConversationPermissionRequest` |
| `AgentSignInException` (thrown by the start of the session or by the prompt) | a `ConversationSignInRequest` in a turn of its own, in place of an error |
| `AgentQuestionRequest` | a `ConversationQuestionRequest`, a form in the turn; a question that nobody answered when the turn ends shows `"Cancelled"` |

A text or thinking block closes before a part of another kind comes, and text after it opens a new block.

**The permission card.** A `ConversationPermissionRequest` holds a title, the options of the agent, the `answer` and a `reply` function. The pane draws it as a card with one button for each option. A click calls `answer_permission_request!`, which sends the id of the option through `reply`, stores the name of the option, and disables the buttons. When `reply` answers `false`, the agent had its answer already from a cancel, and the request shows `"Cancelled"`. A request has one answer: a later call does nothing. A request that nobody answered when the turn ends gets the answer `"Cancelled"`. The `reply` is no data, so the duplicate of a request has none.

**The sign-in.** An agent that needs a sign-in is no fault: the turn ends, and a `ConversationSignInRequest` says how to sign in, with a button for each method that the agent gives. A button runs the command of the method in a `TerminalDocument` inside the card, where a person reads the URL and types or pastes the code. When the program ends with the status 0, the assistant starts the agent again with `StartExternalAgentOperation`. A program that a person stopped did not sign in, whatever its status, because `claude auth login` ends with 0 at Ctrl+C. "Try again" starts the agent again. A sign-in that a prompt of a resumed session needs keeps the session. The close of the tab of the assistant ends the programs of its sign-ins. The option bar has a "Sign out" item when the agent can sign out (`has_agent_sign_out`); `SignOutAgentOperation` calls `sign_out_agent!` on a task of its own, and a note says how it went.

**A stop cancels the turn of the agent.** `CancelAssistantTurnOperation`, from the Stop button or from Escape in the composer, sets `is_cancelled` of the session, and it calls `cancel_agent_prompt!` on a task of its own when the session is open. The agent stops, each waiting request is answered as cancelled, and the turn ends with `:cancelled`. A turn that is still starting its session sends no prompt. The end of the turn clears the flag. At any other time Escape reverts the draft.

**The assistant keeps its session.** When the agent answers a prompt, the assistant keeps the session: `agent_session_id` holds its id, `agent_session_directory` its folder, and `agent_session_turn_count` how many turns of the conversation it saw. A `.pred` file keeps them with the conversation. A turn that starts the agent gives the id and the folder to `open_agent_session!` as `session_id` and `directory`, so the agent resumes the session with its history, when the folder still exists and the agent can resume. A resumed session counts the turns that it saw from `agent_session_turn_count`, so the prompt holds each turn that it did not see. When the agent opens a new session in its place, the assistant forgets the kept session and its title, and a note says "The agent could not resume its session, so the next answer comes from a new session, which does not have the history above." When the first prompt after a resume fails, the agent does not have the session, as for a session in which it never answered; the assistant then drops the folder of the kept session, so the next turn opens a new session with that note. An answer that comes after a reset keeps no session.

**A stop keeps the session.** A turn that throws stops the connection, and the next turn starts the agent again and resumes the session. The count of the turns that the agent saw stays. The close of the tab of an assistant stops the agent and its MCP server: the close ends with `ReleaseDocumentOperation`, and the method of `release_document!` for an `Assistant` calls `stop_external_agent!`, which keeps the id, the folder and the title. An undo of the close brings the tab and its conversation back, and the next turn resumes the session, which holds the earlier turns. A reset of the conversation (`ResetConversationOperation`) stops the agent and forgets the session, so the next turn opens a new one.

**The options of the agent.** `agent_options` holds the options of the session as the agent last listed them, and it is no data. Under the composer, a row of menus (`make_agent_option_bar`) shows the model, the effort and the mode of the agent, in a height that the `option_bar_height` of the `ConversationTheme` gives. Each menu says the value that holds, and a pick evaluates `SetAgentOptionOperation(assistant, option_id, value)`, which calls `set_agent_option!` on a task of its own; the answer of the agent replaces `agent_options`. Before a session is open the row is one item, "Start the agent", which evaluates `StartExternalAgentOperation(assistant)`: it starts the agent and opens its session with no prompt, so the options show before the first message. A lock in the session makes a turn and a start open one session. A failed start shows in the conversation, as a failed turn does. A pick holds for the session; a new session starts with the values that the agent gives. The row is the third child of the split pane, so the maps of the transcript and the composer stay as they are.

**The title and the usage of the session.** `agent_title` holds the title that the agent gave its session, and `get_document_title` of the assistant answers it, or "Assistant" when there is none. The application opens the assistant in a tab with no name of its own, so the tab asks at each draw and shows the title of the session. A tab that the toolbar opens takes its name when it opens and keeps "Assistant". `agent_usage` holds the last `AgentUsageUpdate`, and a short line beside the option menus says it with `format_agent_usage`, as "36k / 1M", with the cost when the agent says. Its tooltip says it in words with `describe_agent_usage`, as "The session uses 36k of the 1M tokens of its context." The usage is no data, and the title is data only with a kept session; a reset and a duplicate start without them.

**The commands of the agent.** `agent_commands` holds the commands that the agent offers, and the last menu of the row, "Commands", lists them as `/name`, each with its description as the tooltip. A pick writes `/name ` into the draft with `ComposerInputOperation`, and the person completes and sends the command; the agent reads it at the start of the prompt. The agent gives its commands with the first prompt, so the menu shows from then on. A completion of `/` while the person types is not built.

**A duplicate starts a new session.** A copy of an assistant with a live `agent_session` or a kept session has `agent_session = nothing` and no kept session, so its first turn starts a new connection and a new session. It ends its conversation with the note "This copy talks to the agent in a new session. The agent does not have the history above."

### The work of an agent

The agent runs its own loop, and it reports more than text: the subagents that it starts, the plans that it keeps, the background tasks that it runs, and the process of its session. The assistant keeps this as documents in the field `agent_work`, so a person sees what the agent does, where it stands, what is done and what is left.

**The documents.**

- **`AgentWork`** is the work of one session, or of one subagent. It holds an `id`, a `title`, a `description`, a `state` (`:running`, `:idle`, `:requires_action` or `:unknown`), a `stop_reason`, the counts of tokens and tool calls and the duration, the time when the window saw it start to run (`start_time`), the last tool, a summary, `can_cancel`, the `plans`, the `background_tasks`, the `subagents` and the `notices`, and a `SystemProcessTree` in `processes` while the agent names a process. The work of the session of an assistant holds no title, state or usage of its own: the assistant holds those. A subagent holds its own.
- **A subagent has a transcript.** Its `conversation` is filled by the code that fills the transcript of the assistant. So a subagent shows its prompt, its text, its reasoning, its tool calls and its plan as the assistant does.
- **A plan is a `WorkPlan`** ([workplan.md](../workplan/workplan.md)), one for each plan id. A step keeps its document from one update to the next by its id, and only the changed fields are written, so a view keeps its open steps. The plan with the empty id has the title "Plan"; another plan has its id as its title. An entry with no id is named by its place. A removal takes the plan out.
- **A background task is a task.** `AgentBackgroundTask <: AbstractTask` is a kind of task that the agent runs and that this editor only watches. It sits in a `TaskDocument` of the task slice ([task.md](../task/task.md)), so its columns, its facts, its detail and its facets come from that slice. Its `TaskExecution` has no process: the events of the agent write its status, its times and its result. The first status starts the execution and registers it with the task feed. A status that ends the task (`:completed`, `:failed` or `:stopped`) ends it with an `AgentBackgroundTaskResult` of the code `DONE`, `ERROR` or `CANCEL`. A stop ends a task on purpose, so `CANCEL` is the expected code then, also when the agent ends; `ERROR` is unexpected. The task keeps the facts that the agent gave: the kind, the title, the tool call, the subagent, the output, the summary and `can_stop`. A task that ended can not be stopped.
- **The buttons of a background task.** Stop shows while `can_stop` holds. It finds the assistant whose session has the id of the task in the list of the assistants of its editor (`get_session_assistant_list(; editor)`), and calls `stop_agent_background_task!` as background work, on the default pool while the loop runs; a refusal is a notice "The agent did not stop …", which the work posts to the editor. "Open the output" shows when the agent names an output file, and evaluates `OpenFileOperation`.
- **A notice is an `AgentNotice`.** A compaction is a notice too, whose title says its status, such as "The context was compacted", with its summary as the description.
- **The process of the session** is a `SystemProcessTree` of the process id that `AgentSessionInfoUpdate` gives ([systemprocess.md](../systemprocess/systemprocess.md)).

**One queue for all events.** An event of a prompt goes into the `AgentEventQueue` of its session, behind the events that came before it, and the turn wakes the editor with `wake_editor!` and never waits for it. The feed applies the queue in the next frame. An editor whose loop does not run (`is_editor_loop_running`), as in a test, applies the queue at once on the task of the turn, as a call through its door runs at once there. The connection gives the events of a prompt to its `on_event` from the outbox of the prompt, with no lock held ([acp.md](../../adapter/acp/acp.md)). The start of a session makes its queue and posts its join to the feed, so the lock of the start holds no wait for the editor. An event between two prompts goes into the same queue, through the connection ([agent.md](../../kernel/agent.md)). So the events apply in the order in which they came, whether a prompt ran or not. `ExternalAgentSession` holds the queue in `events`, and the states of the turns: `prompt_turn`, `agent_turn`, `waiting_requests`, `subagent_turns` and `prompt_end_time`. It is no data, and a walk of the documents does not enter it.

**`apply_agent_event!(editor, assistant, event)`** applies one event, on the editor task. The text, the reasoning, the tool calls, the plans and the questions go into the transcript. The options, the usage, the title and the commands go into the fields of the assistant. The work of the agent goes into `agent_work`. The function takes the editor, because the forms of a tool call read their live results from `editor.tools` and a failed event is a fault of the editor. An event that fails to apply goes to the fault log, and the next event still applies.

**The feed of the window.** `AgentEventFeed` holds the queue of each session that the window opened. The assistant adds the feed to `editor.feeds` at the first session of the window, and a `TaskFeed` when the window has none, because the shadow of a background task syncs through it. Each drain applies the events in each queue, and samples each tree of processes that a view reads. A queue leaves the feed at the drain after its session closed. The window wakes four times a second while a subagent or a background task runs, and for five seconds after a prompt ends, because an agent reports more after its answer. It wakes for the next sample of a tree of processes that a view reads. Else it sleeps, so an idle window draws nothing.

**A turn that the agent starts by itself.** Claude Code starts a turn of its own when a background task or a background subagent ends after the answer to a prompt. A text, a reasoning, a tool call, a plan or a question between two prompts begins a new assistant turn in the conversation. The turn ends at the next prompt, or at the usage that the agent reports at its end, and its open blocks close. An event that only ends a block begins no turn. The start of a prompt applies the events that wait first, ends such a turn, and then makes the state of the prompt the one that takes the events. The end of a prompt applies the events that wait before it cancels the questions.

**The questions of the agent between two prompts.** A question of the session between two prompts is a card in the turn that the agent started by itself. It stays open after that turn ends, and the end of the next prompt cancels it when nobody answered.

**The wrapped request of a subagent.** A subagent can ask a permission or a question. The request is one request in two parts. One part is in the transcript of the subagent, and the end of the subagent cancels it. The other part is in the turn of the session that runs, where the person looks. Its title names the subagent: `The subagent “Explore” asks to run: …`. An answer in either part is the answer of both, and the reply goes to the agent once.

**The end of the work when a connection ends.** The agent may send nothing more when its connection ends, as when its process died. So the work of the session ends at once on the editor task when the agent stops (`stop_external_agent!`, also at the close of a tab and at a reset), when a turn fails or the connection stops, and when the start of the agent fails. Each background task that runs ends as `CANCEL` with the reason "The agent ended.". Each subagent that runs or waits for a person becomes idle with the stop reason `:cancelled`, and its turn ends. Every question that waits is cancelled, and a turn that the agent started by itself ends. After a failed prompt, this comes after the events of the prompt that still wait.

### The work page

`AssistantWork(assistant)` is a document that holds an assistant and shows its work, It is a page of a navigator. The Work button opens it in a tab, titled "Work · " and the title of the assistant. The page is a column of cards in a scroll pane of its own:

- **The job**: the title of the assistant and its first prompt. The plan of the plan mode, when the agent made one, follows in a card of its own.
- **Now**: the activity of the turn (`describe_assistant_activity`), the step that is in progress in the first plan with steps, with its active title, how long the turn runs, and how much of its context the session uses. The elapsed time reads the clock only while a turn runs.
- **The plans**: each other plan, with the view of a plan.
- **Work**: a `DocumentTree` of the session, its subagents and its background tasks, at every depth. The root is the page, with the text "This session".
- **Processes**: a `DocumentTree` of the processes of the session, or a line that says that the agent gives none.
- **Notices**: the notices of the agent, the newest first.

`subagents`, `background_tasks`, `plans` and `processes` of the page follow the work of the assistant, also when a new session starts. A path names a part of the work through them, such as `subagents[1]` or `subagents[1].background_tasks[2]`. So Parent on the page of a top-level subagent returns to the page. The page is opaque to the walk of the documents, as the list of the assistants is: a walk reaches the work once, through the tab of the assistant. A file keeps the assistant of the page and nothing of its work.

**The pages from a node.** A double click or Return on a node of a tree opens its item as a page in the navigator, and Back returns ([tree.md](../tree/tree.md)):

- **A subagent** shows its own page, `AgentWorkToWidget`: a header with its title, its type, its state and the time when it started while it runs, its tokens, tool calls and duration, its last tool and its summary, a block of its lines; Cancel while it runs and `can_cancel`; its plans; its transcript; and a link to each of its subagents and its background tasks. Cancel finds the assistant of the list of its editor whose work holds the subagent, and calls `cancel_agent_subagent!` as background work, as Stop of a background task does.
- **A background task** shows the page of a task, `TaskDocumentToWidgetPane` ([task.md](../task/task.md)): its facts, the buttons of its kind and its executions. The editor does not start it, so the page has no Run again and no Stop of its own; the Stop of its kind shows while the agent can stop it.
- **A process** and **a plan step** show the pages of their slices.

**The ways in.**

- A Work button in the option row of the tab of an assistant with `backend = :acp`, after the Picture button, with the icon `:list`.
- A Work button in each row of the Assistants pane, after Show.
- `show_assistant_work!(assistant; editor)` for code and for a model. It runs through `run_on_editor_task!`, so any task can call it. It shows the page that a tab of the window shows already, else opens `Navigator(AssistantWork(assistant))`, and answers the `AssistantWork` in its window. It finds that tab and builds the answered reference from the windows, their pane trees and the content of each tab, and walks no document, because a walk of the window compiles a method for each type of document that it meets and stalls the first press. The verb is declared to the assistant, and its system text names it.

**The three columns of the list.** The Assistants pane has the columns `plan`, `subagents` and `tasks`, after the usage of the context; `tasks` counts the background tasks, and its short name keeps the column narrow. They are facets of `Assistant` (`plan`, `subagents` and `background_tasks`), so a roster of assistants uses them as keys:

- `plan` is how far the first plan with steps is, as the completed steps over all its steps, such as `3/7`; empty without such a plan;
- `subagents` is how many subagents run, at every depth;
- `background_tasks` is how many background tasks of the agent and of its subagents run.

```julia
show_roster!(TabDocuments(Assistant); columns = ["title", "plan", "subagents", "background_tasks"])
show_roster!(ItemsWithin(TabDocuments(Assistant), TaskDocument); columns = ["name", "status", "within.title"])
```

The second call lists the background tasks of every assistant of the window.

### When a turn fails

- **No backend.** With `backend = :none` and no `llm`, a submit shows an error turn that names the backends whose packages are loaded.
- **No server, or no model on the server.** The error of the adapter shows in an error turn. A connection error names the address, and the Ollama adapter gives the `ollama pull` command for a model that the server does not have.
- **A tool throws.** The tool result carries the error text, the model gets it, and the form of the call is marked `is_error`.

### A copy and a save

A copy of an assistant is a fork: it has the conversation so far and a draft of its own, and it starts idle. A reply that streams stays with the original. `pred_arguments` saves only `backend`, `model`, `system`, `context` and `collapse_thinking`, and the `description`, the `comment` and the `work_state` that the person wrote, for every backend and only when they are not the defaults. A fork copies these three. A key is never written to a file. A command is never written either: a file that named the program of an external agent, or the options of its sessions, would start it at the next message, and a `.pred` file runs no code. So `agent_command` and `agent_session_meta` come from `StartSettings` of the application, and a loaded assistant starts with an empty conversation. An assistant with `backend = :acp` that keeps a session is the exception, because the agent holds the history of its conversation: its file also keeps the conversation, `agent_session_id`, `agent_session_directory`, `agent_session_turn_count` and `agent_title`, so the tab shows the conversation and its title after a load, and the next turn resumes the session. An id is no command and no credential, and the agent still comes from the settings. `accepts_pasted_document` and `accepts_opened_file` return `false`, so a paste or an opened file does not replace the assistant.

## How it fits

The assistant slice depends on the kernel and on the collection, conversation, domain, focus, graphics, layout, natural, navigator, pane, primitive, projection, roster, screen, serialization, style, systemprocess, task, terminal, text, tree, widget and workplan slices of `ProjecturedPlatform`. It loads after `task` and `navigator` and before `shell`. It must load after `task`, because `AgentBackgroundTask` is a subtype of `AbstractTask`, and after `navigator`, because `show_assistant_work!` makes a `Navigator`. The focus slice carries the selection of the Assistants pane down to a card of its detail. From the kernel it takes the `tool`, `llm` and `agent` layers, which [agent.md](../../kernel/agent.md) describes, and the `fault` layer. It does not depend on a backend package: a session loads `ProjecturedOllama` or `ProjecturedAnthropic`, which [ollama.md](../../adapter/ollama/ollama.md) and [anthropic.md](../../adapter/anthropic/anthropic.md) describe.

The shell slice puts an Assistant button on the toolbar, and the host gives the function that makes the assistant, with its backend and its greeting; see [shell.md](../shell/shell.md). The [application slice](../application/application.md) puts the explorer, the files and the assistant in one pane tree.

The package registers the natural row `:assistant` with `build_assistant_graphics_entry`: `Assistant => AssistantToWidgetSplitPane()`, and `AssistantList`, `AssistantWork` and `AgentWork`, each chained with `VerticalLayoutToGraphicsCanvas`, as the MCP log is. The views are `AssistantListToWidgetPane`, `AssistantWorkToWidget` and `AgentWorkToWidget`. It adds the methods `make_submit_operation(::Assistant)` and `make_evaluate_operation(::Assistant)` to the conversation package.

## Design decisions

- **A person names the backend, and a local model is the default.** Nothing guesses a backend, because a guess is right only while one backend exists. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The backend is built at each turn.** A document is built into a constant during precompilation, when no key exists, and a cached backend would keep the first model after a person changed `model`. The reasons are in the docstring of `Assistant` and in the comment on `_build_llm`.
- **The conversation is the one source of the prompt.** `messages` is a function, and not a list that the loop keeps, so the prompt can not differ from the transcript. See [plan/done/kernel-agent-stack.md](../../../../plan/done/kernel-agent-stack.md).
- **An evaluation that a person ran goes to the model as text.** A `tool_use` block would put a call into the history that the model did not make.
- **A tool gets the editor through `evaluate_operation(editor, operation)`.** The rejected options were an `editor` field on the assistant, an ambient `Ref`, task-local storage and a late-bound handler. See [plan/done/assistant-editor-reference.md](../../../../plan/done/assistant-editor-reference.md). The code that the tool runs passes no editor to a verb: `execute_julia_code!` binds the editor it gets as the editor of the evaluation, which the verb takes as the default of its `editor` keyword (PAR-PER-EDITOR-STATE).
- **The pane draws a result, and the model reads the text.** A Markdown page printed back is not the text it was read from, so the form keeps the text in `output`, as it keeps the call in `source`. The tool declares its media type, so the assistant keeps no list of tool names. See [plan/done/documentation-tool-results-as-markdown.md](../../../../plan/done/documentation-tool-results-as-markdown.md).
- **The work of an agent is documents, in the assistant.** A subagent, a plan and a background task are documents that the tree, the roster and the navigator already show, so the work page adds no view of its own for them. The three generic slices, [tree.md](../tree/tree.md), [workplan.md](../workplan/workplan.md) and [systemprocess.md](../systemprocess/systemprocess.md), name no agent.
- **One queue, one order.** The events of a prompt and the events between two prompts take the one path, so they apply in the order in which they came. The queue holds no editor, because a document must not hold the editor.
- **A background task is a task.** The task slice has the columns, the facets, the detail and the stop that a background task needs.
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
- Tests, in `test/projectured/editor/`: `test_assistant_mvp()` drives a whole turn with a scripted model, checks that Return and `SubmitProseOperation` while a turn streams send the message and that Alt+Return does nothing, that a message that waits gets a turn of its own, and checks that the writes of a turn and its tool call wait for the drain of the editor. `test_assistant_duplicate()` covers the fork, and `test_assistant_composer_panel()` covers the composer in the pane. `test_assistant_editor_reference()` and `test_assistant_turn_binds_meaning_model()` are in `McpTest.jl`, and `test_conversation_serialization()` covers `build_messages`.

## Limits

- **A tool call holds the documents, not the window.** A tool call of the model that reads a document runs as a code unit: the window shows the last picture and a busy bar, and keeps the keys for the frames after the call. A stop of the unit also cancels the turn that made the call. A search reads no document and runs on the task of the turn. The first search by description of a build can wait up to 30 seconds for the vectors of the meaning model.
- **A part that fails to apply does not end the turn.** A streamed part is posted and not waited for, so an exception while the drain applies it goes to the fault log of the editor, and the turn goes on.
- The view of an assistant draws `status` only through the Stop button, which is enabled only while a turn runs. The Assistants pane says whose turn it is and what the turn does.
- **The Assistants pane lists the assistants of the tabs of one window.** An assistant inside a layout or a card of a tab gets no row, and a window of another binary, which links no list, shows an empty list. [plan/done/a-table-shows-every-assistant-conversation.md](../../../../plan/done/a-table-shows-every-assistant-conversation.md) records the ways to fill a list that are not supported now.
- **The work of an agent is live state.** A file keeps no subagent, no plan of the work, no background task and no notice, so a window that loads shows the work page empty until the agent reports again.
- **Only an agent that sends the new updates shows its work.** Subagents, plans with an id, notices and compactions are unstable types of the protocol, and background tasks are an extension of it ([acp.md](../../adapter/acp/acp.md)). The built-in agent sends them. An agent that does not send them shows the plan of version 1 and the text.
- **No agent gives `:skipped` or `:deferred` for a plan step.** [workplan.md](../workplan/workplan.md) says why.
- A turn of a file written before the turns had times has a start and an end of `0.0`, so the pane shows no times for it.
- **A stop of a turn of a model waits for the next event.** A model that reads a long prompt sends no event for a while, and the stop takes effect only at its first event. A tool call that runs is not stopped, and the turn ends after it.
- `input`, `SubmitProseOperation`, `SubmitJuliaOperation`, `ClearInputOperation` and `ResetConversationOperation` are exported, but no printer shows `input` and no reader makes these operations. Only the tests call two of them. `SubmitProseOperation` does nothing while a turn streams, as Return does.
- The natural row gives a pane tab a widget and not graphics. A host that shows an assistant in a tab chains `AssistantToWidgetSplitPane` to `NaturalToGraphics` with the rows of the conversation, as `make_application_content_projections` of the [application slice](../application/application.md) does.
- The draft has no frame, no focus ring and no hint line. Stage 4 of [plan/pending/conversation-flat-transcript.md](../../../../plan/pending/conversation-flat-transcript.md) puts them on this pane, and they are not done.
- `DEFAULT_ASSISTANT_SYSTEM` is written for Claude and is long. A small local model can follow it less well, and [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md) keeps this as an open question.
- Tests of the work of an agent, in `test/platform/conversation/`: `test_agent_work()` applies the events of a scripted session: a subagent and its transcript, a subagent of a subagent, a plan with a blocked step, a background task that ends after the prompt, a notice and a compaction, the process of the session, a turn that the agent starts by itself, a live loop, a question of a subagent, a question between two prompts, the end of the connection, and the facets. `test_assistant_work()` runs in a real `Editor`: the work page, a double click on a subagent and on a background task with Back and Parent, the column `plan`, the Work button and the verb.
- Tests of the Assistants pane: `test_assistant_overview()` and `test_assistant_list()` in `test/platform/conversation/`, and two cases of `test_application()` in `test/projectured/editor/ApplicationTest.jl`, which press the toolbar button, Show, `›`, a key in the description and a toggle in a window.
- No test is marked `@test_broken`.
