# Layer 18 — tool (`source/kernel/tool/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed.

## Verdict

The tool layer passes its own tests: the five kernel suites pass 363 checks on the
baseline run. Its two halves disagree when a `ToolSet` declares no API, which is the
default for every `Editor`: the documentation tools read only the 23 kernel modules,
and the code tool reads every loaded `Projectured` package. `execute_julia_code`
swaps the process-wide stdout and stderr into pipes that no task reads until the call
ends, so a large print can stop the editor task, and the output of other tasks and
editors goes into the answer. The `Tool` constructor takes four positional arguments,
so the argument guard `test_arguments()` must fail on it. The other findings are a
catch that also stops the pass-through exceptions, private names that two
repositories reach, and a guide index that starts a new section at each comment line
in a code block.

## Shape

- Purpose: the capability surface of one editor. A `ToolSet` holds the tools and the
  resources that a person, an in-process agent loop and an MCP server call; it runs
  Julia code in a scratch module, reads and searches the guides and the API, and
  ranks a description by its meaning.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `ToolModule.jl` | 62 | ⬜ | module docstring, one export statement (45 names), seven includes |
  | `Tool.jl` | 238 | ⬜ | `Tool`, `Resource`, `ApiEntry` and its readers, `MeaningModel`, `ToolSet`, `observe_evaluations!` |
  | `ToolSet.jl` | 186 | ⬜ | `declare_api!`, `set_meaning_model!`, the tool and resource registry, `read_resource` |
  | `CodeExecution.jl` | 380 | ⬜ | the scratch module, `execute_julia_code` / `execute_julia_expression`, the value description, the nearest names, the observer notice |
  | `SearchQuery.jl` | 276 | ⬜ | `SearchTerm`, `KeywordQuery`, `parse_keyword_query`, the three query modes |
  | `Documentation.jl` | 1391 | ⬜ | guide roots and guide index, the API index by reflection, the readers, `search_guides`, `search_api`, URI resolution, argument coercion |
  | `MeaningSearch.jl` | 463 | ⬜ | the stores and files of meaning vectors, the build task, the rank by meaning, the rank fusion |
  | `DefaultTools.jl` | 327 | ⬜ | the tool descriptions, `register_default_tools!` |

- Imports: none. The module has no `using` and no `import` of a kernel module. It
  reads `ProjecturedKernel` by `parentmodule(@__MODULE__)`, and so it reads every
  layer by reflection, also the five layers above it.
- Imported by: `LlmModule`, `AgentModule` and `EditorModule` in the kernel;
  `AssistantModule`, `ConversationModule`, `UndoModule`, `ProjecturedMcp`,
  `ProjecturedAnthropic`, `ProjecturedOllama` and `ProjecturedKernelExample`; in
  omnet-julia `OmnetCampaignUi`, the notebook page, the campaign and IDE windows and
  their tests. inet-julia does not use it.
- Public surface: 45 exported names.
  - 22 have a user in main code outside the layer: `Tool`, `Resource`, `ToolSet`,
    `MeaningModel`, `set_meaning_model!` (the llm layer only), `register_guide_root!`
    and `observe_evaluations!` (omnet-julia only), `register_tool!`, `list_tools`,
    `find_tool`, `call_tool`, `declare_api!`, `list_resources`, `read_resource`,
    `register_default_tools!`, `execute_julia_code`, `execute_julia_expression`,
    `get_last_evaluated_value`, `describe_value_for_person`,
    `read_function_documentation`, `search_guides`, `search_api`.
  - 13 have only test users outside the layer: `ApiEntry`, `get_api_entry_names`,
    `describe_api`, `describe_resources`, `list_guides`, `read_guide`,
    `list_modules`, `list_types`, `list_functions`, `read_module_documentation`,
    `read_type_documentation`, `parse_keyword_query`, `is_keyword_match`.
  - 7 have no user outside the layer: `api_entry_bindings`, `api_source_name`,
    `register_resource!`, `find_resource`, `read_value_documentation`, `SearchTerm`,
    `KeywordQuery`.
  - 3 have no user at all: `get_api_modules`, `register_tools!`,
    `register_resources!` (L18-22).
- Module/Interface/Defaults: the layer has no interface file and declares no open
  generic. Its seams are values: the `handler` of a `Tool`, the `compute` of a
  `MeaningModel`, the observers of a `ToolSet`. No fragment belongs in another layer,
  but `DefaultTools.jl` names verbs of higher layers in its text (L18-12), and the
  guide reader and the vector store read and write folders of the repository
  (`documentation/`, `build/meaning/`) when no bundle folder exists.
- State:
  - Per editor, on the `ToolSet`: the tools, the resources, the scratch module, the
    last value, the observers, the declared API, the meaning model. Each handler
    closes over its own set.
  - Process-global: `_EXTRA_GUIDE_ROOTS` (a registry that any caller writes, no
    lock, L18-13), `_GUIDE_INDEX`, `_API_INDEX`, `_DECLARED_INDEX` (one entry per
    distinct declaration, never removed), `_INDEX_LOCK`, `_MEANING_STORES` with its
    lock, and the test knobs `_MEANING_FOLDER` and `_MEANING_WAIT_SECONDS`. Each call
    of `execute_julia_code` also swaps the process streams (L18-4).
  - Threads: the meaning build runs on `Threads.@spawn`; the stores and the indexes
    are read and written under their locks. The `ToolSet` itself has no lock; its
    writers (`register_default_tools!` on the turn task and on the MCP task, the
    tools on the editor task) are `@async` tasks of one thread and do not yield inside
    a write.
