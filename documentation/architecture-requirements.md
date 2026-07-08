# Architectural requirements — how to develop ProjecturEd

This document collects the **internal development requirements** the project
must be built to, so that it stays tractable and maintainable as it grows. It is
for contributors, developers, and AI assistants working in the codebase alike.

It is deliberately distinct from its two siblings:

- [requirements.md](requirements.md) states what the editor must do as
  **externally observable capabilities** (behaviour of the editor, usability of
  the project). Those are *product* requirements.
- [architecture-rules.md](architecture-rules.md) is the decision procedure for
  **where a piece of code lives** (package / layer / slice / module). Those are
  *placement* rules.

This document states the **invariants and conventions every change must
respect** — the load-bearing contracts the code assumes you understand, and that
break silently (a hang, a stale render, an un-composable projection, a mis-mapped
cursor) rather than loudly when violated. Each requirement is a few sentences and
is numbered for reference (cite them as *AR-N* in reviews, commit messages, and
plans). The division vocabulary (package / layer / slice / module) is used
exactly as defined in [terminology.md](terminology.md).

When a rule here and a rule in a per-topic guide appear to conflict, the
per-topic guide wins for its topic and this document should be corrected; when
this document does not answer a "may I…?" question, extend it rather than
improvise (the same principle [architecture-rules.md](architecture-rules.md)
states for placement).

---

## Reactivity — the cell engine

1. **Every reactive computation must be a pure function of the cells it reads.**
   A `Cell(() -> …)` thunk (and the parts of `print_document` that build them)
   must have no side effects and must depend only on the cells it reads — no
   clocks, RNG, or external mutable state. A thunk may run zero, one, or many
   times per logical change and its cached result is reused until invalidation,
   so impurity produces a wrong cache, not just a style smell. This is a
   correctness requirement.

2. **A thunk must never write another cell or mutate shared document state.**
   Writing `other_cell[] = v` from inside a cell computation invalidates that
   cell's consumers *mid-computation*, making recomputation order-dependent and
   the graph inconsistent (graphics-domain cells do have consumers, e.g.
   `GraphicsCaching`). To preserve output-object identity across recomputes,
   reuse a *persistent* object whose fields are `set_function!` cells that
   **derive** from the upstream layout cell — do not rebuild objects, and do not
   reuse-then-mutate them with imperative cell writes.

3. **The cell dependency graph must stay acyclic.** `recompute!` evaluates a
   thunk while its cell is on the `_computing` stack; a cell that transitively
   reads itself recurses forever. The engine only skips a *direct* self-edge — it
   does not detect multi-cell cycles — so a computed cell must never depend on
   itself through any chain.

4. **Never hand-set `valid` and never partially invalidate.** Invalidation is
   monotone (an invalid cell implies all its transitive dependents are already
   invalid), and the engine's early-stop walk relies on it. `recompute!` is the
   only thing that re-validates a cell. Setting `valid` by hand, or invalidating
   only a subset of dependents, breaks the early-stop and leaves cells stale
   forever.

5. **Treat propagation as write-driven, not value-driven.** Writing a cell
   invalidates its dependents unconditionally — there is no `old == new`
   short-circuit, and a thunk that recomputes to an unchanged value does not stop
   propagation. Consequently `c[] = c[]` is not free: a printer that rewrites
   `selection` (or any cell) every frame pays to recompute the whole subtree that
   reads it. Write a cell only when its value actually needs to change.

6. **No global mutable state in projections (or the machinery they call).** No
   module-level `Dict`/`Ref`/counter populated at runtime. Every cache, memo, or
   reconciliation table must be created *per projection invocation* and live in
   that invocation's `IoMap` or in its cells' closures. Global state silently
   leaks across unrelated documents rendered in the same process, is never
   evicted, and corrupts under the editor's reuse of one process for many
   documents. A projection's own private reconciliation cache (a plain `Dict` in
   a cell closure, observed by no other node) is the correct way to key reuse.

7. **Use the reactive engine for derived state; do not read a cell before its
   wiring is complete.** Express derived values as computed cells so the system
   can invalidate them, rather than caching them by hand. During construction of
   a struct whose iomap wiring is not yet finished, defer the read with
   `Cell(() -> …)` (the deferred-iomap trick) instead of reading the cell eagerly.

