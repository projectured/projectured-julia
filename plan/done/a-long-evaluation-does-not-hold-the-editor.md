# A long evaluation does not hold the editor

> **Status (2026-10-15): CLOSED.** The owner asked for this plan on 2026-10-09:
> "an execute_julia_code may take a long time and the editor should not become
> unresponsive during that time", and deferred it the same day. Its goal is what
> [the-editor-always-answers-the-person.md](the-editor-always-answers-the-person.md)
> built, which took it in: a tool call and an evaluation run as a code unit off
> the thread of the loop, the loop runs held frames that keep the window alive
> and offer a stop, and model code that must not hold the documents runs as
> background work. Its questions were answered there: Q1 by D1 (option A, a code
> unit on another thread, and not B2); Q2 by D2 and D3 (the last picture, a busy
> bar with a stop and Escape; keys wait for the end of the unit, and pointer
> presses that start during it are dropped); Q3 by the units of §5.4, which take
> the evaluations of the composer and the evaluator at once; Q4 by D9f, an output
> of each evaluation in place of the swap of stdout of the process. This file is
> the text of the branch `plan-evaluation-off-editor`, kept as it was below this
> note.

## Goal

While model code that `execute_julia_code` runs takes its time, the window of the
editor stays alive: it draws, the person can move it, and the Stop button of the
assistant acts. Today the window freezes for as long as the code runs, and a long
call after "Always allow" can look like a hung application.

## Facts (2026-10-09)

**How a tool runs today.**
- Each caller runs a tool on the editor task, in the drain of a frame:
  - `run_turn!` of the kernel: `run_on_editor_task!(target) do call_tool(…)`
    (`AgentLoop.jl:87-109`);
  - the MCP handler of `render_mcp_tools` (`McpServer.jl:237-285`);
  - the local evaluation of the composer, `ComposerEvaluateOperation`
    (`ConversationEditor.jl:372-400`), and `EvaluateSelectedFormOperation` of the
    evaluator (`Evaluator.jl:450-502`), which call `execute_julia_code!` inside
    the evaluation of an operation.
- While a tool runs, the editor draws no frame and reads no input
  (`editor.md:224-225`). The guide of the assistant lists it as a limit: "A tool
  call holds the frame" (`assistant.md:153`). A stop can act only after the call
  returns, because `CancelAssistantTurnOperation` itself runs on the editor task.

**What model code does.**
- It reads documents directly: `editor.document`, `search_documents`,
  `search_references`, `evaluate_reference`, and the fields of a document.
- It changes them through `evaluate_operation(editor, op)` and the verbs
  `replace_referenced_value!`, `insert_elements!` and `delete_elements!`, which
  evaluate their operation on the calling task (`PaneProgram.jl:570-589`). The
  task verbs already go through `run_on_editor_task!(…; wait = false)`.
- The code runs in a `ScopedValue` that binds the editor, so a task that the code
  starts inherits it (`CodeExecution.jl:242, 398`).

**What keeps documents safe.**
- `PAR-STORE-THEN-DRAIN`: only the editor task writes a document that a running
  editor shows (`architecture-invariants.md:258-271`).
- The cell engine has no locks, and a read of a reactive cell computes and caches
  its value, so a read is a write too (`ReactiveCell.jl:124-129`, `cell.md`).
- Work off the editor task already exists for producers: feeds and the task slice
  write stores under locks, and the editor task drains them into documents.

**Threads.**
- The application starts Julia with no thread flag. Julia 1.13 then has one
  interactive thread, which runs the main task and the editor loop, and one
  thread of the default pool (thread 2).
- A task that `Threads.@spawn` starts in the default pool runs on thread 2, at
  the same time as the editor loop.

**Earlier findings.**
- The kernel audit, L18-9 (`plan/pending/kernel-audit/18-tool.md`), finds that
  work on the editor task has no time bound, and proposes to "run model code on
  its own task and send only its writes through `run_on_editor_task!`".
