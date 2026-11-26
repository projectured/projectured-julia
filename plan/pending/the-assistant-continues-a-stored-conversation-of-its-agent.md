# The assistant continues a stored conversation of its agent

> **Status (2026-11-25): approved, in work.** The owner asked for the design
> on 2026-11-25 and answered the five deciding questions in §4 the same day. The
> owner approved the plan for implementation on 2026-11-25 ("Yes, start it"), so
> the decisions in §5 are approved too.

## 1. The purpose

The owner, 2026-11-25: "in the projectured UI I would like to support continuing
existing Claude sessions using ACP. Analyize the problem and let's design
something. The goal is that other conversations create by for example VS Code
should be possible to continue in the omnet IDE."

An example. In VS Code, you talk to Claude about a NED file in the folder
`omnet-julia`. The conversation has the title "Fix the NED parser". The next
day, you start the omnet IDE and open the Assistants pane.

| | Now | With this plan |
| --- | --- | --- |
| The Assistants pane | one row for each open assistant tab | the same rows, and below them one row for each stored conversation of Claude Code, the newest first |
| A press of Show on "Fix the NED parser" | not possible | a new assistant tab opens and shows all turns of the conversation |
| Your next message in that tab | not possible | Claude answers with the whole history, and the turn goes into the same conversation file |
| The same conversation in VS Code later | not changed | shows the turns that you added in the IDE |
| VS Code still has the conversation open when you send | not possible | your message stays in the input field, and a note says "VS Code holds this conversation now. Close it there, and then send again." |

## 2. What works now

- **The assistant talks to Claude Code through ACP.** `ProjecturedACP`
  connects the assistant to an agent of the Agent Client Protocol (ACP). Its
  built-in agent is `ClaudeCodeACP.jl`, which starts one `claude -p` program for
  each session.
- **The assistant continues only its own conversations.** It keeps the id of
  the session of the agent in `agent_session_id`, and its `.pred` file keeps
  that id with a copy of the turns. At the next turn, `open_agent_session!` sends
  `session/resume`, and `ClaudeCodeACP` starts `claude -p --resume <id>`.
- **The Assistants pane lists only open tabs.** `AssistantList` reads the
  assistants of the tabs of the window. Each row is an `Assistant`, and its Show
  button focuses the tab.

## 3. The facts

1. **Claude Code keeps each conversation in one file.** The file is
   `~/.claude/projects/<folder>/<id>.jsonl`, with one JSON record on each line.
   `<folder>` is the folder in which `claude` ran, with each character that is
   not a letter or a digit replaced by `-`. A conversation of VS Code is a file
   of the same kind; its records hold `"entrypoint": "claude-vscode"`.
   `ClaudeCodeACP` already reads these files to fork a session
   (`find_claude_last_answer`, `src/agent.jl`).
2. **A file holds more than the turns.** The records of the main chain have the
   types `user`, `assistant`, `system` and `attachment`, and each names its
   parent with `parentUuid`. Other records hold the titles (`custom-title`,
   `ai-title`), the last prompt (`last-prompt`, with `leafUuid`), the file
   history and the requests to the API. A file branches: in one file of 2322
   records, 32 records have more than one child. A compaction starts a new
   chain: its record `compact_boundary` has no parent and names the record
   before it in `logicalParentUuid`. A subagent has a file of its own in
   `<id>/subagents/agent-<id>.jsonl`.
3. **Conversations are large.** Of the last 60 VS Code conversations of
   `projectured-julia`: a small one has 3 prompts, 27 tool calls and 2 MB; a
   middle one 21 prompts, 486 tool calls and 12 MB; the largest one 207
   prompts, 5391 tool calls, 26 compactions and 113 MB. In the largest one, 1023
   thinking blocks have text and 3718 have none.
4. **Many conversations, not all folders exist.** On this machine Claude Code
   keeps 146 conversations in 22 folders: 93 in `projectured-julia`, 23 in
   `omnet-julia`, 4 in `~/.cache/julia-work/projectured-julia`, and 26 in 19
   folders that are gone (tests, probes, removed worktrees). `claude` can not
   continue a conversation whose folder is gone.
