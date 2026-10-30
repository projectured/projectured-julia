# Every kind of Julia code prints with no compile

Status: IN PROGRESS, 2026-10-30. Step 1 is done. Steps 1 and 2 are done. Step 3 is next.

## The ask

The live check of [the-window-answers-while-the-assistant-works.md](the-window-answers-while-the-assistant-works.md)
(step 4) found two causes of long frames that its steps do not remove. The owner
answered "Yes" to the question "Do you want me to write that new plan?", with these
two changes:

1. The Julia sample file holds one of each kind of Julia code. A test fails when a
   new kind is not in it.
2. The key of an output line has one type for every count of spans.

## The problem

The live check, 2026-10-30, in `/var/tmp/ide-profile-20261030/`: one assistant
turn of the owner in `omnet_ide --assistant=acp --context=32768 --mcp
~/workspace/inet-cpp`, on the `window-answers` branches. 3,749 frames, 2 over 5 s.

### Cause 1: the Julia domain compiles ahead one kind of code

The domain workload of `ProjecturedJulia` opens the file of
`make_workload_file(::Type{JuliaFile})` (`source/domain/julia/JuliaModule.jl:144`),
which is `alice = 1 + 2`. So the print of each other kind of Julia code compiles on
the loop the first time a window shows it, in a file and in a turn. One
`print_document` of a Julia projection takes 0.4–0.6 s to compile.

The frame of 09:40:09 took 18.9 s. The code of the turn used kinds that the warm
turn of the assistant does not have: function, using, curly, try, while, do, if,
const, return, break, continue, comment, broadcast, unary operation, field access,
toplevel. The frame compiled 350 calls in 18.6 s: 28 `print_document` methods of
Julia projections, `_walk_markers`, `_dispatch_print` and closures of the syntax
print. In the whole profile, 35 such `print_document` methods compiled, 8.9 s.

The signature of these calls holds no type of the assistant or of a window, for
example:

    print_document(::JuliaFunctionToSyntaxNode, ::RecursiveProjection,
                   ::JuliaFunction{ReactiveCell{Any}, …}, ::PrinterContext)

So a file of the domain that holds each kind compiles the same calls that a turn
needs.

### Cause 2: the key of an output line has a type for each count of spans

`_make_output_line` (`source/platform/syntax/SyntaxToText.jl:808`) keys the
`TextLine` that it reuses by
`(:line, indentation, objectid(fold), map(objectid, line.spans)..., count)`. The
tuple has one element for each span of the line, so each new count of spans is a
new tuple type. `_deco_span`, and the `get!`, `get`, `setindex!`, `in` and
`hashindex` of the two dictionaries, compile again for it: 42 compiles of
`_deco_span`, 5.0 s. No workload can cover every count. The frames of 2–4 s
(09:40:26, 09:40:38, 09:41:21) are mostly these.

## Decisions

- **D1.** The sample file of the Julia domain holds one of each kind that the
  parser makes. It stays a file that a person can read: a short module with a
  struct, a function, a loop, and so on, not a list of unrelated lines. Its first
  line stays `alice = 1 + 2`, so the steps of `run_file_workload` (a click on
  `alice`, a key, a save, an undo) do not change.
- **D2.** The test compares the kinds in the parsed sample file with
  `subtypes(JuliaDocument)`. A kind that the parser never makes, such as
  `JuliaInsertion`, is in a named list in the test, each with the reason. So a new
  kind of the domain fails the test until the sample file or the list holds it.
- **D3.** The key of an output line keeps the object ids of its spans in one
  `Vector{UInt}`: `(:line, indentation, objectid(fold), ids, count)`. A vector
  hashes and compares by its content, so the reuse of a line stays the same, and
  the key has one type. A hash of the ids into one number is not used, because two
  lines with the same hash would share one `TextLine`.
- **D4** (my recommendation, not an answer of the owner). The work continues on the
  `window-answers` branches of both repositories. Both plans record the same lists
  again, and one recording at the end covers both. The two plans land together.

## Steps

