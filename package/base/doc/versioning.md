# Versioning domain

A generic, domain-neutral overlay that lets **any** document subtree carry
multiple versions of itself. Versioning is an optional, recursive wrapper layer
plus an *elimination projection* that collapses the wrapper away — after which
the downstream domains are ordinary, non-versioned documents and every existing
projection pipeline works unchanged.

It is structurally the same pattern as the clipboard
([`ClipboardModule`](../../../package/visual/main/clipboard/Clipboard.jl) +
[`ClipboardToAny.jl`](../../../package/visual/main/clipboard/ClipboardToAny.jl)):
a wrapper document holding a payload, and a projection that decides which child
becomes the output and re-roots edits back into that child.

## Documents — `VersioningModule`

Two levels, defined in
[`package/base/main/versioning/Versioning.jl`](../../../package/base/main/versioning/Versioning.jl):

- **`VersionedObject`** — the container that *has versions*: a `versions`
  `CellVector` of `ObjectVersion`s (newest-first by convention) plus the active
  selection `criterion`.
- **`ObjectVersion`** — one *value object* (`value::Document`, the actual domain
  document for this version) together with its `properties`.
- **`VersionProperties`** — version metadata (`timestamp`, `author`, `origin`,
  `label`), all optional. A document so it is itself inspectable/editable/
  projectable.

Convenience constructors: `VersionedObject(value)` wraps a single initial
version; `VersionedObject([v1, v2, …])` takes an explicit list;
`ObjectVersion(value; timestamp=…, author=…, …)` builds the properties for you.

Two essential properties:

- **Optional** — a subtree is versioned only if wrapped in a `VersionedObject`.
  Nothing else changes.
- **Recursive** — a version's value may itself contain `VersionedObject`s nested
  anywhere; each resolves independently.

## Criteria

The active version is chosen by a `VersionCriterion` stored *on the document*
(so different versioned nodes in one tree can use different criteria at once):

| Criterion | Selects |
|---|---|
| `VersionCriterionLatest()` | the newest version (index 1) |
| `VersionCriterionIndex(i)` | the 1-based pin `i` |
| `VersionCriterionByAuthor(a)` | newest version with `properties.author == a` |
| `VersionCriterionAsOf(t)` | newest version with `properties.timestamp ≤ t` |
| `VersionCriterionPredicate(f)` | newest version with `f(properties)` true |

`select_version(vo) -> Union{Nothing, Tuple{Int, ObjectVersion}}` dispatches on
the criterion and returns the chosen `(index, version)`, or `nothing` when none
matches. New modes are new subtypes with zero changes to the projection.

## Elimination projection — `VersioningToAnyProjection`

[`package/base/main/versioning/VersioningToAny.jl`](../../../package/base/main/versioning/VersioningToAny.jl)
is the direct analogue of `ClipboardSliceToAnyProjection`:

- **Printer** — `(idx, version) = select_version(input)`, recurse into
  `version.value` through `print_child`, and make that recursion's
  output *be* the projection's output (the wrapper vanishes). When no version
  matches, the output is a `DocumentNothing` (the clipboard's empty-slice
  fallback).
- **Reference mapping** — asymmetric peel/prepend of the three steps
  `versions[idx].value`: forward strips them and delegates the tail to the value
  child; backward delegates to the value child and prepends them.
- **Reader** — own gestures manage versions (`Ctrl+Shift+S` snapshots the active
  value into a new front `ObjectVersion` via a standard `insert_elements` splice on
  `versions`; `Ctrl+Delete` deletes the active version via `delete_elements`). Using
  the standard sequence-splice helpers — which build a `ReplaceReferencedValueOperation` with
  a terminal `RangeReferenceStep`, rather than bespoke version ops — is what lets every
  ancestor projection re-root them when the `VersionedObject` is nested. `SetVersionCriterionOperation` switches the
  active criterion (it drops `editor.iomap`, like the clipboard display toggle).
  Every other gesture is delegated into the value child's reader and the returned
  operation is re-rooted under `versions[idx].value`.

Recursion across nested versioned objects falls out of
`print_child` re-dispatching on each node, so a versioned value
containing further versioned objects is resolved layer by layer.

### Criterion swapping

`SetVersionCriterionOperation` replaces `vo.criterion` and, like the clipboard
display toggle, drops `editor.iomap` to force a rebuild on the new criterion
(see `ToggleClipboardSliceDisplayOperation`).

## Example & tests

- Example: `make_versioning_document_example` / `make_versioning_projection_example`
  (`versioning_example`) — a `VersionedObject` over a `JsonObject` with three
  `ObjectVersion`s. Like `clipboard_example`, it is kept out of the enumeration
  registry; run it directly, e.g. `test_printer(versioning_example)`.
- Tests: `test/projection/VersioningToAnyTest.jl` (`test_versioning_to_any`)
  covers `select_version` per criterion, the printer under Latest vs Index, the
  empty/no-match → `DocumentNothing` case, reference peel/prepend, reader
  re-rooting, the version-management gestures, and versioned-in-versioned
  recursion.
