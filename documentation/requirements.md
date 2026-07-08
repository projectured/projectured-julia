# Requirements

This document lists the requirements ProjecturEd is expected to satisfy. They are
grouped into two parts: the **externally observable behaviour of the editor** —
what a user or an AI assistant can see and do while an editor is running — and
the **usability of the Julia project** — what a contributor working in this
repository can expect. Each requirement is deliberately short and testable; the
linked guides explain the mechanisms behind them. A final section records
capabilities that are planned but **not yet fully met**.

The requirements are grounded in the current source and documentation. Where a
behaviour is only partially delivered today, it is stated as the target and the
gap is recorded under [Requirements not yet fully met](#requirements-not-yet-fully-met).

---

## Externally observable behaviour of the editor

### The editing model

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

4. **Selection and the caret move through every domain.** The user can move the
   selection and the caret through JSON, XML, YAML, text, syntax, widgets,
   tables, prose, math, the Julia AST, SQL, the database catalog, the filesystem
   tree, graphs, markdown, the workbench, and the AI conversation, including
   across nested-domain boundaries. Every document node carries a
   `selection::Reference` field, so the highlighted position on screen always
   corresponds to a real reference path in the model, addressed uniformly by
   `[i]` (1-based item) and `{k}` (0-based cursor).

5. **Keyboard focus follows the selection.** Coordinate-free keyboard events are
   routed only to the child the current selection points at, never to a default
   child; an unselected tree delivers keystrokes nowhere. First focus is
   established by a click or by Tab traversal.

### What can be edited

6. **Structured domains support in-place authoring.** In JSON, XML, and YAML the
   user builds and rewrites structure with contextual gestures — for example,
   typing `[`, `{`, `"`, or a digit in JSON replaces the selected value with an
   array, object, string, or number; `,` inserts a new element or entry; Tab
   moves from a key to its value; XML has element/attribute/text gestures (`<`,
   Space, `=`). The available gesture depends on the selection context, so only
   meaningful edits are offered.

7. **Character-level editing works inside structured values.** The caret
   addresses individual characters inside strings, numbers, keys, XML text and
   attribute values, and styled text spans; printable keys insert, Backspace and
   Delete remove, and arrow keys move the caret across span boundaries. The edit
   is a structural range operation on the model, never a buffer mutation.

8. **Type-in with live completion builds language documents.** Domains whose
   values are best entered as text — Julia, SQL, and the generic insertion
   framework — offer an insertion cursor that buffers typed source, shows live
   completion (accept the suggested continuation with Tab, commit with Enter,
   abort with Escape), and commits by parsing (`juliaparse`, `sqlparse`, and the
   JSON/XML/YAML/Markdown parsers). Completion candidates come from reflection,
   not a hardcoded table, so a new domain gets completion for free.

9. **Prose and expression domains are editable.** The Book domain (books,
   chapters, paragraphs, lists, embedded pictures), Markdown (styled text, inline
   spans, images, lists), and Math (variables, binary operations, parenthesised
   expressions, assignments) support type-in text editing of their content and
   structural insertion cursors.

10. **Browse-and-navigate domains render selectably even when read-only.** The
    database catalog (RDBMS → database → schema → table → column), rendered SQL,
    graphs, the filesystem tree, and live database query results are primarily
    navigational: their projections decline non-selection operations, but the
    user can still move the selection and caret through them and inspect any node.

### Input

11. **The editor handles a complete input vocabulary, backend-independently.**
    Readers receive keyboard (`KeyDown`, `KeyUp`, `KeyPress`, synthesised
    `KeyChord`), mouse (`MouseDown`, `MouseUp`, synthesised `MousePress`,
    `MouseMove`, `MouseScroll`, and motion-synthesised `MouseEnter`/`MouseLeave`),
    and window (`WindowQuit`, `WindowClose`, `WindowResize`) events, each carrying
    ctrl/shift/alt/meta modifiers. Readers never see native platform structs, so
    the same handling applies on every backend.

12. **Clicks, multi-clicks, and drags are recognised.** A press-and-release at the
    same spot becomes a single `MousePress` carrying a click count, so double- and
    triple-click are distinguishable; press-move-release sequences drive drag
    interactions such as split-pane resizing and scroll-bar dragging.

13. **Shared actions give focus-independent shortcuts.** A single `Action` object
    can drive a menu item, a toolbar button, and a keyboard chord at once (for
    example `Ctrl+S`), firing regardless of which child holds the selection;
    disabling the action disables all three surfaces together, and a disabled
    widget emits no operation for any event.

14. **The view can be zoomed and rescaled.** `Ctrl+=`, `Ctrl+-`, and `Ctrl+0`
    zoom the whole editor in, out, and back to default; adding Alt scales fonts
    only; transform panes support Ctrl+wheel zoom about the cursor and wheel
    panning. HiDPI displays are handled by a display-scale factor.

### Multiple views and composition

15. **One model can be shown several ways.** The user can switch the projection of
    a document — for example view the same JSON as a tree, a widget form, a table,
    or source — without changing a single byte of the underlying data.

16. **Computed views require no change to the model.** Inserting a sorting,
    filtering, focusing, scrolling, caching, word-wrapping, line-numbering, or
    search-highlighting projection yields the corresponding view (sorted,
    filtered, zoomed, scrolled, wrapped, numbered, highlighted) while leaving the
    model untouched; removing the projection removes the effect.

17. **Documents can mix domains.** A nesting projection embeds one domain inside
    another, so a document can nest, for example, JSON inside XML inside styled
    prose, and the caret round-trips faithfully across every domain boundary.

18. **Version history is available on any subtree.** Wrapping a subtree in a
    versioned object records snapshots (Ctrl+Shift+S) that can be deleted
    (Ctrl+Delete) and selected by criterion (latest, index, author, as-of,
    predicate); an elimination projection collapses the wrapper so downstream
    projections run unchanged.

19. **Content can be copied, cut, and pasted.** Clipboard projections let the user
    copy, cut, note, and paste arbitrary wrapped content (single slice or a
    collection), and, when text conversion is configured, mirror to and from the
    operating-system clipboard.

20. **The user can search and jump to matches.** A query (a predicate, string, or
    regular expression over leaf text) yields selectable document-rooted
    reference paths, and moving the selection to one places the caret at the
    match.

### Windowing and on-screen feedback

21. **The editor manages multiple windows.** A root screen document holds windows
    that the backend opens, resizes, and closes on demand; popups, dropdown and
    context menus, and submenus open as real windows anchored to their trigger,
    and dismiss on Escape or outside click. Modal dialogs suppress events to other
    windows until dismissed.

22. **A rich widget set is interactive.** Labels, buttons, checkboxes, switches,
    radio groups, text and number fields with validators, lists, sliders,
    progress bars, menus, toolbars, tabbed panes, split panes (drag-resizable),
    scroll panes and scroll bars, transform panes, trees, tables, cards, alerts,
    accordions, and dialogs respond to hover and press with visual feedback, route
    keyboard input to the focused widget, and reject edits that fail a field's
    validator. Buttons and labels can display images and theme-aware icons.

23. **Contextual help and inspection are available.** Hovering shows tooltips and,
    with the reference inspector enabled, a follower window naming the reference a
    click at that spot would create; pressing F1 opens a gesture-help window
    listing exactly the bindings applicable to the current selection.

24. **The selection is always visible.** The selection is rendered as highlight
    rectangles in the graphics backends and as inverse-video spans in the console
    backend, so the user can always see what is currently focused.

### Performance, backends, and export

25. **The editor stays responsive on large and lazy documents.** Editing one
    position recomputes only the projection cells the change affects, so the
    round-trip from keystroke to updated screen stays fast regardless of document
    size, and only the parts actually in view are forced. Lazy structures
    (`ListNode`) let the editor project and edit a finite window of a conceptually
    infinite document without materialising the whole thing.

26. **The same editor runs unchanged on multiple backends.** The identical
    document and projection can be driven by the SDL native-window backend, the
    web backend (browser over HTTP + WebSocket, rendering a JSON draw-list to a
    canvas), or the console backend (terminal with 24-bit ANSI colour); the
    editing behaviour the user observes is the same on each. The web backend sends
    only the smallest changed rectangle on each edit and nothing while idle.

27. **A projected document can be exported without a window.** The user can render
    any projected document headlessly to an image (BMP or PNG), to a
    resolution-independent, optionally paginated vector PDF with selectable text
    and embedded fonts, or — driving a recorded gesture timeline — to an MP4
    video, for screenshots, documentation, print-quality export, and
    visual-regression checks.

28. **The editor exits cleanly on request.** Pressing Escape or closing the window
    quits the running editor, and backend, window, and server resources are
    released rather than left dangling.

### AI-native editing

29. **An external AI assistant can drive the editor over MCP.** While an editor is
    running with the MCP server enabled it exposes tools — chiefly
    `execute_julia_code`, which runs arbitrary Julia in-process with `editor`
    bound and `Projectured` preloaded, plus API and documentation search — through
    which an assistant can read the live document structure, build reference
    paths, and apply structural operations, observing the same visual result the
    user would. Statements run in a persistent scratch module, so state built in
    one call survives into the next.

30. **The editor hosts its own AI assistant, and the conversation is a document.**
    The workbench Assistant streams a Claude turn, runs submitted Julia through
    the shared tool registry, and splits the response so fenced code blocks become
    live domain documents and prose becomes markdown documents. The conversation
    itself is a structured domain, projected and selectable like any other, so the
    editor edits its own AI session with the same machinery it uses for user data.
    Without an API key the assistant falls back to a deterministic offline
    backend, so examples run without a key or network.

31. **A recorded session can be replayed live.** A timeline of timed events and
    operations can be played back on a real window at wall-clock speed while the
    user still interacts and can quit, and the same timeline drives the headless
    video recorder; an animation clock re-evaluates time-dependent cells each
    frame.

---

## Usability of the Julia project

### Getting started and running

32. **The project runs from a clean checkout with documented prerequisites.** A
    contributor with Julia 1.10+ and, for the SDL backend, SDL2/SDL_ttf installed
    can clone the repository, run `julia --project=.`, and reach a working editor
    by following the getting-started guide, with no undocumented setup steps.

33. **Examples are launchable with one call.** Every supported domain and every
    widget has a ready-to-run example reachable through `run_example("<name>")`,
    with `run_web_example` and `run_console_example` for the other backends and
    options such as `workbench=`, `scrolling=`, `caching=`, `tooltip=`, and
    `inspector=`, so a newcomer can see the editor working before reading any
    implementation code.

34. **Output can be inspected without a window.** Helpers such as `print_example`,
    `print_object`, `write_example_image`, and `write_example_pdf` let a
    contributor examine projection output in a REPL or in CI, so development and
    debugging do not require a graphical display.

35. **The REPL exposes the pipeline for debugging.** A contributor can drive the
    printer/reader loop by hand (`print_document` → `read_intent` →
    `evaluate_operation` → reprint), force reactive cells directly, search an
    iomap for reactivity problems, and read per-frame performance counters (reads,
    computes, invalidations, writes, and stage timings) to find unintended
    recomputation.

36. **A standalone executable can be built.** PackageCompiler-based build tooling
    (`build_executable` / `BuildSpec`, or `julia Build.jl`) produces a native
    binary for a chosen domain and backend set, with options for the workbench
    shell, a runtime backend flag, window size, and the MCP server.

### Architecture and extension

37. **The reactive cell system guarantees incrementality and consistency.** Every
    document field is a pull-based reactive cell: reading a cell inside a computed
    thunk records a dependency, a write invalidates its transitive dependents, and
    recomputation is lazy on next read. This gives consistency (any view is
    exactly what the model projects to) and performance (only affected cells
    recompute) without a manual cache.

38. **The projection interface is exactly four functions.** Every projection
    implements `print_document`, `read_intent`, `map_reference_forward`, and
    `map_reference_backward`, and all cross-projection recursion rides these four
    via stored child IO maps — no projection walks a subtree by child type. This
    recursion contract is why any domain works under any higher-order projection.

39. **A small set of macros hides the reactive plumbing.** `@document`,
    `@projection`, and `@iomap` make every struct field a transparent cell;
    `@reference` and `@reference_case` build and destructure reference paths;
    `@gestures` declares a document type's editing gestures; and `@domain`
    generates a new domain's root, placeholder, insertion cursor, and Insert
    gesture from its name.

40. **Adding a new domain is a small, documented task.** A contributor introduces
    a domain by defining its document types (each with a `selection` field),
    writing matching `print_document` and `read_intent` methods to and from the
    syntax domain, declaring its gestures, and adding an example and a test,
    reusing the existing reactive-cell, selection, higher-order-projection, and
    editor infrastructure. The new-domain tutorial walks through it end to end.

41. **New operations, gestures, and backends plug into defined seams.** A new
    operation is a struct plus an `evaluate_operation` method (and a
    `reroot_operation` method if it carries a path); new gestures are declared
    with `@gestures`; and new backends, devices, agent servers, constraint
    solvers, and graph-layout engines register against factory seams
    (`make_backend`, `make_agent_server`, and the solver/layout generics) so
    generic code requests them by symbol and a missing implementation fails with a
    helpful error.

42. **Reactive collections cover indexed, linked, and tabular data.** `CellVector`
    is a growable indexed vector whose slots are individually reactive (writing
    one invalidates only that slot's readers) and can hold computed/lazy children;
    `ListNode` is a doubly-linked list that can be lazy or infinite in either
    direction; `CellMatrix`/`CellTable` extend the same design to grids.

43. **Documents can be saved, loaded, and interchanged.** Binary
    serialization (`save_document`/`load_document`) gives exact, lossless
    same-version persistence, pruning the reactive graph at each cell boundary;
    the natural-format path (`import_document`/`export_document`, dispatched by
    file extension) provides human-readable text interchange, exporting through
    the same printer the editor displays rather than a separate unparser.

### Project structure, tests, and conventions

44. **The repository has a predictable, layered structure.** Each `package/<name>`
    folder holds up to three sibling packages — `main`, `test`, and `example` — of
    identical shape, and the four main packages form a strict downward chain
    (`kernel ← base ← visual ← domain`) re-exported flat by the `Projectured`
    umbrella, so a contributor can predict where code lives.

45. **External dependencies live in separable opt-in packages.** Each heavy or
    platform-specific dependency (SDL2, HTTP/web, ODBC, the Tulip LP solver, the
    Adaptagrams native layout library, FFMPEG video, and the LLM/MCP transports)
    is an opt-in package that registers against a factory seam, so the core
    packages precompile and their test suites run in an environment with none of
    them installed.

46. **Layering rules are machine-checked.** A static guard parses the real import
    headers of each package and asserts a valid topological include order with
    every dependency pointing to an equal-or-lower layer, run per package
    (`test_kernel_layering()` and siblings) in about a second without loading the
    package.

47. **Tests can be scoped to the change.** The suite provides targeted entry
    points — single-example (`test_example`), single-domain (`test_json`),
    per-pipeline-stage (`test_json_to_syntax`), per-package
    (`test_kernel`/`test_base`/`test_visual`/`test_domain`), and the reactive
    primitive (`test_cell`) — plus walker helpers that return errors as a
    `Vector{String}` instead of stopping, so a contributor can verify a change
    with the smallest relevant test instead of the slow full `test_all`.

48. **Test results are unambiguous.** A passing run reports zero `Fail` and zero
    `Error`; known-failing assertions are marked `@test_broken` with a
    `# @broken:` reason and appear only in the `Broken` column, so any regression
    introduced by a change is immediately visible in the summary, and a marker
    that starts passing is flagged as an unexpected pass to be promoted.

49. **Conventions are stated and applied uniformly.** All indexing is 1-based;
    every printer has a matching reader and every projection is bidirectional; the
    division vocabulary (package / layer / slice / module) and the naming ladder
    (Event → Gesture → Intent → Operation → Document, with documents as nouns and
    operations as verb-first `…Operation`) are documented, so code organisation
    and names are predictable and bidirectionally guessable.

50. **Widget appearance is driven by a central theme.** The look of the widget set
    comes from a single theme token object with light and dark presets rather than
    per-widget colours, and the style layer is a set of pure value types
    (colours, fonts, geometry, strokes), so a contributor can restyle the UI in
    one place.

51. **The documentation has a defined reading order.** The guides in
    `documentation/` are organised into tracks (concepts, building, going deeper,
    per-domain, REPL) indexed from the README and CLAUDE.md, so a contributor can
    find the right guide for a task without reading everything, and agent-specific
    guidance is collected in CLAUDE.md.

---

## Requirements not yet fully met

These are intended requirements that the current implementation only partially
satisfies. They are recorded here so the document reflects reality; see the
[roadmap](roadmap.md) for status and priorities.

52. **Universal character-level editing.** Character type-in and range editing
    are wired and tested for the field-addressed domains (JSON, XML, YAML, text,
    prose, and the type-in/insertion path), but are not yet available uniformly in
    every domain. The target is that any leaf value the caret can enter is also
    editable in place.

53. **Global undo/redo.** Version history is available today through the
    versioning overlay, but a general undo/redo of arbitrary operations across any
    document is not yet a built-in editor feature.

54. **Mouse click-to-select in every domain.** Click-to-position and
    click-to-select work where the projection records the necessary coordinate
    map, but are not yet complete across all domains and projections.

55. **The annotation domain.** Attaching typed annotations to any document through
    a global registry is described in the design but not yet implemented; no
    annotation types or functions exist in the code today.
