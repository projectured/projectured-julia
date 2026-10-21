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
3. [ ] **The workloads print one assistant turn.** `warm_assistant_turn!` in
   `source/platform/assistant/`, with a test in a headless editor: the turn has
   each kind of part, the editor records no fault, and the function answers the
   assistant. The call in `warm_application()` lands on main of projectured-julia
   first. The call in `OmnetIde.precompile_workload!` follows in omnet-julia,
   because a worktree of omnet-julia does not see a change of projectured-julia
   that is not on main. The guide `documentation/package/platform/assistant/assistant.md`
   says what the warm-up covers.
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
