# The assistant finds the API for what it means

> **Kind:** plan · **Status:** pending · **Stands on:**
> [three-kinds-of-search.md](../done/three-kinds-of-search.md),
> [declared-api-is-a-list-of-names.md](../done/declared-api-is-a-list-of-names.md),
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

### Step 6. The interface vocabulary (§3g)

- [ ] The survey: names, collisions, the verbs a case needs; the user chooses.
- [ ] The declaration, the docstrings, the golden sentences, the benchmark
      problems; the benchmark run again.

### Step 7. Reduce (§3h) and close

- [ ] `SimulationToolsModule` and its test, after decision 3.
- [ ] Move this plan to `plan/done/` with the four benchmark tables.

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

