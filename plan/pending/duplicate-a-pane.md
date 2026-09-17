# Duplicate a pane

> **Kind:** plan · **Status:** pending · **Stands on:**
> [pane.md](../../documentation/package/pane/pane.md),
> [selection.md](../../documentation/package/kernel/selection.md),
> [widget.md](../../documentation/package/widget/widget.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md)

**Goal.** A person duplicates the tab they work in: the Runner, the Assistant,
or a plot that the assistant made. The duplicate is a second pane that the person
controls on its own. The gesture is a `+` above the `x` of each tab, and a
chord. The assistant duplicates a pane with the verb `duplicate_pane!`.

The work is in two repositories. The copy policy, the pane edit, the tab strip,
the verb and the assistant are in projectured-julia. The runner and the result
documents are in omnet-julia.

## 1. The decision

**A duplicate is a new document of the same kind. `copy_document` makes it,
under a copy policy.** The policy steers the walk in two ways:

- **Special recursion.** A kind that needs more than a copy of each field adds a
  method `copy_document(::DuplicatePolicy, ::Kind)`, and dispatch selects it.
- **Stop control.** At each child document, the policy says if the walk goes
  in. Where the walk stops, the duplicate shares the child. A hook can also
  refuse the whole copy.

Three rules decide how deep the duplicate goes:

1. **The duplicate owns what the person controls in the pane.** The form fields
   of the runner, the transcript and the composer text of the assistant, and the
   title and the query of a plot are copied. After the duplicate exists, an edit
   in one pane does not change the other pane.
2. **The duplicate shares what the pane reads.** The project and its discovery
   cache, the result files, a data frame, the model backend and the API key are
   not in the pane. Both panes read the same source, and a change to the source
   shows in both.
3. **The duplicate does not copy a process.** A run set that runs and an
   assistant turn that streams stay with the original. The duplicate starts
   idle. An action of the duplicate acts on the duplicate: its Run button runs
   its own parameters.

The view state is copied once: the duplicate opens with the same selection. After
that, the two panes move on their own.

**A mirror is not a duplicate, and this plan does not make one.** A mirror is
the same document in two panes. Each document node stores its own `selection`
cell, so two panes that hold one object share one caret. A mirror with two
carets needs a view state that is apart from the document. That is a kernel
design of its own (§6).

**A kind that declares nothing gets no `+`.** The default answer is "no
duplicate", because a copy that the kind does not understand can act on the
original (§2b).

### The decisions of the user, 2026-09-17

- **D1. The button is stacked.** The `+` takes the top half of the `x` box and
  the `x` takes the bottom half. The box grows to the full tab height, and the
  tab keeps its width.
- **D2. The duplicate of the assistant is a fork.** It has the transcript so far
  and goes on from there.
- **D3. The duplicate opens as the next tab in the same group, with the focus.**
- **D4. The assistant gets the verb `duplicate_pane!`.** It lands in this plan.
  The rule of `assistant-recovers-from-a-miss.md` asks a three-seed measurement
  of a change to the words the model reads; the user decided that this verb does
  not wait for one. Step 7 runs a rank probe, which needs no language model.
- **D5. The mechanism is `copy_document` with a recursion control and a stop
  control**, not a second walk.

## 2. What is known, 2026-09-17

### 2a. The pane tree and the tab strip

- A tab is `PaneTab(title, content, icon)` in a `PaneGroup`
  ([PaneDocument.jl](../../source/pane/PaneDocument.jl)). The focus is the
  selection of the tree. No node has a focus field.
