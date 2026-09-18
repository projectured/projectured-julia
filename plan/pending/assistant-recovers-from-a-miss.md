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
which names exist, and the prompt names only words that exist. **A change that
bets on what the model will do lands only when a measurement first proves it
worth doing; a change that corrects something false lands with a test** (§2).

**The measure** stays the benchmark of eleven problems,
`measure_assistant_problems` in omnet. It changes in one way: a stage runs on
three seeds. One seed can not tell a fix from noise, and the last plan showed
that twice.

## 1. What is known, 2026-09-17

### 1a. A rank probe

A probe ranked the omnet IDE's declared names with `nomic-embed-text`. It
reads ranks only, and needs no model but the meaning model (§5).

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
  projectured's folder on 2026-09-16. The test does point `_MEANING_FOLDER` at
  a temporary folder, and sets it back when it ends; the build reads the folder
  on a task of its own, after it has gathered its texts, which is after the
  test set it back. (Found in Step 1; this bullet first said the test set no
  folder.)
- The files this plan changes are unsealed (⬜) in both `SEALING.md` files.

### 1d. The corpus grows, 2026-09-18

The user said that the declared corpus will soon hold thousands of names and
hundreds of modules. It is reachable today. A declaration of every module a
package exposes gives:

| corpus | modules | entries | functions | types | values | with a first sentence | guide sections |
| --- | --- | --- | --- | --- | --- | --- | --- |
| projectured | 72 | 5,556 | 990 | 4,221 | 273 | 1,544 | 1,036 |
| omnet | 80 | 3,769 | 1,177 | 2,191 | 321 | 1,697 | 1,349 |

Two things the counts say. Most entries are types, because `@document` writes a
schema variant per document type, and the pane module's own comment already
says what that costs a search. And most entries carry no sentence at all, so at
scale the ranking reads names and signatures more often than prose.

**What breaks first**, read off the code and not yet measured:

1. **Every description search rebuilds the whole corpus text.** The ranking
   builds the meaning text of every entry and looks each one up in a dictionary
   keyed by that whole text. At 120 entries that is nothing; at 10,000 it hashes
   megabytes per query.
2. **The vector file keeps the text beside each vector**, so it grows with the
   corpus and with every edit, and a text that is gone is never removed.
3. **The vectors live as a dictionary of arrays.** One dense matrix and one
   call of the linear algebra library is the same arithmetic, much faster.
4. **The word search reads the text of every entry, per query.** That is a
   linear scan with no index.
5. **The index is built by reading every docstring**, once per process, and
   that cost grows with the corpus.

## 2. The rule: measure first

Decided by the user on 2026-09-17: "don't change anything unless a measurement
proves that it's worth doing it first", and then, for the changes that correct
something false: "fold it in".

**A benchmark is needed when a change is a bet on what the model will do.** The
note of §3b, the printed line and the `name` keyword of §3c, and the meaning
model of §3e each add text the model reads and bet that it acts on it. Each is a
candidate, and a candidate passes two gates before it lands:

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

**A test is enough when a change corrects something false.** These land before
the baseline, each with its test, so that the baseline is the state the
candidates are compared with:

- the seeds of the benchmark (§3a), the instrument every gate needs. Their
  proof is measured already: between Step 5 and Step 6 of the last plan,
  `simulation_stop` and `added_plot_series` went from failed to solved,
  although nothing in Step 6 touched their verbs;
- the pane sentence of the prompt and its guard test (§3d). No problem of the
  eleven asks to close, move or resize a pane, so no baseline would ever show
  the miss, and the first gate would keep a false prompt;
- the plot with no series (§3c), a behavior the user chose, which makes the
  plot answer an empty frame as the table does;
- the test that writes into the real vector folder, and the limits of the
  vector store in `agent.md` (§3f).

## 3. The changes

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
- `_count_turn_misses(assistant, failure)` counts the misses of §3b and §3c in
  each turn. It reads the conversation, which holds every call with its
  arguments and its code, and not the transcript, which is prose for a person.
  A row carries its counts; a second table gives, per miss, the turns that made
  it, how many of them failed, and their problems; a transcript says its misses
  in a line under its outcome. A name pattern that equals a name the stub
  project recorded is exact on purpose and is no miss.
