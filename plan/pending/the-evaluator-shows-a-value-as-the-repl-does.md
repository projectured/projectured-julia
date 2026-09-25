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
  REPL display with `:limit => true` and 20 rows × 100 columns; when that is still
  longer than 600 characters, the start and the end are kept and the middle becomes
  one mark, "⋯ N characters left out ⋯". One line follows: "The value is trimmed;
  whole, it prints N characters. Print a part, as `println(first(x, 10))` or
  `println(names(x))`." A `Base.Text`, a `Function` and a long `AbstractString`
  keep their present rules. (The numbers are first choices, not measured.)
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

- [ ] **Step 1: the two descriptions in the tool.** In `CodeExecution.jl`: the
      keyword of D3 on both functions; `_run_expression` appends the description
      after the capture; the model's description of D2 and the person's of D1, as
      named functions that follow `documentation/rule/naming-rules.md`. The
      docstring of `execute_julia_code` says what it does now (no history).
      `CodeExecutionTest.jl` asserts the trimmed form (start, mark, end, note) for
      a long value, the unchanged form for a short one, and the person's form for
      a long vector (a header line and `⋮`). Test: `test_kernel()`'s code
      execution suite, or the file alone.
- [ ] **Step 2: the evaluator and the composer use the person's description.**
      `Evaluator.jl:429` and `AssistantTurn.jl:222`. A test in
      `test/projectured/editor/EvaluatorToplevelTest.jl` evaluates a form whose value
      is long (for example `collect(1:1000)`) and checks that the result text shows
      the header line of the REPL and no note to the model. Test:
      `test_evaluator_toplevel()`, and `test_assistant_mvp()` for the composer.
- [ ] **Step 3: the documents.** Every document that describes the answer of
      `execute_julia_code` (search `documentation/` for "last value", "summary" and
      the tool name) says what D1 to D3 say.
- [ ] **Step 4: the landing,** when the owner says so.