5. **Claude Code records each running program.** `~/.claude/sessions/<pid>.json`
   holds `pid`, `sessionId`, `cwd`, `entrypoint`, `status` (`idle` or `busy`)
   and `procStart`. A record stays after its program ends: on 2026-11-25, 8 of
   43 records named a process that runs. The help of `claude` says that
   `claude --bg --resume <id>` "starts a copy and says so when the session is
   already running", so Claude Code uses this information itself. The file is
   internal to Claude Code and has no documentation.
6. **ACP has the two requests.** `session/list` (capability
   `sessionCapabilities.list`) answers `SessionInfo` values: `sessionId`, `cwd`,
   `title`, `updatedAt` and `_meta`, with a filter `cwd` and pages by `cursor`.
   `session/load` (capability `loadSession`) replays the whole history as
   `session/update` notifications before its answer. `AgentClientProtocol.jl`
   has all the types (`ListSessionsRequest`, `LoadSessionRequest`,
   `SessionInfo`, …), and `send_request!` sends any request. The schema 1.7.0
   marks neither request as unstable.
7. **`ClaudeCodeACP` can translate a stored record.** `translate_event!`
   (`src/translation.jl`) with `TurnState(; has_stream_events = false)` turns
   the text and the thinking of a whole `assistant` record into chunks, as it
   does for a subagent now. A `tool_use` always becomes a `tool_call`, and
   `_make_tool_result!` turns a `tool_result` into a `tool_call_update`, with a
   diff for an edit. Only `make_user_message_updates` makes a
   `user_message_chunk`. Now `ClaudeCodeACP` advertises `loadSession = false`
   and no `list`.
8. **`ProjecturedACP` drops a user message of its own session.**
   `_translate_subagent_prompt!` (`source/adapter/acp/AcpConnection.jl`) turns a
   `user_message_chunk` of a child session into `LlmMessage(:user, …)`, and
   drops it for a session that the client opened. So a message from the phone
   through Remote Control does not show now, although the README of
   `ClaudeCodeACP` says it does. An update that comes before the answer to an
   open request goes into `opening_events`, and `_register_session!` gives it to
   the queue of the session after the answer.
9. **The assistant makes no user turn from an event.** `apply_agent_event!`
   (`source/platform/assistant/AgentEventFeed.jl`) fills only turns of the role
   `:assistant`. A user turn comes from the draft.
10. **The tests have fakes for each side.** `ClaudeCodeACP` has a fake `claude`
    (`test/fake_claude.jl`) and a temporary `CLAUDE_CONFIG_DIR` in the test of
    `find_claude_last_answer`. `ProjecturedACP` has `FakeAcpAgent`
    (`test/adapter/acp/FakeAcpAgent.jl`), whose handler can send updates before
    it answers. The assistant has `ScriptedAgentConnection`
    (`test/platform/conversation/ExternalAgentTurnTest.jl`).
11. **`ProjecturedACP` gets `ClaudeCodeACP` by a path.** Its `[sources]` names
    `../../../ClaudeCodeACP.jl`, so a worktree of projectured-julia uses the main
    checkout of `ClaudeCodeACP.jl`. Its compat asks for 0.1.11.

## 4. The deciding questions and the answers of the owner

Each recommendation was the assistant's, and the owner agreed with it on
2026-11-25.

- **D1. The IDE continues the same conversation, not a copy.** The IDE adds its
  turns to the file of the conversation, so VS Code shows them later. The owner:
  "I agree, the same conversation". A copy, "Continue as a copy", can come later
  as a separate action, because `session/fork` exists.
- **D2. The tab shows all old turns.** The agent sends them with
  `session/load`. The owner: "I agree, it's A". Rejected: a note only. "Only the
  last 20 turns" was not offered, because a view does not cut a list.
- **D3. The Assistants pane lists the stored conversations below the open
  tabs.** A Show on a stored row opens an assistant tab, and the row moves up to
  the open rows. The owner: "I agree, it's A". Rejected: a list of its own, and
  a menu that you type into.
