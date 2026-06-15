# TypeReference as a type checkpoint for reference validity

Make `TypeReference` record the **type of the node at the current position** in a
reference path, so that a stored reference can be re-checked against a (possibly
mutated) document: if the actual node's type no longer matches the recorded type,
the **remaining path from that step on is considered invalid**.

Status: **implemented** (2026-06-15). See the "Implementation notes" at the end
for what actually shipped and where the design was adjusted.

## Motivation

References are immutable paths into a document tree
([`program/src/reference/Reference.jl`](../../program/src/reference/Reference.jl)).
They are persisted and replayed — a selection captured before an edit is
re-evaluated against the document after it. When the document's *structure*
changes underneath a stored path (e.g. a `JsonString` is replaced by a
`JsonNumber`, an entry is retyped, a node is swapped for another domain type),
the leftover path steps silently mis-navigate or throw a bare
`"Unsupported reference step"` / `getfield` error.

A `TypeReference` checkpoint pins the expected type at a point in the path. On
replay we can detect the mismatch *at the checkpoint* and truncate the path to
its longest still-valid prefix instead of erroring or dereferencing into the
wrong node.

## Design decision: repurpose `TypeReference` (flag for confirmation)

Today `TypeReference(type)` is **documented** as "element of a given type within a
heterogeneous collection" — i.e. a *navigating* step that descends to a child of
a given type. That meaning was **never implemented**: there is no
`evaluate_reference` case for it (it hits the `error("Unsupported reference
step")` branch at
[`Reference.jl:410`](../../program/src/reference/Reference.jl#L410)), and grep
shows no construction of `TypeReference` anywhere except display
([`ReferenceToText.jl`](../../program/src/projection/primitive/ReferenceToText.jl))
and the export lists. So the navigation semantics are vacant and can be cleanly
redefined.

**Proposed semantics:** `TypeReference(T)` is a **non-navigating assertion** on
the *current* node: "the node reached so far must be a `T`." It does not descend;
evaluation stays on the same node and continues with the tail.

This is a meaning change, not an addition. Confirm before implementing. If the
original "find the child of type T" navigation is still wanted, it should get a
different step name (e.g. `OfTypeReference`) and `TypeReference` is freed for the
checkpoint role.

## 1. Step semantics in `Reference.jl`

- Keep the struct shape `TypeReference(type::Any)` (callers pass a `Type`).
  Update the docstring to the checkpoint meaning.
- Match predicate: `node isa step.type`. Checkpoints are created from
  `typeof(node)` (exact), so `isa` holds on replay iff the type is unchanged,
  while still tolerating a recorded abstract supertype. Decide and document the
  one rule; default **`isa`**.
- Evaluation — add a case to `evaluate_reference`
  ([`Reference.jl:394`](../../program/src/reference/Reference.jl#L394)):

  ```julia
  elseif step isa TypeReference
      document isa step.type ||
          throw(ReferenceTypeMismatch(step.type, typeof(document)))
      return evaluate_reference(document, rest)   # no descent
  ```

  Note `TypeReference` is the one step where the child is the **same** document;
  fold it in before the generic `child = …; evaluate_reference(child, rest)`.
- New exception type `ReferenceTypeMismatch(expected, actual) <: Exception` (in
  this module, exported) so callers can `catch` it specifically and distinguish
  a structural mismatch from a bona-fide bug.

## 2. Document-aware validity / truncation

`is_valid_reference` today is **structural only** (is this object a reference?)
and takes no document. Add document-aware companions, do not overload the
existing one's meaning:

- `valid_reference_prefix(document, path) -> ReferencePath` — walk the path
  applying each step; return the **longest prefix** that navigates without a
  `ReferenceTypeMismatch` (and without a structural nav error). On the first
  failing `TypeReference`, stop and return the prefix accumulated up to (not
  including) it. This is the "remaining path is invalid" behaviour.
- `is_valid_reference(document, path) -> Bool` — a new document-aware method:
  `true` iff every `TypeReference` checkpoint along the whole path holds (i.e.
  `valid_reference_prefix(document, path) == path`). Keep the existing
  single-arg structural method untouched.

## 3. Creating checkpoints: `annotate_reference_types`

Checkpoints have to be inserted to be useful. Add:

- `annotate_reference_types(document, path) -> ReferencePath` — walk `document`
  along `path` and insert a `TypeReference(typeof(node))` immediately **before**
  each navigation step (configurable granularity; start with "before every
  step"). The result is the original path interleaved with checkpoints, ready to
  persist.

Strip-back helper for callers that want the plain path:
`strip_reference_types(path)` removes all `TypeReference` steps, yielding the
original navigation-only path (round-trips with `annotate_reference_types`).

## 4. Integration points (opt-in first)

The mechanism is opt-in; wire it where replaying stale references currently
bites, one site at a time:

- **Selection replay** — `set_selection!` / selection propagation should call
  `valid_reference_prefix` and apply the truncated path rather than throwing.
  (Trace the selection-application path from
  [`guide/editor/selection.md`](../../guide/editor/selection.md).)
- **Focusing** — [`Focusing.jl:125`](../../program/src/projection/generic/Focusing.jl#L125)
  already does `try evaluate_reference(…) catch; break end`; a
  `ReferenceTypeMismatch` slots straight into that graceful-degradation path.
- **JSON/XML→Syntax mappers** — `try evaluate_reference(input, sel) catch; nothing end`
  ([`JsonToSyntax.jl:537`](../../program/src/projection/primitive/JsonToSyntax.jl#L537),
  [`XmlToSyntax.jl:409`](../../program/src/projection/primitive/XmlToSyntax.jl#L409))
  already tolerate failures; mismatches become `nothing` as before — no change
  needed, just confirmed compatible.

## 5. DSL + display (small)

- `@reference` / `@step`
  ([`ReferenceBuilder.jl`](../../program/src/reference/ReferenceBuilder.jl)) and
  `@reference_case`
  ([`ReferenceCase.jl`](../../program/src/reference/ReferenceCase.jl)): optional
  surface syntax for a checkpoint, e.g. `value::JsonString.value` → insert
  `TypeReference(JsonString)`. Defer until a caller needs to hand-write one;
  `annotate_reference_types` covers the programmatic case.
- Display already renders `TypeReference` as `{{Type}}`
  ([`ReferenceToText.jl:104`](../../program/src/projection/primitive/ReferenceToText.jl#L104)).
  Equality is already `===` on the type field. No change.

## 6. Tests

- Evaluation: matching type continues on the same node; mismatching type throws
  `ReferenceTypeMismatch`.
- `valid_reference_prefix`: returns full path when all checkpoints hold; returns
  the prefix up to the first failing checkpoint after the document is mutated to
  change a node's type.
- `annotate_reference_types` / `strip_reference_types` round-trip; an annotated
  path still evaluates to the same node as the bare path on an unchanged
  document.
- A selection-replay test: capture an annotated selection, retype a node, assert
  the selection truncates to the valid prefix instead of throwing.

Smallest scopes to run (per `CLAUDE.md`): `test_cell()` is unrelated; use a
targeted reference test plus `test_selection(json_example)` once selection
replay is wired.

## Open questions

- **Crossing projection boundaries.** A `TypeReference` records an
  *input-domain* type; it is meaningless after `map_reference_forward` into the
  output domain. Initial rule: `map_reference_forward` / `map_reference_backward`
  **strip** `TypeReference` checkpoints they cross (they are validity metadata,
  not navigation). Confirm and test against one projection.
- **`isa` vs exact `typeof ===`.** `isa` tolerates an abstract recorded type;
  exact identity is stricter ("the node is literally the same concrete type").
  Pick one rule and document it (default `isa`).
- **Granularity of annotation** — checkpoint before *every* step vs only before
  steps whose navigation depends on the node's type (`FieldReference`,
  `RangeReference`). Start with every-step; tighten if paths get noisy.

## Touch list

- [`program/src/reference/Reference.jl`](../../program/src/reference/Reference.jl)
  — semantics, `evaluate_reference` case, `ReferenceTypeMismatch`,
  `valid_reference_prefix`, document-aware `is_valid_reference`,
  `annotate_reference_types` / `strip_reference_types`, exports.
- [`program/src/Projectured.jl`](../../program/src/Projectured.jl) — re-export
  new names.
- Selection replay site (TBD via [`guide/editor/selection.md`](../../guide/editor/selection.md)).
- [`guide/editor/reference.md`](../../guide/editor/reference.md) — document the
  new `TypeReference` meaning and the validity functions.
- Tests under `test/src/` (reference + selection).

## Implementation notes (what shipped)

All of §1–§3 and §6 landed; §4–§5 were intentionally scoped down.

- **§1 semantics** — `TypeReference(T)` is the non-navigating checkpoint;
  `evaluate_reference` folds it in *before* the navigating branch (same node, no
  descent) and throws `ReferenceTypeMismatch(expected, actual)` (with a
  `showerror`) on failure. Match rule chosen: **`isa`** (resolves the open
  question — abstract recorded types are tolerated; `annotate_*` records exact
  `typeof`, so it still holds exactly on an unchanged document).
- **§2 validity** — `valid_reference_prefix(document, path)` returns the longest
  resolvable prefix, truncating at the first failing checkpoint *or* the first
  unfollowable structural step (missing field, out-of-range index, throwing
  `FunctionReference`). Steps with no document navigation
  (`Point`/`Projection`/`Text…`) are kept only as a terminal step. Document-aware
  `is_valid_reference(document, path)` is `prefix == path`; the one-arg
  structural `is_valid_reference(obj)` is untouched.
- **§3 annotation** — `annotate_reference_types` inserts a checkpoint **before
  every** navigation step (the every-step granularity from the open question) and
  also a **trailing** checkpoint asserting the destination node's type; existing
  checkpoints are preserved, not double-annotated. `strip_reference_types`
  inverts it.
- **§4 integration — narrowed.** No change to `set_selection!` /
  `clear_selection!`. Reason: those walk a *per-node stored suffix* (each node
  re-derives its path from its own `selection` cell), and a non-navigating
  checkpoint stored in that path would rewrite the same cell and break the
  descent. Checkpoints are therefore kept **out of** stored selection paths; the
  intended replay pattern is to truncate-then-strip *before* applying:
  `set_selection!(doc, strip_reference_types(valid_reference_prefix(doc, stored)))`.
  The JSON/XML mappers and `Focusing.jl` already wrap `evaluate_reference` in
  `try/catch`, so a `ReferenceTypeMismatch` degrades there with no code change.
  Wiring a concrete live replay site is left for when one needs it.
- **§5 DSL — deferred.** No `@reference` / `@reference_case` surface syntax for
  checkpoints yet; `annotate_reference_types` covers the programmatic case and no
  caller hand-writes one. Display (`{{Type}}`) and `===` equality already
  existed.
- **Projection-boundary stripping** (open question) — not exercised; the guide
  states the rule (annotate/validate within one domain, strip before crossing)
  but no mapper strips checkpoints because none are constructed across a boundary
  yet.
- **Tests** — `test/src/reference/TypeReferenceTest.jl`
  (`test_type_reference`, 13 assertions, registered in `test_all` + exported):
  non-navigating evaluation, mismatch throw, mid-path passthrough, annotate/strip
  round-trip, truncation on a type change, structural out-of-range truncation,
  and that the one-arg structural check is unchanged. Passes.