8. **Choose the reactive container that preserves the finest granularity.** Use
   `CellVector` for finite, indexed collections (each slot is its own `Cell`, so
   a write to one slot invalidates only that slot's readers) and `ListNode` for
   sequences that are addressed relative to a node or may extend indefinitely
   (its lazy `prev`/`next` make copying an unbounded list O(1)). Keep the
   per-slot granularity intact: a structural change updates the outer `elements`
   cell (invalidating shape-dependent readers), while a value change touches only
   the affected slot — do not collapse this into a single coarse cell.

## Documents and domains

9. **Every document field is a `Cell`, accessed transparently.** Declare domain
   types with `@document` (or `@cell_struct` for a non-framework transparent
   struct); the macro wraps every field in a `Cell` and generates
   `getproperty`/`setproperty!` so `doc.field` and `doc.field = v` read and write
   the underlying cell. Do not hand-roll cell wrapping, and do not reach for the
   raw cell via `getfield(obj, :field)` unless you are deliberately bypassing
   reactivity (sharing a cell, or attaching a thunk) — and comment it when you do.
   Wrap sub-collections in `CellVector` so length changes invalidate downstream.

10. **A document's struct field names are its public reference vocabulary.** A
    `.field` selection step resolves by `getfield`, so field names *are* API:
    renaming a field is a breaking change to every stored selection and every
    projection that maps through it. Choose field names deliberately, and treat a
    rename as an API migration, not a local refactor.

11. **A field's declared type must admit every value the field can hold.** The
    annotation is preserved verbatim into the generated immutable snapshot
    (`IFoo`), where it becomes enforced. If a field can ever hold `nothing` as an
    empty sentinel, annotate it `Union{…, Nothing}`; a dishonest annotation stays
    silent until the first `snapshot`/`IFoo(foo)` throws.

12. **A macro-wrapped field may never hold a `Cell` or a `Function` as its
    logical value.** The auto-wrapping constructor stores a `Cell` unwrapped and
    turns a `Function` into a *computed thunk* (so the field would be called, not
    returned). If you must store a cell or callable as a value, box it (a
    one-element tuple or wrapper struct) or use a plain hand-rolled `struct`
    (as `SyntaxNodeToText` does). Any convenience constructor must be an *outer*
    constructor — the macro emits the only inner one.

13. **Do not assume two documents with equal fields are `==`.** A `@document`
    type is a `mutable struct` and keeps identity `==`/`hash`; only the immutable
    `I`-prefixed snapshot compares structurally. Code needing value comparison
    (e.g. `collect_references`) compares unwrapped *leaf values*, not whole
    documents.

14. **Domains are independent; a document owns no cross-domain edge.** A domain
    knows nothing about how it is displayed or about other domains; a document
    imports only its own slice and packages below it. All cross-domain coupling
    lives in projections (the edges), never in documents (the nodes) — this is
    what makes the domain package sliceable. Anything two slices both need is a
    framework and sinks to `base` (or `visual` if it renders), not into either
    slice.

15. **Every domain defines its own structural operations and its own insertion
    type.** A domain's edits are expressed structurally in its own terms ("insert
    element at index 3", not "delete the `[` at line 12"), and its type-in entry
    point is a per-domain `…Insertion` document whose reader interprets typed text
    in that domain's vocabulary. Generate the whole insertion kit with one
    `@domain X` line rather than re-implementing the root/placeholder/insertion/
    gesture/traits per domain.

16. **Keep the edited document in its semantic domain; widgets are presentation
    only.** The source-of-truth document being edited should generally not be a
    widget tree — project *through* widgets as a presentation layer while the
    real document stays in its own domain. Transient UI state (hover, press,
    drag, scroll offset, affine transform, splitter drag) is not document content:
    store it in cells on the relevant node, write it via a self-contained
    `ReplaceReferencedValueOperation`, and never serialize it.

17. **Prefer `search_references` / `search_objects` over hand-walking the tree,
    and scope by domain node type.** To locate a node by content, search for it
    and operate on the returned reference rather than open-coding a recursive
    descent; the search predicate runs in the input (document) domain, so match on
    the domain node type (`v isa JsonString`) — a bare string/regex query matches
    every projection of the same value in the workbench. Paths rooted at a
    sub-document or an iomap are for inspection only and are **not** selectable on
    screen; search `editor.document` when you intend to select.

## Projections — the central abstraction

18. **The four functions are the entire projection interface.** Every projection
    implements exactly `print_document`, `read_intent`, `map_reference_forward`,
    and `map_reference_backward` (declared in `ProjectionApi.jl`, dispatched on
    the concrete struct). Nothing else is universal across projections. Do not add
    a fifth generic function that projections are expected to implement. (Ordinary
    local recursion is fine — a projection may use a private helper that walks a
    *data structure*, like `SearchingProjection`'s pre-order DFS or
    `CopyingProjection`'s `ListNode` traversal; what the contract forbids is a new
    *generic descent function every projection must implement*.)

19. **All recursion flows through those four functions, and only those four (the
    recursion contract).** When a projection descends into a child, each function
    hands that child to the *child projection's own* version of the same function
    — the printer via the `recursion` argument (`print_child(recursion, child,
    …)`), the reader and both mappers via the stored `child_iomaps`. Introducing
    a fifth recursive helper breaks composition the moment a pipeline mixes a
    projection that has it with one that does not.

20. **Recurse as little as possible — one level, then delegate ("School A").** A
    projection transforms only its own single level and delegates every child to
    `recursion`, even a same-domain child. Never self-walk your input/output
    subtree dispatching on each child's concrete type and bake the whole subtree
    into your result ("School B") — that hard-codes which projection renders each
    descendant and forecloses unforeseen document/projection combinations. This
    applies to both the printer (do not flatten a child subtree) and the mappers
    (do not re-walk the input by type).

21. **Recurse through `print_child`, never open-coded.** `print_child(recursion,
    child, child_ctx)` expands to `print_document(recursion, recursion, child,
    child_ctx)` — `recursion` appears twice on purpose (the projection to invoke
    *and* that call's own recursion argument). Open-coding the doubled argument and
    getting either slot wrong silently breaks heterogeneous recursion. Pair every
    `print_child` with `make_child_context(ctx, <step to the child>)` so the child's
    root-relative reference path — and therefore its selection bookkeeping — stays
    correct.

22. **Every projection is bidirectional: a printer needs its inverse.** Every
    `print_document` needs matching reference maps (or an explicit, documented
    decision that it is printer-only, e.g. the write-only file-export projections
    `GraphicsCanvasToImageFile`/`…ToPdfFile`). Write `map_reference_forward` and
    `map_reference_backward` as the single source of truth for how a path crosses
    the projection — `print_document` wires the output selection with the forward
    map and the default `read_intent` maps operations with the backward map, so
    the pair gives you cursor navigation across the whole pipeline for free.

23. **`print_document` uses `map_reference_forward`; `read_intent` uses
    `map_reference_backward`, and the two mappers are mutual inverses.** Keep the
    two mappers as the one place a path's crossing is defined, and keep them
    inverse (modulo the documented `ProjectionReference`/flat-offset collapse). If
    the two directions ever disagree — with each other or with how the printer
    wired the output selection — the cursor mis-maps.

24. **Write a `read_intent` method only when re-targeting a reference is not
    enough.** The default `read_intent` re-targets any reference-carrying
    operation via `map_reference_backward`, so a projection that only moves the
    cursor or edits a value through a structure-preserving map needs *only* the
    two mappers. Add the 4-arg `read_intent(p, recursion, change::Intent, iomap)`
    method (returning an `Intent`) only to do more — retype an operation, recurse
    then lift, probe a child, or route by selection. Do not write the obsolete
    3-arg shim in new code.

25. **Geometry-free gesture handling belongs to the document, not the
    projection.** A gesture that reads only the document's structure and
    `selection` (insert a character, backspace, move the caret, step a structural
    selection) lives behind `read_gesture(document, gesture)` in the document's
    own reference vocabulary; a projection reader *delegates* to it and keeps only
    its geometry-dependent arms (hit-testing, visual up/down). This is what lets a
    backend that renders a domain directly (the console pipeline) reuse the
    domain's editing for free.

26. **A structural projection's reader delegates a raw gesture to the selected
    child and lifts the result.** For a raw authoring gesture, find the selected
    child from the node's `selection` and `child_iomaps`, delegate to that child's
    `read_intent`, and lift the returned operation with `reroot_operation`
    (prepending the input step that reaches the child); handle the gesture itself
    only when the child declines. The template engine's `RuleIoMap` reader already
    does this — do not special-case nested editing.

27. **A compound (node-shaped) projection stores its child IoMaps in one shared
    reactive cell and returns a `ChildrenIoMap`.** Store the per-child IoMaps in a
    single `child_iomaps::Cell` (not inline across two separate cells, which would
    instantiate different output objects and break the identity invariant),
    project the selection reactively (`Cell(() -> map_reference_forward(p, iomap,
    node.selection))` with the deferred-iomap trick), and use `ChildrenIoMap` so
    the reader and both mappers can locate the correct child IoMap when translating
    backward.

28. **Cross domains as late as possible in the mappers.** When an output
    reference points at something the projection introduced (a delimiter, bracket,
    separator, indentation) it has no input pre-image: keep input-domain steps for
    as long as the path still has a pre-image, then wrap *only the genuinely
    output-only tail* in `ProjectionReference(projection, …)` (or collapse a
    non-separately-addressable group to a single flat offset). Because
    `map_reference_forward` strips that same step, the path round-trips.

29. **Higher-order projections touch no domain; generic projections are
    input-domain-independent.** A higher-order projection's argument is always
    another projection — it must never name a concrete document type. A generic
    projection operates on any input *by structure, not by type*. Handle a
    heterogeneous tree with the type-dispatch idiom: a
    `TypeDispatchingProjection(Type => Projection, …)`, exposed behind a zero-arg
    factory (`JsonToSyntax()`, …) that returns the *bare* dispatcher; a caller
    wraps it once in a `RecursiveProjection` so children re-enter the whole
    pipeline. List dispatcher entries specific-first (an `Any =>` / fallback last),
    since they are tried in order.

30. **Use `@projection` for projection structs with reactive fields, defaulting
    the supertype.** `@projection` supplies `<: Projection` when none is written;
    use a plain `struct … <: Projection` only when the macro can't be used (a
    `Function` field, or a `Cell` read explicitly). A projection with no reactive
    fields may be a plain struct, but must then spell out `<: Projection` itself.

## References and selection

31. **All indexing is 1-based; distinguish elements from boundaries.** Elements
    are `[i]` (1-based, `ElementReference`), cursor boundaries are `{k}` (0-based,
    `PositionReference`); both are readings of the same `RangeReference(start,
    stop)` axis and apply to any sequence, whether the items are elements or
    characters. Keep this convention everywhere. Mind the two coordinate systems
    in play: a `RangeReference` stores its boundaries **0-based**, while Julia
    containers are **1-based** — convert explicitly (`start + 1`) at every
    reference↔container crossing rather than assuming one base throughout.

32. **Build and match reference paths with the DSL, not by hand.** Construct paths
    with `@reference` (or `ReferencePath(steps...)` / `@step` for programmatic
    use), and pattern-match them with `@reference_case` in mappers and readers. Do
    not cons `ConcreteReferencePath` cells by hand. `evaluate_reference(document,
    path)` is the canonical `(document, reference) → node` walk.

33. **Every concrete `Document` has a `selection::Cell`, and every
    selection-reachable child is itself a `Document`.** Selection is stored
    recursively — each node holds only the path suffix starting at its level — so
    every child a selection step descends into must be a `Document` with its own
    `selection`; wrap any bare collection that appears in a document tree in a
    `Document` type (`CellVector`, …) rather than leaving it selection-opaque.
    Terminal output (`GraphicsText`/`GraphicsRect`/`GraphicsCanvas`) is
    deliberately not a selectable container — the selection mechanism does not
    enter it.

34. **Change selection with `replace_selection!`, not a bare `set_selection!`.**
    `set_selection!` does not clear the old path first, so a branch of the old
    selection can be left behind, producing multiple visible cursors. Use
    `replace_selection!` (clear then set) whenever moving the cursor; reserve bare
    `set_selection!` for the case where you have already cleared.

35. **The empty path is a first-class whole-element selection, not an absence.**
    `EmptyReferencePath()` (written `@reference()`, matched by `∅`) means "the
    whole element here is selected" and maps across any projection by identity;
    `nothing` means "no selection." Keep the two distinct, and let whole-element
    selections round-trip for free.

36. **Folded node-type checkpoints are the canonical form; produce and consume
    them, don't fabricate them.** Selections and mapper/printer output carry a
    per-node `type` checkpoint (folded in by `set_selection!`,
    `collect_references`, and the `ProjectionTemplate` helpers). Replay a
    cross-edit reference through `get_valid_reference_prefix` /
    `evaluate_reference` (which throw/truncate on mismatch) rather than assuming a
    stored path still fits. Do not build checkpoint *steps* by hand — the
    `TypeReference` token exists only as a build-time artifact that
    `fold_reference_types` immediately folds away.

37. **Wire the output selection reactively; focus is the selection.** In
    `print_document`, set `output.selection = Cell(() ->
    map_reference_forward(p, iomap, input.selection))` so the mapping lives in one
    place (a compound projection that introduces structural nodes with no input
    counterpart wires those nodes' selection cells explicitly; a leaf-to-leaf
    projection with identical formats may instead *share* the same
    `selection::Cell`). There is no separate "focused" flag — the focused node is
    the selected one, so a container routes a coordless (keyboard) event only to
    the child its selection points at and returns `nothing` when the selection is
    not inside it, never broadcasting or falling back to a default child. Mouse
    events still hit-test by coordinate.

## Operations

38. **`evaluate_operation(editor, op)` is the one way to change the document.**
    Every edit is an `Operation` produced by a reader and applied by the editor;
    to script the editor, do exactly what a reader does — find the target
    (`search_references`/`search_objects`), build the operation, evaluate it.
    Prefer this over bespoke imperative helpers.

39. **Prefer `ReplaceReferencedValueOperation` (or its builders) before writing a
    new operation type.** Most edits just write a value into one slot, so they are
    the same operation differing only in object/slot/value; reach for
    `ReplaceReferencedValueOperation`, `replace_document`, `insert_elements`,
    `delete_elements`, or a `CompoundOperation` of them. Add a new `Operation`
    struct only for genuinely different behaviour (control flow, I/O, async,
    multi-field/structural change that is not a single splice), and declare it in
    the module that owns the affected document (or `OperationModule` for
    cross-domain ones).

40. **A new reference-carrying operation must be registered in both the default
    `read_intent` and `reroot_operation`.** Both enumerate the path-bearing
    operation types explicitly; an operation missing from either is silently
    passed through *unmapped*, leaving its reference in the wrong domain with no
    error. An operation that carries its own root (`document !== nothing`) needs no
    rerooting and should be preferred when targeting a carried object.

41. **Mutate the cells already wired into the projection graph — or null
    `editor.iomap`.** The editor builds the iomap once and, between frames,
    updates flow *only* through reactive cell writes. An `evaluate_operation` that
    swaps a whole value/subtree out from under the projection — rebinding the
    structure the iomap was built against, e.g. the whole-root swap a
    `ReplaceReferencedValueOperation` with an empty reference performs — must set
    `editor.iomap = nothing` to force a fresh `print_document`, otherwise the
    display renders stale. Conversely, an operation that expresses its change as a
    write into a cell a *computed* selection re-derives (e.g. switching a
    versioning criterion) must **not** drop the iomap — the reactive graph
    propagates it. The test is whether you rebound structure or wrote a wired cell,
    not what the change looks like to the user. Implement
    an operation's evaluation through existing primitives (`replace_selection!`,
    reactive cell writes, `QuitEditorException`), not by reaching into private
    state; the fall-through `evaluate_operation(editor, ::Any) = nothing` lets a
    reader return anything harmlessly.

