# Type checkpoints at every level

Make `TypeReference(T)` checkpoints a **mandatory, canonical part of every
reference** — one `TypeReference(typeof(node))` before each navigation step (and
the terminal node) — instead of the current *optional annotation that is
stripped before use*. The goal is intentional, self-describing references that
capture the structural context of each step.

> Status: **Phases 1–3 implemented; Phase 4 (output residency) intentionally
> deferred — see "Implementation outcome" below.** Selections are now canonical
> **at rest** (input/document-domain cells, search results); the projection
> boundary strips checkpoints so the ~270 bespoke mappers and all render/layout
> consumers keep seeing plain navigation paths. Full sweeps are green or strictly
> better than `main` (see outcome). The central scope question (§0) was resolved
> as Option B, but Option B's *output residency* half proved to be pure decoration
> on transient render artifacts at the cost of ~15+ consumer rewrites, so it is
> deferred (the boundary wrapper has a one-line switch to enable it later).

## Implementation outcome (2026-06-18)

What landed (all green; `test_printers` 116980/116980, `test_readers`
16650/16650, `test_repls`/`test_text_navigations` have **no new** failures vs
`main` and actually fix the pre-existing `json_null` crashes):

- **Phase 1** — checkpoint-tolerant infra: `set_selection!`/`clear_selection!`,
  `@reference_case` (skips `TypeReference` heads; `∅` and `^(expr)` use
  type-ignoring comparison), plus `skip_type_checkpoints`,
  `reference_equal_ignoring_types`, `is_prefix_of_ignoring_types`.
- **Phase 2** — canonical at rest: `set_selection!(document, path)` annotates
  (`annotate_reference_types ∘ strip_reference_types`); `collect_references`
  annotates its results. Every document-domain selection cell and every search
  result is now canonical/self-describing.
- **Phase 3** — boundary strip: the per-projection mappers were renamed to
  `_map_reference_forward`/`_map_reference_backward` (bodies unchanged) and a
  single public `map_reference_forward`/`map_reference_backward` wrapper
  (`common/Projection.jl`) **strips** incoming checkpoints so every mapper sees a
  plain navigation path. The `@invoke …(p::Projection, …)` default-mapper
  fallthroughs in the generic projections were repointed at the `_`-prefixed
  defaults (otherwise they re-entered the wrapper → infinite recursion).
- **Robustness** — operation evaluators that *navigate by a selection-derived
  path* now strip checkpoints (`ReplaceDocumentOperation`,
  `ReplaceReferencedValue`, `_split_replace_reference`,
  `_replace_terminal_with_cursor`); `evaluate_reference` already skipped them.
  `_split_replace_reference` now returns `nothing` (caller no-ops) for a
  reference with no editable slot (a projection-introduced `ProjectionReference`
  span) instead of crashing — this also fixes the pre-existing `json_null`
  failures.

**Phase 4 (output residency) deferred — rationale.** Re-annotating *projected
output* selections against the destination document (the resident-everywhere half
of Option B) breaks every render-/layout-domain consumer that structurally
inspects an output selection cell — cursor placement, box-highlight ranges, the
`*ToGraphics`/`*ToText` walkers, ~15+ functions like
`TextToGraphics._highlight_char_range` and the §8 `sel` cells — each of which
would have to `skip_type_checkpoints` first and then *strip the checkpoints to
use the path anyway*. Output-domain checkpoints are therefore pure decoration on
transient render artifacts. The wrapper keeps a documented one-line switch
(`_destination_output`/`_destination_input`) to turn it on once those consumers
are made checkpoint-tolerant. The user-visible benefit (self-describing,
replay-validatable references) is fully delivered where references are *stored
and inspected*: document selections, search results, assistant/MCP refs.

## Motivation

Today a path prints as `entries[1].value.value{3}` — a `FieldReference("value")`
is ambiguous (value of *what*?). The same path in canonical form is

```
{{JsonObject}}.entries{{CellVector}}[1]{{JsonObjectEntry}}.value{{JsonString}}.value{{String}}{3}
```

