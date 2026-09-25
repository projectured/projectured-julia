# A press on a menu name opens its menu

> **Status (2026-09-25): deferred.** The owner decides the fix later. Nothing is
> started. The owner thinks the clipboard must not be a chain.

A press on "File" or "View" in the menu bar of the application window does
nothing. The dropdown never opens, and no message says why.

## Facts (2026-09-25)

- **The press arrives.** An offscreen probe over `make_application_window`
  pressed the drawn "File". The press reaches the `WidgetMenuItem`, and the
  item answers an `OpenPopupOperation`. The shell passes it up unchanged.
- **The anchor is wrong.** The item takes its anchor from `ctx.reference` at
  print time: `.windows[1].content.menu_bar.elements[1]`. The shell is at
  `.windows[1].content.content`, because `make_window_wrap` puts the shell
  inside the clipboard wrapper, which holds it under `content`.
- **The chain drops the step.** `make_clipboard_projection` builds a
  `ChainingProjection` of the clipboard and the projection of the content. A
  chain gives each stage the context of the chain's input, so the second stage
  prints the shell with the reference of the clipboard.
- **The resolver drops the popup.** `WidgetPopupResolverProjection` maps the
  anchor forward. The forward map of `ClipboardSliceToAnyProjection` wants a
  `content` step first, gets `menu_bar`, and answers `nothing`. The resolver
  then answers no operation.
- **The Lisp original is not a chain stage.** `document/clipboard->t` is an arm
  of a `type-dispatching` under `recursive` (`source/executable/projection.lisp`
  of projectured-lisp). Its printer recurses into the content with the
  reference extended by `content-of`. Its reader runs the clipboard gestures
  first, then the content. A Julia chain reads from the last stage to the
  first, so the content reads a key before the clipboard.
- **The reasons for the chain** in
  [clipboard.md](../../documentation/package/clipboard/clipboard.md) are that
  the toggle is a cell write, and that the wrapper is not in the view. A nesting
  arm keeps both.
- **The chain is a workaround.**
  [clipboard-os-bridge-and-run-example-wrapper.md](../done/clipboard-os-bridge-and-run-example-wrapper.md),
  step 6, records it. The first version was a nesting arm. The output of the
  clipboard is a computed cell, so that Ctrl+/ switches the content and the
  slice with a cell write. At the top of a pipeline nothing read that cell, and
  the cell reached the SDL backend:
  `write_to_devices: …content is Cell, expected GraphicsCanvas`. A chain reads
  the cell of a stage between two stages, so the clipboard became stage 1 and
  the projection of the content stage 2, which answers a plain canvas.
- **The workaround costs three things.** Stage 2 prints with the context of the
  clipboard, so no reference that a printer takes below the clipboard has the
  `content` step. The content reads a key before the clipboard, which is the
  reverse of the Lisp and of `clipboard.md`. The clipboard prints its content
  through `IdentityProjection`, so the real projection prints below it only as
  a second stage.
- **No test presses a menu name** in the application window. The tests call
  the action of an item, or walk the data of the bar.

## The experiment with a nesting clipboard (2026-09-25)

A scratch script redefined `make_clipboard_projection` as a nesting arm:
`RecursiveProjection(TypeDispatchingProjection(ClipboardSlice => clipboard,
Any => NestingProjection(projection; recursion = IdentityProjection())))`. No
file of the repository changed.

- **The old fault is gone.** The top output of a wrapped JSON document is a
  `GraphicsCanvas`, not a cell. An IO map now gives the value of its `output`
  cell when code reads `iomap.output`
  ([IoMapDefaults.jl](../../source/kernel/iomap/IoMapDefaults.jl)).
- **The anchor is correct.** A press on "File" gives the anchor
  `.windows[1].content.content.menu_bar.elements[1]`. Asked with the tail of it,
  every layer from the clipboard down answers a point: the clipboard, the
  `NestingProjection`, `SelectionWalkingProjection`,
  `WidgetHoverTrackingProjection` and the shell, down to the point (2, 2) of the
  menu.
- **The popup still does not open: a second fault.**
  `CommandPaletteDecoratorProjection` answers the point of its inner layer
  inside a path, `elements[1]` of the canvas it wraps its inner output in.
  `get_anchor_point` accepts only a bare `PointReferenceStep`, so it answers
  `nothing`, and the resolver drops the popup. The layers above the palette
  (`GestureLogRecordingProjection`, a `NestingProjection` and a
  `ReferenceDispatchingProjection`) pass that path on. `TooltipProbeProjection`,
  which the binary adds and the test window did not, passes a reference through
  unchanged.
- **The palette breaks a rule of the kernel.** The docstring of
  `map_reference_forward` in
  [ProjectionInterface.jl](../../source/kernel/projection/ProjectionInterface.jl)
  says that a container adds only its own offset to a child's image that is a
  `PointReferenceStep`, and prepends its steps to one that is a structural path:
  "coordinates accumulate, paths stay paths". The palette always prepends
  `elements[1]`. `shift_child_image` in `LayoutToGraphics.jl` is how the shell
  and the layouts follow the rule.
- **Not checked yet:** what changes when the clipboard reads its keys before the
  content; whether Ctrl+/ still switches the view; that the slice prints only
  when it shows; and every test suite.

## Options

The menu opens only when both faults are fixed.

### Part 1: the place of the shell

- a. (recommended by the implementer, and the one the experiment checked) The
  clipboard becomes a nesting arm, as in the Lisp: `make_clipboard_projection` returns a `RecursiveProjection` of a
  `TypeDispatchingProjection` with `ClipboardSlice => clipboard` and
  `Any => NestingProjection(projection)`. The printer already extends the
  context with `content` and `slice`, so the anchor becomes correct. The arm
  prints the slice through the whole projection, so the printer must print it
  only when it is shown. It adds no new type. The risk: the clipboard reads a
  key before the content, as in the Lisp. Find each key that both answer before
  the change.
- b. `make_clipboard_projection` keeps the chain, and a small new projection
  gives the second stage the context of the child on display.
- c. `ChainingProjection` gives each later stage the context of the place where
  its input is, from the backward map of the stage before. This changes every
  chain.
- d. The anchor is not taken at print time. Each container adds its step as the
  operation goes up.

### Part 2: the point through the palette

- e. (recommended by the implementer) `CommandPaletteDecoratorProjection`
  follows the rule: when the image of its inner layer is a
  `PointReferenceStep`, it answers a point, the image plus the origin of the
  inner output in its canvas; when it is a path, it prepends `elements[1]` as
  now. It is a fix of one method, and it adds no new type.
- f. `get_anchor_point` follows a path through the canvases to a point. The same
  docstring says not to add a second way to resolve a position, because every
  wrapper already composes `map_reference_forward`.

## Test

A real press on "File" in the window of `make_application_window` opens a popup
window that draws "New tab", and a press on "New tab" opens a tab. The same for
"Help" once
[the-help-menu-lists-document-types-and-projections.md](../done/the-help-menu-lists-document-types-and-projections.md)
is done.

## Related faults, not in this plan

- The shell gives its content band no `content` step in the context, so a
  dropdown inside a pane has the same fault.
- A right press in the application window opens no popup either. The cause is
  not found.