- Tests: 5 files in `test/kernel/tool/`, 1,417 lines. On the baseline run they pass:
  Declared API 129, Search query 61, Meaning search 67, Search answer 75, Code
  execution 31. The umbrella adds `McpTest.jl`, `AssistantMvpTest.jl`,
  `EvaluatorToplevelTest.jl`, `ApplicationTest.jl`, `SearchScaleTest.jl`,
  `InterfaceApiTest.jl` and `ReferencedDocumentEditorTest.jl`. The tests cover the
  declaration in both directions, the query forms, the hit format, the meaning
  store and its file, and the value description. They do not cover large output,
  overlapped calls, pass-through exceptions, a zero limit, fenced comment lines, the
  catalogue under a pair declaration, the guide registry, and a whole-surface search
  for a name outside the kernel (L18-15). Four assertions can not fail (L18-14).

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 2 | 5 | 6 |
| Architecture | 0 | 3 | 0 |
| Shape | 1 | 0 | 2 |
| State | 1 | 1 | 0 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 4 |
| Tests | 0 | 2 | 0 |
| **total** | **4** | **11** | **14** |

## Findings

### L18-1 With no declared API, the documentation tools read only the kernel, and the code reads every package

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `_projectured()` at `Documentation.jl:176` is `parentmodule(@__MODULE__)`, and `_scratch_sources` binds the umbrella.
- Where: [Documentation.jl:176](../../../source/kernel/tool/Documentation.jl#L176) ⬜,
  [Documentation.jl:211](../../../source/kernel/tool/Documentation.jl#L211) ⬜,
  [Documentation.jl:449](../../../source/kernel/tool/Documentation.jl#L449) ⬜,
  [Documentation.jl:851](../../../source/kernel/tool/Documentation.jl#L851) ⬜,
  [DefaultTools.jl:78](../../../source/kernel/tool/DefaultTools.jl#L78) ⬜,
  [CodeExecution.jl:11](../../../source/kernel/tool/CodeExecution.jl#L11) ⬜,
  [CodeExecution.jl:313](../../../source/kernel/tool/CodeExecution.jl#L313) ⬜
- Evidence:
  - `_projectured() = parentmodule(@__MODULE__)` is `ProjecturedKernel`, because
    `ProjecturedKernel.jl` includes `ToolModule.jl`. So `_index_api`,
    `list_modules`, `_find_module`, `_api_modules` and `_get_writable_names` read
    the 23 kernel layer modules and nothing else.
  - `_scratch_sources` gives the code the `Projectured` umbrella, or every loaded
    `Projectured*` package.
  - A default `Editor` holds `ToolSet()`, and so does the editor of
    `run_window_editor(…; mcp = true)`, the example of `mcp-guide.md`. There,
    `search_api("CellVector")` answers "No API matches",
    `read_function_documentation("PaneModule", …)` answers "Module 'PaneModule' not
    found", and the "Did you mean" hint offers kernel names only. `CellVector(…)`
    runs.
  - The other direction also fails. `_module_functions` and `_struct_types` read
    `names(mod; all = true)`, so the index offers kernel names that no module
    exports, such as `EditorModule.read!`. `_flat_reexport!` binds exported names
    only, so the model writes `read!` and reaches `Base.read!`.
  - plan/done/three-kinds-of-search.md measured "797 API entries" for the whole
    surface; those are the entries of the kernel.
- Rule: the contract of `ToolSet` and agent.md, "One list determines two things …
  the two are never allowed to differ"; PAR-AI-SAME-GUARANTEES.
- Fix: One function answers the modules of the whole surface, and both halves use
  it: `_scratch_sources` for the code; the index, the catalogue, `_find_module` and
  the resources for the documentation. Index only exported names in the whole
  surface.
- Reach: `Documentation.jl`, `DefaultTools.jl`, `CodeExecution.jl`; the counts of
  umbrella tests that search with an empty API (`McpTest.jl`, `SearchAnswerTest.jl`)
  change.

### L18-2 A call that prints more than a pipe holds stops the editor task

- Category: Correctness · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run: a print of 200 000 bytes inside `redirect_stdio` into a `Pipe` that nothing reads is still blocked after 5 s. In `_run_expression` the reader of the pipe runs only after the code ends.
- Where: [CodeExecution.jl:217](../../../source/kernel/tool/CodeExecution.jl#L217) ⬜
- Evidence:
  - `_run_expression` makes two `Pipe`s, redirects stdout and stderr into them for
    the whole evaluation, and reads them only after `redirect_stdio` returns
    (lines 235–240). No task reads a pipe while the code runs.
  - Base `uv_write` waits until libuv completes the write (`uv_write_wait` in
    `base/stream.jl`), and a Linux pipe holds 64 KiB. So a print of a large frame,
    or `for i in 1:100_000; println(i); end`, waits for a reader that runs only
    after the print.
  - The tool runs on the editor task (`run_on_editor_task!`, `AgentLoop.jl:77`,
    `Mcp.jl:155`). The window stops, and no timeout ends the call.
  - The IOCapture package reads its pipe on an `@async` task for this reason. The
    test prints 300 short lines, far below the limit.
- Rule: bug
- Fix: Before the evaluation, start one task per pipe that reads it into an
  `IOBuffer`. After the write ends close, wait for the two tasks.
- Reach: `CodeExecution.jl`; a new case in `CodeExecutionTest.jl`.

### L18-3 The `Tool` constructor takes four positional arguments, and the argument guard fails on it

- Category: Shape · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run of the argument guard: `source/kernel/tool/Tool.jl:30 Tool takes 4 positional arguments`.
- Where: [Tool.jl:30](../../../source/kernel/tool/Tool.jl#L30) ⬜
- Evidence: `Tool(name, description, parameters, handler; result_mime_type …) = …`
  has four positional arguments and no `# @positional:` marker. `argument_violations`
  in `test/suite/arguments.jl` reads every `=` definition under `source/` and fails
  on a public name over three. Commit 2224b9d8 (2026-09-25) added this constructor
  after plan/done/keyword-arguments.md closed on 2026-09-23; that plan moved
  `Resource` and `call_tool` to keywords.
- Rule: code-quality-rules.md §4; the guard `test_arguments()`.
- Fix: `Tool(name; description, parameters, handler, result_mime_type = "text/plain")`.
- Reach: `Tool.jl`, `DefaultTools.jl` (6 calls), `source/platform/undo/UndoDocument.jl`,
  `example/platform/fault/FaultExamples.jl`, and 5 test files (`SearchAnswerTest.jl`,
  `AnthropicTest.jl`, `OllamaTest.jl`, `AssistantMvpTest.jl`, `McpTest.jl`).

### L18-4 Each code call swaps the process-wide stdout and stderr, so all editors and tasks share them

- Category: State · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `redirect_stdio` swaps the streams of the process.
- Where: [CodeExecution.jl:221](../../../source/kernel/tool/CodeExecution.jl#L221) ⬜
- Evidence:
  - `redirect_stdio` replaces `Base.stdout`, `Base.stderr` and the file descriptors
    1 and 2 of the process until the call ends.
  - Every other task and thread that prints while the code runs writes into this
    answer: a simulation on another thread, a second editor, a producer task. That
    output does not reach the console.
  - Two calls that overlap on two tasks restore the wrong stream. Call A saves the
    console and sets pipe A. Call B saves pipe A and sets pipe B. A ends, closes
    pipe A and restores the console. B ends and restores pipe A, which is closed.
    After that, every `println` of the process fails. An overlap needs a call that
    yields (`sleep`, I/O, a wait) while a call of a second editor runs; each editor
    runs its tools on its own task.
- Rule: PAR-PER-EDITOR-STATE
- Fix: Hold one process lock around the swap, so that two calls never nest, and
  read the pipes on tasks (L18-2). Say in the docstring that the output of other
  tasks can enter the answer.
- Reach: `CodeExecution.jl`.

### L18-5 An error drops all that the code printed before it

- Category: Correctness · Severity: Medium · Confidence: Confirmed (the partial run:
  Suspected)
- Where: [CodeExecution.jl:233](../../../source/kernel/tool/CodeExecution.jl#L233) ⬜
- Evidence:
  - The pipes are read and closed on the success path only. When a statement
    throws, the `catch` answers the error text; the output that the code wrote
    before is lost.
  - Both pipes stay open until the garbage collector finalizes them: four file
    descriptors for each call that fails.
  - A model that runs `x = f(); println(x); g(x)` with a fault in `g` sees only the
    error. It can not see that `f` ran, and it runs `f` again.
  - `Meta.parseall` keeps the statements before a syntax error, so a call with a
    syntax error on its last line runs its first lines. Suspected: needs a run of
    `"println(1)\ny = ("`.
- Rule: bug
- Fix: Close and read the pipes in a `finally`, and put the printed text before the
  error text.
- Reach: `CodeExecution.jl`; `CodeExecutionTest.jl`.

### L18-6 A search with a limit below one throws, and the contract says it never throws

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [Documentation.jl:956](../../../source/kernel/tool/Documentation.jl#L956) ⬜,
  [Documentation.jl:971](../../../source/kernel/tool/Documentation.jl#L971) ⬜,
  [Documentation.jl:1116](../../../source/kernel/tool/Documentation.jl#L1116) ⬜,
  [Documentation.jl:1317](../../../source/kernel/tool/Documentation.jl#L1317) ⬜,
  [Documentation.jl:1391](../../../source/kernel/tool/Documentation.jl#L1391) ⬜
- Evidence: `_arg_limit` takes any number from a tool call. With `limit = 0`,
  `shown` is empty, and `_make_footer(_get_section_uri(first(shown)), …)` throws a
  `BoundsError` before it compares the length; `search_api` does the same at line
  1322. With `limit = -1`, `first(ranked, -1)` throws an `ArgumentError`. From the
  REPL, `limit = 2.5` throws an `InexactError` in `Int(limit)`. The docstring of
  `search_guides` says "A query that can not be read answers the reason as text, and
  never throws". The agent loop records a fault and sends the model a stack trace.
- Rule: the contract of `search_guides` and `search_api`.
- Fix: In `_get_hit_count`, answer a message for a limit below one and round a real
  limit; compute the footer URI only when `shown` is not empty.
- Reach: `Documentation.jl`; `SearchAnswerTest.jl`.

### L18-7 The guide index starts a section at each comment line in a code block

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [Documentation.jl:675](../../../source/kernel/tool/Documentation.jl#L675) ⬜
- Evidence: `_index_guide_sections` takes each line that starts with `#` as a
  heading, also inside a code fence. `documentation/` holds 97 such lines, for
  example `# @broken: <one-line reason>` in testing-guide.md and
  ``# Fragment of `CellModule` — …`` in code-quality-rules.md. Each one makes a false
  section: its URI appears in the hits, the true section ends at that line, and
  `_add_guide_footer` lists the comment among the sections. `_split_doc_paragraphs`
  in the same file already keeps the state of a fence.
- Rule: bug
- Fix: Keep the fence state in `_index_guide_sections`, as `_split_doc_paragraphs`
  does.
- Reach: `Documentation.jl`; the meaning vectors of the guide sections are computed
  again once.

### L18-8 The catalogue of modules lists types that the model can not write

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [Documentation.jl:475](../../../source/kernel/tool/Documentation.jl#L475) ⬜
- Evidence: `list_modules(; api)`, which `resource://modules` answers, lists
  `_struct_types(mod)` of each declared module with no filter (line 480). The pair
  `JsonModule => (:JsonArray, …)` of `make_application_api()` then shows every struct
  type of `JsonModule`. A whole module shows the schema variants (`ACFoo`, `RCFoo`,
  `MFoo`, …) that `_index_declared` and `_api_types` hide. A module that two entries
  name shows twice. `_WHOLE_SURFACE_DESCRIPTION` tells the model that this resource
  is a mandatory first read.
- Rule: "what is discoverable is what is callable" (the `ToolSet` docstring,
  `DeclaredApiTest.jl`).
- Fix: Filter the types of `list_modules` as `_api_types` does, and list each module
  once.
- Reach: `Documentation.jl`; `DeclaredApiTest.jl`.

### L18-9 Work that a tool does on the editor task has no time bound

- Category: Correctness · Severity: Medium · Confidence: Confirmed (the wait loop:
  Suspected)
- Where: [CodeExecution.jl:172](../../../source/kernel/tool/CodeExecution.jl#L172) ⬜,
  [MeaningSearch.jl:252](../../../source/kernel/tool/MeaningSearch.jl#L252) ⬜,
  [MeaningSearch.jl:362](../../../source/kernel/tool/MeaningSearch.jl#L362) ⬜
- Evidence:
  - Each tool runs on the editor task, in the drain of a frame (`AgentLoop.jl:77`,
    `Mcp.jl:155`). While it runs, the editor paints nothing and reads no input.
  - `execute_julia_code` has no time limit. A loop in model code stops the window
    until it ends.
  - A description search calls the meaning model over HTTP
    (`_compute_query_vector`). Then `_await_meaning_build` sleeps on the same task
    for up to `_MEANING_WAIT_SECONDS[]`, which is 30 s.
  - Model code that waits in a loop for state that the editor loop advances, for
    example a feed that a frame drains, waits forever: no frame runs until the call
    returns. Suspected: depends on how a host updates its state.
- Rule: bug (a frame of the editor must end).
- Fix: Do not wait for vectors on the editor task; answer "not ready" there. Give
  `execute_julia_code` a stated bound, or run model code on its own task and send
  only its writes through `run_on_editor_task!`.
- Reach: `MeaningSearch.jl`, `CodeExecution.jl`; the agent layer and `Mcp.jl` if the
  code moves off the editor task.

### L18-10 The code tool also catches the exceptions that must stop the program

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [CodeExecution.jl:244](../../../source/kernel/tool/CodeExecution.jl#L244) ⬜,
  [CodeExecution.jl:372](../../../source/kernel/tool/CodeExecution.jl#L372) ⬜,
  [MeaningSearch.jl:365](../../../source/kernel/tool/MeaningSearch.jl#L365) ⬜
- Evidence: `catch e` in `_run_expression` turns each exception into text:
  `InterruptException`, `StackOverflowError`, `OutOfMemoryError`, and
  `QuitEditorException`, which `Operations.jl:74` names a pass-through. The editor
  layer rethrows these (`Inbox.jl:101`), but the tool never lets one reach it. So
  Ctrl+C in a long evaluation becomes an answer, and a quit from the evaluator
  becomes a message. `_notify_evaluation` and `_compute_query_vector` catch in the
  same way. `FaultModule` (layer 1) exports `is_passthrough_exception`.
- Rule: PAR-REPORT-NEVER-THROWS
- Fix: Put `is_passthrough_exception(e) && rethrow()` first in each catch, and add
  `using ..FaultModule` to `ToolModule.jl`. If an interrupt of model code must end
  only the call, the owner must accept that as an exception to the rule.
- Reach: `ToolModule.jl`, `CodeExecution.jl`, `MeaningSearch.jl`.

### L18-11 Code in two repositories reaches private names of the tool layer

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [CodeExecution.jl:54](../../../source/kernel/tool/CodeExecution.jl#L54) ⬜,
  [MeaningSearch.jl:17](../../../source/kernel/tool/MeaningSearch.jl#L17) ⬜,
  [ToolSet.jl:42](../../../source/kernel/tool/ToolSet.jl#L42) ⬜
- Evidence:
  - omnet-julia `source/presentation/page/Notebook.jl:150` calls
    `ToolModule._scratch_module(set)` to bind modules into the scratch module. Its
    comment calls this "the one private reach".
  - `example/kernel/SearchScaleMeasurement.jl:108–130` calls `_api_index`,
    `_guide_index` and `_get_meaning_store`.
  - `source/platform/conversation/Evaluator.jl:396` and `:423` write the fields `observers`
    and `scratch` of another `ToolSet`.
  - Tests in both repositories write `ToolModule._MEANING_FOLDER[]`
    (`MeaningSearchTest.jl`, `McpTest.jl`, `SearchScaleTest.jl`; omnet
    `CampaignAssistantTest.jl`, `MeaningSearchMeasurementTest.jl`,
    `SearchScaleTest.jl`). The value is process-global, so such a test moves the
    vector files of every editor in the process.
  - `declare_api!` sets `set.scratch = nothing`. A declaration after
    `install_notebook!` drops the names that the notebook bound, with no error.
- Rule: PAR-MODULE-BOUNDARY-IS-API
- Fix: Export a call that binds names into the scratch module and keeps them across
  a new declaration, a folder field for the vectors on `MeaningModel` or `ToolSet`,
  and a measurement call. Then the callers use exported names.
- Reach: `CodeExecution.jl`, `ToolSet.jl`, `MeaningSearch.jl`, `Documentation.jl`;
  `Evaluator.jl`, `SearchScaleMeasurement.jl` and three test files here; the notebook
  page and three test files in omnet-julia.
- Related: plan/pending/assistant-api-consolidation.md §8d binds retired names in
  the scratch module and needs the same exported call.

### L18-12 The tool text names verbs and fields of higher layers and packages

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [DefaultTools.jl:31](../../../source/kernel/tool/DefaultTools.jl#L31) ⬜,
  [DefaultTools.jl:48](../../../source/kernel/tool/DefaultTools.jl#L48) ⬜
- Evidence: Layer 18 writes these names into the description that a model reads:
  `replace_referenced_value!(editor, part, new_value)` (ProjecturedPane,
  `PaneProgram.jl:545`), `insert_elements!` and `delete_elements!` with their
  arguments (the editor layer, `DocumentEdits.jl:73` and `:93`), `editor.document`
  and `editor.projection` (the editor layer), and `using Projectured` (the
  umbrella). `_make_editing_description` also picks its sentence by these names. A
  rename or a new argument above does not change this text, and no guard compares
  them: `test_documentation()` checks guide names, not verb names.
- Rule: PAR-NO-CONSUMER-DOCS, PAR-FRAMEWORKS-SINK
- Fix: The owner of the verbs gives the sentence. An `editing_description` on the
  `ToolSet` or in the declaration holds the text that the editor layer and the pane
  package write; the tool layer only prints it.
- Reach: `DefaultTools.jl`, `Tool.jl`; the editor layer and ProjecturedPane give the
  text; `DeclaredApiTest.jl`.

### L18-13 The guide roots are a process-global registry that any caller writes with no lock

- Category: State · Severity: Medium · Confidence: Confirmed (the race: Suspected)
- Where: [Documentation.jl:17](../../../source/kernel/tool/Documentation.jl#L17) ⬜,
  [Documentation.jl:32](../../../source/kernel/tool/Documentation.jl#L32) ⬜,
  [Documentation.jl:889](../../../source/kernel/tool/Documentation.jl#L889) ⬜,
  [MeaningSearch.jl:290](../../../source/kernel/tool/MeaningSearch.jl#L290) ⬜
- Evidence:
  - `register_guide_root!` pushes onto the global `_EXTRA_GUIDE_ROOTS` and sets
    `_GUIDE_INDEX[] = nothing`, with no lock.
  - `OmnetCampaignUi.__init__` calls it. So every editor of a process that loads
    that package offers those guides, and no host can give guides to one editor
    only. The carve-out of PAR-PER-EDITOR-STATE covers read-only data built from
    invariant sources; this is a registry that callers write.
  - `_start_meaning_vectors!` builds the index on another thread, under
    `_INDEX_LOCK`. A registration during that build resets the index, and then the
    build writes the old index back; the new root stays out until the next
    registration. Suspected: needs a run with that order of events.
- Rule: PAR-PER-EDITOR-STATE
- Fix: Keep the guide roots on the `ToolSet` (`register_guide_root!(set, …)`), key
  the guide index by its roots, and take `_INDEX_LOCK` for each write.
- Reach: `Documentation.jl`, `DefaultTools.jl`, `MeaningSearch.jl`; omnet-julia
  `OmnetCampaignUi.jl`.

### L18-14 Four assertions of the whole surface pass when the name is not defined

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [DeclaredApiTest.jl:106](../../../test/kernel/tool/DeclaredApiTest.jl#L106),
  [:446](../../../test/kernel/tool/DeclaredApiTest.jl#L446),
  [:561](../../../test/kernel/tool/DeclaredApiTest.jl#L561),
  [:566](../../../test/kernel/tool/DeclaredApiTest.jl#L566)
- Evidence: `@test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))`
  also passes when the answer is ``UndefVarError: `Cell` not defined``, because the
  error text holds the word. So "an empty declaration is the whole surface" and
  "declaring after the first evaluation still takes effect" can not fail on the
  thing that they name.
- Rule: testing-guide.md (a test asserts the outcome).
- Fix: Assert also that the answer holds no `UndefVarError`.
- Reach: `DeclaredApiTest.jl`.

### L18-15 No test covers the pipe limit, an overlap, the pass-through, a zero limit or the guide registry

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [test/kernel/tool/](../../../test/kernel/tool/)
- Evidence: No test prints more than 64 KiB (L18-2), overlaps two calls (L18-4),
  throws a pass-through exception in code (L18-10), prints before an error (L18-5),
  gives a limit of 0 (L18-6), reads a guide with a `#` line in a fence (L18-7), lists
  modules under a pair declaration (L18-8), or searches the whole surface for a name
  outside the kernel (L18-1). `register_guide_root!` has no test in this repository.
  An observer that throws, `call_tool` with an unknown name and the replacement in
  `register_tool!` have no kernel test, and `observe_evaluations!` is tested in the
  umbrella only (`EvaluatorToplevelTest.jl:159`).
- Rule: PAR-NEW-CODE-SHIPS-TESTS
- Fix: Add these cases to `test/kernel/tool/`, and move the observer case down.
- Reach: `test/kernel/tool/`.

### L18-16 The declared description loses a word when each entry is a whole module

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [DefaultTools.jl:103](../../../source/kernel/tool/DefaultTools.jl#L103) ⬜
- Evidence: With `chosen == 0`, `_declared_sentence` answers "The functions of A, B"
  with no " are ", and line 115 appends "in scope". The model reads "The functions
  of ToyApiin scope, and they are the whole of what you may call."
  `DeclaredApiTest.jl:397` checks the start of the sentence only.
- Rule: bug
- Fix: End the whole-module branch with " are " in both cases.
- Reach: `DefaultTools.jl`; `DeclaredApiTest.jl`.

### L18-17 A short text with a line break reaches the model as one escaped line

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [CodeExecution.jl:288](../../../source/kernel/tool/CodeExecution.jl#L288) ⬜
- Evidence: `repr` of a `String` escapes each `\n`, so the check
  `!occursin('\n', text)` is true for every short string. `"a\nb"` then answers
  `"a\\nb"` in quotes, and a string of more than 200 characters answers its lines
  raw. A model that reads a short program as one escaped line wastes rounds.
- Rule: bug (the comment above says that prose a verb answers is shown whole).
- Fix: Show a `String` that holds a line break as prose at any length, or state that
  a short one keeps the REPL form.
- Reach: `CodeExecution.jl`; `CodeExecutionTest.jl`.
- Known: plan/pending/the-assistant-reaches-a-referenced-document.md, Step 6, records
  it and prints with `println` in the guide.

### L18-18 The code tool throws a `KeyError` for a call with no `code` argument

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [DefaultTools.jl:179](../../../source/kernel/tool/DefaultTools.jl#L179) ⬜
- Evidence: The handler reads `args["code"]`. `execute_julia_code` answers
  `nothing` and empty source with "No code was given", but a call that leaves out
  the key throws before it runs.
- Rule: bug
- Fix: `get(args, "code", nothing)`.
- Reach: `DefaultTools.jl`.

### L18-19 `read_function_documentation` ignores the `type_name` that the tool offers

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Documentation.jl:591](../../../source/kernel/tool/Documentation.jl#L591) ⬜,
  [DefaultTools.jl:242](../../../source/kernel/tool/DefaultTools.jl#L242) ⬜,
  [CodeExecution.jl:107](../../../source/kernel/tool/CodeExecution.jl#L107) ⬜
- Evidence: The body never reads `type_name`. The tool offers it as "Optional type,
  when the function is documented per type", and the scratch module passes it on.
- Rule: bug
- Fix: Remove the parameter from the tool, the scratch module and the function, or
  use it to pick the docstring of one method.
- Reach: `Documentation.jl`, `DefaultTools.jl`, `CodeExecution.jl`.

### L18-20 A short value shows without the `show` method that the same call defined

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [CodeExecution.jl:288](../../../source/kernel/tool/CodeExecution.jl#L288) ⬜,
  [CodeExecution.jl:303](../../../source/kernel/tool/CodeExecution.jl#L303) ⬜
- Evidence: `repr(value; …)` runs in the world of the caller, where a method that
  `Core.eval` added in this call is not visible. `_describe_value_for_model` uses
  `invokelatest` for a function and for the limited display, but not for this first
  measure and not in `_summarize_value`. A model that defines `Base.show` for its
  type and returns a short value reads the default form.
- Rule: bug
- Fix: `Base.invokelatest(repr, value; context = :limit => true)`, and the same for
  `summary`.
- Reach: `CodeExecution.jl`.

### L18-21 `documentation/package/README.md` is in no guide root

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Documentation.jl:77](../../../source/kernel/tool/Documentation.jl#L77) ⬜,
  [Documentation.jl:100](../../../source/kernel/tool/Documentation.jl#L100) ⬜
- Evidence: The bare walk skips each folder under `documentation/package`, and the
  per-slice roots are folders only. `documentation/README.md` lists the file, and
  no `resource://guide/…` name reads it.
- Rule: bug
- Fix: Index the files that sit directly in `documentation/package/` under the
  prefix `package/`.
- Reach: `Documentation.jl`.
- Planned: plan/pending/documentation-rewrite.md (the table of faults the rewrite
  depends on).

### L18-22 Three exported names have no user, and seven have no user outside the layer

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ToolModule.jl:37](../../../source/kernel/tool/ToolModule.jl#L37) ⬜,
  [Tool.jl:145](../../../source/kernel/tool/Tool.jl#L145) ⬜,
  [ToolSet.jl:116](../../../source/kernel/tool/ToolSet.jl#L116) ⬜,
  [ToolSet.jl:155](../../../source/kernel/tool/ToolSet.jl#L155) ⬜
- Evidence: No file of the three repositories calls `get_api_modules`,
  `register_tools!` or `register_resources!`. Only the layer calls
  `api_entry_bindings`, `api_source_name`, `register_resource!`, `find_resource`,
  `read_value_documentation`, and only the layer names `SearchTerm` and
  `KeywordQuery`.
- Rule: code-quality-rules.md §1 (the export block is the surface); architecture-rules.md
  "No orphans shape the structure".
- Fix: Delete the three. Stop the export of the seven, or name the caller that needs
  each.
- Reach: `ToolModule.jl`, `Tool.jl`, `ToolSet.jl`.

### L18-23 The layer breaks the size, argument and export rules of code-quality-rules.md

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ToolModule.jl:37](../../../source/kernel/tool/ToolModule.jl#L37) ⬜,
  [Documentation.jl:531](../../../source/kernel/tool/Documentation.jl#L531) ⬜,
  [Documentation.jl:591](../../../source/kernel/tool/Documentation.jl#L591) ⬜,
  [DefaultTools.jl:171](../../../source/kernel/tool/DefaultTools.jl#L171) ⬜
- Evidence:
  - One export statement serves seven fragments, and names of `Documentation.jl`
    stand before names of `ToolSet.jl` (§1). `test/suite/exports.jl` lists
    `ToolModule.jl` as not migrated.
  - `list_functions(module_name, type_name = nothing; api)` and
    `read_function_documentation(…, type_name = nothing; api)` take an optional
    positional argument beside a keyword (§4). The guard checks that clause only for
    a marked definition.
  - `Documentation.jl` has 1,391 lines against a budget of 500 (§5).
    `register_default_tools!` has 157 lines, `search_api` 71 and `_scratch_module`
    68, against 60. 86 lines are longer than 90 characters.
  - Three functions compute "the names that a declaration gives this module":
    `_is_declared` (Documentation.jl:184), `_find_declared_names`
    (Documentation.jl:491), `_api_types` (DefaultTools.jl:84).
- Rule: code-quality-rules.md §1, §4, §5.
- Fix: Split `Documentation.jl` into the guide index, the readers and the search;
  write one export statement for each fragment; make `type_name` a keyword; keep
  one function for the declared names.
- Reach: the layer only.
- Planned: plan/pending/export-block-rule.md (the export block of `ToolModule.jl`).

### L18-24 Each turn repeats work whose inputs did not change

- Category: Types/performance · Severity: Low · Confidence: Confirmed
- Where: [DefaultTools.jl:293](../../../source/kernel/tool/DefaultTools.jl#L293) ⬜,
  [MeaningSearch.jl:286](../../../source/kernel/tool/MeaningSearch.jl#L286) ⬜,
  [Documentation.jl:118](../../../source/kernel/tool/Documentation.jl#L118) ⬜,
  [CodeExecution.jl:174](../../../source/kernel/tool/CodeExecution.jl#L174) ⬜
- Evidence: `run_turn!` calls `register_default_tools!` at the start of each turn
  (`AgentLoop.jl:37`), which walks the guide tree on disk and reflects over each
  module again. `bind_meaning_model!` at each turn (`AssistantTurn.jl:679`) calls
  `set_meaning_model!`, which spawns a task that gathers about 1.04 million
  characters of text again. `list_guides` reads each guide file at each read of
  `resource://guides`. `execute_julia_code` logs the whole code and the whole answer
  at `@info` (lines 174 and 183), so a large answer also goes into the message log.
- Rule: PAR-PROFILE-WITH-COUNTERS (cost that a frame does not need).
- Fix: Register again only when the declaration changes; start the vectors only
  when the model or the declaration changes; keep the guide list with the index; log
  the length of the answer, not its text.
- Reach: `DefaultTools.jl`, `ToolSet.jl`, `MeaningSearch.jl`, `Documentation.jl`,
  `CodeExecution.jl`.

### L18-25 Two exported functions do not start with a verb, and the code executors have no `!`

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [Tool.jl:106](../../../source/kernel/tool/Tool.jl#L106) ⬜,
  [Tool.jl:129](../../../source/kernel/tool/Tool.jl#L129) ⬜,
  [CodeExecution.jl:172](../../../source/kernel/tool/CodeExecution.jl#L172) ⬜,
  [CodeExecution.jl:195](../../../source/kernel/tool/CodeExecution.jl#L195) ⬜
- Evidence: `api_entry_bindings` and `api_source_name` are nouns; the names are
  `get_api_entry_bindings` and `get_api_source_name`. `execute_julia_code` and
  `execute_julia_expression` write `set.last_value` and `set.scratch` and run code
  with any side effect, and have no `!`. The MCP tool name `"execute_julia_code"` is
  a wire string and can stay.
- Rule: naming-rules.md, "Every function name starts with a verb" and "Mutating
  functions end with `!`".
- Fix: Rename with `workspace/bin/julia-rename.jl`. The two executors reach 10
  source files here and about 16 files in omnet-julia.
- Reach: the layer; `AssistantTurn.jl`, `Evaluator.jl`, `Mcp.jl` and others;
  omnet-julia.

### L18-26 The docstrings and design documents state false facts about global state and the empty API

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [ToolModule.jl:29](../../../source/kernel/tool/ToolModule.jl#L29) ⬜,
  [Tool.jl:189](../../../source/kernel/tool/Tool.jl#L189) ⬜,
  [Documentation.jl:876](../../../source/kernel/tool/Documentation.jl#L876) ⬜,
  [Documentation.jl:1244](../../../source/kernel/tool/Documentation.jl#L1244) ⬜,
  [agent.md:59](../../../documentation/package/kernel/agent.md#L59),
  [agent.md:362](../../../documentation/package/kernel/agent.md#L362),
  [mcp-guide.md:50](../../../documentation/guide/mcp-guide.md#L50)
- Evidence:
  - `ToolModule.jl:29` says "Nothing here is process-global". The module holds
    `_EXTRA_GUIDE_ROOTS`, `_GUIDE_INDEX`, `_API_INDEX`, `_DECLARED_INDEX`,
    `_MEANING_STORES`, `_MEANING_FOLDER` and `_MEANING_WAIT_SECONDS`, and each code
    call swaps the process streams (L18-4). agent.md:59 names the indexes and the
    stores only.
  - `Tool.jl:189`, `Documentation.jl:1244` ("Empty, it sees the whole project"),
    agent.md:362 and mcp-guide.md:50 ("of the loaded packages") say that the empty
    API is every loaded package. The documentation half reads the kernel only
    (L18-1).
  - `Documentation.jl:876` says "(alongside the wall clock)". Since 2026-09-25 no
    clock is shared by the whole process (PAR-PER-EDITOR-STATE).
- Rule: PAR-HONEST-DOCS, PAR-MODULE-DOCSTRING.
- Fix: Name each process-global value and why it is there; correct the empty-API
  sentences after L18-1; delete the clock remark.
- Reach: `ToolModule.jl`, `Tool.jl`, `Documentation.jl`, agent.md, mcp-guide.md.

### L18-27 PAR-AI-SAME-GUARANTEES says that `execute_julia_code` routes through `evaluate_operation`, and it does not

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [architecture-invariants.md, PAR-AI-SAME-GUARANTEES](../../../documentation/rule/architecture-invariants.md#par-ai-same-guarantees),
  [DefaultTools.jl:24](../../../source/kernel/tool/DefaultTools.jl#L24) ⬜
- Evidence: The rule says "Code that exposes editing to an AI (the agent tools,
  `execute_julia_code`) routes through `evaluate_operation`/`search_*`, not around
  them". The tool evaluates any code with `editor` bound, and its description says
  "A direct write works". The owner decided on 2026-09-26 (D22 in
  plan/pending/the-assistant-reaches-a-referenced-document.md) that a direct write
  stays possible and is discouraged. The rule does not state that exception.
- Rule: PAR-HONEST-DOCS
- Fix: Add the accepted exception to the text of PAR-AI-SAME-GUARANTEES.
- Reach: architecture-invariants.md.

### L18-28 Comments keep history, compliance citations, consumer names and private names

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [DefaultTools.jl:285](../../../source/kernel/tool/DefaultTools.jl#L285) ⬜,
  [DefaultTools.jl:228](../../../source/kernel/tool/DefaultTools.jl#L228) ⬜,
  [DefaultTools.jl:168](../../../source/kernel/tool/DefaultTools.jl#L168) ⬜,
  [Documentation.jl:881](../../../source/kernel/tool/Documentation.jl#L881) ⬜,
  [Tool.jl:229](../../../source/kernel/tool/Tool.jl#L229) ⬜,
  [Tool.jl:58](../../../source/kernel/tool/Tool.jl#L58) ⬜,
  [Documentation.jl:1011](../../../source/kernel/tool/Documentation.jl#L1011) ⬜,
  [Documentation.jl:1330](../../../source/kernel/tool/Documentation.jl#L1330) ⬜
- Evidence:
  - History: "It was once the other way: … `search_guides` went on printing"
    (DefaultTools.jl:285–288); "Named here, the asymmetry is gone"
    (DefaultTools.jl:228–229). In the tests: "the tool used to answer"
    (DeclaredApiTest.jl:110), "a miss used to cost" (:160), "The guides were once
    withheld … That was wrong" (:513–518), and the testset name "…, and no longer a
    regex flag" (SearchQueryTest.jl:157).
  - Compliance citations: DefaultTools.jl:168 and Documentation.jl:881 cite
    PAR-PER-EDITOR-STATE for code that obeys it. Documentation.jl:876 and
    MeaningSearch.jl:12 flag the carve-out, which the rule allows.
  - Consumer names: "The simulator's editor uses it …" (Tool.jl:229–232); the
    `ApiEntry` docstring explains itself with `PaneSplit`, `DataFrames` and "a pane"
    (Tool.jl:58–70); the `declare_api!` example names `PaneModule`
    (ToolSet.jl:15–17).
  - Private names: Documentation.jl:1011–1012, 1036–1037 and 1330–1331 name
    `run_simulations_in_conversation`, `stop_simulations` and `CampaignVerbsModule`,
    verbs and a module of a private downstream program.
  - Personification: "the handler signature every other tool is happy with"
    (DefaultTools.jl:169); "none of them knows about the others" (ToolModule.jl:25).
- Rule: code-quality-rules.md §2, PAR-CITE-EXCEPTIONS-ONLY, PAR-NO-CONSUMER-DOCS,
  writing-rules.md ("No private name", "No personification").
- Fix: Delete the history; drop the two citations; state each contract in the terms
  of this layer; write "a downstream program" for the private names.
- Reach: `DefaultTools.jl`, `Tool.jl`, `ToolSet.jl`, `ToolModule.jl`,
  `Documentation.jl`; `DeclaredApiTest.jl`, `SearchQueryTest.jl`.

### L18-29 Docstring signatures and several comments do not match the code

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [Documentation.jl:470](../../../source/kernel/tool/Documentation.jl#L470) ⬜,
  [Documentation.jl:418](../../../source/kernel/tool/Documentation.jl#L418) ⬜,
  [Documentation.jl:724](../../../source/kernel/tool/Documentation.jl#L724) ⬜,
  [Documentation.jl:783](../../../source/kernel/tool/Documentation.jl#L783) ⬜,
  [Documentation.jl:997](../../../source/kernel/tool/Documentation.jl#L997) ⬜,
  [ToolModule.jl:7](../../../source/kernel/tool/ToolModule.jl#L7) ⬜
- Evidence:
  - `list_modules() -> String` (line 470), `read_module_documentation(module_name)`
    (549), `read_type_documentation(module_name, type_name)` (562) and
    `read_function_documentation(…)` (587) do not show the `api` keyword.
    `list_guides` says "tips and tricks" (116), an idiom.
  - The comment at lines 724–726 describes `_index_declared` and stands above
    `describe_api`. The comment at 783–794 describes `_is_schema_variant`, and
    `_is_private_name` with its comment stands between them. The comments about
    the rank at 997–1014 and 1036–1048 stand above `_split_identifier_words` and
    above constants, not above `_rank_api_entries`.
  - `_is_interface_name` (418–430) calls `ICFoo` "the interface type". The prefix
    `I` means immutable (naming-rules.md), and the check matches `IFoo`, not
    `ICFoo`.
  - The `ToolModule` docstring (7–9) and agent.md:30 do not name `ApiEntry` or
    `observe_evaluations!`, which `Tool.jl` holds.
- Rule: PAR-MODULE-DOCSTRING, PAR-TIGHT-COMMENTS.
- Fix: Correct the signatures; move each comment to its function; name the immutable
  variant; list what `Tool.jl` holds.
- Reach: `Documentation.jl`, `ToolModule.jl`, agent.md.

## Accepted before, not raised again

No prior audit of this layer exists in `plan/done/`. These points are decisions or
carve-outs that the rules or the owner state:

- The guide index, the API index, the declared indexes and the stores of meaning
  vectors are process-global: the carve-out of PAR-PER-EDITOR-STATE names them. Only
  the guide-root registry, which that carve-out does not cover, is raised (L18-13).
- The declared API is a focus mechanism and not a security boundary: `Base`, `Core`
  and `Main` stay reachable (agent.md, the `ToolSet` docstring).
- A direct write from model code stays possible and is discouraged (D22, the owner,
  2026-09-26). Only the rule text is raised (L18-27).
- `execute_julia_code` binds no `document` (D20, the owner, 2026-09-26).
- The whole surface is gathered by the package prefix `Projectured`, a reflection
  seam that agent.md states.
- The rank decisions measured and rejected in plan/done/three-kinds-of-search.md and
  the assistant-search plans (fusion for entries, a second meaning model, chunked
  entry text) are not raised again.
- `test_mcp_tools()` fails 2 checks on main ("an assistant turn binds its meaning
  model": `wake_editor!` gets a `NamedTuple`). The fault is in the assistant slice,
  not in this layer; it is the one umbrella check of the meaning model bound at each
  turn.

## Checked and clean

- PAR-NO-TEST-DOUBLES-IN-MAIN: the layer defines no fake, stub or scripted double;
  the tests make their meaning models in the test package.
- PAR-QUALIFIED-EXTENSION: the only extensions are `Base.:(==)` and `Base.hash` for
  `ApiEntry`, both qualified.
- PAR-MODULE-BOUNDARY-IS-API inside the kernel: the layer imports nothing, and no
  kernel module reaches a private name of it (the reaches from outside are L18-11).
- PAR-INTERFACE-DECLARES-ONLY: the layer has no interface file and no open generic,
  so the rule has nothing to hold.
- PAR-MODULE-DOCSTRING (form): `ToolModule.jl` opens with a docstring, and each of
  the seven fragments opens with a "# Fragment of `ToolModule` —" header.
- The known trap of a tuple of a global vector: no global vector is read as a tuple
  splat; `_guide_roots()` appends `_EXTRA_GUIDE_ROOTS` to a new vector at each read.
- PAR-PER-EDITOR-STATE for the tool list, the resource list, the scratch module, the
  last value, the observers, the API and the meaning model: each is a field of the
  `ToolSet`, and each default handler closes over its own set.
- `read_resource` answers a message for an unknown URI and does not throw.
- The meaning store: each field is read and written under the store lock; a file
  with a wrong header is replaced, a record that a crash cut short is cut off, and a
  vector of a new length empties the store.
- 1-based indexes: `_compute_edit_distance`, `_split_long_paragraph` and the chunk
  arithmetic of `_get_meaning_texts` are correct.
- The query parser: an empty piece, a lone `+` or `-`, an unclosed quote and a phrase
  shorter than two characters each give no term and no error.
- Type names (`Tool`, `Resource`, `ToolSet`, `ApiEntry`, `MeaningModel`,
  `SearchTerm`, `KeywordQuery`) are nouns, and the other verbs of the surface follow
  naming-rules.md.
- Could not check here, by the brief: no Julia run. L18-2, L18-3, L18-4, the partial
  run of L18-5 and the race of L18-13 rest on the code as read.