- **D4. The pane lists the conversations of all folders that exist.** A column
  shows the folder, and the newest conversation comes first. The owner: "I
  agree, it's B". Rejected: only the folders of the window, and only the folder
  that the window opened on.
- **D5. One writer at a time.** When another program holds the conversation,
  the IDE does not send. Your message stays in the input field, and a note says
  "VS Code holds this conversation now. Close it there, and then send again."
  The row also says that VS Code has it open. The owner: "I agree, it's B".
  Rejected: a warning only, and no check.

## 5. The decisions

All decisions are proposed by the assistant.

- **P1. The agent lists and loads; the editor reads no file of Claude Code.**
  Rejected: the platform reads `~/.claude/projects`. The editor talks ACP to
  any agent, and the agent owns its history.
- **P2. The agent connection gets two verbs and one value.**
  `list_agent_sessions(connection; directory = nothing) -> Vector{AgentSessionInfo}`
  answers the stored sessions of the agent; the default answers none.
  `load_agent_session!(connection; session_id, directory, mcp_servers, instructions, on_event, events)`
  opens a stored session and puts its history on `events` before it answers
  the id, or answers `nothing` when the agent can not load; the default answers
  `nothing`. `AgentSessionInfo` holds `id`, `directory`, `title`,
  `last_prompt`, `updated_at` and `holder`, the name of the program that holds
  the session now, empty for none. Rejected: a keyword `load` of
  `open_agent_session!`. The caller must know whether the history came, as for
  a fork.
- **P3. A user message of the session is the event `LlmMessage(:user, …)`.** It
  is the value that a child session gives now for the prompt of its subagent,
  so the kernel gets no new event type. In `ProjecturedACP`, a
  `user_message_chunk` of a session that the client opened becomes this event
  whenever no prompt of the client runs in that session; during a prompt of the
  client it stays dropped. So the replay of a load shows the prompts, and a
  message from the phone shows too, as the README of `ClaudeCodeACP` says. The
  assistant ends the open turn of the agent and adds a user turn. Rejected: a
  rule only for a load, which is a special case of the same thing.
- **P4. The replayed turns have no times.** The columns "started" and
  "elapsed" of the pane count from the first turn after the open. Rejected: the
  time of each record in the `_meta` of each update, which is a new payload of
  every event of the kernel.
- **P5. The file of Claude Code is the one source of the history.** The `.pred`
  file of an assistant with the backend `:acp` keeps the id, the folder and the
  title of its session, and no turns. An assistant that keeps a session and
  shows none of its turns loads the session when it starts its agent; one that
  shows them resumes it, as after a stop of its connection. When the agent can
  not load, the assistant resumes, and a note says "The agent can not send the
  earlier turns of this conversation, so they are not shown. The agent still has
  them." Rejected: a copy of the turns in the `.pred` file. The copy goes stale
  when VS Code adds turns.
- **P6. A load in `ClaudeCodeACP` starts no `claude`.** The first prompt or the
  first change of an option starts it with `--resume`. Rejected: a start at the
  load, as a resume does. A window with five assistant tabs from its file would
  start five `claude` programs that nobody uses.
- **P7. The replay follows one chain.** It starts at the record that `claude
  --resume` continues, and goes back by `parentUuid` to the first record, and
  across each compaction by `logicalParentUuid`. Step 1 finds which record
  `claude --resume` continues. The replay sends, in the order of the chain:
  - the text of each prompt of a person as a `user_message_chunk`, but not a
    record that Claude Code marks as meta, a summary of a compaction, or a
    `user` record that holds only tool results;
  - the text and the thinking with text of each `assistant` record as chunks,
    and each `tool_use` as a `tool_call`, through `translate_event!` with
    `TurnState(; has_stream_events = false)`;
  - each `tool_result` as a `tool_call_update`, through `_make_tool_result!`;
  - each compaction as a `compaction_update`, to an editor that takes it.

  It leaves out the other records. A subagent shows as its tool call and its
  result; its own file is not replayed. Rejected: a replay of each subagent as
  a child session, which is more work and can be a later plan.
