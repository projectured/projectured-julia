# The evaluator shows a value as the REPL does, and the model gets a trimmed value

> **Status:** pending. Written 2026-09-26.

## 1. The request

In the S2 rehearsal, the result of `open_pane!(…)` in the conversation and in the
evaluator read: "The last value is ConcreteReference. Print the part you want to
read, as `println(first(x, 10))` or `println(names(x))`." The owner asked what the
Julia REPL does, agreed that a person must see the value as the REPL shows it, and
asked: "even if a hint is printed to the model, should we not include a trimmed
version?" Then: "write plan and do it".

## 2. What exists

- `execute_julia_code(set, target, code)` and `execute_julia_expression(set, target,
  expression)` (`source/kernel/tool/CodeExecution.jl`, not sealed) run the code in
  the scratch module through `_run_expression`. Inside `redirect_stdio`, after the
  last statement, `_run_expression` prints `_describe_last_value(result)` into the
  same pipe as the code's own output. The answer is stdout, then stderr.
- `_describe_last_value(value)`: `nothing` is nothing; a `Base.Text` is shown whole;
  a `Function` as the REPL shows it; a value whose `repr` (with `:limit => true`) is
  at most 200 characters on one line (`_SHOWN_VALUE_CHARACTERS`) is shown as it is;
  a long `AbstractString` is shown whole without quotes; any other value is replaced
  by "The last value is <summary>. Print the part you want to read, …". The
  docstring of `execute_julia_code` says: "A value is whole or described, never cut
  in the middle."
- The answer goes to four readers:
  1. a model, as the answer of its tool call (`source/assistant/AssistantTurn.jl:751`
     puts it in the conversation, where the person sees what the model got);
  2. a person in the evaluator (`source/conversation/Evaluator.jl:429`,
     `evaluate_operation(::EvaluateSelectedFormOperation)`): a `Document` value is
     kept live, and any other value shows the whole answer as its result text;
  3. a person who evaluates from the chat composer (`AssistantTurn.jl:222`);
  4. an MCP client, through the same tool.
- `test/kernel/tool/CodeExecutionTest.jl:38` and `:43` assert the text of the hint.
- What the Julia REPL does (measured 2026-09-26 at 80×24): `display` calls
  `show(io, MIME"text/plain"(), value)` with `:limit => true` and the size of the
  terminal. A struct with no `show` of its own prints its whole `repr`; a string of
  1000 characters shows 559, with the middle left out and marked; a vector of 1000
  shows a header and the first and last rows that fit, with `⋮`; a dictionary of 40
  shows a header and the rows that fit; `nothing` prints nothing.

## 3. Decisions

- **D1. A person sees the value as the REPL shows it.** The evaluator and the chat
  composer show what the code printed, then `show(io, MIME"text/plain"(), value)`
  with `:limit => true` and a display size of 24 rows × 80 columns, the size of a
  default terminal. `nothing` shows nothing, as now. No note to the model appears.
  (The size is a first choice, not measured.)
- **D2. A model gets a trimmed value and a note, not a note alone.** A value of at
  most 200 characters on one line is shown as it is, as now. A longer value is the
  REPL display with `:limit => true` and 20 rows × 100 columns; a display of at
  most 600 characters is shown whole with no note — the REPL's own `⋮` already
  says it was trimmed. A display still longer than 600 characters keeps its
  start and its end (300 characters each, half of 600) and the middle becomes
  one mark, "⋯ N characters left out ⋯", N counted on that *limited* display,
  never on an unlimited print (a huge array would cost too much to even
  measure). One line follows: "The value is trimmed: <summary(value)>. Print a
  part, as `println(first(x, 10))` or `println(names(x))`." **Correction to the
  line first written here** ("whole, it prints N characters"): that phrasing
  implies an unlimited print to learn N, which the code must never compute: the
  note uses `summary(value)` (`_summarize_value`, already in the file) instead.
  A `Base.Text`, a `Function` and a long `AbstractString` keep their present
  rules — both return before the new trimming branch runs. (The numbers are
  first choices, not measured.)
  Reason: the start of a value often answers what the model needs, and a round
  spent on `println(first(x, 10))` is a round lost; S2 ran out of rounds (8) in
  every rehearsal of 2026-09-23.
- **D3. One run, two descriptions.** `execute_julia_code` and
  `execute_julia_expression` take a keyword that names the function which describes
  the last value. Its default is the model's description of D2, so the model, the
  conversation (`AssistantTurn.jl:751`) and MCP are unchanged in form. The evaluator
  and the chat composer pass the person's description of D1. The description is
  appended after the captured output, not printed into the pipe, so the two parts
  do not mix.
- **D4. The conversation shows what the model got.** The result of a model's tool
  call in the conversation stays the model's answer.

## 4. Steps

Each step: a test first where one fits, the change, the narrowest test that covers
it, and a commit. Work in a worktree of its own, from `main`.

