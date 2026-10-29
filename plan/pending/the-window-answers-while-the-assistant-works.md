# The window answers while the assistant works

Status: PENDING, 2026-10-21. Not started. No decision is open.

## The ask

The owner, 2026-10-21: "while the assistant operates, the editor is often
unresponsive, often even the Ubuntu window pops up with Force quit/Wait options",
also "during thinking, or tool calls, not only execute_julia_code". After the
first measurements: "adding to the turns should not reprint what is already
printed, incremental principle says this", "yes, profile to see", and "we should
make this work fast enough, probably the compiler workload is insufficient". The
owner approved the three steps of the profile report with "yes".

## The problem

The window answers the window system only between two frames. Ubuntu shows the
"Force quit / Wait" dialog when one frame takes more than about 5 s. During an
assistant turn, single frames took up to 19.7 s. The agent, its `claude` process
and its MCP server run on other threads, so the frames do not wait for the agent.
The time goes to work on the loop thread.

### The measurement

`omnet_ide --assistant=acp --context=32768 --mcp ~/workspace/inet-cpp`, Julia
1.13.1, `--threads=auto,2`, one long assistant turn by the owner. The profile
sampled every thread each 10 ms. The compile trace has `--trace-compile-timing`.
The data and the scripts are in `/var/tmp/ide-profile-20261021/` (the scripts are
in `scripts/`).

The samples of the loop thread inside frames:

| Work | Samples | Share |
| --- | --- | --- |
| JIT compile (read 1008, print 886, evaluate 277, feeds 228) | 2401 | 52% |
| A thrown and caught `FieldError` (print 1157, read 336) | 1496 | 32% |
| Real work (feeds 454, print 154, read 79, other 20) | 707 | 15% |
| Garbage collector | 34 | 1% |

The profiler stops the loop thread while it unwinds the deep stack, so the frame
times of the profiled run are too long. The shares are valid. An IDE without the
profiler showed the same kind of frames: 19.5 s with 17 s in the read stage, and
prints of 1.5–2.9 s.

### Cause 1: the workloads print no assistant turn

`OmnetIde.precompile_workload!` (`omnet-julia/source/ide/IdePrecompile.jl`)
compiles the result readers, a study and the charts. `warm_application()`
(`source/platform/application/Application.jl:899`) makes an assistant but sends
it no event. So the first thinking block, the first tool call with Julia code,
the first permission request and the first pointer move over each of them
compile on the loop. The trace has 2727 compiles with 89 s in 11 minutes, for the
whole process. Among them:

- `print_document` of the Julia projections that show the code of an
  `execute_julia_code` call: 61 methods, 14.4 s, up to 1.7 s for one method
  (`JuliaIntegerToSyntaxLeaf`, `JuliaSymbolToSyntaxLeaf`, `JuliaTupleToSyntaxNode`,
  `JuliaStringToSyntaxLeaf`, `JuliaForToSyntaxNode`, `JuliaCallToSyntaxNode`, …).
- `Core.kwcall` 210 methods, 14.7 s; `read_intent` 131, 2.5 s; `_walk_document!`
  77, 2.7 s; `map_reference_backward` and `map_reference_forward` 66, 2.3 s.
- 43 compiles were a recompile of invalidated code (0.7 s), so invalidation is not
  the problem.

### Cause 2: the print of a code block throws once for each wrapper

`SyntaxToText.jl:666` makes the context of child `i` of every compound with the
steps `.children` and `[i]`. A `SyntaxWrapper` holds its one child in `.content`,
so `annotate_reference_types` (`ReferenceEvaluation.jl:189-194`) calls
`getfield(wrapper, :children)`, which throws a `FieldError`, and the `catch` turns
it into "no child". Each throw records a backtrace of the whole stack. The stack
of the print recursion is deep, and each unwind step walks every shared object of
the process (`dl_iterate_phdr`), so one throw costs milliseconds. 1460 of the 1492
samples in the unwinder come from this one site.