## Editor, devices, and backends

42. **Keep backends behind the `Backend`/`Device` seam; the same editor runs
    unchanged across them.** A backend provides `initialize_backend!`,
    `quit_backend!`, and `measure_text`, with `read_from_devices`/
    `write_to_devices` as the `Device` interface; swapping `SdlBackend()` for
    `WebBackend()` or `ConsoleBackend()` must change nothing in the editor loop,
    pipeline, or domains. Convert platform events to the backend-agnostic device
    vocabulary (`KeyPress`, `KeyDown`, `Mouse*`, `WindowQuit`) in the backend, so
    projection reader code never sees a raw platform event; a projection that
    needs to measure text takes an injected `measure::Function` rather than the
    backend itself. A single source of truth governs any cross-backend mapping
    (e.g. `web_key_to_symbol` mirrors `sdl_keysym_to_symbol`).

43. **Add a backend/engine as an opt-in package behind a factory seam, not by
    coupling core code to the dependency.** Each external dependency or transport
    gets exactly one opt-in package that registers a method on a seam owned below —
    either a symbol-keyed `Val` factory (`make_backend(:sdl)`,
    `make_agent_server(:mcp)`, `make_database_adapter(:odbc)`, the `record_video`
    seam) or a subtype-dispatched generic (`solve_constraint_layout(::TulipConstraintSolver)`,
    `layout_graph(::AdaptagramsEngine)`, `stream_turn(::AnthropicLlm)`). Generic
    code requests capability by symbol or supertype; the
    opt-in package binds to the *narrowest* package that has what it renders and
    errors helpfully when not loaded. Requesting through a seam creates no
    dependency, which is what keeps `kernel`…`domain` runnable with none of the
    native/network dependencies installed. Output-only file export (`write_image`,
    `write_pdf`) lives beside the backend layer but does **not** subtype `Backend`
    — it has no devices or events.

