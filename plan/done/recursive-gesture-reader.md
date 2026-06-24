# Recursive gesture reader: delegate to the selected child, lift the operation

> **Status: DONE (2026-06-24).** Implemented on branch `recursive-gesture-reader`.
> All five stages landed; nested object/array authoring by typing works; parity
> sweep green (JSON reader at the pre-existing 47/1/0 baseline, `test_repl(json)`
> 225/0/0, `test_syntax_tree_selection` 29/0/0); `json_build_live` types the full
> nested `json_example` from empty (214 pure-event entries, **zero** injected
> operations) and reproduces `make_json_document_example()`; recorded to a 43s MP4.
> Decisions and the open-question resolutions are recorded inline and under
> **"Decisions made during implementation"** at the end.

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

- ✅ **Stage 1 — recursive event reader (template).** Added `_focused_child` (one
  method per child-carrying wiring) + the recursive
  `projection_read(p, iomap::RuleIoMap, evt::Union{KeyPress,KeyDown})` in
  `ProjectionTemplate.jl`, with the `RecursiveProjection`/`RuleIoMap`
  disambiguation shim. `test_json_to_syntax_reader` stayed at 47/1/0.
- ✅ **Stage 2 — nested authoring works.** Driver-verified: nested `,` inserts into
  the nested object **and** array; nested `Tab` moves key→value inside a nested
  object; nested type-to-replace unchanged.
- ✅ **Stage 3 — sweep + parity.** `test_json` 29/0/0, `test_json_to_syntax` 11/0/0,
  `test_json_to_syntax_reader` **47/1/0** (pre-existing array-insert quirk),
  `test_syntax_tree_selection` **29/0/0** (the memory's 12/9/4 baseline is stale —
  fully green now), `test_repl(json_example)` **225/0/0**.
- ✅ **Stage 4 — acceptance demo (the original ask).** `json_build_live` over
  `json_build_example` (a bare `JsonInsertion` under `make_json_projection_example`):
  **214 pure `timed_event` entries, zero injected operations**, using `{`/`[`/`"`/
  digits/`t`/`f` type-to-replace, `Tab` key→value, `,` siblings, and `Alt+Up`
  tree-navigation to step out of a finished value. Driver-verified to reproduce
  `make_json_document_example()` (numbers compared by value). Recorded headlessly
  to `/home/projectured/json_build.mp4` (760×1000, h264, 1304 frames, 43.5s).
- ✅ **Stage 5 — document the principle.** Added the "Recursive gesture reading"
  subsection to `documentation/projection-system.md`, a cross-reference in
  `documentation/operations.md`, and a note in the `OperationRerooting.jl` module
  docstring. (`Projection.jl` needed no edit — the leaf default is simply
  superseded by the more-specific template method; covered by the doc text.)

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

## Decisions made during implementation

- **Open Q1 (where it lives) → a single generic template method.**
  `projection_read(p::Projection, iomap::RuleIoMap, evt::Union{KeyPress,KeyDown})`
  in `ProjectionTemplate.jl` — every `@projection_template` structural projection
  inherits the recursion, no JSON-specific code. `Projection.jl`'s leaf default was
  *not* touched: the new method is strictly more specific (`RuleIoMap` + the event
  `Union`) so it simply wins, and the leaf default still serves non-`RuleIoMap`
  iomaps. The same `RecursiveProjection`/`RuleIoMap` ambiguity the op readers hit
  was broken the same way (a concrete-typed shim deferring to the wrapper).
- **Open Q2 (focused child + steps) → per-wiring `_focused_child`.** One small
  method per child-carrying wiring (`NodeWiring`, `FixedNodeWiring`,
  `MixedNodeWiring`, `SectionsWiring`; `AtomicWiring`/`InlineWiring` → `nothing`),
  returning `(child_iomap, steps)`. Kept separate from `map_reference_backward`
  (which maps an *output*-domain reference) because the event reader walks the
  *input*-domain `selection` — clearer than overloading the existing walk.
- **Open Q3 (selection freshness) → just read the propagated cell.** Each recursion
  level reads its own `iomap.input.selection`. `set_selection!` already writes the
  subtree-relative path into every nested `@document` node (incl. `JsonObjectEntry`),
  so no threading or recomputation is needed; the cells are refreshed after every
  operation. This made the change far smaller than feared.
- **Open Q4 (type-to-replace) → unchanged, confirmed.** Under recursion `{`/`[`/`"`/
  digit are produced by the focused value (relative) and lifted; the lifted path is
  identical to the old root-relative one. The whole-root swap (`ReplaceReferencedValue`
  with an empty path) only happens when the *root* is whole-selected (no focused
  child), exactly as before.
- **Open Q5 (`_object_insert` append point) → kept.** Appends at the focused
  object's end; sequential authoring relies on it. No change to any `Json.jl`
  gesture helper — they were already focus-relative; only the *dispatch target*
  (focused doc vs. root) was wrong, which the recursive reader fixes.
- **The `Alt+Up` ladder is the authoring "step out" gesture.** Mapped empirically
  (with the new reader): from a scalar char-cursor, `Alt+Up×1` whole-selects the
  value (scalars decline `,`, so it bubbles to the containing object); a finished
  nested **array** needs `Alt+Up×3` and a nested **object** `Alt+Up×4` (or ×3 when
  its last value is a bool, already whole-selected) to land on the enclosing entry
  where `,` adds a root sibling. These fixed counts drive `json_build_live`.
- **Number representation is a pre-existing modulo, left alone.** `splice_number`
  (`kernel/src/api/Operation.jl`) reparses to `Float64`, so multi-digit typed
  numbers render `30.0`/`95.0` (single digits stay `Int`). Making it parse integral
  input as `Int` is a correct but out-of-scope core-primitive change with
  cross-domain risk; `json_build_live` matches `make_json_document_example()` modulo
  this. Noted as a possible separate follow-up.
- **No `Json.jl` changes.** The audit in the Files section held: the JSON gesture
  helpers were already correct for any focused object/array; the fix was purely the
  recursive routing + lift at the template layer.