- `test_assistant_problem_table` runs the fake backend on two seeds. It checks
  the `k/n` column, the sums and the folders, and it still needs no server.
  `test_assistant_turn_misses` scripts a backend that makes each miss on one
  seed and none on the other, and checks the counts, the line and the table.
- Cost: `qwen3.8:27b` took 637 s and 733 s for one seed, so a stage of three
  seeds takes about 35 minutes.

### 3b. A short description says how to ask — a candidate

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

**The plot with no series — with a test, before the baseline.** Decided by the
user 2026-09-17: an empty result is shown and not refused. A table maker opens
an empty table, as it does now. `make_result_plot` answers a plot with no
series instead of the error "Nothing matched, so there is nothing to plot." The
test draws the plot, so that the plot projection is proven to take no series.

**The miss:** code that writes a pattern after `=~` with no `*` or `?`, and a
turn whose check says that a table or a plot is empty.

**Two candidates**, tried one at a time, in this order:

1. **The printed line.** A reader keeps the filter it read with: it writes
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
   prints, and a log record goes to the logger the process started with.
2. **`make_result_filter_expression(; name)`**, tried only when the miss
   remains after the first candidate. `name` is a word that the name of a
   statistic contains. `name = "delay"` writes `name =~ "*delay*"`. A `name`
   with `*` or `?` is a pattern and is written as it is. It joins the other
   terms with `AND`, as `config` and `run` do. The examples of the readers and
   of the view makers use it, and the printed line of the first candidate names
   it. `filter` stays for the whole match language.

- Where: `source/ide/ResultVerbs.jl` and `source/legacy/result/ResultReader.jl`
  in omnet.
- Test: `test/ide/ResultVerbsTest.jl` checks the empty plot, then the printed
  line and the keyword when their candidates are tried. The by-hand cases gain
  one: an exact pattern opens an empty table.

### 3d. The prompt names only what exists — with a test, before the baseline

1. **The pane sentence.** It becomes: "To bring a pane forward, call
   `focus_pane!(editor, reference)` with a reference `open_pane!` answered or
   `show_layout` printed. To close, move or resize a pane, edit the program
   `show_layout` prints and send it back with `replace_referenced_value!`."
2. **A guard test.** Every backticked word in `CAMPAIGN_SYSTEM` and
   `IDE_SYSTEM` that has the shape of a Julia name is a declared name, a tool
   name, a declared module or `editor`. The test lists what else it allows: a
   resource URI and a file name. It fails on the prompt as it is now, and
   passes with the new sentence.

**Not done: a second model, and a first line for it.** Decided by the user
2026-09-17: no second model. The first line — "You act by writing Julia" — was
for a model that calls no tool, and without such a model nothing measures what
it is for.

### 3e. A second meaning model — a candidate

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

### 3f. The vector store — with a test, before the baseline

- `test_campaign_assistant` in omnet makes the fake model's store while its
  temporary folder is set, so the build writes where the store says, and
  projectured's `build/meaning/fake_campaign.bin` is deleted. The test checks
  that the store is in its folder and that the real folder holds no fake file.
- `agent.md` says the three limits of §1c: an edited docstring is seen after a
  restart of the process, a model pulled again under its name keeps its old
  vectors, and the file never shrinks. It says how to rebuild: delete the
  model's file, and the next binding computes every vector again.

### 3g. What scale needs, and when

**Now, because a rebuild is cheap only now.** Every change to the text a vector
reads, or to the key it is stored under, rebuilds every vector: seconds at 120
entries, and up to an hour at 10,000. These three change no ranking, so they
land with a test that the ranks do not move:

1. **A vector is keyed by a hash of its text and of the model's digest.** The
   file then holds a hash and a vector, not the text. This also ends the stale
   vectors of a model pulled again under its name, which §1c names as a limit,
   and it ends the hashing of megabytes per query.
2. **An entry's meaning text is computed once**, when the index is built, and
   the entry keeps its hash.
3. **A store keeps its vectors in one dense matrix**, in the order of the
   index, so a description search is one matrix-vector product.

**Later, each on a trigger.** None is worth doing at 120 entries, and the scale
measurement of §3h says when:

