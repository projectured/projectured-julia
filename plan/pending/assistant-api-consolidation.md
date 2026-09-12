# The assistant's vocabulary: three concerns, one verb each

The surface a language model sees in the OMNeT++ IDE is 40 names in 7 modules.
It grew one verb at a time, and it now says the same thing in three ways and
fuses three separate acts into one verb. This plan makes the acts separate and
lets them combine.

It spans two repositories. The abstraction is `ProjecturedPane`; the verbs that
use it are `OmnetCampaignUi` and `OmnetIde`.

## 1. What the surface is now

Read out of a live `ToolSet`, not out of the source.

| module | names |
| --- | --- |
| `OmnetCampaignUi.CampaignVerbsModule` | 6 |
| `ProjecturedPane.PaneProgramModule` | 10 |
| `ProjecturedPane.PaneModule` | 4 |
| `ProjecturedLayout.LayoutModule` | 5 |
| `ProjecturedKernel.ReferenceModule` | 1 |
| `OmnetIde.ResultVerbsModule` | 4 |
| `DataFrames` | 10 |

`describe` is declared twice over: `DataFrames.describe` gives per-column
statistics, and the generic of §4 says one sentence about a value. The generic
becomes `describe_document` and the `DataFrames` one is declared as
`summarize_frame` (§6), which is also the better name for what it does.

## 2. What is wrong

### 2a. One verb does three things

`show_results` reads the results, makes a table document of them, and opens a
pane for it. `plot_results` reads the results, makes a chart document, and opens
a pane. `run_simulations` makes a batch and opens a pane.

Three acts are fused:

1. **Make a value.** A `DataFrame`, a batch, a selection. No window.
2. **View it.** A frame is not yet a view: a table of it and a chart of it are
   two documents, and which one is a choice.
3. **Place it.** In a new tab, over what a pane already holds, in the
   conversation.

Only the first two are about the domain. The third is the same act for every
document there will ever be.

### 2b. The surface grows as make times place

Each observable thing that arrives needs `show_X`, and then `plot_X`, and then a
variant for each place. A NED graph, a log, a sequence chart, an event trace —
four more things, eight more verbs, and none of them says anything a model could
not have composed.

`run_simulations_in_conversation` is the same growth on the other axis: one more
verb for one more place.

### 2c. Three ways to ask what is on the screen

`list_panes` answers the titles. `show_layout` answers the program.
`get_window_tree` answers the tree. A model must choose, and two of the three
answers cannot be acted on.

### 2d. A pane is named two ways

`focus_pane(editor; pane = "Runner")` names it by title.
`get_referenced_value(editor, @reference(window, root.elements[1].tabs[1]))`
names it by reference.

A reference names any part of any document — a tab, a group, the content of a
tab, a field of a split. A title names a tab and nothing else, and two tabs can
carry the same title. **The reference is the universal name, so it is the only
one the surface should take.**

## 3. The abstraction

One verb per concern, and the value passes between them.

```julia
frame = get_results(editor; config = "Tandem*")   # 1. make  — a DataFrame
chart = make_result_plot(frame)                    # 2. view  — a chart document
where = open_pane!(editor, chart)                  # 3. place — answers a Reference
```

Three rules hold it together.

**A verb answers the value, and a returned value is already shown in the
conversation.** `last_evaluated_value` exists so that the assistant embeds a
returned `Document` as a live card rather than its text repr. So "show it here"
needs no verb at all: it is what returning does. `run_simulations_in_conversation`
is `run_simulations`.

**A verb that places something answers a reference to what it placed.** That
closes the loop: make, place, hold the reference, act on it. Nothing has to be
found again by title.

**Where something goes is said by reference, always.** `open_pane!` makes a new
tab. Everything else — replace what a pane holds, move a pane, resize a split,
close a tab — is `replace_referenced_value!` at the reference the printed
program already gave the model.

## 4. The vocabulary this leaves

### The core — `ProjecturedPane.PaneProgramModule`

