# Split the reference layer into cohesive fragments

Break `package/kernel/main/reference/Reference.jl` (817 lines, three unrelated jobs) into
five fragments of one job each, and give the reference layer the `Interface.jl` that every
other kernel layer has.

**This is pure code motion. No behavior change, no API change, no exported name added or
removed.** Every line lands in a new file unchanged apart from the section banners and the
file-header docstrings.

## Why

1. **The kernel's own step types are the only step types in the repo that aren't packaged as
   a unit.** Every out-of-layer step type gets one self-contained file holding its struct,
   `show`, `==`, `step_kind`, `evaluate_step`, and DSL registrations —
   [PointReference.jl](../../package/visual/main/graphics/PointReference.jl) (70 lines) is
   the model, and `TextRectangularReference.jl` / `ProjectionReference.jl` follow it.
   Meanwhile `RangeReference` / `FieldReference` / `TypeReference` are smeared across four
   non-adjacent sections of `Reference.jl` — structs at 8–127, `show` at 242–258, `==` at
   283–286, `step_kind`/`evaluate_step` at 441–461 — with 250 lines of path machinery
   interleaved. To understand `RangeReference` you visit four places.

2. **The reference layer is the only kernel layer with no `Interface.jl`.** `document/`,
   `selection/`, and `operation/` each open with one. The reference layer's extension seam —
   `step_kind` / `evaluate_step` / the three `dsl_*` generics, implemented by three
   out-of-layer step types — is buried at line 408 of an 817-line file. Requirement 50:
   *"Interfaces live with their concept as the layer's first file(s)."*

3. **`Reference.jl`'s own header names three jobs** ("the reference-path *types* … the value
   protocol on them … and the path-producing reflection search"). A three-item contract is
   the smell PAR-MODULE-DOCSTRING exists to catch.

PAR-PACKAGE-CHAIN is the constraint that keeps this honest: *"Files are a readability boundary
only and must never imply an API boundary the module does not enforce."* The module stays
exactly one module; these stay fragments sharing its namespace. This buys readability, not
function — price it accordingly.

## Explicitly out of scope (deferred)

- **Deleting `TypeReference` as a step type** (and `step_kind` with it). Established in
  discussion: the folded representation already stores both types of `::T.f::U` (verified —
  `@reference ::Foo.f::Bar` yields `ConcreteReferencePath(Foo, .f, EmptyReferencePath(Bar))`
  with **zero** `TypeReference` steps in the value). What actually keeps `TypeReference`
  alive is the *step-vararg APIs* — `ReferencePath(steps...)`, `append_reference(base,
  steps...)`, `ProjectionTemplate._prepend(rest, steps...)` — which have no channel for a
  type, so a type has to ride inside a step and get unpacked by `fold_reference_types`.
  Removing it means folding at macro-expansion time and reworking two codegen sites; that is
  a separate plan. **This split must leave `TypeReference` working exactly as it does today.**
- **Unifying the two DSL grammars.** `_parse_build_path!` (ReferenceBuilder.jl:71) and
  `_parse_path!` (ReferenceCase.jl:146) are the same recursive-descent grammar written twice,
  down to verbatim-identical comments, feeding two parallel step-AST hierarchies. Worth a
  shared `ReferenceSyntax.jl` later (the `@event_case`/`@gestures` shared-parser precedent in
  PAR-MODULE-BOUNDARY-IS-API). Not this plan.

The layout below leaves room for both: `TypeReference` is confined to `ReferenceStep.jl`, and
a future `ReferenceSyntax.jl` slots between `ReferenceEvaluation.jl` and the two DSL fragments.

## Precondition: this breaks seals

All five reference files are 🔒 **sealed**. The split edits three of them and deletes one.
**Do not start without the user's explicit permission for each:**

**The user granted the seal override explicitly** (2026-07-13). Files touched, as built:

