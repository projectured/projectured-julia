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

**The order changed on 2026-09-18, by the user's question: the engine before
the chat model.** A stage of the chat model costs 35 minutes and answers with
noise; a measurement of the ranks costs seconds and answers the same twice. So
every change that ranking decides is measured on the questions of §3h, and the
chat model is spent once at the end, as the check that a better rank is a
better turn. That check is needed: `WidgetCard` stood second and the model
still failed, so a rank is a proxy and not the goal.

### Done

- **Step A, 2026-09-17.** What lands with a test: the seeds, the miss counts,
  the plot with no series, the pane sentence and its guard, the campaign
  test's store, and the limits in `agent.md`.
- **Step B, 2026-09-17.** The second meaning model, `mxbai-embed-large`: it
  fails its first gate, 13 of 20 sentences first against 15, so the default
  stays.
- **Step C, 2026-09-18.** The scale corpora and their questions, in each
  repository, and the declaration that refused a name two modules re-export.

### Step 1. The scale measurement (§3h) — the ranks taken 2026-09-18

- [x] Both corpora measured for their ranks, which read no clock. §7 has the
      tables. They are the baseline of every step below.
- [ ] The same run on an idle machine, with the user's word, for the times.
      The times of the rank run say that a search costs about 5 ms by words and
      about 14 ms by description at 2,355 entries, so no trigger of §3g rests
      on them yet.

### Step 2. What a rebuild would cost later (§3g)

- [ ] The vector key: the hash of the text and of the model's digest; the file
      without the text.
- [ ] The meaning text computed once, at the index.
- [ ] The dense matrix per store.
- [ ] A test that the ranks of the questions do not move, and the measurement
      again, which must show the same ranks and a shorter search.

### Step 3. The documentation first, then the ranking (§3g)

**The order was wrong, and the user said so on 2026-09-18.** The experiments
below ranked text that was never written for a model: of the 1,389 entries of
projectured's corpus, only 730 have a first sentence, and the names the
questions expect were not written to the docstring standard of the last plan. A
ranking cannot read what the text does not say, so an experiment measured on
that text answers about the text and not about the ranking.

**The documentation is written for a reader, not for the questions.** The user
said so in the same breath: "we should not update the documentation to
magically fit the test corpus, but at least make it good enough in the general
sense". So a docstring is written from the code and from what the thing is for,
the questions are not read while writing it, and no sentence of a question may
appear in a docstring. A fixture that the text was fitted to measures nothing.

- [x] **The documentation of the kernel's own names**, 2026-09-18: twenty-two
      docstrings over the cells, the projection's two halves, the operation,
      the selection, the reference, the map, the document and the saved
      document, and two of omnet's documents. Six of the files were sealed,
      and the user allowed them.
- [x] **Measured again**: by description 11 questions first, 20 in five and 21
      in ten of 26, against 10, 19 and 20. §7 has it.
- [x] **The three experiments again on the new text**, and none of them lands.
      §7 has the numbers.
- [x] The collections and the drawn shapes, 2026-09-18: fourteen more.
- [x] The colour, the font and the styled text; every domain's root, from the
      macro that writes it, which gave twenty domains a sentence at once.
- [x] **Three kinds of name left the index**, because nobody writes them: the
      alias per storage kind, the struct of the native layout (`MFoo`, `IFoo`),
      and any name that opens with an underscore. The corpus fell from 2,355
      entries to 1,224, and the share that carries a sentence rose from 31 per
      cent to 60.
- [ ] The rest of the layers a reader needs, module by module. The measurement
      now says how many names carry a sentence and how many a paragraph that
      says what they are for, because **the questions can only see the names
      they ask for**: documenting a collection or a shape moved the answers by
      one either way, which is noise, while the coverage is the number that
      shows the work. At the start of it: 717 of 1,364 names carry a sentence,
      78 a use paragraph.

### The ranking, one piece at a time (§3g)

Each piece is measured on the questions of both corpora and on the golden
sentences, which needs no chat model. A piece lands only when more questions
rank first or in the first ten, and none of the three corpora is worse. Each in
its own commit, in this order:

- [x] **A generated schema variant is not a hit**, done 2026-09-18. The rule
      reads the prefixes the macro writes, `AC`, `RC`, `IC`, `MC`, `DC` and `A`,
      and drops the name when the rest of it is a type of the same module. The
      corpora fell from 2,355 to 1,389 entries and from 1,612 to 904. **The
      ranks did not move**, which the user's rule asked to be measured before
      the work was believed: a name with no words of its own answers no query.
      What it buys is the third of the vectors, of the index and of every
      listing of names. §7 has the numbers.
