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
view  = result_plot(frame)                         # 2. view  — a chart document
where = open_pane(editor, view)                    # 3. place — answers a Reference
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

**Where something goes is said by reference, always.** `open_pane` makes a new
tab. Everything else — replace what a pane holds, move a pane, resize a split,
close a tab — is `replace_referenced_value!` at the reference the printed
program already gave the model.

## 4. The vocabulary this leaves

### The core — `ProjecturedPane.PaneProgramModule`

| name | signature | change |
| --- | --- | --- |
| `show_layout` | `(editor) -> Text` | none |
| `get_window_tree` | `(editor) -> PaneTree` | none |
| `get_referenced_value` | `(editor, reference)` | none |
| `replace_referenced_value!` | `(editor, reference, value)` | none |
| `open_pane` | `(editor, value; title) -> Reference` | **new** |
| `focus_pane` | `(editor, reference) -> Text` | takes a reference |
| `describe` | `(value) -> String` | renamed from `describe_pane_content` |

`open_pane` is the one placement a replace cannot say without the model choosing
a group by hand, and the policy it carries — open away from the conversation, so
the answer does not cover the question — is worth a verb of its own.

`describe` is both the extension point `show_layout` writes its comments with and
a sentence a model can ask for. One generic, one method per document.

**Dropped:** `close_pane`, `move_pane`, `resize_pane` — each is a replace at a
reference, and the printed program is the text to edit. `pane_api` — a model has
no use for the function that builds its own list.

### The vocabulary a program is written in — unchanged

`PaneTree`, `PaneSplit`, `PaneGroup`, `PaneTab`; `HorizontalLayout`,
`VerticalLayout`, `GridLayout`, `StackLayout`, `FlowLayout`; `@reference`.

### The runner — `OmnetCampaignUi.CampaignVerbsModule`

| name | signature | change |
| --- | --- | --- |
| `select_simulations` | `(editor; config, exclude, ini_file, run, mode, jobs) -> SimulationFilter` | **new** |
| `run_simulations` | `(selection) -> SimulationBatchDocument` | answers the batch, opens no pane |
| `stop_simulations` | `(batch) -> Text` | takes the batch, not a title |

`select_simulations` is the selection as a value. It writes the keywords into the
runner's form, so a person sees what was chosen, and refuses a selection that
cannot run — which is what `_chosen` already does inside every runner verb.

**Dropped:** `run_simulations_in_conversation` — returning is showing here.
`count_simulations` — `describe(select_simulations(…))` says the same sentence
about the same value. `describe_simulations` — `describe(batch)`.
`list_panes` — `show_layout`.

### The results — `OmnetIde.ResultVerbsModule`

| name | signature | change |
| --- | --- | --- |
| `get_results` | `(editor; results, filter, kind, config, run) -> DataFrame` | none |
| `result_table` | `(frame; title, limit) -> SimulationResultFrame` | **new** |
| `result_plot` | `(frame...; title) -> SimulationPlotDocument` | **new** |

**Dropped:** `show_results` = `open_pane(editor, result_table(get_results(…)))`.
`plot_results` = `open_pane(editor, result_plot(get_results(…)))`. `result_api` —
as with `pane_api`.

`result_plot` takes several frames, which is what `plot_results(; into = …)` was
for. Adding to a plot that is already open becomes what it always was — a read,
a combine and a write:

```julia
open   = get_referenced_value(editor, chart)
replace_referenced_value!(editor, chart, result_plot(open, get_results(editor; config = "Fifo")))
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
batch = run_simulations(select_simulations(editor; config = "Tandem*"))
open_pane(editor, batch)                       # a pane, if a pane is wanted
describe(batch)                                # how far it is
open_pane(editor, result_plot(get_results(editor; config = "Tandem*", kind = "vectors")))
```

Longer to write, and every piece of it is reusable. The model that wants the plot
beside the runner instead of in a new tab writes the last line as a replace at a
reference, with nothing new to learn.

## 6. Open questions

- **Is a `PaneSplit`'s `weights` reachable by a reference step?** If it is,
  `resize_pane` is `replace_referenced_value!(editor, @reference(window,
  root.weights), [0.3, 0.7])` and the drop costs nothing. If it is not, either
  make it reachable or keep `resize_pane` by reference. **Check before Stage 2.**
- **Does `focus` belong to the reference machine at all?** Focus is the
  selection, not the tree, so it is not a replace. `focus_pane` survives for
  that reason. Whether it should be `select!(editor, reference)` — the kernel's
  own word — is a naming question for the review.
- **`describe` is a very common word.** The scratch module does
  `using M: <declared names>`, so a declared `describe` shadows anything else
  called `describe` in that scope. `DataFrames.describe` is one of the ten
  declared names. **These two collide, and one must give.** Either the generic
  is called `describe_content`, or the `DataFrames` name goes.
- **Does `open_pane` need a `title`?** A document that carries its own title
  makes the keyword redundant. Check which documents do.
- **`get_window_tree` is only there so `@reference(window, …)` has a `window`.**
  If `@reference(editor, …)` accepted the editor, the name would go and the
  surface would lose one more.

## 7. Stages

Each stage is a commit, and each leaves the assistant working.

- [ ] **1. `describe`.** Rename `describe_pane_content` to the generic, keep the
  methods, settle the collision of question 3. `ProjecturedPane`, then the three
  methods in `OmnetCampaignUi` and `OmnetIde`.
- [ ] **2. `open_pane`.** Add it to `PaneProgramModule`, answering a `Reference`.
  Answer question 1 first, then drop `close_pane`, `move_pane`, `resize_pane`
  from the declared list.
- [ ] **3. `focus_pane` by reference.** Drop the title lookup.
- [ ] **4. The runner.** `select_simulations`, `run_simulations` answering the
  batch, `stop_simulations` on the batch. Drop the other three.
- [ ] **5. The results.** `result_table` and `result_plot`. Drop `show_results`
  and `plot_results`.
- [ ] **6. The declared list.** Drop `pane_api` and `result_api` from what is
  declared — they stay as functions, they stop being vocabulary.
- [ ] **7. The prompt.** `CAMPAIGN_SYSTEM` and `IDE_SYSTEM` name the modules and
  a verb each. Rewrite them around the three concerns, and re-run the test that
  asserts the replaced sentence fires.
- [ ] **8. Prove it with a model.** Run the three-call session of §5 against
  `qwen3.8:27b`, the way the layout control was proven. A surface a model cannot
  compose is not consolidated, whatever its shape.