| turn it on when | what to do |
| --- | --- |
| a query costs more than about 50 ms, or the corpus passes a few thousand entries | an inverted index over identifier tokens, and BM25F fields over it |
| the first eight hits lose precision on the scale questions | structural signals: the kind asked for, the verb of the name, the window's context |
| one family fills the first hits, as six table makers would | group a family and show one of it |
| a corpus of hundreds of modules | rank modules as answers of their own, and let the model open one |
| above about 100,000 entries | approximate nearest neighbours |

**Not at any size:** a vector database below 100,000 entries, a synonym
dictionary while the word search finds every golden name inside 50 hits, and a
fixed blend of the two rankings. Every fusion measured on the API corpus ranked
worse than the meaning alone, and that must be measured again at scale, not
assumed.

### 3h. The scale corpora and their questions

Each repository gets a corpus of its own and questions of its own, because each
declares its own modules and its own guides. inet is left out for now.

- **projectured**: `ProjecturedKernelExample` holds the list of modules to
  declare, about 25 of them over the kernel, the substrate, the widgets, the
  layouts, the panes and a few domains, and about 25 questions, each an English
  sentence with the name it means. `ProjecturedKernelTest` runs it.
- **omnet**: `OmnetIdeExample` holds the same over the simulator, the results,
  the presentation, the interface, the campaign and the study, with questions
  of its own, and `OmnetIdeTest` runs it.

What the measurement answers, per corpus and per search mode:

- the entries, the modules and the guide sections it declares;
- the time to build the index, the time of a search by words and of a search by
  description, and the memory the vectors take;
- the quality on the questions: how many rank first, recall in the first 5 and
  in the first 10, and the mean reciprocal rank. **Recall in the first ten is
  what matters**, because the model reads eight hits and discards what does not
  fit; a name that is not there at all is the loss.

What the test does, with no timing and no server: it declares the corpus, holds
every question's expected name against the declaration, and runs the
measurement with a backend of the test's own, so that a question can not name a
verb that no longer exists.

## 4. Steps

Work in the worktree `../projectured-julia-format` and in the omnet worktree
`../omnet-julia-answer`. A candidate is committed on a branch of its own, which
is merged into the worktree's branch only when §2 says so. Commit with explicit
paths. Land with `git merge --ff-only`. Cap every Julia process. A stage runs
under the conditions of §5.

### Step 1. What lands with a test (§3a, §3c, §3d, §3f) — done 2026-09-17

- [x] The seed and the meaning model through `_session`, `_run_problem` and
      `measure_assistant_problems`; the `k/n` table; the folders per seed;
      the miss counts; their tests.
- [x] The plot with no series, and its test, which draws it.
- [x] The pane sentence, and the guard test. The guard, run on the old
      sentence, names `focus_pane`, `close_pane`, `move_pane` and
      `resize_pane`.
- [x] The campaign test's store in its own folder, the fake file deleted, and
      the limits in `agent.md`.

### Step 2. The baseline

- [ ] `qwen3.8:27b` on three seeds.
- [ ] The table and the counts of the misses in §7, and the first gate of
      §3b and §3c decided from them.

### Step 3. The trials, one candidate each (§3b, §3c)

In the order of §2, and only for a candidate that passed the first gate:

- [ ] §3b, the note for a one-word description.
- [ ] §3c, the printed line.
- [ ] §3c, the `name` keyword, when the miss remains.

Each: the branch with the change and its tests, the trial stage, the counts,
and the merge or not.

### Step 4. The meaning model (§3e)

- [x] The rank measurement with `mxbai-embed-large`, 2026-09-17. **It fails
      the first gate**: 13 of 20 sentences first, against 15. §7 has the
      table.
- [x] Not run: the trial stage. The default stays `nomic-embed-text`.

### Step 5. The scale corpora and their questions (§3h)

- [ ] The modules, the questions, the measurement and the test, in
      projectured.
- [ ] The same in omnet.

### Step 6. What a rebuild would cost later (§3g)

- [ ] The vector key: the hash of the text and of the model's digest; the file
      without the text.
- [ ] The meaning text computed once, at the index.
- [ ] The dense matrix per store.
- [ ] A test that the ranks of the golden sentences do not move.

### Step 7. The scale measurement (§3h)

- [ ] Both corpora measured, with the user's word, because it reads a clock
      (§5). The numbers go in §7 and set the triggers of §3g.

### Step 8. The text a vector reads (§3g, a candidate)

