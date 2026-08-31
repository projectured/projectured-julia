# Object Versioning

> **Status (2026-08-12): DONE for the eliminated (default) view.** `VersionedObject`
> / `ObjectVersion` / `VersionProperties` and the five `VersionCriterion` subtypes
> live in `package/versioning/main/Versioning.jl`; `VersioningToAnyProjection` lives
> in `package/versioning/main/VersioningToAny.jl`. Versioning is now its own package
> (`ProjecturedVersioning`), not a module inside a shared domain package. Only the
> optional History view (step 5) is still open.

A generic, domain-neutral overlay that lets **any** document subtree carry
multiple versions of itself. Versioning is an *optional, recursive* wrapper
layer plus an *elimination projection* that collapses the wrapper away — at
which point the downstream domains are ordinary, non-versioned documents and
every existing projection pipeline works unchanged.

> **Not undo/redo.** The brainstorming note in
> [`plan/tentative/further-development.md` §3](../tentative/further-development.md)
> frames versioning as a generalization of an undo/redo operation log
> (replaying inverse operations to reach a past state). This plan is a
> different, simpler model that does **not** depend on undo/redo, an operation
> log, or inverse operations. Versions are first-class document values stored
> *in the tree*, not reconstructed by replaying history. The two approaches can
> coexist; this one is the foundation the user actually wants.

## Concept

Versioning has exactly **two levels**:

1. **The versioned object** (`VersionedObject`) — a container that holds *many*
   of the second level. It is the thing that "has versions."
2. **The object version** (`ObjectVersion`) — holds the **value object** (the
   actual domain document for this version) together with the **version
   properties** (metadata: when, who, where, …).

The former contains more of the latter; the latter contains a value plus its
properties. Nothing else.

Two essential properties:

- **Optional.** A subtree is versioned only if it is wrapped in a
  `VersionedObject`. Anything not wrapped is a plain document and behaves
  exactly as today. There is no global "everything is versioned" mode.
- **Recursive.** The value object inside an `ObjectVersion` may itself contain
  `VersionedObject`s nested anywhere within it. A versioned JSON object can
  have a versioned array element whose value is again a versioned string. Each
  `VersionedObject` is resolved independently.

A **projection eliminates the versions**: for each `VersionedObject` it selects
one `ObjectVersion` according to a **criterion** and projects that version's
value object in place of the wrapper. The output of this projection is a tree
with no versioning nodes at all — a simple non-versioned document — which then
flows into `JsonToSyntax`, `XmlToSyntax`, `SyntaxToText`, etc. unchanged.

This is structurally the **same pattern** as the clipboard
(`ClipboardSlice`/`ClipboardCollection` + `ClipboardToAnyProjection`): a wrapper
document holding a `content`/payload, and a projection that decides which child
becomes the output and re-roots edits back into the chosen child. Versioning is
"clipboard, but the payload is a list of timestamped value objects and the
toggle is a selection criterion." Read
[`package/clipboard/main/ClipboardToAny.jl`](../../source/clipboard/ClipboardToAny.jl)
and [`package/clipboard/main/Clipboard.jl`](../../source/clipboard/Clipboard.jl)
before implementing — this plan mirrors them deliberately.

## Goal

Let a user keep several versions of any element side by side, attach metadata to
each version, and view/edit the document *as if* only one version existed —
choosing which one via a criterion (latest, by author, at-or-before a
timestamp, by explicit pin) — without any domain needing to know versioning
exists.

## Design

### File: `package/versioning/main/Versioning.jl`

**✅ DONE (verified):** `VersionProperties`, `ObjectVersion`, `VersionedObject`, and
the `VersionCriterion` hierarchy are defined there. (An earlier audit of this plan
pointed at `package/projectured/example/document/Versioning.jl` — that file only
holds the example builder `make_versioning_document_example`, not the module.)

A new domain module, modeled on `ClipboardModule`. All fields are `Cell`-backed
via `@document` (see [macros.md](../../documentation/package/kernel/macros.md)).