| name | signature | change |
| --- | --- | --- |
| `show_layout` | `(editor) -> Text` | none |
| `get_window_tree` | `(editor) -> PaneTree` | none |
| `get_referenced_value` | `(editor, reference::Reference)` | none |
| `replace_referenced_value!` | `(editor, reference::Reference, value)` | none |
| `open_pane!` | `(editor, value; title) -> Reference` | **new** |
| `focus_pane!` | `(editor, reference::Reference) -> Text` | takes a reference, and gains the `!` |
| `describe_document` | `(document) -> String` | renamed from `describe_pane_content` |

`open_pane!` is the one placement a replace cannot say without the model choosing
a group by hand, and the policy it carries — open away from the conversation, so
the answer does not cover the question — is worth a verb of its own.

`describe_document` is both the extension point `show_layout` writes its comments
with and a sentence a model can ask for. One generic, one method per document.

**Dropped:** `close_pane`, `move_pane`, `resize_pane` — each is a replace at a
reference, and the printed program is the text to edit. `pane_api` — a model has
no use for the function that builds its own list.

### The vocabulary a program is written in — unchanged

`PaneTree`, `PaneSplit`, `PaneGroup`, `PaneTab`; `HorizontalLayout`,
`VerticalLayout`, `GridLayout`, `StackLayout`, `FlowLayout`; `@reference`.

### The runner — `OmnetCampaignUi.CampaignVerbsModule`

| name | signature | change |
| --- | --- | --- |
| `select_simulations!` | `(editor; config, exclude, ini_file, run, mode, jobs) -> SimulationFilter` | **new** |
| `run_simulations!` | `(selection::SimulationFilter) -> SimulationBatchDocument` | answers the batch, opens no pane |
| `stop_simulations!` | `(batch::SimulationBatchDocument) -> Text` | takes the batch, not a title |

`select_simulations!` is the selection as a value. It writes the keywords into the
runner's form, so a person sees what was chosen, and refuses a selection that
cannot run — which is what `_chosen` already does inside every runner verb.

**Dropped:** `run_simulations_in_conversation` — returning is showing here.
`count_simulations` — `describe_document(select_simulations!(…))` says the same sentence
about the same value. `describe_simulations` — `describe_document(batch)`.
`list_panes` — `show_layout`.

### The results — `OmnetIde.ResultVerbsModule`

| name | signature | change |
| --- | --- | --- |
| `get_results` | `(editor; results, filter, kind, config, run) -> DataFrame` | none |
| `make_result_table` | `(frame::DataFrame; title, limit) -> SimulationResultFrame` | **new** |
| `make_result_plot` | `(frame::DataFrame...; title) -> SimulationPlotDocument` | **new** |

**Dropped:** `show_results` = `open_pane!(editor, make_result_table(get_results(…)))`.
`plot_results` = `open_pane!(editor, make_result_plot(get_results(…)))`. `result_api`
— as with `pane_api`.

`make_result_plot` takes several frames, which is what `plot_results(; into = …)` was
for. Adding to a plot that is already open becomes what it always was — a read,
a combine and a write:

```julia
open   = get_referenced_value(editor, chart)
replace_referenced_value!(editor, chart,
                          make_result_plot(open, get_results(editor; config = "Fifo")))
```

### The count

40 names to 33, and the ten `DataFrames` names are 10 of those 33 either way.
The size is not the point. **The growth law is:** a new observable thing adds one
name, its view constructor, instead of two verbs and then a variant per place.

## 5. What a session looks like

Today, to run a set and plot what it recorded:

```julia
title = run_simulations(editor; config = "Tandem*")
# … wait, then …
plot_results(editor; config = "Tandem*", kind = "vectors")
```

After:

```julia
batch = run_simulations!(select_simulations!(editor; config = "Tandem*"))
open_pane!(editor, batch)                      # a pane, if a pane is wanted
describe_document(batch)                       # how far it is
open_pane!(editor,
           make_result_plot(get_results(editor; config = "Tandem*", kind = "vectors")))
```

Longer to write, and every piece of it is reusable. The model that wants the plot
beside the runner instead of in a new tab writes the last line as a replace at a
reference, with nothing new to learn.

## 6. Open questions

- ~~**Is a `PaneSplit`'s `weights` reachable by a reference step?**~~
  **Answered 2026-09-13: yes, and the write works.** Measured:
  `@reference(window, root.weights)` is fully typed, reads the `CellVector`, and
  `replace_referenced_value!(editor, reference, [0.3, 0.7])` lands. `weights` is
  not one of the fields `_refuse_bad_kind` guards, so nothing refuses it.
  `resize_pane` drops with no loss.