The same line also gives the child of a wrapper a wrong path: `.children[1]`
instead of `.content`, and the rest of the path stays untyped.
`build_syntax_child_path` (`SyntaxDocument.jl:81-86`) already gives the right path
for both kinds of compound.

### What the profile does not show

The profile does not show a print of earlier parts as a cost: the long prints
come from new code blocks. But a profile can not prove that no earlier part
prints again. Step 4 counts it.

## The model

1. **A compound gives the path of its child.** The print of a compound makes the
   context of each child from the steps that `build_syntax_child_path` holds. A
   sequence gives `.children[i]` and a wrapper gives `.content`, typed at each
   node. No print evaluates a step that the document does not have.
2. **A walk asks before it steps.** The reference layer gets one predicate,
   `has_reference_step_child(step, document)`. A field step answers whether the
   struct has the field, or the dict has the key as a `String` or a `Symbol`. A
   range step answers true for a position, and else whether the index is inside
   the length of the document, counted in characters for a string. Every other
   step answers true. `annotate_reference_types`, `get_valid_reference_prefix`
   and `try_evaluate_reference` ask the predicate before each step, and a "no"
   ends the walk as the `catch` ends it today. The `catch` stays for a step kind
   that answers true and then throws.
3. **The workloads print one assistant turn.** The assistant slice of the platform
   gets one function, `warm_assistant_turn!(editor, assistant)`. It applies one
   turn of agent events with `apply_agent_event!`, with no agent and no process:
   thinking deltas, text deltas of Markdown with a code block, an
   `execute_julia_code` tool call whose input holds Julia code with the forms
   that the trace lists, its result, a `search_api` call, and a permission request.
   Then it prints, forces the cells that the view reads, moves the pointer over
   each part, clicks an option of the permission request, and ends the turn.
   `OmnetIde.precompile_workload!` and `warm_application()` call it.

## Steps

1. [x] **The child of a wrapper has its own path.** `SyntaxToText.jl:666` uses the
   steps of `build_syntax_child_path`. Tests in
   `test/platform/projection/SyntaxToTextTest.jl`: the context of the child of a
   wrapper is `.content`, the context of a child of a sequence is `.children[i]`,
   and every node of both paths has its type. The paths of carets and selections
   in a wrapper can follow the wrong path today, so run `test_syntax_to_text()`,
   then `test_example` and `test_position_navigation` of one Julia example and of
   one Markdown example with a code block.
2. [x] **A walk asks before it steps.** The predicate and its methods in
   `source/kernel/reference/`, and the three walkers. Tests in
   `test/kernel/reference/ReferenceEvaluationTest.jl`: a field that the struct does
   not have, a dict key as a `String` and as a `Symbol`, an index past the end of a
   vector and of a string, and a position. Each answers the same result as today.
   Then `test_kernel()`. The guide `documentation/package/kernel/reference.md` names
   the predicate.
3. [x] **The workloads print one assistant turn.** Main moved to the design of
   `documentation/design/compile-ahead.md` on 2026-10-29: each package compiles its
   recorded lists `precompile/*.txt` by default, and a workload runs only when a
   person records the lists again. So the turn is a step of the window workloads,
   and the lists are recorded again. The owner approved this form with "yes" on
   2026-10-29.
   - `warm_assistant_turn!(editor, assistant)` in `source/platform/assistant/`
     puts the events of one agent turn into the queue of a session, which the
     feed of the window drains. The step `WorkloadAgentTurn` of
     `ApplicationWorkload.jl` calls it on the assistant that the window shows.
   - `run_window_workload()` of the platform and `make_ide_workload_steps` of
     omnet-julia give the step after the turn of their built-in assistant, wait
     for its answer, and click in its code and on "Allow".
   - Tests: `test_external_agent_turn()` and `test_window_workload()` in
     projectured-julia, `test_ide_window_workload()` in omnet-julia (through a
     scratch environment whose paths go to both worktrees).
   - The recordings, in this order: `record_package_calls!("ProjecturedPlatform")`,
     `record_application_calls!("ProjecturedBuild", "projectured")`, then in
     omnet-julia `record_package_calls!("OmnetIde")` and
     `record_application_calls!("OmnetIdeBuild", "omnet_ide")`.
   - The guide `assistant.md` says what the warm-up covers.
