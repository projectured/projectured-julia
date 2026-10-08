# Focus

> **Kind:** design · **Status:** current · **Stands on:** [selection.md](../../kernel/selection.md), [reference.md](../../kernel/reference.md)

The focus slice of `ProjecturedPlatform` holds the functions that make the selection act as the focus. They are the walk that Tab follows, the rule that gives the focus to a pressed control, the Alt+press rule that selects a whole object, the Alt+arrow walk, and a step that names a drawn widget. It has no document type and names no widget type. This document says what each function computes, which slice applies it, and where the traps are.

## How it works

**Focus is the selection.** No document has a `focused` field. A key goes to the document that the selection names, because each container gives a key only to the child that its own `selection` names; [widget.md](../widget/widget.md#a-key-goes-by-selection) and [layout.md](../layout/layout.md#events) describe the routing. So to move the focus is to write the selection, and this package computes where the selection goes.

### The Tab walk

`is_focusable_document(node)` is `false` by default. A domain adds a method for the documents that Tab can land on. The widget package answers `true` for the enabled controls of its `FocusableWidget` union.

`get_first_focusable_path(node)` and `get_last_focusable_path(node)` walk the subtree depth first and return the relative path to the first or last focusable document, or `nothing`. The path is a whole-element path, so it ends at the document. The walk visits the children in field order: each element of a `CellVector` field, and each field that holds a `Document`, except `selection`. `get_next_focusable_index(children, after, reverse)` returns the next slot whose subtree holds a focusable document, or `0`.

The walk keeps a set of the `objectid` of each node that it visited. A `ListNode` has `prev` and `next`, and both hold documents, so a walk without the set goes from `next` to `prev` and back until the stack overflows. Text and syntax content embed a `ListNode`, so a Tab in a file tab or in the assistant needs the set. A tree without a cycle visits each node once in both cases.

The containers apply the walk. A layout, a `WidgetComposite` and a `WidgetSplitPane` give Tab to the selected child first. When the child returns `nothing`, the container selects the first focusable document of the next sibling. At the end of the tree every container returns `nothing`, and `FocusCyclingProjection` starts over: it selects the first focusable document of its input, or the last one for Shift+Tab. It is a transparent wrapper, as `SelectionWalkingProjection` is, and it answers only a Tab that nothing inside answered.

### A press gives the focus

- `is_focusing_press(event)` is `true` for a left `MouseDown` with no modifier.
- `convert_to_focus_selection(operation, child)` is the answer of a container for such a down that hit `child`, where `operation` is the answer of `child`. A focusable `child` that answered `nothing` and holds no selection gets `ReplaceSelectionOperation` of itself as a whole, the selection that Tab gives it. Every other answer is kept.

The focus moves on the down, and a control acts on the press that a gesture tracking projection makes after the up. So the move of the focus is an operation of its own, and a projection that can not map it drops only the move. A control that answers the down itself keeps its answer, so it does not take the focus from a press. The rule is applied in `read_child_event`, with the Alt+press rule below.

### The whole-element selection

A whole-element selection is a path that ends at a document. A caret and a range of text end inside a document, so they are not whole. Any document can be selected whole, and no document declares that it can be.

- `is_whole_selection_press(event)` is `true` for a left `MouseClick` with Alt and no other modifier. A plain press keeps its meaning, so a button still fires and a caret still lands.
- `is_whole_selection(document, reference)` is `true` when the reference evaluates, inside `document`, to a `Document`.
- `convert_to_whole_selection(operation, child)` is the answer of a container for an Alt+press that hit `child`, where `operation` is the answer of `child`.

`convert_to_whole_selection` keeps a `ReplaceSelectionOperation` whose path evaluates to a document inside `child`, so the innermost object under the pointer wins. It also keeps a path that does not evaluate in `child`, because a container can answer in its own terms, and the level above maps the path back. Every other answer becomes the whole selection of `child`: `nothing`, a caret, or the action of a control. So an Alt+press never acts. Before the test, the function cuts a path at its first `ProjectionReferenceStep`: a place that a projection introduced, such as a bracket, then selects the node that the bracket was printed for.

The rule is applied in one place: `read_child_event` in `source/platform/layout/LayoutToGraphics.jl`. Every layout and every widget container calls it to give a press or a down to a child, so this package only gives the functions. The pane package adds one more rule for a page; see [pane.md](../pane/pane.md#selecting-inside-a-page).

`find_whole_selected_index(selection, field)` and `is_whole_selected_field(selection, field)` read which child a selection names as a whole. A container uses them to draw its selection ring.

### The Alt+arrow walk

`SelectionWalkingProjection(; inner)` prints as `inner` and maps references as `inner`. Its reader gives each event to `inner` first. Only an Alt+arrow key that `inner` returns `nothing` for goes to `compute_selection_walk(document, selection, direction)`:

- `:up` selects the nearest enclosing object, also from a caret.
- `:down` selects the first object inside the selected one.
- `:left` and `:right` select the previous or next object of the same parent. At the first and the last one, the selection stays.

`:down`, `:left` and `:right` need a whole selection and return `nothing` for a caret, so a text reader can use the keys while a person edits. An object is a document that is not a collection and that can hold a selection, so a value such as a color is not one. `is_selection_walk_stop(document)` is `true` by default. A domain answers `false` for a document that only holds the objects that a person points at, and the walk goes through it. The form of the evaluator in the conversation package does this.

### A widget that a projection drew

A projection can draw a widget that no document of the domain stands behind, such as the table of a form. No field or index reaches such a widget. `OutputReferenceStep(owner, node, output_path)` is a step that holds the widget itself and its place in the output. It evaluates to `node`, but only from `owner`; from another document it throws. So a copy, a note and `is_whole_selection` reach the widget, and a paste never writes through it.

`make_output_reference(owner, node, output_path)` makes the typed path. `find_output_path(reference, owner)` returns the place in the output. `follow_output_selection!(root, forward; is_followed)` installs a thunk on the `selection` cell of each document of the output tree, so each container holds its part of the path and rings the child that the path names. `is_followed` stops the walk at a document of the domain inside a widget. With `forward_mouse_target`, the walk also installs a thunk on the `mouse_target` cell of each document. `follow_output_mouse_target!(root, forward; is_followed)` does that alone, for a view that keeps the selection of its output in its own way: each widget that the view makes then lights while the pointer is on it.

The walk does not go along a lazy list (`ListNode`), such as the rows of a table that a viewport builds as it reaches them: a walk of every node would build every row. A path counts into such a list from its head, and the part under the pointer is in the window, near the head. So the list gets one rule, a computed cell: from the path, step from the head that the holder of the list holds now, a node at a time with `find_list_node`, to the node that the path names, and answer that node with the part of the path inside it. Each node takes its part from that rule, so the node that the pointer left loses its part. The walk follows the nodes that are built already, and it puts a computation around each link that has not built its node yet, and around a holder that computes its head (`get_cell_computation`): when the link or the holder builds a node, the walk follows that node, with `run_untracked`, so the link does not compute again when a part of the node changes. A table that scrolls writes a new head into its holder, and the rule counts from that head. A pane of 20,000 tasks so builds only the rows of its window.

A view can also put a document of its input whole into its output, as a scroll pane of the view shows it, while a later view draws that document. A path through that document has a pre-image, so the view maps it with `map_held_node_forward(output, node, reference)` and `map_held_node_backward(output, node, reference)`: forward, the path to the node in the output goes before the path of the node; backward, the rest of the path after the node is the answer. `find_output_node_path(root, node)` finds the path to the node by identity through the child documents. So the part under the pointer reaches the document, and the later view finds its own part in it. The walk of `follow_output_mouse_target!` stays out of that document with `is_followed`, because the chain write holds its mouse target.

### The `focus_cycling` wrapper of `build_editor`

`focus_cycling = true` is the wrapper of `build_editor` that wraps the projection of a window in a `FocusCyclingProjection`, so Tab and Shift+Tab start over at the ends of the window. It is on by default, in every window, and a caller turns it off with `focus_cycling = false`. It acts in the layer `:container` with the number 20, around the chrome of the `shell` wrapper, so the cycle goes through the bands and the panes.

## How it fits

The five files of `source/platform/focus/` hold the parts above: `Focus.jl` the Tab walk and the press that gives the focus, `FocusCycling.jl` the start over at the ends, `WholeSelection.jl`, `SelectionWalking.jl` and `OutputSelection.jl`. The focus slice depends only on the kernel and on the collection slice. The layout and widget slices call the Tab walk and the whole-element functions. The clipboard slice puts a `SelectionWalkingProjection` around the window when its `clipboard` wrapper of `build_editor` is on; see [clipboard.md](../clipboard/clipboard.md). It registers nothing. A domain extends it through two open functions, `is_focusable_document` and `is_selection_walk_stop`.

## Design decisions

- **Focus is the selection.** A second focus field would have to agree with the selection after every edit, and a key would have two places to go. See [plan/done/widget-focus-traversal.md](../../../../plan/done/widget-focus-traversal.md).
- **The walk names no widget type.** A domain opts in with one method, so a layout and a widget container share one walk.
- **The focus moves on the down, and the action on the press.** A focus that rode with the action in one `CompoundOperation` would fail as a whole where a projection maps the action and not the selection, and a press on a control of such a projection would stop acting.
- **An Alt+press selects; a plain press acts.** A plain press already has a meaning in each widget. Alt+press is the whole-element gesture of the syntax domain, and it is free in every widget. See [plan/pending/select-a-widget-and-paste-it-into-a-tab.md](../../../../plan/pending/select-a-widget-and-paste-it-into-a-tab.md), whose steps for this are done.
- **The walk guards cycles by identity, not by depth.** A depth limit stops early on a deep tree and still walks a long cycle many times. The set of visited nodes stops exactly at the cycle.
- **A drawn widget is named by a step that holds it.** A field of the domain for each drawn widget would put view state into the data. The step reaches the widget only from its owner, so a paste can not write through it.

## Usage

```julia
FocusModule.is_focusable_document(w::MyControl) = w.enabled   # a domain opts in
path = get_first_focusable_path(document)                     # a Reference, or nothing
is_whole_selection_press(MouseClick(:left, 10, 20, 1, ModifierKeys(alt = true); time = 0.0))  # true
is_focusing_press(MouseDown(:left, 10, 20, ModifierKeys(); time = 0.0))                        # true
projection = SelectionWalkingProjection(; inner = make_json_projection_example())
```

`MyControl` stands for a document type of your own.

- Examples: `widget_focus_example` shows Tab across widgets.
- Tests: `test_widget_selection()` and `test_selection_walking()` in `test/platform/projection/`, where `test_widget_selection()` also clicks a check box and presses Space, with `WidgetButtonTest.jl`, and `ClipboardTest.jl` in the same folder for `OutputReferenceStep`. The package has no suite of its own.

## Limits

- `:down`, `:left` and `:right` return `nothing` for a caret. This is a rule and not a fault, but a caller that expects a walk from a caret gets nothing.
- No projection of this repository makes an `OutputReferenceStep`. A downstream program uses it for the forms that its projection draws.
- A pane tab needs its own Alt+arrow rules, because the generic walk steps from a tab content to its title; see [pane.md](../pane/pane.md).