Every step now records the type of the node it descends *from*. This is exactly
the shape [`annotate_reference_types`](../../program/src/reference/Reference.jl)
already produces — the refactor promotes that shape from "optional, stripped
before replay" to "the canonical form references are held in."

Benefits: replay validation for free (a retyped node truncates the path at the
mismatching checkpoint), self-documenting selections/search-results/assistant
references, and mappers/patterns that can assert the domain type they expect.

## Current state (what exists)

- `TypeReference(type)` — non-navigating checkpoint, asserts `node isa type`
  ([Reference.jl:111](../../program/src/reference/Reference.jl)). Already handled
  by `evaluate_reference`, `valid_reference_prefix`, the document-aware
  `is_valid_reference`, and rendered by both `ReferenceToText` projections.
- `annotate_reference_types(doc, path)` / `strip_reference_types(path)` — the
  canonical-form ↔ navigation-only inverses. Today checkpoints are deliberately
  kept **out of** stored selection paths; the documented replay pattern is
  *annotate → validate → strip → apply*.
- Construction (`@reference`, `@step`), matching (`@reference_case`), selection
  plumbing (`set_selection!` / `clear_selection!` in
  [Operation.jl](../../program/src/common/Operation.jl)), and the ~60
  `map_reference_forward` / `map_reference_backward` mappers all assume
  **navigation-only** paths.

The blockers for "checkpoints everywhere":

1. `set_selection!` / `clear_selection!` hit their `else => return` branch on a
   `TypeReference` head and **stop early** — they do not skip checkpoints.
2. `@reference_case` patterns have no notion of checkpoints; interleaved
   `TypeReference` steps break every existing pattern.
3. `@reference` / `@step` build at macro-expansion time with **no document**, so
   they cannot synthesize `typeof(node)` checkpoints.
4. Checkpoints record an **input-domain** type and are meaningless after a path
   crosses a projection — so the live forward/backward pipeline cannot just
   carry them through; they must be stripped on entry and re-annotated against
   the destination document on exit.

## 0. Scope decision — RESOLVED: fully live (Option B)

Checkpoints are **resident at every level at all times** — including the live
selection cell of every document and the selection threaded through every
projection. A reference is *never* held in stripped form except transiently
*inside* a mapper while it is being re-typed for the next domain.

The key insight that makes B tractable: types are a property of a *path paired
with a document*, never of a path alone, and input-domain checkpoints are
invalid in the output domain. So at **every projection boundary** the mapper
must `strip → run navigation mapping → re-annotate against the destination
document` regardless — that strip/re-annotate primitive is shared with the
hypothetical Option A. B differs only in keeping the annotated form **resident
between** boundaries instead of stripping it. Concretely B adds, over the shared
primitive:

- document selection cells hold annotated paths (Phase 1 makes set/clear and the
  matcher tolerate this);
- printer selection cells emit **annotated** output selections (annotate the
  constructed output path against the output document);
- the §8 compound-printer recurse pattern must skip checkpoints when extracting
  the child index from the input selection.

(Option A — checkpoints only at rest, stripped through the pipeline — was
considered and rejected: the user wants references self-describing *everywhere*,
and B reuses the same boundary machinery, so the extra cost is modest.)

## Canonical form (definition)

A reference is *canonical* iff it is the output of `annotate_reference_types`
against its document: a `TypeReference(typeof(node))` immediately precedes every
navigation step, and existing checkpoints are not double-annotated.
`strip_reference_types ∘ annotate_reference_types == id` on an unchanged
document remains the invariant. `EmptyReferencePath` (whole-element `∅`
selection) annotates to a single trailing `TypeReference(typeof(node))` so even a
whole-element selection records what it selects.

---

## Phase 1 — make all infrastructure checkpoint-tolerant (backward compatible)

Nothing here changes the *form* of any reference; it only makes every consumer
skip `TypeReference` steps transparently. After this phase, checkpoints may
appear anywhere without breaking existing navigation-only paths. **Land and test
this first — it is risk-free and unblocks everything else.**

