# The assistant recovers from a miss

> **Kind:** plan · **Status:** pending · **Stands on:**
> [assistant-finds-the-api.md](../done/assistant-finds-the-api.md),
> [three-kinds-of-search.md](../done/three-kinds-of-search.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [code-quality-rules.md](../../documentation/rule/code-quality-rules.md)

**Goal.** The plan before this one ended with `qwen3.8:27b` at 9 of 11
problems and four open items. This plan closes the four items. Each item is a
place where the model missed, and each fix puts the way out into the answer the
model reads: a short search says how to ask, an empty result says which names
exist, and the prompt names only words that exist.

**The measure** stays the benchmark of eleven problems,
`measure_assistant_problems` in omnet. It changes in one way: a stage runs on
three seeds. One seed can not tell a fix from noise, and the last plan showed
that twice.

## 1. What is known, 2026-09-17

### 1a. A rank probe

A probe ranked the omnet IDE's declared names with `nomic-embed-text`. It
reads ranks only, so it is not a measurement in the sense of §4.

What one or two words answer, first five hits:

| query | keywords | description |
| --- | --- | --- |
| card | `run_card!`, `make_run_card`, `WidgetCard`, … | `run_card!`, `WidgetCard`, `make_run_card`, … |
| a card | the same | the same |
| card widget | `WidgetCard`, `run_card!`, `make_run_card`, … | `WidgetCard`, `WidgetList`, `WidgetCheckbox`, … |
| button | `WidgetButton`, `Fixed`, `Action`, … | `WidgetButton`, `WidgetCheckbox`, `WidgetSwitch`, … |
| plot | `ResultPlotView`, `make_result_plot`, … | `make_result_plot`, `ResultPlotView`, … |
| row | `nrow`, `ByRow`, `GridLayout`, … | `GridLayout`, `HorizontalLayout`, `nrow`, … |
| split | `PaneSplit`, `WidgetSplitPane`, … | `WidgetSplitPane`, `WidgetSeparator`, `PaneSplit`, … |

The rank of the expected verb for the twelve verb sentences, by the text a
vector is computed from: the whole docstring (now), the name with the first
paragraphs and the "Use it to" paragraph (purpose), the better of the two
scores (max), and their mean.

| sentence | expected | whole | purpose | max | mean |
| --- | --- | --- | --- | --- | --- |
| draw how a value changes over time | `make_result_plot` | 20 | 15 | 21 | 17 |
| the single numbers the runs recorded | `get_simulation_scalar_results` | 5 | 3 | 3 | 3 |
| write down what the runs taught us | `add_finding!` | 5 | 4 | 5 | 4 |
| run the simulations the filter selects | `run_simulations!` | 1 | 2 | 2 | 2 |
| put the table and the plot side by side | `HorizontalLayout` | 2 | 2 | 2 | 2 |
| a button that runs the sweep again | `WidgetButton` | 1 | 2 | 1 | 2 |
| the six other sentences | | 1 | 1 | 1 | 1 |
| **sum of ranks / ranked first** | | **40 / 8** | **34 / 6** | **40 / 7** | **36 / 6** |

Two conclusions:

- **A description of one word ranks by the word.** Both modes put `run_card!`
  first for "card", and "a card" is no better, because "a" is a stop word.
  "card widget" puts `WidgetCard` first in both modes. The failure of
  `card_around_table` began with the search "card".
- **The whole docstring stays the best text for a vector.** The purpose text
  lowers the sum of ranks and ranks two fewer sentences first. No mix ranks
  `make_result_plot` in the first ten.

### 1b. A correction

The done plan said that `make_result_plot` ranks twentieth because its
docstring "still says chart". That is false. Since Step 5 of that plan the
docstring says "Use it to draw, plot or chart what the runs recorded: a value
over time from a vector frame". The first three hits for the sentence are
`get_referenced_value`, `get_formula_value` and `replace_referenced_value!`: the
small meaning model matches the word "value" to the names that hold it. The done
plan is corrected.

### 1c. What else was found

- **The window's prompt names four words a model can not call.**
  `CAMPAIGN_SYSTEM` says "`focus_pane`, `close_pane`, `move_pane` and
  `resize_pane`", and "each names a pane by its title". The declared verb is
  `focus_pane!(editor, reference)`, which takes a reference. `close_pane`,
  `move_pane` and `resize_pane` occur in no source file of either repository
  except the prompt. The eleven tools removed in the last plan's Step 7 had two
  of these names.
- **The model that called no tool is no longer installed.**
  `qwen3-coder:30b-a3b-q8_0` is gone from Ollama. `mistral:latest` is there:
  7.2 B parameters, `Q4_K_M`, 4.4 GB, with the `tools` capability. The coder
  model needs 32.5 GB, and the memory rule of §4 asks for the Julia cap, the
  model and 10 GB free: 20 + 32.5 + 10 is more than the machine's 61 GB.
- **A filter that matches nothing costs a turn.** Twice the model wrote
  `name =~ "delay"`. An OMNeT++ pattern matches the whole name, and the names
  are `delay:mean`, so the frame was empty. A table maker opened an empty
  table (Step 5 of the last plan); `make_result_plot` answered "Nothing matched,
  so there is nothing to plot." and nothing more (its Step 7).
- **`mxbai-embed-large` is installed** since 2026-09-17, with the `embedding`
  capability. `_MEANING_PREFIXES` in `source/ollama/Ollama.jl` already knows
  its query prefix, and its vectors go to a file of their own,
  `build/meaning/ollama_mxbai-embed-large.bin`.
- **The vectors are computed without a manual step, with three limits.** A
  vector is keyed by its exact text. Binding a meaning model to a tool set
  queues every declared entry and guide section that has no vector, and a
  description search queues what it lacks; a task computes them and appends
  them to the model's file. A changed docstring is a new text, so it gets a
  new vector. The limits: the API and guide indexes are read once per Julia
  process, so a docstring edited under Revise is seen after a restart; a model
  pulled again under the same name, with vectors of the same length, keeps the
  old vectors until its file is deleted; and the file never shrinks, because
  the vector of an old text stays in it. `agent.md` says the first and none of
  the limits.
- **A test writes into the real vector folder.** `test_campaign_assistant` in
  omnet binds `FakeLlm("ok"; meaning_model = "campaign")`, and the build of
  that fake model wrote `build/meaning/fake_campaign.bin`, 1.9 MB, into
  projectured's folder on 2026-09-16. The measurement test points
  `_MEANING_FOLDER` at a temporary folder; this test does not.
- The files this plan changes are unsealed (⬜) in both `SEALING.md` files.

## 2. The design

### 2a. The benchmark runs on seeds

- `_session`, `_run_problem` and `measure_assistant_problems` take a seed.
  `measure_assistant_problems(; seeds = [SESSION_SEED])` runs each problem once
  per seed, each in a fresh window, all in one Julia process with one model.
- The table says `solved` as `k/n` per problem. Rounds, calls, tokens and
  seconds are sums over the seeds. A last line gives the solved count per seed,
  so a reader sees the spread.
- A transcript goes to `<folder>/<seed>/<problem>.md`.
- The stage seeds are `SESSION_SEED` and two more fixed values. A value means
  nothing; that it does not change is the point.
- `test_assistant_problem_table` runs the fake backend on two seeds. It checks
  the `k/n` column, the sums and the folders, and it still needs no server.
- Cost: `qwen3.8:27b` took 637 s and 733 s for one seed, so a stage of three
  seeds takes about 35 minutes.

### 2b. A short description says how to ask

**Decision: a description of one content word answers its hits with a note
before them.** The note says: "A description of one word ranks by that word
alone. Say in a sentence what the <word> is and what it does, and the meaning
ranks it." A content word is a word that is not in `_STOP_WORDS`.

- It is in `search_api` and in `search_guides`, at every `detail`.
- Why a note and not a new ranking: the probe shows that the keywords give the
  same order for one word, so no ranking of one word can tell a run card from a
  card widget. Two words can, and the model writes them when it is told to.
- Rejected: one hit per module before the rest. It changes every answer to fix
  one query.
- Test: `test_search_answer` gains a case. A one-word description answers the
  note, a sentence does not, and a keyword search of one word does not.

### 2c. An empty frame says which names exist

**Decision: two layers.** The first layer removes the pattern the model gets
wrong; the second answers the mistake when it is made anyway.

1. **`make_result_filter_expression(; name)`.** `name` is a word that the name
   of a statistic contains. `name = "delay"` writes `name =~ "*delay*"`. A
   `name` with `*` or `?` is a pattern and is written as it is. It joins the
   other terms with `AND`, as `config` and `run` do. The examples of the
   readers and of the view makers use `name = "delay"`. `filter` stays for the
   whole match language.
2. **An empty result is shown, and says why it is empty.** Decided by the user
   2026-09-17: no refusal. A table maker opens an empty table, as it does now,
   and `make_result_plot` answers a plot with no series instead of the error it
   throws now. A reader keeps the filter it read with: it writes
   `filter_expression` and `source` as frame metadata of style `:note`, which
   `filter` and `subset` carry along. A view maker — `make_result_table`, the
   six table makers and `make_result_plot` — that gets an empty frame prints
   one line, which `execute_julia_code` answers whole, and its
   `describe_document` says the same, so `show_layout` shows it too:

   ```
   The frame is empty: nothing matched name =~ "delay". A pattern matches the
   whole name. Names that contain "delay": delay:mean.
   Write make_result_filter_expression(name = "delay") to match every name that contains it.
   ```

   The line names eight names at most. A frame without the metadata prints
   "The frame is empty. Read it again with a wider filter_expression."
   A printed line and not a log record: the code tool captures what the code
   prints, and a log record goes to the logger the process started with.
   The plot projection must draw a plot with no series; the step checks it.

- Where: `source/ide/ResultVerbs.jl` and `source/legacy/result/ResultReader.jl`
  in omnet.
- Test: `test/ide/ResultVerbsTest.jl` checks the keyword, the printed line
  and the empty plot. The by-hand cases gain one: an exact pattern opens an
  empty table and prints the names, and the `name` keyword then opens a full
  one.

### 2d. The prompt names what exists, and says how to act

1. **The pane sentence.** It becomes: "To bring a pane forward, call
   `focus_pane!(editor, reference)` with a reference `open_pane!` answered or
   `show_layout` printed. To close, move or resize a pane, edit the program
   `show_layout` prints and send it back with `replace_referenced_value!`."
2. **A guard test.** Every backticked word in `CAMPAIGN_SYSTEM` and
   `IDE_SYSTEM` that has the shape of a Julia name is a declared name, a tool
   name, a declared module or `editor`. The test lists what else it allows: a
   resource URI and a file name. A prompt that names a word nobody can call then
   fails a test, not a turn.

**Not done: a second model, and a first line for it.** Decided by the user
2026-09-17: no second model. The first line — "You act by writing Julia" — was
for a model that calls no tool, and without such a model nothing measures what
it is for, so the prompt does not get it.

### 2e. A second meaning model, as an experiment

`measure_meaning_search!(; backend = OllamaLlm(; meaning_model =
"mxbai-embed-large"))` ranks the same twenty sentences. The default changes only
when the new model ranks at least as many sentences first as `nomic-embed-text`
does now (8 of 12 verbs and 7 of 8 guides), and ranks `make_result_plot` in the
first five. Otherwise the default stays, and the result is written here. The
sentence "draw how a value changes over time" stays in the golden table as a
known miss either way: the words "plot" and "chart" find the verb first.

The user downloaded the model on 2026-09-17. Its first measurement builds its
file; `measure_meaning_search!` waits for the build.

In the same step:

- `agent.md` says the three limits of §1c, and how to rebuild: delete the
  model's file, and the next binding computes every vector again.
- `test_campaign_assistant` points `_MEANING_FOLDER` at a temporary folder, as
  the measurement test does, and `build/meaning/fake_campaign.bin` is deleted.

## 3. Steps

Work in the worktree `../projectured-julia-format` and in the omnet worktree
`../omnet-julia-answer`. Commit each step with explicit paths. Land with
`git merge --ff-only`. Cap every Julia process.

### Step 1. The benchmark on seeds (§2a)

- [ ] The seed through `_session`, `_run_problem` and
      `measure_assistant_problems`; the `k/n` table; the folders per seed.
- [ ] `test_assistant_problem_table` on two seeds.
- [ ] The baseline: `qwen3.8:27b` on three seeds, with the user's word (§4).

### Step 2. The prompt (§2d)

- [ ] The pane sentence, and the guard test.

### Step 3. The short description (§2b)

- [ ] The note in both searches, and its test.

### Step 4. The empty frame (§2c)

- [ ] The `name` keyword, and the examples that use it.
- [ ] The metadata in the readers, the printed line and the description in
      the view makers, the empty plot, and the tests.

### Step 5. The stage run

- [ ] `qwen3.8:27b` on three seeds, with the user's word.

### Step 6. The second meaning model (§2e)

- [ ] The measurement with `mxbai-embed-large`, and the decision it gives.
- [ ] The limits of the vector store in `agent.md`; the campaign test in a
      temporary folder.

### Step 7. Close

- [ ] The tables in §6, and this plan to `plan/done/`.

## 4. Rule of measurement

- A benchmark run needs an idle machine and the user's word for that run. A
  test and a rank probe do not.
- One Julia process at a time, and one Ollama model in it. Before a run, read
  `free -g`: the free memory must hold the Julia cap (20 GB), the model and
  10 GB more. Unload every other model before the run and the run's own model
  after it.
- If the machine is busy at the moment of a run, say so and wait for the user.
  Do not start a loop that polls for an idle machine.

## 5. Decisions

Made by the user on 2026-09-17:

1. **Seeds:** three per stage.
2. **A second model:** none. §2d says what goes with it.
3. **An empty result:** shown, as an empty table or a plot with no series, and
   not refused. §2c says how the model learns why it is empty.
4. **`mxbai-embed-large`:** downloaded; Step 6 stays.

## 6. Findings

Nothing yet beyond §1.
