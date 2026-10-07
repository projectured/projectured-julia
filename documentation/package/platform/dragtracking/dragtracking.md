# Drag tracking

> **Kind:** design · **Status:** current · **Stands on:** [gesture.md](../../kernel/gesture.md), [operation.md](../../kernel/operation.md), [mouse-target.md](../../kernel/mouse-target.md)

The dragtracking slice of `ProjecturedPlatform` keeps the path of the part whose drag is on, and gives that part the parts of its drag, `DragMove`, `DragEnd` and `DragCancel`, wherever the pointer is. A part starts its own drag with a `StartDragOperation` in its answer, and keeps its own state of what the drag does. This document says how the wrapper keeps the path, how the drags of the editor use it, and how a global drag finds where it lands.

## How it works

### How a drag starts

A part answers `StartDragOperation(path, dragged)` from its own place, the empty path, as it answers `ReplaceMouseTargetOperation`: a container puts its own step in front of the path on the way up, and a projection maps it backward. A part starts its drag at two different moments:

- **at the press**, for a part whose press has no other meaning, such as the thumb of a slider or the divider of a split pane;
- **after a small move of 5 pixels from the press**, for a part whose click has a meaning of its own, such as the tab of a pane or an element of a list that a drag reorders. A press that is released before that move is a plain click.

**A drag inside the output of a view.** A part that a view drew has no path in the input of the view. The view names it by an introduced reference, as the default backward map does, and a chain routes a gesture along such a path: an operation stops where its route names no node of the input, and a gesture goes on, so each stage maps the introduced step forward into its output. So a drag that starts on a part inside the output of a view, such as the thumb of the bar of the file tree, comes back to that part. A drag whose path ends at the input of a view as a whole is read by position from the deepest stage of the chain, which reaches the part that the output starts with. A view whose backward map answers `nothing` for a part it drew drops the start of the drag, and the default reader drops the whole answer to the press with it; such a map ends in the default.

`dragged` is the thing that a global drag carries to the part that takes it, and `nothing` for a local drag such as the thumb of a slider.

### The wrapper's state

`DragTrackingState(; content)` wraps `content` and holds two fields, both view state, so a history does not record them: `drag_path`, the path in `content` of the part whose drag is on, or `nothing` when no drag is on; and `dragged`, the thing that a global drag carries, or `nothing`. `DragTrackingProjection(; inner)` shows `content` through `inner` and adds nothing to the view.

### While a drag is on

The projection takes the `StartDragOperation` out of the answer of the content and writes its path and its dragged thing into the state. From then on, for each input of a window:

- it still gives the raw event on to the content by position, exactly as when no drag is on, so the part under the pointer still lights (see [mouse-target.md](../../kernel/mouse-target.md));
- it also sends the part at the kept path, by that path, the gesture of its drag: a move with a button held gives `DragMove(x, y, modifiers; time)`, the release gives `DragEnd(x, y, modifiers; time)`, each in the frame of that part ([a route moves the point](../graphics/graphics.md#a-route-moves-the-point));
- a bare Escape, the loss of the focus of the window, and a move with no button held, which shows that the release was lost, give `DragCancel(; time)` instead, and Escape goes no further;
- a `MouseClick` that the gesture tracker makes while the drag is on goes nowhere.

While a drag is on, a part starts no other drag: the content still answers the raw event, but a `StartDragOperation` in that answer is dropped.

### How a drag ends

`DragEnd` ends the drag with the change that the part makes of it. `DragCancel` ends it with no change, and is the one gesture for the three cases that call for it: the part reads it and puts back what it kept at the start of the drag.

### The drags

Each part that drags keeps its own state as a field of its own document, written with `ReplaceViewStateOperation` so a history records none of it:

| Part | State | `DragCancel` puts back |
| --- | --- | --- |
| `WidgetSlider` | `press_value`, the value at the press | the value at the press |
| the divider of a `WidgetSplitPane` | `drag_anchor`, the grab point and the two adjacent sizes ([widget.md](../widget/widget.md#the-drag-of-a-splitter)) | the two sizes of the grab |
| a `ChartPlot` | `drag_anchor`, the press point, the mode (`:pan` or `:zoom`), the window and the axis scales at the press, and the `view` field as the plot held it | the `view` field as the plot held it, for a pan |
| a `PaneTree` | `drag`, `(group, index, target, zone, origin, started)` | nothing dropped; `drag` is cleared |
| a `DraggingState` of the dragging slice | `press`, `(x, y, source, started)` | nothing moved; `press` is cleared |
| the thumb of a `WidgetScrollBar` | `thumb_drag`, `(along, value, travel)`, the place of the press along the bar, the value and the track that the thumb can move along; `owned` when an owner keeps the drag ([widget.md](../widget/widget.md#the-scroll-bars)) | the value at the press |

The split pane divider and the slider start their drag at the press; the chart starts it at the press too, inside the plot; the pane tree and the dragging state start it after the small move of 5 pixels, because a press on a tab or on a list element is first of all a click. See [dragging.md](../dragging/dragging.md) for the dragging slice, and [pane.md](../pane/pane.md) for the pane tree.

### Where a global drag lands

`find_drop_zone(document, dragged, point) -> zone or nothing`, in the operation layer of the kernel, answers where `document` takes `dragged` with the pointer at `point`, or `nothing` when it does not; the default answers `nothing` for every document. Two methods exist, each called by the part that keeps the drag, from its own `DragMove` and `DragEnd`:

- `find_drop_zone(tree::PaneTree, dragged, point)`, where `point` holds the point and the size of the view of the tree in pixels, answers the group and the zone under the point — the strip, the middle, or one of the four edge bands — from the geometry of the tree.
- `find_drop_zone(state::DraggingState, dragged, point)`, where `point` is the path that the mouse target of the content names, answers the collection and the index under it.

The part that keeps the drag draws its own preview from the zone it keeps, such as the rectangle the pane tree draws over the group a tab would land in.

### The shape of the pointer during a drag

The drag tracking does nothing for the shape of the pointer. The part that drags says its shape to the screen at the start of its drag, and gives it back at its `DragEnd` and its `DragCancel`, which the wrapper sends for every end of a drag ([screen.md](../screen/screen.md#the-shape-of-the-pointer-during-a-drag)). The list that the dragging slice reorders says no shape.

### The light during a drag

A `MouseMove` still goes down by position to the content, and names the part under the pointer, as every move does, whether or not a drag is on ([mouse-target.md](../../kernel/mouse-target.md)). So a part lights while a drag passes over it, and a button that a drag passes off clears its own `pressed`, the same way the leave of the pointer does outside a drag.

### Where the wrapper sits

`make_tracking_screen(document, projection; drag_tracking = true, gesture_tracking = true, …)` of the screen slice puts the drag tracker just inside the gesture tracker, and the inner wrappers, such as the tooltip window, inside that, around the screen: `GestureTrackingState` wraps the `DragTrackingState`, which wraps the documents of the inner wrappers, which wrap the `ScreenDocument`. The wrapper `window` of `build_editor` uses `make_tracking_screen` by default, so every editor with a window has a drag tracker. `drag_tracking = false` turns it off, for a host with no gesture tracker of its own.

## How it fits

The dragtracking slice depends on the kernel: the gesture layer for `DragMove`, `DragEnd` and `DragCancel`, and the operation layer for `StartDragOperation` and `find_drop_zone`. It registers nothing. The widget slice answers `StartDragOperation` for the slider, the split pane divider and the thumb of a scroll bar; the chart domain answers it for the pan and the zoom of a plot; the pane slice answers it for the drag of a tab; the dragging slice answers it for the reorder of a list. [graphics.md](../graphics/graphics.md#a-route-moves-the-point) holds the functions that move the point of `DragMove` and `DragEnd` into the frame of the part they are for, as a route descends to it.

## Design decisions

- **`StartDragOperation` and `find_drop_zone` are the two names a part needs.** `StartDragOperation(path, dragged)` starts a drag at a path, with `nothing` for a local drag; `find_drop_zone(document, dragged, point)` answers the zone of a drop, or `nothing`.
- **A route moves the point.** A container that draws its children in their own frames moves the point of a routed pointer gesture into the frame of the child, the same move it gives a gesture it hands to that child at a point. So `DragMove` and `DragEnd` reach a part at the point in its own frame, wherever the container has placed it. See [graphics.md](../graphics/graphics.md#a-route-moves-the-point).
- **A drag that ends with no change gets one gesture, `DragCancel`.** The wrapper turns Escape, the loss of the focus of the window, and a lost release into the same gesture, so a part reads one case and not three.
- **A part reads its drag from three gestures, and the raw events go on by position too.** A held move must reach the dragged part by its path, and it must also go by position, so the mouse target follows the pointer; the wrapper sends both, instead of only the raw `MouseMove` and `MouseUp` by the path, to keep the two needs apart.
- **Each global drag is a drag of the part that keeps it.** The tab strip of a pane and the dragging slice each start their own drag and find their own drop zone; no gesture searches outward through every container for a part that takes a drop. This serves every drag of the editor today; a drag that must land in a document other than the one that keeps it, such as a file dropped from the explorer into an editor, has no such search yet.

See [plan/done/a-document-knows-the-part-under-the-pointer.md](../../../../plan/done/a-document-knows-the-part-under-the-pointer.md) for the design record.

## Usage

```julia
scene = make_window_scene(document, "W"; width = 400, height = 300)
document, projection = make_tracking_screen(scene, projection)  # drag_tracking = true by default
editor = Editor(document, projection; backend = backend, devices = Device[Keyboard(), Mouse()])

# The path of the part whose drag is on, or nothing:
editor.document.content.drag_path
```

A worked example, a slider at `(20, 20)` with its thumb pressed at `x = 60`:

1. `MouseDown(:left, 60, 28)` on the thumb: the slider answers a value write, `dragging = true`, `press_value = 0.5`, and `StartDragOperation(EmptyReference(), nothing)`. The wrapper keeps the path of the slider.
2. `MouseMove(390, 200, buttons = :left)`, far to the right of the slider: the wrapper gives the content the raw move by position, and gives the slider `DragMove(390, 200)` by its path. The slider reads only the second and sets its value to `1.0`, because the drag reaches it wherever the pointer is.
3. `MouseUp(:left, 390, 200)`: the wrapper gives the slider `DragEnd(390, 200)`, which clears `dragging` and `press_value`; the wrapper then clears its own kept path.

Escape in place of the release sends `DragCancel` instead: the slider reads back `0.5` from `press_value`, and the drag ends with no change.

- Tests: `test_drag_tracking()` (`test/platform/shell/DragTrackingTest.jl`) drives the five drags through a real editor, with the light under a dragged thumb and a lost release; `test_routed_gesture()` (`test/platform/projection/RoutedGestureTest.jl`) checks that a route moves the point through eight kinds of container; `test_pane_drag()` (`test/platform/projection/PaneDragTest.jl`) and `test_dragging()` (`test/projectured/projection/DraggingProjectionTest.jl`) cover the two global drags at the reader level.

## Limits

- A drag that must land in a document other than the one that keeps it has no outward search yet: for example, a file dragged from the explorer into an editor needs a new mechanism.
- The scroll bar reads a held move by position directly, inside its own reader; it answers no `StartDragOperation` and keeps no path in `DragTrackingState`, so it is not a drag of this wrapper.
