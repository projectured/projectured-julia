# Reference-layer naming review

A consistency pass over the vocabulary the reference layer (Layer 8) exports.
The layer is not yet sealed, so its own names are free to change; the review also
crosses into a small number of **sealed** Layer-7 touch-points (flagged below)
that need explicit permission.

## The core insight

The **function** names already treat *reference* = *the path*: `append_reference`,
`concat_references`, `reference_steps`, `evaluate_reference`, `is_valid_reference`,
`search_references`, `annotate_reference_types`, … all operate on the linked-list
path and call it a "reference". Only the **type** names use a split vocabulary:

- `ReferencePath` (abstract) + `EmptyReferencePath` / `ConcreteReferencePath` — the path.
- `Reference` = `Union{Nothing, ReferencePath}` — the union a `selection` field holds.
- `RangeReference`, `FieldReference`, `TypeReference`, … — the **steps**, which are
  *not* references at all (a step is one link; a reference is the whole chain).

So the fix is: **a "reference" is the path** (rename `ReferencePath → Reference`),
**a step is a `…ReferenceStep`** (not a `…Reference`), and the union that currently
squats on the name `Reference` moves aside.

## Three problems, restated

1. **Steps are misnamed as references.** `FieldReference` reads as "a reference to a
   field", but it is a *step* that navigates a field. The abstract type is already
   `ReferenceStep`; the concretes should end in `…ReferenceStep`.
2. **`Reference` vs `ReferencePath` are used interchangeably.** Pick one word for the
   addressing chain — "reference" — and drop "Path". The union yields the name.
3. **A few names are too vague:** `append_reference` (appends *steps*, not a
   reference), `is_prefix_of`, `is_fully_typed`, and the `dsl_*` seam trio.

## Proposed vocabulary

### The addressing chain (path → reference)

| Current | Proposed | Note |
|---|---|---|
| `ReferencePath` (abstract) | **`Reference`** | reference *is* the chain |
| `EmptyReferencePath` | **`EmptyReference`** | terminates *at* a node (incl. ∅ whole-node) |
| `ConcreteReferencePath` | **`ConcreteReference`** | non-empty (head step + tail) — see open Q4 |
| `ReferencePath(steps...)` ctor | **`Reference(steps...)`** | build from steps |
| `Reference` = `Union{Nothing, ReferencePath}` | **removed — inline `Union{Nothing, Reference}`** | the `const Reference` alias is deleted; each `selection`-field type is spelled out, so `Reference` means the path and nothing else |

### Steps (`…Reference` → `…ReferenceStep`)

| Current | Proposed | Owner |
|---|---|---|
| `ReferenceStep` (abstract) | `ReferenceStep` | kernel (unchanged) |
| `RangeReference` | **`RangeReferenceStep`** | kernel |
| `FieldReference` | **`FieldReferenceStep`** | kernel |
| `TypeReference` | **`TypeReferenceStep`** | kernel |
| `ElementReference(i)` (ctor → range) | **`ElementReferenceStep(i)`** | kernel |
| `PositionReference(i)` (ctor → range) | **`PositionReferenceStep(i)`** | kernel |
| `ProjectionReference` | **`ProjectionReferenceStep`** | projection |
| `PointReference` | **`PointReferenceStep`** | graphics |
| `TextSpanReference` | **`TextSpanReferenceStep`** | text |
| `TextRangeReference` | **`TextRangeReferenceStep`** | text |
| `TextColumnReference` | **`TextColumnReferenceStep`** | text |
| `is_element_reference(s)` | **`is_element_reference_step(s)`** | predicate on a reference step |
| `is_position_reference(s)` | **`is_position_reference_step(s)`** | predicate on a reference step |
| `Position` (cursor value) | `Position` | minor — see open Q5 |
| `ReferenceTypeMismatch` | `ReferenceTypeMismatch` | unchanged |

The eight rows above `is_element_reference` are **the complete set** of concrete
`ReferenceStep` subtypes (verified by `<: ReferenceStep` grep). **Do NOT rename**
`SqlColumnReference` (sql-domain `Document`) or `FormulaReference` (formula-domain
`Document`) — despite the `…Reference` name, they are documents, not steps, so a
blanket `*Reference → *ReferenceStep` sweep must exclude them.

