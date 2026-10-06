# Architectural requirements — how to develop ProjecturEd

> **Kind:** rule · **Status:** current · **Stands on:** [accepted-requirements.md](../requirement/accepted-requirements.md), [architecture-decisions.md](../design/architecture-decisions.md)

This document collects the **internal development requirements** the project
must be built to, so that it stays tractable and maintainable as it grows. It
is for contributors, developers, and AI assistants working in the codebase
alike.

It is deliberately distinct from its two siblings:

- [accepted-requirements.md](../requirement/accepted-requirements.md) states what the editor must do as
  **externally observable capabilities** (behaviour of the editor, usability of
  the project). Those are *product* requirements, carrying `PR-` IDs.
- [architecture-rules.md](architecture-rules.md) is the decision procedure for
  **where a piece of code lives** (package / layer / slice / module). Those are
  *placement* rules.

This document states the **invariants and conventions every change must
respect** — the load-bearing contracts the code assumes you understand, and
that break silently (a hang, a stale render, an un-composable projection, a
mis-mapped cursor) rather than loudly when violated. Each requirement is a few
sentences and carries a symbolic ID — `PAR-PURE-THUNK`, `PAR-PER-EDITOR-STATE` —
to cite in reviews, commit messages, guard failures, and plans. The division
vocabulary (package / layer / slice / module) is used exactly as defined in
[division-terminology.md](division-terminology.md).

**A prefix names the repository that owns the rule**, so a citation says which
document to open without a link. The downstream projects cite these rules as
`PAR-…`:

| repository | product | architectural |
| --- | --- | --- |
| **projectured-julia** | **`PR-`** | **`PAR-`** |

Every other repository allocates its own pair of prefixes and states them in
its own documents. This one names no repository but itself.

Three rules govern the IDs:

- **An ID is permanent and is never reused.** Retiring a requirement retires its
  ID; a deleted one is never reassigned to a different rule.
- **The ID names the rule, not the section it sits in**, so it survives
  regrouping. Adding a requirement appends a section and an index row; nothing
  else moves, and no existing citation changes.
- **Each ID is a heading**, so a citation can link to the requirement itself:
  `[PAR-PURE-THUNK](architecture-invariants.md#par-pure-thunk)`.

When a rule here and a rule in a per-topic guide appear to conflict, the
per-topic guide wins for its topic and this document should be corrected; when
this document does not answer a "may I…?" question, extend it rather than
improvise (the same principle [architecture-rules.md](architecture-rules.md)
states for placement).

---

## Index

Every architectural requirement in document order. The ID links to the
requirement; the rule is its own lead sentence.

**Reactivity — the cell engine**

