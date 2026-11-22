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
  (TaskPagesToWidget.jl): a card titled `stdout · N lines`, with a button `Open stdout`
  to the page of the stream, over the last `_STREAM_PREVIEW_LINES = 8` lines. (Found in
  step 1: the plan said before that the count is the link.)
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
2. The new part kind is `AgentTerminalCommand <: ConversationDocument`, and its view is
   `AgentTerminalCommandToWidget`, both in the assistant slice. Its fields: `call` (the
   `EvaluatorForm` of the call, which the updates of the call keep filling), `task` (the
   `TaskDocument`, or `nothing` after a load), `command` and `fold`. Its title is the
   header of its call. (Changed in step 1, mine: the plan had the fields `title` and
   `tool_use_id`. The call keeps the input, the text that the call answered and the
   title, so the file form, the replay and the updates need no copy of them. Renamed in
   step 5: the plan had the name `AgentCommand`, which the kernel already gives a slash
   command of an agent (`AgentConnectionEvent.jl`); the two names in one module broke the
   command menu of the agent.)
3. The command that the card shows is the line that the agent wrote: the input field
   `command` of the call when it is a text, else the words of the terminal request. So
   the card shows no `bash -c`. When the title is the command itself, because the agent
   gave no description, the body does not show the command again.
4. The part becomes a command at the update that names the terminal. It keeps its place
   and its fold. A call that names more than one terminal makes a command of the first
   one.
5. After that, the updates of the call fill its form as before: a new title changes the
   header of the command. The result of the call stays the text that the call answered;
   the task is no longer the result of the call.
6. The header shows the result code of the task in the color of its role (`DONE`,
   `ERROR`, `CANCEL`), or the state while it runs, then the time of the decoration of the
   task. An `ERROR` shows its reason under the header, such as `Non-zero exit code: 3`.
7. Stop calls `stop_task!` on the task, as the Stop of a task alone on the task page
   does.
8. `TaskModule` exports `make_task_output_preview(document; …)`: for each stream of the
   current execution that has lines, a link `stdout · N lines` to the page of the
   stream, over its last 8 lines; a stream with no lines shows nothing. It follows the
   current execution. The task page and the preview share the builder of the last
   lines, so both show the same 8 lines; the task page keeps its card and its button.
9. The default fold of the card follows the rule of the transcript, from the property
   `:conversation_fold` of the context, as a part does. A click on the chevron writes
   the choice into the `fold` of the command with `ReplaceConversationFoldOperation`.
   (Found in step 5: the click works, the default does not. The turn gives the
   property only to the parts that it prints itself; a command is a document that the
   part embeds, which the layout prints later without it. So the card starts open
   when nobody chose a fold, also in an opened work line. The test keeps the rule as
   `@test_broken`. To make it reach the card, the transcript must print an embedded
   document with the context of its part, which changes every kind of part: a
   question to the owner.)
10. The work line of a finished turn counts a command as a tool call. The conversation
    slice gets the function `is_conversation_tool_call(content)`, which is true for an
    `EvaluatorForm`, and the assistant slice answers it for a command.
11. The tree names a command by its title and gives it the decoration of its task.
12. `format_conversation` writes a command as `# <title>`, `$ <command>` and
    `= <result> <time> <row name>`.

Found in step 1, decided by me (to report to the owner):

13. The file of an assistant of an external agent keeps its conversation
    (`pred_arguments(::Assistant)`), and the file form of a call writes a live result as
    the text that the call answered. So a command has a file form too: it writes its
    call, its command and its fold, and not the task. A load gives a command with no
    task: its card shows the title, the command and the last 8 lines of the text that
    the call answered, with no state, no row name and no link.
14. The replay of a conversation to a model of the editor reads a command as its call.
    `describe_assistant_activity` says `runs a command` for a command.

## Not in this plan

- The title of the row of the task in the task list. It stays `bash -c …`.
- A caret or a copy in the text of the command card.
- A time that counts up while a command runs.
- The cards of the tools of the editor, and the "arguments" part of other calls.

## Steps

