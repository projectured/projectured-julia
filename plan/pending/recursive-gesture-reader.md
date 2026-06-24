# Recursive gesture reader: delegate to the selected child, lift the operation

> **Status: pending.** Design grounded in the current reader architecture
> (verified empirically, 2026-06-24). The acceptance demo — a live example that
> types the full nested `json_example` from an empty document, recorded to video —
> is Stage 4 and is the original ask that surfaced the bug.

## The design principle (to be documented)

**A structural (container) projection's gesture reader should delegate a raw input
gesture to the reader of the *projection of the selected child element*, and lift
the resulting operation back into its own domain. It may override — handle the
gesture itself — but in general it should not; it defers to the child first and
only acts at its own level when the child declines (or for a gesture that has no
child pre-image).**

This is the reader-side mirror of three things the codebase already does:

- the **printer** is recursive — `@projection_template`'s `collection(:field)` /
  `project(:value)` delegate each child subtree to the child's projection and
  record the per-child correspondence (`child_iomaps`, "School A");
- the **operation reader** is already recursive — `map_reference_backward`
  walks `child_iomaps` (`ProjectionTemplate.jl`), so a `ReplaceSelectionOperation`
  / `StringReplaceRangeOperation` whose path points into a child is mapped through
  the child projection;
- **container event routing already lifts** — `WidgetToGraphics` /
  `LayoutToGraphics` route a `MousePress`/`MouseScroll` to the hit child via
  `projection_read(child.projection, child, evt)` and lift the returned operation
  with `prepend_steps_to_op(op, steps)` (`OperationRerooting.jl`).

The **raw-gesture (keyboard authoring) reader** at the structural layer is the one
place that is *not* recursive yet. That is the gap this plan closes.

## Motivation — the concrete bug

The full `json_example` is nested (an `address` object, `scores`/`tags` arrays, a
`meta` object). Authoring it from an empty document by typing is impossible today:

- `,` (insert sibling entry) and `Tab` (key→value) only work on the **root**
  object. Inside a nested object they either no-op (`Tab`) or insert at the root
  (`,`) — e.g. typing into `address` appends `city` as a *root* entry.
- Array element insertion (`,` on a `JsonArray`) only fires when the **root** is an
  array, never for a nested `scores`/`tags`.

Root cause (verified): the authoring gestures reach the JSON layer as **raw
events** (the Text/Syntax layers decline `,`/`Tab`/`{`/`"`), where the generic
leaf fallback in `Projection.jl` calls `document_read(iomap.input, event)` with
`iomap.input` = the **root** `JsonObject`. The reified `@gestures JsonObject`
helpers then run against the root:

- `_object_insert(doc)` does `insert_elements(@reference(entries), length(doc.entries), …)`
  — always appends to the **root** object.
- `_object_tab(doc)` pattern-matches only the root-level shape `entries[i].key…`;
  a nested key path `entries[i].value.entries[j].key…` falls through → no-op.

## Why the fix is small: selection already localizes

`set_selection!` → `_set_selection_walk!` (`kernel/src/common/Operation.jl`)
**already propagates** the selection down the document tree: each nested
`@document` node's `selection` cell holds its **own subtree-relative** remaining
path. With a caret in `address.street`'s key the cells hold:

| document node        | its `selection` cell                          |
|----------------------|-----------------------------------------------|
| root `JsonObject`    | `entries[1].value.entries[1].key{6}` (full)   |
| `address` `JsonObject` | `entries[1].key{6}` (relative)              |
| `street` key string  | `{6}`                                          |

So `document_read(addressObject, ',')` would *already* do the right thing —
`_object_insert(addressObject)` appends to `address.entries`, `_object_tab` matches
the now-root-relative `entries[1].key…`. **The gesture helpers need (almost) no
change.** The only missing piece is that the reader must *call* `document_read` on
the **focused** nested document instead of the root, and lift the returned
(child-relative) operation back to the root domain.

## Target design

Add a recursive **gesture reader at the structural template layer** (`RuleIoMap`,
and by extension the JSON node projections), parallel to the existing recursive
operation reader:

```
projection_read(p, iomap::RuleIoMap, evt::Union{KeyPress,KeyDown,MousePress}):
    child = focused_child_iomap(iomap)          # via selection + child_iomaps
    if child !== nothing
        child_op = projection_read(child.projection, child, evt)   # recurse
        child_op !== nothing && return lift(child_op, steps_to(child))
    end
    return document_read(iomap.input, evt)       # own-level handling / override
```

Properties:

- **Innermost-first with bubbling.** The recursion descends to the focused leaf;
  on the way back, the *nearest enclosing* structural node whose `document_read`
  produces an operation wins. That is exactly how `,` should target the nearest
  enclosing object/array and `Tab` the enclosing object.
- **Lift = prepend steps.** Reuse `prepend_steps_to_op` (the same lift
  `WidgetToGraphics`/`LayoutToGraphics` use) with the input-domain step(s) from
  the parent to the focused child (`entries[i].value`, `elements[i]`). The steps
  are exactly what `child_iomaps` already records for the printer/operation
  reader.
- **Override stays possible.** A projection can still special-case a gesture at its
  own level (the trailing `document_read(iomap.input, evt)` *is* the override
  seam, and a node may add its own pre-check) — but the default is "defer to the
  child."
- **No behavior change at the root.** When the selection is a direct root child,
  `focused_child` bottoms out quickly and the trailing `document_read(root, evt)`
  reproduces today's behavior — so existing root-level authoring and the
  `test_json_to_syntax_reader` 47/1/0 baseline are preserved.

