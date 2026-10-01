# Mouse target tracking

> **Kind:** design · **Status:** current · **Stands on:** [gesturetracking.md](../gesturetracking/gesturetracking.md), [devices-and-backends.md](../../kernel/devices-and-backends.md)

The mousetargettracking slice of `ProjecturedPlatform` keeps the part under the pointer, the target, and gives the parts of the target their crossings: `MouseEnter`, `MouseLeave` and `MouseHover`. It is a projection with a wrapper document, and the screen slice puts it around the screen, inside the gesture tracker, so one target serves every window.

## How it works

`MouseTargetTrackingState` wraps a `content` document and keeps four fields: `target`, the path of the part under the pointer; `parts`, the prefixes of that path that name a document, the outer first; `position`, the window and the point of the last motion; and `waiting`, the crossings that wait for the content. A view state operation writes each field, so a history does not record it.

On a `MouseMove`, `MouseTargetTrackingProjection` maps the point backward through its `inner` projection. In a screen, the point of window `w` is the point step after `windows[i].content`. A point step at the end of the answer is no part of the target, so a plot is the same target at every point of it.

**A widget that a view makes.** A view names a widget of its output by a projection step, the introduced reference, when the widget shows no part of its input, such as a button of the view. That output is in no document, so each prefix of the path inside the step is a part: the button gets its enter and its leave. A crossing of a prefix that names no widget reaches no reader. When a widget shows a part of the input, such as the row of a file, the part is on the target, and the route of a chain carries its crossings on to the widget that shows it ([higher-order-projections.md](../projection/higher-order-projections.md)).

- When the target changes, each part of the old target that is not on the new one gets a `MouseLeave`, the inner first, and each part of the new target that is not on the old one gets a `MouseEnter`, the outer first. A button ends its press on a leave.
- Then, on each move, the deepest part gets a `MouseHover`, at the point step of the answer when there is one, and at the point in the window otherwise. The route of the hover is the whole target, not the deepest part: a row of a list is no document, so the list is the deepest part. A dwell opens a tooltip.
- A `DisplayUpdate` of the window of the pointer finds the target again at the last position, because a view can change under a still pointer: a list that scrolls, a popup that opens. It gives the crossings of the change, and a hover when the target changed.
- A `WindowLeave` of that window gives every part a leave and clears the target.
- The route of a crossing holds the type of each node, because a view that maps a route forward checks the types. A crossing whose part is gone is not delivered.

## Why a crossing goes by route

A crossing is for a part, not for a place: a leave goes to the part that the pointer left, wherever the pointer is now. So each crossing goes to its part by route, with the route mechanism of the kernel (`read_routed_child`), and no container sends a crossing to a child by position. At its place, the reader of the part reads the gesture. A widget with rows, such as a list, reads a route into a row with its own reader.

## Why a crossing waits

The content reads the input first. The crossings wait in the state, and a timer at the time of the input brings them in, one in each read, after the operation of the input, as the gesture tracker does. The loop of the editor reads until the input runs out and prints once, so the crossings cost no frame.

## How to use it

Apply the wrapper with `make_mouse_target_tracking_document(document)` and `make_mouse_target_tracking_projection(projection)`, or through the keyword `mouse_target_tracking` of `make_tracking_screen` in the screen package, which is on by default. The gallery turns it off with `hover = false`. `get_wrapped_document` of the state answers the content.

The root of the content is no part, because every target is on it. So a lone widget that is the whole content of a window, and maps a point to nothing, gets no crossing; a window holds a container, and a widget in it is a part.

No widget lights from a crossing. A widget draws its light from its own mouse target, which a move writes ([widget.md](../widget/widget.md)).