- [ ] The structured header: the kind, the module, the signature and the split
      words, before the documentation. Measured on the golden sentences and on
      the scale questions of both corpora, which needs no chat model. It lands
      only when more sentences rank first.

### Step 9. Close

- [ ] The tables and the gate results in §7, and this plan to `plan/done/`.

## 5. Rule of running a stage

A stage measures what the model does, not how fast: solved turns, misses,
rounds, calls and tokens. The load of the machine changes none of them. Two
runs of 2026-09-16 on the same seed gave six turns with the same rounds, calls
and tokens, and the chat request to Ollama has no read time limit, so a slow
machine slows a turn and does not fail it. The seconds are reported and are no
gate. Decided by the user 2026-09-17: a stage needs no idle machine and no word
before it. **A measurement that reads a clock is another matter**: the scale
measurement of Step 7 waits for an idle machine and for the user's word. A test
and a rank measurement read no clock and wait for neither.

A stage starts only when both of these hold, and otherwise it does not start
and the report says why:

- **The memory.** `free -g` shows room for the Julia cap (20 GB), the model and
  10 GB more. A full memory crashed the user's machine twice on 2026-09-16.
- **Ollama is free.** `/api/ps` shows no model but the meaning model. A model
  that another session loaded is that session's, and is not unloaded; a second
  client can load or evict a model during the stage, and its requests can
  change the output for the same seed (expected, not measured).

One Julia process at a time, one chat model in it, and that model unloaded when
the stage ends. No loop polls for the conditions.

## 6. Decisions

Made by the user on 2026-09-17:

1. **Seeds:** three per stage.
2. **A second model:** none. §3d says what goes with it.
3. **An empty result:** shown, as an empty table or a plot with no series, and
   not refused. §3c says how the model may learn why it is empty.
4. **`mxbai-embed-large`:** downloaded; §3e stays.
5. **Measure first:** a change that bets on what the model will do lands only
   when a measurement first proves it worth doing. §2 says how.
6. **A test is enough** for a change that corrects something false: the seeds,
   the pane sentence, the empty plot, and the vector store. §2 lists them.
7. **A stage needs no idle machine and no word before it**, only the memory and
   a free Ollama. §5 says why.
8. **The corpus will grow** to thousands of names and hundreds of modules, so
   the engine is built for that: §3g says what to do now and what waits for a
   trigger, and §3h builds a corpus and questions in each repository. inet is
   left out for now.

## 7. Findings

### Step 1, 2026-09-17

The tests that pass: the verbs that read what a run recorded (63), the prompt
names (3), the table of problems with a fake backend (16), the misses of a turn
(8), the campaign assistant pane (18) and the window as a program (32).
Twenty seconds after the campaign test, the real vector folder held only
`ollama_nomic-embed-text.bin`.

### The meaning model, 2026-09-17 — not worth doing

The twenty golden sentences, ranked by description with each model, in one
process, on the code after Step 1:

| sentence | expected | `nomic-embed-text` | `mxbai-embed-large` |
| --- | --- | --- | --- |
| draw how a value changes over time | `make_result_plot` | 26 | **1** |
| the single numbers the runs recorded | `get_simulation_scalar_results` | 5 | 5 |
| write down what the runs taught us | `add_finding!` | 5 | 10 |
| start a new study with a question | `make_study!` | 1 | 2 |
| run the simulations the filter selects | `run_simulations!` | 1 | 2 |
| put the table and the plot side by side | `HorizontalLayout` | 2 | 19 |
| a button that runs the sweep again | `WidgetButton` | 1 | 3 |
| what a package may depend on | `rule/package-rules` | 1 | 2 |
| which test should I run after I change a file | `guide/testing-guide` | 2 | 1 |
| the eleven other sentences | | 1 | 1 |
| **ranked first** | | **15 of 20** | **13 of 20** |

`mxbai-embed-large` ranks the plot verb first, and loses more than it gains:
the row layout falls from second to nineteenth, and five verbs fall out of
first place. The first gate asks for more sentences first, so the default
stays. Its vector file stays in `build/meaning/`, for a later measurement.

One more fact from the same table: the plot verb ranked twentieth on the
morning of 2026-09-17 and twenty-sixth after Step 1. Step 1 added one sentence
to its docstring. A rank past the first ten moves with a sentence, and says
little.