- **P8. The list in `ClaudeCodeACP`.** It lists each file
  `projects/*/<id>.jsonl` that holds a prompt of a person and whose folder
  exists. The folder is the `cwd` of the first record that has one. The title is
  the last `custom-title`, else the last `ai-title`, else the first prompt.
  `updatedAt` is the time of the last change of the file. `_meta.claudeCode`
  holds `lastPrompt` and `heldBy`. The order is the newest first, in pages of
  100. The agent reads the start of a file for the folder and the end for the
  title and the last prompt, so a file of 113 MB costs no full read. Step 2
  measures a list of the 146 files of this machine.
- **P9. A program holds a conversation when it runs.** A record
  `sessions/<pid>.json` names the id, its process runs, and its `procStart`
  matches the start of that process, so a process id that the system gave again
  does not count. The agent does not count its own `claude` programs. The name
  of the program comes from `entrypoint`: `claude-vscode` gives "VS Code", and
  step 1 finds the names of the other entry points.
- **P10. The agent checks at each prompt (D5).** Before `ClaudeCodeACP` gives a
  prompt to `claude`, it refuses the prompt in two cases:
  - another program holds the conversation;
  - the file has an answer that this session did not see, because another
    program wrote after the load or after the last turn of this session. The
    next prompt then starts `claude` again with `--resume`, because the history
    in the running `claude` is old.

  The error answer names the program and says whether it is open.
  `ProjecturedACP` turns it into `AgentSessionConflictException(program, is_open)`.
  The assistant takes the user turn out, puts its text back into the input
  field, and shows a note. For an open program: "VS Code holds this conversation
  now. Close it there, and then send again." For a program that wrote and
  ended, the assistant first loads the conversation again, so the tab shows the
  new turns: "VS Code added turns to this conversation. They show above now.
  Send again." Rejected: a check in the editor before the send, which reads a
  file of Claude Code against P1.
- **P11. The Assistants pane shows stored rows.** A stored row is an
  `AgentSessionInfo`. The rows of the open tabs come first, then the stored
  rows, the newest first. A stored row whose id an open assistant keeps is left
  out, so a Show moves the row up. Two new columns are for every row: "folder"
  and "changed". The activity column of a stored row says "open in VS Code"
  when a program holds it. Show on a stored row opens a new assistant tab that
  keeps that session; its acquire starts the agent, which loads it. The pane
  reads the stored rows on a task when it is acquired, and again at a press of
  a new button "Refresh". Rejected: a read at each draw, because a reader reads
  no disk.
- **P12. The pane gets its agent from the factory of the window.** The wrapper
  `assistant_list` reads the factory of assistants that the `shell` wrapper
  has, in `parts.arguments`, as the `shell` wrapper reads which tools record.
  The list makes its own connection with the `agent_command` and the
  `agent_session_meta` of an assistant of the factory, and the factory makes
  the assistant of a stored row. The connection of the list is live state, not
  data, and the stop step of the wrapper stops it. A window whose assistant has
  no backend `:acp` shows no stored rows. So the omnet IDE needs no change.
  Rejected: a new option of the wrapper with the agent settings, which is a
  second place that must agree with the factory.
- **P13. `ClaudeCodeACP` becomes 0.1.12, and `ProjecturedACP` asks for it.**
  The change adds requests and removes no export.

## 6. The steps

The work is in two repositories, each in its own worktree:

- ClaudeCodeACP.jl: the branch `session-list-and-load` in the worktree
  `ClaudeCodeACP.jl-session-list-and-load`.
- projectured-julia: the branch `continue-stored-conversation`, made with
  `workspace/bin/julia-worktree`.

Fact 11 sets the order: `ClaudeCodeACP` lands first, after the approval of the
owner, so that the live check of step 9 runs the new agent. Steps 5 to 8 use the
fakes and do not wait for that land.