44. **Profile edits with the per-frame performance counters.** The read-eval-print
    loop resets and logs `reads / computes / invalidations / writes` each frame;
    use them to find unintentional recomputation (a single keypress causing
    thousands of `computes` means something reads more cells than necessary).

## Package, layer, slice, and module structure

45. **Respect the package chain and the four-level division.** Dependencies flow
    one way, `kernel → base → visual → domain → umbrella` (plus opt-in packages);
    create a **package** only for a new external dependency or a distinct consumer
    set, a **layer** for a distinct dependency height (a layer imports only lower
    layers), a **slice** for a feature within one layer (slice→slice edges stay
    acyclic), and a **module** for a named import surface (module-per-domain,
    module-per-projection). Files are a readability boundary only and must never
    imply an API boundary the module does not enforce. See
    [architecture-rules.md](architecture-rules.md) for the full decision
    procedure.

46. **Every piece of code lives in the lowest package of its DAG whose API it
    hard-references.** Source, test, example, and harness alike sink to their
    lowest home. A seam call (`make_backend(:sdl)`) is not a reference; only a
    `using`/`import` or naming a package's types/functions anchors code. For a test
    or example, the *fixture* decides the home (a Pdf-backend test driven by a JSON
    pipeline is a domain test), not the machinery it happens to exercise.