- **Does `focus` belong to the reference machine at all?** Focus is the
  selection, not the tree, so it is not a replace. `focus_pane` survives for
  that reason. Whether it should be `select!(editor, reference)` — the kernel's
  own word — is a naming question for the review.
- ~~**`describe` is a very common word.**~~ **Answered 2026-09-13: rename the
  `DataFrames` one.** Julia's `using M: name as alias` lowers to
  `Expr(:as, Expr(:., :name), :alias)` inside the `:` expression the scratch
  module already builds, so the rename is a declaration, not a wrapper. It needs
  `ApiEntry` to carry `name => alias` pairs beside plain names, and one branch in
  `_scratch_module`. `DataFrames.describe` becomes `summarize_frame`, which also
  says what it does — it is per-column statistics, not a sentence.
- **Does `open_pane!` need a `title`?** A document that carries its own title
  makes the keyword redundant. Check which documents do.
- **`get_window_tree` is only there so `@reference(window, …)` has a `window`.**
  If `@reference(editor, …)` accepted the editor, the name would go and the
  surface would lose one more.

## 7. Every name obeys the naming rules

[naming-rules.md](../../documentation/rule/naming-rules.md) governs this surface
as it governs every other. **Every function name starts with a verb**, a factory
is `make_*`, a getter is `get_*`, and a function that mutates its subject ends
with `!`. Four of the names in the first draft of this plan broke that.

| draft | correct | the rule |
| --- | --- | --- |
| `result_table` | `make_result_table` | not a verb; it is a factory |
| `result_plot` | `make_result_plot` | not a verb; it is a factory |
| `describe` | `describe_document` | "verb + the unit that flows in" |
| `open_pane` | `open_pane!` | it splices a tab into the tree |
| `focus_pane` | `focus_pane!` | it moves the selection |
| `select_simulations` | `select_simulations!` | it writes the runner's form |
| `run_simulations` | `run_simulations!` | it starts processes |
| `stop_simulations` | `stop_simulations!` | it interrupts them |

The bangs are not this plan's invention.
[naming-rule-violations.md](naming-rule-violations.md) already records the same
finding for the four verbs that exist today: *"`focus_pane`, `close_pane`,
`move_pane`, `resize_pane` — add the `!`. Each one calls `_apply(editor, …)`,
which mutates its `editor` argument."* This plan drops three of those four and
fixes the survivor.

**The `!` costs the model nothing and buys it something.** A model reads
`run_simulations!` and knows the call changes the world; it reads `get_results`
and knows the call does not. That is the same information the three-concern
split is trying to teach, said again in the one line a search hit shows (§8a).

## 8. How a model learns to combine

A verb that is removed takes its knowledge with it. `show_results` said "read,
make a table, open a pane" in its name; three verbs say it only if the model can
see how they join. This is what makes that visible, and none of it is prose.

### 8a. The signature line is the contract, because it is the only line a hit shows

Measured in `Documentation.jl`. A search hit is **found by** two paragraphs — the
signature line and the sentence under it — and **shown as** `_first_paragraph`,
which is the signature line alone. A model calls a verb off that line without
reading more.

So the types in the signature are the combination documentation:

```
get_results(editor; …)                 -> DataFrame
make_result_table(frame::DataFrame; …) -> SimulationResultFrame
make_result_plot(frame::DataFrame…; …) -> SimulationPlotDocument
open_pane!(editor, value; …)           -> Reference
focus_pane!(editor, reference::Reference)
```

Read down that column and the chain is forced: `get_results` answers what
`make_result_table` takes, which answers what `open_pane!` takes, which answers
what `focus_pane!` takes. Nothing has to be said in words. **Every verb must spell its
return type and the type of the argument that links it to its neighbour**, and
that is a rule this plan holds itself to, not a wish.

### 8b. The prompt carries the shape, not the list

`IDE_SYSTEM` names the modules today. A list of module names teaches nothing
about joining. It should carry the three concerns in one sentence and one worked
session of four lines — the §5 example. That is always in context, and it is what
a model pattern-matches on before it searches for anything.

### 8c. A model edits an example; it does not compose from a description