1. [x] **Find the facts that only `claude` can give.** Done 2026-11-25, see the
   answers below. In a folder of the
   scratchpad, with short prompts, and with no change of code:
   - which record `claude -p --resume <id>` continues in a file with two
     branches (make the branch with `--resume-session-at` and no
     `--fork-session`);
   - what `claude -p --resume <id>` does while another `claude -p` holds `<id>`;
   - the `entrypoint` of a `claude -p` and of a `claude` in a terminal;
   - whether the error of a request in `AgentClientProtocol.jl` carries `data`.

   Record the answers in this plan.

   The answers, with `claude` 2.1.309, `--model haiku`, in the folder
   `resume-probe` of the scratchpad:
   - **`claude --resume` continues the leaf of the last `last-prompt` record.**
     A file with the chain ALPHA → BRAVO and the branch ALPHA → CHARLIE (made
     later with `--resume-session-at`) continued at CHARLIE, which is also the
     last leaf of the file. A copy of the same file with one more `last-prompt`
     record whose `leafUuid` names the BRAVO answer continued at BRAVO: the
     answer listed "ALPHA BRAVO". So the replay starts at the `leafUuid` of the
     last `last-prompt` record. A file with no such record starts at its last
     `user` or `assistant` record. A `leafUuid` can name an `attachment`, whose
     `parentUuid` leads back to the chain.
   - **A second `claude -p --resume <id>` does not refuse** while another
     `claude -p` holds `<id>`. It answers with exit code 0 and writes into the
     same file. So two programs can mix one file, and only the check of P10
     stops that.
   - **The record of a program.** A `claude -p` that waits on its input writes
     `~/.claude/sessions/<pid>.json` with `"kind": "interactive"`,
     `"entrypoint": "sdk-cli"`, `"status": "idle"` and `procStart`, which is
     field 22 of `/proc/<pid>/stat` (the start time in clock ticks after the
     boot). A program that ends normally removes its record; a record stays only
     after a kill or a crash.
   - **The entry point comes from the environment.** A `claude` takes
     `CLAUDE_CODE_ENTRYPOINT` from its parent: a `claude -p` started from a
     terminal of VS Code writes `claude-vscode`. So the agent finds its own
     programs by their process ids, never by the entry point (P9). With a clean
     environment, a `claude -p` writes `sdk-cli`. On this machine, the 44
     records hold only `claude-vscode` (42) and `sdk-cli` (2), and the first
     records of the 149 files hold the same two names. A terminal `claude` under
     `script` wrote no record in 12 s, so its name stays unknown. The name of a
     program is "VS Code" for `claude-vscode` and "Claude Code" for each other
     entry point.
   - **An error answer carries `data`.** `send_request!` of
     `AgentClientProtocol.jl` throws `ProtocolException(code, message, data)`
     with the `data` of the answer, and a handler that throws a
     `ProtocolException` with `data` sends it. `RESOURCE_NOT_FOUND` (-32002)
     exists.
2. [x] **`ClaudeCodeACP` answers `session/list`** (P8, P9). Test with a
   temporary `CLAUDE_CONFIG_DIR`: a folder that exists and one that is gone, the
   three sources of a title, the order, two pages, a record of a process that
   runs (the test process) and of one that ended, a record of an own `claude`.
   Measure the time of a list of this machine once, and record it with what it
   measures.
3. [x] **`ClaudeCodeACP` answers `session/load`** (P6, P7). Test with stored
   files: a branch, a compaction, an edit with its diff, a meta prompt, a
   thinking with no text, the updates before the answer in the order of the
   chain, no `claude` at the load, `--resume` at the first prompt, and
   `RESOURCE_NOT_FOUND` for a session with no file.