47. **Cross-layer imports name only exported symbols.** A non-exported name is a
    module-internal detail. To share a private helper, either make the sharers
    fragments of one module (in-namespace by construction) or sink the machinery to
    a layer at or below both users and export it — never lend an internal across a
    layer boundary. Same-layer neighbours may share internals.

48. **Frameworks sink below their users via the seam pattern; only per-domain
    methods stay above.** A lower layer declares open generics (or a small
    registry); higher layers add methods *in files they already have* — multiple
    dispatch is the registration, and a couple of methods never earns a new file.
    A lower layer may *mention* a higher concept only as an opaque payload it never
    interprets; if it must *call* it, that is a seam, not a payload.

49. **Honor the projection placement invariant.** `home(projection) ≥
    max(package(input), package(output), package(every other import))`; the
    canonical home is the more-specific side (`JsonToSyntax` → the json slice,
    `ObjectToSyntax` → visual). Interfaces live with their concept as the layer's
    first file(s), not in a separate `api/` layer. A file nothing imports gets
    wired in or deleted before it gets a home — no orphan shapes the structure.

50. **Keep the main/test/example triads parallel and minimal-environment
    runnable.** Each main package has sibling `test`/`example` packages forming
    DAGs of identical shape; a test package depends only on the main package it
    tests plus test/example packages at or below its position (never a main
    package above it), and the umbrella keeps only genuinely cross-cutting or
    opt-in-coupled suites. Registering a new domain/projection means editing the
    package's entry module (`include` + `using` + `export`). This is what lets
    `test_kernel()`…`test_domain()` run without SDL/ODBC/etc. installed — do not
    break it.