This is measured in this repository, not assumed. `show_layout` hands back a
runnable program, and the layout work was proven with a local model that read it,
edited two lines and sent it back. The same note records the opposite: handed a
`String` instead of a `Text`, the same model spent its whole five-round budget
and acted on nothing.

The lesson is that **the worked program is the teaching device**, and it is the
one we already have. `show_layout` is the map of the window; §8b makes the prompt
the map of the verbs.

### 8d. A retired name should teach, not fail blankly

`show_results(...)` after this plan is `UndefVarError`, which tells a model it was
wrong and not what to write. The scratch module can bind each retired name to a
function that throws the replacement:

```
show_results is retired. Write:
    open_pane!(editor, make_result_table(get_results(editor; config = "Tandem*")))
```

These bindings are not declared, so they cost nothing in the search and nothing
in the prompt. They can go once a recording shows nobody reaches for them.

### 8e. The claim is testable, so test it

Whether three verbs cost more rounds than one is a measurement, not an opinion.
Stage 9 runs the same three tasks against the same local model on both surfaces
and counts the rounds each needs. If the new surface costs more, the answer is
more worked examples in §8b, not more verbs.

### 8f. The guard: what a local model can actually reach

§8e says to count rounds. That is a comparison, run once. This is the standing
guard that keeps the surface reachable, and it lives in
`omnet-julia/test/ide/AssistantSessionTest.jl` as `test_assistant_session()`.

**It drives a real model.** A surface is reachable or it is not, and only a model
can say which. The existing `test/ollama/OllamaTest.jl` drives the adapter over
recorded lines — it tests the wire format and says nothing about whether a model
can use the API.

**It asserts the outcome, never the code.** A model writes different Julia every
run. What must hold is what the window and the documents look like afterwards.
A test that matched the source text would fail on a correct answer.

#### The cases

Each is one sentence a person would say, one turn, and one outcome.

| # | what is said | what must be true afterwards |
| --- | --- | --- |
| 1 | "How many simulations would the Tandem configuration run?" | the reply names the count; no batch started |
| 2 | "Run the Tandem simulations." | a `SimulationBatchDocument` exists and its status is not `:idle` |
| 3 | "Show me the delay scalars." | a pane holds a `SimulationResultFrame`, `kind === :scalars`, with the delay rows |
| 4 | "Plot the vectors." | a pane holds a `SimulationPlotDocument` with one series or more |
| 5 | "Add the Fifo delays to that plot." | the same plot document now holds one series more |
| 6 | "Put the plot beside the runner." | the tree holds a `PaneSplit`, and the plot and the runner are in different groups |
| 7 | "Stop the runs." | the batch's status is stopping or stopped |
| 8 | "Which columns does that result frame have?" | the reply names a column, and no pane opened |

Case 5 is the one that used to be `plot_results(; into = …)` and is now a read, a
combine and a write — the composition this plan claims a model can do. Case 6 is
the layout half, already proven once by hand. Case 8 checks that the ten
`DataFrames` names are reachable and that a question is answered without acting.

#### How it runs

- **The fixture is the one that exists.** `_result_editor()` in
  `test/ide/ResultVerbsTest.jl` builds a headless editor on a temporary project
  with result files written by hand. No OMNeT++, no display, no simulation.
  Cases 2 and 7 need a runnable stub, which `CampaignPrecompile.jl`'s shell
  script already is.
- **Skip loudly when there is no server**, the way
  `test_db_catalog(; skip_if_no_db = true)` does: probe once, `@info` the reason
  and return. A capability guard that fails the suite on a developer machine with
  no Ollama gets deleted; one that passes in silence is worthless. So it says
  which it did, every time.
- **`test_assistant_session(; model = "qwen3.8:27b", skip_if_no_model = true)`.**
  The model is an argument, so the same guard runs against a bigger one.
- **Each case is bounded and its rounds recorded.** The agent default is
  `max_rounds = 5`. The test writes rounds-used per case into the testset's own
  output, which is the data §8e compares.
- **A case that fails is reported as what the model wrote.** The assertion
  message carries the last code the model ran, or the surface cannot be repaired
  from a red line saying `false`.

#### What it guards against