| File | Change |
| --- | --- |
| `reference/Reference.jl` | content moved out; file **deleted** |
| `reference/ReferenceModule.jl` | include list + the fragment docstring |
| `reference/ReferenceCase.jl` | header comment + `dsl_match_step` / `dsl_step_subpath_args` moved out to `Interface.jl` |
| `reference/ReferenceBuilder.jl` | header comment + `dsl_build_step` moved out to `Interface.jl` |
| `reference/ReferenceLayer.jl` | **untouched** — it only includes `ReferenceModule.jl`; keeps its 🔒 |

Every reference file the split touched dropped back to ⬜ **unsealed** in the CLAUDE.md seal
list, pending re-audit against
[architecture-requirements.md](../../documentation/rule/architecture-invariants.md). Carrying a
seal across a content change would defeat the point of the seal; re-sealing is the user's
call. The audit should be cheap — the code is unchanged, only its home is new.

### Decisions taken

- **Seal list rewritten** (the recommended option). The reference section drops the
  `Reference.jl` entry and lists the nine files in load order. The alternative — keeping the
  name `Reference.jl` for one fragment so no entry disappears — was rejected: it costs
  naming consistency for nothing.
- **The `dsl_*` seams moved to `Interface.jl`** (the recommended option), so both DSL
  fragments are touched after all. They are the layer's extension points —
  `PointReference.jl` imports all three — so they belong in the contract, not buried in a DSL
  fragment.

## Target layout

Include order is load-bearing: struct field annotations (`head::ReferenceStep`,
`tail::ReferencePath`) are evaluated at definition time, so the abstract types must precede
the concrete ones.

```
reference/
  ReferenceLayer.jl        unchanged — includes ReferenceModule.jl
  ReferenceModule.jl       module: imports, exports, include list (updated)
  Interface.jl             NEW  ~90   the layer contract
  ReferenceStep.jl         NEW ~170   the step vocabulary
  ReferencePath.jl         NEW ~230   the path structure + algebra
  ReferenceEvaluation.jl   NEW ~220   document-aware walking + the typing invariant
  ReferenceSearch.jl       NEW ~145   search_references
  ReferenceCase.jl         unchanged (bar 1 header line)
  ReferenceBuilder.jl      unchanged
```

Source line ranges below are from today's `Reference.jl`.

### `Interface.jl` — the layer contract

Follows `operation/Interface.jl`: abstract vocabulary + open generic *declarations*; concrete
methods live in siblings.

- `abstract type ReferenceStep` (10–16), `abstract type ReferencePath` (130–137),
  `const Reference = Union{Nothing, ReferencePath}` (155–161).
- The step seam: the `step_kind` / `evaluate_step` docstrings and the seam prose (408–439),
  plus the `step_kind(::ReferenceStep) = :structural` default (425) — legal here, the
  abstract type is defined a few lines up.
- The DSL seams: `dsl_build_step` / `dsl_match_step` / `dsl_step_subpath_args` declarations,
  docstrings, and their "no method registered" error fallbacks, moved out of
  `ReferenceBuilder.jl` / `ReferenceCase.jl`. These are the layer's extension points —
  `PointReference.jl` imports all four — so they belong in the contract, not buried in a DSL
  fragment. *(This is the one place the plan moves code out of a file other than
  `Reference.jl`. If the user prefers to keep the seal blast radius to three files, leave the
  `dsl_*` generics where they are and note the inconsistency; the split still stands.)*

### `ReferenceStep.jl` — the step vocabulary

Each step type gets its struct, `show`, `==`, `step_kind`, and `evaluate_step` **adjacent**,
matching how `PointReference.jl` packages a step.

- `RangeReference` + `ElementReference` / `PositionReference` constructors +
  `is_element_reference` / `is_position_reference` + `Position` (18–80), its `show`
  (242–250), its `==` (283), its `step_kind`/`evaluate_step` (443, 449–452).
