# The duplicate of an assistant starts from the same context

> **Status (2026-11-11): in progress, step 2; step 1 is done.** The owner asked for this plan
> on 2026-11-11 and approved it for implementation the same day ("Implement the
> plan"). The decisions in §5 were proposed by the assistant and approved with
> the plan on 2026-11-11.

## 1. The purpose

The owner, 2026-11-11: "I would like to change the duplication of assistant
pane in projectured to make a new assistant which starts from the same context
as the original one. They should share state if that's possible to avoid
unnecessarily duplicating everything, but if it's not then let's just
duplicate. In any case the current behavior isn't very useful."

## 2. What a duplicate does now

An assistant talks to one of two kinds of backend.

- **A model that the editor drives** (`:anthropic`, `:ollama` and the other
  backends of the built-in loop). The editor sends the whole transcript at each
  turn (`build_messages`). The duplicate copies the transcript, so its model
  already starts from the same context. This plan does not change it.
- **An external agent** (`:acp`, by default Claude Code through the built-in
  agent `ClaudeCodeACP`). The agent keeps the history in its session, and the
  editor sends only the new messages. The duplicate copies the transcript, but
  its first turn opens a new session. So the agent of the copy does not know the
  conversation that the copy shows. A note at the end of the copy says so: "This
  copy talks to the agent in a new session. The agent does not have the history
  above."

An example. The assistant `A1` holds this conversation, and its agent keeps it
in the session `S`:

| Turn | Role | Text |
| --- | --- | --- |
| 1 | user | "Read parser.jl and find why `1+` gives no error." |
| 2 | assistant | (reads the file with its tools) "The reader stops at the operator, …" |

The person duplicates the tab and asks the copy `A2`: "Write a test for it."

| | Now | With this plan |
| --- | --- | --- |
| The session of `A2` | a new session `N`, empty | a new session `N` that the agent copied from `S` |
| What the agent of `A2` knows | only "Write a test for it." | turns 1 and 2, the file that it read, and "Write a test for it." |
| The answer of `A2` | asks which test the person means | writes a test for `1+` |
| The note in `A2` | "This copy talks to the agent in a new session. …" | none |
| The session of `A1` | `S`, unchanged | `S`, unchanged |

## 3. The facts

1. The Agent Client Protocol (ACP) has the request `session/fork`, which it marks
   as unstable. The request names a session and a folder. The agent answers the
   id of a new session that starts with the history of the named session.
   `AgentClientProtocol.jl` has the types `ForkSessionRequest`,
   `ForkSessionResponse` and `SessionForkCapabilities`.
2. The agent `claude-agent-acp` 0.87.0 advertises `sessionCapabilities.fork`
   (`AgentClientProtocol.jl/test/recorded/claude-agent-acp-0.87.0.jsonl`).
3. The built-in agent `ClaudeCodeACP` 0.1.10 advertises only `close` and
   `resume`. It runs one `claude -p` for each session. It starts `claude` with
   `--session-id` for a new session, and with `--resume` for a session that has
   a history.
4. `claude` 2.1.309 takes `--resume S --fork-session --session-id N`: it opens a
   copy of `S` with the id `N`. I checked the arguments on 2026-11-11 with a
   session that does not exist. `claude` refuses `--session-id` with `--resume`
   and no `--fork-session`. With `--fork-session`, it accepts them and looks for
   the session. `claude` also knows the option `--resume-session-at`, which its
   help does not show. It cuts the history at a message.
5. `ClaudeCodeACP` starts `claude` when a session opens. When an option of the
   session changes, it starts `claude` again at the next prompt. A session of
   `ClaudeCodeACP` starts in the mode `"default"`, and the editor sets `"auto"`
   at each open. So the `claude` of a new session starts again at its first
   prompt.
6. The open of a tab acquires its content (`acquire_document!`), and a duplicate
   opens its tab the same way. The undo of the duplicate releases the content
   (`release_document!`), and the release of an assistant stops its agent.
   `StartExternalAgentOperation` opens the session of an assistant with no
   prompt, on a task.
7. Each assistant has its own connection to its agent. A turn that fails closes
   its connection.
8. Each node of a document stores its own selection, so two panes that show one
   node show one caret ([pane.md](../../documentation/package/platform/pane/pane.md),
   "A duplicate is a pane of its own").

## 4. What the copy shares and what it copies

The owner asked for shared state where it is possible. This table gives each
part of an assistant and the choice.

| Part | Now | With this plan | Reason |
| --- | --- | --- | --- |
| backend, model, system prompt, key, agent command, mode | shared | shared | They are values. |
| the transcript | copied | copied | A shared turn shows one caret and one selection in two panes (fact 8). |
| the text of the composer | copied | copied | The person edits each one alone. |
| the history of the agent | not given | copied by the agent (`session/fork`) | A session has one owner, and its history grows on one line. |
| the work of the model on the history | done again | shared by the prompt cache | The history of the copy is the same text, so the first answer of the copy reads it from the cache of the provider while the cache lives. |
| the options that the person chose: model, effort | lost | kept | The copy must answer as the original does. |
| the agent process and the connection | own | own | A turn that fails closes its connection (fact 7), so a shared connection stops the turns of both. |
| the work of the agent (subagents, plans, background tasks), the usage, the title | empty | empty | They are the live state of the session of the original. |

So the only new copy of the history is the copy that the agent makes itself. For
Claude Code, it is one file of the session on the disk.

## 5. The decisions

All decisions were proposed by the assistant and approved with the plan on 2026-11-11.

- **P1. The agent copies its session with `session/fork`.** The copy gets a new
  session that starts with the history of the session of the original.
  Rejected: the copy sends the transcript as text in its first prompt. Then the
  copy pays for the whole history as new input, and the agent gets a text about
  the tool calls in place of the calls and their results.
- **P2. The fork happens when the duplicate opens, not at the first message of
  the copy.** The acquire of the copy opens its session, as
  `StartExternalAgentOperation` does. Rejected: the fork at the first message of
  the copy. Between the duplicate and that message, the person can send more
  messages to the original. The agent of the copy then knows turns that its
  transcript does not show.
- **P3. The agent connection gets the verb `fork_agent_session!`.** It opens a
  session with the history of another session, and answers its id, or `nothing`
  when the agent can not fork that session. The default method answers
  `nothing`. Rejected: a keyword `fork_session_id` of `open_agent_session!`. A
  new session and a fork both answer a new id, so the caller can not tell them
  apart, and the note of the copy depends on it.
- **P4. A copy of an assistant that answers now starts a new session.** It keeps
  the rule of today: the turn that streams stays with the original. Its note
  says why: "The original answered when this copy was made, so this copy talks
  to the agent in a new session. The agent does not have the history above."
  Rejected: a fork during the turn. The agent of the copy then has a part of a
  turn that the transcript of the copy does not show.
- **P5. A note shows only when the agent of the copy does not have the
  history.** When the fork succeeds, the copy has no note. When the fork gives
  `nothing`, the note says: "This copy talks to the agent in a new session,
  because the agent could not copy the session of the original. The agent does
  not have the history above." The note of P4 is the other case.
- **P6. The copy keeps the options that the person chose.** After the fork
  opens, the copy sets each option whose value differs from the value of the
  original, as the open sets the mode now.
- **P7. A fork in `ClaudeCodeACP` has the history of its source as it was at
  the request.** This holds also when `claude` starts again before the first
  prompt of the fork (fact 5). Step 1 finds which of these two ways is
  necessary:
  - If `claude` writes the file of the fork when it starts, a start again
    resumes the fork, and nothing more is necessary.
  - Else the agent records the last message of the source at the request, and
    each start before the first prompt of the fork adds `--resume-session-at`
    with that message.

## 6. The steps

The work is in two repositories, each in its own worktree:

- projectured-julia: the branch `assistant-fork` in the worktree
  `projectured-julia-assistant-fork`.
- ClaudeCodeACP.jl: the branch `session-fork` in the worktree
  `ClaudeCodeACP.jl-session-fork`.

1. ~~**Find how `claude` forks a session.** In a folder of the scratchpad, make a
   session with one short prompt, then fork it. Record in this plan: when
   `claude` writes the file of the fork; what `--resume-session-at` takes, and
   if it works with `--fork-session`; and if the first answer of the fork reads
   the history from the cache (its usage shows `cache_read_input_tokens`). This
   step costs two short prompts. It changes no code.~~ **Done 2026-11-11.**
   - **(a) `claude` writes the file of the fork only at its first prompt.** A
     `claude -p --input-format stream-json --resume S --fork-session --session-id N`
     that got no prompt for 12 seconds wrote no file `N.jsonl` and printed
     nothing. So a start again before the first prompt can not resume `N`, and
     P7 takes its second way.
   - **(b) `--resume-session-at` takes the uuid of an `assistant` record of the
     source file, and it works with `--fork-session` and `--session-id`.** A
     source said "apple" and then "banana". A fork with
     `--resume-session-at <uuid of the record "apple">` answered "apple" to
     "List every word that you said before". Each record of the file is one
     JSON line with `type` and `uuid`; the records of a prompt are `user`,
     `attachment` and `assistant`, with other types between them.
   - **(c) The fork shares the work of the model on the history.** A source and
     its fork in the stream mode of the agent: the second prompt of the source
     read 26 263 tokens from the cache; the first prompt of the fork read
     30 830 and wrote only 383. A fork whose source ran in another mode
     (`--output-format json`) read 0, because its system prompt differs.
   - **The way of P7.** At the request, `ClaudeCodeACP` reads the file of the
     source, which the Claude Agent SDK also reads, and keeps the uuid of its
     last `assistant` record. Each start of the fork before its first prompt
     adds `--resume-session-at` with it. A source with no file, or with no
     `assistant` record, answers an error of the protocol.
2. **`ClaudeCodeACP` answers `session/fork`.** It advertises
   `sessionCapabilities.fork`. It opens the fork with
   `--resume S --fork-session --session-id N`, by the way of P7 that step 1
   chose. After the first prompt of the fork, the fork resumes as a session of
   its own. Test, with the fake `claude` of `test/agent.jl`: the fork gets these
   arguments, also at a start again before its first prompt; a fork of a session
   that does not exist answers an error of the protocol. The version becomes
   0.1.11, and `ProjecturedACP` asks for 0.1.11. The registration in
   `ProjecturedRegistry` is a step of the owner.
3. **The agent connection forks a session.** Declare `fork_agent_session!` in
   `source/kernel/agent/AgentConnectionInterface.jl`, with the default `nothing`
   in `AgentConnectionDefaults.jl`. `AcpConnection` sends `session/fork` when
   the agent advertises it, with the instructions and the MCP servers as
   `open_agent_session!` sends them, and registers the session the same way. An
   error of the protocol answers `nothing`. `ScriptedAgentConnection` forks a
   session when a test asks for it. Test: `test_acp_connection()`.
4. **The copy of an assistant forks the session of its agent.** `copy_document`
   of an `Assistant` keeps the source of the fork: the id and the folder of the
   session of the original, the count of the turns that the session saw, and
   the options that the person chose. The source is live state, so a file does
   not keep it. `acquire_document!` of an `Assistant` that holds a source posts
   `StartExternalAgentOperation`. The open of the session then forks in the
   folder of the original, and gives the copy the kept session, its count of
   turns and the options (P6). When the fork gives `nothing`, or the folder does
   not exist, a new session opens with the note of P5. The note of P4 replaces
   `FORK_AGENT_NOTE`. Tests in `test_external_agent_turn()`: the copy forks the
   session of the original and has no note; the next prompt of the copy sends
   only the new message; a fork that gives `nothing` gives the note of P5; a copy
   of an assistant that answers gives the note of P4; the undo of the duplicate
   stops the agent of the copy. Then `test_assistant_duplicate()`.
5. **The guides, and a check in the real editor.** Update
   `documentation/package/platform/assistant/assistant.md` ("A duplicate starts
   a new session"), `documentation/package/kernel/agent.md`,
   `documentation/package/adapter/acp/acp.md`, the docstrings of `Assistant`
   and `duplicate_pane!`, and the README of `ClaudeCodeACP`. Then, in the editor
   with the built-in agent: ask the original a question, duplicate the tab, and
   ask the copy "What did I ask you first?". The copy must answer with the first
   question. This check costs three short prompts.

## 7. The limits

- A message that the person sends to the original in the seconds between the
  duplicate and the open of the session of the copy can reach the agent of the
  copy. The duplicate takes the focus, so the person must first go back to the
  original.
- The history of the copy can name a background task or a subagent of the
  original. The copy can not reach it.
- An agent that does not advertise `session/fork` works as now, with the note
  of P5.

## 8. Not in this plan

- One agent process for the original and its copies.
- A copy that starts at an earlier turn of the conversation.
- A text of the transcript for an agent that can not fork.

## 9. Progress

- 2026-11-11: step 1 done (facts in step 1).