4. [x] **`ClaudeCodeACP` checks at each prompt** (P10). Test: a held
   conversation gives the error with the program; a conversation that another
   program changed gives the error, and the next prompt starts `claude` again
   with `--resume`; an own `claude` does not count. Update the README. The
   version becomes 0.1.12. Then report and ask the owner to approve the land of
   `ClaudeCodeACP`.

   Steps 2 to 4 done 2026-11-25 on the branch `session-list-and-load` of
   `ClaudeCodeACP.jl`, in one commit for the code and the tests (9b383a4) and
   one for the README (12541cf), because the check needs the load and the list
   in its tests. 482 tests pass, 78 of them new. The land waits for the
   approval of the owner. What the work found and decided:
   - **A new file `src/history.jl`** holds the readers: `find_claude_conversations`,
     `read_conversation_title`, `find_conversation_chain`,
     `foreach_conversation_record`, `make_replay_updates!`, `find_claude_holders`,
     `find_last_answer_record` and `foreach_line_backward`.
     `find_claude_last_answer` of the fork reads the file from its end now.
   - **A prompt of a person** is a `user` record with text that is not of a
     subagent, not meta, not the summary of a compaction, whose `origin` is none
     or `{"kind": "human"}` (a task notification has
     `{"kind": "task-notification"}`, a message of another session
     `{"kind": "peer"}`), and whose text does not start with `<command-name>`,
     `<command-message>`, `<local-command-` or `[Request interrupted by user`.
     A survey of the 95175 `user` records of this machine gave these forms.
   - **The list reads at most the first 1 MiB of a file** for the folder and the
     first prompt (the first `user` record of each of the 149 files comes in its
     first 1797 bytes), and **its end in blocks of 64 KiB** for the titles and the
     last prompt. `claude` writes `custom-title`, `ai-title` and `last-prompt`
     again after each turn: 37519, 35848 and 40052 such records in 149 files,
     the last one of each at most 34 KB before the end of its file. A file whose
     start has no prompt of a person counts when its end has a `last-prompt`.
   - **The time of the list**, measured in one job of 2 cores with the files of
     this machine in the cache of the system: 123 of the 149 files are listed;
     the first list in a new process takes 1.63 s, compilation included, and a
     second list 0.035 s.
   - **The time of the replay** of the largest file (110.5 MB): its chain of 24619
     records takes 0.43 s, and the translation of the chain into 13575 updates
     (219 prompts, 26 compactions) 1.59 s, without the send. The second largest
     (109.8 MB): 13509 records in 0.21 s, 6663 updates in 0.39 s.
   - **P6 changed in one detail:** only the first prompt starts `claude` after a
     load. A change of an option before it changes only the flags of that start,
     as the handler of the options did before.
   - **The check of P10.** The session keeps `last_answer_uuid`: the last answer
     in the file at a load or a resume, then the uuid of each answer event of
     its own `claude`, which is the uuid of the record in the file (checked
     with the real `claude`). Before a prompt, the agent reads the last answer
     of the file from its end. Another uuid is an answer of another program,
     and its `entrypoint` names that program. Two cases count as no conflict: a
     session that knows no answer yet takes the answer of the file as known, so
     a `claude` that gives no uuid can not refuse each prompt; and while a turn
     runs in the own `claude`, only the holder counts, because the file can hold
     the answer before its event comes.
   - **The error** has the code `INVALID_REQUEST`, as "A prompt runs in this
     session" has, and `data.claudeCode = {heldBy, isOpen}`.
   - **An own `claude`** is a process of the agent, or a child of one up to 4
     parents, so a `claude` command that is a script still counts as own. A
     test fake gets the process id of the test process for this; it has no
     `Base.Process`, so no signal goes to that id.
   - **The tests use a configuration of their own:** `runtests.jl` sets
     `CLAUDE_CONFIG_DIR` to an empty temporary folder, so no test reads the
     files of the person.
   - **`Dates`** is a new dependency of `ClaudeCodeACP`, for the time of a row
     in ISO 8601. It is a standard library.
5. [x] **The kernel gets the verbs** (P2). `AgentSessionInfo`,
   `list_agent_sessions`, `load_agent_session!` and
   `AgentSessionConflictException` in `source/kernel/agent/`, with their
   defaults. Update [agent.md](../../documentation/package/kernel/agent.md).
   Test: `test_kernel(only = "agent")`.
6. [x] **`ProjecturedACP` lists, loads and refuses** (P2, P3, P10). The list
   reads every page. The load sends `session/load` when the agent advertises
   `loadSession`, and the replay goes to `events` as the updates of an open do
   now. A `user_message_chunk` outside a prompt of the client becomes
   `LlmMessage(:user, …)`. The error of P10 becomes the exception. Update
   [acp.md](../../documentation/package/adapter/acp/acp.md). Test with
   `FakeAcpAgent`.