- `make_pane_open_tab_operation(tree, group, tab; index)` inserts a tab and moves
  the focus to it ([PaneSurgery.jl:351](../../source/pane/PaneSurgery.jl#L351)).
- `PaneGroupToWidgetTabbedPane` prints each group as a `WidgetTabbedPane` with
  `closable`, `new_tab` and `draggable` set
  ([PaneToWidget.jl:340](../../source/pane/PaneToWidget.jl#L340)). The strip
  reports `CloseTabOperation(pane, index)`, and `PaneTreeToWidget` answers it
  with a pane edit ([PaneToWidget.jl:427](../../source/pane/PaneToWidget.jl#L427)).
- `_tab_strip_geometry` gives each tab a close box of width `th`, the text
  height of the label, flush with the right edge of the tab, after a gap of
  `_sc(6)` ([WidgetToGraphics.jl:2856](../../source/widget/WidgetToGraphics.jl#L2856)).
  The tab height `sel_h` is the text height plus `2 × tab_padding`, and
  `tab_padding` is 4. The icon `:close` is drawn in a square of side `th`.
- `_tab_at_strip_x` tests the x coordinate only
  ([WidgetToGraphics.jl:3078](../../source/widget/WidgetToGraphics.jl#L3078)).
  A stacked button needs a y test too.
- The icon `:plus` exists. The new-tab button draws it. The close button has no
  hover state.
- A tab page is `WidgetTabPage(selector, element, icon)`
  ([WidgetDocument.jl:1168](../../source/widget/WidgetDocument.jl#L1168)). It
  has no per-tab flag.
- The strip tests are `test_widget_tab_strip` in
  [WidgetTabStripTest.jl](../../test/substrate/projection/WidgetTabStripTest.jl).
  They sweep the strip and never hard-code a pixel.
- No gesture table binds `Ctrl+D` or `Ctrl+Shift+D` (a search for
  `KeyDown(:d` found none).
- `open_pane!` names a new tab with `_unique_pane_title`, which gives "Runner
  (2)" when "Runner" is taken, and places it by `pane_group_to_avoid`
  ([PaneProgram.jl:305](../../source/pane/PaneProgram.jl#L305)). Its docstring
  calls it "the one placement verb". The comment above `focus_pane!` calls focus
  "the one act that is not a value written at a reference".
- `make_pane_api()` declares the pane verbs that the model can call
  ([PaneProgram.jl:93](../../source/pane/PaneProgram.jl#L93)). The test of the
  verbs is `test_pane_program` in omnet `test/campaign/PaneProgramTest.jl`.

### 2b. The copy that exists, and three hazards

`copy_document(document)`
([DocumentCopy.jl](../../source/kernel/document/DocumentCopy.jl)) makes a deep
copy with fresh cells, and keeps the kind of each cell. The clipboard uses it. It
is not a correct duplicate for the IDE, for three reasons:

1. **A computed cell becomes a constant.** `copy_cell_as` makes a
   `ReactiveCell{T}(value)`, and that constructor sets no thunk. The copy stops
   to follow its source, and nothing shows that.
2. **A behaviour leaf is shared.** A value that is not a document, a vector or a
   cell passes through unchanged. The runner stores its Run action in a `Ref`,
   and the action is a closure that captures the original form:
   `filter_runner!(filter, _ -> run_filter_in_new_pane!(tree, filter))`
   (omnet `CampaignSession.jl:49`). The Run button of a copy runs the parameters
   of the original.
3. **A back-link makes the walk endless.** `Assistant.draft` is a
   `ConversationDraft`, and `ConversationDraft.assistant` is the assistant. The
   walk has no guard against a cycle, so by reading, `copy_document(assistant)`
   does not end. Step 2 confirms this with a test.

The walk has a stop control, but only in one of its two forms:

- The hooks `is_descendable_for_sync(policy, depth, slot)`,
  `sync_element_limit(policy, source, shadow)` and
  `make_unsynced_placeholder(policy, source, current)` exist
  ([DocumentDefaults.jl](../../source/kernel/document/DocumentDefaults.jl)).
  Only the form that converts the cell kind, `copy_document(K, document,
  policy, depth)`, reads them. The form that keeps the cell kind has no policy.
- The descend hook receives the depth and the slot of a shadow, not the child.
  A copy passes `slot = nothing`. So a policy can stop by depth, but not by
  kind.
- `CellVector` has its own two `copy_document` methods
  ([CellVector.jl:237](../../source/collection/CellVector.jl#L237)).

Other facts about the files:

- No public function tells that a cell computes. The field
  `ReactiveCell.thunk` holds the function.
- `CellInterface.jl` is sealed. `CellModule.jl`, `CellDefaults.jl` and
  `ReactiveCell.jl` are not.
- The document files that this plan changes are not sealed:
  `DocumentModule.jl`, `DocumentInterface.jl`, `DocumentDefaults.jl` and
  `DocumentCopy.jl`. The kernel root `ProjecturedKernel.jl` is sealed, but it has
  no export list; `DocumentModule.jl` exports.

### 2c. The documents that the IDE puts in a tab

| Tab | Type | Owned | Shared | Process |
| --- | --- | --- | --- | --- |
| Runner | `SimulationFilter` (omnet) | 15 parameter documents | `cache` | none; `runner` is the action |
| Assistant | `Assistant` (projectured) | `conversation`, `input`, `draft`, `collapse_thinking` | `backend`, `model`, `system`, `api_key`, `context`, `llm` | a turn: an `@async` task, seen only as `status` |
| Plot of a frame | `SimulationPlotDocument` (omnet) | title, labels, series of `Vector{Float64}` | nothing: the data is a copy made when the plot was made | none |
| Live plot or table | `ResultPlotView`, `ResultTableView` (omnet) | the selections, `title`, `limit`, `revision` | `root`, the result files | none |
| Result table | `SimulationResultFrame` (omnet) | title, columns, selected, limit | `frame`, `source` | none; `plotter` is to be read in Step 8 |
| Run set | `SimulationBatchDocument` (omnet) | — | — | `batch`, the runs |
| Study, run card | `StudyStudy`, `LegacyRun` (omnet) | — | — | `LegacyRun.task` |
| Empty tab | `DocumentNothing` | nothing | nothing | none |

Other facts:

- The IDE has one runner form: `CampaignSession.filter`. The assistant verbs find
  the form by the tab title "Runner" (`get_runner_filter`, omnet
  `CampaignVerbs.jl:80`).
- The Run button already passes the form it is drawn for: `action(doc)` (omnet
  `SimulationFilterToWidget.jl:423`). Only the closure ignores its argument.
- The assistant already shows one document in two places: a run set is a live
  card in the transcript, and `open_pane!(editor, batch)` puts it in a tab too.
  So a shared document in two trees is a practice that exists.
- `pred_arguments(view)` and `make_pred_document(type, positional, keywords)`
  (omnet `ResultView.jl`) already rebuild a result view from its arguments.
- Omnet `plan/pending/driving-and-reading-a-run.md` §5 names the shared caret of
  one document in two panes as an open problem.

## 3. The design

### 3a. `copy_document` under a policy

```julia
abstract type CopyPolicy end
copy_document(policy::CopyPolicy, value) -> value
```

**The policy comes first.** The form that converts the cell kind takes a cell
type first, `copy_document(K, value)`. A policy is an instance and never a
type, so no method of one form is ambiguous with a method of the other.

The walk is a set of generic methods:

| The value | What the walk does |
| --- | --- |
| a leaf | shares it: the answer is the value |
| a vector | makes a new vector, each element through the walk |
| a `CellVector` | makes a new `CellVector`, each slot through the walk (a method in `CellVector.jl`) |
| a cell that stores | `copy_cell_as(cell, copy_document(policy, cell[]))` |
| a cell that computes | `copy_computed_cell(policy, cell)` |
| a document | `copy_document_fields(policy, document)` if `is_descendable_for_copy(policy, document)`, else `make_copy_placeholder(policy, document)` |

**Special recursion** is a method on the pair of the policy type and the value
type. Dispatch selects the most specific one, so a kind or a policy changes one
step of the walk and keeps the rest.

**Stop control** is four hooks. The policy comes first, as in the sync hooks:

- `is_descendable_for_copy(policy, document) -> Bool`. The default is `true`.
  It receives the child, so a policy can stop by kind.
- `make_copy_placeholder(policy, document)` gives what stands where the walk
  stopped. The default raises an error, as `make_unsynced_placeholder` does.
- `copy_computed_cell(policy, cell)`. The default gives a cell that stores the
  value that the cell has now. That is what `copy_document` does today.
- `get_copy_memo(policy) -> IdDict | Nothing`. The default is `nothing`. With a
  memo, a document that the walk meets twice gets one copy. A document that the
  walk meets inside its own copy stops the walk with a
  `DocumentCopyException`.

A hook refuses the whole copy with `throw(DocumentCopyException(value,
reason))`. The exception leaves the walk at any depth, and the caller catches
it.

**The field rebuild is a function of its own**, so a kind method can use it:

```julia
copy_document_fields(policy, document; replacements...) -> Document
```

It rebuilds the node through `Base.typename(T).wrapper`, as `copy_document`
does now. Each field goes through the walk, except a field named in
`replacements`, which takes the value given.

**The plain form uses the same walk.** `copy_document(value)` becomes
`copy_document(PlainCopyPolicy(), value)`, and `PlainCopyPolicy` takes every
default. The clipboard keeps its behaviour, and the kernel keeps one walk that
keeps the cell kind. The form that converts the cell kind and its `SyncPolicy`
hooks do not change in this plan.

**One predicate goes in the cell layer:** `is_computed_cell(cell) -> Bool`.
The default `false` goes in `CellDefaults.jl`, the `ReactiveCell` method in
`ReactiveCell.jl`, and the export in `CellModule.jl`. The contract of the cell
interface is in the sealed `CellInterface.jl`, and this plan does not change
that file. If the declaration must go there, the user gives permission for that
file first.

### 3b. The duplicate policy

```julia
struct DuplicatePolicy <: CopyPolicy
    copies::IdDict{Any,Any}
end
has_document_duplicate(document) -> Bool
make_document_duplicate(document) -> Document
```

`DuplicatePolicy` goes in the kernel document layer, so a domain adds a method
and does not depend on the pane slice. It answers the hooks so:

- `is_descendable_for_copy` gives `has_document_duplicate(document)`.
- `make_copy_placeholder` gives the document itself. The duplicate shares a
  child whose kind declares no duplicate.
- `copy_computed_cell` throws "a computed value". A frozen copy looks live and
  is not.
- A leaf that is a `Function`, a `Ref` or a `Task` throws "an action". The walk
  can not know what the leaf captures. This is a method
  `copy_document(::DuplicatePolicy, ::Union{Function, Base.RefValue, Task})`.
- `get_copy_memo` gives `copies`.

The selection cell is a cell that stores, so the walk copies it.

`has_document_duplicate` is the question that the tab strip asks at print time.
The default is `false`. It must not walk the tree: a walk makes the strip read
every cell of the content, and then each key typed in a transcript prints the
strip again.

`make_document_duplicate(document)` throws a `DocumentCopyException` when
`has_document_duplicate(document)` is `false`, with the reason "the kind
declares no duplicate". Otherwise it answers `copy_document(DuplicatePolicy(),
document)`, and the exception of a hook passes through to the caller.

**A kind declares its duplicate in one line**, `has_document_duplicate(::Kind) =
true`, and gets the field walk. A kind that needs more adds a second method,
`copy_document(policy::DuplicatePolicy, document::Kind)`, which can call
`copy_document_fields`.

### 3c. The pane edit

```julia
make_pane_duplicate_tab_operation(tree, group, index) -> Operation | Nothing
```

It calls `make_document_duplicate` on the content of the tab. If the call
throws a `DocumentCopyException`, the edit answers `nothing` and logs one
warning with the kind and the reason. Otherwise it answers
`make_pane_open_tab_operation` with a new `PaneTab` at `index + 1` of the same
group, and the focus moves to the new tab. The title comes from
`_unique_pane_title`, so the duplicate of "Runner" is "Runner (2)". The icon is
shared. `_unique_pane_title` moves from `PaneProgram.jl` to `PaneSurgery.jl`,
because both files use it now.

The duplicate is built when the reader answers the press. The build is a pure
construction: it starts nothing and registers nothing.

Step 5 looks for a message line in the editor. If one exists, the warning goes
there too.

### 3d. The gesture

- **The stacked button (D1).** On a page whose `duplicable` field is true, the
  close box becomes a column of width `th` and of the full tab height `sel_h`.
  The top half shows `+`, and the bottom half shows `x`. Each icon is centred in
  its half, in a square of side `sel_h ÷ 2`, a little smaller than `th`. A page
  whose field is false keeps the `x` as it is now.
- **The flags.** `WidgetTabbedPane` gets the flag `duplicable`, and
  `WidgetTabPage` gets the field `duplicable::Bool = false`. The strip draws the
  column only when both are true.
- **The hit test.** `_tab_at_strip_x` also takes the y coordinate and answers
  the tab index and the part hit: `:tab`, `:close` or `:duplicate`.
- **The report.** A press on the `+` answers `DuplicateTabOperation(pane,
  index)`. It is a report, as `CloseTabOperation` is, and its
  `evaluate_operation` is `nothing`. A down on the `+` is not a drag.
- **The pane printer** sets `duplicable` on the group widget and sets the page
  field from `has_document_duplicate(tab.content)`.
- **The pane reader** answers `DuplicateTabOperation` with
  `make_pane_duplicate_tab_operation`.
- **The chord** is `Ctrl+Shift+D`, "Duplicate the focused tab", in
  `@gestures PaneTree`. Step 4 checks the text and syntax tables for a conflict
  before it binds the chord.

### 3e. The kinds in this plan

| Kind | Declaration | Where |
| --- | --- | --- |
| `DocumentNothing` | `has_document_duplicate` only | projectured, primitive |
| primitive documents | `has_document_duplicate` only | projectured, primitive |
| conversation documents | `has_document_duplicate` only; a draft that links to an assistant is copied by the `Assistant` method | projectured, conversation |
| widget documents | `has_document_duplicate` only; a card that holds a button throws "an action" | projectured, widget |
| `Assistant` | both; the fork below | projectured, assistant |
| `SimulationFilter` | both; the runner below | omnet |
| `SimulationPlotDocument` | `has_document_duplicate` only | omnet |
| `ResultPlotView`, `ResultTableView` | `has_document_duplicate` only; `revision` starts at the value of the original | omnet |
| `SimulationResultFrame` | both; `frame` and `source` are shared by replacement; `plotter` is read first | omnet |

**The assistant fork (D2).** The method copies `conversation` and `input`
through the walk. It makes a new draft whose parts go through the walk and whose
back-link names the new assistant. It sets `status = :idle`. It shares
`backend`, `model`, `system`, `api_key`, `context` and `llm`. A turn that
streams keeps its writes in the original, because the task holds the original.
The duplicate shares `llm`, so a scripted fake `Llm` in a test is shared too;
the test of the fork uses a fake that has no position.

A document that a transcript embeds, such as a live run set, declares no
duplicate, so the fork shares it. It is history, and the run exists once.

**The runner.** The action changes from `_ -> run_filter_in_new_pane!(tree,
filter)` to `form -> run_filter_in_new_pane!(tree, form)`. The action then
receives the form it acts on and captures no form. The method is
`copy_document_fields(policy, form; runner = Cell(Ref{Any}(filter_runner(form))))`:
the duplicate has a new `Ref` that holds the same function, and the walk never
meets the `Ref` of the original. This is the rule for an action in a document
that has a duplicate: **an action receives the document it acts on; it does not
capture it.**

The assistant verbs keep to the tab titled "Runner". A duplicate is "Runner
(2)", so the verbs drive the first form. §6 lists this.

### 3f. The verb `duplicate_pane!` (D4)

```julia
duplicate_pane!(editor, reference::Reference) -> Reference
```

- The docstring has the form of the other verbs: one sentence, a "Use it to"
  paragraph, an example and a "See also" line. The example duplicates a plot and
  focuses the duplicate.
- The verb finds the tab through `_pane_referenced`, as `focus_pane!` does.
- It puts the duplicate as the next tab in the group of the original, with the
  focus. If that group is `pane_group_to_avoid(tree)`, which holds the
  conversation of the assistant, the verb uses the placement of `open_pane!`,
  so the conversation stays in view. An assistant that duplicates itself gets
  its fork in the other group.
- It answers the reference of the new tab, as `open_pane!` does.
- If the content has no duplicate, it throws an `ArgumentError` that names the
  kind and the reason. For example: "A SimulationBatchDocument pane has no
  duplicate: the kind declares no duplicate."
- `make_pane_api()` declares it after `:focus_pane!`.
- The docstring of `open_pane!` and the comment above `focus_pane!` change to
  name the new verb.

**The verb is a word of its own** because a replace can not say a duplicate. A
model could write `replace_referenced_value!` with a copy only if it could make
a correct copy, and §2b shows that a plain copy is not correct.

**The meaning search.** The next process computes the vector of the new
docstring without a manual step ([agent.md](../../documentation/package/kernel/agent.md)).
A rank probe with the meaning model checks two things. First, the sentences
"duplicate this plot", "another assistant like this one" and "a second runner"
must find `duplicate_pane!` in the first five hits. Second, the twelve verb
sentences in §1a of `assistant-recovers-from-a-miss.md` must keep their ranks.
If a rank moves, the step records it here, and the user decides.

## 4. Open questions

None. §1 records the decisions of the user.

## 5. Steps

Do the work in a git worktree of each repository, as a sibling in
`~/workspace/`. Commit each step. Mark the step done here, and record each
decision that the work finds.

**The baseline**, against projectured-julia `bce0084e` in the worktree
`projectured-julia-duplicate`: `test_document_contract` 31, `test_clipboard`
102, `test_pane_surgery` 79, `test_pane_gestures` 42, `test_widget_tab_strip`
18, `test_pane_reader` 32, `test_pane_to_widget` 44, `test_pane_construct` 45.
All pass, with no failure and no error.

- [x] **Step 1. The policy walk.** Add `is_computed_cell`, `CopyPolicy`,
  `PlainCopyPolicy`, the four hooks, `copy_document_fields`,
  `DocumentCopyException`, and the `CellVector` methods. Make
  `copy_document(value)` use the walk. Test in `test_document_contract`: a test
  policy that stops at one kind gets its placeholder there; a memo gives one
  copy of a shared child; a hook that throws leaves the walk from depth three;
  a replacement field takes the value given. Run `test_document_contract` and
  `test_clipboard`. Both must pass with no change to their assertions.
  - **Done.** `test_document_contract` 72 pass, `test_clipboard` 102,
    `test_collection` 47, `test_bounded_sync` 84, `test_document_reflection` 33.
  - Both methods of `is_computed_cell` are in `CellDefaults.jl`, the file that
    has every cell kind in scope, as `copy_cell_as` is.
  - The default `copy_computed_cell(policy, cell)` does not type `cell`. A typed
    default made a policy method `(::MyPolicy, cell)` ambiguous, and the first
    run of the test found it.
  - The walk has a method for `Vector{Cell}`. A comprehension can not promise
    that type for an empty list, and a collection keys its storage on it.
  - The `CellVector` step asks the stop hook itself, sends its `elements` cell
    through the cell step, and keeps one difference of the plain copy: the
    plain copy of a list starts with no selection, as before. Under any other
    policy the list keeps its selection.
  - A replacement value goes into a new cell of the kind of the field, and a
    replacement that names no field throws an `ArgumentError`.
  - Steps 1 and 2 are one commit, because they change the same kernel files.
- [x] **Step 2. The duplicate policy.** Add `DuplicatePolicy`,
  `has_document_duplicate` and `make_document_duplicate`. Test in
  `test_document_contract`: a value-only document gives an equal and independent
  duplicate; a computed cell, a `Function` leaf, a `Ref` leaf and a cycle each
  throw with their reason; a child of a kind with no duplicate is the same
  object; the selection is copied. Show that the plain `copy_document` of a
  document with a back-link does not end, with a bound on the time, or record
  that the reading of §2b was wrong.
  - **Done**, in the same test run as Step 1.
  - The reading of §2b was right. The plain `copy_document` of an `Assistant`
    ends in a `StackOverflowError` after 0.13 s, and Julia warns that the state
    of the process can be corrupt after it. So no test keeps this check; it was
    run once by hand.
  - `SelectionDocument` declares a duplicate, in `SelectionDocument.jl`, because
    that file loads after `DocumentCopy.jl`. So the duplicate owns its
    selection value, as it owns its selection cell.
- [x] **Step 3. The substrate kinds.** Add the declarations for
  `DocumentNothing`, the primitive documents, the conversation documents and the
  widget documents (§3e). Test each family with one document, and a widget card
  that holds a button (throws "an action").
  - **Done.** The new `test_document_duplicate`
    (`test/substrate/document/DocumentDuplicateTest.jl`, in `test_substrate`)
    passes 23 of 23. The conversation documents are tested with the assistant
    in Step 6, because the substrate test package does not load them.
  - The layout documents (`LayoutDocument`) and the collections
    (`CollectionDocument`) declare a duplicate too, because a card that the
    assistant makes holds layouts and lists.
  - **A correction to §3e: a card with a button does not refuse.** A
    `WidgetButton` keeps its function in an `Action` document, and an `Action`
    is by its own contract "shared by every control that shows it"; its
    callback receives the editor, not the button. `Action` declares no
    duplicate, so the duplicate of a button shares the command, and the test
    asserts that. A widget that holds a bare function, such as a `WidgetText`
    with a `validator`, refuses.
  - A draft keeps the assistant it links back to
    (`copy_document(::DuplicatePolicy, ::ConversationDraft)`), because that
    link is not the draft's own.
- [ ] **Step 4. The pane edit and the chord.** Add
  `make_pane_duplicate_tab_operation`, move `_unique_pane_title`, and bind
  `Ctrl+Shift+D`. Check the gesture tables for a conflict first. Test in
  `test_pane_surgery` (the new tab, its index, its title, the focus, and a
  content with no duplicate) and in `test_pane_gestures`.
- [ ] **Step 5. The button.** Add the flag, the page field, the stacked
  drawing, the hit test and `DuplicateTabOperation`. The pane printer sets the
  flags, and the pane reader answers the report. Test in `test_widget_tab_strip`
  (the seam between `+` and `x` along y, the full `x` on a page whose field is
  false, a down on the `+` is not a drag), in `test_pane_reader`, and in
  `test_pane_construct` (the standing render equals a fresh print after a
  duplicate). Look for a message line (§3c).
- [ ] **Step 6. The assistant fork.** Add the `Assistant` method (§3e). Test: an
  edit of the composer in one assistant does not reach the other; a turn
  submitted in the duplicate goes to the duplicate; a duplicate made while a
  turn streams is idle, and the stream writes to the original only.
- [ ] **Step 7. The verb.** Add `duplicate_pane!`, declare it in
  `make_pane_api()`, and change the docstring of `open_pane!` and the comment
  above `focus_pane!`. Test in omnet `test_pane_program`: the verb answers the
  reference of the duplicate; the duplicate of a plot is the next tab of its
  group; the duplicate of the assistant goes to the other group; a run set
  gives the `ArgumentError`. Run the tests of the prompt names, because the
  declared names change. Run the rank probe of §3f. It needs Ollama with no
  other model loaded and room for the meaning model in memory.
- [ ] **Step 8. The omnet kinds.** Change the runner action to receive the form.
  Read `SimulationResultFrame.plotter` and decide its rule. Add the declarations
  of §3e. Test: the Run button of a duplicate form runs the parameters of the
  duplicate, and the original form does not change; a duplicate plot view reads
  the same files.
- [ ] **Step 9. The real window.** Drive the campaign window headless through
  real presses on the rendered strip: duplicate the Runner, type a filter in the
  duplicate, press its Run, and assert that the new run set holds the jobs of
  the duplicate. Duplicate the Assistant and a plot the same way. Write one
  screenshot of the strip with the stacked button.
- [ ] **Step 10. The guides.** Update
  [pane.md](../../documentation/package/pane/pane.md) (the mouse and keyboard
  tables, a section on what a duplicate is),
  [widget.md](../../documentation/package/widget/widget.md) (the flag, the page
  field and the report), the contract of `copy_document` in
  `DocumentInterface.jl`, and the verb list in
  [agent.md](../../documentation/package/kernel/agent.md) if it lists the pane
  verbs. Move this plan to `plan/done/`.

## 6. What this plan does not do

- **A mirror with two carets.** It needs the view state apart from the
  document: the selection of each node, the scroll and the collapse flags. It is
  a kernel design, and omnet `driving-and-reading-a-run.md` stage 4 needs the
  same answer.
- **A snapshot.** A duplicate that freezes a live view on purpose is a second
  gesture. `copy_document(PlainCopyPolicy(), value)` already makes it.
- **One walk for both forms.** The form that converts the cell kind keeps its
  `SyncPolicy` hooks. A later plan can make it a `CopyPolicy` too.
- **A duplicate of a run set, a study or a run card.** They hold a process. A
  "run the same set again" gesture is a different feature.
- **A duplicate of a card with a button.** A widget action captures its
  document. The rule of §3e for the runner can apply to widget actions later.
- **The assistant drives the focused runner.** The verbs find the tab titled
  "Runner". A follow-up can make them use the runner that has the focus.