A verb renamed, a docstring whose signature line stops naming its return type, a
declaration dropped from the list, a prompt that stops teaching the shape — each
breaks a case here and nothing else in the suite. That is the point: the rest of
the suite tests that the verbs work, and this tests that they can be found and
combined.

### 8g. The baseline, measured 2026-09-13

`test_assistant_session()` against **today's** surface, `qwen3.8:27b`, eight
cases. **Six reached, two not.** 11 assertions passed, 2 cases errored.

| case | tool calls | reached |
| --- | ---: | --- |
| count | 5 | yes — it found `count_simulations` |
| run | 4 | yes |
| table | 6 | yes |
| **plot** | 5 | **no — nothing was plotted** |
| **add_series** | 9 | **no — the plot still held one series** |
| layout | 2 | yes — the cheapest case of the eight |
| stop | 3 | yes |
| columns | 5 | yes |

The two that fail are the two this plan is about, and the transcript says why.

**The model found `plot_results` and could not call it.** It searched the name,
read the docstring, and then spent its last three rounds hunting for one thing:

> *"The kind is `vector`/`scalar`/`histogram`. For delay vectors, I want
> `kind="vector"`."*

The value is `"vectors"`. `RESULT_FRAME_KINDS` holds the set and the signature
line does not, so a model that has done everything right guesses and fails. It
then searched the guides, got `CellVector` and `@document`, and ran out of
rounds.

**This sharpens §8a.** "Spell the return type and the linking argument type" is
not enough. **A keyword whose values are a closed set must show that set in the
signature line**, because the signature line is the only line a search hit shows:

    make_result_plot(frame::DataFrame...; title) -> SimulationPlotDocument
    get_results(editor; kind = "scalars"|"vectors"|"statistics"|"histograms", …) -> DataFrame

A model reading the second cannot make the mistake the first surface invited.
The consolidation helps here for a second reason: `kind` belongs to
`get_results`, which *makes* the frame, and not to the verb that draws it — so
there is one place to get it right rather than three.

**`layout` was the cheapest case at two calls**, which is the reference program
working exactly as it was built to: the model read what `show_layout` printed and
edited it. That is the evidence behind §8c, now measured on a case nobody wrote
by hand.

## 9. Stages

Each stage is a commit, and each leaves the assistant working.

- [ ] **1. The guard, first.** Write `test_assistant_session()` with the eight
  cases of §8f **against today's surface**, before a single name changes. Then it
  records what the old surface reaches, every later stage is checked against it,
  and a case that was already out of reach is not mistaken for a regression this
  plan caused.
- [ ] **2. `describe_document`.** Rename `describe_pane_content`, keep the
  methods, and declare `DataFrames.describe` as `summarize_frame` (§6). Needs
  `ApiEntry` to carry `name => alias` pairs and one branch in `_scratch_module`.
  `ProjecturedPane`, then the three methods in `OmnetCampaignUi` and `OmnetIde`.
- [ ] **3. `open_pane!`.** Add it to `PaneProgramModule`, answering a
  `Reference`. Then drop `close_pane`, `move_pane` and `resize_pane` from the
  declared list — §6 proved a `weights` write by reference, so `resize_pane`
  costs nothing to lose.
- [ ] **4. `focus_pane!` by reference.** Drop the title lookup, add the `!`.
- [ ] **5. The runner.** `select_simulations!`, `run_simulations!` answering the
  batch, `stop_simulations!` on the batch. Drop the other three.
- [ ] **6. The results.** `make_result_table` and `make_result_plot`. Drop
  `show_results` and `plot_results`.
- [ ] **7. The declared list.** Drop `pane_api` and `result_api` from what is
  declared — they stay as functions, they stop being vocabulary.
- [ ] **8. The signature lines.** Give every verb in §4 a signature that spells
  its return type and its linking argument type, per §8a. Retire the dropped
  names with the errors of §8d.
- [ ] **9. The prompt.** `CAMPAIGN_SYSTEM` and `IDE_SYSTEM` name the modules and
  a verb each. Rewrite them around the three concerns and one worked session
  (§8b), and re-run the test that asserts the replaced sentence fires.
- [ ] **10. Prove it.** Re-run the guard and compare, case by case, the rounds
  each surface needed (§8e). A surface a model cannot compose is not
  consolidated, whatever its shape.