- [x] **Identifier tokens and the rarity of a word**, done 2026-09-18. A term
      that is a whole word of the name scores above one that falls inside it,
      and the prose score became BM25: a word few entries hold is worth more
      than one most of them hold. The words alone did nothing; the rarity did
      the work. §7 has the numbers.
- [x] **The text a vector reads:** tried twice, 2026-09-18, and **not kept**.
      §7 says what each variant answered.
- [x] **The words fused with the meaning**, re-measured at scale as §3g asked,
      and **not kept**: it is worse at 1,389 names as it was at 88. §7 has the
      numbers.
- [ ] **Fields and their weights**, a BM25F score over an inverted index, if a
      later measurement says a search costs more than about 50 ms.
- [x] **An entry's documentation cut into chunks**, tried at 600 and at 1,000
      characters, 2026-09-18, and **not kept**. §7 has the numbers.
- [x] **An alias carries the documentation of what it stands for**, tried
      2026-09-18 and **not kept**: it moved nothing.
- [ ] **Structural signals:** the kind a question asks for, a thing against an
      action, and the module the window is working in. Held: the failures that
      are left are not of that shape. §7 says what they are.
- [ ] **A family shown once**, if one family fills the first hits.

### Step 4. The baseline of the chat model — done 2026-09-18

- [x] `qwen3.8:27b` on three seeds, with the engine as it stands: **29 of 33
      turns**, 9, 10 and 10 by seed.
- [x] The counts of the misses: **every one is zero**, over 33 turns. §7 has
      the table.

### Step 5. The trials that are left (§3b, §3c) — none, 2026-09-18

The first gate of §2 asks that a miss occur in at least two turns of the
baseline and fail at least one. **Not one of the three misses occurred at all**
in 33 turns, so no candidate goes on:

- [x] §3b, the note for a one-word description: the model wrote no one-word
      description in 33 turns.
- [x] §3c, the printed line of an empty result: no turn opened an empty table
      or an empty plot.
- [x] §3c, the `name` keyword: no turn wrote a name pattern without a wildcard.

### Step 6. Close

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

**A measurement runs in a lane of its own**, decided by the user 2026-09-18:
cores 28, 30 and 31, which are neither the build lane, 16 to 23, nor the suite
lane, 24 to 27, nor the two isolated cores, 13 and 29. It runs at the ordinary
priority, because a measurement that is pushed aside measures the pushing. The
lane is what makes a time worth reading while the machine has other work, and
every time is reported with the load it was taken under.

## 6. Decisions

Made by the user on 2026-09-17:

1. **Seeds:** three per stage.
2. **A second model:** none. §3d says what goes with it.
3. **An empty result:** shown, as an empty table or a plot with no series, and
   not refused. §3c says how the model may learn why it is empty.
4. **`mxbai-embed-large`:** downloaded; §3e stays.
5. **Measure first:** a change that bets on what the model will do lands only
   when a measurement first proves it worth doing. §2 says how. A change that
   ranking decides is measured on the questions, not on the chat model, and the
   chat model checks the result once at the end (§4).
6. **A test is enough** for a change that corrects something false: the seeds,
   the pane sentence, the empty plot, and the vector store. §2 lists them.
7. **A stage needs no idle machine and no word before it**, only the memory and
   a free Ollama. §5 says why.
8. **The corpus will grow** to thousands of names and hundreds of modules, so
   the engine is built for that: §3g says what to do now and what waits for a
   trigger, and §3h builds a corpus and questions in each repository. inet is
   left out for now.

## 7. Findings

### The chat model over the new documentation, 2026-09-18

The same eleven problems, the same three seeds, after the documentation sweep
and the three kinds of name that left the index:

| stage | solved | rounds | tokens in |
| --- | --- | --- | --- |
| before the sweep | 29 of 33 | 151 | 900,330 |
| after it | 29 of 33 | 150 | 891,609 |

The same problems fail, and most rows are identical to the token. **The sweep
did not reach these turns, and that was to be expected**: this window declares
about 150 names, and the last plan wrote their documentation already. What the
sweep documented is the kernel's own surface, which this window does not
declare. It is worth what a reader of the code gets from it, and it shows in
the corpora of §3h, not here.

The corpora after everything, for the record:

| corpus | entries | with a sentence | names first / in five / in ten, by description |
| --- | --- | --- | --- |
| projectured, 26 questions | 1,224 | 721 of 1,199 | 10 / 20 / 21 |
| omnet, 34 questions | 786 | 539 of 728 | 8 / 15 / 19 |

Omnet's corpus fell from 1,612 entries to 786 and its share of documented names
rose from 44 per cent to 74. Its questions by words rose from 3 first to 6, and
15 in the first ten against 12.

### Step 4, the chat model on three seeds, 2026-09-18

`qwen3.8:27b`, the eleven problems, three seeds, with the engine after Step 3:

| solved | rounds | calls | tokens in / out | seconds |
| --- | --- | --- | --- | --- |
| 29 of 33 turns; 9, 10 and 10 by seed | 151 | 145 | 900,330 / 28,409 | 2,242 |

The four that failed: `pane_arrangement` twice, `simulation_run` once and
`card_around_table` once. `table_beside_plot`, which failed at every earlier
stage, is solved on all three seeds, and so is `simulation_stop`.

**Every miss the plan was built around is gone.** Over 33 turns the model wrote
no description of one word, no name pattern without a wildcard, and opened no
empty table or plot. The three candidates of §3b and §3c therefore fail their
first gate and are not done. What removed them is not provable from this one
stage; the prompt that names only what exists, the plot that answers an empty
frame, and the word score are all of Step 1 and Step 3.

**A stage is worth three of an earlier one.** The earlier stages ran one seed
and moved by one or two problems; this one shows a problem solved twice of
three and tells a real change from noise.

### Step 1, the ranks at scale, 2026-09-18

| corpus | entries | guide sections | names first / in five / in ten, by words | by description |
| --- | --- | --- | --- | --- |
| projectured, 26 questions | 2,355 | 1,153 | 4 / 7 / 7 | 10 / 19 / 20 |
| omnet, 34 questions | 1,612 | 1,349 | 3 / 10 / 12 | 8 / 15 / 19 |

The guides, 6 questions each: projectured 2 first and 5 in ten by words, 3 and
5 by description; omnet 1 and 5 by words, 3 and 5 by description. The mean
reciprocal rank of the names is 0.21 and 0.19 by words, 0.52 and 0.35 by
description.

**Recall is the loss, not the order.** Six of projectured's 26 names and 15 of
omnet's 34 are not in the first ten by description, and some are not in the
first fifty by either mode: `Cell`, `set_cell_function!` and `parse_pred_text`
in projectured; `get_simulation_histogram_results`,
`make_result_filter_expression`, `get_batch_document_status`,
`build_batch_document_counts`, `open_simulation_pane!`, `SimulationFilter` and
`SimulationResultFrame` in omnet. At a hundred names every golden verb was
found inside fifty hits. At two thousand, a third of them are gone.

**Speed is not the problem yet.** On a machine that was not idle, a search took
about 5 ms by words and 14 ms by description, and the index built in 0.3 s. The
vectors of a corpus take about 13 MB. So the inverted index and BM25F wait, as
§3g says, and the ranking comes first.

**A third of the corpus is noise.** 790 of projectured's 2,355 entries are
generated schema variants of another type. Step 3 takes them out first.

### Step 3, the ranking, 2026-09-18

**The word score.** A whole word of a name now scores above a piece of one, and
a rare word in the prose above a common one. Measured on the three corpora, by
words, as first / in five / in ten:

| corpus | before | after |
| --- | --- | --- |
| projectured, 26 questions | 4 / 7 / 7 | 6 / 7 / 8 |
| omnet, 34 questions | 3 / 11 / 13 | 6 / 14 / 14 |
| the omnet window, 12 verbs | 5 first | 6 first |

The mean reciprocal rank rose from 0.21 to 0.25 and from 0.19 to 0.28. The
words alone changed nothing; the rarity did all of it. What it repairs is
plain in one question: "make a field of a document computed" never reached
`set_cell_function!`, because "document" stands in hundreds of entries and
counted as loudly as "computed", which stands in a few.

**The text a vector reads: two variants, neither kept.** A header of the kind,
the name, the words of the name and the signature, before the documentation,
answered 11 questions first instead of 10, and only 18 in the first ten instead
of 20. A lighter header, the name and its words, answered 10 / 18 / 20 against
10 / 19 / 20. Recall in the first ten is what matters, so the text stays as it
was: the qualified name and the whole documentation.

**The words fused with the meaning: worse, again.** §3g said this must be
measured again at scale rather than assumed. With the word ranking counted once
beside the meaning, the description answered 8 first, 13 in five and 15 in ten,
against 10, 19 and 20 for the meaning alone. The rule of 2026-09-16 stands at
1,389 names: on this corpus the meaning decides and the words only stand in for
it.

**An entry's documentation in chunks: not kept.** A long docstring gets one
vector, and one vector over 2,000 characters answers a question about one
paragraph of it weakly. Cut at 600 characters, with an entry scoring as its
best chunk, `declare_api!` entered the list at 14 for "say which names a model
may write", which its own first sentence says; but the corpus answered 9
questions first instead of 10, the same 19 in five and 20 in ten, and the mean
reciprocal rank fell from 0.52 to 0.49. At 1,000 characters it was 9 / 19 / 20
and 0.50. Fewer first and no more in ten is not worth the vectors, so the text
stays whole.

