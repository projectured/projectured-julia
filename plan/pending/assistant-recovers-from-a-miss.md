# The assistant recovers from a miss

> **Kind:** plan · **Status:** pending · **Stands on:**
> [assistant-finds-the-api.md](../done/assistant-finds-the-api.md),
> [three-kinds-of-search.md](../done/three-kinds-of-search.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [code-quality-rules.md](../../documentation/rule/code-quality-rules.md)

**Goal.** The plan before this one ended with `qwen3.8:27b` at 9 of 11
problems and four open items. This plan closes the four items. Each item is a
place where the model missed, and each candidate fix puts the way out into the
answer the model reads: a short search says how to ask, an empty result says
which names exist, and the prompt names only words that exist. **No candidate
lands unless a measurement first proves that it is worth doing** (§2).

**The measure** stays the benchmark of eleven problems,
`measure_assistant_problems` in omnet. It changes in one way: a stage runs on
three seeds. One seed can not tell a fix from noise, and the last plan showed
that twice.

## 1. What is known, 2026-09-17

### 1a. A rank probe

A probe ranked the omnet IDE's declared names with `nomic-embed-text`. It
reads ranks only, so it needs no idle machine (§5).

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
  model needs 32.5 GB, and the memory rule of §5 asks for the Julia cap, the
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

## 2. The rule: measure first

Decided by the user on 2026-09-17: "don't change anything unless a measurement
proves that it's worth doing it first". Every item of §3 is therefore a
candidate, and a candidate passes two gates before it lands.

1. **The miss is real.** The baseline — `qwen3.8:27b` on three seeds, 33 turns
   — is counted for the miss the candidate is for. §3 names the count for each
   candidate. The candidate goes on only when the miss occurs in at least two
   turns and at least one of those turns fails. Otherwise §7 records it as
   measured and not worth doing, and nothing changes.
2. **The candidate helps.** The candidate is committed on a branch of its own,
   with its tests. A trial stage runs on the same three seeds with that
   candidate and no other. The branch is merged only when the miss occurs in
   fewer turns than in the baseline, and the solved turns are at least as many
   as in the baseline. Otherwise the branch stays unmerged, and §7 records the
   result.

One candidate per trial, so that a result names its cause. The candidate whose
miss fails the most turns goes first. The trial stage of a merged candidate is
the baseline of the next trial.

**The instrument is not a candidate.** The seeds of §3a change no behavior the
model sees, and every gate above needs them. Their proof is measured already:
between Step 5 and Step 6 of the last plan, `simulation_stop` and
`added_plot_series` went from failed to solved, although nothing in Step 6
touched their verbs. One seed can not tell a fix from that.

## 3. The candidates

### 3a. The instrument: the benchmark runs on seeds

- `_session`, `_run_problem` and `measure_assistant_problems` take a seed.
  `measure_assistant_problems(; seeds = [SESSION_SEED])` runs each problem once
  per seed, each in a fresh window, all in one Julia process with one model.
- The table says `solved` as `k/n` per problem. Rounds, calls, tokens and
  seconds are sums over the seeds. A last line gives the solved count per seed,
  so a reader sees the spread.
- A transcript goes to `<folder>/<seed>/<problem>.md`.
- The stage seeds are `SESSION_SEED` and two more fixed values. A value means
  nothing; that it does not change is the point.
- `_session` takes the meaning model of its Ollama backend, so that a trial of
  §3e can name `mxbai-embed-large`.
- `count_transcript_misses(folder)` reads the transcripts of a stage and counts
  the misses of §3b, §3c and §3d, each with the turns it occurred in and
  whether those turns were solved. The counts go into §7 beside the table.
- `test_assistant_problem_table` runs the fake backend on two seeds. It checks
  the `k/n` column, the sums and the folders, and it still needs no server. A
  test gives `count_transcript_misses` a folder of written transcripts with one
  miss of each kind.
- Cost: `qwen3.8:27b` took 637 s and 733 s for one seed, so a stage of three
  seeds takes about 35 minutes.

### 3b. A short description says how to ask

**The miss:** a `search_api` or `search_guides` call with mode `description`
and a query of one content word, a word that is not in `_STOP_WORDS`.

**The candidate:** a description of one content word answers its hits with a
note before them: "A description of one word ranks by that word alone. Say in a
sentence what the <word> is and what it does, and the meaning ranks it."

- It is in `search_api` and in `search_guides`, at every `detail`.
- Why a note and not a new ranking: the probe shows that the keywords give the
  same order for one word, so no ranking of one word can tell a run card from a
  card widget. Two words can, and the model writes them when it is told to.
- Rejected without a trial: one hit per module before the rest. It changes
  every answer to fix one query.
- Test: `test_search_answer` gains a case. A one-word description answers the
  note, a sentence does not, and a keyword search of one word does not.

### 3c. An empty result says which names exist

**The miss:** code that writes a pattern after `=~` with no `*` or `?`, and a
turn whose answer holds "Nothing matched" or whose check says that a table is
empty.

**Two candidates**, tried one at a time, in this order:

1. **An empty result is shown, and says why it is empty.** Decided by the user
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
   Write "name =~ \"*delay*\"" to match every name that contains it.
   ```

   The line names eight names at most. A frame without the metadata prints
   "The frame is empty. Read it again with a wider filter_expression." A
   printed line and not a log record: the code tool captures what the code
   prints, and a log record goes to the logger the process started with. The
   plot projection must draw a plot with no series; the test checks it.
2. **`make_result_filter_expression(; name)`**, tried only when the miss
   remains after the first candidate. `name` is a word that the name of a
   statistic contains. `name = "delay"` writes `name =~ "*delay*"`. A `name`
   with `*` or `?` is a pattern and is written as it is. It joins the other
   terms with `AND`, as `config` and `run` do. The examples of the readers and
   of the view makers use it, and the printed line of the first candidate names
   it. `filter` stays for the whole match language.

- Where: `source/ide/ResultVerbs.jl` and `source/legacy/result/ResultReader.jl`
  in omnet.
- Test: `test/ide/ResultVerbsTest.jl` checks the printed line and the empty
  plot, and the keyword when the second candidate is tried. The by-hand cases
  gain one: an exact pattern opens an empty table and prints the names.

### 3d. The prompt names only what exists

**The miss:** code that calls `close_pane`, `move_pane`, `resize_pane`, or
`focus_pane` without `!`, and an `UndefVarError` that names one of them.

**The candidate:**

1. **The pane sentence.** It becomes: "To bring a pane forward, call
   `focus_pane!(editor, reference)` with a reference `open_pane!` answered or
   `show_layout` printed. To close, move or resize a pane, edit the program
   `show_layout` prints and send it back with `replace_referenced_value!`."
2. **A guard test**, which lands with the sentence. Every backticked word in
   `CAMPAIGN_SYSTEM` and `IDE_SYSTEM` that has the shape of a Julia name is a
   declared name, a tool name, a declared module or `editor`. The test lists
   what else it allows: a resource URI and a file name.

**Not a candidate: a second model, and a first line for it.** Decided by the
user 2026-09-17: no second model. The first line — "You act by writing Julia" —
was for a model that calls no tool, and without such a model nothing measures
what it is for.

### 3e. A second meaning model

**The first gate is a rank measurement.** `measure_meaning_search!(; backend =
OllamaLlm(; meaning_model = "mxbai-embed-large"))` ranks the same twenty
sentences. The candidate goes on only when the new model ranks more of them
first than `nomic-embed-text` does now, 15 of 20, or as many with a lower sum of
ranks. Its first measurement builds its vector file, and the measurement waits
for the build.

**The second gate is a trial stage** with `mxbai-embed-large` as the meaning
model of the session. The default meaning model in `source/ollama/Ollama.jl`
changes only when the solved turns are at least as many as in the baseline.

The sentence "draw how a value changes over time" stays in the golden table
either way, as a known miss: the words "plot" and "chart" find the verb first.

## 4. Steps

Work in the worktree `../projectured-julia-format` and in the omnet worktree
`../omnet-julia-answer`. A candidate is committed on a branch of its own, which
is merged into the worktree's branch only when §2 says so. Commit with explicit
paths. Land with `git merge --ff-only`. Cap every Julia process. Every stage
run needs the user's word (§5).

### Step 1. The instrument (§3a)

- [ ] The seed and the meaning model through `_session`, `_run_problem` and
      `measure_assistant_problems`; the `k/n` table; the folders per seed.
- [ ] `count_transcript_misses`, and the tests of both.

### Step 2. The baseline

- [ ] `qwen3.8:27b` on three seeds, with the user's word.
- [ ] The table and the counts of the misses in §7, and the first gate of
      §3b, §3c and §3d decided from them.

### Step 3. The trials, one candidate each (§3b, §3c, §3d)

In the order of §2, and only for a candidate that passed the first gate:

- [ ] §3b, the note for a one-word description.
- [ ] §3c, the empty result that says why.
- [ ] §3c, the `name` keyword, when the miss remains.
- [ ] §3d, the pane sentence and its guard test.

Each: the branch with the change and its tests, the trial stage with the user's
word, the counts, and the merge or not.

### Step 4. The meaning model (§3e)

- [ ] The rank measurement with `mxbai-embed-large`.
- [ ] If it passes: the trial stage, with the user's word, and the default
      changed or not.

### Step 5. Close

- [ ] The tables and the gate results in §7, and this plan to `plan/done/`.

## 5. Rule of running a stage

- A benchmark stage needs an idle machine and the user's word for that run. A
  test and a rank measurement do not.
- One Julia process at a time, and one Ollama model in it. Before a run, read
  `free -g`: the free memory must hold the Julia cap (20 GB), the model and
  10 GB more. Unload every other model before the run and the run's own model
  after it.
- If the machine is busy at the moment of a run, say so and wait for the user.
  Do not start a loop that polls for an idle machine.

## 6. Decisions

Made by the user on 2026-09-17:

1. **Seeds:** three per stage.
2. **A second model:** none. §3d says what goes with it.
3. **An empty result:** shown, as an empty table or a plot with no series, and
   not refused. §3c says how the model learns why it is empty.
4. **`mxbai-embed-large`:** downloaded; §3e stays.
5. **Measure first:** no change lands unless a measurement proves first that it
   is worth doing. §2 says how.

## 7. Findings

Nothing yet beyond §1.

**Found, and not scheduled.** These change no behavior the model sees, so the
benchmark can not prove them worth doing, and this plan does not change them:

- `test_campaign_assistant` in omnet writes the vectors of its fake model into
  projectured's `build/meaning/`, as `fake_campaign.bin`.
- `agent.md` does not say the three limits of the vector store in §1c.