- `FieldReference` (83–90) + `show` (252–254) + `==` (284) + `evaluate_step` (454–455).
- `TypeReference` + `ReferenceTypeMismatch` (92–126) + `show` (256–258) + `==` (285) +
  `step_kind`/`evaluate_step` (445, 457–461). Kept together so the deferred deletion is a
  clean excision of one block.
- The `==(::ReferenceStep, ::ReferenceStep) = false` fallback (286).
- The navigation helpers `_deref_cell`, `_has_field`, `_get_field` (383–406). Used also by
  `ReferenceSearch.jl` — fine, same module (PAR-MODULE-BOUNDARY-IS-API explicitly blesses fragment
  sharing over exporting an internal).

### `ReferencePath.jl` — the path structure and its algebra

Everything that needs no document.

- `EmptyReferencePath` (139–153), `ConcreteReferencePath` + its two-arg / one-arg
  constructors + the whole-element (`∅`) note + `ReferencePath(steps...)` (163–218).
- Accessors, `isempty`, `length`, iteration, `eltype` (220–238).
- Path `show` + `_show_node_type` (260–278), path `==` + `is_reference_equal` +
  `is_prefix_of` (288–316).
- `append_reference`, `concat_references`, `reference_steps` (318–381).

### `ReferenceEvaluation.jl` — document-aware walking + the typing invariant

The three walkers are structurally parallel, all dispatch through the step seam, and all
enforce the same "types always present" invariant, so they stay together.

- `evaluate_reference` (463–484).
- `get_valid_reference_prefix`, `is_valid_reference` (486–538).
- `reference_node_type` / `_node_type`, `annotate_reference_types`, `strip_reference_types`,
  `fold_reference_types`, `is_fully_typed`, `_strict_check` (540–675).

### `ReferenceSearch.jl` — the path-producing reflection search

- `_is_search_leaf`, `_search_text`, `_text_query`, `search_references`,
  `_search_references!` (677–817), with the "keep in sync with `search_documents`" note.

## Steps

Done in the worktree `.claude/worktrees/reference-layer-file-split` (branch
`worktree-reference-layer-file-split`), not the main checkout — there is concurrent activity
in main, so every commit named explicit paths.

- [x] **0. Baseline.** `ProjecturedKernel | 338 Pass, 338 Total`, zero Fail/Error/Broken.
      (The invocation in the original plan was wrong: `test_kernel` lives in the test package,
      so it is `using Projectured, ProjecturedKernelTest; test_kernel()`.)
- [x] **1–4. The five fragments**, `Reference.jl` deleted, `ReferenceModule.jl` include list
      and docstring updated, `dsl_*` seams lifted out of the two DSL fragments, header
      docstrings written for each new file. **Landed as one commit** (`903c5ee0`), not the
      four the plan proposed — see the deviation below.
- [x] **5. Verification.** Full-stack load + `test_kernel()`: **338/338, matching the baseline
      exactly**, zero Fail/Error/Broken.
- [x] **6. Docs + seal list** (`10f39885`).

### Deviation: commit granularity

The plan called for a commit *and a verification run* per fragment. Dropped, for two reasons:
each intermediate state would have needed its own full Julia precompile + test cycle (minutes
each) to be honestly "verified", and bisecting four mechanical commits buys nothing over
bisecting one — a dropped definition fails at load, pointing straight at the name. The code
motion is one atomic refactor and landed as one commit.

What replaced the per-step runs is a **stronger** check for pure motion, run before any test:
strip comments and blanks from the old `Reference.jl` and from the five new fragments,
normalize whitespace, sort, and set-diff the code lines. Every code line of the old file was
present in the new fragments — zero dropped — which a test run cannot prove (a lost `==`
method would silently change behavior rather than error). Only then was the test run spent.

## Docs to update (step 6)

Found by grep; all name `Reference.jl` or "three fragments" and go stale:

- [package/kernel/doc/reference.md](../../documentation/package/kernel/reference.md) — lines 19, 26, 32,
  35, 39 (the fragment tree and the "three fragments" prose) and 580 (`Reference.jl`
  documents the higher-type-opaquely rule → now `Interface.jl`).
