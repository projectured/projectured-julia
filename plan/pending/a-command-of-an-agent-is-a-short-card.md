# A command of an agent is a short card

## The problem

When an external agent runs a command through the editor (Claude Code over ACP calls
its Bash tool), the conversation shows a tool card with the full page of the task in
its result part:

```
tool · mcp__claude_code_acp__Bash "cd ~/workspace/ghci-baseline-catch-up/inet && grep…"
  arguments
    command: cd ~/workspace/… (all of it)
    description: Find a generic drop statistic and the LMac baselines
  result
    DONE  bash -c cd ~/workspace/… (all of it)   T5
    [Stop] [Run again]
    command    bash -c cd ~/workspace/… (all of it)
    folder     /home/projectured/workspace/omnet-julia
    exit code  0
    Process    process 1566987, elapsed 0.8 s
    stdout …
```

- The command shows four times. Two of the four copies add `bash -c`, which the adapter
  adds to start the command.
- The header gives the internal tool name. `_remove_agent_tool_prefix` removes only
  `mcp__projectured__`.
- The description, the only line in plain words, is inside "arguments".
- The folder is the folder of the session, but the command goes to another folder with
  `cd`.
- Stop, Run again, the process number and exit code 0 are facts of the task list. They
  push the output, which is the important part, out of view.

## The decisions of the owner (2026-11-21)

1. The card of a command shows only the description as its header, with the state, the
   time and the row name such as `T5`; the command one time; and the output. Stop shows
   only while the command runs. The exit code shows only when it is not 0. All other
   facts stay on the task page, which a click on `T5` opens.
2. The card shows the last 8 lines of the output, the same as the task page. The line
   count is a link to all of the lines. While the command runs, the lines follow the
   end.
3. The header of every call of an external agent is the title that the agent sends. The
   tools of the editor keep the headers that the editor gives them, such as `eval` and
   `resource · <uri>`. Only the header changes. The "arguments" part stays.
4. A command is its own kind of part in the conversation. The assistant slice makes it
   and draws it. All other calls stay tool cards. The other choices were a second, short
   view of a task in the task slice, and a new edge from the conversation slice to the
   task slice.

The result:

```
▾ Find a generic drop statistic and the LMac baselines        DONE  0.8 s  T5
    $ cd ~/workspace/ghci-baseline-catch-up/inet && grep -n -E 'extends|like' …
    stdout · 14 lines
    …the last 8 lines…
```

## Facts

- `_show_agent_terminals!` (source/platform/assistant/AgentTerminal.jl) sets
  `form.result` to the `TaskDocument` of the terminal. The dispatch has one view of a
  `TaskDocument`, the page `TaskDocumentToWidgetPane` (TaskGroupToWidget.jl), so the
  card shows the full page.
- The conversation slice may not use the task slice (`PLATFORM_SLICE_EDGES` in
  test/platform/PlatformSuite.jl). The assistant slice may use both.
- `ConversationPartToWidget` draws a part whose content is no card kind as its content,
  with no frame. `ConversationPart.content` is a cell.
- The first event of a call makes an `EvaluatorForm`. The terminal comes later, in an
  update whose content names it.
- ACP gives each call a `title`. ClaudeCodeACP.jl `format_tool_title` sends the
  `description` of a Bash call as its title, else the command, and a title for each
  other tool: `Read <path>`, `Search for <pattern>`, `Fetch <url>`. The editor uses the
  title now only for a call that has no name. `get_evaluation_title` makes the header
  from the tool name and the first text argument.
- A `WidgetLink` whose target is a document opens its page in a new tab when no
  navigator is around the link.
- The task page builds the preview of a stream in `_build_stream_preview`
  (TaskPagesToWidget.jl): `stdout · N lines` as a link to the page of the stream, over
  the last `_STREAM_PREVIEW_LINES = 8` lines.
- `get_document_decoration(::TaskDocument)` gives the result code with its role and the
  time: the time it took, or `running since 12:03:04` while it runs. It reads no clock.
- The tree names a part through `format_tree_node_label` and marks it through
  `get_document_decoration`.
- `ReplaceConversationFoldOperation` writes a fold into any `ConversationDocument`.