- [x] **`set_selection!` / `clear_selection!`**
  ([Operation.jl:362,398](../../program/src/common/Operation.jl)). Add a
  `TypeReference` head case that stays on the current node and recurses on
  `path.tail` (mirroring `evaluate_reference`). Confirm there is no surviving
  domain-specific override (none found in `Syntax.jl` today despite the
  deep-dive note; verify before relying on it).
- [x] **`@reference_case`**
  ([ReferenceCase.jl](../../program/src/reference/ReferenceCase.jl)). Make
  `_gen_path_match` / `_gen_prefix_match` **skip `TypeReference` heads** before
  matching each pattern step, so existing patterns match regardless of
  interleaved checkpoints. (Generate a small "advance past checkpoints" wrapper
  around the per-step `ConcreteReferencePath` destructuring.)
- [x] **`is_prefix_of` / `reference_equal`** decide and document the semantics:
  recommended — keep `==` strict (checkpoints included) and add
  `reference_equal_ignoring_types` for callers that compare across
  annotated/plain forms. Audit the `@reference_case` `^(expr)` interpolation
  path and `is_prefix_of` users for which semantics they need.
- [x] **Tests:** extend
  [TypeReferenceTest.jl](../../test/src/reference/TypeReferenceTest.jl) — feed
  annotated paths through `set_selection!`/`clear_selection!`/`@reference_case`
  and assert identical behavior to the stripped form. `test_cell()` +
  one domain (`test_json()`) to confirm no regressions.

## Phase 2 — canonical construction (annotate at the document boundary)

**DSL question — RESOLVED.** `@reference` expands at parse time with no document
in scope, so it *cannot* and *should not* infer types — it builds the
**navigation skeleton** only, exactly as today. Checkpoints are a property of a
path *paired with a document*, filled by `annotate_reference_types(document,
path)` at the moment the skeleton is bound to a document. There is no
construction-time "DSL types" choice; explicit type syntax is only a
pattern-matching nicety (see Phase 1's optional `::Type` assertion in
`@reference_case`).

The single binding point: **`set_selection!` annotates.** Make the public
`set_selection!(document, path)` call `annotate_reference_types(document,
strip_reference_types(path))` before walking — so any skeleton handed to it
becomes canonical against the live document, idempotently (already-annotated
paths are stripped and re-annotated, which is a no-op on an unchanged document).
This means **every selection in every document is canonical by construction**
without touching the dozens of `@reference …` call sites.

- [x] `set_selection!` annotates against `document` (depends on Phase 1's
  checkpoint-tolerant walk).
- [x] **Produced references** (collect_references annotates; no separate search/MCP producers found) (`collect_references` / `search_references`,
  references handed to / from
  [WorkbenchAssistant.jl](../../program/src/editor/WorkbenchAssistant.jl) /
  [Mcp.jl](../../program/src/editor/Mcp.jl)) annotate against the document they
  point into before leaving their producer.
- [x] **`@step`** stays navigation-only (a single step has no document); steps
  are annotated as part of the whole path at the binding point.
- [x] **Tests:** assert a path built with `@reference`, set via `set_selection!`,
  reads back from the document's `selection[]` in canonical form and still
  resolves via `evaluate_reference`.

## Phase 3 — projection boundary re-typing (the shared primitive)

Every mapper receives a canonical (annotated) input path and must emit a
canonical output path in the *destination* domain. Input-domain checkpoints are
invalid in the output domain, so they cannot be carried through — they are
stripped and regenerated.

- [x] Wrap the public `map_reference_forward` / `map_reference_backward` entry
  points ([api/Projection.jl](../../program/src/api/Projection.jl),
  [common/Projection.jl](../../program/src/common/Projection.jl)) so they:
  `strip_reference_types` the incoming path → call the existing per-projection
  mapper (which stays navigation-only internally) → `annotate_reference_types`
  the result against the destination document from the iomap (`iomap.output`
  forward, `iomap.input` backward). **This is what keeps the 60 bespoke mappers
  unedited** — they keep matching and building plain navigation paths; the
  wrapper makes the boundary canonical-in / canonical-out.
