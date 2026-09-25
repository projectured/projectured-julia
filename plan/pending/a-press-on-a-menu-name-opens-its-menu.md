# A press on a menu name opens its menu

> **Status (2026-09-25): deferred.** The owner decides the fix later. Nothing is
> started.

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
- **No test presses a menu name** in the application window. The tests call
  the action of an item, or walk the data of the bar.

## Options

- a. (recommended by the implementer) The clipboard becomes a nesting arm, as
  in the Lisp: `make_clipboard_projection` returns a `RecursiveProjection` of a
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
