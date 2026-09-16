# The assistant finds the API for what it means

> **Kind:** plan · **Status:** done 2026-09-16 · **Stands on:**
> [three-kinds-of-search.md](three-kinds-of-search.md),
> [declared-api-is-a-list-of-names.md](declared-api-is-a-list-of-names.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [code-quality-rules.md](../../documentation/rule/code-quality-rules.md)

The assistant has something in mind, and it can say it in English. It must find
out how to do it with the Julia API that the window declares. This plan reviews
the tools and the resources against that one goal, and changes them where they
fall short.

**The measure** is how easily a local model, `qwen3.8:27b` through Ollama, finds
the solution to each of a table of problems: how many problems it solves, and
how many rounds, tool calls and tokens each solution costs.

## 1. What the assistant has now

One `ToolSet` per editor. The chat pane's agent loop calls it in the process,
and with `--mcp` the server at `127.0.0.1:9876/mcp` publishes the same set and
gives a client the window's prompt.

| kind | what | count in the omnet IDE |
| --- | --- | --- |
| tools | `execute_julia_code`, `search_api`, `search_documentation`, `read_function_documentation`, `list_resources`, `read_resource` | 6 |
| resources | `resource://guides`, `resource://guide/<name>`, `resource://modules`, `resource://module/<m>`, `resource://type/<m>/<t>` | 2 catalogues, 69 guides, 9 modules, about 15 types |
| declared names | what `execute_julia_code` can call, and what the searches see | 88 entries in 9 modules |

The path from an intent to a call has five steps, and each has a tool: say the
intent (`search_api` in description mode, or `search_documentation`), read the
hits, read one in full (`read_function_documentation` or `read_resource`), write
the call (`execute_julia_code`), and read the result.

## 2. The analysis

### 2a. Where the path breaks

1. **The ranking depends on the docstring, and a docstring lacks the words a
   person uses.** The meaning vector reads the whole docstring; the keyword
   scorer reads its signature and first sentence. Measured 2026-09-16 on the 88
   names: "draw how a value changes over time" ranks `make_result_plot`
   twelfth, because its docstring says "chart" and never "draw", "value" or
   "time"; "write down what the runs taught us" ranks `add_finding!`
   twenty-fifth. Five of eight verb sentences ranked their verb first; the
   guides did better, seven of eight, because a heading says in plain words
   what its section is about.
2. **A hit shows its signature and nothing else**, and nothing controls the
   detail. A model reads eight signatures and still does not know what a verb
   is for. The review of 2026-09-16 found this, and §3a fixes it.
3. **A wrong guess costs a whole round.** A model that guesses `plot_results`
   gets `UndefVarError: plot_results not defined` and nothing else, although
   `make_result_plot` shares two of its words. A guess is the most natural
   search a model makes, and the failure is where the answer is wanted.
4. **The value of the last expression is printed whole, unasked.** A verb
   called for its side effect prints its return value; a `DataFrame` prints
   hundreds of rows; the model's window is 32,768 tokens, and one such value
   can take a third of it. Julia gives the value without being asked, and the
   tool passes it on without asking either.
5. **Compositions have no unit of their own.** A goal often needs two or three
   verbs in order — read the results, make a table, open a pane. The guides
   hold such compositions as worked sessions, but a hit points at a whole
   guide, and a model reads 4,000 characters for one recipe.
6. **The model can arrange panes, and it can not build a widget.** The 99
   widget names and 25 layout names of `WidgetModule` and `LayoutModule` are
   outside the declaration. A person asks for "a card with the table and the
   plot side by side", and no declared name answers.
7. **Every answer ends where its data ends.** A model that read a list of hits
   must remember the tool to read one in full; a model that read a long guide
   gets no table of contents. The tool descriptions carry the instructions
   instead, and they are sent with every request.

### 2b. What is redundant

1. **Three catalogues overlap.** `list_resources` lists every URI, about 95
   lines in the IDE; `resource://guides` describes every guide in a paragraph;
   `resource://modules` describes every declared module. The first is the
   longest and says the least.
2. **The word "documentation" means two things.** `search_documentation`
   searches the guides, and `read_function_documentation` reads a docstring;
   `list_guides`, `read_guide` and `resource://guide/<name>` say "guide". One
   word for two corpora is a wrong turn a model takes at no fault of its own.
3. **Two readers for one job.** A module or a type has a URI and is read with
   `read_resource`; a function has none and is read with
   `read_function_documentation`. The tool exists because a model, told in
   prose to "call read_function_documentation", looked for a tool of that
   name (measured 2026-09-13). The asymmetry stays: a hit's locator is a URI
   for two kinds and a call for the third.
4. **Eleven tools that no window registers.** `SimulationToolsModule` in omnet
   defines `count_matching_runs`, `list_configurations`, `start_campaign`,
   `stop_campaign`, `rerun`, `describe_campaign`, `describe_run`,
   `open_in_qtenv`, `list_panes`, `focus_pane` and `close_pane`.
   `run_campaign_window` gives `build_campaign_session` no tool set, so they
   are dead surface, and their docstrings say "the MCP server serves them".

The `kind` filter of `search_api` is seldom useful and costs little; it stays.

### 2c. What to extend, what to reduce

| change | extends or reduces | why |
| --- | --- | --- |
| `search_documentation` becomes `search_guides`, tool and function | neither | one word, "guide", for that corpus everywhere |
| `detail` levels on both searches | extends | the model chooses between many names and few whole docstrings |
| a footer of next actions on a long answer | extends | the instructions move from every request into the answers that need them |
| guide sections as resources | extends | a hit reads one section, not a whole guide |
| `execute_julia_code`: the last value described, printed output whole, "did you mean" | extends | the model decides what it reads; the round after a wrong guess is not wasted |
| a docstring standard with use cases and an example | extends | the ranking reads the docstring; a use case is what a person says |
| widget and layout vocabulary | extends | the model builds and controls the interface |
| `list_resources` by kind | reduces | 95 lines become 6 |
| `SimulationToolsModule` | reduces | dead surface, and its documentation is false |
| a benchmark of problems | extends | nothing above is adopted without it |

## 3. The design

### 3a. The answer of a search — the review of 2026-09-16

Decided by the user: a hit shows two lines, its signature in code with its kind
and module, then the first sentence of its description. The name is not
repeated. One line at the end says how to read a hit in full, once. The note
of a description search says what ranked the hits — "No meaning model was
given, so the words of the description ranked these hits. When you know a word
of the name, mode \"keywords\" with that word does better." — and never "this
editor" for a Julia call. `search_api(set, query; …)` reads the declaration
and the meaning model from the set, so a REPL call answers what the tool
answers. A module that two declaration entries name is indexed once. The stale
`resource://classes` and `resource://functions` in `setup-guide.md` and
`PAR-NEVER-GUESS-NAMES` name the catalogues that exist.

`_ApiEntry.doc` becomes `signature` (the first signature of the docstring, cut
at 200 characters) and `summary` (the first sentence of the first prose
paragraph, without `**`, cut at 160 characters). A signature paragraph starts
with the name and `(` or `{`, or is the name alone, with any fence removed. A
sentence ends at `.`, `!` or `?` after two word characters and before a capital,
a backtick or a bracket, so "e.g." ends none. `list_modules`, `list_types` and
`list_functions` show the same summary, whole, instead of the signature.

### 3b. Two searches, one shape

The two searches stay two tools. They rank differently on purpose — a verb by
its name first, and by meaning alone in description mode; a guide section by
its heading first, and by words and meaning merged — and they answer different
intents: `search_api` when the model wants to write code, `search_guides` when
it wants to understand how things fit together. A model that is unsure calls
both in one round. One tool over both corpora was considered and refused: it
would only call both and print two lists, so every answer would be longer, for
the rare call that does not know its corpus.

`search_documentation` becomes `search_guides`, the tool and the Julia
function, with `workspace/bin/julia-rename.jl` and the two sweeps its blind
spots need. The word "documentation" then means a docstring, as in
`read_function_documentation`, and "guide" means a guide, as in `list_guides`,
`read_guide` and `resource://guide/<name>`.

```
search_api(query; mode = "keywords", detail = "summary", kind, limit)
search_guides(query; mode = "keywords", detail = "summary", limit)
```

- `mode` is as today: `"keywords"`, `"regex"`, `"description"`.
- `detail` is `"names"`, `"summary"` or `"full"`, the same on both:

  | detail | a hit of `search_api` | a hit of `search_guides` | default `limit` |
  | --- | --- | --- | --- |
  | `names` | one line: the signature | one line: the guide and heading | 25 |
  | `summary` | the two lines of §3a | the heading and an excerpt | 8 |
  | `full` | the whole docstring | the whole section | 3 |

  A model that wants the lie of the land asks for names; one that has narrowed
  the search asks for full. The "one clear hit answers in full" rule stays at
  every level.
- `kind` filters `search_api` as today.
- Each description says in one sentence when to use the tool: "to find the
  name to call" and "to learn how the parts fit together". A miss in one
  search gets a footer that names the other (§3c).

**Decision 1, taken 2026-09-16:** two tools, and the rename.

### 3c. A footer of next actions

An answer over 600 characters ends with one or two lines that say the actions
that apply, and a shorter answer ends with none:

- a list of names: "Read one in full: `read_resource(\"<uri of the first
  hit>\")`. Narrow the search with +word or -word, or ask with mode
  \"description\"."
- a list of guides: the same, with the first section's URI.
- a miss: the other search, in one line — "No name says this; a guide may:
  `search_guides` with the same words." — and for `search_api` also the names
  that exist, as today.
- a guide read whole: "Sections: a · b · c. Read one with
  `resource://guide/<name>#<heading>`."
- a `describe_api` miss: as today, the names that exist.

The rules are in one place, `_make_footer(answer, hits)`, so a footer never
says a tool that is not registered — which is how the 2026-09-13 failure
happened.

### 3d. Guide sections as resources

`read_resource` resolves `resource://guide/<name>#<heading>` to one section,
by the heading text after the `#`, matched without case and with `-` for a
space. The sections are not listed in `list_resources`, as functions are not;
a search hit and a whole-guide footer name them. A search hit for a guide
carries the section URI, so a model reads 400 characters instead of 4,000.

Functions get a URI the same way: `resource://function/<module>/<name>` is
resolved by pattern, never listed. Every hit then carries one URI form, and
the footer says one reader. `read_function_documentation` stays a tool, for a
model that knows a module and a name from prose.

**Decision 2.** Keep `read_function_documentation` beside the function URI, or
retire it after the benchmark shows that the URI is found. Recommended: keep
it for now, measure, then decide.

### 3e. `execute_julia_code`

The tool answers two kinds of output today, and they deserve opposite rules.

- **What the code prints comes back whole, and is never cut.** It is what the
  model asked for. A cut would hide the rows the model wanted, and the model
  could not know what was cut. The user refused a cut on 2026-09-16 for this
  reason, and the plan first had one.
- **The value of the last expression is described in one line, never
  dumped.** Julia gives it without being asked, and it is what floods the
  window: a `DataFrame` of 4,200 rows, the `Text` a side-effect verb answers.
  The line is Julia's own `summary` — "4200×6 DataFrame", "10-element
  Vector{Float64}" — and a short value, up to about 200 characters, is shown as
  it is, because its description would be longer than the value. Nothing is
  hidden: the line says what exists, and `first(frame, 10)` or `names(frame)`
  in the next call shows the part the model wants.
- **`nothing` answers "Done."** — never an empty string, which a model read
  as a broken tool (measured 2026-09-15). A `Document` stays embedded live in
  the conversation, as today.
- **The description says it in one sentence:** "The tool answers what your
  code prints. The value of the last expression is described in one line.
  Print what you want to read: `println(x)`, `show(x)`, or `@show x`."
  `return x` was considered and refused: `return` is not allowed at the top
  level of a module, so it would be a convention of ours to learn, where
  printing is Julia's own.
- **A wrong guess answers the nearest names.** When the code fails with an
  `UndefVarError` in the scratch module, the message gains one line: "Did you
  mean: `make_result_plot`, `make_result_table`?" — the declared names ranked
  by shared words of the name and by edit distance, at most three. This is
  the search that starts from a guessed name, done where the guess fails, so
  it costs no round.
- The keyword help gains one sentence: "A guessed name is a good query: its
  words match the parts of the real name."

### 3f. A docstring standard for a declared name

A name that a window declares to a model documents itself in this shape, and
the searches read every part of it:

```
    make_result_plot(frames::DataFrame...; title) -> SimulationPlotDocument

A chart of every `frame` given, as a document.

Use it to draw a value over time, to compare the runs of a sweep, or to see
the shape of a histogram. The frame decides the chart: …

# Example

    vectors = get_simulation_vector_results(get_project_result_directory(editor))
    open_pane!(editor, make_result_plot(vectors; title = "Delay"))

See also `make_result_table`, which shows the same frame as rows.
```

- The first sentence says what it is; a hit shows it.
- The **Use it to** paragraph says the goals it serves, in the words a person
  says: "draw", "over time", "compare". The meaning vector and the keyword
  prose score read it.
- The **Example** is a call that runs in this window; a model copies a shape
  more than it reads a signature.
- **See also** names the neighbours a model confuses it with.

The standard goes in `code-quality-rules.md` as a rule for a declared name,
with the grep that finds a declared docstring without a "Use it to" paragraph.
Then every declared name of the omnet IDE gets it: 88 today, in
`CampaignVerbs`, `PaneProgram`, `ResultVerbs`, `StudyVerbs`, the result readers
and the selections in omnet, and the pane verbs in projectured. The
`DataFrames` names keep their own docstrings.

### 3g. The interface vocabulary

The IDE declares the names a model needs to build and control the interface.
The set is chosen by a survey before it is declared, and each name gets the
docstring of §3f:

- **layouts:** `GridLayout`, `VerticalLayout`, `HorizontalLayout`,
  `FlowLayout`, and their policies `Fixed`, `Content`, `Weight`, `Inset`;
- **widgets:** `WidgetCard`, `WidgetTable`, `WidgetText`, `WidgetButton`,
  `WidgetCheckbox`, `WidgetScrollPane`, `WidgetSplitPane`, `WidgetImage`, and
  what the survey adds;
- **verbs:** the pane verbs that exist, and a verb to replace what a pane
  shows and one to close a pane, if the survey finds that a case needs them.

`declare_api!` refuses a name that two modules give, so the survey lists the
collisions first — `select` is `DataFrames`' and may be a widget's too. The
golden table of the search gains sentences for the interface: "put the table
and the plot side by side", "a card with a title around the plot", "a button
that runs the sweep again".

### 3h. Reduce

- `list_resources` answers six lines: each catalogue with its count and its
  URI pattern, and how a section and a function are addressed.
- `SimulationToolsModule` is deleted, with its test. A headless client has the
  verbs through `execute_julia_code`, which is the design the window took.

**Decision 3.** Delete `SimulationToolsModule`, or keep it for a client that
wants tools and no Julia. Recommended: delete.

### 3i. The benchmark

`test_assistant_session()` in omnet already drives `qwen3.8:27b` with a seed
against a stub project through eight cases, asserts the outcome of each, and
counts the tool calls. It becomes the benchmark:

- **A table of problems**, each a sentence a person says and a check of the
  window's state. The eight cases, the study's seven turns, and the interface
  cases of §3g. About twenty.
- **What is recorded per problem:** solved or not, rounds, tool calls, which
  tools, tokens in and out, wall time, and the first verb the model reached
  for. `run_turn!` gives the events; the harness counts them.
- **A report** printed as a table and kept in this plan, by stage: the
  baseline before any change, then after §3a–3e, after §3f, after §3g.
- **The by-hand upper bound** stays: the same problems solved by a person's
  code, so a failure is the model's and not the API's.

A run takes the model about a minute per problem; the machine must be idle
and the user must say go before each run.

## 4. Steps

Work in the worktree `../projectured-julia-format` and in an omnet worktree.
Commit each step with explicit paths; land with `git merge --ff-only`; cap
every Julia process.

### Step 1. The answer of a search (§3a) — done 2026-09-16

- [x] `Documentation.jl`: `_ApiEntry.signature` and `summary`, read by
      `_read_doc_heading` from the paragraphs of the docstring; the two-line
      hit, `_format_api_hit`; the footer by kind, `_format_api_footer`; the set
      methods `search_api(set, …)` and `search_documentation(set, …)`; one
      module entry per module; the catalogues show the description and say
      "Types:" instead of "Classes:"; `describe_api` shows the first signature.
      `_first_paragraph` has no caller left and is gone.
- [x] `MeaningSearch.jl`: the three notes say what ranked the hits, and never
      "this editor". `DefaultTools.jl`: the tools call the set methods.
- [x] Tests: `test/kernel/tool/SearchAnswerTest.jl`, `test_search_answer()`,
      registered in `KernelSuite.jl` and `ProjecturedKernelTest`; the tests that
      read the old format follow the new one. The kernel search tests: 260 pass.
- [x] `agent.md` says what a hit shows and how to read one; `setup-guide.md`
      and `PAR-NEVER-GUESS-NAMES` name the catalogues that exist.
- [x] omnet: `measure_meaning_search!` parses the new hit line; the live
      table prints the same ranks, 5 of 8 verbs and 7 of 8 guides first.

### Step 2. The benchmark and its baseline (§3i)

- [x] projectured: `LlmTurnEnd` carries `input_tokens` and `output_tokens`,
      filled by both adapters; `_run_agent_loop!` takes `observe`, a callback
      that sees every event of a turn. The Ollama live test skips a resident
      model that can not chat, because the meaning model now stays in memory.
- [x] omnet: the eight cases are `_SESSION_PROBLEMS`, each a setup, a sentence
      and a check; `_ask` records rounds, calls by tool, tokens and seconds
      through `observe`; `measure_assistant_problems` prints the table and
      `test_assistant_session` prints it after its assertions; the study arc
      prints the same table for its seven turns; `test_assistant_problem_table`
      runs the table with a `FakeLlm` and needs no server. 64 assertions pass.
- [x] The user said go on 2026-09-16 and named a second model,
      `qwen3-coder:30b-a3b-q8_0`. The baseline of `qwen3.8:27b` is in §5. The
      second model's run was cut off by a crash of the user's session and waits
      for an idle machine.

### Step 3. The two searches, footers, sections (§3b, §3c, §3d, §3h) — done 2026-09-16

- [x] `search_documentation` → `search_guides`, tool and function, with
      `julia-rename.jl` (15 references in 7 files in projectured, 2 in omnet)
      and the sweep of strings, docstrings and guides; the test functions
      followed. Each tool's description says in one sentence when to use it.
- [x] `detail` on both searches: `names` (25), `summary` (8), `full` (3), and a
      `limit` given replaces the count; an unknown detail answers the three.
- [x] `_make_footer`: over 600 characters, a list ends with how to read its
      first hit in full and how to narrow the search; a shorter answer ends
      with its hits; a miss names the other search. A long whole guide ends
      with its sections. The plan first put a reader line on every list, and
      the rule above replaced it.
- [x] `read_resource` reads `resource://guide/<name>#<heading>` and
      `resource://function/<module>/<name>` by their shape; a guide hit carries
      its section URI; `describe_resources` answers the kinds in six lines and
      the `list_resources` tool answers it.
- [x] `agent.md` and `orientation.md` say all of it. The kernel search tests:
      286 pass.
- [x] omnet: the window's prompt, its guide and its measurement say
      `search_guides`. The IDE harness tests, 64, and the campaign assistant
      test, 16, pass against the landed projectured.

### Step 4. `execute_julia_code` (§3e) — done 2026-09-16

- [x] The last value: `Text` whole; a short value as its `repr`; a long
      `String` whole without its quotes; anything else described by its
      `summary` with how to read a part of it. `repr` is limited, so a long
      vector shows as Julia's own elided line, and the description is for what
      is long even limited, a tuple or a table. `nothing` with nothing printed
      is "Done.". Printed output comes first and is never cut.
- [x] An `UndefVarError` answers the nearest declared names: by the words the
      guess shares, then by edit distance, at most three.
- [x] The descriptions of `execute_julia_code` say to print what is wanted,
      and no longer forbid `print`.
- [x] `test/kernel/tool/CodeExecutionTest.jl`, `test_code_execution()`. The
      kernel search tests: 304 pass.

### Step 5. The docstring standard (§3f) — done 2026-09-16

- [x] The rule and its grep in `code-quality-rules.md`, under §1.
- [x] The 66 declared names of the omnet IDE that are not `DataFrames`': 48
      in omnet (the campaign verbs, the result verbs, the six readers, the six
      selections and the two views, the study verbs and the four study
      types) and 18 in projectured (the pane verbs and types, the five
      layouts, `get_formula_value`, `@reference`). Each gained its "Use it to"
      paragraph in a person's words, an example that runs in the window, and
      its neighbours. A tool, `add_use.py` in the scratchpad, put them under
      the first paragraph.
- [x] `_search_text` reads the "Use it to" paragraph wherever it stands, so
      the keyword scorer counts a person's words too.
- [x] The harness keeps every problem's transcript, one markdown file per
      problem, headed by its sentence and its outcome.
- [x] The golden table before and after, and the benchmark run again; the
      numbers are in §5.

### Step 6. The interface vocabulary (§3g) — started 2026-09-16

- [x] The survey: names, collisions, the verbs a case needs; the user chooses.
      The set is in §5, "The interface survey". The user was asked twice and
      said "continue with the plan", so the proposed set stands.
- [x] The declaration, the docstrings, the golden sentences, the benchmark
      problems; the benchmark run again. Done 2026-09-16; the table is in §5,
      "After Step 6".

### Step 7. Reduce (§3h) and close

- [x] `SimulationToolsModule` and its test, after decision 3. **The premise
      was half wrong, and the reduction is a move.** The module held the eleven
      tools no window registers, and also `build_campaign_session` and
      `SimulationToolContext`, which `run_campaign_window`, the precompile
      workload and the test fixture build the window with. Decided by the user
      2026-09-16 ("yes, continue"): `CampaignSessionModule` in omnet holds
      `CampaignSession(editor, tree, filter)` and `build_campaign_session`,
      whose Run wiring is `run_filter_in_new_pane!`; the tools file and
      `test_simulation_tools` are deleted, and `test_campaign_session` presses
      Run on a stub project. `batches`, which only the tools read, is gone.
- [x] **The round cap.** Decided by the user 2026-09-16: `Agent`'s default
      `max_rounds` is 8, from 5. Eight is what a turn that searches, reads a hit
      in full and writes needs, with a wrong guess and a read after it to spare.
      Measured once more below, "After Step 7".
- [x] Move this plan to `plan/done/` with the benchmark tables. Done 2026-09-16.

## 5. Findings

**Step 1, 2026-09-16.**

- **The whole docstring of one clear hit showed a name the model may not
  write.** A declaration that renames a function — `describe` as
  `summarize_frame` — got the hit under the new name, and the docstring under
  it opened with `describe(df)`. The signature paragraph of a renamed entry now
  carries the model's name, and the prose keeps its words. Found by the new
  test, not by a model.
- **`string(@doc f)` is not the docstring on Julia 1.13.** It is the `repr` of
  a `DocStr`. The index reads a docstring through `Base.Docs._doc` on a
  `Binding`, in `_binding_doc`, and a test must read it the same way.
- **A docstring's signature paragraph can be fenced, and can hold several
  signatures.** `_read_doc_heading` removes the fence and cuts at the second
  signature; `DataFrames.subset` opens with two.

**The baseline, 2026-09-16, `qwen3.8:27b`**, with the tools of Step 1: the
two-line hits, no `detail`, no footers, `search_documentation` still so named.
The seed and the context are the harness's own. The machine ran nothing else.

| problem | solved | rounds | calls | tokens in / out | seconds | first verb | tools |
| --- | --- | --- | --- | --- | --- | --- | --- |
| simulation_count | yes | 5 | 4 | 15,839 / 417 | 56.7 | `select_simulations!` | search_api, read_function_documentation, execute_julia_code, search_documentation |
| simulation_run | no | 5 | 6 | 34,811 / 429 | 46.1 | `select_simulations!` | search_api, read_resource, read_function_documentation ×2, execute_julia_code, … |
| scalar_result_table | no | 5 | 5 | 15,205 / 496 | 36.5 | — | search_api, read_function_documentation, search_api, read_function_documentation, search_api |
| vector_result_plot | yes | 4 | 4 | 12,993 / 319 | 27.3 | `open_pane!` | search_api ×2, read_function_documentation, execute_julia_code |
| added_plot_series | yes | 5 | 5 | 30,743 / 973 | 84.3 | `show_layout` | search_documentation, read_resource, execute_julia_code ×3 |
| pane_arrangement | yes | 4 | 4 | 28,231 / 2,048 | 143.3 | `show_layout` | search_api, read_resource, execute_julia_code ×2 |
| simulation_stop | no | 5 | 6 | 20,417 / 1,027 | 74.7 | `show_layout` | search_api, read_function_documentation, execute_julia_code ×2, search_api, execute_julia_code |
| result_frame_columns | yes | 2 | 1 | 4,815 / 133 | 13.2 | `get_simulation_scalar_results` | execute_julia_code |

Solved 5 of 8; 35 rounds, 35 calls, 163,054 tokens in and 5,842 out, 482 s.

What the table says:

- **The round cap decides.** Five of the eight turns ran to the fifth round,
  the cap `Agent` sets, and all three failures are among them. A turn that
  searches, reads and then writes code has spent three rounds before its
  first call; a wrong first call leaves it one.
- **A search is followed by a read.** `read_function_documentation` follows
  `search_api` in five of eight turns, and `scalar_result_table` spent its five
  rounds in three searches and two reads and never wrote code. The whole
  docstring of one clear hit was meant to end this pair; the model asks with
  words that give several hits.
- **The prompt is the cost.** 163,054 tokens in against 5,842 out: every round
  re-reads the conversation, so a turn of five rounds reads its transcript five
  times. A shorter answer per tool call is worth more than a shorter prompt.

**After Steps 3 and 4, 2026-09-16**, the same eight problems, the same seed:
the two-line hits, `detail`, footers, section and function URIs,
`search_guides`, the last value described, the nearest names. One model per
process, the other unloaded first.

`qwen3.8:27b`:

| problem | solved | rounds | calls | tokens in / out | seconds | first verb | tools |
| --- | --- | --- | --- | --- | --- | --- | --- |
| simulation_count | yes | 4 | 4 | 15,626 / 477 | 57.9 | `select_simulations!` | search_api, search_guides, read_resource, execute_julia_code |
| simulation_run | yes | 4 | 4 | 27,765 / 433 | 45.4 | `select_simulations!` | read_resource, search_api, execute_julia_code ×2 |
| scalar_result_table | yes | 3 | 2 | 9,876 / 318 | 28.7 | `open_pane!` | search_api, execute_julia_code |
| vector_result_plot | yes | 5 | 4 | 17,870 / 416 | 32.6 | `open_pane!` | search_api, read_function_documentation, search_api, execute_julia_code |
| added_plot_series | yes | 5 | 9 | 28,697 / 1,298 | 78.7 | `show_layout` | search_api ×2, search_guides, read_resource, show_layout, execute_julia_code, … |
| pane_arrangement | yes | 5 | 5 | 36,779 / 2,878 | 186.3 | `show_layout` | read_resource, execute_julia_code, read_function_documentation, search_api, execute_julia_code |
| simulation_stop | no | 5 | 6 | 19,491 / 762 | 57.8 | `show_layout` | search_api, read_function_documentation, search_api, execute_julia_code ×2, search_api |
| result_frame_columns | yes | 2 | 1 | 5,632 / 179 | 14.7 | — | search_api |

Solved 7 of 8, from 5; 33 rounds, 35 calls, 161,736 tokens in and 6,761 out,
502 s. `scalar_result_table` went from five rounds of searches and reads to one
search and one call: the two-line hit told it what `make_scalar_result_table`
was for. `simulation_run` was solved in four rounds. `simulation_stop` still
fails: the model reaches for `show_layout` and never finds the set to stop.

`qwen3-coder:30b-a3b-q8_0`, its first table; the server says it has the
`tools` capability and no `thinking`:

| problem | solved | rounds | calls | tokens in / out | seconds |
| --- | --- | --- | --- | --- | --- |
| simulation_count | yes | 2 | 1 | 5,464 / 77 | 24.4 |
| simulation_run | no | 1 | 0 | 2,612 / 31 | 0.7 |
| scalar_result_table | no | 5 | 5 | 18,273 / 493 | 17.4 |
| vector_result_plot | no | 1 | 0 | 2,609 / 34 | 0.9 |
| added_plot_series | no | 1 | 0 | 2,620 / 94 | 2.1 |
| pane_arrangement | no | 5 | 6 | 17,588 / 175 | 7.9 |
| simulation_stop | no | 1 | 0 | 2,616 / 76 | 2.1 |
| result_frame_columns | yes | 1 | 0 | 2,622 / 36 | 0.9 |

Solved 2 of 8; 17 rounds, 12 calls, 54,404 tokens in and 1,016 out, 56 s. Five
of eight turns ended in one round with no tool call and under a hundred tokens
written; the two it solved it solved without running code. The turns it did
call tools in read the resource list and searched, and never wrote code. This
is a model that does not use the tools, and no change to the tools is measured
by it until it does. The transcripts of the next run say what it wrote.

**Step 5, 2026-09-16.**

- **A tool that edits docstrings must parse what it wrote.** The first pattern
  of `add_use.py` took the first prose paragraph as "every line to the next
  blank line", and a docstring whose first paragraph is its last has no blank
  line before its closing quotes: the paragraph ran into the code below, the
  paragraph landed after the code, and three projectured files did not parse
  on `main` for eleven minutes. A line of three quotes is now never part of a
  paragraph, and every touched file goes through `Meta.parseall` before it is
  committed.
- **Two characters end or break a docstring from inside an example.** Three
  quotes, as in a `raw"""…"""` file, end the docstring; a `$`, as in an INI
  iteration variable `${K=1..10}`, starts an interpolation. Both are written
  escaped, `\"\"\"` and `\$`, and the docstring of `write_ini_file!` had said
  so of the second already.

**After Step 5, 2026-09-16.** The search measurement, the sixteen sentences of
`measure_meaning_search!`, before and after the use paragraphs:

| | verbs found by words | verbs first by words | verbs first by description | guides first by description |
| --- | --- | --- | --- | --- |
| before | 5 of 8 | 4 | 5 | 7 |
| after | 8 of 8 | 3 | 5 | 7 |

The words now find every verb, because the use paragraph says the words a
person says and the keyword scorer reads it. By meaning, `add_finding!` rose
from 25th to 5th and `get_simulation_scalar_results` from 4th to 4th, and
`make_result_plot` fell from 12th to 14th: with every verb's docstring saying
"value" and "over time" somewhere, the meaning of a sentence is spread thinner.

`qwen3.8:27b`, the eight problems, the same seed: solved 5 of 8; 31 rounds, 31
calls, 157,280 tokens in and 6,079 out, 464 s. Two problems that Steps 3 and 4
had solved failed, and the transcripts say why:

- `scalar_result_table`: the model read the example of
  `get_simulation_scalar_results`, which the docstring rendered as
  `filter_expression = "name =~ "*delay*""` — a docstring turns `\"` into `"`,
  and the example had been written with one backslash. The model wrote in its
  reasoning "example weird escaping", chose `"name =~ \"delay\""`, an exact
  match on the name `delay`, and opened an empty table. The twelve example
  lines with a quoted match are written with `\\"` now, and the run below is
  after that fix.
- `added_plot_series`: five rounds and eight calls, three of them code, and the
  plot still held one series at the cap.

After the fix, the same run: solved 6 of 8; 31 rounds, 31 calls, 157,042
tokens in and 6,139 out, 468 s. `scalar_result_table` was solved in three
rounds and two calls, with the corrected example. The two that fail are the two
that fail at every stage:

- `simulation_stop` is checked wrongly, and the transcript says so: "the set is
  still finished". The stub's runs end within a second, so the set is
  `:finished` before most turns are, and the check accepted only `:stopping`,
  `:stopped` and `:done`. The model did reach for `stop_simulations!` — with
  the tab instead of the tab's `content`, got a `MethodError`, and ran out of
  rounds. The check now requires that `stop_simulations!` was called and that
  nothing runs afterwards, a finished set included.
- `added_plot_series` found the guide section that says how — "Several frames
  in one plot", read through its section URI — and then spent its last three
  rounds on the frame: `columns(frame)`, which no name is near, and
  `length(::DataFrame)`, a `MethodError`; the cap of five rounds ended it with
  the plot untouched. The round cap decides, as the baseline said; a cap of
  eight would cost a failed turn three more rounds and give a turn like this
  one what it needs.

`vector_result_plot` went from four rounds to three and from four calls to two:
the search answered `get_simulation_vector_results` in full, with its example,
and the model wrote the call at once.

`qwen3-coder:30b-a3b-q8_0` solved 2 of 8 again, in 46 s. Its transcript of
`simulation_run` is one sentence: "None of the provided functions can be used
to run TandemQueue simulations. They are all related to reading documentation
resources, not executing simulations." It reads the six tools as readers and
does not see `execute_julia_code` as the way to act, although the prompt says
the verbs are called through it. A tool change is not measured by this model;
a prompt whose first line says that everything is done by writing Julia into
`execute_julia_code` might be, and is a question for the prompt's owner.

### The interface survey (Step 6)

The survey read `WidgetDocument.jl`, forty-four widget types, `LayoutDocument.jl`
and `Geometry.jl`, and chose by one question: does a person ask for it by name
when they say what a pane shows. Thirty-one names are declared, by
`make_interface_api()` in `PaneProgram.jl`, beside `make_pane_api()`:

| kind | names |
| --- | --- |
| containers, 7 | `WidgetCard`, `WidgetTitlePane`, `WidgetTabbedPane`, `WidgetSplitPane`, `WidgetScrollPane`, `WidgetAccordion`, `WidgetComposite` |
| content, 8 | `WidgetLabel`, `WidgetText`, `WidgetTextarea`, `WidgetTable`, `WidgetBadge`, `WidgetAlert`, `WidgetProgress`, `WidgetSeparator` |
| controls, 10 | `WidgetButton` with `Action`, `WidgetCheckbox`, `WidgetSwitch`, `WidgetToggleGroup`, `WidgetRadioGroup`, `WidgetSelect`, `WidgetSlider`, `WidgetSpinBox`, `WidgetList` |
| geometry, 2 | `Point2D`, `Inset` |
| size policies, 4 | `Fixed`, `Content`, `Relative`, `Fill` |

§3g named a policy `Weight`; no such name exists. `Relative(weight)` and
`Fill`, which is `Relative(1.0)`, are the names. The five layouts are declared
already, by `make_pane_api()`.

Left out, and why:

- `WidgetTabPage`, `WidgetAccordionItem`, `WidgetOption`: a tuple builds each,
  and the container's docstring says so.
- `WidgetMenu`, `WidgetMenuItem`, `WidgetContextMenu`, `WidgetToolbar`,
  `WidgetStatusBar`, `WidgetShell`, `WidgetDialog`, `WidgetTooltip`: the
  window's chrome, which the window builds, not a pane's content.
- `WidgetTree`, `WidgetToggle`, `WidgetAvatar`, `WidgetSkeleton`,
  `WidgetHighlight`, `WidgetTransformPane`, `WidgetScrollBar`,
  `WidgetInsertion`, the constraint layouts and every projection: no problem of
  the table asks for one. A declared name is a name in every search, so a name
  without a problem costs the ranking and buys nothing.

**Collisions:** none. `declare_api!` builds the omnet declaration with the
thirty-one names, and `select` is not among them. **Verbs:** none added.
`open_pane!` places a widget as it places a document, and
`replace_referenced_value!` swaps one; no case of the table needs a pane closed.

**The docstrings.** Each of the thirty-one has the §3f shape: the first
sentence, "Use it to", an example that runs in the omnet window, "See also".
The prose the docstrings held for a person — transient state, the variants of
a card, the fields of a table — stays under the example. The example of
`WidgetTextarea` carries `\\n`, because a docstring renders `\n` as a line break
inside the copied code (the lesson of Step 5). The example of `WidgetButton` binds a callback that
takes the editor; the by-hand case clicks it and gets a set of runs.

**The problems.** Three join the table, eleven in all: `card_around_table`
("Open a card titled "Delay" that holds a table of the delay scalars"),
`table_beside_plot` ("Show a table of the delay scalars and a plot of the delay
vectors side by side, in one pane") and `button_runs_again` ("Add a button
labelled "Run again" that runs the TandemQueue simulations when it is
clicked"). A check walks every field of what a tab holds, so a card inside a
row inside a card is found where the model put it. The golden table gains four
sentences: a row, a card, a button, an alert.

### After Step 6 — the interface declared, 2026-09-16

The search, on the same twenty sentences plus four for the interface:

| corpus | first by words | first by description | found by words |
| --- | --- | --- | --- |
| verbs and names, 12 | 5 | 8 | 12 |
| guides, 8 | 5 | 7 | 8 |

The four interface sentences: "a card with a title around the plot" ranks
`WidgetCard` first by words and by description; "a button that runs the sweep
again" ranks `WidgetButton` first by both; "a message that warns about a failed
run" ranks `WidgetAlert` tenth by words and first by description; "put the
table and the plot side by side" ranks `HorizontalLayout` fifteenth by words
— "table" is `WidgetTable`'s word — and second by description, after `Fill`.
The eight old verb sentences keep their ranks, but "draw how a value changes
over time" fell from twelfth to twentieth by description: thirty-one more names
share the ranking, and that docstring still says "chart".

`qwen3.8:27b` on the eleven problems, seed and context as before:

| problem | solved | rounds | calls | tokens in / out | seconds | first verb |
| --- | --- | --- | --- | --- | --- | --- |
| simulation_count | yes | 3 | 3 | 17,432 / 589 | 70.3 | `select_simulations!` |
| simulation_run | yes | 5 | 5 | 36,502 / 433 | 46.9 | `select_simulations!` |
| scalar_result_table | yes | 5 | 7 | 19,750 / 496 | 35.4 | `get_project_result_directory` |
| vector_result_plot | yes | 5 | 5 | 24,861 / 418 | 40.2 | `open_pane!` |
| added_plot_series | yes | 5 | 4 | 36,785 / 876 | 65.6 | `show_layout` |
| pane_arrangement | yes | 3 | 2 | 9,709 / 1,079 | 66.0 | `show_layout` |
| simulation_stop | yes | 5 | 6 | 19,590 / 402 | 33.0 | `show_layout` |
| result_frame_columns | yes | 5 | 4 | 24,986 / 838 | 70.5 | `get_simulation_scalar_results` |
| card_around_table | no | 5 | 6 | 20,153 / 748 | 52.8 | `get_project_result_directory` |
| table_beside_plot | no | 5 | 8 | 29,885 / 1,031 | 89.6 | — |
| button_runs_again | yes | 5 | 9 | 27,871 / 918 | 67.0 | `show_layout` |

Solved 9 of 11: 51 rounds, 59 calls, 267,524 tokens in and 7,828 out, 637 s.
**The eight problems of the earlier stages are all solved**, 8 of 8, against
6 of 8 after Step 5 and 5 of 8 at the baseline; `simulation_stop` and
`added_plot_series`, the two that failed on the corrected examples, passed.
One seed, and a prompt that now carries thirty-one more names, so every sample
differs from the earlier runs': the two that pass now are the two a `MethodError`
and the cap ended before, and nothing in Step 6 touched their verbs. The gain on
the eight is within the noise this plan warned about, and a second seed would
say more. The three interface problems:

- **`button_runs_again` passed**, in five rounds and nine calls. The search
  "button with click action callback" answered `WidgetButton` first; the model
  read `Action`, `WidgetButton` and `open_pane!` in full and wrote, in its
  words, "The Action example shows exactly this": the docstring's example,
  with the configuration changed.
- **`card_around_table` failed** with a table titled "Delay" in a tab, and the
  reply "I opened a card titled Delay". The search "card" by description
  ranked `run_card!` first and `WidgetCard` second, and the footer pointed at
  the first; the model read the table verbs instead and took the tab for the
  card. The meaning of one word is thin: "card" is `run_card!`'s word as much
  as `WidgetCard`'s, and a sentence would have ranked them apart, as the golden
  table shows.
- **`table_beside_plot` failed without writing code.** Three searches for the
  readers and the plot, the whole assistant guide read as one resource, 4,000
  characters, and in the fifth round the search "a horizontal row container
  that shows two documents beside each other in one pane", which answered
  `HorizontalLayout` first with its sentence "A row of children" — then the
  read of it in full was the turn's last call. The cap of five rounds decided
  it, with the answer in hand. This is the third turn the cap ends one round
  short of its solution, after `added_plot_series` in Step 5.

**What the run says about the cap.** Of the eleven turns, nine ran to the
fifth round. A cap of eight would have cost `table_beside_plot` one more round
and given it its pane; it would cost a turn that has lost its way three rounds
more. The proposal of Step 5 stands, and it is the prompt owner's call.

### After Step 7 — the cap of eight, 2026-09-16

The same eleven problems, the same seed, `Agent`'s `max_rounds` 8:

| problem | solved | rounds | calls | tokens in / out | seconds |
| --- | --- | --- | --- | --- | --- |
| simulation_count | yes | 3 | 3 | 17,432 / 589 | 69.0 |
| simulation_run | yes | 5 | 5 | 36,502 / 433 | 46.6 |
| scalar_result_table | yes | 8 | 10 | 37,283 / 835 | 62.2 |
| vector_result_plot | yes | 6 | 5 | 32,273 / 476 | 43.3 |
| added_plot_series | yes | 5 | 4 | 36,785 / 876 | 63.9 |
| pane_arrangement | yes | 3 | 2 | 9,709 / 1,079 | 64.5 |
| simulation_stop | yes | 7 | 7 | 36,560 / 560 | 48.3 |
| result_frame_columns | yes | 5 | 4 | 24,986 / 838 | 70.8 |
| card_around_table | no | 5 | 6 | 20,153 / 748 | 52.9 |
| table_beside_plot | no | 8 | 11 | 65,274 / 1,687 | 138.2 |
| button_runs_again | yes | 6 | 9 | 36,494 / 989 | 73.5 |

Solved 9 of 11: 61 rounds, 66 calls, 353,451 tokens in and 9,110 out, 733 s.
**The cap bought nothing on this seed.** The same nine pass and the same two
fail; the rounds grew from 51 to 61 and the tokens by a third, because a turn
that had its answer at round five went on checking it. `card_around_table` ends
by itself at five rounds, as before, with the tab taken for the card.
`table_beside_plot` used all eight and still failed, and its transcript says
what the extra rounds bought:

- Round six read `resource://function/ResultVerbsModule/get_simulation_scalar_results`
  — the model's guess of the module — and the reader answered "not one of the
  names you may write", which is false: the name is declared, in another
  module. Fixed after this run: a read under the wrong module now says where
  the name is declared and the URI that reads it there.
- Round seven wrote the whole solution — `HorizontalLayout([table, plot])`
  in `open_pane!` — with the filter `name =~ "delay"`, an exact match that
  matched nothing; the example says `"*delay*"`.
- Round eight guessed a column `:scalar` that the frame does not have.

The cap stands at eight, as decided: it is not what fails these turns, and
a turn that needs six rounds has them. What fails them is a wrong guess
answered with less than the truth, which the fix above addresses, and the
model's own habit of shortening an example.
