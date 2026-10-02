# Mouse target

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The mouse target is the part under the pointer, stored on a document the way the selection is. Each projection acts on the mouse target of its own document: a widget lights, and a syntax compound lights its delimiters. No central component decides where the pointer is or which part answers it; see [`PAR-DECIDE-LOCALLY`](../../rule/architecture-invariants.md#par-decide-locally) and [`PAR-NO-GLOBAL-ROUTING`](../../rule/architecture-invariants.md#par-no-global-routing).

## How it works

### The field

`@document` adds a field `mouse_target::Union{Nothing,Reference}`, default `nothing`, next to `selection`, to every cell-layout document: the documents that an editor holds. A native, immutable layout has none. The mouse target is view state: `is_view_state_field(name)` is true for `:selection` and `:mouse_target` (`source/kernel/document/DocumentDefaults.jl`), so a binary save skips it, a load gives `nothing`, a copy gives `nothing`, and a history does not record it.

`get_mouse_target(document)` reads the field without its type checkpoints, as `get_selection` reads the selection. It answers `nothing` when the pointer is not in `document`, or `document` has no mouse target.

The mouse target follows the shape of the selection closely enough that the two are best read side by side:

| | Selection | Mouse target |
| --- | --- | --- |
| Field | `selection` | `mouse_target` |
| Default | `nothing` | `nothing` |
| Written by | `set_selection!`, `replace_selection!` | `replace_mouse_target!` |
| Operation | `ReplaceSelectionOperation` | `ReplaceMouseTargetOperation` |
| Forward map | `map_selection_forward` | `map_mouse_target_forward` |
| Dormant state, for a tab or a pane not shown | kept, marked dormant | none; a document not shown holds no mouse target |
| Saved and copied | both | neither |
| Recorded by a history | no | no |

### The chain

Each document on the path holds its own tail of the path, as a selection does: the document at the root holds the whole path, and the document that the path ends on holds the empty path. `replace_mouse_target!(document, path)` writes it: it calls `replace_path_chain!(document, :mouse_target, path)` of `source/kernel/operation/PathChain.jl`. The chain write goes down while the old and the new path agree, writes a cell only when its value changes, and clears the chain of a child that was on the old path and is not on the new one. A document off the path holds `nothing`.

For example, with `[1, [2, 3]]` and the pointer on the `2`: the outer array holds `.elements[2].elements[1]`, the inner array `.elements[1]`, the number `2` a path into its own value, and the `1` holds `nothing`. Because only the cells whose value changes are written, a move that stays inside the same part writes no cell. Paths are compared without their type checkpoints, so a path that only gains or loses a checkpoint writes nothing either.

The selection keeps its own chain, with its dormant state for a tab or a pane that is not shown. The mouse target has no dormant state: a document that is not shown holds no mouse target at all, because the pointer cannot rest on what is not drawn.

### A move becomes a path

A `MouseMove` with no button held goes down by position, as a click does: each container hit-tests its children and moves the point into the frame of the one it gives the move to. `read_child_move` and `read_child_leave` of `source/platform/graphics/ChildMove.jl` carry the mouse-target half of this routing; see [graphics.md](../platform/graphics/graphics.md#the-part-under-the-pointer) for the functions that every container shares.

A container compares the child that its own mouse target names, the old part, with the child at the point, the new part. It finds the old child with `get_mouse_target(document)`: the layout package's `_get_target_layout_slot` reads the field and matches its first steps against `children[i]`, so a container needs no state of its own to know which child the pointer was on last.

When the old and the new child differ, the container gives the move first to the old child, with the point moved into that child's frame, so each part on the old path sees that the pointer left it and can act: a button clears `pressed`, and a chart ends a drag with no change. It then gives the move to the new child by position. The deepest part under the point answers `ReplaceMouseTargetOperation(EmptyReference())`, "the pointer is on me." A child that answers no target is the target itself, the same rule that turns an unanswered press into a whole selection. When the old and the new child are the same, the container gives the move once.

On the way up, each projection maps the path backward into the path of its own input, as it maps a selection. The default `read_intent(projection, iomap, operation)` of [the operation layer](operation.md) already does this for any `ReplacePathOperation`, the shared supertype of `ReplaceSelectionOperation` and `ReplaceMouseTargetOperation`: it reads the path with `get_operation_path`, maps it backward with `map_reference_backward`, and rebuilds the same kind of operation with `make_path_operation`. So a projection whose reference maps keep the structure needs no code for the mouse target. A reader that must do more than map the path writes its own `read_intent` only for that case.

An answer of another kind, such as a write of `pressed`, carries its own document and acts on it directly, also when that document is a widget that a view made. The editor evaluates the operation that reaches it, which writes the path at the root with the chain write above.

### A leave

A leave of the window is a move to `(-1, -1)`, a point off every part. It clears the mouse target along the old path, the same way a move to a point with no part under it does.

### The forward map

A printer maps the mouse target of its input forward into its output, as it maps the selection forward: the output document's `mouse_target` is a computed cell that reads `map_mouse_target_forward(input, map_forward)` (`source/kernel/projection/OutputPaths.jl`), where `map_forward` is normally built from `map_reference_forward`. `make_output_path_cells(input, map_forward)` gives this cell and the selection cell together, as a named tuple. A printer that builds a tree of output documents wires the root of the tree with `set_output_path_computations!` and then calls `set_output_tree_path_computations!(root)`, which gives each document below the root the part of its parent's paths below the step that reaches it, so a key reaches the part that the selection names.

So a widget that a view makes for a part of a domain lights when the pointer is over that part. The view needs no code of its own for this.

### The light

Each projection draws from its own mouse target, as it draws the selection ring from its selection, and no reader writes a state for this. A widget lights while its mouse target is set, that is while the pointer is on it or on a part inside it; a list, a table and a tree light the row that their mouse target names. [widget.md](../platform/widget/widget.md) describes each widget's light. A light never changes the layout: it draws a layer over the surface or the row, never a different size or place.

### A container that reads its own parts

A row of a list, a table or a tree is not a document, so the pointer never reaches it through the chain of a child's own field. Instead, the backward map of the point inside such a container answers a path into the container's own structure, for example `items[2]`, and the container is itself the deepest part: it holds that path in its own `mouse_target` and lights the row the path names. A column header of a table works the same way, holding its own column in its own field. So a list, a table and a tree need no document for each row to give it a light.

A widget container that a view builds for a domain, such as a tree of files, reads the forward-mapped mouse target the same way a native container reads its own: through `get_mouse_target` of the widget document it holds, to find the child the pointer was on last. [The forward map](#the-forward-map) computes that field.

### The brackets of a tree

In the text of a tree, such as a JSON document, the delimiters of the compounds around the part under the pointer light by their level: the innermost compound is at level 0 and has the light colour, and each level further out mixes the colour more with the delimiter's own gray, until a fixed number of levels out the delimiter keeps its own colour. [syntax.md](../platform/syntax/syntax.md#the-delimiters-around-the-pointer) describes the level and the colours.

### An edit keeps the mouse target right

An edit that writes into a slot, through `ReplaceReferencedValueOperation` (an insert, a delete, a replace of an element, and so an undo and a redo too), moves the mouse target paths that pass through that slot along with it: a path into an element after a splice moves by the change in length, a path whose slot is gone becomes the empty path at the parent, and the documents above the slot on the path of the operation get the same tail.

A child that the write takes out of the slot keeps no mouse target of its own, because it can still be shown at another place; the move that follows the changed frame finds it there. [operation.md](operation.md) describes the mechanism.

This is why an edit must go through an operation, as the user interface does, rather than through a direct write into a cell: only the evaluation of an operation keeps the chain right.

### A view that changes under a still pointer

After a frame that changes what a window shows, or after a window closes, the SDL backend queues a `MouseMove` at the point where the pointer is, in the window under it, with the buttons held now. So the light moves to the part that is now under the pointer after a list scrolls or a popup opens or closes, with no move of the hardware pointer. A reader must not write a cell again on a move to the point of the last move, [`PAR-REPEATED-MOVE-WRITES-NOTHING`](../../rule/architecture-invariants.md#par-repeated-move-writes-nothing), because otherwise each such move would write cells, change the frame and cause one more move. See [sdl.md](../backend/sdl/sdl.md) for the backend side.

### A dwell and a right click travel by position too

A dwell and a right click are not read from the mouse target: each container routes them by position, the same hit test that a move uses. `is_outward_gesture(gesture)` is true for a `MouseDwell` and for a right `MouseClick`.

When the deepest part answers nothing, `read_child_part_gesture` reads the gesture tables of the documents inside the child through the backward map of the point, and `read_container_gesture`, with the kernel's `read_gesture_outward`, reads the container's own stretch outward. A document reads the gesture when nothing deeper answered, or when the deeper answer collects, such as a tooltip or a context menu; a collected answer is joined. [graphics.md](../platform/graphics/graphics.md#a-dwell-and-a-right-click) names the functions; [tooltip.md](../platform/tooltip/tooltip.md) and [context-menu.md](../platform/widget/context-menu.md) describe what a dwell and a right click mean.

The gesture tracker recognizes the click and the dwell from the times of the events, not from the mouse target: the dwell comes once for each place where the pointer rests, a move to the same point keeps the wait, and a press, a click or a scroll stops it. See [gesturetracking.md](../platform/gesturetracking/gesturetracking.md).

## How it fits

The field comes from the document layer, layer 10, the same `@document` macro that adds `selection`. The chain write, `get_mouse_target` and `ReplaceMouseTargetOperation` are in the operation layer, layer 13, beside `replace_selection!` and `ReplaceSelectionOperation`. `map_mouse_target_forward` is in the projection layer, layer 17, beside `map_selection_forward`. None of this needs the selection layer itself, because the mouse target is its own kind of path with no dormant state.

The graphics slice of `ProjecturedPlatform` holds the container routing that every container shares: the hit test, the comparison of the old and the new child, and the outward read of a dwell and a right click. The widget slice reads the mouse target to draw its light and to open a context menu by a right click; the syntax slice reads it to light the brackets of a tree; the tooltip slice reads a dwell routed by position to open its window. A domain needs no slice of its own for this: the field, the chain and the forward map work the same way for every document, so a new domain gets a lit part under the pointer with no code written for it.

## Design decisions

- **The path is stored like the selection.** A document that already holds a path for the selection holds a second one for the part under the pointer, with the same chain write and the same forward map, and each projection draws from it locally. One mechanism serves both, and a third kind of path, if one is ever added, can reuse it the same way.
- **A move reaches the old part before the new one.** The move goes first to the part that the pointer leaves, then to the part that it is on. So the old part can act when the pointer leaves it, as a button that clears `pressed`, and no other function is necessary for that case.
- **The operation shares its shape with the selection.** `ReplaceMouseTargetOperation` and `ReplaceSelectionOperation` are both a [`ReplacePathOperation`](operation.md): a container that puts its own step before the answer of a child, and a projection that maps an answer backward, handle both in one method, so a reader that only maps a path needs no mouse-target-specific code.
- **No dormant state.** Unlike the selection, the mouse target is never kept for a part that is not shown, because the pointer can not rest on a part that is not drawn.
- **A path answer and a value answer go back differently.** `ReplaceMouseTargetOperation` is mapped backward on the way up, as any path is; an answer that carries its own document, such as a write of `pressed`, is not re-targeted and acts directly on the document it names, a widget that a view made included.
- **A route is decided only to return an operation from one named place.** A move, like a click and a dwell, travels by position and by the chain that each document holds; code fixes a route in advance only for the rare case where an operation must come back from one specific document, such as a command run from the palette.

See [plan/pending/a-document-knows-the-part-under-the-pointer.md](../../../plan/pending/a-document-knows-the-part-under-the-pointer.md) for the design record.

## Usage

```julia
# Read the part under the pointer, without its type checkpoints:
target = get_mouse_target(document)

# Write it directly, such as in a test:
replace_mouse_target!(root, path)

# Wire it forward in a printer, beside the selection:
paths = make_output_path_cells(input, path -> map_reference_forward(projection, iomap, path))
output = TextBlock(elements, paths.selection, paths.mouse_target)
```

`print_document` of `SyntaxLeafToText` in `source/platform/syntax/SyntaxToText.jl` makes both cells this way. The printer of a syntax compound makes the two cells itself, because its selection also shows the caret of a child.

A test moves the pointer by hand and checks the chain it leaves. On `[1, [2, 3]]` with the pointer moved onto the `2`:

```
outer.mouse_target[]   ← .elements[2].elements[1]   (into the inner array, then the `2`)
  └─ inner.mouse_target[]  ← .elements[1]            (the `2` is its first element)
       └─ two.mouse_target[]  ← .value               (the number's own value)
one.mouse_target[]     ← nothing                     (off the path)
```

- Tests: `test_json_mouse_target()` (`test/domain/json/editor/JsonMouseTargetTest.jl`) moves the pointer over a JSON document and checks the chain at each document; `test_mouse_target_move()` (`test/platform/projection/MouseTargetMoveTest.jl`) moves the pointer over a composite of widgets and over a view that makes widgets for a domain, and checks that a button that the pointer leaves ends its press.

## Limits

- **A move with a button held does not change the part under the pointer.** It keeps the routing of a drag, and it does not reach the part that the pointer leaves. So a button that is pressed and dragged off stays drawn pressed until the release.
- **A domain document that a view shows inside a widget, and that a second view also draws, gets no mouse target.** This is an open question.
- **An edit that is no operation keeps no path right.** A direct write into a cell does not move or clear the mouse target paths that pass through it. An assistant or a script that edits a document must make an operation, also for this reason.
