# Every kind of Julia code prints with no compile

Status: IN PROGRESS, 2026-10-30. Step 1 is done. No decision is open.

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
2. [ ] **The Julia sample file holds each kind.**
   - `make_workload_file(::Type{JuliaFile})` gets the new text (D1). Its `shown`
     stays `r"alice"`.
   - A test in `test/domain/julia/` (D2) parses the text with the parser of the
     domain, walks the document, and compares the kinds.
   - Tests: the new test; `test_julia_file_view()`; the file workload of the
     Julia file in `test/projectured/editor/FileWorkloadTest.jl`.
3. [ ] **Record the lists again**, in this order, with
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
4. [ ] **The live check.** The profile harness of `/var/tmp/ide-profile-20261030/`
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