4. [ ] **The live check.** The profile scripts of `/var/tmp/ide-profile-20261021/scripts/`
   again, with one long turn of the same kind. Counts, which do not depend on the
   load of the machine:
   - no sample of the loop in the unwinder below `annotate_reference_types`;
   - no compile of a `print_document` of a Julia projection, of a
     `ConversationPart` print or of an `EvaluatorForm` print in the trace of the
     turn;
   - the share of compile samples of the loop inside frames, against 52%;
   - one more text delta after the turn recomputes no cell of an earlier part. A
     scratch script counts it: it redefines `_run_computation` of the cell module
     with `@eval` and counts the computations by the file and the line of each,
     and the distinct cells of each place with an `IdDict`.

   A time of a frame is a measurement, so it needs an idle machine and the word of
   the owner. Then the plan moves to `plan/done/`.

## Not in this plan

- The start of the agent (`start_agent_connection!`, `ClaudeCodeACP._open_session!`)
  and the search tools compile on threads of the default pool. They delay the first
  answer, but they do not hold the window.
- The held frames of an `execute_julia_code` call. The window paints during the
  call, as designed.

## As built

### Step 1

- `make_syntax_child_steps(doc, i)` (`SyntaxDocument.jl`, exported by
  `SyntaxModule`) answers the steps to child `i` with no types: `.children` and
  `[i]` for a sequence, `.content` for a wrapper. It sits beside
  `build_syntax_child_path`, which answers the same steps with their node types.
  The print needs the steps without types, because `make_child_context(ctx, node,
  steps...)` types them against `node` itself.
- The test "the print gives a child the path that its compound gives it"
  (`SyntaxToTextTest.jl`) prints a wrapper and a sequence through a recursion that
  records the context of each child. It checks the steps, and that every node of
  each path has its type.
- `test_syntax_to_text()`: every testset passes ("Syntax wrappers" 42). The
  navigation checks on `julia_example` and `markdown_example` run with the tests of
  step 2, because they need the umbrella `ProjecturedTest`.

### Step 2

- `has_reference_step_child(step, document)` is declared in `ReferenceInterface.jl`
  and exported. Its methods sit beside the evaluation of each step in
  `ReferenceStep.jl`: a field step on a dict (the key as a `String` or a `Symbol`)
  and on any other document (`hasfield` of its type, as `getfield` reads it); an
  element step on an `AbstractArray` (`checkbounds`) and on an `AbstractString`
  (the count of characters); a cursor is always `true`. The default for every
  other `ReferenceStep` is `true`, so a `TypeReferenceStep` still reaches the
  `MethodError` of its evaluation, and a step type of a higher package keeps its
  behaviour until it adds a method.
- `try_evaluate_reference` walks step by step with `_evaluate_reference_or`, which
  answers the default for a recorded type that does not hold or a step that
  reaches no place. `get_valid_reference_prefix` and `annotate_reference_types`
  ask the predicate before each step. Each walk keeps its `catch`.
- A `CellVector` is not an `AbstractArray` (it is a `ListDocument` of the
  platform), so an element step on it still evaluates and can throw out of range.
  The syntax print does not reach that case: its index always fits.
- Tests (`ReferenceEvaluationTest.jl`): "a walker asks before it steps" uses a step
  whose predicate answers "no" and whose evaluation throws an `InterruptException`,
  which every walker passes on; and "a step says whether it reaches a place"
  covers each case of the predicate and the answers of the walkers.
  `test_reference_evaluation()` 128 passes, `test_kernel()` 4932 passes, no
  failure and no error. The guide `reference.md` names the predicate.

### Step 3

- `warm_assistant_turn!(assistant)` (`source/platform/assistant/AssistantWarmUp.jl`,
  exported by `AssistantModule`) gives the assistant an `ExternalAgentSession` with
  no connection for the length of the call, applies a user turn and the events of
  one agent turn with `apply_agent_event!(nothing, assistant, event)`, and puts the
  session back. The agent turn opens by itself, as a turn that an agent starts
  between two prompts, and ends at its `AgentUsageUpdate`.