1. [x] **The key of an output line has one type.**
   - `_make_output_line` in `SyntaxToText.jl` makes its key with D3, in a small
     function of its own, `_make_output_line_key(line)`.
   - A test in `test/platform/projection/SyntaxToTextTest.jl`: the keys of a line
     with one span and of a line with five spans have the same concrete type, and
     two lines with the same spans in the same order have equal keys.
   - Tests: `test_syntax_to_text()`; then `test_julia_to_syntax()`, because the
     Julia print reuses lines through this cache.
2. [x] **The Julia print writes each kind back as code.** The sample text of step 3
   found two faults of the print, which are on main too, and the save of the sample
   file writes text that does not parse. The owner answered "Yes" to "Shall I add
   this step to the plan and fix both faults?"
   - [x] `JuliaFunction` keeps its keyword parameters in a list of its own,
     `keyword_parameters`, as `JuliaCall` keeps its keyword arguments. The parser
     fills it, and the print writes `; …` after the positional parameters. The
     evaluation parses the print (`make_julia_expression`), so it needs no change.
   - [x] A body with no statement prints a break before `end`. The owner answered
     "Yes" to "Shall I fix the empty body with A, with that guard?":
     - **A.** A block writes the break before each statement and no break after
       the last one. Each statement with a body writes the break before its `end`,
       `else`, `elseif`, `catch` and `finally`, as a pretty printer does. An empty
       block then prints nothing, and the statement still writes its `end` on a line
       of its own. A template that forgets the break prints every body wrong, not
       only an empty one, so any test of an example finds it.
     - **The guard.** The test of the sample text (step 3) also checks that the
       sample prints back to the same code.
     - An empty block offers no caret of its own. The owner: "A person can press
       insert or enter to add a statement in an empty block, so there are easy
       ways out."
   - [x] `begin … end` prints with its `begin` and its `end`. The owner answered
     "Yes" to "Shall I fix `begin … end` as a third part of step 2?" A `:block` in
     the place of a value, an argument or a statement becomes a `JuliaBegin`; the
     body of a construct stays a `JuliaBlock`.
   - Tests: round-trip tests in `JuliaParserTest.jl`; `test_julia_tooltip()`;
     `test_julia_to_syntax()`; `test_example` of `julia_example` and
     `julia_code_example`; `test_formula_names()`, `test_formula_evaluation()`.
3. [ ] **The Julia sample file holds each kind.**
   - `make_workload_file(::Type{JuliaFile})` gets the new text (D1). Its `shown`
     stays `r"alice"`.
   - A test in `test/domain/julia/` (D2) parses the text with the parser of the
     domain, walks the document, and compares the kinds.
   - Tests: the new test; `test_julia_file_view()`; the file workload of the
     Julia file in `test/projectured/editor/FileWorkloadTest.jl`.
4. [ ] **Record the lists again**, in this order, with
   `precompile_calls = "none"` for the packages that each one records (Decision 7
   of `documentation/design/compile-ahead.md`):
   `record_package_calls!("ProjecturedPlatform")`,
   `record_package_calls!("ProjecturedJulia")`,
   `record_application_calls!("ProjecturedBuild", "projectured")`, then in
   omnet-julia `record_package_calls!("OmnetIde")` and
   `record_application_calls!("OmnetIdeBuild", "omnet_ide")`.
   - Check: `ProjecturedJulia/precompile/workload.txt` holds a `print_document` of
     each `Julia…ToSyntax…` projection, and no list holds a `_deco_span` with a
     tuple key of a variable length.
5. [ ] **The live check.** The profile harness of `/var/tmp/ide-profile-20261030/`
   again, with one long turn of the owner whose code uses many kinds. Counts:
   - no compile of a `print_document` of a Julia projection in the trace of the
     turn;
   - no compile of `_deco_span` after the window opened;
   - no frame over 5 s outside the held frames of code units, and the count of
     frames over 1 s against 17;
   - the share of compile samples of the loop inside frames, without the held
     frames, against 50%.

   Then this plan and the plan of the window move to `plan/done/`, and I ask the
   owner to land both branches.

