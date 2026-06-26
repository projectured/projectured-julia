# Web backend: widget expand/collapse flips back immediately (double toggle)

## Symptom

On the **web** backend, clicking a collapsible widget card's header collapses it
for a moment, then it expands again immediately (net: no change). The SDL backend
does not have this problem.

## Root cause

Click (`MousePress`) recognition is done **twice** for every click on the web
backend:

1. The editor's `GestureRecognizer` (`next_gesture!`, run by `Editor.read!` for
   *every* backend) synthesises a `MousePress` from each `MouseDown`/`MouseUp`
   pair — this is the single, backend-agnostic home for click recognition.
2. The web backend *also* synthesised its own `MousePress` in
   `_decode_and_enqueue!` on `mouseup` (legacy code, "mirrors SdlBackend").

So one physical click delivered **two** `MousePress` events to the reader
pipeline → `WidgetCardToGraphicsCanvas` emitted **two** `ToggleCollapseOperation`s
→ `collapsed` flipped twice → back to where it started.

The SDL backend had already been migrated to emit only raw events and rely on the
recognizer (see `GestureRecognizer.jl` docstring: *"This used to be done (for
clicks) inside the SDL backend; moving it here makes recognition
backend-agnostic"*). The web backend was never updated, so it kept the duplicate.

## Fix — `package/web/src/ProjecturedWeb.jl`

Make the web backend emit **only raw device events** (matching SDL); let the
editor's `GestureRecognizer` be the sole click synthesizer.

- Removed the `MousePress` synthesis block from the `mouseup` branch.
- Removed the `last_down_button/x/y/time` bookkeeping from the `mousedown` branch.
- Removed those four fields from `WebBackend` (and the matching constructor args).
- Dropped the now-unused `MousePress` import.
- Updated the `_decode_and_enqueue!` comment to explain why no backend-side click
  synthesis happens.

## Verification

- `using ProjecturedWeb; WebBackend()` loads/precompiles clean (`nfields == 10`).
- No browser integration test exists for the web backend; correctness rests on
  the editor always wrapping backend reads through `next_gesture!` (confirmed in
  `Editor.read!`), so exactly one `MousePress` now reaches the readers per click.
