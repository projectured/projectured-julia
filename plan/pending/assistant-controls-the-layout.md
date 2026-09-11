# The assistant controls the layout

**Status:** pending. Written 2026-09-12. No step is implemented.

**Goal:** a language model reads the window as a Julia program, and changes it by
naming a reference and a new value. It writes the document types, because the
document types are what a layout is.

**Asked for by:** the user, 2026-09-12. First the question:

> Let's figure out how could we allow the AI to freely and effectively control
> the layout of the user interface? It should be capable of understanding what's
> displayed, at least to some degree. For example, pane groups, panes, runners,
> running simulations, assistants, result tables, plots. […] The AI should be
> able to use layouts in panes to control positioning and size.

Then the shape of the answer:

> I would rather print the tree as a Julia construction and let the agent to
> apply a change by specifying changes by reference. If the user moves something
> while the agent acts, the operation may fail, but that's ok for now. Replace
> range by reference, can also use new constructors for layouts.

> The reference macro should be used.

Result tables and plots come from
[result-frames-browsed-and-plotted.md](../../../omnet-julia/plan/pending/result-frames-browsed-and-plotted.md).
This plan places them; it does not build them.

## 1. What exists now

Almost all of it. The model can not reach any of it.

| part | where | state |
| --- | --- | --- |
| the layout, as a document | [PaneDocument.jl](../../source/pane/PaneDocument.jl) | **done**. `PaneTree` → `PaneSplit` / `PaneGroup` / `PaneTab`, with an orientation and one weight per child. |
| a layout inside one pane | [LayoutDocument.jl](../../source/layout/LayoutDocument.jl) | **done**. `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`, `StackLayout`, `ConstraintLayout`, each over a `CellVector` of **arbitrary documents**. |
| a size policy per cell | `SizePolicy`, `Fixed`, `Content`, `Relative`, `Fill` | **done**. It landed with the widget sizing rules. |
| a layout drawn, and read back | [LayoutToGraphics.jl](../../source/layout/LayoutToGraphics.jl), [WidgetToGraphics.jl:6749](../../source/widget/WidgetToGraphics.jl#L6749) | **done**. Every layout has a `print_document` and a `read_intent`. |
| **a replace by reference** | `ReplaceReferencedValueOperation`, [Operations.jl:220](../../source/kernel/operation/Operations.jl#L220) | **done**. |
| **a replace of a range by reference** | the same operation, with a `RangeReferenceStep` terminal | **done**. It is the kernel's own primitive: `insert_elements` is a zero-width range, and `delete_elements` is a range replaced by an empty vector ([Operations.jl:296](../../source/kernel/operation/Operations.jl#L296)). |
| **the reference macro** | `@reference`, [ReferenceBuilder.jl](../../source/kernel/reference/ReferenceBuilder.jl) | **done**, and `ReferenceModule` exports it ([ReferenceModule.jl:106](../../source/kernel/reference/ReferenceModule.jl#L106)). |
| a macro in the model's namespace | [CodeExecution.jl:77](../../source/kernel/tool/CodeExecution.jl#L77) | **done**. The declared-api branch does `using M: <every exported name>`, and an exported macro is one of them. |
| a pane edit applied | `apply_pane_operation!`, [SimulationWindow.jl:76](../../../omnet-julia/source/legacy/simulator/presentation/SimulationWindow.jl#L76) | **done**. It evaluates the operation against a host whose `document` is the tree. |
| a verb that prints the tree | — | **missing**. |
| a verb that reads one node | — | **missing**. |
| a verb that writes by reference | — | **missing**. |

So the work is three verbs, one module that exports the right names, and a way
for a content to say what it is.

## 2. The three levels of a layout, and the one verb

The word "layout" names three things here.

| level | the document | what it gives |
| --- | --- | --- |
| the screen | `ScreenDocument`, [source/screen/](../../source/screen/) | more than one window. Out of scope, see §8. |
| the window | `PaneTree`, `PaneSplit`, `PaneGroup` | a splitter the person can drag, and a tab strip per group |
| inside a pane | `GridLayout` and the other layout documents | a grid of contents, with no tab strip and no drag |

The two lower levels are both needed, and they are not the same act. Four sets of
runs belong in four tabs of one group, because a person watches one at a time.
Four plots of one study belong in one pane, in a grid, because a person compares
them and all four must be on screen at once.

**One verb reaches all three.** A replace at `root` rearranges the window; a
replace at `root.elements[1].tabs[1].content` puts a `GridLayout` inside a pane.
The level is the reference, not the verb.

## 3. The shape of the answer

```julia
show_layout(editor)                  -> String    # the window, as a Julia program
node_at(editor, reference)           -> Document  # the node the reference names
replace_at(editor, reference, value) -> String    # the write; answers the new program
```

The model writes `@reference(…)` for the reference and a constructor for the
value. It needs nothing else.

## 4. Decisions

### 4.1 The read is a program that rebuilds the window

`show_layout` prints the tree as Julia. Each pane gets a name, and the comment on
its line says what it holds. The last statement is the `replace_at` call that
produces the window as it stands.

```julia
runner      = node_at(editor, @reference(root.elements[1].tabs[1]))              # Runner — the run form
assistant   = node_at(editor, @reference(root.elements[2].elements[1].tabs[1]))  # Assistant — this conversation (focused)
tandem_runs = node_at(editor, @reference(root.elements[2].elements[2].tabs[1]))  # Tandem runs — 18 runs: 12 done, 6 running
delay_table = node_at(editor, @reference(root.elements[2].elements[2].tabs[2]))  # delay table — a result table, 4200 rows

replace_at(editor, @reference(root),
    PaneSplit(:vertical, [
        PaneGroup([runner]),
        PaneSplit(:horizontal, [
            PaneGroup([assistant]),
            PaneGroup([tandem_runs, delay_table])], weights = [0.6, 0.4])],
        weights = [0.3, 0.7]))
```

Three properties make this the whole of the design.

**It runs.** Paste it back unchanged and the window does not move. So a model
that wants a change edits the text it was given: it swaps two names, changes a
weight, or wraps two panes in one `PaneGroup`. It does not compose a program from
a docstring.

**It teaches the grammar by an example that is true right now.** The model never
learns `@reference` or `PaneSplit` in the abstract. It reads them written about
the window in front of it.

**It keeps identity.** Each name binds the *existing* `PaneTab` object, so the
tree that is written holds the same tabs. The iomap under each content survives
and no content re-prints. A fresh `PaneGroup` or `PaneSplit` is cheap; a fresh
content is not.

The preamble binds tabs, not groups, because a tab is what a person moves. A
model that wants to keep a whole group writes `node_at` for it in the same form.

**A name comes from the title**, cut down to a Julia identifier and made unique.
A title is the person's word for the pane, so the program reads as the person
thinks. The name carries no meaning to the verb: the reference does.

### 4.2 The address is a reference, written with `@reference`

The model writes `@reference(root.elements[2].tabs[1])`. This is the kernel's own
path grammar, parsed by
[ReferenceSyntax.jl](../../source/kernel/reference/ReferenceSyntax.jl) and lowered
by [ReferenceBuilder.jl](../../source/kernel/reference/ReferenceBuilder.jl).

**Nothing new is built for this.** The macro exists, it is exported, and the
scratch namespace imports exported macros. A string address with a runtime parser
was considered and is not needed: it would be a second spelling of a grammar that
already has one, and one meaning per word is the rule.

The reference is rooted at the **pane tree**, not at `editor.document`. A live
editor holds a `ScreenDocument` and a headless caller holds the tree, so an
address that started at the editor would differ between the two. Both verbs
resolve against the tree, the way `apply_pane_operation!` already does with its
`PaneHost`. `root` is therefore the tree's own field, in both cases.

### 4.3 The write is `ReplaceReferencedValueOperation`, and a range is a terminal step

`replace_at(editor, reference, value)` builds one
`ReplaceReferencedValueOperation` and evaluates it against the tree. That is the
whole verb.

A reference whose last step is a range splices, which is the user's "replace
range by reference". The kernel already writes every collection edit that way:

| intent | reference | value |
| --- | --- | --- |
| replace one node | `root.elements[2]` | the new node |
| replace a run of tabs | `root.elements[1].tabs[1, 3]` | a vector of tabs |
| insert before tab 2 | `root.elements[1].tabs[1, 1]` | a vector of tabs |
| delete tabs 2 and 3 | `root.elements[1].tabs[1, 3]` | `[]` |
| put a layout in a pane | `root.elements[1].tabs[1].content` | `GridLayout([…], 2)` |

**A range is 0-based and half-open; an index is 1-based.** `tabs[2]` is the
second tab, and `tabs[1, 2]` is the same tab as a range of one. This is what
`RangeReferenceStep` means to `insert_elements` and `delete_elements`, and the
macro lowers the two spellings without changing either. It is the sharpest edge
in this surface. §7 says how it is guarded.

**A whole-node replace is the normal path, and it needs no index arithmetic.** To
drop a tab, the model writes the group again without it. The range form is there
for the case a whole-node replace is wasteful — one insert into a long list.

**An operation means undo.** The person presses undo once and the layout is back.
That is the whole safety story for a model that rearranges a window, and it comes
free from the write being an operation rather than a field assignment.

### 4.4 A stale reference fails, and it fails loudly

The user settled this: *"If the user moves something while the agent acts, the
operation may fail, but that's ok for now."*

So no locking, no version check, and no repair. But a failure must be a failure,
not a wrong write. Three cheap guards make it one:

1. `node_at` throws when the path resolves to nothing, naming the path.
2. `replace_at` refuses a range whose bounds fall outside the collection, and
   says how long the collection is.
3. `replace_at` refuses a value whose type can not sit in that slot — a
   `PaneTab` where an element of a split belongs.

A model that reads a fresh `show_layout` in the same round is almost never stale,
because the program it edits was printed for it in that round.

### 4.5 The focus, and the tab each group shows

Focus is the selection, and the selection is a path into the tree the write
replaced. Two rules follow, and they are the two traps of this plan. Both are
stated in [PaneDocument.jl](../../source/pane/PaneDocument.jl), under "Focus is
the selection" and "Dormant selections".

1. **`replace_at` repairs the focus.** It finds the focused `PaneTab` object
   before the write, looks for that same object in the tree after it, and writes
   a selection naming it where it now sits. When the object is gone, the focus
   goes to the first tab.
2. **A new group shows the tab it should show.** A fresh `PaneGroup` carries no
   selection, so it shows its first tab. A group whose tabs the model listed in a
   new order would therefore jump. `replace_at` gives each new group the
   selection of the tab that group's tabs were shown under, when exactly one of
   them was shown.

Both are a service of the verb. The model is never told about them.

### 4.6 A content says what it is, through a method table

The comments of §4.1 need one line per content, and the pane package can not know
a `SimulationBatchDocument` or an `Assistant`. So it asks:

```julia
pane_content_description(content) -> String
```

The default method answers the type's name. Each presentation package adds one
method beside the document it describes:

```julia
pane_content_description(::SimulationFilter) = "the run form"
pane_content_description(::Assistant) = "this conversation"
pane_content_description(b::SimulationBatchDocument) = _live_sentence(b)
```

This is a method table, not a registry. Nothing registers itself: a package that
is loaded has its methods, and a package that is not loaded has no document to
describe.

**A description is one short line, and it says what changes.** "18 runs: 12 done,
6 running" tells the model the set is not finished, which is the fact it needs
next. "a SimulationBatchDocument" tells it nothing.

### 4.7 One module exports exactly what the model may write

`declare_api!` takes modules, and the scratch namespace imports **a declared
module's own exported names, and not the names of the submodules it reaches**
([CodeExecution.jl:71](../../source/kernel/tool/CodeExecution.jl#L71)). So the
surface is a decision a person writes down, which is what that comment says.

A new `PaneAgentModule` is that decision. It exports:

- the three verbs, `show_layout`, `node_at`, `replace_at`;
- `@reference`, re-exported from `ReferenceModule`;
- the constructors the model writes: `PaneSplit`, `PaneGroup`, `PaneTab`, and
  `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`,
  `StackLayout`, with `SizePolicy`, `Fixed`, `Content`, `Relative` and `Fill`.

**`LayoutModule` exports none of its layout types today.** Its export list names
`LayoutDocument`, `FormLayout`, `SizePolicy`, `Fixed`, `Content`, `Relative`,
`Fill` and the anchored kinds, and reaches `GridLayout` only as
`LayoutModule.GridLayout` ([LayoutDocument.jl:22](../../source/layout/LayoutDocument.jl#L22)).
`PaneAgentModule` re-exports them. Whether `LayoutModule` should export them too
is a separate question and not this plan's.

### 4.8 What is rejected, and why

**A layout grammar of its own** — `beside(a, b)`, `above(a, b)`, `tabbed(a, b)`,
with a pane named by its title. It reads well and it is short. It is rejected
because it is a second vocabulary for a thing the repository already has a
vocabulary for: `PaneSplit(:vertical, …)` says `beside` exactly, to the document
that means it. A title is also a weaker address than a reference — a person
renames a tab, and two panes can carry one title.

**A picture in prose**, with a number per node. A number is minted per query, so
it goes stale the same way a path does, and it needs a table that outlives the
call. A path needs nothing and is already the system's word.

**A field assignment**, `editor.document.root = PaneSplit(…)`. It is what the
model could do today inside `execute_julia_code`. It is not an operation, so
there is no undo, the selection is left pointing into a tree that is gone, and
nothing checks the write. `replace_at` is the same freedom with those three
fixed.

**A screenshot.** The window renders to an image already, so a vision model could
read the screen literally, and that is the only way to know how a thing *looks*.
It is not the way to know where things sit: the program of §4.1 says that
exactly, and a local model with no vision can read it. Keep the screenshot for a
later question — "does this chart read well?" — which is a different question.

## 5. Stages

### Stage A — the model reads the window

1. `pane_content_description` and its default method, in
   [PaneDocument.jl](../../source/pane/PaneDocument.jl).
2. `PaneAgentModule`, in a new `source/pane/PaneAgent.jl`, with the exports of
   §4.7.
3. `node_at`, over `evaluate_reference` against the tree.
4. The printer for §4.1: the preamble, the construction, and the comments.

**Test.** Build a known tree by hand and assert the printed program, string for
string. Then the round trip, which is the property that matters: evaluate the
program it printed, print the new tree, and assert the two programs are equal.
Neither test needs a model.

### Stage B — the model writes the window

1. `replace_at`: build the operation, evaluate it against the tree, answer the
   new program.
2. The three refusals of §4.4.
3. The focus repair and the shown-tab repair of §4.5.

**Test.** Each is model-free and each is one assertion:

- A whole-root replace that reorders two panes keeps every `PaneTab` object
  `===` the object that was in the old tree.
- The focused pane still has the focus, in its new place.
- A group that showed its second tab still shows that tab.
- A range replace deletes the tab the range names, and only that tab.
- A range whose bounds are outside the collection is refused, and the message
  says how long the collection is.
- One undo restores the layout that was there before.

### Stage C — the assistant reaches the verbs

1. `OmnetCampaignUi` adds `PaneAgentModule` to the `api` list it hands to
   `run_campaign_window`. That list is the decision §5.3 of the result-frames
   plan already made.
2. `CAMPAIGN_SYSTEM` gains two sentences: the window's layout is the model's to
   change, and `show_layout` prints it as a program to edit.
3. `list_panes` is dropped. `show_layout` answers what it answered and more.

**Test.** The headless two-turn run the campaign agent tests already use. A
person types "put the runs next to the runner", and the tree after the turn is
the asserted one.

### Stage D — a layout inside a pane

This needs the result-frames plan, because it needs contents worth placing.

1. Check first that a pane whose content is a `GridLayout` draws and reads. The
   row is registered at
   [WidgetToGraphics.jl:6749](../../source/widget/WidgetToGraphics.jl#L6749) and
   every layout has a `read_intent`, so this is a check, not a claim.
2. The printer prints a content that is a layout as a construction too, one level
   deep, so the model can edit a grid the same way it edits the window.
3. Nothing else. `replace_at` at `….content` already writes it.

### Stage E — refinements, each behind a measurement

1. The program says how large each pane is, in pixels.
   [PaneGeometry.jl](../../source/pane/PaneGeometry.jl) already computes it for
   the drag.
2. A type checkpoint in each printed reference — `root.elements[1]::PaneGroup` —
   so a stale path fails on the type rather than on the slot. The grammar takes
   it today. Measure whether it earns its length first.

## 6. Five verbs that are not built

`move_pane`, `close_pane`, `focus_pane`, `split_pane` and `resize_pane` are each
one line of `replace_at`, and [PaneSurgery.jl](../../source/pane/PaneSurgery.jl)
already builds the operation behind each. They are not in this plan. Add one only
when a measured round count says the model spends a round it should not have to.
The surface stays at three names until then.

## 7. What can go wrong

| trap | why | where it is caught |
| --- | --- | --- |
| A range is read as 1-based and the wrong tab goes. | `tabs[2]` is 1-based and `tabs[1, 2]` is 0-based half-open. | §4.3. The docstring states it with both examples, and §4.4 refuses an out-of-range one. A whole-node replace is the recommended path. |
| The focus lands on the wrong pane. | The selection is a path into the tree the write replaced. | §4.5 rule 1; the stage B test. |
| A group shows its first tab, not the one it showed. | A fresh group has no dormant selection. | §4.5 rule 2; the stage B test. |
| Every tab re-prints and the window blinks. | A rebuilt subtree drops the iomaps under it. | §4.1. The preamble binds the existing tab objects; the identity test asserts it. |
| The model can not write `GridLayout`. | `LayoutModule` does not export it. | §4.7. `PaneAgentModule` re-exports it. |
| A `ReplaceSelectionOperation` has no selection to write. | The host `apply_pane_operation!` builds carries a document and nothing else. | Stage B. Check it before the focus repair is written. |
| The model rearranges the window every turn. | Nothing stops it. | The write is one operation, so one undo takes it back. Say so in the system prompt. |

## 8. Out of scope

**More than one window.** `ScreenDocument` holds a list of windows, and the same
three verbs extend to them: the program gains a statement per window, and the
references gain a `windows[k].content` head. Nothing here blocks it. It waits
until a person asks for a second window.

**The size of a widget inside a content.** The widget sizing rules own that. A
`GridLayout` in a pane is where the model's control stops.

**A runtime parser for a reference string.** `@reference` is the spelling, and
one spelling is enough. [document-locator.md](document-locator.md) is where a
second addressing mode belongs, if one is ever wanted.

## 9. Open questions

1. Does `PaneAgentModule` live in `ProjecturedPane`, where every application with
   a pane tree reaches it, or in `OmnetCampaignUi` beside `CampaignAgentModule`?
   This plan assumes `ProjecturedPane`. Nothing in the three verbs is about
   simulations.
2. §4.3 keeps the kernel's 0-based half-open range and states it. The other
   choice is for `replace_at` to read a range as 1-based and inclusive, and
   convert. That would make the verb's grammar differ from the macro's, which is
   the drift this plan otherwise avoids. Keep the kernel's reading?
3. Is stage D in this plan, or does it wait for the result-frames plan to land
   and become a stage of that one?
