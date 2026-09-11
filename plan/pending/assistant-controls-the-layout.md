# The assistant controls the layout

**Status:** pending. Written 2026-09-12. No step is implemented.

**Goal:** a language model reads the window, says what arrangement it wants, and
the window takes it. The model says it in one call, and it never names a document
type or a tree path.

**Asked for by:** the user, 2026-09-12:

> Let's figure out how could we allow the AI to freely and effectively control
> the layout of the user interface? It should be capable of understanding what's
> displayed, at least to some degree. For example, pane groups, panes, runners,
> running simulations, assistants, result tables, plots. […] The AI should be
> able to use layouts in panes to control positioning and size. For example, one
> API to query the window contents to known where large user interface
> components sit, then another to rearrange them using their references. This
> latter one may be a simple replace operation. The former I don't know. Why
> other idea, how to allow the AI to control layout and nesting?

Result tables and plots come from
[result-frames-browsed-and-plotted.md](../../../omnet-julia/plan/pending/result-frames-browsed-and-plotted.md).
This plan places them; it does not build them.

## 1. What exists now

Most of the machinery is built. The model can not reach any of it.

| part | where | state |
| --- | --- | --- |
| the layout itself, as a document | [PaneDocument.jl](../../source/pane/PaneDocument.jl) | **done**. `PaneTree` → `PaneSplit` / `PaneGroup` / `PaneTab`, with an orientation and one weight per child. |
| every layout edit, as an operation | [PaneSurgery.jl](../../source/pane/PaneSurgery.jl) | **done**. Open, close, split, move a tab, drop a tab into a split, resize, focus. |
| a walk over the groups | `pane_groups`, `pane_parent`, [PaneDocument.jl](../../source/pane/PaneDocument.jl) | **done**. |
| a layout inside one pane | [LayoutDocument.jl](../../source/layout/LayoutDocument.jl) | **done**. `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`, `StackLayout`, `ConstraintLayout`. Each holds a `CellVector` of **arbitrary documents**. |
| a size policy per cell | `SizePolicy`, `Fixed`, `Content`, `Relative`, `Fill` | **done**. Landed with the widget sizing rules. |
| a layout drawn | [LayoutToGraphics.jl](../../source/layout/LayoutToGraphics.jl), [WidgetToGraphics.jl:6749](../../source/widget/WidgetToGraphics.jl#L6749) | **done**, and each one reads gestures back. |
| a tab opened by a verb | `open_simulation_pane!`, [SimulationWindow.jl:99](../../../omnet-julia/source/legacy/simulator/presentation/SimulationWindow.jl#L99) | **done**. It takes any document, and it makes the title unique. |
| the assistant's verbs | [CampaignAgent.jl](../../../omnet-julia/source/ide/CampaignAgent.jl) | six verbs. One, `list_panes`, answers a flat list of titles and nothing about where they sit. |
| a verb that reads the arrangement | — | **missing**. |
| a verb that writes the arrangement | — | **missing**. |

Two facts from that table decide the shape of the work.

**A title is already an address.** `open_simulation_pane!` makes each title unique
in the window, so a title names one pane. The model already holds titles, because
`run_simulations` answers one.

**A pane holds any document, and a layout is a document.** So a pane can already
hold four plots in a grid. Nothing new is needed for that but a verb that says so.

## 2. The three levels of a layout

The word "layout" names three different things here, and a verb must say which.

| level | the document | what it gives | what it costs |
| --- | --- | --- | --- |
| the screen | `ScreenDocument`, [source/screen/](../../source/screen/) | more than one window | out of scope, see §8 |
| the window | `PaneTree`, `PaneSplit`, `PaneGroup` | a splitter the person can drag, and a tab strip per group | a tab strip per leaf |
| inside a pane | `GridLayout` and the other layout documents | a grid of contents, no tab strips | the person can not drag it apart |

The two lower levels are both needed, and they are not the same act:

- **Four sets of runs** belong in four tabs of one group. A person watches one at
  a time, and the tab strip is how they switch.
- **Four plots of one study** belong in one pane, in a two-by-two grid. A person
  compares them, so all four must be on screen at once, and one tab strip over
  the four is right where four strips are noise.

So the model must be able to say both. §4.6 says how it says them with the same
words.

## 3. The shape of the answer

Five verbs and three combinators, in a new `PaneAgentModule`. The assembly adds
the module to the `api` list that `declare_api!` takes.

```julia
show_layout(editor)                             -> String   # the picture
arrange(editor, description)                    -> String   # the picture, after
move_pane(editor; pane, next_to, side)          -> String   # the picture, after
focus_pane(editor; pane)                        -> String
close_pane(editor; pane)                        -> String   # the picture, after

beside(children...)    # side by side, left to right
above(children...)     # one over the other, top down
tabbed(panes...)       # tabs of one group
```

A child of a combinator is a title, another combinator, or a `title => fraction`
pair that states the share of the axis. That is the whole grammar.

## 4. Decisions

### 4.1 The model names a pane, and nothing else

A pane is the only thing that has a name. A group, a split and a weight have
none — a combinator makes them.

This is the decision that keeps the surface small. The alternatives each add an
address space the model must keep straight:

| address | why not |
| --- | --- |
| a path, `root.elements[2].tabs[3]` | It is the tree's own vocabulary and it is exact. It goes stale at the first edit, and a stale path names a **different** pane rather than no pane, so a wrong move is silent. |
| a number minted per query | The same staleness, and it needs a table that outlives the call. |
| a word for a place, "the left group" | Two groups can both be on the left. |

A title goes stale only when a person renames the tab, and then it names nothing
rather than the wrong thing. A verb that finds no such title answers the list of
titles, so the next round is right.

**Two panes can carry one title** when a person renames one by hand. A verb that
matches two refuses and says so.

### 4.2 The picture ends with the call that reproduces it

`show_layout` answers a picture, and the last line of the picture is the
`arrange` call that makes that same layout. For example:

```
The window shows 4 panes. A star marks the one that has the focus.

side by side
  30%   Runner                          the run form
  70%   one above the other
          60%   tab   Assistant *       this conversation
          40%   tab   Tandem runs       18 runs: 12 done, 6 running
                tab   delay table       a result table, 4200 rows

This layout is:
  arrange(editor, beside("Runner" => 0.3,
                         above(tabbed("Assistant") => 0.6,
                               tabbed("Tandem runs", "delay table") => 0.4)))
```

**This is the main lever of the design.** A model does not learn the grammar from
a docstring and then write it blind. It reads the current window written in the
grammar, and it edits that text. To move the table beside the plot, it moves one
word. The grammar is taught by an example that is true right now.

Two rules follow from it:

1. **Every verb that changes the window answers the new picture.** A model that
   acts therefore perceives, in the same round, at no extra call.
2. **The printer and the parser must agree exactly.** A round trip test asserts
   it: print the picture, run the call it names, print again, and the two
   pictures are equal. §6 stage A.

### 4.3 A content says what it is, through a method table

The picture's right-hand column says what each pane holds. The pane package can
not know a `SimulationBatchDocument` or an `Assistant`, so it asks:

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

This is a method table, not a registry. Nothing registers itself and nothing is
mutable: a package that is loaded has its methods, and a package that is not
loaded has no document to describe. A `nothing` content answers "empty".

**A description is one short line and it says what changes.** "18 runs: 12 done,
6 running" tells the model the set is not finished, which is the fact it needs
next. "a SimulationBatchDocument" tells it nothing.

### 4.4 A write is a reconcile, and it ends in one replace

`arrange` does not edit the tree step by step. It builds the tree the description
names and writes it at `tree.root`, with one `ReplaceReferencedValueOperation`.
The user said the write "may be a simple replace operation". It is.

Three rules make the replace safe:

1. **Every `PaneTab` object is carried over by identity.** The tree that is
   written holds the *same* tab objects, so the iomap under each content
   survives and no content re-prints. This is the rule
   [PaneSurgery.jl](../../source/pane/PaneSurgery.jl) already states about
   itself. A fresh `PaneGroup` or `PaneSplit` is cheap; a fresh content is not.
2. **The focus is written in the same operation.** Focus is the selection, and
   the selection is a path into the tree that is replaced. So the operation is a
   `CompoundOperation`: the root write, and a `ReplaceSelectionOperation` that
   names the focused tab where it now sits. Leave this out and the focus lands
   on whatever the old path now reaches.
3. **Each new group is given the selection of the tab it must show.** A group
   shows the tab its own selection names, and a fresh group has none, so it
   would show its first tab. Every group whose shown tab is still in it must
   keep showing that tab.

Rules 2 and 3 are the two traps of this plan. Both are stated in
[PaneDocument.jl](../../source/pane/PaneDocument.jl) under "Focus is the
selection" and "Dormant selections", and both are easy to miss.

**An operation means undo.** The person presses undo once and the old layout is
back. This is the whole safety story for a model that rearranges the window, and
it comes free from the write being an operation rather than a field assignment.

**A group that is unchanged can be reused** — same tabs, same order. That saves
the tab strip a re-print. It is a refinement, not a requirement: do it in stage B
only if the strip re-print is visible. Measure first.

### 4.5 `arrange` never closes a pane

A description that leaves a pane out is **refused**, and the refusal names the
panes it left out.

The alternatives are both worse:

- **Close the panes that are not named.** A model that forgets the Runner
  destroys it. The damage is silent and the person's work is gone.
- **Keep them somewhere.** Then `arrange` does not say what the layout is, and
  the model must guess where the extras went.

A refusal costs one round and the message says exactly what to add, so the retry
is right. To close a pane, the model calls `close_pane`, which is a different
word for a different intent.

`arrange` also refuses a description that names one pane twice, or a name no pane
carries.

### 4.6 Inside a pane: the same words, a different document

The combinators build a description, not a tree. So the same description reaches
two destinations:

| destination | a combinator becomes | a leaf is |
| --- | --- | --- |
| the window | `PaneSplit` / `PaneGroup` | a pane, by title |
| one pane | `HorizontalLayout` / `VerticalLayout` / `GridLayout` | a content document |

```julia
# the window
arrange(editor, beside("Runner" => 0.3, "Assistant" => 0.7))

# one pane, holding four plots in two rows of two
open_pane(editor; title = "delay study",
          content = above(beside(p1, p2), beside(p3, p4)))
```

A fraction becomes a split weight in the window, and a `Relative(w)` policy
inside a pane. `Fill` and `Content` are what a leaf takes when no fraction is
given, which is what the widget sizing rules already say.

**`open_pane` is not in the first stages.** It needs contents worth placing, and
those are plots and result tables from the other plan. Stage D adds it after that
plan lands. The combinators are built in stage A either way, because the window
needs them.

### 4.7 What is rejected, and why

**The model writes the document itself.** `execute_julia_code` can already
evaluate `editor.document.root = PaneSplit(...)`. It needs no new API at all, and
it is the most free of every option. It is rejected for four reasons: it is not
an operation, so there is no undo; it rebuilds subtrees, so every tab re-prints
and the iomaps drop; it leaves the selection pointing into a tree that is gone;
and it makes the model name document types, which
[CampaignAgent.jl](../../../omnet-julia/source/ide/CampaignAgent.jl) already
found to be the thing a model gets wrong. Freedom that costs correctness is not
control.

**A layout string, `"[Runner | [Assistant / runs]]"`.** It is compact and it
needs a grammar, a parser and error messages of its own. The combinators are
Julia, which the model already writes, and they need none of the three.

**Incremental verbs only** — split this group, move that tab, resize this
splitter. This is what `PaneSurgery` gives, and it is the most faithful to what a
person does with a mouse. A model driving it needs one round per step and must
hold the shape of the tree in its head between rounds. `move_pane` keeps the one
case where a single step is the whole intent.

**A gesture replay** — the model emits the drags a person would. It is exact and
it is unaimable.

**A screenshot.** The window renders to an image already, so a vision model could
read the screen literally, and that is the only way to know how a thing *looks*.
It is not the way to know *where things sit*: the picture of §4.2 says that in 80
tokens, exactly, and a local model with no vision can read it. Keep the
screenshot for a later question — "does this chart read well?" — which is a
different question from this plan's.

## 5. The verbs

Each one takes the editor first and everything else as a keyword of a plain type,
which is the rule
[CampaignAgent.jl](../../../omnet-julia/source/ide/CampaignAgent.jl) states.

| verb | what it does |
| --- | --- |
| `show_layout(editor)` | Answer the picture of §4.2. |
| `arrange(editor, description)` | Make the window match `description`. Answer the new picture. Refuse a description that omits, repeats or invents a pane. |
| `move_pane(editor; pane, next_to, side)` | Move one pane. `side` is `"left"`, `"right"`, `"above"`, `"below"` or `"tab"`. Answer the new picture. |
| `focus_pane(editor; pane)` | Show that pane and give it the focus. |
| `close_pane(editor; pane)` | Close one pane. Answer the new picture. |

`move_pane` exists because `arrange` restates the whole window, and a window of
ten panes is ten names the model must repeat to move one. It is
`pane_move_tab_operation` and `pane_drop_split_operation`, which already exist,
behind one name.

## 6. Stages

### Stage A — the model reads the window

1. `pane_content_description` and its default method, in
   [PaneDocument.jl](../../source/pane/PaneDocument.jl).
2. The picture printer, in a new `source/pane/PaneAgent.jl`.
3. `beside`, `above`, `tabbed`, and the `PaneArrangement` struct they build. It
   holds a kind, a list of children and a list of fractions. It holds no
   document.
4. The parser is Julia: the model's own `arrange(editor, beside(…))` call.
5. `show_layout`.

**Test.** Build a known tree by hand, print it, and assert the string. Then the
round trip: run the call the last line names, print again, assert the two
pictures are equal. No model is needed for either.

### Stage B — the model writes the window

1. `arrange`, as §4.4 says: resolve the titles, carry the tab objects over by
   identity, build the new root, write it with the focus and the per-group
   selections in one `CompoundOperation`.
2. The three refusals of §4.5.
3. `move_pane`, `focus_pane`, `close_pane` over the existing surgery.

**Test.** Each of these is model-free, and each is one assertion:

- `arrange` moves a pane, and every `PaneTab` in the new tree is `===` the object
  that was in the old one.
- The focused pane still has the focus, in its new place.
- A group that showed its second tab still shows that tab.
- A description that omits a pane is refused, and the message names it.
- One undo restores the layout that was there before.

### Stage C — the assistant reaches the verbs

1. `OmnetCampaignUi` adds `PaneAgentModule` to the `api` list it hands to
   `run_campaign_window`. That list is the decision §5.3 of the result-frames
   plan already made.
2. `CAMPAIGN_SYSTEM` gains one sentence: the window's layout is the model's to
   change, and `show_layout` says what it is now.
3. `list_panes` is dropped. `show_layout` answers what it answered and more.

**Test.** The headless two-turn run the campaign agent tests already use: a
person types "put the runs next to the runner", and the layout after it is the
asserted one.

### Stage D — a layout inside a pane

Needs the result-frames plan, because it needs contents worth placing.

1. Check first that a pane whose content is a `GridLayout` draws and reads. The
   row is registered at
   [WidgetToGraphics.jl:6749](../../source/widget/WidgetToGraphics.jl#L6749) and
   every layout has a `read_intent`, so this is a check, not a claim.
2. `open_pane(editor; title, content)`, where `content` is a document or a
   description of documents.
3. The description compiles to `HorizontalLayout`, `VerticalLayout` or
   `GridLayout`, and a fraction becomes `Relative(w)`.

### Stage E — refinements, each behind a measurement

1. Reuse a group whose tabs and order did not change, so its strip does not
   re-print. Measure the re-print first.
2. The picture says which panes are large and which are small, in pixels, when
   the geometry is known. [PaneGeometry.jl](../../source/pane/PaneGeometry.jl)
   already computes it for the drag.

## 7. What can go wrong

| trap | why | where it is caught |
| --- | --- | --- |
| The focus lands on the wrong pane. | The selection is a path into the tree that `arrange` replaced. | §4.4 rule 2; stage B test. |
| A group shows its first tab, not the one it showed. | A fresh group has no dormant selection. | §4.4 rule 3; stage B test. |
| Every tab re-prints and the window blinks. | A rebuilt subtree drops the iomaps under it. | §4.4 rule 1; the identity test. |
| The model rearranges the window on every turn. | Nothing stops it. | The write is one operation, so one undo takes it back. Say so in the system prompt. |
| A pane vanishes. | A description that omits it. | §4.5. The verb refuses. |
| Two panes carry one title. | A person renamed one. | The verb refuses and says which. |

## 8. Out of scope

**More than one window.** `ScreenDocument` holds a list of windows, and the same
two verbs extend to them: the picture gains a window per block, and `move_pane`
gains a `window` keyword. Nothing in this plan blocks it. It waits until a person
asks for a second window.

**The size of a widget inside a content.** The widget sizing rules own that, and
the model does not reach it. A `GridLayout` in a pane is where the model's
control stops.

## 9. Open questions

1. Does `PaneAgentModule` live in `ProjecturedPane`, where every application with
   a pane tree reaches it, or in `OmnetCampaignUi` beside `CampaignAgentModule`?
   This plan assumes `ProjecturedPane`. Nothing in the verbs is about
   simulations.
2. §4.5 refuses a description that omits a pane. Is that right, or must the
   omitted panes go somewhere?
3. Is stage D in this plan, or does it wait for the result-frames plan to land
   and become a stage of that one?
