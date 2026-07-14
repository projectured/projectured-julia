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
    silent until the first `snapshot`/`IFoo(foo)` throws. Type honestly for
    *representability*, not just for the well-formed case: a field that is too
    tight silently forecloses an *intermediate* state the user's mental model
    passes through on the way between two valid ones (product requirement *Every
    intermediate state is representable*). Widen the annotation to admit the
    transient value — including one that is ill-formed in the domain's own terms —
    rather than assuming only fully-formed values ever occur (see AR-15).

12. **A macro-wrapped field may never hold a `Cell` or a `Function` as its
    logical value.** The auto-wrapping constructor stores a `Cell` unwrapped and
    turns a `Function` into a *computed thunk* (so the field would be called, not
    returned). To store a callable as a value, either box it (a one-element tuple
    or wrapper struct) or hand it a primitive cell built with
    `Cell(f; as_value = true)` — a valid cell holding `f` as its value — which the
    auto-wrapper passes through unwrapped (it only wraps non-`Cell` values). A plain hand-rolled `struct` (as `SyntaxNodeToText` does) is the third
    option. Any convenience constructor must be an *outer* constructor — the macro
    emits the only inner one.

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
    gesture/traits per domain. The per-domain `…Insertion` document is also what
    makes *every intermediate state representable* (product requirement of that
    name): as the user builds toward a well-formed value the content may pass
    through states that are ill-formed in the domain's own terms, and the
    insertion document — together with permissive field typing (AR-11) — is the
    sanctioned place to hold such a transient state rather than forbidding it. Do
    not constrain a domain's structural operations or types so tightly that a
    reachable intermediate the user pictures has nowhere to live; the architecture
    must permit that state to exist, one way or another.

16. **Keep the edited document in its semantic domain; widgets are presentation
    only.** The source-of-truth document being edited should generally not be a
    widget tree — project *through* widgets as a presentation layer while the
    real document stays in its own domain. Transient UI state (hover, press,
    drag, scroll offset, affine transform, splitter drag) is not document content:
    store it in cells on the relevant node, write it via a self-contained
    `ReplaceReferencedValueOperation`, and never serialize it.

17. **Prefer `search_references` / `search_documents` over hand-walking the tree,
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
    (`search_references`/`search_documents`), build the operation, evaluate it.
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