1. ✅ Tests that fail on main, in test/platform/conversation/AgentTerminalTest.jl and
   test/platform/conversation/ExternalAgentTurnTest.jl. Each one renders the
   transcript and checks what it draws. On the code of main: `test_agent_terminal`
   3 failed and 3 errors (the card, the failure, Stop, and the first test that now asks
   for a command); the work line test passes on main too and stays as a guard;
   `test_external_agent_turn` 3 failed (the titles of Read and Grep). The test of the
   file form came after that run, and was not run on main.
   - a call of an external agent with a title shows the title as its header and as its
     tree label; a call of a tool of the editor keeps `eval`;
   - a call that names a terminal shows the title, the state, the time, `T5`, the
     command one time and the last 8 lines, and no `bash -c`, Run again, folder or
     process;
   - Stop shows only while the command runs; an `ERROR` shows its reason;
   - a click on `T5` opens the task page in a new tab, and a click on the line count
     opens the page of the stream;
   - the work line of a finished turn counts the command as a tool call;
   - a command written to a `.pred` file and read back shows its title, its command
     and the last lines of the text that the call answered.
2. ✅ The header from the title of the agent (proposed decision 1). `EvaluatorForm` has
   the field `title`, which its file writes when it is not empty; the header is the
   first line of the title, with `…` when more lines follow. `_find_agent_tool_title`
   in ExternalAgentTurn.jl gives no title to a call whose name has the prefix, or
   whose tool the tool set of the editor holds. `test_conversation_tree` 43 pass,
   `test_external_agent_turn` 363 pass.
3. ✅ `TaskModule` exports `make_task_output_preview`, and the task page shares its
   builder of the last lines (proposed decision 8). The task page does not change.
   The card also takes two parts of the task page, so they are public too:
   `make_task_state_badge` (was `_make_task_state_badge`) and `make_task_error_line`
   (was `_make_task_error_line(p, …)`, now with a `color` keyword); the count of lines
   is the public `TASK_PREVIEW_LINES` (was `_STREAM_PREVIEW_LINES`), which the card of a
   loaded command reads. `test_task_pages` 71 pass, `test_task_views` 168 pass.
4. ✅ `AgentTerminalCommand`, its view, the change of the part in `_show_agent_terminals!` and the
   updates after it (proposed decisions 2 to 7 and 9). Facts found: the row of the
   natural renderer chains `AgentTerminalCommandToWidget` with `VerticalLayoutToGraphicsCanvas`,
   as the page of a subagent does, because a bare view that answers a card has no
   canvas and draws nothing. A program task finds no error message, so the card shows
   the reason of an `ERROR` through `make_task_error_line(…; with_reason = true)`; the
   task page keeps that reason beside the name of the task. The time is written as the
   task page writes it (`0.8 s`). A press on the row or on the count of lines answers an
   `OpenPageOperation` of the task; the editor posts the new tab to its loop, which the
   test editor does not run, and the test editor can not draw an assistant in a tab, so
   the test checks the operation of the press. Run of `test_agent_terminal` before the
   last test change: every check of step 4 passes; the checks of step 5 fail.
5. ✅ The tree, the work line, the text of a conversation, the file form, the replay and
   the activity (proposed decisions 10 to 14). The type is now `AgentTerminalCommand`
   (see proposed decision 2), and the fold follows proposed decision 9 as far as it
   can. Runs: `test_agent_terminal` 72 pass, 1 broken (the default fold);
   `test_external_agent_turn` 363 pass; `test_conversation_tree` 43, `test_assistant_overview`
   69, `test_assistant_work` 133, `test_assistant_list` 62 and
   `test_conversation_transcript` pass (before the last fold change, which touches only
   the card of a command).
6. ⬜ A live check in the editor with Claude Code over ACP: a short command, a command
   that fails, and a long command that a person stops. Screenshots at density 1 and 2.
7. ⬜ The suites: the platform suites of the conversation, the assistant and the task,
   the ACP adapter suite, `test_application`, and the precompile and the assistant tests
   of omnet-julia. Main is green, so each failure that has no marker is a regression.
8. ⬜ A report to the owner, then the land on main after the owner approves it.