## Testing and verification

51. **Run the smallest test that covers the change; never default to
    `test_all()`.** Pick the narrowest scope — a single example
    (`test_printer(json_example)`, `test_example(…)`), a single domain/stage
    (`test_json()`, `test_syntax_to_text()`), one package suite (`test_kernel()`
    …), or the cell primitive (`test_cell()`). `test_all()` is slow and floods the
    context; reach for broad sweeps only after the targeted test already passes.

52. **Every currently-failing assertion is marked `@test_broken` with a
    `# @broken:` reason.** An unmarked `Fail` or `Error` in a summary is
    unambiguously a regression from your change — `Fail + Error` must be zero after
    a passing run. A bare `@test_broken` with no reason comment is not acceptable;
    when a marker reports `Error: Unexpected Pass`, the bug is fixed — promote it
    back to `@test` and delete the comment. Reserve `@test_skip` for code that
    would crash the runner.

53. **New code ships with tests, registered in the lowest test package that can
    express them.** A new projection needs a printer test (output structure), a
    reader test (selection translation for one event), and an example so
    `run_example("my_domain")` works. Add the test file to the test package of the
    lowest main-package position that can express it (usually
    `package/domain/test`), following the existing `function test_x() … @testset
    … end` pattern.

54. **Preserve the recursion contract's external validation — add no
    per-projection introspection method.** The contract is checked externally by a
    harness that drives the four functions over composed examples (reachability,
    round-trip, printer lockstep, and the discriminating composition-substitution
    probe) and reuses the existing walkers; it must not introduce a new
    per-projection generic function of its own. New document types are covered by
    the reflexive `_walk!` automatically as long as their state lives in struct
    fields — state kept in a side table needs a dedicated test.