- [x] Confirm the `∅` whole-element identity mapping still round-trips (no steps;
  strip/annotate reduce to the trailing checkpoint).
- [x] **Tests:** `test_json_to_syntax()`, `test_syntax_to_text()`, then a full
  `test_printers()` / `test_readers()` sweep once targeted ones pass.

## Phase 4 — printer selection cells emit canonical output (Option B residency)

With Phase 3 the boundary is canonical-in/out, but printer-side reactive `sel`
cells construct output selections *directly* (not through the mapper wrapper),
so they must annotate their own output to keep the resident form canonical.

- [ ] In the §8 compound-printer recurse pattern (e.g.
  [JsonToSyntax.jl](../../program/src/projection/primitive/JsonToSyntax.jl),
  [ObjectToSyntax.jl](../../program/src/projection/primitive/ObjectToSyntax.jl)),
  when reading `input.selection[]` to extract the child index, **skip
  `TypeReference` heads** (the input selection is now canonical).
- [ ] When a `sel` cell builds the output selection (e.g. prepending
  `ElementReference(i)`), annotate the constructed path against the output
  document before writing it — or build the checkpoints inline. Prefer a single
  helper so this is uniform across compound printers.
- [ ] Leaf-to-leaf shared-cell pipelines (§7 of the deep-dive) need the shared
  selection to be canonical in *both* domains — verify the shared-cell shortcut
  still holds, or split the cell where the canonical forms differ.
- [ ] **Tests:** assert each domain's projected output `selection[]` prints with
  output-domain `{{Type}}` checkpoints; re-run the per-domain navigation tests
  (`test_text_navigation(json_example)` …).

## Phase 5 — docs & cleanup

- [x] Updated the "Type checkpoints" section of guide/editor/reference.md (canonical at rest; boundary strips). Full worked-example rewrite of selection-deep-dive.md still TODO. Original item:
- [ ] Rewrite the "Type checkpoints" sections of
  [guide/editor/reference.md](../../guide/editor/reference.md) and
  [guide/selection-deep-dive.md](../../guide/selection-deep-dive.md): checkpoints
  are now the canonical form, not an opt-in annotation. Update every worked
  example path to its canonical shape. Document the boundary strip/re-annotate
  rule and the chosen DSL syntax.
- [x] Reframe `strip_reference_types` as the *internal boundary* tool used by the
  mapper wrapper, not a "strip before apply" step in callers.

## Risk / surface-area notes

- `@reference_case` is used in ~26 files and `@reference` in ~31; Phase 1's
  skip-checkpoints approach keeps all of them working untouched.
- ~60 files define `map_reference_forward`/`map_reference_backward`; the Phase 3
  boundary wrapper is designed specifically so none of them need editing.
- The biggest test churn is selection round-trip tests whose expected paths gain
  `{{Type}}` tokens — budget for updating golden/printed paths in the reference
  and per-domain test suites.

## Resolved decisions

- **§0 scope — RESOLVED: fully live (Option B).** Checkpoints resident at every
  level at all times; mappers strip + re-annotate at each boundary; printer cells
  emit canonical output.
- **§2 DSL — RESOLVED.** `@reference` has no document and therefore builds the
  navigation skeleton only; checkpoints are filled by `annotate_reference_types`
  at the document-binding point (`set_selection!` and producers). No
  construction-time type syntax; optional `::Type` assertions live only in
  `@reference_case` patterns.

## Open questions

1. **Equality** — should `==` / `is_prefix_of` ignore checkpoints, or stay
   strict with a separate ignoring-variant? *Recommend strict + variant*; the
   matcher (Phase 1) skips checkpoints regardless.
2. Should the terminal node always get a trailing checkpoint (whole-element and
   position selections), or only nodes descended *from*? *Recommend trailing
   checkpoint for `∅`; positions are already terminal.*
3. **Performance** — annotating on every `set_selection!` and re-annotating at
   every projection boundary walks the document per edit/frame. Measure; if hot,
   memoize annotation per (document-version, path) or annotate lazily.