### Path algebra

| Current | Proposed | Note |
|---|---|---|
| `append_reference(r, steps...)` | **`extend_reference(r, steps...)`** | extends a reference *with steps* — see open Q3 |
| `concat_references(a, b)` | `concat_references(a, b)` | now unambiguous (ref + ref) |
| `reference_steps(r)` | **`get_reference_steps(r)`** | verb-first (accessor) |
| `is_reference_equal(a, b)` | `is_reference_equal(a, b)` | unchanged |
| `is_prefix_of(a, b)` | **`is_reference_prefix(a, b)`** | matches `is_reference_equal` (a is a prefix of b) |

### Evaluation & the type protocol (mostly already right)

| Current | Proposed | Note |
|---|---|---|
| `evaluate_reference` / `try_evaluate_reference` | unchanged | |
| `get_valid_reference_prefix` / `is_valid_reference` | unchanged | |
| `annotate_reference_types` / `strip_reference_types` / `fold_reference_types` | unchanged | |
| `reference_node_type` | **`get_reference_node_type`** | verb-first (accessor) |
| `is_fully_typed(r)` | **`is_fully_typed_reference(r)`** | matches `is_valid_reference` |
| `step_kind(s)` | **`get_reference_step_kind(s)`** | verb-first + carries "reference step" |
| `evaluate_step(s, doc)` | **`evaluate_reference_step(s, doc)`** | carries "reference step"; pairs with `evaluate_reference` |
| `search_references` | unchanged | produces references |

### Reference-step DSL seams (`dsl_*` → `*_reference_step`)

The three seams a higher-package step type registers to join the two reference
DSLs. They carry the uniform `reference_step` noun and lead with a verb. They exist
**only** for `.name(...)` extension steps — the kernel's built-in steps (`.field`,
`[i]`, `{k}`, `::T`) are lowered directly, never through these — a fact the
default-method error message and docstrings state (so the name stays
`build_reference_step`, not the ballooning `build_extension_reference_step`).

| Current | Proposed | Used by |
|---|---|---|
| `dsl_build_step(::Val{n}, args...)` | **`build_reference_step`** | `@reference` |
| `dsl_match_step(::Val{n}, …)` | **`match_reference_step`** | `@reference_case` |
| `dsl_step_subpath_args(::Val{n})` | **`get_reference_step_subpath_args`** | both DSLs + `@step` |

### Verb-first + the `reference_step` noun (PAR-NAMING-LAW)

Every exported function now leads with a verb (`get_`/`is_`/`build_`/… ) and every
step operation carries the `reference_step` noun, matching the `ReferenceStep` type:
`get_reference_steps`, `get_reference_node_type`, `get_reference_step_kind`,
`evaluate_reference_step`, `is_element_reference_step`, `is_position_reference_step`,
`build_reference_step`, `match_reference_step`, `get_reference_step_subpath_args`.
The only remaining noun-first name is the pair of unexported linked-list accessors
`head` / `tail` (internal; the cons-list convention reads clearly), kept as-is. The
DSL keywords `when` / `prefix` are being **removed from the exports** entirely (Q6), so
they leave the public surface rather than standing as verb-first exceptions.

### Macros

| Current | Proposed | Note |
|---|---|---|
| `@reference` | `@reference` | unchanged |
| `@reference_case` | `@reference_case` | unchanged |
| `@step` | **`@reference_step`** | rename (not removal) — see Q6 for why it isn't redundant with `@reference` |

### Unchanged

`@reference`, `@reference_case`; the internal surface-AST (`RefStep`/`RefField`/…,
`PatValue`/`PatStep…`); the unexported `head` / `tail` accessors.

## Decisions (locked 2026-07-18)

- **Q1 — step suffix → `…ReferenceStep`.** Unambiguous cross-package; matches the
  abstract `ReferenceStep`.