- [x] **Step 1: the two descriptions in the tool.** In `CodeExecution.jl`: the
      keyword of D3 on both functions; `_run_expression` appends the description
      after the capture; the model's description of D2 and the person's of D1, as
      named functions that follow `documentation/rule/naming-rules.md`. The
      docstring of `execute_julia_code` says what it does now (no history).
      `CodeExecutionTest.jl` asserts the trimmed form (start, mark, end, note) for
      a long value, the unchanged form for a short one, and the person's form for
      a long vector (a header line and `⋮`). Test: `test_kernel()`'s code
      execution suite, or the file alone.
      **Done** (2026-09-26, commit `ba5699b9`). Names chosen: the keyword is
      `describe_value`; the model's default is the private `_describe_value_for_model`
      (only ever used as that default, so it stays unexported); the person's is the
      exported `describe_value_for_person` (D1's audience is cross-module: the
      evaluator and the assistant composer both need to reach it). `_run_expression`
      now collects `result` outside the `redirect_stdio` block and appends
      `describe_value(result)` to `stdout_output * stderr_output` after the pipes
      close, rather than `print`ing the description inside the block. Both
      `describe_value_for_person` and the new 600-character branch of
      `_describe_value_for_model` wrap their `sprint(show, MIME"text/plain"(), …)`
      call in `Base.invokelatest`, mirroring the existing `Function` branch's use of
      it — needed for a value whose type or method the evaluated code just defined
      in a newer world; not stated in D1's formula, added for correctness, a value
      that formula did not need to spell out. The `Function` and short-`repr`
      branches run before the new branch and return early, so a `Function` value
      never reaches it. Test: `test_code_execution()` — 23/23 pass before the
      change (stashed and reverted after, to measure), 31/31 after: the trimmed-
      value testset goes from 4 assertions to 5 (drops `!occursin("500", long)`,
      which no longer holds any meaning once the text is the REPL display rather
      than a summary line, adds the mark-line and note-text checks), a new
      "a short value is unchanged" testset adds 2, and a new "the person's
      description shows the value as the REPL does" testset adds 5. No
      `Fail`/`Error` either run.
- [x] **Step 2: the evaluator and the composer use the person's description.**
      `Evaluator.jl:429` and `AssistantTurn.jl:222`. A test in
      `test/projectured/editor/EvaluatorToplevelTest.jl` evaluates a form whose value
      is long (for example `collect(1:1000)`) and checks that the result text shows
      the header line of the REPL and no note to the model. Test:
      `test_evaluator_toplevel()`, and `test_assistant_mvp()` for the composer.
      **Done** (2026-09-26, commit `8253de60`). `AssistantTurn.jl`'s
      `SubmitJuliaOperation` (the chat composer, ALT+ENTER / ENTER on a Julia
      insertion) called `execute_julia_code` through `call_tool(set,
      "execute_julia_code"; …)`, which dispatches to the handler
      `register_default_tools!` registered — a closure fixed at registration
      time with no `describe_value` override, shared with the model's own tool
      calls. There is no way to pass a keyword through `call_tool`, so
      `SubmitJuliaOperation` now calls `execute_julia_code` directly, matching
      the pattern `Evaluator.jl` and `ConversationEditor.jl` already use; `target`
      stays `editor` either way, so `test_assistant_editor_reference()` (which
      guards a past bug in exactly that forwarding) still passes.
      **A third call site that answers a person:** `ComposerEvaluateOperation` in
      `source/conversation/ConversationEditor.jl:383` (documented at
      `documentation/package/conversation/conversation.md:66`), the plain
      conversation composer's own ALT+ENTER evaluation, distinct from the
      assistant's chat composer. The implementing agent found it and left it; D1
      covers it, because a person reads that result, so it passes
      `describe_value_for_person` too (2026-09-26).
      Test: the combined run (`test_evaluator_toplevel()` +
      `test_assistant_mvp()` + `test_execute_julia_code()` +
      `test_assistant_editor_reference()`, `ProjecturedTest`) gives 373 pass,
      4 fail, 0 error — `test_evaluator_toplevel()` alone is 219/219, and the 4
      fails are all in `test_assistant_mvp()`'s "the assistant card fills its
      page" testset. That same 4-fail count reproduces identically on
      unmodified main at commit `66f18230` (127 pass, 4 fail — checked in a
      throwaway detached worktree) and after Step 1 alone, so it is a
      pre-existing, environment-level failure, not a regression from this
      step. **Baseline correction:** the task's stated baseline for
      `test_assistant_mvp()`, "113 pass and 4 broken", does not match this
      machine's current main — measured here as 127 pass, 4 fail (`Fail`, not
      `Broken`); the stated number is stale.
- [x] **Step 3: the documents.** Every document that describes the answer of
      `execute_julia_code` (search `documentation/` for "last value", "summary" and
      the tool name) says what D1 to D3 say.
      **Done** (2026-09-26). Searched `documentation/` for "last value", "Print
      the part", "summary(value)", "never cut in the middle", "described by
      its" and "whole or described", together with every file that mentions
      `execute_julia_code`. Two files described the answer's shape and needed a
      rewrite: `documentation/package/kernel/agent.md` (the tool's own
      paragraph — now states the `describe_value` keyword, the 600-character
      trim, and a second paragraph for `describe_value_for_person`) and
      `documentation/package/kernel/editor.md` (the MCP section, which said "It
      returns the repr of the last value plus any captured stdout/stderr" —
      wrong on the order even before this plan; now short/limited/trimmed).
      Every other hit (`conversation.md`, `assistant.md`, `mcp.md`,
      `mcp-guide.md`, `assistant-guide.md`, `architecture.md`,
      `system-anatomy.md`, `engineer-tour.md`, `orientation.md`,
      `testing-guide.md`, `architecture-decisions.md`,
      `architecture-invariants.md`, `finding-and-selecting.md`, `operation.md`,
      `undo.md`, `transcript.md`, `sdl.md`) names `execute_julia_code` for
      something else (who calls it, what a `Document` result does, the
      persistent scratch module, a test file) and stays true unchanged. Test:
      `test_naming()` and `test_documentation()` (`ProjecturedTest`) — 2/2
      pass, 0 fail, 0 error; `test_documentation()` counts these as a single
      aggregate assertion each, so this is the whole repository's report, not
      only the two changed files.
- [x] **Step 4: the landing,** when the owner says so. **Done** (2026-09-26): the owner said "Land it"; the branch was rebased onto main at 8441a948, and the code execution and evaluator suites passed again there before the fast-forward.