- Decision: the canned events are input, as the canned keys of `warm_application()`
  are, and not a double of the agent seam (`PAR-NO-TEST-DOUBLES-IN-MAIN`). No path
  that a person reaches makes them, and no connection is implemented.
- Facts found on the way:
  - Only the prefix `mcp__projectured__` is taken off a tool name, so the warm
    calls use it; with another prefix the form does not read the input as code.
  - A text block becomes Markdown at its end through `parse_markdown_blocks`, and
    a fenced block becomes a live Julia document. Both need `ProjecturedMarkdown`
    and `ProjecturedJulia` loaded, which the binaries load.
  - A pane follows the end of a turn, so the thinking and the first text are out
    of view in a window of 1280 × 800. The `execute_julia_code` call therefore
    comes last but one, before the answer, so its code is in view.
  - A click on "Allow" in the assistant pane can move the focus, and the test of
    `warm_application()` checks that the focus ends in the tab that the Insert key
    made. So `warm_application()` moves the pointer over six drawn tokens of the
    code and the option (`runner_1`, `select_simulations!`, `for`, `0.5`, `Fifo`,
    `Allow`; all six found in view) and answers the request with
    `answer_permission_request!`, with no click.
  - `_find_drawn_text_point` skips a text above or left of the frame, because a
    scrolled pane keeps its texts in the tree with a negative place.
- Tests: "a warm-up applies one turn with each kind of part, and no agent"
  (`ExternalAgentTurnTest.jl`); `test_external_agent_turn()` 281 passes;
  `test_application()` 389 passes and 2 broken, the two known markers of the
  scroll scenario of the Files pane. The guide `assistant.md` has "The warm-up of a
  build" and a design decision.
- The example checks of step 1, run alone: `test_position_navigation` 83 passes
  (Julia) and 395 (Markdown); `test_example(markdown_example)` 6050 passes;
  `test_example(julia_example)` 3357 passes and 84 failures at
  `TypeinTest.jl:733`. The base commit `4c07f266c` gives the same 3357 and the same
  84 failures, so they come before this branch: the Julia example draws no caret on
  its identifier leaves.
- The call in `OmnetIde.precompile_workload!` is omnet-julia `e6fe4a3b` on the
  branch `window-answers` (worktree `omnet-julia-window-answers`). It opens an
  assistant pane in the tree of the workload, prints the turn through the wrapped
  projection, reads 400 pointer moves over a grid of the window of 1200 × 800, and
  answers the request with `answer_permission_request!`. The workload has no
  editor, so the hover operations that the moves answer are read, not evaluated.
- Fact: `campaign_assistant(choice; llm)` makes an `Assistant` only for
  `choice === :auto`, with the backend `llm`; another `choice` is answered as it
  is. So the workload calls `campaign_assistant(:auto; llm = :acp)`, as
  `--assistant=acp` does. The first version called `campaign_assistant(:acp)`, and
  the `catch` of the workload hid the `MethodError`.
- The block is checked in a scratch copy of the app environment
  (`/var/tmp/window-answers-app/omnet_ide`, paths to both worktrees) by a script
  that runs it with no `catch` (`/var/tmp/window-answers-tests/check_ide_workload.jl`):
  313 drawn texts with the code tokens, the Markdown text, the answer, the search
  and the option; the moves answer `nothing` or a `ReplaceMouseTargetOperation`;
  the answered request prints.
- The precompile of the app logs "The pane has no duplicate" twice for the
  `StudyStudy` pane. The F1 and Ctrl+Shift+P reads of the workload make it while
  the Study tab has the focus, before the assistant pane opens.

### Step 3, second form (2026-10-29)

- The branch moved onto main (`d338b8d04`). Steps 1 and 2 applied with no change.
  The first form of step 3 conflicted: `warm_application()` moved to
  `ApplicationWorkload.jl`, and omnet-julia has no `IdePrecompile.jl` any more. The
  helper, its test and the guide kept their commit; the calls of the workloads
  went, and the omnet commit `e6fe4a3b` left the branch.