## Not in this plan

- A code unit that walks the documents compiles `_walk_document!` once for each
  type of document and type of predicate: 364 methods, 13.2 s, in one tool call of
  the turn. The loop ran held frames meanwhile, so the window answered. The tool
  call took 13 s longer.
- 39 samples of the loop in thrown errors at other places than the reference walk:
  a method lookup, `_strict_check` of `ChartToChartPlot`, `_get_field` in
  `read_gesture_outward` and in `PathChain`, and the zero-argument constructors of
  `get_insertion_candidates`.
- The reader of each kind of Julia code, at a click or a key in it. The sample file
  gets one click. Step 4 measures what remains.

## As built

### Step 1

- `_make_output_line_key(line)` in `SyntaxToText.jl` gives
  `(:line, indentation, objectid(fold), UInt[objectid(span) for span in spans])`, and
  `_make_output_line` adds the count to it. `counts` and the cache of `_deco_span`
  now see one key type.
- The test "the key of an output line has one type for every count of spans" in
  `SyntaxToTextTest.jl`: one concrete type for 1 and 5 spans, equal keys and
  hashes for the same spans, a different key for the spans in another order.
- `test_syntax_to_text()`: every test set passes, the new one 5 of 5.
  `test_julia_to_syntax()`: 18 of 18.

### Step 2

- The keyword parameters: `JuliaFunction` has the field `keyword_parameters`, last,
  with an empty default. With two collections, `@document` makes no constructor that
  wraps a plain vector (its Rule C), so an outer constructor
  `JuliaFunction(name, params::AbstractVector, body, …, keyword_parameters::AbstractVector)`
  wraps both, as the one of `JuliaCall` does. Its typed `params` makes it a
  different signature from the untyped Rule Y forms.
- The print has the form of the print of a call: `(x, y` from `params`, and
  `; k = 1)` from `keyword_parameters`, whose open text is `; ` only when it holds a
  parameter.
- Two readers of a function read the keyword parameters too: the signature of the
  tooltip (`scale(p, factor; by, unit)`, and a parameter with a default shows its
  name), and the walk of the formula domain that finds the free names of a body.
- Tests: `test_julia_parser()` 149 of 149, `test_julia_tooltip()` 14 of 14,
  `test_julia_to_syntax()` 18 of 18, `test_julia_workload_file()` 5 of 5,
  `test_formula_names()` and `test_formula_evaluation()` pass. `test_example` of
  `julia_example`: 3,445 pass and 84 fail; the 84 are the known baseline of main
  (no caret on the 6 name leaves of the `factorial` example, 28 places × 3 edits).
  `julia_code_example` did not run in that process: the failure of the first
  example stopped it. The run of the empty body measures it.
- The empty body (A): `JuliaBlockToSyntaxNode` writes `open` and `sep` breaks and
  no `close`. `_make_julia_body_keyword(text, style)` makes the leaf of `end`,
  `else`, `catch` and `finally` with the break as its `open` text, and `struct`,
  `module`, `for`, `while`, `do`, `let`, `begin`, `function` and `try` use it. The
  `if` keeps its fixed parts: its `else` and its `end` are `make_text_block` texts
  of a function (`"\nelse"`, `"\nend"`, or `""`), because the nested `if` of an
  `elseif` writes its own `end`.
- A file of many statements is one block, whose close break was the last
  character of the saved text. `emit_text(::JuliaFile)` now writes the final break
  (`* "\n"`, as `MathFile` does). The saved text still starts with a break and
  indents the top level by two spaces, because the top level prints as a body; that
  is a fault of its own, not in this plan.
- Tests: 13 new round trips in `JuliaParserTest.jl` (each kind with an empty body,
  an `elseif`, a nested loop); `test_julia()` 730 of 730; `test_fsm()`,
  `test_process()`, `test_formula()` 895 of 895. `test_example(julia_example)`:
  the 84 known failures. `test_example(julia_code_example)`: 423 type-in failures,
  the same lines as on clean main (`no cursor in Graphics image` on name leaves).
  Its printer test makes 16,938 checks against 17,030 on main, and its position
  navigation reaches 420 states against 421. A probe that records the drawn caret
  of each reached state (`caret-places.jl` in the scratchpad of the session) finds
  the same 346 drawn places on both. The one lost state is the place after the last
  break of the top-level block, the empty line at the end of the view, which draws
  no caret on main either.