| ID | Rule |
| --- | --- |
| [PAR-PURE-THUNK](#par-pure-thunk) | Every reactive computation must be a pure function of the cells it reads |
| [PAR-NO-WRITE-IN-THUNK](#par-no-write-in-thunk) | A computation must never write another cell or mutate shared document state |
| [PAR-STORE-THEN-DRAIN](#par-store-then-drain) | Data enters a running editor through a store and a drain, never through a direct write |
| [PAR-ACYCLIC-CELLS](#par-acyclic-cells) | The cell dependency graph must stay acyclic |
| [PAR-MONOTONE-INVALIDATION](#par-monotone-invalidation) | Never hand-set `valid` and never partially invalidate |
| [PAR-WRITE-DRIVEN-PROPAGATION](#par-write-driven-propagation) | Treat propagation as write-driven, not value-driven |
| [PAR-NO-PROJECTION-GLOBALS](#par-no-projection-globals) | No global mutable state in projections (or the machinery they call) |
| [PAR-DERIVED-CELLS](#par-derived-cells) | Use the reactive engine for derived state; do not read a cell before its wiring is complete |
| [PAR-FINEST-GRANULARITY](#par-finest-granularity) | Choose the reactive container that preserves the finest granularity |

**Documents and domains**

| ID | Rule |
| --- | --- |
| [PAR-FIELDS-ARE-CELLS](#par-fields-are-cells) | Every document field is a `Cell`, accessed transparently |
| [PAR-FIELD-NAMES-ARE-API](#par-field-names-are-api) | A document's struct field names are its public reference vocabulary |
| [PAR-WIDE-FIELD-TYPES](#par-wide-field-types) | A field's declared type must admit every value the field can hold |
| [PAR-NO-NESTED-CELL](#par-no-nested-cell) | A macro-wrapped field may never hold a `Cell` or a `Function` as its logical value |
| [PAR-DOCUMENT-IDENTITY](#par-document-identity) | Do not assume two documents with equal fields are `==` |
| [PAR-NO-EDITOR-IN-DOCUMENT](#par-no-editor-in-document) | No document stores the editor, not even in a closure or a `Ref` that a field holds |
| [PAR-DOMAINS-INDEPENDENT](#par-domains-independent) | Domains are independent; a document owns no cross-domain edge |
| [PAR-DOMAIN-OWNS-EDITS](#par-domain-owns-edits) | Every domain defines its own structural operations and its own insertion type |
| [PAR-WIDGETS-ARE-PRESENTATION](#par-widgets-are-presentation) | Keep the edited document in its semantic domain; widgets are presentation only |
| [PAR-SEARCH-DONT-WALK](#par-search-dont-walk) | Prefer `search_references` / `search_documents` over hand-walking the tree, and scope by domain node type |

**Projections — the central abstraction**

| ID | Rule |
| --- | --- |
| [PAR-FOUR-FUNCTIONS](#par-four-functions) | The four functions are the entire projection interface |
| [PAR-RECURSION-CONTRACT](#par-recursion-contract) | All recursion flows through those four functions, and only those four (the recursion contract) |
| [PAR-DELEGATE-ONE-LEVEL](#par-delegate-one-level) | Recurse as little as possible — one level, then delegate ("School A") |
| [PAR-DECIDE-LOCALLY](#par-decide-locally) | Nothing is decided globally that can be decided locally |
| [PAR-NO-GLOBAL-ROUTING](#par-no-global-routing) | A route is fixed in advance only to return an operation from one place, or to give a drag to the part that started it; every other input travels by position or by the choice of each projection |
| [PAR-RECURSE-VIA-PRINT-CHILD](#par-recurse-via-print-child) | Recurse through `print_child`, never open-coded |
| [PAR-BIDIRECTIONAL-PROJECTION](#par-bidirectional-projection) | Every projection is bidirectional: a printer needs its inverse |
| [PAR-MAPPERS-ARE-INVERSES](#par-mappers-are-inverses) | `print_document` uses `map_reference_forward`; `read_intent` uses `map_reference_backward`, and the two mappers are mutual inverses |
| [PAR-PREFER-REFERENCE-RETARGET](#par-prefer-reference-retarget) | Write a `read_intent` method only when re-targeting a reference is not enough |
| [PAR-NO-NEW-SYNTHETIC-EVENT](#par-no-new-synthetic-event) | The reader chain reads what a person does; add no `SyntheticEvent` type and no `read_intent` method for a payload that carries an operation, a request or a question |
| [PAR-REPEATED-MOVE-WRITES-NOTHING](#par-repeated-move-writes-nothing) | A move to the point of the last move writes no cell |
| [PAR-LIGHT-KEEPS-LAYOUT](#par-light-keeps-layout) | A light changes no size and no place |
| [PAR-GEOMETRY-FREE-IN-DOCUMENT](#par-geometry-free-in-document) | Geometry-free gesture handling belongs to the document, not the projection |
| [PAR-DELEGATE-AND-LIFT](#par-delegate-and-lift) | A structural projection's reader delegates a raw gesture to the selected child and lifts the result |
| [PAR-SHARED-CHILDREN-IOMAP](#par-shared-children-iomap) | A compound (node-shaped) projection stores its child IoMaps in one shared reactive cell and returns a `ChildrenIoMap` |
| [PAR-STABLE-IOMAP-IDENTITY](#par-stable-iomap-identity) | A projection's IoMap keeps its identity; its varying parts are computed cells and its children reconcile by identity and index |
| [PAR-CROSS-DOMAIN-LATE](#par-cross-domain-late) | Cross domains as late as possible in the mappers; an introduced part maps forward and backward |
| [PAR-HIGHER-ORDER-IS-DOMAIN-FREE](#par-higher-order-is-domain-free) | Higher-order projections touch no domain; generic projections are input-domain-independent |
| [PAR-USE-PROJECTION-MACRO](#par-use-projection-macro) | Use `@projection` for projection structs with reactive fields, defaulting the supertype |

**References and selection**

| ID | Rule |
| --- | --- |
| [PAR-ONE-BASED-INDEXING](#par-one-based-indexing) | All indexing is 1-based; distinguish elements from boundaries |
| [PAR-REFERENCE-DSL](#par-reference-dsl) | Build and match reference paths with the DSL, not by hand; a mapper is one `@reference_case` |
| [PAR-EVERY-DOCUMENT-HAS-SELECTION](#par-every-document-has-selection) | Every concrete `Document` has a `selection::Cell`, and every selection-reachable child is itself a `Document` |
| [PAR-REPLACE-SELECTION](#par-replace-selection) | Change selection with `replace_selection!`, not a bare `set_selection!` |
| [PAR-SELECTION-WRITTEN-AT-ROOT](#par-selection-written-at-root) | Every write of the live selection starts at the root document; a reader reads its own selection and never searches below |
| [PAR-EMPTY-PATH-IS-SELECTION](#par-empty-path-is-selection) | The empty path is a whole-element selection in its own right, not an absence |
| [PAR-FOLDED-CHECKPOINTS](#par-folded-checkpoints) | Folded node-type checkpoints are the canonical form; produce and consume them, don't fabricate them |
| [PAR-REACTIVE-OUTPUT-SELECTION](#par-reactive-output-selection) | Wire the output selection reactively; focus is the selection |

**Operations**

| ID | Rule |
| --- | --- |
| [PAR-ONE-WAY-TO-EDIT](#par-one-way-to-edit) | `evaluate_operation(editor, op)` is the one way to change the document |
| [PAR-READER-IS-PURE](#par-reader-is-pure) | A reader never mutates; it returns an operation |
| [PAR-REACTIVE-OUTPUT-STRUCTURE](#par-reactive-output-structure) | A projection's output structure is reactive, not re-printed |
| [PAR-PREFER-REPLACE-VALUE](#par-prefer-replace-value) | Prefer `ReplaceReferencedValueOperation` (or its builders) before writing a new operation type |
| [PAR-REGISTER-NEW-OPERATION](#par-register-new-operation) | A new reference-carrying operation must be registered in both the default `read_intent` and `reroot_operation` |
| [PAR-MUTATE-OR-NULL-IOMAP](#par-mutate-or-null-iomap) | Mutate the cells already wired into the projection graph — or null `editor.iomap` |
| [PAR-INVERTIBLE-OPERATIONS](#par-invertible-operations) | Design every operation to be invertible; keep its inverse well-defined |

**Editor, devices, and backends**

| ID | Rule |
| --- | --- |
| [PAR-MANY-WINDOWS](#par-many-windows) | A window is a window on every backend, and a tooltip is drawn in one of its own |
| [PAR-BACKEND-SEAM](#par-backend-seam) | Keep backends behind the `Backend`/`Device` seam; the same editor runs unchanged across them |
| [PAR-OPT-IN-DEPENDENCY](#par-opt-in-dependency) | Add a backend/engine as an opt-in package behind a factory seam, not by coupling core code to the dependency |
| [PAR-PROFILE-WITH-COUNTERS](#par-profile-with-counters) | Profile edits with the per-frame performance counters |
| [PAR-PER-EDITOR-STATE](#par-per-editor-state) | No process-global state in the editor or the machinery it drives; one process must run many editors at once |
| [PAR-REPORT-NEVER-THROWS](#par-report-never-throws) | A fault report never throws, and a barrier never swallows a fault in silence |

**Package, layer, slice, and module structure**

| ID | Rule |
| --- | --- |
| [PAR-PACKAGE-CHAIN](#par-package-chain) | Respect the package chain and the four-level division |
| [PAR-LOWEST-PACKAGE](#par-lowest-package) | Every piece of code lives in the lowest package of its DAG whose API it hard-references |
| [PAR-MODULE-BOUNDARY-IS-API](#par-module-boundary-is-api) | Imports name only exported symbols — the module boundary *is* the API boundary |
| [PAR-FRAMEWORKS-SINK](#par-frameworks-sink) | Frameworks sink below their users via the seam pattern; only per-domain methods stay above |
| [PAR-PROJECTION-PLACEMENT](#par-projection-placement) | Honor the projection placement invariant |
| [PAR-INTERFACE-DECLARES-ONLY](#par-interface-declares-only) | An interface file declares; it never implements |
| [PAR-QUALIFIED-EXTENSION](#par-qualified-extension) | Import the names a file extends; name every other module with bare `using ..Xxx`. The compiler does not check it, so a guard does |
| [PAR-PARALLEL-TRIADS](#par-parallel-triads) | Keep the main/test/example triads parallel and minimal-environment runnable |

**Testing and verification**

| ID | Rule |
| --- | --- |
| [PAR-SMALLEST-TEST](#par-smallest-test) | Run the smallest test that covers the change; never default to `test_all()` |
| [PAR-MARK-BROKEN-TESTS](#par-mark-broken-tests) | Every currently-failing assertion is marked `@test_broken` with a `# @broken:` reason |
| [PAR-NEW-CODE-SHIPS-TESTS](#par-new-code-ships-tests) | New code ships with tests, registered in the lowest test package that can express them |
| [PAR-NO-INTROSPECTION-METHOD](#par-no-introspection-method) | Preserve the recursion contract's external validation — add no per-projection introspection method |
| [PAR-DRIVE-THE-BEHAVIOUR](#par-drive-the-behaviour) | Verify a change by driving the behaviour, not only by reading code |

**Documentation, vocabulary, and process**

| ID | Rule |
| --- | --- |
| [PAR-DIVISION-VOCABULARY](#par-division-vocabulary) | Use the division vocabulary exactly — package, layer, slice, module — and no synonyms |
| [PAR-NEVER-GUESS-NAMES](#par-never-guess-names) | Do not guess names or signatures — search for them |
| [PAR-GREEN-LAYERING-GUARDS](#par-green-layering-guards) | Keep the layering guards green and let them enforce the structure |
| [PAR-UPDATE-THE-GUIDE](#par-update-the-guide) | Update the guide that documents behaviour you changed, and teach concepts before mechanisms |
| [PAR-HONEST-DOCS](#par-honest-docs) | Keep documentation honest, and flag aspirational designs as such |
| [PAR-FOCUSED-DIFFS](#par-focused-diffs) | Keep diffs focused — no unrelated reformatting |
| [PAR-STABLE-FOUNDATIONS](#par-stable-foundations) | Respect the stable foundations and the roadmap ordering |
| [PAR-AI-SAME-GUARANTEES](#par-ai-same-guarantees) | AI edits carry the same guarantees as human edits |
| [PAR-NAMING-LAW](#par-naming-law) | Follow the naming law — names must be guessable in both directions |
| [PAR-MODULE-DOCSTRING](#par-module-docstring) | Every source file opens with a module docstring stating its contract |
| [PAR-PERSISTENCE-BY-VALUE](#par-persistence-by-value) | Persistence crosses cell boundaries by value and never enters the reactive graph |
| [PAR-NO-TEST-DOUBLES-IN-MAIN](#par-no-test-doubles-in-main) | No test doubles live in `main` packages |
| [PAR-NO-CONSUMER-DOCS](#par-no-consumer-docs) | A module's documentation describes its own contract, never its consumers |
| [PAR-TIGHT-COMMENTS](#par-tight-comments) | A comment carries only what the code cannot — keep it tight |
| [PAR-CITE-EXCEPTIONS-ONLY](#par-cite-exceptions-only) | Cite an architectural requirement only to flag an exception, never to announce compliance |

## Reactivity — the cell engine

### PAR-PURE-THUNK

**Every reactive computation must be a pure function of the cells it reads.** A
computation, `@computation …`, and the parts of `print_document` that build one must
have no side effects and must depend only on the cells it reads — no clocks,
RNG, or external mutable state. A computation may run zero, one, or many times per
logical change and its cached result is reused until invalidation, so impurity
produces a wrong cache, not just a style smell. This is a correctness
requirement.

**Accepted carve-out — a write to a collector outside the graph.**
The requirement is that the *cached result* be right: a computation that runs many
times for one logical change must leave the same value behind. A write to an
object with two properties changes no result: no cell depends on the object, and
no computation reads it. A count in such an object can grow at each run, because
no cached value can see it. `PAR-NO-WRITE-IN-THUNK` carries the same carve-out and
names the case: the fault store. A counter or a log that a cell or a computation
reads does not qualify, and a write to it stays forbidden.

### PAR-NO-WRITE-IN-THUNK

**A computation must never write another cell or mutate shared document state.**
Writing `other_cell[] = v` from inside a cell computation invalidates that
cell's consumers *mid-computation*, making recomputation order-dependent and
the graph inconsistent (graphics-domain cells do have consumers, e.g.
`GraphicsCaching`). To preserve output-object identity across recomputes, reuse
a *persistent* object whose fields are `set_cell_computation!` cells that **derive**
from the upstream layout cell — do not rebuild objects, and do not
reuse-then-mutate them with imperative cell writes.

**Accepted carve-out — a plain collector outside the reactive graph.** The ban
protects one thing: a write in the middle of a computation invalidates that
cell's consumers mid-computation, so recomputation becomes order-dependent and
the graph inconsistent. An object that is not a cell and has no dependents can
not do that, so a computation may write one. The fault store
(`source/kernel/fault/FaultStore.jl`) is the case the carve-out was written for,
and it exists because of this rule rather than in spite of it: a printer throws
inside the computation that derives its output, not inside `print_document`, so the
barrier has to catch inside the computation — and the message log it reports to is a
document made of cells, which the computation may not write. It writes the store
instead, and the editor's frame drains the store into the log afterwards, on its
own task, outside every computation. Two properties make it safe, and a collector that
lacks either does not qualify: **no cell depends on it**, so no consumer can be
invalidated half way; and **no computation reads it**, so no cached value depends on
what it holds. A count in it can grow at each run of a computation. The key of a
record keeps the store small, because the capacity counts keys; the key does not
keep the cache right.

The editor's other feed stores — the inbox, the message log store, the frame
measurement store — share the shape but do not need the carve-out: their producers
run on ordinary tasks, outside every computation, so this ban is not in play for
them. Only a store a computation itself writes must have the two properties above,
and the fault store is the one that does.

**Accepted carve-out — a new cell that the same run made.** A computation can write
a cell that it made in the same run, before it gives the cell out. Until then no
cell depends on the new cell, so the write invalidates nothing. The computation
reads such a cell only with `peek`, so that the cell gets no dependent before the
write. The template walk of `@projection_template` does this: a nested template
builds an output node inside the computation of its parent, reads the blueprint
of that node with `peek`, and completes its cells.

### PAR-STORE-THEN-DRAIN

**Data enters a running editor through a store and a drain, never through a
direct write.** A producer on any task — a logger, a simulation driver, a
barrier inside a computation — writes a plain store outside the reactive graph; the
write never blocks and never touches a cell. The editor drains the store into
the target document on its own task, once per frame, before `run_read_stage!`
(`drain_feeds!`; the fault report at the top of `run_frame!` is the same
motion). Only the editor task writes a document a running editor shows. The
heartbeat of a wall clock is the accepted exception: `start_wall_clock!` writes
the time cell of its clock from a task of its own, on the thread of the task that
reads the clock. A producer that wants a frame soon calls the wake function it was
given (`wake_editor!`, or the callback its store received at registration); it
never reaches into the editor. The inbox (`post_operation!`) is the queue-shaped
case of the same rule, for a payload that is an edit: ordered, applied exactly
once, with backpressure.

### PAR-ACYCLIC-CELLS

**The cell dependency graph must stay acyclic.** `_recompute!` evaluates a computation
while its cell is on the computing stack; a cell that transitively reads
itself recurses forever. The engine records no edge for a *direct* self-read,
but that read recurses too, and the engine detects no cycle, so a computed cell
must never read itself, directly or through any chain.

### PAR-MONOTONE-INVALIDATION

**Never hand-set `valid` and never partially invalidate.** Invalidation is
monotone (an invalid cell implies all its transitive dependents are already
invalid), and the engine's early-stop walk relies on it. `_recompute!` is the
only thing that re-validates a cell. Setting `valid` by hand, or invalidating
only a subset of dependents, breaks the early-stop and leaves cells stale
forever.

### PAR-WRITE-DRIVEN-PROPAGATION

**Treat propagation as write-driven, not value-driven.** Writing a cell
invalidates its dependents unconditionally — there is no `old == new`
short-circuit, and a computation that returns an unchanged value does not stop
propagation. Consequently `c[] = c[]` is not free: a printer that rewrites
`selection` (or any cell) every frame pays to recompute the whole subtree that
reads it. Write a cell only when its value actually needs to change.

### PAR-NO-PROJECTION-GLOBALS

**No global mutable state in projections (or the machinery they call).** No
module-level `Dict`/`Ref`/counter populated at runtime. Every cache, memo, or
reconciliation table must be created *per projection invocation* and live in
that invocation's `IoMap` or in its cells' closures. Global state silently
leaks across unrelated documents rendered in the same process, is never
evicted, and corrupts under the editor's reuse of one process for many
documents. A projection's own private reconciliation cache (a plain `Dict` in a
cell closure, observed by no other node) is the correct way to key reuse.

### PAR-DERIVED-CELLS

**Use the reactive engine for derived state; do not read a cell before its
wiring is complete.** Express derived values as computed cells so the system
can invalidate them, rather than caching them by hand. During construction of a
struct whose iomap wiring is not yet finished, defer the read with
`Cell(@computation …)` (the deferred-iomap trick) instead of reading the cell
eagerly.

### PAR-FINEST-GRANULARITY

**Choose the reactive container that preserves the finest granularity.** Use
`CellVector` for finite, indexed collections (each slot is its own `Cell`, so a
write to one slot invalidates only that slot's readers) and `ListNode` for
sequences that are addressed relative to a node or may extend indefinitely (its
lazy `prev`/`next` make copying an unbounded list O(1)). Keep the per-slot
granularity intact: a structural change updates the outer `elements` cell
(invalidating shape-dependent readers), while a value change touches only the
affected slot — do not collapse this into a single coarse cell.

## Documents and domains

### PAR-FIELDS-ARE-CELLS

**Every document field is a `Cell`, accessed transparently.** Declare domain
types with `@document` (or `@cell_struct` for a non-framework transparent
struct); the macro wraps every field in a `Cell` and generates
`getproperty`/`setproperty!` so `doc.field` and `doc.field = v` read and write
the underlying cell. Do not hand-roll cell wrapping, and do not reach for the
raw cell via `getfield(obj, :field)` unless you are deliberately bypassing
reactivity (sharing a cell, or attaching a computation) — and comment it when you do.
Wrap sub-collections in `CellVector` so length changes invalidate downstream.

### PAR-FIELD-NAMES-ARE-API

**A document's struct field names are its public reference vocabulary.** A
`.field` selection step resolves by `getfield`, so field names *are* API:
renaming a field is a breaking change to every stored selection and every
projection that maps through it. Choose field names deliberately, and treat a
rename as an API migration, not a local refactor.

### PAR-WIDE-FIELD-TYPES

**A field's declared type must admit every value the field can hold.** The
annotation is preserved verbatim into the generated immutable snapshot
(`ICFoo`), where it becomes enforced. If a field can ever hold `nothing` as an
empty sentinel, annotate it `Union{…, Nothing}`; a dishonest annotation stays
silent until the first `snapshot`/`ICFoo(foo)` throws. Type honestly for
*representability*, not just for the well-formed case: a field that is too
tight silently forecloses an *intermediate* state the user's mental model
passes through on the way between two valid ones (product requirement
PR-INTERMEDIATE-STATES). Widen the annotation to admit the transient value —
including one that is ill-formed in the domain's own terms — rather than
assuming only fully-formed values ever occur (see PAR-DOMAIN-OWNS-EDITS).

### PAR-NO-NESTED-CELL

**A macro-wrapped field may never hold a `Cell` or a `Computation` as its logical
value.** Both are cell vocabulary, and the auto-wrapping constructor consumes
them rather than storing them. A cell that a constructor gets becomes the cell of
the field, whatever type of value it holds, and a `Computation` becomes the
field's *derivation*, making it a computed cell. The declared type of a field is
the type that the field holds at rest. The reactive layout does not enforce it,
because an edit passes through intermediate values, such as a text to parse or a
document of another domain that a projection gives meaning to. The kind layouts
(`ImmutableCell`, `MutableCell`) check a raw value and a write against the
declared type. To hold either as
data, box it (a one-element tuple or wrapper struct) or use a plain hand-rolled
`struct` (as `SyntaxCompoundToText` does). Any convenience constructor must be
an *outer* constructor — the macro emits the only inner one.

A `Function`, by contrast, is an ordinary value and needs no ceremony: a field
may hold a callback, predicate, or factory, and `field` reads it back
uncalled. Computedness is stated, never inferred — `Computation(f)` is what makes
a field a derivation, so a bare `f` is always data.

### PAR-DOCUMENT-IDENTITY

**Do not assume two documents with equal fields are `==`.** The cell layout of a
`@document` type is an immutable struct that holds one cell for each field, and
`===` compares it cell by cell. A reactive cell and a mutable cell compare by
identity, so two documents built apart with equal contents are not `==`. Only
`ICFoo`, whose cells are immutable too, compares structurally. Code needing
value comparison (e.g. a string query of `search_documents`) compares unwrapped
*leaf values*, not whole documents.

### PAR-NO-EDITOR-IN-DOCUMENT

**No document stores the editor, not even in a closure or a `Ref` that a field
holds.** A field of a `@document` must not hold the `Editor`. Neither must a
closure, a `Ref` or any other value that a field holds, such as a session object
that knows the editor. An act that needs the editor gets it when the editor
evaluates the act: an `Operation` receives it in `evaluate_operation(editor,
operation)`, a callback takes it as an argument, and a verb takes `editor` as its
first argument.

A document is data that a view shows, a copy copies, a save writes and `show`
prints. A path from it to the editor makes each of these walk into the whole
editor, and it ties the data to one window. A plain struct of a session that is
not a document, such as the store that a feed drains, is outside this rule.

### PAR-DOMAINS-INDEPENDENT

**Domains are independent; a document owns no cross-domain edge.** A domain
has no reference to a projection and none to another domain; a document
imports only its own slice and packages below it. All cross-domain coupling
lives in projections (the edges), never in documents (the nodes) — this is what
makes the domain package sliceable. Anything two slices both need is a
framework and sinks to the platform slice that owns the concept, not into either
slice.

### PAR-DOMAIN-OWNS-EDITS

**Every domain defines its own structural operations and its own insertion
type.** A domain's edits are expressed structurally in its own terms ("insert
element at index 3", not "delete the `[` at line 12"), and its type-in entry
point is a per-domain `…Insertion` document whose reader interprets typed text
in that domain's vocabulary. Generate the whole insertion kit with one `@domain
X` line rather than re-implementing the root/placeholder/insertion/
gesture/traits per domain. The per-domain `…Insertion` document is also what
makes *every intermediate state representable* (product requirement
PR-INTERMEDIATE-STATES): as the user builds toward a well-formed value the
content may pass through states that are ill-formed in the domain's own terms,
and the insertion document — together with permissive field typing
(PAR-WIDE-FIELD-TYPES) — is the sanctioned place to hold such a transient state
rather than forbidding it. Do not constrain a domain's structural operations or
types so tightly that a reachable intermediate the user pictures has nowhere to
live; the architecture must permit that state to exist, one way or another.

### PAR-WIDGETS-ARE-PRESENTATION

**Keep the edited document in its semantic domain; widgets are presentation
only.** The source-of-truth document being edited should generally not be a
widget tree — project *through* widgets as a presentation layer while the real
document stays in its own domain. Transient UI state (hover, press, drag,
scroll offset, affine transform, splitter drag) is not document content: store
it in cells on the relevant node, write it via a self-contained
`ReplaceReferencedValueOperation`, and never serialize it.

### PAR-SEARCH-DONT-WALK

**Prefer `search_references` / `search_documents` over hand-walking the tree,
and scope by domain node type.** To locate a node by content, search for it and
operate on the returned reference rather than open-coding a recursive descent;
the search predicate runs in the input (document) domain, so match on the
domain node type (`v isa JsonString`) — a bare string/regex query matches every
occurrence of the same value, wherever it recurs in the document. Paths rooted at a sub-document
or an iomap are for inspection only and are **not** selectable on screen;
search `editor.document` when you intend to select.

## Projections — the central abstraction

### PAR-FOUR-FUNCTIONS

**The four functions are the entire projection interface.** Every projection
implements exactly `print_document`, `read_intent`, `map_reference_forward`,
and `map_reference_backward` (declared in `ProjectionInterface.jl`, dispatched on the
concrete struct). Nothing else is universal across projections. Do not add a
fifth generic function that projections are expected to implement. (Ordinary
local recursion is fine — a projection may use a private helper that walks a
*data structure*, like `SearchingProjection`'s pre-order DFS or
`CopyingProjection`'s `ListNode` traversal; what the contract forbids is a new
*generic descent function every projection must implement*.)

### PAR-RECURSION-CONTRACT

**All recursion flows through those four functions, and only those four (the
recursion contract).** When a projection descends into a child, each function
hands that child to the *child projection's own* version of the same function —
the printer via the `recursion` argument (`print_child(recursion, child, …)`),
the reader and both mappers via the stored `child_iomaps`. Introducing a fifth
recursive helper breaks composition the moment a pipeline mixes a projection
that has it with one that does not.

### PAR-DELEGATE-ONE-LEVEL

**Recurse as little as possible — one level, then delegate ("School A").** A
projection transforms only its own single level and delegates every child to
`recursion`, even a same-domain child. Never self-walk your input/output
subtree dispatching on each child's concrete type and bake the whole subtree
into your result ("School B") — that hard-codes which projection renders each
descendant and forecloses unforeseen document/projection combinations. This
applies to both the printer (do not flatten a child subtree) and the mappers
(do not re-walk the input by type).

### PAR-DECIDE-LOCALLY

**Nothing is decided globally that can be decided locally.** A central component
(a wrapper that gives one answer for all the parts, a walker over the parts, a
registry that answers for them) gives a behavior only when no part can give it,
and its documentation says why. The work that a part can do stays in the part, and a wrapper does only the
piece that spans the parts, such as keeping one window for the whole screen.
The projections on the path must be able to change and control what an input
means: a meaning is an operation that goes up through them, and each can change
it, drop it, or answer in its place. A central component that gives the answer
for them takes this away, and the projections stop composing, because a projection can skip or
change any part for its own reason, which a central component can not see.

### PAR-NO-GLOBAL-ROUTING

**A route is fixed in advance only to return an operation from one place, or to
give a drag to the part that started it.** An intent carries a route
(`Intent.route`) when an operation must come back from one specific projection:
a verb that the assistant or a command calls acts at a place, and
`read_rooted_operation` carries the operation there and back. A part that starts
a drag answers `StartDragOperation` with its own path, and the drag wrapper sends
that part the parts of its drag (`DragMove`, `DragEnd`, `DragCancel`) by that
path until the drag ends. The part chose the route itself, so no global
component chooses the part, and the raw events of the drag still go by
position. Every other input travels with no route decided:

- a mouse event and a mouse gesture, such as a click or a dwell, go down by
  position: each container chooses the child at the point, moves the point into
  the frame of the child, and can take the input itself;
- a key goes where each projection sends it, which is usually along the
  selection.

Apart from the drag that a part started, the path of an input is never fixed by
a global component, such as a tracker or a wrapper at the screen. With such a
component, the part is chosen before the
readers run, and no projection on the path can take the input or send it to
another child (PAR-DECIDE-LOCALLY).

### PAR-RECURSE-VIA-PRINT-CHILD

**Recurse through `print_child`, never open-coded.** `print_child(recursion,
child, child_ctx)` expands to `print_document(recursion, recursion, child,
child_ctx)` — `recursion` appears twice on purpose (the projection to invoke
*and* that call's own recursion argument). Open-coding the doubled argument and
getting either slot wrong silently breaks heterogeneous recursion. Pair every
`print_child` with `make_child_context(ctx, <step to the child>)` so the
child's root-relative reference path — and therefore its selection bookkeeping
— stays correct.

### PAR-BIDIRECTIONAL-PROJECTION

**Every projection is bidirectional: a printer needs its inverse.** Every
`print_document` needs matching reference maps (or an explicit, documented
decision that it is printer-only, e.g. the write-only file-export projections
`GraphicsCanvasToImageFile`/`…ToPdfFile`). Write `map_reference_forward` and
`map_reference_backward` as the single source of truth for how a path crosses
the projection — `print_document` wires the output selection with the forward
map and the default `read_intent` maps operations with the backward map, so the
pair gives you cursor navigation across the whole pipeline for free.

### PAR-MAPPERS-ARE-INVERSES

**`print_document` uses `map_reference_forward`; `read_intent` uses
`map_reference_backward`, and the two mappers are mutual inverses.** Keep the
two mappers as the one place a path's crossing is defined, and keep them
inverse. A reference to a part that the projection printed itself goes back and
forth too (PAR-CROSS-DOMAIN-LATE). If
the two directions ever disagree — with each other or with how the printer
wired the output selection — the cursor mis-maps.

### PAR-PREFER-REFERENCE-RETARGET

**Write a `read_intent` method only when re-targeting a reference is not
enough.** The default `read_intent` re-targets any reference-carrying operation
via `map_reference_backward`, so a projection that only moves the cursor or
edits a value through a structure-preserving map needs *only* the two mappers.
Add the 4-arg `read_intent(p, recursion, change::Intent, iomap)` method
(returning an `Intent`) only to do more — retype an operation, recurse then
lift, probe a child, or route by selection. Do not write the obsolete 3-arg
shim in new code.

A reader that only maps the path of an operation takes `ReplacePathOperation`
and answers `make_path_operation(operation, path)`. So one method maps every kind
of path: the selection, the part under the pointer, and a kind that comes later.
A reader that must treat one kind in a different way adds a method for that kind.
A case that belongs to a press, such as the whole selection of an Alt+press,
names `ReplaceSelectionOperation`, because a move of the pointer must not do it.

### PAR-NO-NEW-SYNTHETIC-EVENT

**Do not add a new `SyntheticEvent` type, and do not add a `read_intent` method
for a payload that carries an operation, a request or a question.** The reader
chain reads what a person does: an event that a device reports, and a gesture
that a recognition or a tracker makes of such events, such as a click, a dwell,
a chord or a part of a drag. It is not a channel to carry an operation, a request
or a question through the projection hierarchy. So do not wrap an operation in an event that a reader answers with
the same operation, only to have the wrappers reroot it on its way out. That is
a new mechanism that goes through every projection, and it breaks the recursion
contract (PAR-RECURSION-CONTRACT) in spirit even when no fifth function is
declared. A synthetic event or a reader payload that exists now is not a
precedent for a new one.

A new gesture type is what a person does too, but every reader can meet it, so
add one only when the owner agrees, as for `DragMove`, `DragEnd` and
`DragCancel`. When a change seems to need a new event type, a new gesture type or
a new payload for the reader, stop and ask the owner. Do not add it first and
report it after.

### PAR-REPEATED-MOVE-WRITES-NOTHING

**A move to the point of the last move writes no cell.** After a frame that
changed a window, the backend sends a `MouseMove` at the point where the pointer
is, with the buttons that are held, so that the readers find the part under the
pointer in the new frame. A cell write invalidates every cell that reads it,
also when the value is equal, and the backend counts a frame with a stale cell
as changed. So a reader that writes again on a move to the same point makes a
changed frame, which sends one more move: a loop at the frame rate while the
pointer rests. A reader that computes from an anchor or from the point, such as
a drag, compares the new value with the value that the document holds, and
writes nothing when they are equal. The check goes where the cell is written: a
reader whose answer a projection above it can replace compares in the
evaluation of its operation, not in the reader.

### PAR-LIGHT-KEEPS-LAYOUT

**A light changes no size and no place.** A part that lights under the pointer
draws a layer, a colour or a frame over what it draws, and it changes the size
and the place of no part. After a frame that changed a window, the backend sends
a move at the still pointer (PAR-REPEATED-MOVE-WRITES-NOTHING). A light that
moved another part under the pointer would light that part next, which would
move the first part back, frame after frame. So a widget computes its light
where it builds its surface, not in its measure, and a syntax compound lights its
delimiters by their colour only.
### PAR-GEOMETRY-FREE-IN-DOCUMENT

**Geometry-free gesture handling belongs to the document, not the projection.**
A gesture that reads only the document's structure and `selection` (insert a
character, backspace, move the caret, step a structural selection) lives behind
`read_gesture(document, gesture)` in the document's own reference vocabulary; a
projection reader *delegates* to it and keeps only its geometry-dependent arms
(hit-testing, visual up/down). This is what lets a backend that renders a
domain directly (the console pipeline) reuse the domain's editing for free.

### PAR-DELEGATE-AND-LIFT

**A structural projection's reader delegates a raw gesture to the selected
child and lifts the result.** For a raw authoring gesture, find the selected
child from the node's `selection` and `child_iomaps`, delegate to that child's
`read_intent`, and lift the returned operation with `reroot_operation`
(prepending the input step that reaches the child); handle the gesture itself
only when the child declines. The template engine's `TemplateIoMap` reader already
does this — do not special-case nested editing.

### PAR-SHARED-CHILDREN-IOMAP

**A compound (node-shaped) projection stores its child IoMaps in one shared
reactive cell and returns a `ChildrenIoMap`.** Store the per-child IoMaps in a
single `child_iomaps::Cell` (not inline across two separate cells, which would
instantiate different output objects and break the identity invariant), project
the selection reactively (`Cell(@computation(map_reference_forward(p, iomap,
node.selection)))` with the deferred-iomap trick), and use `ChildrenIoMap` so
the reader and both mappers can locate the correct child IoMap when translating
backward.

### PAR-STABLE-IOMAP-IDENTITY

**A projection's IoMap keeps its identity; its varying parts are computed cells,
and its children reconcile by identity and index.** `print_document` returns one
IoMap per projection instance and never rebuilds or replaces it in response to a
change.
Every part that can vary — the output document, its `selection`, and every child
IoMap — is a *computed cell* deriving from the projection's input and parameter
cells, not a value captured eagerly at print time; and a collection of children
goes through the shared reconciler, keyed by the identity and the index of each
child, so the IoMap of a child that keeps its object and its index is reused. A
delete or a front insert moves the later children to other indices, so their
IoMaps are made again. A change
therefore propagates through the cells the projection already wired — never by
allocating a new IoMap, and never by nulling `editor.iomap`. This is the
generalization, from "a compound projection should" to "every projection must,"
of three rules it subsumes: PAR-REACTIVE-OUTPUT-SELECTION (wire the output
selection as a cell), PAR-SHARED-CHILDREN-IOMAP (child IoMaps in one shared
reactive cell), and PAR-NO-WRITE-IN-THUNK (reuse a persistent output object whose
fields are `set_cell_computation!` cells, rather than rebuilding it). The failure it
forbids is the eager capture: `output = f(input)` stored in a plain field has no
reactive edge, so a later change to what `f` read — a parameter the projection
navigates by, an upstream object it re-exposes — leaves a stale render and a
mis-mapped cursor with **no error** at all. Correspondingly, an
`evaluate_operation` that changes what a projection shows writes the cell the
projection derived from (PAR-MUTATE-OR-NULL-IOMAP), reserving
`invalidate_projection!` for genuine whole-root rebinds. The template engine
(`ProjectionTemplate`) is the reference implementation; the shared reconciler it
and every projection use is `make_reconciled_child_iomaps_cell` (in the iomap layer).

### PAR-CROSS-DOMAIN-LATE

**Cross domains as late as possible in the mappers.** When an output reference
points at a part that the projection introduced (a delimiter, a bracket, a
separator, an indentation), the part has no input pre-image. Keep input-domain
steps for as long as the path still has a pre-image. Then wrap only the
output-only tail, with `make_introduced_reference(projection, input, tail)`.

**An introduced part maps forward and backward.** The tail is a path in the
output of this projection: the path that the backward map got, such as
`.open{0}` for the bracket of a syntax node. It is never an offset in the output
of a later stage, because only that stage can read it. The forward map takes off
the step of its own projection and answers the tail
(`proj(^(p), inner) => inner`), and the next stage maps the tail forward as any
path of its input. A flat offset is correct only where it is a position in the
output of this projection, for a group of parts that has no path of its own. The
atomic wiring of the rule projections is the model (`_atomic_backward`,
`_atomic_forward`).

This holds for every kind of path. The pointer on a bracket names the node that
printed the bracket, as a caret on it does, so that node can draw the bracket
lit.

### PAR-HIGHER-ORDER-IS-DOMAIN-FREE

**Higher-order projections touch no domain; generic projections are
input-domain-independent.** A higher-order projection's argument is always
another projection — it must never name a concrete document type. A generic
projection operates on any input *by structure, not by type*. Handle a
heterogeneous tree with the type-dispatch idiom: a
`TypeDispatchingProjection(Type => Projection, …)`, exposed behind a zero-arg
factory (`JsonToSyntax()`, …) that returns the *bare* dispatcher; a caller
wraps it once in a `RecursiveProjection` so children re-enter the whole
pipeline. List dispatcher entries specific-first (an `Any =>` / fallback last),
since they are tried in order.

### PAR-USE-PROJECTION-MACRO

**Use `@projection` for projection structs with reactive fields, defaulting the
supertype.** `@projection` supplies `<: Projection` when none is written; use a
plain `struct … <: Projection` only when the macro can't be used (a `Cell` read
explicitly). A projection with no reactive fields may be a plain struct, but
must then spell out `<: Projection` itself. A `Function` field is no longer a
reason to avoid the macro — a callable is an ordinary field value
(PAR-NO-NESTED-CELL) — so a plain-struct projection that carries one
(`TooltipDecoratorProjection`) is free to move to it.

## References and selection

### PAR-ONE-BASED-INDEXING

**All indexing is 1-based; distinguish elements from boundaries.** Elements are
`[i]` (1-based, `ElementReferenceStep`), cursor boundaries are `{k}` (0-based,
`PositionReferenceStep`); both are readings of the same `RangeReferenceStep(start,
stop)` axis and apply to any sequence, whether the items are elements or
characters. Keep this convention everywhere. Mind the two coordinate systems in
play: a `RangeReferenceStep` stores its boundaries **0-based**, while Julia
containers are **1-based** — convert explicitly (`start + 1`) at every
reference↔container crossing rather than assuming one base throughout. A parser of
an outside format whose text counts from another index takes that index as a
keyword, with the default 1, and converts at the boundary:
`parse_reference_pattern(text; first_index = 0)` reads a configuration key that
counts from 0.

### PAR-REFERENCE-DSL

**Build and match reference paths with the DSL, not by hand.** Construct paths
with `@reference` (or `Reference(steps...)` / `@reference_step` for programmatic
use), and pattern-match them with `@reference_case` in mappers and readers. Do
not cons `ConcreteReference` cells by hand. `evaluate_reference(document,
path)` is the canonical `(document, reference) → node` walk.

**A mapper is one `@reference_case`.** Where the patterns can state it, write the
body of `map_reference_forward` and of `map_reference_backward` as one
`@reference_case`, with no code before or after it. Its arms are the empty
path, the introduced reference of the projection, and one arm for each child or
field. A condition that a pattern can not state is a `when(...)` guard. Code
by hand in a mapper needs a reason, written next to it.

### PAR-EVERY-DOCUMENT-HAS-SELECTION

**Every concrete `Document` has a `selection::Cell`, and every
selection-reachable child is itself a `Document`.** Selection is stored
recursively — each node holds only the path suffix starting at its level — so
every child a selection step descends into must be a `Document` with its own
`selection`; wrap any bare collection that appears in a document tree in a
`Document` type (`CellVector`, …) rather than leaving it selection-opaque.
Terminal output (`GraphicsText`/`GraphicsRect`/`GraphicsCanvas`) is
deliberately not a selectable container — the selection mechanism does not
enter it.

### PAR-REPLACE-SELECTION

**Change selection with `replace_selection!`, not a bare `set_selection!`.**
`set_selection!` does not clear the old path first, so a branch of the old
selection can be left behind, producing multiple visible cursors. Use
`replace_selection!` (clear then set) whenever moving the cursor; reserve bare
`set_selection!` for the case where you have already cleared.

### PAR-SELECTION-WRITTEN-AT-ROOT

**Every write of the live selection starts at the root document.** The live
selection is one path from the root, and each document on that path holds its
suffix of it (PAR-EVERY-DOCUMENT-HAS-SELECTION). A write that starts below the
root changes the suffixes below its start and leaves every document above it
with an old path or none, so the chain is no longer one path.

- Do not call `replace_selection!` or `set_selection!` on a document below the
  root of a live tree, and do not evaluate a selection operation against such a
  document. Code that moves the selection makes an operation whose path starts
  at the root, and the editor evaluates it there.
- A reader reads its own `selection` only. It never searches the documents
  below it for a selection, because the rule above makes its own suffix
  correct.
- A document that nothing holds yet is its own root. The code that puts it into
  a larger tree makes sure that the new root holds the selection it had.
- A dormant selection, which a document keeps off the live path, is not the
  live selection, and this rule does not apply to it.

### PAR-EMPTY-PATH-IS-SELECTION

**The empty path is a whole-element selection in its own right, not an absence.**
`EmptyReference()` (written `@reference()`, matched by `∅`) means "the
whole element here is selected" and maps across any projection by identity;
`nothing` means "no selection." Keep the two distinct, and let whole-element
selections round-trip for free.

### PAR-FOLDED-CHECKPOINTS

**Folded node-type checkpoints are the canonical form; produce and consume
them, don't fabricate them.** Selections and mapper/printer output carry a
per-node `type` checkpoint (folded in by `set_selection!`,
`collect_references`, and the `ProjectionTemplate` helpers). Replay a
cross-edit reference through `get_valid_reference_prefix` /
`evaluate_reference` (which throw/truncate on mismatch) rather than assuming a
stored path still fits. Do not build checkpoint *steps* by hand — the
`TypeReferenceStep` token exists only as a build-time artifact that
`fold_reference_types` immediately folds away.

### PAR-REACTIVE-OUTPUT-SELECTION

**Wire the output selection reactively; focus is the selection.** In
`print_document`, set `output.selection = Cell(@computation(map_reference_forward(p,
iomap, input.selection)))` so the mapping lives in one place (a compound
projection that introduces structural nodes with no input counterpart wires
those nodes' selection cells explicitly; a leaf-to-leaf projection with
identical formats may instead *share* the same `selection::Cell`). There is no
separate "focused" flag — the focused node is the selected one, so a container
routes a coordless (keyboard) event only to the child its selection points at
and returns `nothing` when the selection is not inside it, never broadcasting
or falling back to a default child. Mouse events still hit-test by coordinate.

## Operations

### PAR-ONE-WAY-TO-EDIT

**`evaluate_operation(editor, op)` is the one way to change the document.**
Every edit is an `Operation` produced by a reader and applied by the editor; to
script the editor, do exactly what a reader does — find the target
(`search_references`/`search_documents`), build the operation, evaluate it.
Prefer this over bespoke imperative helpers.

### PAR-READER-IS-PURE

**A reader never mutates; it returns an operation.** `read_intent` inspects the
input and the IoMap and *returns* — it must not write a document field, call a
domain mutator, or otherwise change state on the way past. Swallowing an input by
returning `nothing` is legal; swallowing it *after* performing the edit by hand is
not, however local the edit looks. If a reader needs an effect, it names that
effect as an `Operation` and lets `evaluate_operation` apply it
(PAR-ONE-WAY-TO-EDIT).

This is not bookkeeping. A reader that mutates is invisible to every mechanism
built on the operation stream — undo, playback, scripting, logging, an agent
driving the editor — because the edit never becomes an operation. It also runs at
a moment the editor has not sanctioned, so an operation-level guard (enablement,
a read-only mode, a transaction) cannot see it, and the same gesture behaves
differently depending on whether the projection that read it happened to take the
shortcut. Two projections over the same domain then disagree about what an input
*means*, which is precisely what the printer/reader pair exists to prevent.

The temptation is a reader that already has the target and the new value,
where building an operation feels like ceremony. Build it anyway;
`ReplaceReferencedValueOperation` covers the common case (PAR-PREFER-REPLACE-VALUE)
and `InvokeActionOperation` carries a callback for an effect that is not a field
write.

### PAR-REACTIVE-OUTPUT-STRUCTURE

**A projection's output structure is reactive, not re-printed.** When what the
output *contains* depends on domain state — which children a layout holds, which
of them are disclosed — that dependency is a derived cell over persistent widget
objects, wired with `set_cell_computation!`. Do not rebuild the output by asking the
editor to drop its IoMap.

`invalidate_projection!` exists for a change the reactive pipeline genuinely
cannot carry — a whole-root swap, where the object the projection was built
against is gone. Reaching for it because a *child list* changed is a different
thing: it throws away and rebuilds every widget in the tree, so transient view
state (scroll positions, in-progress text, hover) dies, expensive sub-projections
re-run wholesale, and identity is lost for every consumer that was holding a
widget — which is the guarantee `sync_document!` and the IoMap reconciler are
built on. It also hides the cost: a re-print is O(tree) on an interaction the
reactive graph would have served with a handful of cell writes.

The failure it masks is silent. A `Vector` passed to a layout constructor is
frozen into constant `Cell`s, so a printer that builds `children` conditionally
produces output that is correct on the first frame and never changes again — it
does not error, it just stops growing. If output structure varies with domain
state, bind the container's `elements` to a computation and let the graph do it.

### PAR-PREFER-REPLACE-VALUE

**Prefer `ReplaceReferencedValueOperation` (or its builders) before writing a
new operation type.** Most edits just write a value into one slot, so they are
the same operation differing only in object/slot/value; reach for
`ReplaceReferencedValueOperation`, `make_replace_document_operation`, `make_insert_elements_operation`,
`make_delete_elements_operation`, or a `CompoundOperation` of them. Add a new `Operation`
struct only for genuinely different behaviour (control flow, I/O, async,
multi-field/structural change that is not a single splice), and declare it in
the module that owns the affected document (or `OperationModule` for
cross-domain ones).

### PAR-REGISTER-NEW-OPERATION

**A new reference-carrying operation registers once, with the pair
`operation_reference` / `retarget_operation`.** The catch-all `reroot_operation`
reroots the reference that the pair reports, and the default `read_intent` maps
it back through a projection. An operation with no pair reports no reference, so
it is never rerooted and the default reader drops it, with no error. An operation
that carries its own root (`document !== nothing`) reports no reference, needs no
rerooting, and should be preferred when targeting a carried object. A
`ReplacePathOperation` registers through `get_operation_path` and
`make_path_operation`, the two functions of its family.

An operation that **holds another operation** registers itself differently, and
once: it subtypes `WrappingOperation` and answers `get_wrapped_operation` and
`rewrap_operation`. Every seam then reaches what it holds through those two,
with no branch of its own — the same rule a `CompoundOperation` follows, for the
same reason, and the reason a wrapper needs no entry in either enumeration.

### PAR-MUTATE-OR-NULL-IOMAP

**Mutate the cells already wired into the projection graph — or null
`editor.iomap`.** The editor builds the iomap once and, between frames, updates
flow *only* through reactive cell writes. An `evaluate_operation` that swaps a
whole value/subtree out from under the projection — rebinding the structure the
iomap was built against, e.g. the whole-root swap a
`ReplaceReferencedValueOperation` with an empty reference performs — must set
`editor.iomap = nothing` to force a fresh `print_document`, otherwise the
display renders stale. Conversely, an operation that expresses its change as a
write into a cell a *computed* selection re-derives (e.g. switching a
versioning criterion) must **not** drop the iomap — the reactive graph
propagates it. The test is whether you rebound structure or wrote a wired cell,
not what the change looks like to the user. Implement an operation's evaluation
through existing primitives (`replace_selection!`, reactive cell writes,
`QuitEditorException`), not by reaching into private state; the fall-through
`evaluate_operation(editor, ::Any) = nothing` lets a reader return anything
harmlessly.

### PAR-INVERTIBLE-OPERATIONS

**Design every operation to be invertible; keep its inverse well-defined.** An
`Operation` is the unit of change (PAR-ONE-WAY-TO-EDIT), and reversibility rests
on each applied operation having a clear inverse — the change that restores the
prior state. General operation-log undo/redo is not yet built (it is the
in-progress roadmap item *Undo / redo*, which "depends on the editing
operations having well-defined inverses"), and structural-operation
collaboration (OT/CRDT) rests on the same property; so a new `Operation` type
carries a *design* obligation even before the log exists. Its change must have
a clear inverse (a value replacement inverts to writing back the prior value; a
splice inverts to the complementary splice), or the operation must be
explicitly one an undo log skips (control-flow / IO, e.g. quitting the editor).
This is a silent-breakage contract: an operation added per
PAR-PREFER-REPLACE-VALUE/PAR-REGISTER-NEW-OPERATION passes every
reference-mapping check while quietly having no inverse, and the omission
surfaces only once undo reaches it. Prefer `ReplaceReferencedValueOperation`
and its splice builders (PAR-PREFER-REPLACE-VALUE), whose inverses are already
well-defined, over a bespoke operation whose reversal you would have to design
from scratch. (Product requirements PR-UNDO-REDO and PR-REVISITABLE-HISTORY.)

## Editor, devices, and backends

### PAR-MANY-WINDOWS

**A window is a window on every backend, and a tooltip is drawn in one of its
own.** The editor shows a `ScreenDocument` holding a list of `WindowDocument`s.
Every backend must open all of them. A backend that can show only one, or that
draws a second one inside the first, does not implement the seam — it imitates
it, and the imitation is visible the moment a tooltip must leave the window it
belongs to.

**This holds whatever the platform makes convenient.** A browser opens a window
only inside a transient user activation, and a Wayland client does not place its
own surface on the screen. Neither is a reason to draw a second window inside the
first. A backend that meets such a limit solves it in the backend — by reserving
a window while it has an activation, by asking for the permission it needs, or by
saying plainly that it cannot — and it never answers by folding two windows into
one, because everything above the backend is written against the list and would
then be written against a lie.

A tooltip is the case that proves it. It says something about what is under the
pointer, and near an edge that is outside the window, so a tooltip drawn inside
the window is clipped exactly where it is most needed.

**And what a window is drawn in is a document too.** A window's chrome — its menu
bar, its toolbar, its status bar — is a `WidgetShell` holding the window's own
document, not something a printer conjures on the way to the screen. A projectional
editor presents structured data through projections, so anything a projection
invents for itself can be neither selected, referenced, walked, copied nor reached
by a verb. Chrome that only the printer produces is outside the editor.

### PAR-BACKEND-SEAM

**Keep backends behind the `Backend`/`Device` seam; the same editor runs
unchanged across them.** A backend provides `initialize_backend!`,
`quit_backend!`, and the per-frame device I/O
`take_from_devices!`/`write_to_devices!` — all declared in `BackendInterface.jl`
and dispatched on the concrete backend; the device layer supplies only the
`Device`/`Keyboard`/`Mouse`/`Display` device types those two take as a list.
Swapping `SdlBackend()` for
`WebBackend()` or `ConsoleBackend()` must change nothing in the editor loop,
pipeline, or domains. Convert platform events to the backend-agnostic device
vocabulary (`KeyPress`, `KeyDown`, `Mouse*`, `WindowQuit`) in the backend, so
projection reader code never sees a raw platform event; a projection that needs
to measure text takes an injected `measure::TextMeasure` rather than the
backend itself. A single source of truth governs any cross-backend mapping. For
example, `convert_web_key_to_symbol` gives the key names of `sdl_keysym_to_symbol`.

### PAR-OPT-IN-DEPENDENCY

**Add a backend/engine as an opt-in package behind a factory seam, not by
coupling core code to the dependency.** Each external dependency or transport
gets exactly one opt-in package that registers a method on a seam owned below —
either a symbol-keyed `Val` factory (`make_agent_server(:mcp)`,
`make_database_adapter(:odbc)`, the `record_video` seam) or a
subtype-dispatched generic (`solve_constraint_layout(::TulipConstraintSolver)`,
`layout_graph(::AdaptagramsLayout)`, `make_llm(:ollama)`). Generic
code requests capability by symbol or supertype; the opt-in package binds to
the *narrowest* package that has what it renders and errors helpfully when not
loaded. Requesting through a seam creates no dependency, which is what keeps
`kernel`…`domain` runnable with none of the native/network dependencies
installed. Output-only file export (`write_image`, `write_pdf`) lives beside
the backend layer but does **not** subtype `Backend` — it has no devices or
events.

### PAR-PROFILE-WITH-COUNTERS

**Profile edits with the per-frame performance counters.** Set
`PROJECTURED_PERFORMANCE_COUNTERS=true` and recompile to compile the counters in.
The read-eval-print loop then binds a fresh counter store for each frame, and
`_log_performance_counters!` logs `reads / computes / invalidations / writes` for each frame that
applied an operation. Use them to find unintentional recomputation (a single
keypress causing thousands of `computes` means something reads more cells than
necessary).

### PAR-PER-EDITOR-STATE

**No process-global state in the editor or the machinery it drives; one process
must run many editors at once.** Every piece of mutable runtime state an editor
touches — its `document`, `selection`, `iomap`, in-flight `operation` and
animation clock — must live on the `Editor` instance (or on values reachable only
from it), never in a module-level `const` cell, `Ref`, `Dict`, or counter. This is
a correctness
requirement, not a style preference: it is what lets one Julia process host
several independent editors side by side (product requirement
PR-MANY-EDITORS-ONE-PROCESS). Process-global holds tie the editors together and
break that independence — two editors sharing one animation-time cell write
conflicting elapsed values into it every frame, so both animations judder and
each editor's tick cross-invalidates the other's animated cells; a shared
performance-counter dict has each editor overwrite the other's numbers.
PAR-NO-PROJECTION-GLOBALS already forbids process-global mutable state inside
projections and the machinery they call; this extends the same ban up to the
editor loop, the devices, and the backends it drives — a backend or device that
must hold per-connection state holds it on its own instance (one per editor),
never in a global registry. State that belongs to a single *evaluation* rather
than to an editor is instead task-local (its natural scope). The reactive
engine keeps its computing stack, which tracks dependencies, in task-local
storage, so concurrent evaluations never cross-register dependencies. The
performance counters live in the scope of one frame of one editor:
`run_editor!` binds a fresh counter store for each frame with
`run_with_performance_counters`, a task-local binding. The animation clock is a
per-editor `Clock` (a `@cell_struct`, not a document — `clock/ClockModule.jl`);
`run_editor!` advances `editor.clock`, and every animated cell subscribes to the
clock the printer context carries, so two editors in one process never
cross-invalidate each other's animation graph. No clock is shared by the whole
process: an owner without a frame loop starts a heartbeat on its own clock with
`start_wall_clock!`, on the task that reads that clock.

**The editor of an evaluation is state of one evaluation.** While the code of
the evaluator, of the assistant or of the `execute_julia_code` tool runs,
`_run_expression` binds its editor in a `ScopedValue`, and
`get_evaluation_editor()` reads it. The tasks that the code starts get the same
editor, and nothing else does. Only a verb reads it, and only as the default of
its `editor` keyword, `focus_pane!(reference; editor = get_evaluation_editor())`,
so the code of a person or a model names no editor. Every other code passes the
editor it has: an operation gets it from `evaluate_operation(editor, operation)`,
and a projection, the editor loop and a call from a package never read the
scope. The argument guard, `test/suite/arguments.jl`, fails on a call of
`get_evaluation_editor` anywhere else.

**Accepted carve-out — state that is identical for every editor.** Process-global
state is permitted precisely when its value is the same for every editor in the
process: no editor can observe another's writes through it, so there is no
cross-editor divergence to create. This is the escape valve the rule's rationale
leaves open — what PAR-PER-EDITOR-STATE forbids is one editor's state *conflicting
with or leaking into* another's, which a genuine singleton cannot do. One kind
qualifies:

- **Read-only data derived from process-invariant sources.** A cache built once
  from inputs that do not change while the process runs and are the same for
  every editor — for example the documentation and API indexes behind
  `search_guides` / `search_api` (`tool/Documentation.jl`), built by
  reflection over the loaded code and the guide files on disk. Lazily populated,
  read-only thereafter, and identical for all editors, so it introduces no
  cross-editor write conflict; giving each editor its own copy
  would only duplicate identical work. The stores of meaning vectors behind a
  search by description (`tool/MeaningSearch.jl`) are the same kind: a vector is
  derived from such a text and from the model its store is named for, so every
  editor that names that model reads the same vectors.

A shared read of one such value does not reintroduce the cross-editor *write*
conflict PAR-PER-EDITOR-STATE targets.

### PAR-REPORT-NEVER-THROWS

**A fault report never throws, and a barrier never swallows a fault in
silence.** `report_fault!` may not raise an ordinary exception: it runs when
everything else has already failed, and an exception from it turns one broken
frame into a dead editor. It reports at the first tier that works — a mark in the
document, the message log, the console, a sound, nothing — and each tier falls to
the next. A
store that throws and a backend that throws, both at once, still answer a tier,
and a log target that throws does not stop the drain. Tests assert both.

The second half is what keeps the first half honest. **A barrier that catches
must record**, so no fault is lost, and the policy that governs the barriers
must default to catching **nothing** wherever a test can reach it. Every form that
makes an editor — `Editor`, `make_editor`, `build_editor` and
`run_editor!(document, projection)` — starts it with `make_strict_fault_policy()`.
A program that a person starts passes `FaultPolicy()` on purpose, and
`run_editor!` keeps the policy of its editor. A barrier that is on under test
turns a real bug into a passing run, which is the one way error tolerance can
make the program worse than it was.

An exception that means the program is to stop or can not go on is never caught:
`is_passthrough_exception` names them one at a time — `QuitEditorException`,
`InterruptException`, `StackOverflowError`, `OutOfMemoryError` — and a layer that
owns a control-flow exception adds its own method. **Every catch-all arm asks it
first and rethrows when it answers true**, in every layer: a barrier, the report
path, a walk, a search, a fallback for a text. "A report never throws" is about an
ordinary exception; an exception that means stop is a request to stop the editor,
and a report lets it go on. A catch that hands the exception on to its caller,
as the build of an editor does through a channel, keeps it.

**One accepted exception: the model code of the code tool.** The code tool acts as
the Julia REPL. An exception that model code raises is the answer of the call, an
interrupt and a stack overflow too, so that an endless loop or a deep recursion
that a model wrote ends that call and not the editor. A `QuitEditorException` and
an `OutOfMemoryError` still pass.

## Package, layer, slice, and module structure

### PAR-PACKAGE-CHAIN

**Respect the package chain and the four-level division.** Dependencies flow
one way, `kernel → platform → domain → umbrella` (plus opt-in packages);
create a **package** only for a new external dependency or a distinct consumer
set, a **layer** for a distinct dependency height (a layer imports only lower
layers), a **slice** for a feature within one layer (slice→slice edges stay
acyclic), and a **module** for a named import surface (module-per-domain,
module-per-projection). Files are a readability boundary only and must never
imply an API boundary the module does not enforce. See
[architecture-rules.md](architecture-rules.md) for the full decision procedure.

### PAR-LOWEST-PACKAGE

**Every piece of code lives in the lowest package of its DAG whose API it
hard-references.** Source, test, example, and harness alike sink to their
lowest home. A seam call (`record_video(…)`, `default_backend()`) is not a
reference; only a `using`/`import` or naming a package's types/functions
anchors code. For a test or example, the *fixture* determines the home (a
Pdf-backend test driven by a JSON pipeline is a domain test), not the machinery
it happens to exercise.

### PAR-MODULE-BOUNDARY-IS-API

**Imports name only exported symbols — the module boundary *is* the API
boundary.** A non-exported name is a module-internal detail; no code outside
the module that defines it may `import`/`using` that name — not from a higher
layer, and not from a sibling module in the *same* layer. If another module
needs a symbol, that symbol is part of the defining module's public contract
and must be **exported**; reaching into an internal is the smell, never the
fix. The only way to share a helper without exporting it is to make the sharers
**fragments of one module** (same namespace by construction, so nothing is
imported); otherwise sink the machinery to a module at or below both users and
export it. Precedents: the `@gesture_case`/`@gestures` parser (same-module
fragments); the transparent-Cell struct codegen — `@cell_struct` +
`build_cell_struct_exprs`/`build_cell_struct_keyword_parameters`/`build_cell_struct_keyword_constructor` exported from
`CellStructModule` (struct layer), built on by `@document`/`@iomap`/`@projection`.
Enforcement is
staged like the layer guard itself: `check_private_imports` already forbids
cross-*layer* internal imports; the same-layer case is enforced per package
once its same-layer internal imports are cleaned up. An import header is only
half the boundary, though — `XxxModule._private` reaches a non-exported name
just as far, and bypasses the export list entirely.
`qualified_reference_errors` closes that half (PAR-QUALIFIED-EXTENSION), with no
same-layer exemption. Known remaining instance: `PlaybackModule` reaches into
`EditorModule`'s non-exported `run_read_stage!`/`run_evaluate_stage!`/`run_print_stage!`/`_log_performance_counters!` — fix by
making Playback a fragment of the editor module, or by exporting the loop
steps.

### PAR-FRAMEWORKS-SINK

**Frameworks sink below their users via the seam pattern; only per-domain
methods stay above.** A lower layer declares open generics (or a small
registry); higher layers add methods *in files they already have* — multiple
dispatch is the registration, and a couple of methods never earns a new file. A
lower layer may *mention* a higher concept only as an opaque payload it never
interprets; if it must *call* it, that is a seam, not a payload.

### PAR-PROJECTION-PLACEMENT

**Honor the projection placement invariant.** `home(projection) ≥
max(package(input), package(output), package(every other import))`; the
canonical home is the more-specific side (`JsonToSyntax` → the json slice,
`ObjectToSyntax` → visual). Interfaces live with their concept as the layer's
first file(s), not in a separate `api/` layer. A file nothing imports gets
wired in or deleted before it gets a home — no orphan shapes the structure.

### PAR-INTERFACE-DECLARES-ONLY

**An interface file declares; it never implements.** A layer's interface file —
the contract file its module includes first (`document/DocumentInterface.jl`,
`reference/ReferenceInterface.jl`, `backend/BackendInterface.jl`, …) — carries *only*
declarations: the module docstring, the abstract types and type aliases that
form the layer's vocabulary, and its open generics as bodiless `function f
end`. **No method bodies.** Not a delegation, not an accessor, and not a
"trivial" default or error fallback either: a default is behaviour, and
behaviour is implementation. It belongs in the sibling file that implements the
contract — the default `get_reference_step_kind` sits with the step types in
`ReferenceStep.jl`, next to their concrete methods. Nor may an interface file
hold a concrete struct, mutable or global state, or an algorithm. A contract default with no natural sibling home is the signal that
the layer needs an implementation fragment, and not a reason to park behaviour
in the interface. Every name an interface file declares is **exported**
(PAR-MODULE-BOUNDARY-IS-API): it has no private half, and its export list *is*
the layer's API surface. The purpose is documentary — one file gives a reader
the entire contract of a layer and nothing else — and it is what
PAR-NO-CONSUMER-DOCS's seam carve-out already assumes when it calls an open
declaration "content-free by construction". Machine-checked: the layering guard
parses each file named in its package's `interface_files` map and reports every
expression that implements rather than declares, plus any declared name its
module fails to export (purity is decidable from the AST — a bodiless `function
f end` is a one-argument `Expr(:function)`, a method a two-argument one). The
kernel's nine contract files are enforced today; a package opts its own in as
they come clean. Note a Julia constraint: a bodiless declaration may not be
qualified (`function Base.peek end` is a syntax error), so a contract that
includes a `Base` generic states it in the docstring and lets the implementors
add the methods.

### PAR-QUALIFIED-EXTENSION

**Import the names a file extends. Name every other module with a bare `using
..Xxx`.** Two forms, and each says a different thing:

- `using ..XxxModule` — bare, no symbol list. This code *calls* what
  `XxxModule` exports and adds no method to any of it. The bare form also binds
  the module's name, which a qualified extension needs.
- `import ..XxxModule: f, g` — exactly the names this code *extends*, and no
  others. The list is short by construction, so a reader sees at the header
  which contracts this code implements.

**Above the platform, two aggregates stand for their groups.** A domain, a
backend or an adapter writes `using ..KernelModule` and `using ..PlatformModule`
in place of a bare `using` for each module of the kernel and of the platform:
each aggregate exports every module of its group and every name those modules
export. An extension still imports its names from the module that owns them,
`import ..SyntaxModule: print_document`, so the header still shows which
contracts a file implements. The kernel and the platform themselves never use
the aggregates: each of their modules names the modules it uses, because their
layering guard and the table of the edges between the slices read those lines.

A definition may qualify instead of import: `XxxModule.f(…) = …`. Both reach the
owner's generic. Qualification is the better form where the extension is rare or
the file is long, and the only form a macro can emit, by interpolating the
module object (`:(function $(ReferenceModule).get_reference_step_kind(…) end)`),
which needs nothing at the call site.

**The compiler does not check this, so a guard must.** Measured on Julia 1.13:
after a bare `using ..XxxModule`, a plain `f(…) = …` for a name `XxxModule`
exports raises no error and no warning. It defines a *new* `f` in the calling
module. `XxxModule.f` keeps its own methods, and every call that goes through
`XxxModule` reaches the fallback instead of the method just written. The code
compiles, loads, and is wrong.

The shape to watch for is a one-line trait method:
`insertable(::Type{MyType}) = false` reads as an extension of
`DomainModule.insertable` and is not one unless the name is imported or the
definition is qualified.

Three guards hold the rule up:

- `shadowed_extension_violations` (`test/suite/naming.jl`) reports a definition
  of a name that a module this one names exports, written neither imported nor
  qualified. This is the one that catches the silent case, and it runs over the
  whole tree on every suite.
- `relative_import_errors` (the layering guard) keeps an import list meaning
  what it says: no bare `import ..Xxx`, no `using ..Xxx: a, b`, and no imported
  name that nothing extends. It checks **every** file of a package. What is not
  migrated is named in that package's `unmigrated_files`, and a file named there
  and since migrated is itself reported, so the set cannot go stale.
- `qualified_reference_errors` asserts every `XxxModule.sym` names an exported
  symbol, because qualification bypasses the export list entirely
  (`XxxModule._private` reaches a non-exported name with no complaint) and
  PAR-MODULE-BOUNDARY-IS-API would otherwise hold for import headers and be
  unenforced exactly where this rule sends the traffic.

**Qualification is for cross-module extension only.** A file that is a
*fragment of the defining module* defines bare — same namespace by
construction, so nothing is imported and nothing is qualified. This is
PAR-MODULE-BOUNDARY-IS-API's "fragments of one module" carve-out, and after the
slice collapse it covers most files: a slice's header sits in its module file
and its definitions sit in the fragments.

**A module is qualified by its real name.** A bare `using` of an alias binds
the module the alias points at, under *that* module's name — `using
..BackendApiModule` (a `const` alias for `ProjecturedKernel.BackendModule`)
binds `BackendModule`, not `BackendApiModule`. So every backend in the repo,
whichever alias path its package uses, registers under the same canonical
`BackendModule.initialize_backend!`.

A bare `using` also means every export of every used module lands in scope, so
the rule needs one precondition: **no two modules may export the same name with
different bindings.** A *re-export* — the same binding object reached through
several module names — is not a collision and Julia resolves it silently;
distinct bindings raise `UndefVarError` on use. The precondition is
cross-package, so `test_export_collisions` (umbrella) checks it dynamically.
Precedent: `NothingToSyntaxLeaf`, the one such clash that ever existed, meant
the `nothing` leaf in visual and the `*Nothing` insertion placeholder in
domain; the more specific concept took the qualifier
(`InsertionNothingToSyntaxLeaf`).

Every file of the tree follows this rule. A package may name what it has not
migrated in `unmigrated_files`, and none does.

### PAR-PARALLEL-TRIADS

**Keep the main/test/example triads parallel and minimal-environment
runnable.** Each main package has sibling `test`/`example` packages forming
DAGs of identical shape; a test package depends only on the main package it
tests plus test/example packages at or below its position (never a main package
above it), and the umbrella keeps only genuinely cross-cutting or
opt-in-coupled suites. Registering a new domain/projection means editing the
package's entry module (`include` + `using` + `export`). This is what lets
`test_kernel()`…`test_domain()` run without SDL/ODBC/etc. installed — do not
break it.

## Testing and verification

### PAR-SMALLEST-TEST

**Run the smallest test that covers the change; never default to
`test_all()`.** Pick the narrowest scope — a single example
(`test_printer(json_example)`, `test_example(…)`), a single domain/stage
(`test_json()`, `test_syntax_to_text()`), one package suite (`test_kernel()`
…), or the cell primitive (`test_cell()`). `test_all()` is slow and floods the
context; reach for broad sweeps only after the targeted test already passes.

### PAR-MARK-BROKEN-TESTS

**Every currently-failing assertion is marked `@test_broken` with a `#
@broken:` reason.** An unmarked `Fail` or `Error` in a summary is unambiguously
a regression from your change — `Fail + Error` must be zero after a passing
run. A bare `@test_broken` with no reason comment is not acceptable; when a
marker reports `Error: Unexpected Pass`, the bug is fixed — promote it back to
`@test` and delete the comment. Reserve `@test_skip` for code that would crash
the runner.

### PAR-NEW-CODE-SHIPS-TESTS

**New code ships with tests, registered in the lowest test package that can
express them.** A new projection needs a printer test (output structure), a
reader test (selection translation for one event), and an example so
`run_example("my_domain")` works. Add the test file to the test package of the
lowest main-package position that can express it (usually
`package/<domain>/test`), following the existing `function test_x() … @testset …
end` pattern.

### PAR-NO-INTROSPECTION-METHOD

**Preserve the recursion contract's external validation — add no per-projection
introspection method.** The contract is checked externally by a harness that
drives the four functions over composed examples (reachability, round-trip,
printer lockstep, and the discriminating composition-substitution probe) and
reuses the existing walkers; it must not introduce a new per-projection generic
function of its own. New document types are covered by the reflexive `_walk!`
automatically as long as their state lives in struct fields — state kept in a
side table needs a dedicated test.

### PAR-DRIVE-THE-BEHAVIOUR

**Verify a change by driving the behaviour, not only by reading code.** Use the
walker helpers (`walk_printer_output`, `walk_repl_loop`,
`explore_position_selections`) and the REPL reproducers (`run_example`,
`print_example`; `reset=true` for a fresh instance) to exercise the affected
pipeline headlessly. The console backend and offscreen renderers
(`write_image`, `write_pdf`) make this possible without a display, and
development must not depend on a graphical display.

## Documentation, vocabulary, and process

### PAR-DIVISION-VOCABULARY

**Use the division vocabulary exactly — package, layer, slice, module — and no
synonyms.** Avoid "tier" and architectural "level"; say "package" or "layer";
say "per-package" (not "per-layer") for `test_kernel()`…; name a pipeline stage
by the thing (the Syntax domain, the `syntax/` slice, the `SyntaxToText`
projection), not "the syntax layer"; use "end-to-end path", not "vertical
slice", for MVP scope. See [division-terminology.md](division-terminology.md).

### PAR-NEVER-GUESS-NAMES

**Do not guess names or signatures — search for them.** Use `search_api`,
`read_function_documentation`, the `resource://modules` catalogue and the
`resource://module/…` and `resource://type/…` resources, the [orientation
index](../guide/orientation.md), or ripgrep before naming a type or function; a
hallucinated name is worse than an admitted gap. Property access already
unwraps cells — write `node.field`, not `node.field[]`.

### PAR-GREEN-LAYERING-GUARDS

**Keep the layering guards green and let them enforce the structure.** Every
main package has a static guard that parses the real `import ..Module` headers
and asserts a valid topological include order, correct layer/slice membership,
and same-or-lower-layer edges (slice acyclicity follows from the topological
order); the export-only cross-layer-import check and the interface-purity check
(PAR-INTERFACE-DECLARES-ONLY) are enabled on the kernel guard today and extend
to the platform and the domains as they come clean. Run `test_kernel_layering()`
(…`test_domain_layering()`) after any structural change; the guard runs in ~1s
without loading the package, and its error messages are prescriptive — they
name the offending file, the module, and the fix — so treat those messages as
part of the contract.

### PAR-UPDATE-THE-GUIDE

**Update the guide that documents behaviour you changed, and teach concepts
before mechanisms.** A change that affects documented behaviour updates the
relevant `documentation/` guide in the same change; the reading order in
[README.md](../README.md) (concepts → architecture → reactive cells → macros →
projection system → editor) and the per-topic guides must stay a coherent path
in. Link the relevant `plan/` document when one exists.

### PAR-HONEST-DOCS

**Keep documentation honest, and flag aspirational designs as such.** Doc and
slide claims must be grounded in the guides and source; a design that is not
yet implemented (e.g. the Annotation domain) must be clearly marked as a future
sketch, not presented as callable API. When a forthcoming feature lands, update
the corresponding guide/slide so claims stay accurate.

### PAR-FOCUSED-DIFFS

**Keep diffs focused — no unrelated reformatting.** Do not reformat lines you
are not logically changing; keep the diff to what the change requires so review
stays tractable.

### PAR-STABLE-FOUNDATIONS

**Respect the stable foundations and the roadmap ordering.** The pull-based
reactive `Cell` system, bidirectional printer/reader projections,
module-per-domain/projection, 1-based indexing, and the MCP AI bridge are
settled design decisions — build on them rather than re-litigating them.
Sequence new work to **deepen the end-to-end path first**, then **widen** (more
domains, layouts, backends), then **distribute** (network, collaboration,
external data).

### PAR-AI-SAME-GUARANTEES

**AI edits carry the same guarantees as human edits.** An AI assistant works
the document through the same operations, references, and selection machinery a
person does — targeting the *meaning* of the content (references and operations
on the model), never its position on screen, and it is likewise unable to
produce structurally invalid content. Code that exposes editing to an AI (the
agent tools, `execute_julia_code!`) routes through
`evaluate_operation`/`search_*`, not around them, so the same invariants hold
for both.

**Accepted exception — a direct write through the code tool.** The code tool
(the Julia function `execute_julia_code!`, the tool `execute_julia_code`) runs any
code with the editor bound, so a direct write to a document stays possible. The
editor discourages it: both descriptions of the tool tell the model that such a
write gets no undo, no check and no transform, and that a verb or an operation
changes the document of the editor.

### PAR-NAMING-LAW

**Follow the naming law — names must be guessable in both directions.** A name
shows you what kind of thing it is and what it does, and a concept gives you
its name, without a lookup (see
[naming-rules.md](naming-rules.md)). Module name =
filename + `Module`, and every exported name has exactly one owning module.
Name new concepts onto the pipeline ladder **Event → Gesture → Intent →
Operation → Document**, not alongside it: events are noun-first and suffixless
(`WindowClose`, `KeyDown` — they report what happened), operations are
verb-first with the `Operation` suffix (`CloseWindowOperation` — they express
an intended edit). A projection type is a gerund stem + `Projection`
(`FilteringProjection`); getter/derive/mutate is the `get_x` / `with_x` /
`set_x!` trio; factories are `make_*`, predicates `is_*` or `has_*`, mutators end in `!`.
Use full words, not ad-hoc abbreviations (`value` not `val`, `reference` not
`ref`, `operation` not `op`); the sanctioned compact forms are `Api`, `IoMap`,
the `I<Document>` prefix, `ctrl`/`alt`/`meta`, and any well-known, widely-used
abbreviation that reads unambiguously as its one expansion (`ctor` for
constructor, `expr` for expression). The bar is guessability in both directions —
`ctor` clears it (every reader expands it, with no rival meaning); a coined
shortening of a domain word (`val`, `ref`, `op`) does not. Declarative macros are
noun-named DSL keywords (`@document`, `@projection`, `@gestures`) — the one
exemption from verb-first.

### PAR-MODULE-DOCSTRING

**Every source file opens with a module docstring stating its contract.** A
triple-quoted docstring at the top of each file names the module and its role
(and any invariants it upholds) — this is a uniform, load-bearing convention
across the codebase, not optional decoration. A fragment file that shares an
aggregator's namespace says so; a file that declares a cross-file invariant
(e.g. the `read_intent` ⇄ `reroot_operation` sync) states it where both sides
can find it. Keep these docstrings accurate when you change the code they
describe — a docstring that names a function that no longer exists is a defect.

### PAR-PERSISTENCE-BY-VALUE

**Persistence crosses cell boundaries by value and never enters the reactive
graph.** Serialization (binary and natural-format) writes a `Cell`'s *value*
only — reading it via `getfield(c, :value)`, never `c[]`, so no spurious
reactive dependency is registered — and never traverses a cell's `dependents`
out into the projection-output graph. Keep this boundary intact: what is
durable is the document's data, not the reactive machinery or the projected
view built over it. Transient view/UI state (hover, drag, scroll, zoom) is
projection output and is therefore excluded from serialization by construction.

### PAR-NO-TEST-DOUBLES-IN-MAIN

**No test doubles live in `main` packages.** A fake, mock, stub, or any
canned/scripted stand-in for a real seam is test/example scaffolding: it lives
in a `test` or `example` package and is never defined in, exported from, or
named by `main` code — not even as a fallback. A `main` package defines only
the real seam (the abstract type + generic) the double implements; the double
subtypes that seam from its `test`/`example` home. Production code that finds
no real backend fails loudly rather than fabricating a fake, so a real user is
never served a faked result; offline/deterministic behaviour is opted into by
the example or test that needs it (it passes an explicit double). A double may
still be *defined* in an example package the executable bundles, but because no
`main` path constructs one, none is reachable at runtime in production. See the
"No test doubles in `main`" bullet in
[architecture-rules.md](architecture-rules.md). Precedent: `FakeLlm` /
`ScriptedLlm` moved from kernel `main` (`LlmModule`) to
`ProjecturedKernelExample`, and `Assistant` dropped its `FakeLlm`
fallback.

### PAR-NO-CONSUMER-DOCS

**A module's documentation describes its own contract, never its consumers.** A
docstring or comment must not name, enumerate, or explain the higher-layer
modules, macros, or callers that build on the code it documents — that is
forward knowledge a lower layer cannot have without inverting the dependency
direction. Describe what the code *is* and the contract it gives to *any*
caller, as a self-contained service; let each consumer's own documentation
state that it builds on this. This is the documentation-level companion to
PAR-MODULE-BOUNDARY-IS-API (imports name only exported symbols) and
PAR-FRAMEWORKS-SINK (a lower layer mentions a higher concept only as an opaque
payload): dependencies point down in prose exactly as they do in code. Citing
an architectural *rationale* is still allowed — "holds no global state, so one
process can run many editors" (PAR-PER-EDITOR-STATE) names a requirement, not a
consumer; "the seam `@document`/`@iomap`/`@projection` build on" names
consumers and is the violation. Precedent: `PerformanceModule` dropped
its "`CellModule` imports this" reference, and `CellModule` dropped the
"declarative macros `@document`/`@iomap`/`@projection` build on this"
references.

**Seam carve-out.** An open interface declaration is content-free by
construction (`function foo end`, no signature — PAR-INTERFACE-DECLARES-ONLY):
its *docstring* is what describes the contract, and a contract's meaning is the
shape of the values that flow through it. So an interface/seam file may name
the **concepts** it bridges as forward pointers — the *kinds* of value on each
side of the seam (a `gesture`, an `Operation`, a projection's output domain) —
but not the specific higher-package modules, macros, or methods that implement
it. "Maps a gesture to an `Operation` expressed against `document`'s reference
vocabulary" names concepts; "the `@gestures` catch-all in
`GestureBindingModule` supplies the default" names a consumer and is the
violation. The carve-out applies only to a *seam file* (one whose job is to
declare the open interface) and only to the *concepts* the seam bridges;
everything else in PAR-NO-CONSUMER-DOCS still holds. Prefer redistributing the
seam to the lowest layer where every concept it names is already introduced
(PAR-LOWEST-PACKAGE): once every concept sits at or below the seam, the
forward-concept references become backward, not forward, and the carve-out is
unnecessary.

### PAR-TIGHT-COMMENTS

**A comment carries only what the code cannot — keep it tight.** A comment
earns its place by holding information that is neither visible in the code nor
one hop away in a docstring: a constraint, an invariant, a rejected
alternative, the reason an expected method is *absent*, a non-obvious
consequence. Everything else is noise that rots. Specifically, do not restate
what the next line does; do not re-explain a function, macro, or generic that
is documented at its own definition (its owning module is the single place —
PAR-NO-CONSUMER-DOCS); do not summarise the code beneath a section banner (the
banner names the section, nothing more); and do not narrate the change that
produced the code ("was previously", "moved from", "now uses X") — history
belongs in the `plan/` document, never in the source. Prefer a docstring on the
definition over a comment above the call. Two comments saying the same thing in
two files is one comment too many, and when a comment and the code drift apart,
the comment is the bug. Precedent: JSON's insertion-factory block shed a
paragraph restating `make_insertion_document`'s own docstring and
`@selected`'s semantics, keeping only the one line no reader could derive
— why an empty `JsonNumber` is selected whole while an empty `JsonString` gets
a caret at position 0.

### PAR-CITE-EXCEPTIONS-ONLY

**Cite an architectural requirement in a comment or docstring only to flag an
exception, never to announce compliance.** The sanctioned places to cite an
`PAR-…` ID are reviews, commit messages, guard failures, and `plan/` documents; a
*source comment or docstring* is not one of them. There, a rule reference earns
its place only when it marks a **deviation** — an accepted non-compliance, or a
non-obvious constraint the rule forces at that spot which a reader would
otherwise question or "correct". Naming the rule a piece of code simply *follows*
is noise: compliance is the default, it is enforced elsewhere (the layering
guards, review, this document), and the citation only rots when the rule is
renamed or the code moves. A file that is the textbook case of a rule states its
role in plain terms — an interface file says "nothing here carries a body", it
does not cite PAR-INTERFACE-DECLARES-ONLY to prove it. This is the citation-level
companion to PAR-TIGHT-COMMENTS (a comment carries only what the code cannot): a
rule name the reader can look up, pinned to code that plainly obeys it, carries
nothing. A guide (or this document) that *teaches* a rule is stating it, not
announcing compliance, and is exempt. Precedent: the cell layer's
`CellInterface.jl`/`CellDefaults.jl` name their interface/implementation split in
plain words and cite no rule to justify it.