- **Q2 — the union → inlined, no alias.** Delete `const Reference = Union{Nothing,
  ReferencePath}`; drop it from the exports; spell `Union{Nothing, Reference}` at every
  site (after the path rename). `Reference` now names the path and only the path.
- **Q3 — `append_reference` → `extend_reference`.** Pairs with `concat_references`
  (ref+ref) vs extend (ref+steps).
- **Q4 — the non-empty subtype → keep `ConcreteReference`** (least churn). Noted:
  *both* subtypes are technically concrete; revisit only if it grates.
- **Q5 — keep `Position`** (revisit `CaretPosition` later if desired). Low priority.
- **Q6 — the noun-first survivors, resolved:**
  - `@step` → **`@reference_step`** (rename, not removal). It is *not* redundant with
    `@reference`: it returns a single `ReferenceStep` (not a `Reference`), skips the
    strict-typing check (fragments are typed later), and its grammar drops a leading
    placeholder (a leading symbol is a real field in `@reference`, a placeholder in
    `@step` — essential for `@step c.point(x,y)`). Used 61× as composable step varargs
    to `make_child_context(ctx, doc, @step field, @step [i], …)`, where a `@reference`
    path would not fit and `@reference field` would throw (`under-typed`). Only the
    name was wrong.
  - `head` / `tail` — **keep** (unexported, internal cons-list accessors).
  - `when` / `prefix` — **un-export** (remove from `ReferenceModule`'s export list).
    Every DSL that uses them (`@reference_case`, and independently `@event_case` /
    `@gestures`) recognizes the *symbol* at macroexpand time and never evaluates the
    function — proven by the event layer (Layer 3) using `when(...)` far below the
    reference layer with no `when` imported. Once un-exported, the error-stubs are
    reachable only by qualified call (effectively dead) → **remove the stub
    definitions** too. Aside: `prefix` also collides with an unrelated real accessor
    `prefix(::DocumentInsertion)` in `base`'s `DocumentCore.jl` — un-exporting the
    reference stub also ends that overlap.
- **Sealed edits — approved.** May edit the three sealed Layer-7 touch-points below;
  user re-seals afterward.

## Sealed-file impact (needs explicit permission)

Renaming the union `Reference → OptionalReference` and the `…Reference` step names
reaches three sealed Layer-7 files:

- `document/DocumentMacro.jl` — **substantive**: line 350
  `add_cell_struct_field!(plan, :selection, :Reference, :nothing)` (the codegen that
  types every document's `selection` field), plus its docstring (L258–260) and the
  bare-symbol explanation comment (L327–341).
- `document/DocumentInterface.jl:24` — doc comment naming `ElementReference`.
- `document/DocumentWalk.jl:13` — doc comment naming `ReferencePath`.

## Scope & migration

~172 `.jl` files: visual (59), domain (51), kernel (34), base (22),
projectured/video/sdl/odbc (10). Largest single symbols: `ConcreteReferencePath`
(792), `FieldReference` (583), `EmptyReferencePath` (497), `RangeReference` (361),
`ReferencePath` (235).

Migration is a mechanical, per-symbol rename best done in a worktree, one symbol (or
small cluster) per commit, verifying the layering guard + a smoke test after each.
Order that avoids substring collisions on the token `Reference`:

1. **Steps first** — `…Reference → …ReferenceStep`, per-symbol (not a blanket sweep):
   `RangeReference`, `FieldReference`, `TypeReference`, `ElementReference`,
   `PositionReference` (kernel); `ProjectionReference`, `PointReference`,
   `TextSpanReference`, `TextRangeReference`, `TextColumnReference` (higher packages).
   **Exclude** `SqlColumnReference` and `FormulaReference` — they are documents, not
   steps. Doing steps before the path/union frees the bare token `Reference` of all
   step meanings.
2. **Dissolve the union** — delete `const Reference = Union{Nothing, ReferencePath}`,
   drop it from the exports, and rewrite every use site to spell
   `Union{Nothing, ReferencePath}` (still using the *current* path name). This is the
   sealed `DocumentMacro.jl:350` edit (emit the `Union{…}` expr instead of the bare
   `:Reference` symbol). After this, `Reference` names nothing.
3. **Path last** — `ReferencePath → Reference`, `EmptyReferencePath → EmptyReference`,
   `ConcreteReferencePath → ConcreteReference`; the `Union{Nothing, ReferencePath}`
   sites from step 2 become `Union{Nothing, Reference}` automatically.

Function renames (`extend_reference`, `is_reference_prefix`, `is_fully_typed_reference`,
`get_reference_steps`, `get_reference_node_type`, the `reference_step` ops and seams,
and `@step → @reference_step`) are independent of the above and can go in any order.

## Status — DONE (implemented on branch `reference-naming`, 2026-07-18)

All five rename phases landed as five commits; verified with **zero regressions**.

### Phases (one commit each)
1. Step types → `…ReferenceStep` (163 files).
2. Verb-first + `reference_step`-noun function renames; `@step`→`@reference_step`.
3. Dissolve the `Reference` union (each `selection` spells `Union{Nothing, Reference}`);
   path rename `ReferencePath`→`Reference`, `EmptyReferencePath`→`EmptyReference`,
   `ConcreteReferencePath`→`ConcreteReference`.
4. Un-export `when`/`prefix`, delete their dead error-stubs.
5. Doc-polish (stale `dsl_*` prose) + this plan.
6. Eponymous step modules/files → `…ReferenceStep{Module,ApiModule,.jl}` (follow-up,
   commit `a1666532`).

### Facts discovered during implementation
- **Union footprint was larger than the plan implied:** `Reference` (union) was
  imported in ~40 files (mostly so the macro-injected `selection::Reference` resolved).
  Files importing only the union keep `Reference` (it now binds the *path*); the 9
  importing both had the union token dropped. Use-sites (`::Reference`, `K{Reference}`,
  the macro's `:Reference` symbol) became explicit `Union{Nothing, Reference}`.
- **Eponymous step modules/files renamed (follow-up commit `a1666532`):** each
  standalone step type's module + file was named after the old type
  (`PointReferenceModule` + `graphics/PointReference.jl`, …); renamed to match
  (`…ReferenceStep{Module,ApiModule,.jl}` for Projection / Point / TextSpan / TextRange /
  TextColumn) across every using/import site, the package-level const aliases, the
  `include()` paths, the layering guard's `qualified_files` map, and the CLAUDE.md
  kernel inventory. The `ReferencePath.jl` fragment KEEPS its name — it names the
  fragment's *role* (the reference-path structure/algebra) and matches its sibling
  `Reference<Suffix>.jl` fragments; `Reference.jl` would collide with `ReferenceModule.jl`.
- **Exclusions held:** `SqlColumnReference` / `FormulaReference` (documents, not steps)
  untouched; `child_reference_steps` (a distinct function) untouched.

### Sealed files edited (permission granted) — RE-SEAL after review
- `document/DocumentMacro.jl` — the `selection` injection emits `Union{Nothing,
  Reference}` (was the bare `:Reference` symbol); docstring + comment updated.
- `document/DocumentInterface.jl:24`, `document/DocumentWalk.jl:13` — doc-comment
  step/path names.

### Verification (zero regressions)
- Kernel layering guard 10/10; base 7/7, visual 7/7, domain 6/6.
- JSON printer 3516/3516 (= pre-rename baseline), reader 225/225; base suite 97/97.
- Reference-DSL testsets all green (ReferenceBuilder 30/30, ReferenceEval 7/7,
  Rerooting 10/10, EventCase 26/26, GestureBinding 46/46).
- Re-verified after the module rename (commit `a1666532`): base 7/7, visual 7/7,
  domain 6/6, json printer 3516/3516, reader 225/225 — all green.
- Kernel suite: 455 pass, 3 fail / 2 error — **all 5 pre-existing**, the `DocumentMacro`
  "Rule C" testset: the CellVector collection-sugar trait lives in `base`, which the
  kernel-only test env doesn't load (commit `2e015ea5`, already on `main`). Confirmed by
  running `test_kernel()` on `main` (8559b2d5) → identical Fail 3 / Error 2.
