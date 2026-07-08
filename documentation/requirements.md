# Requirements

This document lists the requirements ProjecturEd is expected to satisfy. They are
grouped into two parts: the **externally observable behaviour of the editor** —
what a user or an AI assistant can see and do while an editor is running — and
the **usability of the Julia project** — what a contributor working in this
repository can expect. Each requirement is deliberately short and testable; the
linked guides explain the mechanisms behind them.

## Externally observable behaviour of the editor

1. **The model is always valid.** The editor stores a document as structured,
   typed data rather than a character buffer, so the user can never place the
   cursor at an invalid position or produce a structurally malformed document. A
   keystroke is interpreted as a structural operation on the model, not as a
   character inserted into text.

2. **What is shown is a projection of the model.** Everything on screen is
   derived from the document by a projection chain; the display is never edited
   directly. Because the projection is a pure function of the model, the view is
   always exactly what the current document projects to, with no cache that can
   drift out of sync.

3. **Editing round-trips through the projection.** When the user presses a key or
   clicks, the event is translated backward through the same projection chain
   into an operation in the document's own domain, that operation is applied, and
   the display re-renders. The user observes an ordinary edit; internally it is a
   model mutation followed by a re-projection.

4. **Selection and cursor movement work in every domain.** The user can move the
   selection and the caret through JSON, XML, text, syntax, widgets, tables,
   prose, math, Julia AST, the filesystem tree, and the workbench, including
   across nested-domain boundaries, and the highlighted position on screen always
   corresponds to a real reference path in the model.

5. **One model can be shown several ways.** The user can switch the projection of
   a document — for example view the same JSON as a tree, a widget form, or
   source — without changing a single byte of the underlying data, and can layer
   sorting, filtering, focusing, scrolling, or caching projections to obtain a
   computed view that leaves the model untouched.

6. **The editor is responsive on large documents.** Editing a single position in
   a large document recomputes only the parts of the projection that the change
   affects, so the observable round-trip from keystroke to updated screen stays
   fast regardless of document size, and only the parts actually in view are
   forced.

7. **The editor runs on multiple backends unchanged.** The same document and
   projection can be driven by the SDL native-window backend, a browser via the
   web backend (`run_web_example`), or the terminal via the console backend, and
   the editing behaviour the user observes is the same across all three.

8. **The editor exits cleanly on request.** Pressing Escape or closing the window
   quits the running editor, and backend and server resources are released rather
   than left dangling.

9. **A projected document can be exported without a window.** The user can render
   any projected document to an image (BMP/PNG) or to a resolution-independent,
   multi-page vector PDF with selectable text, entirely headless, for
   screenshots, documentation, and visual-regression checks.

10. **The editor is drivable by an AI assistant over MCP.** While an editor is
    running it exposes an MCP server on `127.0.0.1:9876`, through which an
    assistant can read the live document structure, look up types and functions,
    build reference paths, and apply structural operations against the live
    `editor.document` and `editor.projection` — observing the same visual result
    the user would.

## Usability of the Julia project

11. **The project runs from a clean checkout with documented prerequisites.** A
    contributor with Julia 1.10+ and SDL2/SDL_ttf installed can clone the
    repository, run `julia --project=.`, and reach a working editor by following
    the getting-started guide, with no undocumented setup steps.

12. **Examples are launchable with one call.** Every supported domain has a
    ready-to-run example reachable through `run_example("<name>")` (and
    `run_web_example` for the browser), so a newcomer can see the editor working
    before reading any implementation code.

13. **Output can be inspected without a window.** Helpers such as
    `print_example`, `print_object`, `write_example_image`, and
    `write_example_pdf` let a contributor examine projection output in a REPL or
    in CI, so development and debugging do not require a graphical display.

14. **The documentation has a defined reading order.** The guides in
    `documentation/` are organised into tracks (concepts, building, going deeper,
    per-domain, REPL) indexed from the README and CLAUDE.md, so a contributor can
    find the right guide for a task without reading everything.

15. **Tests can be scoped to the change.** The test suite provides targeted
    entry points — single-example (`test_example`), single-domain (`test_json`),
    per-pipeline-stage, per-package (`test_kernel`/`test_base`/`test_visual`/
    `test_domain`), and the reactive primitive (`test_cell`) — so a contributor
    can verify a change with the smallest relevant test instead of the slow full
    `test_all`.

16. **Test results are unambiguous.** A passing run reports zero `Fail` and zero
    `Error`; known-failing assertions are marked `@test_broken` and appear only
    in the `Broken` column, so any regression introduced by a change is
    immediately visible in the summary.

17. **Adding a new domain is a small, documented task.** A contributor can
    introduce a new domain by defining its document types, writing matching
    `print_document` and `read_intent` methods, and adding an example and a test,
    reusing the existing reactive-cell, selection, higher-order-projection, and
    editor infrastructure, following the new-domain tutorial.

18. **Conventions are stated and consistent.** Project-wide rules — all indexing
    is 1-based, every printer must have a matching reader, and the division
    vocabulary (package / layer / slice / module) — are documented and applied
    uniformly, so a contributor can predict how code is organised and named.

19. **The reference and REPL tooling is discoverable.** The `@reference` DSL,
    the debugging helpers (`run_example`, driving the printer/reader by hand,
    forcing reactive cells), and the performance counters are documented so a
    contributor can navigate documents and diagnose recomputation without reading
    the source first.

20. **The project is safe to contribute to under a defined process.** Repository
    conventions, the pull-request process, and code style are documented in
    `CONTRIBUTING.md`, and agent-specific guidance is collected in `CLAUDE.md`,
    so both human and AI contributors have a single place that tells them how to
    work in the repository.