## Proposed decisions (approved with the plan)

1. An `EvaluatorForm` keeps the title that the agent sent, in a new field `title`.
   `get_evaluation_title` answers it when it is not empty, else the rule of now. So the
   card, the tree label, the tooltip and the text of a conversation follow. A call of a
   tool of this editor (a name with the prefix `mcp__projectured__`) keeps no title.
2. The new part kind is `AgentCommand <: ConversationDocument`, and its view is
   `AgentCommandToWidget`, both in the assistant slice. Its fields: `title`, `command`,
   `task` (the `TaskDocument`), `tool_use_id` and `fold`.
3. The command that the card shows is the line that the agent wrote: the input field
   `command` of the call when it is a text, else the words of the terminal request. So
   the card shows no `bash -c`. When the title is the command itself, because the agent
   gave no description, the body does not show the command again.
4. The part becomes a command at the update that names the terminal. It keeps its place
   and its fold. A call that names more than one terminal makes a command of the first
   one.
5. After that, a new title of the call replaces the title of the command. The output
   text and the status of the call change nothing, because the task shows them.
6. The header shows the result code of the task in the color of its role (`DONE`,
   `ERROR`, `CANCEL`), or the state while it runs, then the time of the decoration of the
   task. An `ERROR` shows its reason under the header, such as `Non-zero exit code: 3`.
7. Stop calls `stop_task!` on the task, as the Stop of a task alone on the task page
   does.
8. `TaskModule` exports the builder of the stream preview. The task page and the command
   card both use it.
9. The default fold of the card follows the rule of the transcript, from the property
   `:conversation_fold` of the context, as a part does. A click on the chevron writes
   the choice into the `fold` of the command with `ReplaceConversationFoldOperation`.
10. The work line of a finished turn counts a command as a tool call. The conversation
    slice gets the function `is_conversation_tool_call(content)`, which is true for an
    `EvaluatorForm`, and the assistant slice answers it for a command.
11. The tree names a command by its title and gives it the decoration of its task.
12. `format_conversation` writes a command as `# <title>`, `$ <command>` and
    `= <result> <time> <row name>`.

## Not in this plan

- The title of the row of the task in the task list. It stays `bash -c …`.
- A caret or a copy in the text of the command card.
- The save of a conversation that holds a command. A task in the result of a call has
  the same limit now; [a-file-keeps-what-a-task-group-runs.md](a-file-keeps-what-a-task-group-runs.md)
  gives a task its file form.
- A time that counts up while a command runs.
- The cards of the tools of the editor, and the "arguments" part of other calls.

## Steps

1. ⬜ Tests that fail on main, in test/platform/conversation/AgentTerminalTest.jl and
   test/projectured/projection/ConversationTranscriptTest.jl. Each one renders the
   transcript and checks what it draws:
   - a call of an external agent with a title shows the title as its header and as its
     tree label; a call of a tool of the editor keeps `eval`;
   - a call that names a terminal shows the title, the state, the time, `T5`, the
     command one time and the last 8 lines, and no `bash -c`, Run again, folder or
     process;
   - Stop shows only while the command runs; an `ERROR` shows its reason;
   - a click on `T5` opens the task page in a new tab, and a click on the line count
     opens the page of the stream;
   - the work line of a finished turn counts the command as a tool call.
2. ⬜ The header from the title of the agent (proposed decision 1).
3. ⬜ `TaskModule` exports the builder of the stream preview, and the task page uses it
   (proposed decision 8). The task page does not change.
4. ⬜ `AgentCommand`, its view, the change of the part in `_show_agent_terminals!` and the
   updates after it (proposed decisions 2 to 7 and 9).
5. ⬜ The tree, the work line and the text of a conversation (proposed decisions 10 to
   12).
6. ⬜ A live check in the editor with Claude Code over ACP: a short command, a command
   that fails, and a long command that a person stops. Screenshots at density 1 and 2.
7. ⬜ The suites: the platform suites of the conversation, the assistant and the task,
   the ACP adapter suite, `test_application`, and the precompile and the assistant tests
   of omnet-julia. Main is green, so each failure that has no marker is a regression.
8. ⬜ A report to the owner, then the land on main after the owner approves it.
