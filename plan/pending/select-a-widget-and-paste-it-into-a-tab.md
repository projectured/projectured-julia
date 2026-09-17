# Select any widget, and paste the selected object into a tab

**Status (2026-09-17): IN PROGRESS** on the branch `select-and-paste`, in the
worktree `projectured-julia-select-paste`, and in omnet on the branch
`select-and-paste` in the worktree `omnet-julia-select-paste`. Steps 0 to 5, 8
and 9 are done; Steps 6 and 7 wait on their omnet test run.

**Goal:** in the omnet IDE, a person selects any widget in any tab: a table, a
form, a message, an evaluation, a part of the runner. The selection shows on
the screen. `Ctrl+C` or `Ctrl+N` stores the selected object, and `Ctrl+V` puts
it into an empty new tab. The conversation and the tool panes (the assistant,
the runner) refuse a paste. The two charts walk with the same `Alt` + arrows as
everything else.

**Repositories:** projectured-julia (the widget, focus, clipboard, domain,
conversation and pane slices) and omnet-julia (the IDE window and its
presentation projections). The plan changes no sealed file.

## 1. The request and the rulings

> in omnet ide, I want to be able to select user interface components like
> tables, forms, assistant messages, evaluated forms in the conversation. The
> selection should be visible to the user, it should use the normal selection
> path, and I would like to be able to copy-paste, note-paste the selected
> object into an empty new tab pane in a tab group

The user's rulings on the first draft, 2026-09-17:

| Question | Ruling |
| --- | --- |
| Which widgets can be selected? | Any widget. No opt-in flag. |
| Which gesture selects? | A click with a modifier, so that a plain click still controls the widget. |
| Which tabs? | Every tab: the runner and any other tab, not only the conversation. |
| Where does a new tab put the selection? | On its content. |
| Paste into the conversation | The conversation must refuse it. |
| The tab takes the name of the pasted object | Only if it is simple. |
| A note puts one object in two views, and both show its selection | Accepted. |
| `Alt+Up` / `Alt+Down` walk the objects, `Ctrl+N` notes | Accepted. |
| `Alt+Left` / `Alt+Right` | Move between siblings. |
| The two charts turn the `Alt` arrows the other way | Change them to the syntax meaning. |
| A paste over a whole tool pane (the assistant, the runner) | Refuse it, as for the conversation. |

The words mean this in the code:

| Word | Meaning |
| --- | --- |
| select | a `ReplaceSelectionOperation` whose path ends AT the object: a whole-element selection, the path tail is `EmptyReference()` |
| visible | the selected widget draws a selection ring |
| normal selection path | the document's `selection` cells, written by the editor from a reader's operation. No second selection state. |
| copy-paste | `Ctrl+C`, then `Ctrl+V`. The tab gets an independent deep copy (`copy_document`). |
| note-paste | `Ctrl+N`, then `Ctrl+V`. The tab gets the same live object. |
| empty new tab | `Ctrl+T` or the `+` button: `PaneTab("untitled", DocumentNothing())` |

## 2. What exists