7. [x] **The assistant shows a loaded conversation** (P3, P5, P10). A user
   message event adds a user turn. The start of the agent loads or resumes by
   the rule of P5. The `.pred` file keeps no turns. The exception puts the text
   back into the input field and shows the note. Update
   [assistant.md](../../documentation/package/platform/assistant/assistant.md).
   Test with `ScriptedAgentConnection`.
8. [x] **The Assistants pane shows the stored rows** (P11, P12). Test: the
   order of the rows, the new columns, a row left out while a tab keeps its id,
   Show opens a tab that loads, Refresh reads again, and a window with no
   `:acp` assistant shows no stored rows. Update
   [assistant.md](../../documentation/package/platform/assistant/assistant.md).
   Step 5: `test_kernel(only = "agent")` gives 4 parts, 140 pass, 0 fail.
   Step 6: `test_acp()` gives 4 parts, 378 pass, 0 fail.
   Steps 7 and 8: the parts `test_external_agent_turn`, `test_assistant_list`
   and `test_assistant_work` of `test_platform` give 607 pass, 0 fail, and the
   other parts of the assistant (`assistant`, `composer`, `draft`) pass too.

   What steps 5 to 8 found and decided, 2026-11-25:
   - **No new dependency.** A first version used `Dates` in `ClaudeCodeACP` and
     `ProjecturedACP` for the time of a row. The checked-in
     `environment/all/Manifest.toml` lists the dependencies of `ClaudeCodeACP`,
     so the land of `ClaudeCodeACP` with `Dates` would break the load of main
     until a new resolve. Both packages compute the date in the Gregorian
     calendar instead (`format_utc_time`, `_read_iso_time`).
   - **The compat of `ProjecturedACP` changes at step 9.** Its `[sources]` path
     names the main checkout of `ClaudeCodeACP`, which is 0.1.11 until the land,
     so the compat 0.1.12 comes after that land. The fakes of steps 5 to 8 need
     no new agent.
   - **A replayed prompt is one `user_message_chunk`** with its blocks of text
     joined, so the editor, which makes one `LlmMessage` of each chunk, makes one
     user turn of it.
   - **The history waits in a queue of its own.** The load gives its events into
     a queue that joins the feed of the window only after
     `_apply_agent_history!` applied them on the editor task. The start posts
     that call, and the next prompt runs it first, so the history comes before a
     message that the person sent while it loaded.
   - **A turn that comes from the agent between two prompts goes after the
     turns that it saw**, before the first user turn that it did not see
     (`_insert_agent_turn!`), and counts as seen. This holds for the history, a
     message from the phone and a turn that the agent starts by itself.
   - **The prompt reads the conversation in the same call** on the editor task
     in which the events before it apply (`_start_agent_prompt_turn!` calls
     `_read_agent_prompt!`). Before, the prompt read the conversation in one
     call and applied the waiting events in the next, so a turn of the agent
     that came between them shifted the count of the seen turns.
   - **After the history, `agent_session_turn_count` holds the turns that the
     session saw**, so a start again resumes and does not load a second time.
   - **The refused message goes back as its parts**, with the new
     `prepend_draft_parts!` of `ConversationModule`, before what the person
     wrote since.
   - **Show on a stored row makes a new assistant with the settings of an
     assistant of the factory**, because a factory of the omnet IDE
     (`_make_assistant_factory(assistant)`) answers the same assistant at each
     call. A stored row that no program holds says "stored" in the column of the
     activity.
   - **A list that a tab shows at the start of the window reads its stored
     sessions in the start step** of the wrapper, because it gets its factory
     only there.

