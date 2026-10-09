# A terminal runs a program in the editor

> **Status:** PROPOSED, waits for the answers of the owner. **Asked by:** the owner
> on 2026-10-09, for step 2.5 of
> [the-assistant-talks-to-an-acp-agent.md](the-assistant-talks-to-an-acp-agent.md):
> "a simple terminal domain would be good in general but don't overdo it. it's
> worth its own plan".

## Goal

A document that runs one program, shows what the program writes, and sends a
line that the person types to the program. The first user is the sign-in of an
ACP agent (step 2.5): the program `claude-code-acp --login` runs
`claude auth login`, which writes a URL, asks for a code, and ends with the
status 0 on success. The terminal is simple: no pseudo terminal, no emulation
of a screen.

## Facts (2026-10-09)

- `claude auth login` works with pipes and no terminal device. With an empty
  `CLAUDE_CONFIG_DIR` and no display it wrote "Opening browser to sign in…",
  then "If the browser didn't open, visit: <url>", then
  `Paste code here if prompted > ` **with no line end**, and waited for a line
  on its standard input. With a display, it opens the browser itself.
- The `task` slice of the platform runs a process with pipes
  (`start_process_task!` in `source/platform/task/TaskExecution.jl`): it reads
  the standard output and the standard error **line by line**, starts the
  process in a group of its own (`detach = true`), and stops the group with
  SIGINT. It does not pipe the standard input. Its documents model work that
  ends with a result, in groups, in the words of `opp_repl`.
- A document holds no editor. A background task posts a change with
  `run_on_editor_task!(function_, target; wait = false)`, and the editor applies
  it at the top of its next frame.
- `release_document!(editor, document)` frees what a document holds outside the
  tree when its tab closes; the assistant stops its agent there.
- The package rules: a domain package is a kind of content that a person edits,
  and it has no third-party dependency. The file system, the conversation and
  the assistant look like domains but are slices of `ProjecturedPlatform`. A
  process is the same kind of thing as a task.
- No widget shows a list of lines with an input line below it. The assistant
  shows its transcript over its composer in a `WidgetSplitPane`.

## Design (a proposal)

- **T.1 The document.** A slice `terminal` of the platform (see Q1) with
  `TerminalDocument`: the command (`Cmd`), the lines of the output, the line
  that the person types, the status (`:running`, or the exit status), and an
  `on_exit` function that the slice calls on the editor task with the editor
  and the exit status. The document holds the process in a cell that no path
  reaches, as the assistant holds its agent session.
- **T.2 The process.** Start the command with pipes for the standard input, the
  standard output and the standard error, in a group of its own. A reader task
  reads what is available (`readavailable`), not whole lines, so a prompt with
  no line end shows at once. It posts the text to the document through
  `run_on_editor_task!`. The text of the standard error has its own colour.
  The reader removes the escape sequences of colour and cursor (CSI) and keeps
  the text after the last carriage return of a line, so a progress line does
  not repeat. When the process ends, the document shows "The program ended with
  the status N", and `on_exit` runs.
- **T.3 The input.** Enter sends the typed line and a line end to the standard
  input. The program does not echo without a terminal device, so the document
  adds the line to the output in the colour of input. A secret is not hidden;
  the plan says so and the guide says so.
- **T.4 Stop and close.** A stop button and Ctrl+C send SIGINT to the group;
  a second stop kills it. `release_document!` kills the group when the tab or
  the card closes. On Windows, which has no process group of this kind, a stop
  kills the process.
- **T.5 The view.** `TerminalToWidget`: the lines in a scroll pane that follows
  the end, the input line below them, and a status row with the command, the
  status and the stop button. Text of the output can be selected and copied,
  so a person can copy the URL when no browser opens.
- **T.6 The sign-in (step 2.5e of the ACP plan).** The button of a sign-in
  method makes a `TerminalDocument` for the command of the method, with an
  `on_exit` that starts the agent again on the status 0. See Q2 for where it
  shows.

Not in this plan: a pseudo terminal, colours of a program, cursor movement,
programs with a full screen, such as an editor or `top`, and a shell of the
person as a general tool (see Q3).

## Steps

- [ ] T.1 + T.2 The document and the process, with tests that run `sh` scripts:
  a prompt with no line end shows, a line on the standard input reaches the
  program, the standard error has its colour, the exit status arrives.
- [ ] T.3 + T.4 The input, stop and close, with tests.
- [ ] T.5 The view, with a test in a real editor (a key types, Enter sends).
- [ ] T.6 The sign-in card uses it (with step 2.5e).
- [ ] Guide: `documentation/package/platform/terminal/terminal.md`, the slice
  table in `documentation/rule/package-rules.md`, and the edge of the slice in
  `PLATFORM_SLICE_EDGES`.

## Questions for the owner

- **Q1.** A slice `terminal` of the platform (recommended: the package rules put
  a process with the task and the assistant, not with a domain of content), or
  a domain package `ProjecturedTerminal`?
- **Q2.** Where the terminal of a sign-in shows: inside the sign-in card in the
  conversation (recommended: the URL and the code input are where the person
  already looks, and no window opens), or in a tab of its own?
- **Q3.** A command that opens a terminal with the shell of the person, as a
  general tool. Without a pseudo terminal a shell shows no line editing and no
  colours, and some programs behave differently. Recommended: not now; a later
  step can add it.