69. **Design every operation to be invertible; keep its inverse well-defined.**
    An `Operation` is the unit of change (AR-38), and reversibility rests on each
    applied operation having a clear inverse — the change that restores the prior
    state. General operation-log undo/redo is not yet built (it is the in-progress
    roadmap item *Undo / redo*, which "depends on the editing operations having
    well-defined inverses"), and structural-operation collaboration (OT/CRDT)
    rests on the same property; so a new `Operation` type carries a *design*
    obligation even before the log exists. Its change must have a clear inverse (a
    value replacement inverts to writing back the prior value; a splice inverts to
    the complementary splice), or the operation must be explicitly one an undo log
    skips (control-flow / IO, e.g. quitting the editor). This is a silent-breakage
    contract: an operation added per AR-39/AR-40 passes every reference-mapping
    check while quietly having no inverse, and the omission surfaces only once undo
    reaches it. Prefer `ReplaceReferencedValueOperation` and its splice builders
    (AR-39), whose inverses are already well-defined, over a bespoke operation
    whose reversal you would have to design from scratch. This requirement lives
    with the Operations section (AR-38–41); it is numbered 69 to keep the existing
    AR numbers stable. (Product requirements *Reversible editing* and *A history
    that can be revisited*.)

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
    either a symbol-keyed `Val` factory (`make_agent_server(:mcp)`,
    `make_database_adapter(:odbc)`, the `record_video` seam) or a
    subtype-dispatched generic (`solve_constraint_layout(::TulipConstraintSolver)`,
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

45. **No process-global state in the editor or the machinery it drives; one
    process must run many editors at once.** Every piece of mutable runtime state
    an editor touches — its `document`, `selection`, `iomap`, in-flight
    `operation`, `GestureRecognizer`, animation clock, and per-frame performance
    counters — must live on the `Editor` instance (or on values reachable only
    from it), never in a module-level `const` cell, `Ref`, `Dict`, or counter.
    This is a correctness requirement, not a style preference: it is what lets one
    Julia process host several independent editors side by side (product
    requirement *Many editors in one process*). Process-global holds tie the
    editors together and break that independence — two editors sharing one
    animation-time cell write conflicting elapsed values into it every frame, so
    both animations judder and each editor's tick cross-invalidates the other's
    animated cells; a shared performance-counter dict has each editor overwrite the
    other's numbers. AR-6 already forbids process-global mutable state inside
    projections and the machinery they call; this extends the same ban up to the
    editor loop, the devices, and the backends it drives — a backend or device that
    must hold per-connection state holds it on its own instance (one per editor),
    never in a global registry. State that belongs to a single *evaluation* rather
    than to an editor is instead task-local (its natural scope): the reactive
    engine's `_computing` dependency-tracking stack has been migrated from a module
    global to task-local storage, so concurrent evaluations never cross-register
    dependencies. `PerformanceCounterModule` was likewise migrated off its
    process-global `_perf` dict onto a task-local `with_performance_counters` binding
    (each editor frame binds its own store). The animation clock is a per-editor
    `Clock` (a `@cell_struct`, not a document — `cell/Clock.jl`); `run_editor!`
    ticks `editor.clock`, and every animated cell subscribes to the clock the
    printer context carries, so two editors in one process never cross-invalidate
    each other's animation graph.

    **Accepted carve-out — the wall clock.** The `Clock` behind
    `ClockModule.get_wall_clock()` is a process-global one reflecting OS time. It is a principled exception:
    exactly one writer (the `start_wall_clock_heartbeat!` background task) and
    read-only for every editor, representing the genuine singleton of real time.
    Reader-armed animations (which see no `PrinterContext` and so cannot reach the
    enclosing editor's private clock) read the wall clock; those animations
    consequently move in step across editors — the trade-off until a reader-side
    seam analogous to `PrinterContext` lands. A shared read of one real external
    truth does not reintroduce the cross-editor *write* conflict AR-45 targets.

## Package, layer, slice, and module structure

46. **Respect the package chain and the four-level division.** Dependencies flow
    one way, `kernel → base → visual → domain → umbrella` (plus opt-in packages);
    create a **package** only for a new external dependency or a distinct consumer
    set, a **layer** for a distinct dependency height (a layer imports only lower
    layers), a **slice** for a feature within one layer (slice→slice edges stay
    acyclic), and a **module** for a named import surface (module-per-domain,
    module-per-projection). Files are a readability boundary only and must never
    imply an API boundary the module does not enforce. See
    [architecture-rules.md](architecture-rules.md) for the full decision
    procedure.

47. **Every piece of code lives in the lowest package of its DAG whose API it
    hard-references.** Source, test, example, and harness alike sink to their
    lowest home. A seam call (`record_video(…)`, `default_backend()`) is not a
    reference; only a `using`/`import` or naming a package's types/functions
    anchors code. For a test
    or example, the *fixture* decides the home (a Pdf-backend test driven by a JSON
    pipeline is a domain test), not the machinery it happens to exercise.

48. **Imports name only exported symbols — the module boundary *is* the API
    boundary.** A non-exported name is a module-internal detail; no code outside the
    module that defines it may `import`/`using` that name — not from a higher layer,
    and not from a sibling module in the *same* layer. If another module needs a
    symbol, that symbol is part of the defining module's public contract and must be
    **exported**; reaching into an internal is the smell, never the fix. The only way
    to share a helper without exporting it is to make the sharers **fragments of one
    module** (same namespace by construction, so nothing is imported); otherwise sink
    the machinery to a module at or below both users and export it. Precedents: the
    `@event_case`/`@gestures` parser (same-module fragments); the transparent-Cell
    struct codegen — `@cell_struct` + `cell_struct_exprs`/`cell_struct_kw_params`/`cell_struct_kwctor`
    exported from the cell module, built on by `@document`/`@iomap`/`@projection`.
    Enforcement is staged like the layer guard itself: `check_private_imports` already
    forbids cross-*layer* internal imports; the same-layer case is enforced per
    package once its same-layer internal imports are cleaned up. An import header is
    only half the boundary, though — `XxxModule._private` reaches a non-exported name
    just as far, and bypasses the export list entirely. `qualified_reference_errors`
    closes that half (#73), with no same-layer exemption. Known remaining instance:
    `PlaybackModule` reaches into `EditorModule`'s non-exported
    `read!`/`evaluate!`/`print!`/`perf!` — fix by making Playback a fragment of the
    editor module, or by exporting the loop steps.

49. **Frameworks sink below their users via the seam pattern; only per-domain
    methods stay above.** A lower layer declares open generics (or a small
    registry); higher layers add methods *in files they already have* — multiple
    dispatch is the registration, and a couple of methods never earns a new file.
    A lower layer may *mention* a higher concept only as an opaque payload it never
    interprets; if it must *call* it, that is a seam, not a payload.

50. **Honor the projection placement invariant.** `home(projection) ≥
    max(package(input), package(output), package(every other import))`; the
    canonical home is the more-specific side (`JsonToSyntax` → the json slice,
    `ObjectToSyntax` → visual). Interfaces live with their concept as the layer's
    first file(s), not in a separate `api/` layer. A file nothing imports gets
    wired in or deleted before it gets a home — no orphan shapes the structure.

72. **An interface file declares; it never implements.** A layer's interface file
    — the contract file its module includes first (`document/Interface.jl`,
    `reference/Interface.jl`, `backend/BackendInterface.jl`, …) — carries *only* declarations:
    the module docstring, the abstract types and type aliases that form the layer's
    vocabulary, and its open generics as bodiless `function f end`. **No method
    bodies.** Not a delegation, not an accessor, and not a "trivial" default or error
    fallback either: a default is behaviour, and behaviour is implementation. It
    belongs in the sibling file that implements the contract — the default
    `step_kind` sits with the step types in `ReferenceStep.jl`, next to their
    concrete methods. Nor may an interface file hold a concrete struct, mutable or
    global state, or an algorithm. When a contract's default has no natural sibling
    home, that is the signal the layer wants an implementation fragment, not a reason
    to park behaviour in the interface. Every name an interface file declares is
    **exported** (#48): it has no private half, and its export list *is* the layer's
    API surface. The purpose is documentary — one file gives a reader the entire
    contract of a layer and nothing else — and it is what #70's seam carve-out
    already assumes when it calls an open declaration "content-free by construction".
    Machine-checked: the layering guard parses each file named in its package's
    `interface_files` map and reports every expression that implements rather than
    declares, plus any declared name its module fails to export (purity is decidable
    from the AST — a bodiless `function f end` is a one-argument `Expr(:function)`, a
    method a two-argument one). The kernel's nine contract files are enforced today;
    a package opts its own in as they come clean. Note a Julia constraint: a bodiless
    declaration may not be qualified (`function Base.peek end` is a syntax error), so a
    contract that includes a `Base` generic states it in the docstring and lets the
    implementors add the methods.

73. **Name a module with bare `using ..Xxx`; extend its generics by
    qualification. `import ..Xxx` is banned.** One import form, one extension form:

    - `using ..XxxModule` — bare, **never** a symbol list. It binds the module's
      name *and* brings its exports into scope, so one line serves both roles. A
      symbol list is noise, and the export list is already the module's declared API
      (#48).
    - `XxxModule.f(…) = …` at the definition site — this file **implements** part of
      `XxxModule`'s contract.

    The form is load-bearing, not taste. `import` makes a bare `f(…) = …` *silently
    add a method* to another layer's generic; after `using`, the same line is a
    compile error (`function XxxModule.f must be explicitly imported to be
    extended`). So the compiler — not a convention — tells a new function apart from
    an extension of another layer's contract, and #49's *"multiple dispatch is the
    registration"* becomes visible at every site instead of being inferable only from
    an import header. The codebase already worked this way at the `Base` boundary
    (`function Base.show(io::IO, s::PointReference)`); there is not one `import Base:`
    anywhere. Julia is moving the same way: on 1.12 an unqualified constructor
    extension already warns that the behaviour is deprecated.

    **Qualification is for cross-module extension only.** A file that is a *fragment
    of the defining module* (`reference/ReferenceStep.jl` and friends, which have no
    import header at all) defines bare — same namespace by construction, so nothing
    is imported and nothing is qualified. This is #48's "fragments of one module"
    carve-out.

    **A module is qualified by its real name.** A bare `using` of an alias binds the
    module the alias points at, under *that* module's name — `using
    ..BackendApiModule` (a `const` alias for `ProjecturedKernel.BackendModule`) binds
    `BackendModule`, not `BackendApiModule`. So every backend in the repo, whichever
    alias path its package uses, registers under the same canonical
    `BackendModule.initialize_backend!`.

    Two guards back this, and both are needed. `qualified_reference_errors` asserts
    every `XxxModule.sym` names an exported symbol — qualification bypasses the export
    list entirely (`XxxModule._private` reaches a non-exported name with no
    complaint), so without it #48 would hold for import headers and be unenforced
    exactly where this rule sends the traffic. It has no same-layer exemption, unlike
    `private_import_errors`: qualification is new syntax, so there is no legacy to
    grandfather. `relative_import_errors` enforces the import form itself over an
    opt-in `qualified_files` set that grows as the sweep proceeds — an honest ledger
    of what is migrated, where a shrinking exemption list over ~1400 import lines
    would not be.

    Bare `using` also means every export of every used module lands in scope, so the
    rule needs one precondition: **no two modules may export the same name with
    different bindings.** A *re-export* — the same binding object reached through
    several module names — is not a collision and Julia resolves it silently;
    distinct bindings raise `UndefVarError` on use. The precondition is
    cross-package, so `test_export_collisions` (umbrella) checks it dynamically.
    Precedent: `NothingToSyntaxLeaf`, the one such clash that ever existed, meant the
    `nothing` leaf in visual and the `*Nothing` insertion placeholder in domain; the
    more specific concept took the qualifier (`InsertionNothingToSyntaxLeaf`).

    Migrated so far: the reference-step seam (`step_kind`, `evaluate_step`,
    `dsl_build_step`, `dsl_match_step`, `dsl_step_subpath_args`) and the backend/device
    seam (`initialize_backend!`, `quit_backend!`, `measure_text`, `write_image`,
    `read_from_devices`, `write_to_devices`, …). Known remaining: the four projection
    generics (`print_document`, `read_intent`, `map_reference_forward`,
    `map_reference_backward`, ~793 sites) and `evaluate_operation` (46), which are
    entangled with `@projection`/`@iomap` codegen and get their own sweep. A macro can
    emit a qualified extension by interpolating the *module object*
    (`:(function $(ReferenceModule).step_kind(…) end)`), which needs no import at the
    call site at all.

51. **Keep the main/test/example triads parallel and minimal-environment
    runnable.** Each main package has sibling `test`/`example` packages forming
    DAGs of identical shape; a test package depends only on the main package it
    tests plus test/example packages at or below its position (never a main
    package above it), and the umbrella keeps only genuinely cross-cutting or
    opt-in-coupled suites. Registering a new domain/projection means editing the
    package's entry module (`include` + `using` + `export`). This is what lets
    `test_kernel()`…`test_domain()` run without SDL/ODBC/etc. installed — do not
    break it.

## Testing and verification

52. **Run the smallest test that covers the change; never default to
    `test_all()`.** Pick the narrowest scope — a single example
    (`test_printer(json_example)`, `test_example(…)`), a single domain/stage
    (`test_json()`, `test_syntax_to_text()`), one package suite (`test_kernel()`
    …), or the cell primitive (`test_cell()`). `test_all()` is slow and floods the
    context; reach for broad sweeps only after the targeted test already passes.

53. **Every currently-failing assertion is marked `@test_broken` with a
    `# @broken:` reason.** An unmarked `Fail` or `Error` in a summary is
    unambiguously a regression from your change — `Fail + Error` must be zero after
    a passing run. A bare `@test_broken` with no reason comment is not acceptable;
    when a marker reports `Error: Unexpected Pass`, the bug is fixed — promote it
    back to `@test` and delete the comment. Reserve `@test_skip` for code that
    would crash the runner.

54. **New code ships with tests, registered in the lowest test package that can
    express them.** A new projection needs a printer test (output structure), a
    reader test (selection translation for one event), and an example so
    `run_example("my_domain")` works. Add the test file to the test package of the
    lowest main-package position that can express it (usually
    `package/domain/test`), following the existing `function test_x() … @testset
    … end` pattern.

55. **Preserve the recursion contract's external validation — add no
    per-projection introspection method.** The contract is checked externally by a
    harness that drives the four functions over composed examples (reachability,
    round-trip, printer lockstep, and the discriminating composition-substitution
    probe) and reuses the existing walkers; it must not introduce a new
    per-projection generic function of its own. New document types are covered by
    the reflexive `_walk!` automatically as long as their state lives in struct
    fields — state kept in a side table needs a dedicated test.

56. **Verify a change by driving the behaviour, not only by reading code.** Use
    the walker helpers (`walk_printer_output`, `walk_repl_loop`,
    `explore_position_selections`) and the REPL reproducers (`run_example`,
    `print_example`; `reset=true` for a fresh instance) to exercise the affected
    pipeline headlessly. The console backend and offscreen renderers
    (`write_image`, `write_pdf`) make this possible without a display, and
    development must not depend on a graphical display.

## Documentation, vocabulary, and process

57. **Use the division vocabulary exactly — package, layer, slice, module — and
    no synonyms.** Avoid "tier" and architectural "level"; say "package" or
    "layer"; say "per-package" (not "per-layer") for `test_kernel()`…; name a
    pipeline stage by the thing (the Syntax domain, the `syntax/` slice, the
    `SyntaxToText` projection), not "the syntax layer"; use "end-to-end path", not
    "vertical slice", for MVP scope. See [terminology.md](terminology.md).

58. **Do not guess names or signatures — search for them.** Use `search_api`,
    the `resource://modules`/`classes`/`functions` catalogues, the
    [orientation index](orientation.md), or ripgrep before naming a type or
    function; a hallucinated name is worse than an admitted gap. Property access
    already unwraps cells — write `node.field`, not `node.field[]`.

59. **Keep the layering guards green and let them enforce the structure.** Every
    main package has a static guard that parses the real `import ..Module` headers
    and asserts a valid topological include order, correct layer/slice membership,
    and same-or-lower-layer edges (slice acyclicity follows from the topological
    order); the export-only cross-layer-import check and the interface-purity check
    (#72) are enabled on the kernel guard today and extend to base/visual/domain as
    they come clean. Run
    `test_kernel_layering()` (…`test_domain_layering()`) after any structural
    change; the guard runs in ~1s without loading the package, and its error
    messages are prescriptive — they name the offending file, the module, and the
    fix — so treat those messages as part of the contract.

60. **Update the guide that documents behaviour you changed, and teach concepts
    before mechanisms.** A change that affects documented behaviour updates the
    relevant `documentation/` guide in the same change; the reading order in
    [README.md](../README.md) (concepts → architecture → reactive cells → macros →
    projection system → editor) and the per-topic guides must stay a coherent path
    in. Link the relevant `plan/` document when one exists.

61. **Keep documentation honest, and flag aspirational designs as such.** Doc and
    slide claims must be grounded in the guides and source; a design that is not
    yet implemented (e.g. the Annotation domain) must be clearly marked as a future
    sketch, not presented as callable API. When a forthcoming feature lands, update
    the corresponding guide/slide so claims stay accurate.

62. **Keep diffs focused — no unrelated reformatting.** Do not reformat lines you
    are not logically changing; keep the diff to what the change requires so review
    stays tractable.

63. **Respect the stable foundations and the roadmap ordering.** The pull-based
    reactive `Cell` system, bidirectional printer/reader projections,
    module-per-domain/projection, 1-based indexing, and the MCP AI bridge are
    settled design decisions — build on them rather than re-litigating them.
    Sequence new work to **deepen the end-to-end path first**, then **widen** (more
    domains, layouts, backends), then **distribute** (network, collaboration,
    external data).

64. **AI edits carry the same guarantees as human edits.** An AI assistant works
    the document through the same operations, references, and selection machinery
    a person does — targeting the *meaning* of the content (references and
    operations on the model), never its position on screen, and it is likewise
    unable to produce structurally invalid content. Code that exposes editing to an
    AI (the agent tools, `execute_julia_code`) routes through
    `evaluate_operation`/`search_*`, not around them, so the same invariants hold
    for both.

65. **Follow the naming law — names must be guessable in both directions.** A name
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

66. **Every source file opens with a module docstring stating its contract.** A
    triple-quoted docstring at the top of each file names the module and its role
    (and any invariants it upholds) — this is a uniform, load-bearing convention
    across the codebase, not optional decoration. A fragment file that shares an
    aggregator's namespace says so; a file that declares a cross-file invariant
    (e.g. the `read_intent` ⇄ `reroot_operation` sync) states it where both sides
    can find it. Keep these docstrings accurate when you change the code they
    describe — a docstring that names a function that no longer exists is a defect.

67. **Persistence crosses cell boundaries by value and never enters the reactive
    graph.** Serialization (binary and natural-format) writes a `Cell`'s *value*
    only — reading it via `getfield(c, :value)`, never `c[]`, so no spurious
    reactive dependency is registered — and never traverses a cell's `dependents`
    out into the projection-output graph. Keep this boundary intact: what is
    durable is the document's data, not the reactive machinery or the projected
    view built over it. Transient view/UI state (hover, drag, scroll, zoom) is
    projection output and is therefore excluded from serialization by construction.

68. **No test doubles live in `main` packages.** A fake, mock, stub, or any
    canned/scripted stand-in for a real seam is test/example scaffolding: it lives
    in a `test` or `example` package and is never defined in, exported from, or
    named by `main` code — not even as a fallback. A `main` package defines only
    the real seam (the abstract type + generic) the double implements; the double
    subtypes that seam from its `test`/`example` home. Production code that finds
    no real backend fails loudly rather than fabricating a fake, so a real user is
    never served a faked result; offline/deterministic behaviour is opted into by
    the example or test that wants it (it passes an explicit double). A double may
    still be *defined* in an example package the executable bundles, but because no
    `main` path constructs one, none is reachable at runtime in production. See the
    "No test doubles in `main`" bullet in
    [architecture-rules.md](architecture-rules.md). Precedent: `FakeLlm` /
    `ScriptedLlm` moved from kernel `main` (`LlmModule`) to
    `ProjecturedKernelExample`, and `WorkbenchAssistant` dropped its `FakeLlm`
    fallback.

70. **A module's documentation describes its own contract, never its consumers.**
    A docstring or comment must not name, enumerate, or explain the higher-layer
    modules, macros, or callers that build on the code it documents — that is forward
    knowledge a lower layer cannot have without inverting the dependency direction.
    Describe what the code *is* and the contract it offers to *any* caller, as a
    self-contained service; let each consumer's own documentation state that it builds
    on this. This is the documentation-level companion to #48 (imports name only
    exported symbols) and #49 (a lower layer mentions a higher concept only as an
    opaque payload): dependencies point down in prose exactly as they do in code.
    Citing an architectural *rationale* is still allowed — "holds no global state, so
    one process can run many editors" (#45) names a requirement, not a consumer;
    "the seam `@document`/`@iomap`/`@projection` build on" names consumers and is the
    violation. Precedent: `PerformanceCounterModule` dropped its "`CellModule` imports
    this" reference, and `CellModule` dropped the
    "declarative macros `@document`/`@iomap`/`@projection` build on this" references.

    **Seam carve-out.** An open interface declaration is content-free by
    construction (`function foo end`, no signature — #72): its *docstring* is what
    describes the contract, and a contract's meaning is the shape of the
    values that flow through it. So an interface/seam file may name the
    **concepts** it bridges as forward pointers — the *kinds* of value on
    each side of the seam (a `gesture`, an `Operation`, a projection's
    output domain) — but not the specific higher-package modules,
    macros, or methods that implement it. "Maps a gesture to an
    `Operation` expressed against `document`'s reference vocabulary" names
    concepts; "the `@gestures` catch-all in `GestureBindingModule`
    supplies the default" names a consumer and is the violation. The
    carve-out applies only to a *seam file* (one whose job is to declare
    the open interface) and only to the *concepts* the seam bridges;
    everything else in AR-70 still holds. Prefer redistributing the seam
    to the lowest layer where every concept it names is already
    introduced (AR-47): once every concept sits at or below the seam, the
    forward-concept references become backward, not forward, and the
    carve-out is unnecessary.

71. **A comment carries only what the code cannot — keep it tight.** A comment
    earns its place by holding information that is neither visible in the code
    nor one hop away in a docstring: a constraint, an invariant, a rejected
    alternative, the reason an expected method is *absent*, a non-obvious
    consequence. Everything else is noise that rots. Specifically, do not restate
    what the next line does; do not re-explain a function, macro, or generic that
    is documented at its own definition (its owning module is the single place —
    #70); do not summarise the code beneath a section banner (the banner names the
    section, nothing more); and do not narrate the change that produced the code
    ("was previously", "moved from", "now uses X") — history belongs in the `plan/`
    document, never in the source. Prefer a docstring on the definition over a
    comment above the call. Two comments saying the same thing in two files is one
    comment too many, and when a comment and the code drift apart, the comment is
    the bug. Precedent: JSON's insertion-factory block shed a paragraph restating
    `make_insertion_document`'s own docstring and `@with_selection`'s semantics,
    keeping only the one line no reader could derive — why an empty `JsonNumber` is
    selected whole while an empty `JsonString` gets a caret at position 0.
