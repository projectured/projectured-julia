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

## ⚠️ Corrected mechanism (discovered during implementation — supersedes the framing below)

The premise "defer the edit and the structural replace kicks in" is **wrong for delimiter
and separator carets.** Verified empirically (before/after runtime probe over `json_example`):
**typing on a delimiter or separator caret does nothing** — the same, before and after every
change here.

Why — the `ChainingProjection` reader runs **last-to-first**
([Chaining.jl:144-158](../../package/base/main/projection/higherorder/Chaining.jl#L144-L158)):
it finds the *outermost* stage that turns the key into an op, then translates that op
*inward*. A caret that sits **on a text span** (value, quote, bracket, separator) makes the
text layer emit a character-edit op; that op either **applies** (value) or **dies** when an
inner stage can't map it (delimiter/separator) — and a died op yields `nothing`. The reader
does **not** re-offer the raw key after an op dies. The type-to-replace gesture fires **only**
on a **whole-element (∅) selection**, where the text layer has no character to edit, declines,
and the raw key reaches the domain untouched.

Consequences:
- **`_json_replaceable` is only ever consulted for ∅ selections** (and other non-text-caret
  selections). For those, the old and new guard are **identical** (`!(node isa entry)`). The
  introduced-caret branch — old *or* new — is **never reached by a keystroke**, because an
  introduced caret is a text span whose edit dies before reaching the domain gesture. So
  **Phase 1 is a true no-op refactor** (a genuine simplification, but zero behavior change,
  not the "quote-caret now replaces" story told below).
- **Phase 2 (leaf + separator)** is likewise **behavior-preserving for domain documents**
  (a delimiter/separator edit went from dying at the syntax stage to dying at the domain
  stage — same `nothing`). Its one real effect: the syntax→text projection now emits proper
  `.open`/`.close`/`.separator` edit ops, which a **standalone syntax document applies** and a
  **domain projection defers**. The deliverable is "the syntax domain owns its own text
  editing," realized as a clean refactor — not a domain-doc behavior change.

The sections below preserve the original (partly mistaken) framing for history; read them
through this correction.

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

## Phase 1 — Collapse the replace guard — ✅ Done

Independently correct against today's routing. The guard *logic* now returns `true` for
an introduced caret on a scalar (was `false`); everything else is unchanged. See the
**Result** below — the triggering caret turns out to be unreachable via arrow navigation
today, so this lands as a behavior-preserving simplification with a latent consistency
benefit, not an observable behavior change.

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

**Result (implemented)**
- Loads clean; targeted tests green with no regression: `test_json()` 24/24,
  `test_repl(json_example)` 225/225, `test_repl(yaml_example)` 225/225, no `Fail`/`Error`.
  (There is **no** `test_yaml()` suite — YAML is only exercised via `test_repl` and the
  shared drivers.)
- **Guard-logic delta confirmed** by direct unit call:
  `_json_replaceable(JsonString(""), <introduced ref>)` → `true` (was `false`);
  `_json_replaceable(JsonObjectEntry("k", …), ∅)` → `false`;
  `_json_replaceable(JsonString(""), nothing)` → `false`.
- **Reachability finding (important).** Enumerating `explore_position_selections` over
  `json_example`: 532 reachable carets, 315 introduced — but **all 315 name the root
  container**, and **zero name a scalar**. A string's quote is *not* an arrow-navigable
  stop; navigating into a string lands on its editable content (a concrete, non-introduced
  reference the text layer owns). So the one selection on which the old and new guard
  disagree is **unreachable via keyboard navigation** — Phase 1 is behavior-preserving
  under nav, which is why the pass counts are identical.
- Consequence: the scalar/container consistency win is **latent**. It only becomes
  observable once an introduced caret can land on a scalar's own token — via a mouse
  click on the quote glyph (untested here; may already produce such a selection) or via
  the separate introduced-text navigation work
  ([left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md)).
  This corrects the earlier "quote-caret now replaces" framing: it's reachable by click
  at most, not by arrow keys.

**Commit 1:** guard collapse for JSON + YAML (+ this result note).

---

## Phase 2 — Move the delimiter deferral to the projection boundary — ✅ Done (leaf delimiters + separators)

Goal: `SyntaxLeaf` owns its delimiters (they become editable in the syntax domain);
the *projection* that introduced a delimiter defers edits to it. The Phase-1 guard is
unchanged — this phase just relocates *why* the key falls through.

**Shipped:** 2a-leaf (leaf reader accepts open/value/close edits) + 2b (template op-reader
defers introduced-output edits, via the full-path `_targets_introduced_output` walk) +
2d (compound reader maps a separator-span edit onto the shared `.separator` field —
edit-side only; selection stays per-occurrence chrome).
**Not shipped:** compound *delimiters* (verified already-handled, no change needed).

### Findings from the code (2026-07-15, during implementation)

Reading the full `SyntaxToText` reader refined the scope:

- **Leaf** — the *selection* mapper already resolves `.open`/`.close`
  ([SyntaxToText.jl:109-111](../../package/visual/main/syntax/SyntaxToText.jl#L109-L111));
  only the *edit* reader gates on `:value`
  ([:151](../../package/visual/main/syntax/SyntaxToText.jl#L151)). Removing that gate is
  the clean, in-scope change (2a-leaf).
- **Compound delimiters** — a bracket caret is a *concrete* `.open`/`.close` reference
  (recorded in `own_spans`, mapped by `_backward_zone`
  [:449-450](../../package/visual/main/syntax/SyntaxToText.jl#L449-L450)), and the edit
  reader's zero-width disambiguation branch
  ([:882-888](../../package/visual/main/syntax/SyntaxToText.jl#L882-L888)) already emits a
  `.open{c}`/`.close{c}` op for an edit there; the node template then defers any
  non-`.children` field edit. So compound bracket edits appear to **already** route to a
  structural replace — treat 2a as *verify*, not *change*, for compounds.
- **Separators — deliberate design conflict → RESOLVED (user chose: make them editable).**
  Separators were intentionally **not** backward-addressable: `_push_separator!`
  ([:581-593](../../package/visual/main/syntax/SyntaxToText.jl#L581-L593)) keeps them out of
  `own_spans`, and `_backward_zone`
  ([:452-454](../../package/visual/main/syntax/SyntaxToText.jl#L452-L454)) maps a separator
  caret to a projection-introduced position. Rationale: one `separator` field renders n−1
  spans, so an edit on one occurrence rewrites *all* of them, and a click on one forward-maps
  the caret to the *first*. The user chose to make separators editable, so **2d** (below)
  reverses this on the **edit side only**: a separator-span *edit* maps to the shared
  `.separator` field, while a separator *selection* stays per-occurrence introduced chrome
  (the split the user accepted). For a domain-projected node the `.separator` edit is deferred
  downstream (same as any introduced output), so JSON/YAML are unaffected; a standalone syntax
  document edits its separator in place.

### 2a. Leaf → text reader accepts open/close edits (in scope)

[SyntaxToText.jl:147-159](../../package/visual/main/syntax/SyntaxToText.jl#L147-L159):
drop the `_leaf_field_at(...) === :value` gate; map an edit on **any** present leaf span
(`:open` / `:value` / `:close`) to that field's `SyntaxLeaf` op (`String(field)` into the
existing `ConcreteReferencePath(SyntaxLeaf, FieldReference(...), …)` shape). Value edits
are unchanged; open/close now produce `.open`/`.close` ops that 2b defers downstream.
Compound delimiters: **verify** they already route to replace (above); do not change the
compound reader for delimiters. Separators: see 2d.

### 2d. Compound reader maps a separator edit onto the shared `.separator` field

[SyntaxToText.jl](../../package/visual/main/syntax/SyntaxToText.jl) `read_intent(::SyntaxCompoundToText,
…, ::ReplaceStringRangeOperation)`: after the child-zone loop, if `span_idx ∈ iomap.sep_indices[]`,
build `.<separator-field>[char_start:char_stop]` from `syntax_separator(node).first` and return it.
Edit-side only — `_backward_zone` (selection) is untouched, so a separator *caret* stays
per-occurrence introduced chrome while an *edit* collapses onto the one field.

**Result (implemented + verified):**
- Regression-free: before/after runtime probe over `json_example` is byte-identical at every
  reachable separator caret (both `nothing`); `test_visual` 49384/0/0/1, `test_domain`
  113400/0/0/8, `test_typein` json+yaml 160/160 all unchanged. (`test_typein` only types into
  *value* spans, so it never exercises separators — hence the probe.)
- New capability confirmed on a **standalone** `SyntaxSeparation("a", "b"; separator=", ")`:
  the separator-span edit returns `::SyntaxSeparation.separator::TextString[1]::Position`
  (was `nothing` on HEAD), and applying it changes the separator content `", " → "X "`.
- For a domain-projected node the `.separator` op is deferred by the domain reader (`_node_backward`
  returns `nothing` for a non-`children` field), so JSON/YAML are unaffected.

### 2b. The template op-reader defers edits that land on introduced output

The load-bearing change, and it is **generic** (all `@projection_template` domains
inherit it). Today
[ReaderDefaults.jl:39-52](../../package/base/main/projection/ReaderDefaults.jl#L39-L52)
early-returns `nothing` only for the *fully opaque* leaf (`bound_field === nothing`); a
bound leaf editing a non-value field falls through to `_atomic_backward`, which wraps it
in a `ProjectionReference` ([ProjectionTemplate.jl:867-868](../../package/kernel/main/projection/ProjectionTemplate.jl#L867-L868))
and hands back a bogus `ReplaceStringRangeOperation` targeting introduced output.

Generalize the early return: after `new_ref = map_reference_backward(...)`, if `new_ref`
passes through **projection-introduced output**, return `nothing` (defer):

```julia
new_ref = map_reference_backward(p, iomap, op.reference)
new_ref === nothing && return nothing
_targets_introduced_output(new_ref) && return nothing   # NEW

# Does the reference pass through any projection-introduced output? A ProjectionReference
# step ANYWHERE means part of the path has no document pre-image, so an edit targeting it
# cannot be applied. Head-only `is_introduced_reference` is NOT enough: a scalar nested in
# a container maps to `.elements[i] → ProjectionReference(.open)` — introduced below head.
_targets_introduced_output(p::ConcreteReferencePath) =
    p.head isa ProjectionReference || _targets_introduced_output(p.tail)
_targets_introduced_output(::Any) = false
```

**Implementation note (done):** the plan first sketched a head-only
`is_introduced_reference(strip_reference_types(new_ref))`; reading the node backward mapper
showed that's wrong for a scalar *nested* in a container — `_node_backward` prepends
`.elements[i]` ahead of the child's `ProjectionReference`, so the introduced step is not at
the head. The full-path walk above is what shipped. (The walk transparently steps through
`TypeReference` checkpoints, so it works on both folded and unfolded paths — no
`strip_reference_types` needed.)

> **Do not touch `_atomic_backward`'s ProjectionReference wrap.** That wrap is required
> for *reference/selection* mapping — navigating a caret onto a delimiter must round-trip
> as an introduced reference (which is what makes the Phase-1 `named_node_reference`
> normalize it to ∅). Only the *operation* path defers.

**Detection detail (resolved):** the concern was that `_atomic_backward` builds
`_path(TypeReference(w.intype), ProjectionReference(p, reference))` with a `TypeReference`
ahead of the `ProjectionReference`. The recursive walk steps *through* the `TypeReference`
(it is not a `ProjectionReference`, so the walk recurses into the tail), so no explicit
`strip_reference_types` is needed — confirmed by the unit check (case 1 = introduced at
head, true).

### 2c. Fall-through

No change — [Projection.jl:193-197](../../package/kernel/main/projection/Projection.jl#L193-L197)
already preserves the gesture across the template's `nothing`.

**Result (implemented + verified)**
- Regression-free across the shared seam: `test_visual()` 49384 pass / **0 Fail / 0
  Error** / 1 broken; `test_domain()` 113400 pass / **0 Fail / 0 Error** / 8 broken;
  `test_repl(json_example)` & `(yaml_example)` 225/225; `test_typein(json_example)` &
  `(yaml_example)` 160/160. Broken counts unchanged from baseline; the domain `@warn`/
  `@error` *log* lines are pre-existing intentional error-path tests (no testset Fail).
- The `test_typein` drivers type a character at **every** caret — the sharpest
  edit-routing coverage — and stay green, so 2b's deferral did not disturb any reachable
  edit across the template domains.
- **New-path confirmation (tests can't reach it — leaf quotes aren't nav stops):**
  - `_targets_introduced_output` unit check — introduced-at-head → `true`,
    introduced-below-`.elements[i]` → `true` (the nested case a head-only check misses),
    a `.value` edit → `false`, `∅` → `false`. All match.
  - Drove the **real** `JsonStringToSyntaxLeaf` template op-reader: a `.open`-span
    `ReplaceStringRangeOperation` returns `nothing` (deferred); a `.value`-span one
    returns a real `ReplaceStringRangeOperation`. Exactly the intended behavior.

**Commit 2:** 2a-leaf (`SyntaxToText.jl`) + 2b (`ReaderDefaults.jl`) + this result note.
**Commit 3:** 2d separator edits (`SyntaxToText.jl`) + this result note.

**Still not touched:** the optional compound-*delimiter* verification (appears
already-correct; not re-touched).

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