- `warm_assistant_turn!(editor, assistant)` makes an `ExternalAgentSession` with no
  connection, makes its queue with `_make_agent_event_queue!` (which registers it
  with the `AgentEventFeed` of the window, at once on the task of the editor), puts
  the events with `put_agent_event!`, and calls `wake_editor!`. The frames that
  follow drain the queue, so a recording also sees the drain of the feed, which
  took 228 compile samples and 454 work samples of the loop in the first profile.
  The assistant keeps the session, which only a window that its workload closes
  takes.
- `WorkloadAgentTurn` (exported by `ApplicationModule`) finds the first view whose
  input is an `Assistant` (`_collect_part_iomaps`, which `_collect_part_outputs`
  now uses too), calls `warm_assistant_turn!` there, and gives no device input.
- `run_window_workload()` and `make_ide_workload_steps` give, after the turn of the
  built-in assistant: `WorkloadAgentTurn()`, `WorkloadWait(DrawnText(r"33\.5"))`,
  `WorkloadClick(DrawnText(r"lengths_1"))` and `WorkloadClick(DrawnText("Allow"))`.
  `lengths_1` is only in the code of the turn, which a pane keeps in view.
- Tests (projectured worktree, `bounded-run`): `test_external_agent_turn()` 305
  passes; `test_window_workload()` 1 pass, so each new step found its target and no
  barrier caught a fault.
- Test (omnet worktree, scratch environment `/var/tmp/window-answers-omnet-env`
  with the paths of both worktrees): `test_ide_window_workload()` 1 pass, so the
  IDE window found the same three targets.
- The recordings, each with no failure of its workload:
  - `ProjecturedPlatform/precompile/workload.txt`: 560 lines added, 279 removed;
    44 new lines name the agent turn (the step, the drain of the feed, the card of
    the permission request). The removed lines are calls that main no longer makes
    since its last recording.
  - The binary `projectured`: 16 lists `precompile/projectured.txt` and
    `ProjecturedBuild/precompile/workload.txt`, 1022 lines added, 12 removed. The
    Julia list now holds `JuliaSymbolToSyntaxLeaf`, `JuliaTupleToSyntaxNode`,
    `JuliaStringToSyntaxLeaf`, `JuliaForToSyntaxNode`, `JuliaCallToSyntaxNode` and
    the Markdown list `MarkdownCodeToSyntaxLeaf`; main had none of them.
  - The IDE: `OmnetIde` and `OmnetIdeBuild` lists and two lists of other omnet
    packages, 1427 lines added, 520 removed (omnet-julia, after `c3869aa22`).
    They now hold `WorkloadAgentTurn`, the permission request,
    `JuliaForToSyntaxNode`, `JuliaTupleToSyntaxNode` and `MarkdownCodeToSyntaxLeaf`.
    `JuliaCallToSyntaxNode` falls from 6 to 3 lines, because the projectured list
    of `ProjecturedJulia` compiles those calls, and a recording does not list a
    call that an image holds.
- A job of the run tool can wait for room: other sessions held caps of 20 GB, so
  the IDE recordings waited about 20 minutes. One test job at a cap of 9 GB had
  one OOM kill of a parallel precompile worker, which Pkg compiled again.

### Step 4

- The cell probe (`/var/tmp/window-answers-tests/probe_delta_cells.jl`) wraps
  `_run_computation` of the cell module with `@eval` in a scratch process and counts
  each computation by its module and the name of its closure. A `@computation` has
  no line of its own, so the name of the closure (`#print_document##28`) tells the
  function that made it. In the application window with the warm turn:
  - one text delta into the open text part: 31 computations at 26 places, one
    closure each: the text part, its lines, its layout and the canvas;
  - one more text delta: the same 31;
  - a new tool call part: 289 computations at 73 places, the new form and the
    places of the parts beside it.

  No computation of an earlier part runs, and none of the syntax print. A delta
  does not print the parts before it again.