```julia
module VersioningModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

abstract type VersioningDocument <: Document end

# ── VersionProperties ──────────────────────────────────────────────────────
# Version metadata. A document so it is itself inspectable/editable/projectable
# (and could later be versioned too). All fields optional — a version can be
# anonymous.
@document struct VersionProperties <: VersioningDocument
    timestamp::Any        # e.g. DateTime, or nothing
    author::Any           # who created it (string / user object / nothing)
    origin::Any           # where it came from (host, file, session, nothing)
    label::Any            # optional human name / tag for the version
    selection::Reference
end

# ── ObjectVersion ──────────────────────────────────────────────────────────
# The second level: one value object + its properties.
@document struct ObjectVersion <: VersioningDocument
    value::Document            # the actual domain document for this version
    properties::VersionProperties
    selection::Reference
end

# ── VersionedObject ─────────────────────────────────────────────────────────
# The first level: many ObjectVersions + the active selection criterion.
@document struct VersionedObject <: VersioningDocument
    versions::CellVector       # Vector{ObjectVersion}, newest-first by convention
    criterion::Any             # a VersionCriterion (see below); selects the active version
    selection::Reference
end

end # module
```

Convenience constructors (outer — the `@document` inner constructor is
generated): `VersionedObject(value; ...)` wrapping a single initial version,
`ObjectVersion(value; timestamp=now(), author=…, …)`, etc.

### Selection criteria

The criterion is what makes the elimination deterministic. Keep it an abstract
type with concrete subtypes (the `DocumentLocator<Mode>` pattern from
[`plan/pending/document-locator.md`](document-locator.md)), so new selection
modes are added without touching the projection:

```julia
abstract type VersionCriterion end

struct VersionCriterionLatest    <: VersionCriterion end                    # newest version
struct VersionCriterionIndex     <: VersionCriterion; index::Int end        # explicit pin (1-based)
struct VersionCriterionByAuthor  <: VersionCriterion; author::Any end       # newest by a given author
struct VersionCriterionAsOf      <: VersionCriterion; timestamp::Any end    # newest with timestamp ≤ t
struct VersionCriterionPredicate <: VersionCriterion; predicate::Any end    # newest matching f(properties)
```