55. **Verify a change by driving the behaviour, not only by reading code.** Use
    the walker helpers (`walk_printer_output`, `walk_repl_loop`,
    `explore_position_selections`) and the REPL reproducers (`run_example`,
    `print_example`; `reset=true` for a fresh instance) to exercise the affected
    pipeline headlessly. The console backend and offscreen renderers
    (`write_image`, `write_pdf`) make this possible without a display, and
    development must not depend on a graphical display.

## Documentation, vocabulary, and process

56. **Use the division vocabulary exactly — package, layer, slice, module — and
    no synonyms.** Avoid "tier" and architectural "level"; say "package" or
    "layer"; say "per-package" (not "per-layer") for `test_kernel()`…; name a
    pipeline stage by the thing (the Syntax domain, the `syntax/` slice, the
    `SyntaxToText` projection), not "the syntax layer"; use "end-to-end path", not
    "vertical slice", for MVP scope. See [terminology.md](terminology.md).

57. **Do not guess names or signatures — search for them.** Use `search_api`,
    the `resource://modules`/`classes`/`functions` catalogues, the
    [orientation index](orientation.md), or ripgrep before naming a type or
    function; a hallucinated name is worse than an admitted gap. Property access
    already unwraps cells — write `node.field`, not `node.field[]`.

58. **Keep the layering guards green and let them enforce the structure.** Every
    main package has a static guard that parses the real `import ..Module` headers
    and asserts a valid topological include order, correct layer/slice membership,
    and same-or-lower-layer edges (slice acyclicity follows from the topological
    order); the export-only cross-layer-import check is enabled on the kernel guard
    today and extends to base/visual/domain as they come clean. Run
    `test_kernel_layering()` (…`test_domain_layering()`) after any structural
    change; the guard runs in ~1s without loading the package, and its error
    messages are prescriptive — they name the offending file, the module, and the
    fix — so treat those messages as part of the contract.