- `begin … end` (the third part): `_convert_head(::Val{:block})` makes a
  `JuliaBegin`, and a new `_convert_body` makes the `JuliaBlock` of the body of
  `module`, `function`, `for`, `while`, `let`, `do`, `try` and `if`; `struct` builds
  its block itself. A lambda takes its body with `_convert_lambda_body`: one
  statement stays as it is, several go into a `JuliaBegin`, because a lambda writes
  no `end` of its own. The short definition `f(x) = begin x end` still prints as
  `f(x) = x`: Julia reads both as the same `Expr`. The header of `JuliaParser.jl`
  states the rule by place in the place of the old line "never `JuliaBegin`".
- Tests: round trips of `begin … end` as a value, a macro argument, a statement of a
  body, a call argument, and a lambda of two statements. One assertion of
  `JuliaParserTest` named the old behavior (`parse_julia("begin a; b end") isa
  JuliaBlock`); it now asserts its intent, two statements in the block of the
  `JuliaBegin`. `JuliaBegin` leaves the list of kinds that only an edit makes.
- `test_julia()` 744 of 744; `test_fsm()` 271, `test_process()` 316,
  `test_formula()` 308, each with no failure. The two Julia examples: the same
  counts as after the empty body, and the 423 type-in failures of `julia_code` are
  the lines of clean main.

### Step 3 (stopped: two faults of the Julia print, see step 2)

- The sample text (`_WORKLOAD_FILE_TEXT` in `JuliaModule.jl`, a module `Sample`)
  holds 57 of the 60 kinds. The three others come only from an edit:
  `JuliaBegin` (the parser makes a `JuliaBlock` of `begin … end`), `JuliaInsertion`
  and `JuliaObject`. A walk of the names of `JuliaModule` finds the kinds, so the
  test package needs no `InteractiveUtils`.
- `test_julia_workload_file()` passes, 5 of 5. `run_file_workload(JuliaFile)`
  fails: the save writes the print of the sample, and the file change feed reads
  `ready = true; done = false` with "Expected `end`".
- The cause is two faults of the Julia print, the same on main
  (`/var/tmp/every-kind/snippets.jl`):
  - A block with an empty body prints no break before `end`: `while falseend`,
    `for x in 1:2end`, `if trueend`, `trycatchend`, `struct Send`, `module Mend`.
  - `JuliaFunction` has no list of keyword parameters, as `JuliaCall` has. The
    parser puts the `Expr(:parameters)` of `function g(x; y = 1)` among the
    positional parameters as a named tuple, and it prints
    `function g((; y = 1), x)`, which is other code. A call and a short definition
    print correctly.
- After step 2: the sample writes the docstring as `"""…"""` and the named tuple as
  `(; …)`, the forms that the print writes. The test gets the guard: the sample
  prints back to the same code, compared with no line numbers (a strip of its own,
  because `Base.remove_linenums!` keeps the line numbers of the top level and of a
  macro call). `test_julia_file_view()` and `run_file_workload(JuliaFile)` pass.
  The guard fails on one statement: `else begin nothing end` prints as
  `else nothing`.
- That is the third fault. The parser maps every `:block` to a `JuliaBlock` (its
  header says so: "`begin … end` parses to a block, so it becomes `JuliaBlock`
  (never `JuliaBegin`)"), so a `begin … end` prints with no `begin` and no `end`.
  As a body this keeps the code; in other places it does not
  (probe `begin-probe.jl` in the scratchpad of the session):
  `@testset "a" begin … end` prints as a `@testset` with no body and the statements
  after it, and `x = begin a = 1; a + 1 end` prints as `x = a = 1` and `a + 1`.
  Both parse, so nothing reports them. A question for the owner.