`select_version(vo::VersionedObject) -> (index, ObjectVersion)` dispatches on
`vo.criterion`, scanning `vo.versions` and their `properties`. Returns the
chosen index (needed for reference mapping) and the version, or `nothing` when
no version matches (the projection then emits a `DocumentNothing`, mirroring
`ClipboardSlice`'s empty-slice fallback).

### File: `package/versioning/main/VersioningToAny.jl`

**✅ DONE (verified):** implemented there, in the standalone `versioning` package.

The elimination projection — the direct analogue of
`ClipboardSliceToAnyProjection`. One `VersionedObject` in, the projected
**value object of the selected version** out.

```julia
struct VersioningToAnyProjection <: Projection end   # criterion lives on the document
```

**Printer** (`projection_print(::VersioningToAnyProjection, recursion, input::VersionedObject, ctx)`):

1. `(idx, version) = select_version(input)`.
2. Recurse into that version's value:
   `value_iomap = projection_printer_recurse(recursion, version.value,
       child_context(ctx, FieldReference("versions"), ElementReference(idx),
                     FieldReference("value")))`.
3. `output = value_iomap.output` (the wrapper vanishes; the value object's
   projection *is* the output). Store `idx`, `value_iomap` (and a default for
   the empty case) in the iomap.

**Reference mapping** — exactly the asymmetric peel/prepend from
`ClipboardToAny`:

- `map_reference_forward`: require the path to descend through
  `versions[idx].value`, strip those three steps, delegate the remainder to the
  value child's iomap.
- `map_reference_backward`: delegate to the value child, then prepend
  `versions[idx].value` so the resulting path is rooted at the `VersionedObject`.

**Reader** (`projection_read`): delegate non-versioning gestures into the value
child's reader and re-root the returned operation under `versions[idx].value`
(the `_prefix_op` / `_prepend` helper, copied from `ClipboardToAny`). Own
gestures handle version management (below).

Because the elimination is purely structural and recursive (every `recursion`
re-enters `projection_printer_recurse`, which re-dispatches on the next node's
type), nested `VersionedObject`s inside a selected value are resolved
automatically — each by its own criterion.

### Operations (version management)

Plain `Operation` subtypes evaluated by `evaluate_operation`, following the
clipboard's gesture→operation→re-root style:

- **`CreateVersionOperation`** — snapshot the current selected value into a new
  `ObjectVersion` (deep-copied via `copy_document`, with fresh
  `VersionProperties`: timestamp now, author/origin from editor context) and
  `CollectionInsertOperation` it at the front of `versions`. This is how a
  "save point" is taken; it is *not* tied to undo.
- **`SetVersionCriterionOperation`** — replace `vo.criterion` (e.g. switch from
  *latest* to *as-of T* or pin an index). Like the clipboard display toggle,
  this swaps which child becomes the output, so it must drop `editor.iomap` to
  force a rebuild on the new criterion (see `ToggleClipboardSliceDisplay`).
- **`DeleteVersionOperation`** — `CollectionDeleteOperation` on `versions`.
- *(optional)* **`EditVersionPropertiesOperation`** — handled for free: the
  properties are a projectable document, so editing them just needs a
  projection that exposes the version list (a "history" view, below).

### Two viewing modes

1. **Eliminated (default).** `VersioningToAnyProjection` shows one version's
   value as a plain document. Editing edits that version's value in place.
2. **History (optional, later).** A projection that exposes `versions` as a
   collection — each entry rendered as `properties` + a preview of `value` —
   for browsing, diffing, pinning, and labeling. This is the versioning analogue
   of the clipboard's `display_collection` mode and can reuse
   `CollectionToSyntax`/widget tables. Defer until the eliminated mode works.

## Design Decisions

**A domain + elimination projection, not an operation log.** Versions are
values stored in the document tree, so they are inspected, projected, edited,
copied, persisted, and *recursively versioned* using machinery that already
exists. An undo-style log would require a complete invertible-operation
vocabulary (which the codebase does not yet have) and could not naturally
express *branching* or *per-subtree* versioning. Storing versions as data makes
per-subtree versioning the default rather than the hard case.

**Two levels, not one.** Folding properties into `VersionedObject` (a parallel
`values`/`metadata` pair of arrays) was rejected: it desynchronizes under
insert/delete and prevents a version's properties from being a first-class,
projectable, individually-selectable document. `ObjectVersion` keeps a value and
its properties together as one addressable unit.

**Criterion as an abstract type with subtypes.** Mirrors
`DocumentLocator<Mode>` and the existing `ReferenceStep`/`GraphEdge` families.
`select_version` dispatches on the concrete criterion; new modes (by-tag,
by-session, by-predicate) are new subtypes with zero changes to the projection
or documents. A single `criterion::Any` slot with `if/elseif` was rejected for
the same reasons given in `document-locator.md`.

**Optionality falls out of projection dispatch.** `projection_print` only
matches `VersionedObject`; any other node is projected by whatever projection
already handles it. There is no flag to toggle versioning on — wrapping a node
*is* turning it on, unwrapping is turning it off.

**Recursion falls out of `projection_printer_recurse`.** The elimination
projection never special-cases nesting; the standard recursion re-dispatches at
every node, so versioned values containing further versioned objects resolve
layer by layer, each by its own criterion.

**Criterion on the document, not the projection.** Unlike the clipboard's
display flag (which lives on the projection instance), the criterion is stored
on the `VersionedObject` so different versioned nodes in the same tree can be
viewed under different criteria simultaneously, and so the choice is part of the
(persistable) document state. A single global projection instance still works
for every versioned node.

## Exports

**As built**, versioning is its own package (`ProjecturedVersioning`, loaded by
`package/versioning/main/ProjecturedVersioning.jl`), not an include list inside a
shared domain file. `package/versioning/main/Versioning.jl` exports
`VersioningDocument, VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate, select_version`
(the `I`-struct names are generated by `@document` and not separately exported).
`package/versioning/main/VersioningToAny.jl` exports `VersioningToAnyProjection,
VersioningToAnyProjectionIoMap, SetVersionCriterionOperation` — **no**
`CreateVersionOperation` / `DeleteVersionOperation` types exist; see the design
refinement recorded at step 3 below (they became `_create_version`/`_delete_version`
helpers emitting the generic collection operations).

Original design (superseded by the paragraph above):

```julia
export VersioningDocument, VersionedObject, ObjectVersion, VersionProperties,
       IVersionedObject, IObjectVersion, IVersionProperties
export VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
       VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate,
       select_version
export VersioningToAnyProjection, VersioningToAnyProjectionIoMap,
       CreateVersionOperation, SetVersionCriterionOperation, DeleteVersionOperation
```

## Examples & tests

- **`example/src/document/Versioning.jl`** — a small versioned JSON example: a
  `VersionedObject` over a `JsonObject` with two or three `ObjectVersion`s
  carrying different timestamps/authors. Register it like the other examples so
  the test harness picks it up.
- **`test`** — add to the printer/reader/navigation suites. The key assertions:
  - **Printer:** under `VersionCriterionLatest`, the projected output equals the
    plain projection of the newest version's value (the wrapper is invisible);
    switching to `VersionCriterionIndex(2)` yields the second version's value.
  - **Reader:** an edit gesture (e.g. a JSON typein) on the eliminated view
    produces an operation rooted at `versions[idx].value.…` — verify the
    re-rooting, mirroring the clipboard reader tests.
  - **Recursion:** a `VersionedObject` whose selected value contains another
    `VersionedObject` projects through both layers.
  - **Empty:** a `VersionedObject` with no matching version projects as
    `DocumentNothing` without error.
  - Use the narrowest helpers per [documentation/testing.md](../../documentation/testing.md):
    `test_printer(versioning_example)`, `test_reader(versioning_example)`,
    `test_text_navigation(versioning_example)` — never `test_all`.
- **[package/versioning/doc/versioning.md](../../documentation/package/versioning/versioning.md)** —
  a short domain guide once the code lands, linked from `CLAUDE.md`'s per-domain list.
  **As built:** this file exists.

## Implementation Steps

> **Audit note (2026-08-12):** Steps 1–4 and 6 are implemented, now in the
> standalone `package/versioning/` package (its own package, not a module folded
> into a shared domain package — see [documentation/packages.md](../../documentation/packages.md)).
> Only the optional History view (step 5) remains open.

1. **✅ DONE (verified):** **`VersioningModule`** — `VersionProperties`,
   `ObjectVersion`, `VersionedObject`, the `VersionCriterion` hierarchy, and
   `select_version`. Include + export in `Projectured.jl`. Unit-test
   `select_version` for each criterion (latest, index, by-author, as-of,
   predicate, no-match).
   Evidence: `package/versioning/main/Versioning.jl` defines all three
   `@document` types, the five `VersionCriterion` subtypes, and `select_version`,
   with `export`. Included by `package/versioning/main/ProjecturedVersioning.jl`
   and re-exported through the umbrella `package/projectured/main/Projectured.jl`.
   All six criteria are unit-tested in
   `package/substrate/test/projection/VersioningToAnyTest.jl`
   ("select_version criteria" testset).
2. **✅ DONE (verified):** **`VersioningToAnyProjection`** — printer +
   forward/backward reference mapping + reader delegation/re-rooting, copied
   structurally from `ClipboardToAny.jl`. Include + export.
   Evidence: `package/versioning/main/VersioningToAny.jl` defines `print_document`,
   `map_reference_forward`/`map_reference_backward`, `projection_read` (via
   `get_projection_gesture_bindings` + `read_intent`) with `_create_version`/
   `_delete_version` re-rooting, and `export`s `VersioningToAnyProjection`,
   `VersioningToAnyProjectionIoMap`, `SetVersionCriterionOperation`.
3. **✅ DONE (verified, with design refinement):** **Version operations** —
   `SetVersionCriterionOperation` exists as a named `Operation` and drops
   `editor.iomap` in `evaluate_operation`. `CreateVersionOperation`/
   `DeleteVersionOperation` were implemented per the "school-A" pattern as
   standard `CollectionInsertOperation`/`CollectionDeleteOperation` emitted by
   the reader helpers `_create_version`/`_delete_version`, bound through
   `get_projection_gesture_bindings`, rather than as dedicated named operation
   types — the deliverable (snapshot/delete version) is present and tested
   ("own gestures" testsets, `VersioningToAnyTest.jl`).
4. **✅ DONE (verified):** **Example + tests** — the versioned-JSON example and
   the printer/reader/navigation/recursion/empty assertions above.
   Evidence: `package/projectured/example/document/Versioning.jl`
   (`make_versioning_document_example`, three `ObjectVersion`s over a
   `JsonObject`) and `package/projectured/example/projection/Versioning.jl`
   (`make_versioning_projection_example`), registered as `versioning_example` in
   `package/projectured/example/DomainExamples.jl` / `Examples.jl`.
   `package/substrate/test/projection/VersioningToAnyTest.jl` covers printer,
   reader re-rooting, empty/no-match → `DocumentNothing`, and recursion
   versioned-in-versioned.
5. **⏳ OPEN:** **History view (optional, later)** — a collection-style
   projection over `versions` for browsing/diffing/pinning; defer until 1–4 pass.
   No implementation found (a grep for `history` inside `package/versioning/`
   returns nothing). Explicitly optional and deferrable per this plan.
6. **✅ DONE (verified):** **Guide** — a short domain guide, linked from `CLAUDE.md`.
   Evidence: `package/versioning/doc/versioning.md` exists and is linked from the
   per-domain list in `/home/projectured/workspace/projectured-julia/CLAUDE.md`.

## Open Questions

- **Re-rooting helper reuse.** `ClipboardToAny`'s `_prefix_op`/`_prepend` are
  private. Either copy them (current clipboard approach) or promote a shared
  `prefix_operation(op, steps)` into a common module — worth doing if a third
  elimination projection appears. Decide during step 2.
- **Default criterion & empty list.** Is the default `VersionCriterionLatest`,
  and does an empty `versions` render `DocumentNothing` or is a
  `VersionedObject` required to always hold ≥1 version? Leaning: default latest,
  allow empty → `DocumentNothing`.
- **Editing a non-active version.** In eliminated mode edits target the selected
  version. Editing another version is only reachable via the history view —
  acceptable, or should there be a "pin then edit" affordance?
- **Copy-on-write vs. in-place edit.** Does editing the active version mutate it,
  or auto-fork a new version (immutable history)? Default: in-place mutate;
  `CreateVersionOperation` is the explicit snapshot. Auto-fork could be a
  criterion/policy later.
- **Timestamp/author source.** `CreateVersionOperation` needs the current time
  and the acting author/origin. Where does the editor expose these? Possibly via
  the printer/projection context (see [package/kernel/doc/editor.md](../../documentation/package/kernel/editor.md))
  — confirm before step 3.
- **Persistence.** `VersionProperties`/`ObjectVersion` snapshot through the
  generated `I`-structs; long-lived version history intersects the external
  persistence question (`further-development.md` §13).

## Dependencies

- `CollectionModule` (`CellVector`) — `versions` is a collection; load
  `Versioning.jl` after `Collection.jl`.
- `ReferenceModule`, `PrinterContextModule`, `IoMapApiModule`, `OperationModule`,
  `KeyboardModule`, `EventCaseModule`, `DocumentCopyModule` — same set
  `ClipboardToAny.jl` imports.
- No domain depends on versioning; it sits *above* every domain as an optional
  wrapper, so no existing document or projection needs changes.
