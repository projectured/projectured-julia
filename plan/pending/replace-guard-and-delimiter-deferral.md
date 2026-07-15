# Replace guard collapse + delimiter-edit deferral relocation

Two entangled things get untangled:

1. **The domain replace guard** (`_json_replaceable` / `_yaml_replaceable`) drops its
   introduced-caret / scalar special-casing and becomes a pure structural-validity
   check: *replace the named node unless it is an object entry*.
2. **The "you can't edit a projection-introduced fragment" decision** (a delimiter, a
   separator, any output-only text) moves from the syntax→text boundary (where it's too
   high — it disables editing those fragments for a *standalone* syntax document) **down
   to the projection that introduced the fragment**, which is the only layer that knows
   the fragment has no document pre-image. There it defers, and the existing gesture
   fall-through lets the structural replace kick in.

The guard and the routing are independent and land in separate phases. Phase 1 (guard)
is already correct against *today's* routing; Phase 2 (routing) is the real cleanup that
retires the special-case the guard used to need.

## Why the current shape is a smell

- `SyntaxLeafToText` defers **all** delimiter-span edits
  ([SyntaxToText.jl:147-159](../../package/visual/main/syntax/SyntaxToText.jl#L147-L159),
  `_leaf_field_at(...) === :value || return nothing`). Too high: even a bare `SyntaxLeaf`
  document — not projected from anything — then can't have its `"` quotes edited.
- `_json_replaceable` re-declines a scalar on an introduced caret (branch 2 of
  [Json.jl:91-102](../../package/domain/main/json/Json.jl#L91-L102)) while *allowing*
  a container on its bracket. The scalar/container asymmetry exists only to paper over
  the fact that the deferral already happened one layer up. Two wrongs that cancel.

The delimiter is projection-*introduced* (`open=TextString("\"")` in
`JsonStringToSyntaxLeaf`), so the projection that emitted it is what should say "no
document slot maps to this edit" and defer — exactly as the fully-opaque leaves
(`JsonNull`, `JsonInsertion`, `bound_field === nothing`) already do at
[ReaderDefaults.jl:45](../../package/base/main/projection/ReaderDefaults.jl#L45).

## How the fall-through already works (no change needed)

An `Intent` carries **both** the gesture and the operation
([Projection.jl:193-197](../../package/kernel/main/projection/Projection.jl#L193-L197)):

```julia
payload = change.operation === nothing ? change.gesture : change.operation
op = read_intent(p, iomap, payload)
return Intent(change.gesture, op)     # gesture preserved even when op becomes nothing
```

When an inner projection returns `nothing`, `operation` clears, `gesture` survives, and
the next layer inward re-dispatches on the raw `KeyPress` → reaches
`@gestures JsonDocument`. This is the *same* mechanism that already makes
container-bracket replaces fire; Phase 2 just routes scalar delimiters through it too.

---

## Phase 1 — Collapse the replace guard

Independently correct against today's routing (delimiter keys already fall through via
the `SyntaxLeafToText` deferral). The only behavior change: a caret on a **string's
quote** + a replace key now *replaces* instead of no-op'ing — making scalars consistent
with containers (a key on a `[` bracket already replaces).

**JSON** — [Json.jl:91-102](../../package/domain/main/json/Json.jl#L91-L102):

```julia
# Replace the named node — unless it's an object entry, which is retyped through its
# value. Every other "meaningful type-in" is caught a layer up: a keystroke that maps
# to editable text is consumed there and only *falls through* to us when it can't be
# (a projection-introduced delimiter, or a whole-node selection), so any key reaching
# here is a replace command.
function _json_replaceable(doc, sel)
    node = try_evaluate_reference(doc, named_node_reference(sel))
    return node !== nothing && !(node isa JsonObjectEntry)
end
```

`named_node_reference` (introduced → ∅ → `doc`) subsumes both the `sel === nothing` and
`target === nothing` guards. `named_node_reference` and `try_evaluate_reference` are
already in scope (`using ..ProjectionReferenceModule`, `..ReferenceModule`).

**YAML** — mirror line-for-line at
[Yaml.jl:102-113](../../package/domain/main/yaml/Yaml.jl#L102-L113)
(`YamlMappingEntry` in place of `JsonObjectEntry`).

**XML** — leave as-is; `_xml_replaceable` only ever allows replacing an insertion, a
deliberately narrower rule (the insertion is a typed-name buffer).

**Verify Phase 1**
- `test_position_navigation(json_example)`, `test_repl(json_example)`, `test_json()`,
  `test_yaml()`.
- New behavior: navigate onto a string's opening quote, press `[` → array replace.
  Drive by hand in the REPL (`documentation/debugging.md`) since nav tests only assert
  `states > 0`.
- Watch the pass-count deltas (an IoMap field-count change would show here, per the
  "test counts track cell count" note) — expect `Fail`/`Error` to stay at baseline.

**Commit 1:** guard collapse for JSON + YAML.

---

## Phase 2 — Move the delimiter deferral to the projection boundary

Goal: `SyntaxLeaf` owns its delimiters (they become editable in the syntax domain);
the *projection* that introduced a delimiter defers edits to it. The Phase-1 guard is
unchanged — this phase just relocates *why* the key falls through.

### 2a. Syntax→text readers accept edits on *any* span, not just the value

The syntax→text readers stop privileging the value span and instead map an edit on **any**
introduced part — open/close delimiters **and** separators (and any other output-only
fragment) — onto the corresponding `SyntaxLeaf` / `SyntaxNode` / `SyntaxSeparation` field
op. The syntax domain owns all of its own text; whether an edit ultimately *maps* is the
downstream domain projection's call (2b), not this layer's.

- **Leaf** — [SyntaxToText.jl:147-159](../../package/visual/main/syntax/SyntaxToText.jl#L147-L159):
  drop the `_leaf_field_at(...) === :value` gate; map an edit on the `:open` / `:value` /
  `:close` span to the matching `SyntaxLeaf` field op (reuse `_leaf_elem_path` /
  `_leaf_field_at`, which already resolve the span → field).
- **Compound** — the `SyntaxCompoundToText` reader: accept edits on the node's `open` /
  `close` delimiters **and** its `separator`, mapping each to the corresponding
  `SyntaxNode` / `SyntaxSeparation` field op.
- **Separator wrinkle** — a separator renders n−1 times for one `separator` field
  ([Syntax.jl:375-380](../../package/visual/main/syntax/Syntax.jl#L375-L380)): a cursor
  can sit in it (`.separator{k}` → first occurrence) but no single span *is* "the"
  separator. Map an edit on any occurrence onto the one `separator` field (editing the
  shared `TextString`); if that proves ambiguous to invert, fall back to deferring the
  separator edit — which is *also* correct here, since a deferred edit simply falls
  through to the structural gesture (the whole point of Phase 2). Decide during
  implementation and record which we chose.

### 2b. The template op-reader defers edits that land on introduced output

The load-bearing change, and it is **generic** (all `@projection_template` domains
inherit it). Today
[ReaderDefaults.jl:39-52](../../package/base/main/projection/ReaderDefaults.jl#L39-L52)
early-returns `nothing` only for the *fully opaque* leaf (`bound_field === nothing`); a
bound leaf editing a non-value field falls through to `_atomic_backward`, which wraps it
in a `ProjectionReference` ([ProjectionTemplate.jl:867-868](../../package/kernel/main/projection/ProjectionTemplate.jl#L867-L868))
and hands back a bogus `ReplaceStringRangeOperation` targeting introduced output.

Generalize the early return: after `new_ref = map_reference_backward(...)`, if `new_ref`
resolves to **this projection's own introduced output**, return `nothing` (defer):

```julia
new_ref = map_reference_backward(p, iomap, op.reference)
new_ref === nothing && return nothing
is_introduced_reference(strip_reference_types(new_ref)) && return nothing   # NEW
```

> **Do not touch `_atomic_backward`'s ProjectionReference wrap.** That wrap is required
> for *reference/selection* mapping — navigating a caret onto a delimiter must round-trip
> as an introduced reference (which is what makes the Phase-1 `named_node_reference`
> normalize it to ∅). Only the *operation* path defers.

**Detection detail (verify carefully):** `_atomic_backward` builds
`_path(TypeReference(w.intype), ProjectionReference(p, reference))` — head is a
`TypeReference`, not the `ProjectionReference`. Confirm the predicate sees through the
leading type checkpoint (`strip_reference_types` / `fold_reference_types` first, or match
`is_introduced_reference` after folding). This is the one spot most likely to be subtly
wrong.

### 2c. Fall-through

No change — [Projection.jl:193-197](../../package/kernel/main/projection/Projection.jl#L193-L197)
already preserves the gesture across the template's `nothing`.

**Verify Phase 2**
- `test_syntax()` + a standalone syntax-domain edit check (the newly enabled capability):
  editing `.open` on a bare `SyntaxLeaf`, and the `.separator` on a `SyntaxNode` /
  `SyntaxSeparation`, now produces a real edit.
- `test_json_to_syntax()`, `test_syntax_to_text()`, then `test_visual()` + `test_domain()`.
- Re-confirm the Phase-1 quote-caret replace still fires (now via the projection-boundary
  deferral rather than the syntax-boundary one) for JSON **and** YAML.
- Diff a full `test_all` summary against clean `main` (per "wide-refactor → baseline
  diff") — 2b is a shared seam touching every template domain.

**Commit 2:** 2a (syntax readers) + 2b (template deferral), green visual+domain.

---

## Phase 3 (optional) — Retire the entry guard via re-target

The entry check is the last survivor because `replace_document` is a blind slot-write
([Operations.jl:196-217](../../package/kernel/main/operation/Operations.jl#L196-L217)) —
replacing `object.entries[i]` with a bare `JsonNull` would violate the `JsonObject`
invariant. The literal reading of the existing "an entry is retyped through its value"
comment is to **re-target**: when the named node is a `JsonObjectEntry`,
`replace_selected_document` targets `entry.value` instead of `∅`-of-entry. Then typing
`n` on a whole entry yields `"key": null` (useful) instead of declining, the guard
becomes unconditionally `true`, and the structural edit "kicks in" at the value exactly
as the routing philosophy says.

This is a **behavior change** (today it no-ops), so it's a deliberate, separate call —
not bundled with Phases 1–2. If taken, `_json_replaceable` / `_yaml_replaceable`
disappear entirely and the `@gestures` `when(...)` precondition is dropped.

**Verify:** `test_repl(json_example)` over object entries; confirm the cursor lands in
the replaced value.

---

## Risks / notes

- **2b blast radius:** the template op-reader is shared by every `@projection_template`
  domain (JSON, YAML, INI, markdown, …). The deferral must fire *only* for introduced
  output, never for a genuine bound-value edit — hence the "verify the detection" flag.
- **2a and other domains:** enabling `.open`/`.close` edits at the syntax layer must not
  regress domains that assumed the old deferral silently swallowed delimiter keys. The
  full-suite baseline diff covers this.
- Related pending work:
  [left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md)
  (introduced-token navigation) and
  [projection-template-engine.md](projection-template-engine.md) touch the same
  introduced-reference machinery — check for overlap before Phase 2.
- Recommended order: **Phase 1 → Phase 2**, so a bisect can attribute any behavior
  change to the guard vs. the routing separately. Phase 3 only if we want the entry
  behavior changed.