59. **Update the guide that documents behaviour you changed, and teach concepts
    before mechanisms.** A change that affects documented behaviour updates the
    relevant `documentation/` guide in the same change; the reading order in
    [README.md](../README.md) (concepts → architecture → reactive cells → macros →
    projection system → editor) and the per-topic guides must stay a coherent path
    in. Link the relevant `plan/` document when one exists.

60. **Keep documentation honest, and flag aspirational designs as such.** Doc and
    slide claims must be grounded in the guides and source; a design that is not
    yet implemented (e.g. the Annotation domain) must be clearly marked as a future
    sketch, not presented as callable API. When a forthcoming feature lands, update
    the corresponding guide/slide so claims stay accurate.

61. **Keep diffs focused — no unrelated reformatting.** Do not reformat lines you
    are not logically changing; keep the diff to what the change requires so review
    stays tractable.

62. **Respect the stable foundations and the roadmap ordering.** The pull-based
    reactive `Cell` system, bidirectional printer/reader projections,
    module-per-domain/projection, 1-based indexing, and the MCP AI bridge are
    settled design decisions — build on them rather than re-litigating them.
    Sequence new work to **deepen the end-to-end path first**, then **widen** (more
    domains, layouts, backends), then **distribute** (network, collaboration,
    external data).

63. **AI edits carry the same guarantees as human edits.** An AI assistant works
    the document through the same operations, references, and selection machinery
    a person does — targeting the *meaning* of the content (references and
    operations on the model), never its position on screen, and it is likewise
    unable to produce structurally invalid content. Code that exposes editing to an
    AI (the agent tools, `execute_julia_code`) routes through
    `evaluate_operation`/`search_*`, not around them, so the same invariants hold
    for both.

64. **Follow the naming law — names must be guessable in both directions.** A name
    tells you what kind of thing it is and what it does, and a concept tells you its
    name, without a lookup (see [kernel/doc/naming.md](../package/kernel/doc/naming.md)).
    Module name = filename + `Module`, and every exported name has exactly one owning
    module. Name new concepts onto the pipeline ladder **Event → Gesture → Intent →
    Operation → Document**, not alongside it: events are noun-first and suffixless
    (`WindowClose`, `KeyDown` — they report what happened), operations are
    verb-first with the `Operation` suffix (`CloseWindowOperation` — they express an
    intended edit). A projection type is a gerund stem + `Projection`
    (`FilteringProjection`); getter/derive/mutate is the `get_x` / `with_x` /
    `set_x!` trio; factories are `make_*`, predicates `is_*`, mutators end in `!`.
    Use full words, not abbreviations (`value` not `val`, `reference` not `ref`,
    `operation` not `op`); the only sanctioned compact words are `Api`, `IoMap`, the
    `I<Document>` prefix, and `ctrl`/`alt`/`meta`. Declarative macros are noun-named
    DSL keywords (`@document`, `@projection`, `@gestures`) — the one exemption from
    verb-first.

65. **Every source file opens with a module docstring stating its contract.** A
    triple-quoted docstring at the top of each file names the module and its role
    (and any invariants it upholds) — this is a uniform, load-bearing convention
    across the codebase, not optional decoration. A fragment file that shares an
    aggregator's namespace says so; a file that declares a cross-file invariant
    (e.g. the `read_intent` ⇄ `reroot_operation` sync) states it where both sides
    can find it. Keep these docstrings accurate when you change the code they
    describe — a docstring that names a function that no longer exists is a defect.

66. **Persistence crosses cell boundaries by value and never enters the reactive
    graph.** Serialization (binary and natural-format) writes a `Cell`'s *value*
    only — reading it via `getfield(c, :value)`, never `c[]`, so no spurious
    reactive dependency is registered — and never traverses a cell's `dependents`
    out into the projection-output graph. Keep this boundary intact: what is
    durable is the document's data, not the reactive machinery or the projected
    view built over it. Transient view/UI state (hover, drag, scroll, zoom) is
    projection output and is therefore excluded from serialization by construction.
