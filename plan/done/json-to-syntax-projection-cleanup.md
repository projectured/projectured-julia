# Align `JsonToSyntax` primitive projections with the projection contract

## Context

A review of [program/src/projection/primitive/JsonToSyntax.jl](../../program/src/projection/primitive/JsonToSyntax.jl)
against the API docstrings in
[program/src/api/Projection.jl](../../program/src/api/Projection.jl) and the
guides ([projection-system.md](../../guide/projection-system.md),
[selection-deep-dive.md](../../guide/selection-deep-dive.md),
[editor/reference.md](../../guide/editor/reference.md)) found the projections
are **functionally correct** — selections round-trip and editing works — but
several spots diverge from the contract those docs lay out. The recurring
theme is the documented principle:

> **`projection_print` uses `map_reference_forward`; `projection_read` uses
> `map_reference_backward`.** The two mappers are the single source of truth
> for how a path crosses the projection.

Today the path-mapping logic is in several cases duplicated across a custom
`projection_read`, a hand-written check, and/or an inline selection cell, so
the "single source of truth" is split and the two directions can drift. None
of this is a live bug; it is debt that makes the file harder to keep correct
as the pipeline evolves. The default fallbacks these items lean on are in
[program/src/common/Projection.jl](../../program/src/common/Projection.jl#L41-L75):
default `map_reference_forward` strips a `proj(p, inner)` wrapper, default
`map_reference_backward` wraps in `proj(p, …)`, and default `projection_read`
handles `ReplaceSelectionOperation` by calling `map_reference_backward`.

Items are ordered by value/risk: 1, 2, and 4 are low-risk, behavior-preserving
de-duplication; 3 and 5 are larger because they touch the School-A/School-B
split (see [projection-system.md § Mapping references when the printer
recurses](../../guide/projection-system.md)); 6–8 are minor.

## 1. Delete redundant `ReplaceSelectionOperation` readers on `JsonBool` / `JsonNumber`

[JsonToSyntax.jl:88-94](../../program/src/projection/primitive/JsonToSyntax.jl#L88-L94)
(`JsonBoolToSyntaxLeaf`) and
[JsonToSyntax.jl:124-130](../../program/src/projection/primitive/JsonToSyntax.jl#L124-L130)
(`JsonNumberToSyntaxLeaf`) define a `projection_read(::, ::, ::ReplaceSelectionOperation)`
that checks `path.head` is `FieldReference("value")` and returns `op`
unchanged.

The default reader
([common/Projection.jl:67-75](../../program/src/common/Projection.jl#L67-L75))
already does exactly this by calling each projection's own
`map_reference_backward`, which is defined identically as `value{k} => value{k}`
at [lines 74-78](../../program/src/projection/primitive/JsonToSyntax.jl#L74-L78)
and [110-114](../../program/src/projection/primitive/JsonToSyntax.jl#L110-L114).
The `projection_read` docstring is explicit: *"a projection that only moves the
cursor needs **no** `projection_read` method."*

**Fix:** delete both `ReplaceSelectionOperation` methods; rely on the default
reader + the existing `value{k}` mapper. Confirm selection round-trips for
booleans and numbers still pass (`test_selections`).

## 2. Move `JsonString` delimiter handling into `map_reference_backward`

`map_reference_backward` for `JsonString` only handles `value{k}`
([JsonToSyntax.jl:170-174](../../program/src/projection/primitive/JsonToSyntax.jl#L170-L174)),
but the open/close-quote → `ProjectionReference` wrapping lives in the custom
`projection_read`
([JsonToSyntax.jl:191-201](../../program/src/projection/primitive/JsonToSyntax.jl#L191-L201)).
So the mapper is incomplete and the reader disagrees with it about what an
`.open`/`.close` output reference maps to — exactly the asymmetry the
`map_reference_backward` docstring's *"Positions with no input pre-image"*
section says the mapper should own.

**Fix:**
- Extend `map_reference_backward(::JsonStringToSyntaxLeaf, …)` so a `.value`
  path passes through as today, and an `.open`/`.close` path returns
  `ConcreteReferencePath(ProjectionReference(p, path))` (the body currently at
  [line 199](../../program/src/projection/primitive/JsonToSyntax.jl#L199)).
- Delete the custom `projection_read(::, ::, ::ReplaceSelectionOperation)`
  ([lines 191-201](../../program/src/projection/primitive/JsonToSyntax.jl#L191-L201))
  so the default reader drives it.
- Keep the `StringReplaceRangeOperation` reader (it is the edit path, not the
  selection path) — but see item 7.
- Verify clicking a string's value vs. its surrounding quotes still lands the
  cursor in the right place via the full pipeline.

## 3. Wire `JsonArrayToSyntaxNode`'s output selection through `map_reference_forward`

The selection cell at
[JsonToSyntax.jl:248-261](../../program/src/projection/primitive/JsonToSyntax.jl#L248-L261)
computes the output selection inline by reading
`child_iomaps[i].output.selection` (School A), while `map_reference_forward`
delegates to `_forward_json_path` (School B,
[line 227](../../program/src/projection/primitive/JsonToSyntax.jl#L227)). The
canonical wiring (print docstring step 3; [projection-system.md "Wiring the
selection"](../../guide/projection-system.md)) is

```julia
sel = Cell(() -> map_reference_forward(p, iomap_cell[], j.selection))
```

with the deferred-iomap trick (`iomap_cell = Cell(nothing)`; assign after
building the `ChildrenIoMap`) — one definition reused on both sides.

They are not equivalent today: the selection cell special-cases
`path.head isa ProjectionReference` and passes it through
([line 250](../../program/src/projection/primitive/JsonToSyntax.jl#L250)),
but `_forward_json_path(::JsonArray, …)`
([lines 499-509](../../program/src/projection/primitive/JsonToSyntax.jl#L499-L509))
only matches `elements{s:e}` and returns `nothing` for a proj-wrapped path. So
unifying requires **adding the proj passthrough to `_forward_json_path`**
first, then switching the selection cell to call `map_reference_forward`.

**Fix:**
- Add a `proj`-passthrough case to `_forward_json_path` (return the path
  unchanged when its head is a `ProjectionReference` for this projection), so it
  matches what the selection cell does today.
- Replace the inline selection cell body with
  `map_reference_forward(p, iomap_cell[], j.selection)` using the deferred
  iomap.
- This deletes the School-A walk in the selection cell and makes School B the
  single forward definition. Verify array element selection and structural
  (bracket/comma) cursor positions still round-trip.

## 4. Stop constructing a `ChildrenIoMap` with null children on `JsonObject`

[JsonToSyntax.jl:365](../../program/src/projection/primitive/JsonToSyntax.jl#L365)
builds `ChildrenIoMap(p, j, node, Cell(nothing))`. The whole point of
`ChildrenIoMap` ([projection-system.md § compound step 4 and the IoMap
table](../../guide/projection-system.md)) is to carry the per-child IO maps so
the reader and mappers can recurse in lockstep — here it is `nothing` because
the mappers use School B (`_forward_json_path` / `_translate_json_path`) and
never consult it. The result is effectively a `SimpleIoMap` mislabeled as a
`ChildrenIoMap`, and it is asymmetric with `JsonArray`, which *does* store
`child_iomaps` ([line 270](../../program/src/projection/primitive/JsonToSyntax.jl#L270)).

**Fix (pick one):**
- **Minimal/honest:** if the object projection genuinely maps everything via
  School B, return a `SimpleIoMap` (or a small bespoke iomap) instead of a
  `ChildrenIoMap` with a null field, so the type reflects what is stored.
- **Consistent:** store the real per-entry / per-value child IO maps (mirroring
  `JsonArray`) and let the mappers delegate through them. This is the larger
  change and only worth it if item 3's direction (canonical wiring) is also
  applied to the object so both nodes use the same school.

Decide alongside item 3 so array and object stay symmetric.

## 5. Prefer the fine-grained `ProjectionReference` form for structural positions

Both node readers fall back to a flat character offset
`ProjectionReference(p, {flat})` via `_syntax_to_flat` —
[JsonToSyntax.jl:278](../../program/src/projection/primitive/JsonToSyntax.jl#L278)
(array) and
[JsonToSyntax.jl:373](../../program/src/projection/primitive/JsonToSyntax.jl#L373)
(object). The `map_reference_backward` docstring and
[projection-system.md](../../guide/projection-system.md) both flag this as the
*"coarser shortcut … prefer the fine-grained form when the structure is
available."*

**Fix (optional, larger):** map a structural output position to
`matched_input_prefix + ProjectionReference(p, unmatched_output_suffix)` so a
cursor on `[`, `]`, `,`, `{`, `}`, `:` round-trips with structural fidelity
instead of collapsing to a single integer offset. Lowest priority; only worth
doing if a feature needs to address those positions individually.

## 6. Unify the leaf projections' selection strategy

The five leaf projections use three different approaches:

- `JsonNull` / `JsonInsertion`
  ([42-45](../../program/src/projection/primitive/JsonToSyntax.jl#L42-L45),
  [55-58](../../program/src/projection/primitive/JsonToSyntax.jl#L55-L58)): no
  custom mappers, wire forward via the **default** `map_reference_forward`, rely
  entirely on default proj-wrapping backward.
- `JsonBool` / `JsonNumber` / `JsonString`: custom identity mappers + the
  shared-cell shortcut in `projection_print` + (currently) custom readers.

For leaves with empty open/close and a single value span this is more variation
than warranted. After items 1–2, converge them: define the `value{k}` mappers,
use the shared-cell shortcut where the leaf-to-leaf formats are identical
(selection-deep-dive §7), and let the default reader handle selection. Decide
whether `JsonNull` / `JsonInsertion` should also carry explicit `value{k}`
mappers for consistency (they render `"null"` / `"insert JSON here"`, which are
not user-editable, so the default proj-wrapping may be acceptable — document the
choice either way).

Sub-note: `JsonNull` / `JsonInsertion` call
`map_reference_forward(p, nothing, j.selection)` passing `iomap = nothing`
([lines 43](../../program/src/projection/primitive/JsonToSyntax.jl#L43),
[56](../../program/src/projection/primitive/JsonToSyntax.jl#L56)). Harmless for
the current mappers (they ignore it) but a latent trap if a mapper ever inspects
the iomap; the canonical call threads the real iomap.

## 7. (Minor) Re-target edit operations via `map_reference_backward`

The `StringReplaceRangeOperation` / `NumberReplaceRangeOperation` readers on
`JsonNumber`
([134-140](../../program/src/projection/primitive/JsonToSyntax.jl#L134-L140))
and `JsonString`
([207-213](../../program/src/projection/primitive/JsonToSyntax.jl#L207-L213))
re-target by manually checking `path.head` is `FieldReference("value")`. The
reader docstring's *"Re-target the references"* recipe says to rewrite the
`.reference` with `map_reference_backward`. It is identity here so behavior is
unchanged, but routing through the mapper keeps the single source of truth. The
retype `StringReplaceRangeOperation` → `NumberReplaceRangeOperation`
([line 139](../../program/src/projection/primitive/JsonToSyntax.jl#L139)) is the
documented "convert to a different operation" move and is correct — keep it.

## 8. (Minor) Decide the fate of the dead `NumberReplaceRangeOperation` reader

[JsonToSyntax.jl:144-150](../../program/src/projection/primitive/JsonToSyntax.jl#L144-L150)
is admittedly never produced upstream (its own comment: *"no upstream produces
one today"*). Either keep it with a clear rationale or delete it; right now it
is untested surface area.

## Documentation fix noticed in passing (not code)

[selection-deep-dive.md §9](../../guide/selection-deep-dive.md) lists
`JsonString → {k}`, but the code,
[json.md](../../guide/document/json.md),
[reference.md](../../guide/editor/reference.md), and
[Json.jl:19](../../program/src/document/Json.jl#L19) all use `.value{k}` for
JSON primitives. Update the deep-dive table's JSON-primitive rows to `.value{k}`
so the guides agree.

## Verification

1. **Build/load:** `julia --project=program -e 'using Projectured'` — no errors.
2. **Selection round-trips:** `julia --project=program -e 'using Projectured; Projectured.test_selections()'`
   — the primary safety net for items 1–6; must stay green.
3. **Readers / printers:** `Projectured.test_readers()` and
   `Projectured.test_printers()` (see [guide/testing.md](../../guide/testing.md)).
4. **REPL sanity:** `Projectured.test_repls()`, plus an interactive check
   (`run_example` / `print_example`, see
   [guide/debugging.md](../../guide/debugging.md)) of clicking a string value,
   a string quote, an array element, an object key, an object value, and a
   structural delimiter — confirm the cursor lands where it did before.
5. **Full suite:** `julia --project=program -e 'using Projectured; Projectured.test_all()'`.