| Fact | Where |
| --- | --- |
| The IDE root is a screen. Its first window holds a `PaneTree`. | [PaneProgram.jl:166](../../source/pane/PaneProgram.jl#L166) `get_window_tree` |
| The IDE chain is `WidgetHoverTrackingProjection` over `PaneToWidget` and `NaturalToGraphics`. The chat draws with `AssistantToWidgetSplitPane`. | omnet [CampaignWindow.jl:52](../../../omnet-julia/source/campaign/CampaignWindow.jl#L52) |
| The runner tab holds a `SimulationFilter`. A set of runs opens as a `SimulationBatchDocument`. Their projections register with `register_natural_graphics!`. | omnet [SimulationWindow.jl:50](../../../omnet-julia/source/legacy/simulator/presentation/SimulationWindow.jl#L50), `SimulationFilterToWidget.jl`, `SimulationBatchToWidget.jl`, `SimulationToWidget.jl`, `StudyGraphics.jl` |
| A new tab holds `DocumentNothing()`. Its docstring promises that Alt+click selects it whole and that a paste replaces it. | [PaneDocument.jl:38-52](../../source/pane/PaneDocument.jl#L38-L52) |
| `Ctrl+T` puts the cursor on the TAB (`tabs[k]`), not on its placeholder. A paste there replaces the whole `PaneTab`. | [PaneSurgery.jl:351](../../source/pane/PaneSurgery.jl#L351) |
| Alt+click is already the whole-element gesture: a syntax node, a table cell, the placeholder. | [SyntaxDocument.jl:626-641](../../source/syntax/SyntaxDocument.jl#L626-L641), [WidgetToGraphics.jl:6166](../../source/widget/WidgetToGraphics.jl#L6166) |
| The syntax walk binds all four `Alt` + arrows: up is the parent, down is the first child, left and right are the siblings. At the first or last sibling the selection stays. At its own root, left and right decline, so a walk above can answer. | [SyntaxDocument.jl:676-714](../../source/syntax/SyntaxDocument.jl#L676-L714) |
| The chart and the sequence chart turn the arrows the other way: `Alt+Left` selects the whole chart, `Alt+Right` the first part, `Alt+Up` and `Alt+Down` the siblings. | [ChartDocument.jl:618-623](../../source/chart/ChartDocument.jl#L618-L623), [SequenceChartDocument.jl:1005](../../source/sequencechart/SequenceChartDocument.jl#L1005) |
| No widget answers an Alt+click in general. `WidgetCard` and `WidgetComposite` answer `nothing` for a press that misses their children. | [WidgetToGraphics.jl:4343](../../source/widget/WidgetToGraphics.jl#L4343) |
| No widget draws a whole-element selection, except `WidgetTable` (`_WT_HL_COLOR`). Controls draw `_push_focus_ring!` for ANY selection. | [WidgetToGraphics.jl:276](../../source/widget/WidgetToGraphics.jl#L276) |
| The widget renderer has 41 printers and no one place that builds every canvas. `get_anchor_point` maps a document reference forward to a point in the root canvas. | [WidgetToGraphics.jl:25](../../source/widget/WidgetToGraphics.jl#L25) |
| A projection that can not map a click back can store a projection-induced reference (`ProjectionReference`). Only the `RuleIoMap` reader does this. | [generic-structural-selection-fallback.md](../done/generic-structural-selection-fallback.md) |
| The transcript selection stops at a part. A plain click names `turns[i].parts[j]`. | [ConversationToWidget.jl:410-440](../../source/conversation/ConversationToWidget.jl#L410-L440) |
| The transcript is read-only. Its reader declines three write operations by their exact type. | same place |
| The result of an evaluation is a live `Document` in `EvaluatorForm.result`. The part prints it as the body of a section card. | [AssistantTurn.jl:697-712](../../source/assistant/AssistantTurn.jl#L697-L712), [ConversationToWidget.jl:268-290](../../source/conversation/ConversationToWidget.jl#L268-L290) |
| A `SimulationResultFrame` maps no reference either way. A click on a row writes `selected`, and a double click plots. | omnet [SimulationResultFrameToWidget.jl:200-239](../../../omnet-julia/source/legacy/result/presentation/SimulationResultFrameToWidget.jl#L200-L239) |
| `ConversationDocument` draws through `ConversationToWidget` anywhere, so a turn or a part draws alone in a tab. A bare `EvaluatorForm` has no entry. | omnet `CampaignWindow.jl:62-68` |
| The clipboard slice has copy, cut, note, paste, paste-copy and a view toggle. The IDE does not use it. `run_example` adds it through `Gallery.jl`. | [ClipboardSliceToAny.jl](../../source/clipboard/ClipboardSliceToAny.jl), [Gallery.jl:247](../../example/projectured/Gallery.jl#L247) |
| `make_clipboard_projection` is in an example file. | [WrapperProjectionExample.jl:96](../../example/workbench/WrapperProjectionExample.jl#L96) |
| The clipboard re-roots with a private closed copy (`_prefix_op`) of the kernel's open `reroot_operation`. | [Clipboard.jl:137](../../source/clipboard/Clipboard.jl#L137), [Rerooting.jl](../../source/kernel/operation/Rerooting.jl) |
| A clipboard paste writes over ANY selection, a text caret included. | `_clipboard_paste` |
| The pane verbs (`open_pane!`, `focus_pane!`) write the selection into the tree directly, not from the editor root. | [PaneSurgery.jl:159](../../source/pane/PaneSurgery.jl#L159) |
| The pane package does not depend on the clipboard package. Both depend on `ProjecturedDomain`, and so does the conversation package. | `package/*/Project.toml` |
| A tab strip reads its titles reactively through `get_pane_tab_title_string`. | [PaneToWidget.jl:342-346](../../source/pane/PaneToWidget.jl#L342-L346) |
| A closed plan proposed per-node `selectable`/`editable` flags and a gating projection. It is not the intended direction. | [selectable-editable-document-support.md](../done/selectable-editable-document-support.md) |

## 3. Decisions

### D1. What a selection names

A selection names a document, so that a paste puts a document into the tab and
the tab draws it again.

- **A tab whose content is a widget tree** (for example a view the assistant
  built from widgets): the selected widget is the document. Any widget can be
  selected.
- **A tab whose content is a domain document** (the runner, a set of runs, a
  result, a plot, a study, the conversation): the selection names the
  innermost domain document whose print holds the widget. A widget that shows
  no document of its own, such as a button or a header label, selects the
  document that encloses it.

A projection-induced reference could name the chrome widget itself. The plan
does not use it: a copy of chrome is not a document that the tab can draw
again, and it is not a document that the assistant can use.

In the transcript, these are the objects:

| The person points at | The object | Path in the conversation |
| --- | --- | --- |
| a message | `ConversationTurn` | `turns[i]` |
| a prose part, a code part, a thinking part | `ConversationPart` | `turns[i].parts[j]` |
| an evaluation (header and both sections) | the `ConversationPart` that holds the `EvaluatorForm` | `turns[i].parts[j]` |
| the code of an evaluation | the form document (`JuliaDocument`) | `turns[i].parts[j].content.form` |
| the result of an evaluation: a table, a plot, a form, any document | the result document | `turns[i].parts[j].content.result` |

The evaluation object is its part, because a part draws alone and a bare
`EvaluatorForm` does not. Prose stays not selectable by character.

### D2. How a person selects

1. **Alt+click** selects the innermost object under the pointer. A plain click
   still controls the widget: a button fires, a row is picked, a caret is put.
   Alt+click is already the whole-element gesture of the syntax domain, the
   table and the placeholder.
2. The transcript keeps its plain click, which names a part. It changes nothing.
3. **`Alt+Up`** selects the enclosing object. **`Alt+Down`** selects the first
   object inside. **`Alt+Left`** and **`Alt+Right`** select the previous and the
   next sibling. These are the meanings of the syntax walk. The syntax domain
   keeps its own walk, and the two charts change to the same meanings (D14).
   The pane layer keeps `Ctrl+Alt` + arrows.
4. An Alt+click never acts. A button does not fire, and a row is not picked.

### D3. The widget layer answers an Alt+click

A container routes an Alt+press to the child under the pointer, as it routes a
press now. It keeps the child's answer only when that answer is itself a
whole-element selection, for example a table cell. Otherwise it answers
`ReplaceSelectionOperation(EmptyReference())` for itself. So the innermost
widget wins, and a control never acts on an Alt+click, because its own answer
is not a whole-element selection and is dropped.

### D4. The selection shows on every widget

Every widget draws a selection ring while its selection is `EmptyReference()`,
and only then. There is no flag. The ring reads only the selection cell, as
`_push_focus_ring!` does, so a selection move repaints the ring alone. It uses
the table's selection color. A widget that already draws its own whole-element
look (`WidgetTable`) keeps that look and gets no ring.

The mechanism is chosen in Step 0. The preferred one is a single decorator
around the renderer's dispatch, which adds the ring element to every widget's
canvas. The other one is a helper call in each of the 41 printers, as
`_push_focus_ring!` is called now.

An object whose print is not a widget (a prose part prints as a stack of text
blocks) gets a host: a `:plain` card with zero padding, which draws nothing and
takes no space. **A tab with no whole-element selection must draw the same
pixels as before.** A test asserts it.

### D5. Each domain projection maps a widget selection back

A domain projection maps a widget whole-element selection back to the domain
object of D1, and a domain whole-element selection forward to the widget that
draws it. These projections in the IDE need it:

- the transcript (`ConversationToWidget`), with the objects of D1;
- the runner (`SimulationFilterToWidget`), a set of runs
  (`SimulationBatchToWidget`), a run (`SimulationToWidget`), a study
  (`StudyGraphics`);
- a result (`SimulationResultFrameToWidgetTable`: frame to table, table corner
  to frame) and a plot.

Step 0 lists the others that a tab of the IDE can hold. A projection that is
not on the list keeps its behavior: an Alt+click inside it selects the nearest
enclosing object that is mapped, at worst the tab.

### D6. A generic walk for the four `Alt` + arrows

A small stage in front of the IDE chain answers the four keys when no inner
reader answered them:

- `Alt+Up`: the nearest shorter prefix of the selection path that names a
  document. From a caret, this is the document that holds the caret.
- `Alt+Down`: the first document inside the selected document, in the order of
  its fields, and the first element of a vector.
- `Alt+Left` / `Alt+Right`: the previous / next sibling of the selected
  document. A sibling is the neighbouring element of the same vector, or the
  neighbouring document field of the same parent in the order of its fields.
  At the first or the last sibling the selection stays, as in the syntax walk.

`Alt+Left` and `Alt+Right` act only on a whole-element selection. With a caret
they answer `nothing`, so the key goes on and a text reader can use it later.

A domain answers `is_selection_walk_stop(document) = false` for a document
that only holds objects, and the walk passes through it (added in Step 7: the
assistant's pane hands the Alt arrows to its composer, so in the IDE the
generic walk, not the transcript's, walks a transcript, and it stopped on the
bare `EvaluatorForm`).

An inner reader answers first. So the syntax domain and the two charts answer
with their own walks, and the transcript answers with the object walk of D1, which skips
the bare `EvaluatorForm`. From the root of a tab's content, `Alt+Up` selects the
tab, which is the pane focus. `Alt+Down` from a tab selects its content. The
stage goes to the focus slice, which already walks child documents for `Tab`.

The pane layer answers the sideways keys in two places, because the generic
sibling of a tab's content is the tab's title, which is not an object of the
content:

- a whole tab: `Alt+Left` / `Alt+Right` focus the previous / next tab of its
  group, as `Ctrl+PageUp` / `Ctrl+PageDown` do;
- the root of a tab's content: the selection stays.

The two charts turn the arrows the other way (see §2). D14 changes them.

### D7. The IDE gets the clipboard

The IDE wraps the window content in a `ClipboardSlice` and puts the clipboard
stage in front of its chain. `make_clipboard_projection` moves out of the
example into a package that sees both `ProjecturedClipboard` and
`ProjecturedProjection`. The step reads
[package-rules.md](../../documentation/rule/package-rules.md) to choose it. The
gallery and the IDE both call it.

The IDE offers copy, note, paste and paste-copy. It does not offer cut in this
plan, and it does not offer the view toggle (`Ctrl+/`), because the toggle
puts the stored object in the place of the whole window.
`ClipboardSliceToAnyProjection` gets an `offered_gestures` keyword. Its default
is all six.

`get_window_tree` must find the tree under the wrapper. The pane package can
not name `ClipboardSlice`. So `get_window_tree(editor)` calls
`get_window_tree(first(windows).content)`, and a method
`get_window_tree(::ClipboardSlice)` goes in a package that depends on both.

### D8. A new tab selects its content

`Ctrl+T` and the `+` button put the selection on the placeholder:
`tabs[k].content` with the whole-element tail. The pane focus already reads a
path that goes into a tab's content, because a click in content makes one. A
tab that `open_pane!` opens with a real document keeps today's cursor.

The IDE draws the placeholder as a hint ("empty — Ctrl+V pastes here") with the
selection ring. This is an IDE renderer entry for `DocumentNothing`, not a
change to `NaturalToGraphics`.

### D9. The paste rules, and how the conversation and the tool panes refuse a paste

**Why the transcript reader can not refuse it.** The clipboard stage sits in
front of the transcript. The transcript reader sees `Ctrl+V` first, but a
reader can only answer an operation or `nothing`, and `nothing` means "not
mine". The clipboard answers its own gesture in either case, and the editor
applies that write directly. No reader below sees it.

**So a domain type states a fact about its document, and the clipboard honors
it.** A new predicate `accepts_pasted_document(document)` in
`ProjecturedDomain` answers `true` by default. It answers `false` for a document
that a paste must not replace, and must not change inside:

| Document | Why it refuses | Declared in |
| --- | --- | --- |
| `ConversationConversation` | the history is a record | the conversation slice |
| `Assistant` | a tool pane: the conversation, the draft and the settings | the assistant slice |
| `SimulationFilter` | a tool pane: the runner | omnet |

The predicate does not say "read-only". A person types into the runner form and
into the draft, and those edits come from their own readers, which the
predicate does not touch. It speaks only to a pasted document. The composer's
own text paste is not a pasted document, so it still works.

Step 0 lists the other documents that a tab of the IDE can hold. The same test
decides each one: a document that drives something live (a set of runs, a
running simulation) is a tool pane and refuses. A result, a plot, a widget
view, a pasted object and the placeholder accept.

A paste (and a cut, where it is offered) is refused unless all three rules
hold:

1. **The target is a whole-element selection of a document**, not a caret and
   not a range. A caret in the composer therefore falls through, and the
   composer's own `Ctrl+V` pastes text.
2. **Every document from the clipboard's content down to the target accepts a
   pasted document.** A target in the conversation, the whole conversation,
   the whole assistant, the runner and anything inside them are refused.
3. **The target's slot accepts the pasted document.** A field cell whose value
   type the document is not, or an immutable cell, refuses. And the document in
   the slot must accept the pasted one as its replacement:
   `accepts_pasted_replacement(document, value)`, `true` by default. The pane
   slice answers `false` for a pane on either side, so a paste never replaces a
   tab, a group or a split, and a pane is never pasted. Without this rule a
   paste with the normal pane focus — a whole tab — replaced the `PaneTab` in
   its group's list with a table (found in Step 7).

A refused paste answers `nothing`, so the key goes on to the content. The IDE
passes no rule of its own.

This is not the closed gating plan. That plan filtered every operation of a
subtree through a projection policy. This one is one fact that a domain type
states, read by the one writer that sits in front of the readers.

**A record or a tool is neither copied, noted nor pasted** (decided in Step 7;
the first decision allowed a copy and a note). A copy made by `copy_document`
keeps what a tool holds by reference: the runner's `runner` handle and `cache`,
the assistant's model session. A pasted copy would then start runs or turns of
the original, and a deep copy of the assistant follows the draft's back-link to
the assistant and overflows the stack. A second tool is the work of a duplicate
with a copy policy ([duplicate-a-pane.md](duplicate-a-pane.md)), not of a paste.
So `_find_paste_target` refuses such a value, and copy and note refuse such a
document (`_is_clipboard_value`). What a record or a tool holds — a message, a
result, a parameter — is copied and noted as any other document.

### D10. The clipboard reads the selection from its content

A pane verb writes the tree's selection directly (see §2), so the wrapper's own
`selection` cell can hold an old path. The clipboard therefore names the
selected object from `input.content`'s selection, with the `content` step put
in front.

### D11. The clipboard re-roots with the kernel generic

`_prefix_op` is deleted. The clipboard calls `reroot_operation`, which is open,
so every operation type that has a method re-roots correctly under the wrapper.
`MoveRangeOperation` needs no method: it carries its vectors.

### D12. What a note means (accepted)

A note puts ONE document in two places. Each consequence gets a test:

- A change to the object shows in both views. A row pick in the tab also shows
  in the transcript.
- The object keeps one `selection` cell, so both views draw its ring. When the
  selection moves away, both rings go. The test checks both orders of
  `_sync_selection!`: clear the old branch first, and set the new one first.
- A saved window writes the object twice. After a load the two are copies. The
  guide says so.

### D13. The tab takes the name of the pasted object (only if simple)

A new tab gets an empty title. `get_pane_tab_title_string` shows an empty title
as `get_document_title(content)`, and as "untitled" when that answers
`nothing`. `F2` still writes a real title. The name never comes from
`describe_document`, because that names the document's state, and a tab must
not rename itself while its content changes.

This is a change to one function and to the default tab. If `show_layout`, the
unique-title search or an omnet caller needs more than the same function, skip
D13 and write the reason here.

### D14. The two charts follow the syntax walk

The chart and the sequence chart change their `Alt` + arrows to the meanings of
D2:

| Key | Now | After |
| --- | --- | --- |
| `Alt+Up` | the previous part | the whole chart |
| `Alt+Down` | the next part | the first part |
| `Alt+Left` | the whole chart | the previous part |
| `Alt+Right` | the first part | the next part |

Each key keeps today's rule for the case where it does not apply: with the whole
chart selected, `Alt+Up`, `Alt+Left` and `Alt+Right` answer `nothing`, so a
walk above can answer. `Ctrl+Alt+Home`, the plain arrows and the `Ctrl` arrows
of the sequence chart do not change.

## 4. Steps

Each step works in a worktree, commits when its tests pass, and marks itself
done here. Run only the tests that each step names.

### Step 0 — baselines and probes

- [x] **Done 2026-09-17** at `b2219baa`, in one process from
      `environment/all`. All pass, with no fail and no error: conversation 96,
      clipboard 102, widget_card_fold 22, pane_surgery 79, pane_geometry 35,
      pane_to_widget 44, pane_reader 32, pane_gestures 42, pane_drag 251,
      pane_rename 19, pane_construct 45, chart 339, sequencechart 270. The omnet
      counts are taken in Step 6, from the omnet worktree.
      Record the counts of these suites on clean main: `test_conversation()`,
      `test_clipboard()`, `test_widget_card_fold()`, `test_chart()`,
      `test_sequencechart()`, the eight pane tests
      (`test_pane_surgery`, `test_pane_geometry`, `test_pane_to_widget`,
      `test_pane_reader`, `test_pane_gestures`, `test_pane_drag`,
      `test_pane_rename`, `test_pane_construct`), and omnet
      `test_result_views()`, `test_result_verbs()` and the test of each runner
      projection of D5.
- [x] Probe: when a document's selection names an object whole, what does the
      selection cell of the widget that draws it hold after a print? D4 needs
      `EmptyReference()` there. If the chain does not write widget selection
      cells, each projection of D5 sets them with `set_cell_function!`, as
      `AssistantToWidget.jl` does.
      **Answer:** the chain writes no widget selection cell. With the
      conversation's selection at `turns[1]`, the transcript's layout and both
      turn cards hold `nothing`, while `map_reference_forward` answers
      `.children[1]`. So Step 4 wires the transcript's containers with
      `set_cell_function!`, as `PaneToWidget` does with `_forward_selection!`.
- [x] Probe: can one decorator add the ring element to every widget canvas
      (D4)? A canvas whose elements are a computed vector can refuse it. Write
      the choice here.
      **Answer: no decorator.** A decorator at the renderer's dispatch would
      wrap the IO map of every child, and several readers find a child IO map
      by its type (`_find_fold_operation`, the pane reader). The ring is drawn
      by the container instead: every layout, the composite and the card keep
      one ring at the end of their element list. The ring covers the child
      that the container's OWN selection names as a whole (`children[i]`,
      `elements[i]`, `content`). That works for a widget child and for an
      embedded document child alike, and it never reads the child's cell.
- [ ] Probe: does an Alt+press reach the editor through the SDL backend on this
      desktop, or does the window manager take it? It needs a live window and a
      person; it is not done.
- [x] List every document type that a tab of the IDE can hold, and its
      projection. Mark which ones D5 covers, and which ones are tool panes
      that refuse a paste (D9).

      | Tab content | Projection | Maps references | Tool pane (refuses a paste) |
      | --- | --- | --- | --- |
      | `SimulationFilter` (the runner) | `SimulationFilterToWidgetForm` | yes | yes |
      | `Assistant` | `AssistantToWidgetSplitPane` | yes | yes |
      | `SimulationBatchDocument` (a set of runs) | `build_campaign_graphics_entry` | no | yes: a process pool |
      | `StudyStudy` | `StudyStudyToWidget` | no | yes: it holds live runs |
      | `SimulationResultFrame` | `SimulationResultFrameToWidgetTable` | no | no |
      | `ResultTableView` | `ResultTableViewToSimulationResultFrame`, then the frame | no | no |
      | `SimulationPlotDocument` | `SimulationPlotToGraphics` | no | no |
      | `DocumentNothing` (the placeholder) | `PhraseToGraphics` | no | no |
      | a widget or layout tree | the widget and layout renderer | yes | no |

      A projection that maps no reference makes the pane the floor: an
      Alt+click inside it selects the tab's content as a whole (Step 5).

### Step 1 — Alt+click and the ring (projectured, focus, graphics, layout and widget slices)

- [x] The Alt+press rule of D3 in every container, and in the leaves through
      one shared rule.
      **Done 2026-09-17.** The focus slice holds the rule
      (`WholeSelection.jl`: `is_whole_selection_press`, `is_whole_selection`,
      `convert_to_whole_selection`, `find_whole_selected_index`,
      `is_whole_selected_field`), because both the layout and the widget
      packages see it. The layout slice holds `read_child_event`: every router
      that hands a press to a child calls it in place of the child's reader —
      the layouts, the composite, the split pane, the tabbed pane, the scroll
      pane, the transform pane, the dialog and the card. The leaves need no
      change: a leaf's answer is dropped by its container.
- [x] The ring of D4.
      **Done 2026-09-17.** `make_selection_ring` is in the graphics slice,
      because the layout package does not see the style package.
      `make_layout_selection_ring` serves the horizontal, vertical, grid, flow,
      constraint and anchored layouts; the composite and the card build theirs
      in `WidgetToGraphics.jl`. At rest the ring has no size and no border. A
      child that takes the focus (`is_focusable_document`) gets no ring,
      because a control draws its own focus ring when it is selected; without
      that rule a selected button drew two rings. The stack layout lists only
      its visible children, so its entries do not follow the child index; it
      has no ring yet.
- [x] Tests: a new `test_widget_selection()`. It presses real pixels: an
      Alt+click on a button selects it and does not fire it; an Alt+click on a
      widget in a card in a composite selects the innermost one; an Alt+click
      on a table cell keeps the cell selection; the ring pixels appear and go
      away; a tree with no whole-element selection draws the same pixels as on
      main.
      **Done 2026-09-17: 43 pass.** The "same pixels" check is that every ring
      at rest has no size and no border, which both backends skip. A plain
      press in a `WidgetText` that has no focus answers nothing, so the caret
      case is a unit test of the helpers. The table cell case is covered by
      the rule (a whole selection inside a child is kept), and by the table's
      own tests. The 13 suites of Step 0 keep their counts.

### Step 2 — the `Alt` + arrows walk (projectured, focus and pane slices)

- [x] The stage of D6, with a name that follows
      [naming-rules.md](../../documentation/rule/naming-rules.md).
      **Done 2026-09-17:** `SelectionWalkingProjection` and
      `compute_selection_walk` in `source/focus/SelectionWalking.jl`. The walk
      reuses the focus slice's `_child_document_refs`. An object is a document
      that is not a collection and whose `selection` cell is not an
      `ImmutableCell{Nothing}`: that is how a value document (a color, a font,
      a text style) declares that it holds no selection, so the walk never
      stops on one. A plain struct such as `Point2D` is not a document at all.
- [x] The two pane answers of D6: a whole tab moves to its neighbour tab, and
      the root of a tab's content stays.
      **Done 2026-09-17:** `_walk_tab` in the `@gestures PaneTree` table, and
      `get_pane_content_path` in `PaneSurgery.jl`. A whole tab also stays on
      `Alt+Up` and goes to its content, not its title, on `Alt+Down`. The pane
      table runs only for a key that the content did not answer, so a syntax
      tab keeps its own walk.
- [x] Tests: all four keys over a widget tree and over a pane tree; a vector
      sibling and a field sibling; the first and the last sibling stay;
      `Alt+Left` with a caret answers `nothing`; an inner reader that answers
      first keeps its answer (a syntax tree and a chart in a tab).
      **Done 2026-09-17:** `test_selection_walking()`, 29 pass, with a stub
      inner reader in place of a syntax tree; `test_pane_gestures()`, 52 pass
      (42 before). The chart case is in Step 2b.

### Step 2b — the two charts follow the syntax walk (projectured, chart and sequencechart slices)

- [x] Change the four `Alt` + arrow bindings of both `@gestures` tables (D14).
      The gesture help text follows from the table.
      **Done 2026-09-17.** `_step_part` answers `nothing` at the first and the
      last part. With a walk around the chart, `nothing` would let the generic
      walk move the selection to another field of the chart, so at an end the
      chart answers its own selection and keeps it, as the syntax walk does.
- [x] Tests: the assertions of `test_chart_projection()`
      ([ChartProjectionTest.jl:1113-1123](../../test/chart/projection/ChartProjectionTest.jl#L1113-L1123))
      change to the new keys. `test_sequencechart_selection()` gets the same
      four assertions. `test_chart()` and `test_sequencechart()` keep their
      other counts.
      **Done 2026-09-17:** the two suites pass together, 624 (609 before).

### Step 3 — the paste rules and the clipboard (projectured, domain and clipboard slices)

- [x] `accepts_pasted_document` in `ProjecturedDomain` (D9).
      **Done 2026-09-17**, in `DocumentCore.jl`.
- [x] The three paste rules of D9.
      **Done 2026-09-17:** `_find_paste_target` in `Clipboard.jl`. Paste,
      paste-copy and cut use it, and the paste from the host's clipboard too.
      Rule 3 reads the value type of the slot's own cell
      (`AbstractCell{T}`), and an `ImmutableCell` takes nothing; an element
      of a vector takes any document. The kernel keeps the declared field
      types in the private `_declared_value_types`, and the plan does not
      open it, because another session changes the same kernel files.
- [x] Read the selection from the content (D10).
      **Done 2026-09-17:** `_get_clipboard_selection`. The clipboard's own
      cell decides only when it names a field other than `content`.
- [x] Replace `_prefix_op` with `reroot_operation` (D11).
- [x] Add `offered_gestures` (D7).
      **Done 2026-09-17**, with `CLIPBOARD_GESTURES` naming the six.
- [x] Move `make_clipboard_projection` out of the example (D7).
      **Done 2026-09-17:** `ClipboardWrapper.jl` holds it and
      `make_clipboard_document`, as `DraggingWrapper.jl` does for dragging.
      `ProjecturedClipboard` now depends on `ProjecturedProjection`, and
      `environment/all/Manifest.toml` is resolved. The workbench example
      re-exports both for the gallery.
- [x] Tests, in `test_clipboard()`: each rule refuses and then falls through to
      the content; a caret paste reaches the content; each gesture of
      `offered_gestures` is on and off; a pane edit under a wrapper re-roots; a
      copy after a direct write to the content's selection copies the right
      object.
      **Done 2026-09-17: 135 pass** (102 before). `test_command_palette_decorator`
      and `test_gesture_help`, which build the wrapper, pass (105).

### Step 4 — objects in the transcript (projectured, conversation and assistant slices)

- [x] `accepts_pasted_document(::ConversationConversation) = false`, and
      `accepts_pasted_document(::Assistant) = false` in the assistant slice.
- [x] The objects of D1, and the mapping below the part: `content.form` and
      `content.result` to the widget paths of the two section bodies, and back.
      Any path from inside a section body maps back to the section's object.
- [x] ~~A plain host card for a prose part and for each result (D4).~~
      **Not needed.** Step 1 put the ring in the container, so the turn's body
      layout rings a whole part, whatever the part prints, and a section card
      rings its content, which is the form or the result. The transcript draws
      no new card.
- [x] The object walk for the four keys. `Alt+Left` / `Alt+Right` move from a
      message to the previous / next message, from a part to the previous /
      next part of its message, and between the code and the result of an
      evaluation.
- [x] The fold reader works for a turn or a part that is the root of a tab.
- [x] Tests, in `test_conversation_transcript()`: each object of D1 is
      selected by an Alt+click and by the walk with all four keys; the walk
      stays at the first and the last message; the ring shows on that object;
      an unselected transcript draws the same pixels as on main; an Alt+click
      in a result writes nothing; a paste over each object is refused.

**Done 2026-09-17.** What the step found and decided:

- **The containers follow the node's selection.** `_follow_selection!` wires
  the conversation's layout, a turn's card and body, and an evaluation's card,
  body and two section cards: each holds the node's selection mapped forward,
  less the steps that lead to it. A section card then holds `content` when its
  section is selected, and draws the ring over the form or the result.
- **A plain click still names at most a part.** A four-argument reader on the
  conversation truncates a plain press's answer to `turns[i].parts[j]`, so
  the scan test of plain clicks keeps its six parts. An Alt+press keeps the
  innermost object.
- **A bug the Alt+click showed.** `_backward_level` skipped the first step of
  a turn's path without checking it. An Alt+click on a turn's header answers
  `title.children[k]`, which was read as part `k`. The level now checks that
  the skipped steps are `content`, and the header names the message.
- **The transcript answers the four keys itself**, whatever a widget inside
  said, because nothing in a read-only transcript has a use for them.
  `compute_transcript_walk` walks messages, parts and the two sections; from a
  message, up is the conversation as a whole, and from there the walk around
  the transcript takes over.
- The conversation package depends on `ProjecturedFocus` now, for the gesture
  tests, and imports the intent module.
- **Counts:** `test_conversation_transcript()` 113 (51 before);
  `test_conversation()` 158 (96 before).

### Step 5 — the new tab and the page (projectured, pane and widget slices)

- [x] `Ctrl+T` and the `+` button select the placeholder (D8). A split that
      opens a new tab does the same.
- [x] `get_window_tree` finds a tree under a wrapper (D7).
- [x] Tests: the eight pane tests keep their counts, except the assertions on
      the new-tab cursor, which change to the new path. `F2`, `Ctrl+W` and
      `Ctrl+PageDown` still act on a tab whose placeholder holds the selection.

**Done 2026-09-17.** What the step found and decided:

- **The cursor of a new tab** is built by `_make_new_tab_cursor`: the tab's
  content when it is the placeholder, the tab otherwise. `open_pane!` opens a
  real document, so its cursor stays on the tab. No existing pane assertion
  named the new-tab cursor, so none changed.
- **The tree under a wrapper.** `get_window_tree(::ClipboardSlice)` unwraps,
  and `get_window_tree(editor)` asks the window's content. The pane package now
  depends on `ProjecturedClipboard` and `ProjecturedFocus`.
- **An Alt+click on a page.** The tabbed pane now adds the page's `element`
  step to a whole-page answer, so it differs from a click on the tab strip. The
  pane tree's reader then turns an Alt+click inside a page whose answer is not
  a whole document — the tab, a caret, or a place the content's projection
  introduced — into the tab's content as a whole (`_select_page_content`).
  This is the floor of D5: any tab content can be selected, whatever its
  projection maps.
- **The ring over a page.** The tabbed pane rings its page while the page's
  document holds a whole-element selection. That document is in the tree, so
  the editor writes its selection cell. A noted object in two places rings in
  both, as D12 accepts.
- **A lie the ring showed.** The pane tree's root composite held the constant
  selection `elements[1]` only to route keys, and the ring rule read it as
  "the pane layer, selected whole": every window was ringed. The composite now
  names the layer whole only when the tree's root is selected whole, and
  otherwise holds the image of the root's own step — the prefix that names a
  split's element or a group's tab. Only that prefix is forwarded: the pane
  group's forward map refuses a deep caret path that carries no node types,
  which a first version that forwarded the whole selection met in the
  campaign suite's typed number field (Step 6).
- **Counts:** `test_pane_reader()` 41 (32 before); `test_pane_gestures()` 60
  (42 before, 52 after Step 2). The ten suites of Step 1 keep the baseline's
  failures and no other: substrate 62295 pass, 3 fail, 2 error, 1 broken (the
  split-pane drag test); workbench 108 pass, 3 fail, 2 error (the assistant
  and tab-strip scroll tests).

### Step 6 — the IDE and its projections (omnet)

- [x] ~~`build_campaign_projection` puts the clipboard stage (copy, note, paste,
      paste-copy) and the walk stage in front of the chain.~~
      **Changed:** `make_ide_window_wrap` does it. The window takes its layers
      from that fold (`run_campaign_window(...; wrap)`), which another session
      added while this plan was written, so the campaign window alone stays as
      it is. The fold has a `selection` flag, on by default: the walk wraps the
      projection, the clipboard wraps the walk and the document, and the help,
      the palette and the log go over them, in the gallery's order.
- [x] ~~`run_campaign_window` wraps `session.tree` in a `ClipboardSlice`.~~ The
      same fold wraps the document. `get_window_tree` finds the tree inside it.
- [x] ~~A renderer entry for `DocumentNothing` draws the hint (D8).~~
      **Dropped.** A renderer row is registered for the whole session, so every
      window would say "Ctrl+V pastes here", a window without a clipboard too.
      The ring on the empty page already shows where a paste goes, and the
      greeting names the keys.
- [x] `accepts_pasted_document(::SimulationFilter) = false`, and the same for
      each tool pane that Step 0 found (D9): `SimulationBatchDocument` and
      `StudyStudy`.
- [x] The mappings of D5 for the runner, a set of runs, a run, a study, a
      result and a plot.
      **Done as a floor, plus one rule.** Step 5 gives every tab content a
      floor: an Alt+click that names no whole document selects the content.
      The runner adds one rule: an Alt+click on a parameter box names the whole
      parameter, where its map answers a caret. A set of runs, a run, a study,
      a result and a plot are selected as a whole; a table inside a pasted result
      rings through its tab's page.
- [x] The greeting names the selection keys when the window has them.
- [x] Tests: the suites of Step 0 keep their counts. A new test per projection
      selects its objects by an Alt+click and shows the ring.
      **Done 2026-09-17**, measured in two throwaway environments: omnet main
      with projectured main, and the two worktrees. Both give campaign 148,
      window wrap 22, result views 33, result verbs 63, runner filter 35, study
      presentation 20, with no failure. The projections are tested through the
      window in Step 7 rather than one by one.

### Step 7 — the whole gesture, end to end (omnet)

`test_select_and_paste()` in `test/ide/IdeSelectAndPasteTest.jl` drives the
window as `run_omnet_ide` builds it, through the editor loop and a headless
backend, and finds every press point by the text it draws.

- [x] A result table in the transcript: Alt+click, see the ring, `Ctrl+C`,
      `Ctrl+T` (the placeholder shows the ring), `Ctrl+V`. The new tab draws a
      table, its document is not the transcript's, and the transcript is
      unchanged.
- [x] The same with `Ctrl+N`. The tab's document IS the transcript's. A row
      pick in the tab shows in both views, because it is one object; the test
      asserts the identity.
- [x] The walk under the real chain: from the table, `Alt+Up` reaches the
      part, the message, the conversation and the assistant, and `Alt+Left`
      the previous message. Copying a message or a part is covered by
      `test_conversation_transcript()`.
- [x] The code of an evaluation, pasted: the tab holds a copy of the form's
      document and draws it.
- [x] A widget of the runner: an Alt+click on Run selects the runner as a whole
      and starts no set of runs.
- [x] A widget view built from widgets: an Alt+click selects one widget, and it
      pastes.
- [x] Refusals: a paste over a transcript object, over a whole tab, over the
      assistant and over the runner writes nothing. ~~`Ctrl+V` with the caret in
      the composer pastes text~~: a headless press can not place the composer's
      caret; the rule that makes it work — a caret is not a paste target — is
      tested in `test_clipboard()`.
- [x] ~~A copy of the whole assistant pastes into a new tab and starts no second
      model session.~~ **Changed:** a copy of a tool is never pasted (D9). The
      test copies the whole assistant and finds the paste refused.
- [x] `focus_pane!` from the assistant API, then the clipboard names the object
      that the focus names.
- [ ] Measure one copy of a large `SimulationResultFrame`, and write the time
      here. **Not done:** a timing needs an idle machine and the user's word.

**Found by this step, and fixed in projectured** (commits after Step 5):

- A paste with the normal pane focus — a whole tab — replaced the `PaneTab` in
  its group's list. `accepts_pasted_replacement` and the pane's refusal fix it.
- A noted object that had lost the focus held a dormant selection, and the
  kernel's `replace_document` failed on it. It now carries only a live one.
- The pane composite forwarded the whole selection, which the group's forward
  map refuses for a deep untyped path; it forwards the root's step only.
- An Alt+click inside a widget page lost its answer: the tabbed pane spells a
  widget page's path without the `element` step, so the answer did not resolve,
  and the container replaced it. A container now keeps an answer that does not
  resolve, and replaces only one that names a value rather than a document.
- **Count:** 36 pass before the walk and the tool-paste cases were added.

### Step 8 — the tab name (only if simple)

- [x] D13, or the reason to skip it.
      **Done 2026-09-17:** `default_new_pane_tab()` has an empty name, and
      `get_pane_tab_title_string` answers the content's `get_document_title`
      for an empty name, and "untitled" when there is none. Two functions in
      `PaneDocument.jl`; `show_layout` and the unique-title search already read
      the same function.
- [x] Test: a pasted table names its tab; `F2` still renames it; a tab whose
      content changes state keeps its name.
      **Done:** `test_pane_gestures()` names an empty tab after a titled
      content, keeps a name of its own, and falls back to "untitled";
      `test_pane_rename()` still renames a fresh tab. A widget table has no
      title, so the pasted table of Step 7 keeps "untitled".

### Step 9 — guides, and close

- [x] [widget.md](../../documentation/package/widget/widget.md): Alt+click, the
      ring, the rule of D3, and the four `Alt` + arrows.
- [x] The chart and sequence chart guides in
      [documentation/package/](../../documentation/package/): the new `Alt` +
      arrows (D14). The sequence chart guide names no `Alt` key, so only the
      chart guide changed.
- [x] [transcript.md](../../documentation/package/conversation/transcript.md):
      the objects, the walk, the history that refuses a paste. Remove the claim that
      `Ctrl+C` copies a part in every host.
- [x] [pane.md](../../documentation/package/pane/pane.md): the new-tab
      selection, the tree under a wrapper, the tab name, and `Alt+Left` /
      `Alt+Right` on a whole tab.
- [x] The clipboard guide or its module docstring: the three paste rules and
      `offered_gestures`. There is no clipboard guide; the docstrings of
      `ClipboardSliceToAnyProjection`, `_find_paste_target` and
      `make_clipboard_projection` carry them.
- [x] omnet
      [assistant-guide.md](../../../omnet-julia/documentation/guide/assistant-guide.md):
      select, copy and note into a tab, and what a note shares.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

- **The window manager takes Alt+click.** Some Linux desktops move a window on
  Alt+drag. Step 0 probes it. The gesture is already in use, so a change of
  modifier is a separate decision for the user.
- **The unselected pixels change.** A ring element or a host card can shift a
  widget by a pixel. The pixel tests of Steps 1 and 4 catch it.
- **The ring changes hit-testing.** A full-size ring over a selected widget is a
  drawn element, and containers route by drawn elements. Step 1 tests a plain
  click on a selected widget.
- **The chart keys change for people who know them.** D14 turns four keys of
  the two charts. The chart guides say so.
- **A copy of a live tool.** `copy_document` of an `Assistant` or a runner can
  copy a value that belongs to a live session. Step 7 tests it (D9).
- **Many projections need D5.** The list of Step 0 can be long. A projection
  left out still works, and selects a larger object.
- **The new-tab selection breaks a pane assertion.** Step 5 changes only the
  assertions that name the new-tab cursor. Any other count that moves is a
  regression.
- **The IDE's key routing changes under the two new stages.** A key that they
  do not take must reach the pane and the composer as before. Step 6 runs the
  pane gestures through the wrapped chain.
- **The flat-transcript plan changes the same printer.** If
  [conversation-flat-transcript.md](conversation-flat-transcript.md) lands first,
  Step 4 builds on its printer.
- **A large result is slow to copy.** `copy_document` walks every cell. Step 7
  measures it.

## 6. Out of scope

- A selection of characters, or of a range, in prose.
- Cut. The three paste rules already make it safe, so a later change can turn it
  on.
- A text form of an object on the OS clipboard (for example a table as
  tab-separated text). The `to_text` keyword already makes it possible later.
- A paste by a drop, or into a split.
- The assistant's own writes (`replace_referenced_value!`). They do not read
  `accepts_pasted_document`.
- A second selected object (multi-selection).