**An alias that carries the documentation of what it stands for: not kept.**
`Cell` documents the alias, and `ReactiveCell` documents the thing. With both,
the corpus answered exactly as before, 10 / 19 / 20, and `Cell` was still not
among the first fifty for "a value that is computed again when what it reads
changes".

**What is left is not the engine's to fix.** The names that no mode finds are
`Cell`, whose documentation is about being an alias; `parse_pred_text`, whose
whole documentation is two sentences; and `set_cell_function!`, whose
documentation never says "document" or "field". A ranking cannot read what the
text does not say. The next lever is the text, which is the docstring standard
of the last plan, applied wider.

**Every result of this section is about the old text.** The experiments should
have run after the documentation was written for a model, and Step 3 runs them
again. The one that landed, the rarity of a word, stays for now because what it
repairs — a common word counting as loudly as a rare one — is a property of the
scoring and not of the text; it is measured again all the same.

### Step 3, the documentation and the experiments again, 2026-09-18

Twenty-two docstrings were written to the standard, from the code and never
from the questions. The corpus answered better by description at once:

| projectured, 26 questions | first | in five | in ten | mean reciprocal rank |
| --- | --- | --- | --- | --- |
| before the documentation | 10 | 19 | 20 | 0.52 |
| after it | 11 | 20 | 21 | 0.55 |

By words it moved the other way by one, 6 first to 5, because more prose
changes what a rare word is. The three experiments, run again on the new text:

| experiment | first | in five | in ten | mean reciprocal rank |
| --- | --- | --- | --- | --- |
| the text as it is | 11 | 20 | 21 | 0.55 |
| a header of the kind, the name, its words and the signature | 11 | 18 | 19 | 0.53 |
| the documentation in chunks of 600, best chunk wins | 11 | 20 | 21 | 0.56 |
| the words fused with the meaning | 7 | 14 | 16 | 0.40 |

So the answers stand where they stood on the thin text: the header is worse,
the fusion is much worse, and the chunks are the same for more vectors. **The
text is the lever, and the ranking is not.** Twenty-two docstrings bought what
five ranking experiments could not.

**The sweep stopped where the prose would be for machinery.** What is left
undocumented is the projection that draws each widget, about 110 names, and
some 250 colour constants whose names say what they are. Writing paragraphs for
those buys a model nothing.

**A fixture sees only what it asks.** The questions name 26 things of 1,364.
Documentation of anything else cannot raise them, and may cost a place by
making another name findable. So the questions gate a change of the ranking,
and the coverage of the documentation is watched instead, as the measurement
now prints it.

**A caution on comparing.** The guides of projectured changed under these runs,
because the user is editing them. A guide number is only comparable within one
day.

### Step 3, the generated variants, 2026-09-18

The corpora, before and after the rule, and what the questions answered:

| corpus | entries before | after | names first / in five / in ten, by words | by description |
| --- | --- | --- | --- | --- |
| projectured, 26 questions | 2,355 | 1,389 | 4 / 7 / 7, unchanged | 10 / 19 / 20, unchanged |
| omnet, 34 questions | 1,612 | 904 | 3 / 11 / 13, from 3 / 10 / 12 | 8 / 15 / 19, unchanged |

**The noise cost work, not ranks.** A variant has no words of its own, so it
never stood where a question's answer should have been. It costs a vector, a
line of a listing of names, and a place in the index; a third of each is now
saved. The measure-first rule earned its keep here: the reason written in the
plan for doing this — that the variants crowd out the name a person means — was
wrong, and the measurement said so.

The times, taken in the measurement lane with a load of about 3: a search by
words about 4 ms, by description about 14 ms, the index built in 0.2 s, and the
vectors of a corpus take 13 MB. Nothing here triggers the inverted index.

### Step 5, 2026-09-18

**A wide declaration was refused, and the refusal was wrong.** `declare_api!`
refused any name that two modules gave. Of the 25 modules of projectured's
scale corpus, twelve names are given twice, and **every one of them is the same
function**, re-exported by a module that uses another. The refusal now compares
the bindings, and the index keeps one hit per binding. Without this, no corpus
of more than a few modules can be declared at all.

The corpora, as the tests hold them:

| corpus | modules | entries | questions |
| --- | --- | --- | --- |
| projectured | 25 | about 2,400 | 26 of names, 6 of guides |
| omnet | 54 of its own and 3 the window draws with | about 1,600 | 34 of names, 6 of guides |

The measurement prints what the corpus holds, what the index and the vectors
took to build, what a search costs, and for each mode how many questions rank
first, how many are in the first five and in the first ten, and the mean
reciprocal rank. The tests run it offline with a bag-of-words model, and hold
every question's expected name to the declaration. The numbers wait for Step 7.

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