- [package/kernel/doc/selection.md](../../documentation/package/kernel/selection.md):69 — "the generic
  implementation in `Reference.jl` walks the path step by step" → `ReferenceEvaluation.jl`.
- [documentation/architecture.md](../../documentation/design/system-anatomy.md):308 (the include tree)
  and 383 (the module-inventory table row).
- [documentation/concepts.md](../../documentation/design/editor-concepts.md):186 — the `Reference` row's
  file pointer.
- [CLAUDE.md](../../CLAUDE.md):35–37 — the seal list (see the open decision above).

## Verification

Per-step, not just at the end:

- `julia --project=. -e 'using Projectured; test_kernel()'` — includes `test_kernel_layering()`,
  which asserts a valid topological include order and layer/slice membership, so a
  misordered include fails loudly here.
- An **actual load** of the full stack (`using Projectured`), not just the guards: structural
  guards and a green `Pkg.precompile` exit code can both pass while every `using` fails.
  The load is what proves the include order really works.
- `test_domain()` once at the end. Code motion inside one module should be invisible
  downstream; this is the cheap check that it is.

Counts must match the step-0 baseline exactly. Any new `Fail`/`Error` is a regression from
the motion — most likely a definition left behind, duplicated, or ordered after its use in a
struct field annotation.

## Risks

- **Include order.** The one real hazard. `ConcreteReferencePath` has `head::ReferenceStep`
  and `tail::ReferencePath`, evaluated at definition time — hence abstract types first, in
  `Interface.jl`. Method *bodies* resolve lazily, so `evaluate_step(::TypeReference)` throwing
  `ReferenceTypeMismatch` (same file) and `ReferenceSearch.jl` calling `_deref_cell`
  (earlier file) are both fine.
- **Silent loss.** A moved block that gets dropped rather than relocated fails as a
  `MethodError`/`UndefVarError` at load, not silently — the full-stack load catches it.
- **Seal churn.** Eight files to re-audit and re-seal. That cost is real and is the main reason
  to fold the deferred `TypeReference` and grammar work into the same seal cycle later rather
  than re-sealing twice.

## Outcome

Landed on branch `worktree-reference-layer-file-split`:

| Commit | |
| --- | --- |
| `879c5e85` | the plan |
| `903c5ee0` | the split — 9 files, +968 / −891 |
| `10f39885` | docs + seal list |

The layer as built (load order), 2238 lines across nine files where there were five:

```
ReferenceLayer.jl          2   includes ReferenceModule.jl
ReferenceModule.jl        96   imports, exports, include list
Interface.jl             129   the contract: 2 abstract types, the Reference union, 5 generics
ReferenceStep.jl         202   RangeReference / FieldReference / TypeReference / Position
ReferencePath.jl         225   the path structure and its document-free algebra
ReferenceEvaluation.jl   231   the 3 walkers + the "types always present" invariant
ReferenceSearch.jl       142   search_references
ReferenceCase.jl         741   @reference_case
ReferenceBuilder.jl      470   @reference / @step
```

`Reference.jl` was 817 lines doing three jobs; the largest fragment that replaces it is 231.

**Verified:** full-stack `using Projectured` loads clean; `test_kernel()` returns 338/338,
identical to the pre-split baseline; zero code lines lost (set-diff, above).

### Left undone, deliberately

- **`documentation/architecture.md`'s "Module dependency graph"** (~line 308) still lists
  `Reference.jl (depends on Reactive)`. That whole diagram predates the layering — it names a
  `Reactive` module that no longer exists and flat `Text.jl` / `Json.jl` / `ProjectionApiModule`
  entries that are not the current structure. Fixing one line of a broadly stale diagram would
  imply the rest is current. It needs its own pass; out of scope for a file split.
- The two deferred items at the top of this plan (`TypeReference` deletion, DSL grammar
  unification) are untouched, as intended.