### Open design questions (resolve during implementation, record decisions here)

1. **Where the recursive event reader lives.** Preferred: a generic
   `projection_read(p, iomap::RuleIoMap, evt)` in `ProjectionTemplate.jl` so
   *every* `@projection_template`-built structural projection inherits recursion
   (JSON, and later XML/syntax), not a JSON-specific method. Must disambiguate
   against the `RecursiveProjection`/`RuleIoMap` method tie the existing
   operation readers already had to break (see the concrete-typed shims at
   `ProjectionTemplate.jl:920`).
2. **Identifying the focused child + its lift steps.** Factor a helper out of the
   existing `map_reference_backward` child-walk (it already finds the child iomap
   and the descending step for a given path) so the event reader and the operation
   reader share one "follow the selection to the focused child" routine. Handle the
   wirings that carry children: `NodeWiring`, `FixedNodeWiring`, `MixedNodeWiring`,
   `InlineWiring`, `SectionsWiring`.
3. **Selection on the focused child for `document_read`.** Rely on the
   already-propagated per-node `selection` cell (above). Confirm it is fresh at
   read time (the printer rebuilds child docs; the propagated selection must match
   the iomap the reader holds). If a mismatch is possible, compute the child-
   relative selection from the parent path instead of reading the cell.
4. **Whole-document-swap operations.** `_replace` / type-to-replace already work at
   depth today (they target the full root selection path). Under recursion they
   would instead be produced by the focused doc (relative) and lifted. Verify the
   lift yields an identical absolute path (it should) so type-to-replace is
   unchanged.
5. **`_object_insert` insertion point.** Currently appends at the focused object's
   end. Keep (sequential authoring appends); revisit "insert after current entry"
   separately if desired.

## Staged implementation

Work in a dedicated worktree; commit per stage; keep the plan updated with
decisions; run the **narrowest** covering test first (never `test_all`).

- **Stage 1 — recursive event reader (kernel/template).** Add the
  `focused_child_iomap` + lift helper and the recursive
  `projection_read(p, iomap::RuleIoMap, evt)`; wire the leaf fallback to defer to
  it. Tests: `test_json_to_syntax_reader` stays at 47/1/0 for root-level gestures.
- **Stage 2 — nested authoring works.** Verify with a driver (the same
  read→evaluate→reprint loop the recorder uses): from an empty doc, build a nested
  object (`address`) and a nested array (`scores`) by typing only. New focused
  tests: nested `,` inserts into the nested object/array; nested `Tab` moves
  key→value inside a nested object; nested type-to-replace unchanged.
- **Stage 3 — sweep + parity.** Run `test_json()` / `test_json_to_syntax()` /
  `test_syntax_tree_selection` and the printer tests; confirm no regression beyond
  the known-pre-existing baselines (see memory: JSON reader 47/1/0, syntax
  tree-selection 12/9/4).
- **Stage 4 — acceptance demo (the original ask).** Add
  `json_build_live` to `LiveExamples.jl`: a `LiveExample` over a new empty-document
  Example paired with the full `make_json_projection_example`, whose timeline types
  the entire `json_example` (keys, values, nesting, arrays) using only
  `timed_event` gestures (`{`, key, `Tab`, `"`/digits/`t`/`f`, `Alt+Up` to escape a
  value before `,`, `,` for siblings). Verify the resulting document equals
  `make_json_document_example()` (modulo the trailing insertion placeholder), then
  **record it to a video** via `record_live_example(json_build_live, "…mp4")` and
  report the path. Export + register in `live_examples`.
- **Stage 5 — document the principle.** Write the principle (top of this file)
  into `documentation/projection-system.md` (reader interface section) with a
  pointer from `documentation/operations.md` (re-rooting) and the module docstrings
  of `OperationRerooting.jl` / `Projection.jl`. Cross-link the existing precedents
  (printer recursion, `map_reference_backward`, `WidgetToGraphics` routing).

## Files (anticipated)

- **Edit:** `package/domain/src/projection/ProjectionTemplate.jl` — recursive
  event reader + shared focused-child helper.
- **Edit:** `package/kernel/src/common/Projection.jl` — leaf fallback defers to the
  recursive reader (or documents that the template reader supersedes it).
- **Maybe edit:** `package/domain/src/document/Json.jl` — only if a gesture helper
  assumed the root (audit `_object_insert`/`_object_tab`/`_array_insert`); expected
  to be unchanged.
- **Edit:** `package/example/src/LiveExamples.jl` + `ProjecturedExample.jl` —
  `json_build_live` + export/registration.
- **Edit:** `documentation/projection-system.md`, `documentation/operations.md`,
  `OperationRerooting.jl`, `Projection.jl` docstrings.
- **Tests:** extend the JSON reader test with nested-authoring cases.

## Risks / watch-list

- **Method ambiguity** at `RuleIoMap` (the operation readers already needed
  concrete-typed shims for the `RecursiveProjection` tie — mirror that).
- **Double handling**: ensure a gesture handled by a child is not *also* handled by
  an ancestor (return immediately on a non-`nothing` child op).
- **Selection freshness** across the reprint cycle (Open question 3).
- Keep the recursion confined to raw **gesture** events; navigation/char-typein
  still arrive as operations and must keep flowing through the existing
  `map_reference_backward` path unchanged.
- `json_build_live` depends on Stage 1–3 landing; until then a flat-only or
  operation-assisted demo is the fallback (the already-committed `json_insert_live`
  shows the single-entry insert).