9. [ ] **The live check in the omnet IDE**, with the real agent and the real
   conversations of this machine:
   - the pane lists them, and their titles and folders are right;
   - a small VS Code conversation opens and shows its turns; no message is sent
     to it;
   - the time and the memory of the open of the middle conversation (fact 3) and
     of the largest one, recorded with what they measure;
   - a send in a conversation that a `claude -p` in the scratchpad made adds the
     turn to its file;
   - the note of D5 while a second `claude -p` holds that conversation.

   Then ask the owner to check by hand that VS Code shows the turns that the IDE
   added (D1), because no tool here drives VS Code.

   **A check before the land, 2026-11-25.** `julia-worktree` mounts only the
   worktrees of projectured-julia and omnet-julia, so the IDE gets the new agent
   only after its land. Before it, `ProjecturedACP` ran the new agent as a child
   process (`command = julia --project=<the agent worktree> -e "serve_agent()"`)
   in a job of 2 cores and no network, with the real files of this machine, in
   the cache of the system, and sent no prompt to Claude:
   - the start of the agent took 28.84 s, its compilation included;
   - the list gave 123 conversations in 1.28 s (the first list of the process),
     and in 0.15 s the second time; 9 are held, among them this session by
     VS Code and the probe of step 1 by its waiting `claude -p`;
   - the load of a conversation of 10.7 MB took 3.91 s, the first load of the
     process, its compilation included, and gave 1426 events (842 tool call
     updates, 7 prompts); the editor process held them in 1.2 MiB
     (`Base.summarysize` of the events), its live heap grew by 2.5 MiB;
   - the load of the largest conversation (110.5 MB) took 0.88 s and gave 19549
     events (10774 tool call updates, 207 prompts), held in 17.3 MiB; the live
     heap of the editor process grew by 27.9 MiB, and its peak resident memory
     was 0.53 GiB; this measures no drawing of the turns;
   - a prompt in the probe conversation, which a waiting `claude -p` held, was
     refused before the agent started `claude`: `AgentSessionConflictException`
     with the program "Claude Code" and `is_open`.
10. [ ] **The land.** Run all parts as "Main is green" in `CLAUDE.md` says, and
    the fast parts of omnet-julia against the branch. Report, and ask the owner
    to approve the land. After the land, record the test calls again, remove the
    worktrees, their depots and their branches, and move this plan to
    `plan/done/`.

## 7. The limits

- The files of Claude Code are internal. A change of their format can stop the
  list, the load and the check of P10. The fork of a session depends on them
  already.
- A thinking with no text in the file does not show (fact 3).
- A subagent shows as one tool call (P7).
- A conversation of another folder continues in that folder, so Claude works
  there, and not in the folder of the window.
- A resume, which an assistant that shows its turns sends after a stop of its
  connection, takes the last answer in the file at the resume as known. Turns
  that another program added while the connection was stopped then do not show
  until a load.
- Step 9 measures the open of the largest conversation. If it is too slow or
  too large, this plan records the numbers, and the memory of a long transcript
  goes to a plan of its own, because the memory of a long list is one question
  for every list.

## 8. Not in this plan

- "Continue as a copy" (D1).
- The delete of a stored conversation, which ACP offers with
  `sessionCapabilities.delete`.
- A replay of subagents as child sessions (P7).
- The times of the replayed turns (P4).

## 9. Progress

- 2026-11-25: the owner answered D1 to D5, and approved the plan.
- 2026-11-26: steps 1 to 8 done. The fast parts that the changes since main
  reach (`--changed main --level fast ProjecturedTest test_all`, 686 parts) gave
  79782 pass, 8 fail, 1 error, 633 broken, in four parts:
  - `test_exports` (2 fail: `GestureModule.jl` names out of the order of
    `MouseGesture.jl`), `test_documentation` (3 fail: `dragtracking.md` and
    `pane.md` link to a plan that moved to `plan/done/`) and `test_scroll_work`
    (1 fail: the Files pane makes 13 guards in a notch, the bound is 12) fail on
    main too: the branch changes none of their files, and the stored records
    of two other branches of 2026-11-25 hold the same counts.
  - `test_semantic_tokens` (2 fail, 1 error: a `clangd` that the test ends
    with SIGTERM still runs after 10 s) failed twice in the test session, and
    passed in the records of the other branches. The branch changes nothing of
    the language server; a run in fresh workers found no room in the memory
    budget. Step 10 runs it again.
- The land of `ClaudeCodeACP` waits for the approval of the owner, and step 9
  waits for that land.