- L18-4 of the same audit: each evaluation swaps the stdout and the stderr of the
  whole process with `redirect_stdio`, so every task that prints during an
  evaluation writes into its answer, and two evaluations that overlap restore
  the wrong stream.

## The options

- **A. A task of its own, on the editor thread.** The editor runs a frame
  whenever the code waits: for I/O, a download, `sleep`. Code that computes never
  yields, so it still holds the window. No change of what code may touch.
- **B1. The code off the editor task, and only its writes through
  `run_on_editor_task!`** (the proposal of L18-9). The frame and the code then run
  at the same time. The writes are safe, but every direct read of the code races
  the frame, and a read of a reactive cell writes its cache. Every read would have
  to go through the editor task too, which no code that reads a field can do.
- **B2. The editor lends its documents to the evaluation.** The code runs on a
  task of its own, on thread 2. For that time the evaluation owns the documents,
  and the editor task touches none:
  - The window keeps its last picture, redraws it when the system asks, and can
    be moved. The assistant shows that a call runs.
  - The editor reads only what needs no cell: Escape, and a click at the place of
    the Stop button, which the editor notes as plain numbers before it lends the
    documents. Any other input waits until the evaluation ends.
  - A `run_on_editor_task!` from the evaluation, or from a task that it starts,
    runs at once, because the evaluation owns the documents. One from another
    task, such as a post of a streamed turn, waits in the inbox.
  - When the evaluation ends, the editor takes its documents back, drains the
    inbox and draws the new state.
  So the rule of one writer still holds: for the time of the call, the writer is
  the evaluation.
- **C. MCP Tasks.** The fork of ModelContextProtocol can answer a call at once
  and run it in the background. That frees the MCP server only; the code still
  needs the documents.

**My recommendation: B2.** It keeps what model code may do today, and it keeps
one writer. The editor stays alive and the Stop button works, but the window
shows the last state until the call ends. B1 would need an API for reads that
the model's code can not keep to.

## What a stop can do

- Julia does not preempt a task. A stop can throw `InterruptException` into the
  task of the evaluation only when that task waits: at I/O, a print, `sleep`, a
  `yield`. The code then ends at that point, and the answer says that it was
  stopped.
- Code that computes without a yield point runs to its end. The plan can only
  tell the person so; a time bound can not cut such code either.

## The questions

- **Q1.** B2, or another option?
- **Q2.** The window during a call: the last picture, a mark that a call runs,
  Escape and the Stop button. Does other input wait until the call ends, or is it
  dropped?
- **Q3.** The local evaluation of the composer and the forms of the evaluator also
  run code inside the evaluation of an operation. They get the same treatment in a
  later step, which makes their operation end before the code does. Now, or later?
- **Q4.** L18-4: with B2 the editor prints during an evaluation only through its
  log. The process-wide swap of stdout stays a fault of its own. Fix it in this
  plan, with an output of the evaluation that is its own and not the process's,
  or leave it to the kernel audit?

## Steps (after the answers)

- [ ] **E.1 A probe.** In a throwaway app: a frame loop that only redraws its
  last picture and reads raw events while a task on thread 2 computes and writes
  cells. Measure that the window stays alive, and that Escape is seen.
- [ ] **E.2 The lend, in the kernel editor layer.** The editor gets a state "lent
  to a task": the loop runs held frames, and `run_on_editor_task!` runs inline for
  the borrower and the tasks that inherit it.
- [ ] **E.3 The callers.** `run_turn!` and the MCP handler run a tool through the
  lend, on a task of the default pool, and wait for it on their own task.
- [ ] **E.4 The stop.** `CancelAssistantTurnOperation` reaches the evaluation in a
  held frame and throws `InterruptException` into it at its next yield point.
- [ ] **E.5 The guides, the tests, and a live check** with the built-in agent: a
  call of `sleep(10)` and a call of a loop that computes for ten seconds; the
  window must stay alive in both, and the stop must end the first.
