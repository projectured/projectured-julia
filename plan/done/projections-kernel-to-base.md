# Move all concrete projections from kernel to base

> **STATUS (2026-07-09, IMPLEMENTED):** Done on `main` in commit `d39da1f`. All
> 12 concrete projection modules (`generic/`: Identity, Reversing, Constant,
> Focusing; `higherorder/`: Chaining, TypeDispatching, Recursive, Switching,
> PredicateDispatching, ReferenceDispatching, Nesting, EnvelopeUnwrapping) now
> live under `package/base/main/projection/`; the kernel projection layer keeps
> only the interface + infrastructure. The `ProjectionTemplate` ↔
> `RecursiveProjection` coupling was broken by relocating the two `RuleIoMap`
> disambiguations to base's `ReaderDefaults.jl` (Phase 2). Visual/domain aliases
> were repointed to `ProjecturedBase`, `FocusingTest` moved to the base test
> package, and the kernel/base architecture guides + docstrings updated. The
> phases below are kept as the historical record.
>
> **Not run:** the Julia test suite was not executed in the implementing
> session (no Julia toolchain available; the installer host was blocked by egress
> policy). Verification was static — import resolution, include-order topological
> sort, no residual `ProjecturedKernel.<moved>` references, and preservation of
> the full `read_intent` dispatch set. The recommended follow-up checks are
> `test_kernel_layering()`, `test_base()`, and one pipeline test such as
> `test_json_to_syntax()`.

## Goal

Make `ProjecturedKernel`'s projection layer carry **only projection machinery**
(the interface, the IO-map types, the `@projection` macro, the projection
template engine, the gesture-binding infrastructure) and move every **concrete
projection struct** down into `ProjecturedBase`, alongside the concrete
projections base already owns (`SortingProjection`, `FilteringProjection`,
`SearchingProjection`, `CopyingProjection`, `DraggingProjection`).

This finishes the direction the architecture already states — the kernel
docstring claims it "carries no concrete documents at all" and base is "the
domain-independent vocabulary and frameworks." Concrete generic/higher-order
projections are domain-independent *frameworks built on the kernel interface*,
so base is their correct home. After the move, `ProjecturedKernel`'s projection
layer is purely the interface + algebra engine, with zero concrete `Projection`
subtypes.

## Scope — what moves and what stays

### Moves to base (12 modules, `package/kernel/main/projection/{generic,higherorder}/`)

**Generic** (`generic/`):
- `Identity.jl` — `IdentityProjectionModule`
- `Reversing.jl` — `ReversingProjectionModule`
- `Constant.jl` — `ConstantProjectionModule`
- `Focusing.jl` — `FocusingProjectionModule`

**Higher-order** (`higherorder/`):
- `Chaining.jl` — `ChainingProjectionModule`
- `TypeDispatching.jl` — `TypeDispatchingProjectionModule`
- `Recursive.jl` — `RecursiveProjectionModule`
- `Switching.jl` — `SwitchingProjectionModule`
- `PredicateDispatching.jl` — `PredicateDispatchingProjectionModule`
- `ReferenceDispatching.jl` — `ReferenceDispatchingProjectionModule`
- `Nesting.jl` — `NestingProjectionModule`
- `EnvelopeUnwrapping.jl` — `EnvelopeUnwrappingProjectionModule`

### Stays in kernel (projection machinery — layer 7 interface & engine)

`ProjectionApi.jl`, `IoMapApi.jl`, `Intent.jl`, `IoMap.jl`,
`PrinterContext.jl`, `ChildrenContainer.jl`, `GestureBindings.jl`
(`ProjectionGestureBindingsModule`), `Projection.jl` (`ProjectionModule` —
four-generic fallbacks + `@projection` macro), `ProjectionTemplate.jl`.

## Feasibility — the dependency picture (verified)

The move is clean because **kernel machinery does not depend on any concrete
projection**, with exactly one exception:

1. **No kernel machinery names a concrete projection** except
   `ProjectionTemplate.jl`. Grepping every concrete-projection module name
   across `package/kernel/main` (excluding the `generic/` and `higherorder/`
   folders themselves) yields a single hit:
   `ProjectionTemplate.jl:44 import ..RecursiveProjectionModule: RecursiveProjection`.

2. **The editor and agent layers are clean** — the only matches are prose in
   doc comments (`editor/Editor.jl:38` mentions `ChainingProjection` in a
   docstring). No code dispatch.

3. **`Projection.jl` (the defaults + macro) is clean** — the only match is a
   docstring listing example projection names.

4. **The concrete projections import only kernel + peers.** Every
   `import ..XxxModule` in the 12 files resolves to a kernel machinery module
   (`CellModule`, `GestureModule`, `IntentModule`, `IoMapApiModule`,
   `IoMapModule`, `OperationModule`, `PrinterContextModule`,
   `ProjectionApiModule`, `ProjectionGestureBindingsModule`, `ReferenceModule`)
   or to a peer concrete projection (`IdentityProjectionModule`, imported by the
   higher-order compound users). None import a base document type
   (Primitive/Collection). So the projection layer of base can host them
   with only kernel + document-layer dependencies — satisfying the base
   layering guard order `document → projection → serialization`.

### The one coupling to break: `ProjectionTemplate` ↔ `RecursiveProjection`

`ProjectionTemplate.jl` stays in kernel but currently imports
`RecursiveProjection` to define two **disambiguation** `read_intent` methods
whose signatures name `RecursiveProjection`:

- `read_intent(rp::RecursiveProjection, iomap::RuleIoMap, evt::Union{KeyPress, KeyDown})` (line ~1298)
- `read_intent(rp::RecursiveProjection, iomap::RuleIoMap, op::ReplaceSelectionOperation)` (line ~1328)

Once `RecursiveProjection` lives in base, the kernel cannot name it, so these two
methods must move down to base — **exactly the precedent already set** for the
third disambiguation method. `base/main/projection/ReaderDefaults.jl` already:
- imports `RuleIoMap, AtomicWiring` from `ProjecturedKernel.ProjectionTemplateModule`,
- imports `RecursiveProjection`,
- and hosts `read_intent(rp::RecursiveProjection, iomap::RuleIoMap, op::ReplaceStringRangeOperation)`
  (line 53) — moved out of `ProjectionTemplate.jl` for the identical reason
  (it names a base type).

So the pattern, the imports, and the home file already exist. We add the two
remaining `RecursiveProjection` disambiguation methods next to it and delete
them (plus the `import ..RecursiveProjectionModule` and its explanatory comment)
from `ProjectionTemplate.jl`.

The non-recursive `read_intent(p::Projection, iomap::RuleIoMap, op::ReplaceSelectionOperation)`
method (line ~1312) names only kernel types and **stays** in `ProjectionTemplate.jl`.

## Plan

### Phase 1 — Move the 12 module files

1. `git mv` the four `generic/*.jl` and eight `higherorder/*.jl` files from
   `package/kernel/main/projection/` to `package/base/main/projection/`.
   Suggested layout: keep the `generic/` and `higherorder/` subfolders under
   `base/main/projection/` (or flatten — decide with the base projection
   layer's existing flat layout; base currently keeps projection files flat, so
   flattening to `base/main/projection/<Name>.jl` matches the neighbours).
2. The files need **no edits to their `import ..XxxModule` lines** — those
   relative references resolve inside `ProjecturedBase` once the aliases exist
   (Phase 3). Peer imports (e.g. higher-order files importing
   `..IdentityProjectionModule`) now resolve to the real base module.

### Phase 2 — Break the ProjectionTemplate coupling

1. In `package/kernel/main/projection/ProjectionTemplate.jl`:
   - Delete `import ..RecursiveProjectionModule: RecursiveProjection` (line 44).
   - Delete the two `read_intent(rp::RecursiveProjection, iomap::RuleIoMap, …)`
     methods (lines ~1298 and ~1328) and their disambiguation comments.
   - Update the comment at line ~54 ("dispatches on RecursiveProjection") — it
     no longer does.
   - Keep the non-recursive `read_intent(p::Projection, iomap::RuleIoMap, op::ReplaceSelectionOperation)`.
2. In `package/base/main/projection/ReaderDefaults.jl` (or a sibling fragment):
   - Add the two moved methods verbatim. `RecursiveProjection`, `RuleIoMap`,
     `Intent`, and `ReplaceSelectionOperation` are all importable here
     (`RecursiveProjection` becomes base-local `..RecursiveProjectionModule`;
     `RuleIoMap`/`AtomicWiring` already imported from kernel; add
     `ReplaceSelectionOperation` from `ProjecturedKernel.OperationModule`).
   - Change `ReaderDefaults.jl`'s `import ProjecturedKernel.RecursiveProjectionModule: RecursiveProjection`
     (line 18) to the base-local `import ..RecursiveProjectionModule: RecursiveProjection`.

### Phase 3 — Wire the modules into base and fix aliases

In `package/base/main/ProjecturedBase.jl`:

1. **Remove** the four aliases that now shadow real base modules (they must not
   be `const … = ProjecturedKernel.X` once base *defines* `X`):
   `IdentityProjectionModule`, `NestingProjectionModule`,
   `RecursiveProjectionModule`, `ReferenceDispatchingProjectionModule`.
2. **Add** the one missing kernel-machinery alias the moved files reference:
   `const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule`
   (`GestureBindings.jl` stays in kernel; the moved Focusing/Chaining/Nesting/
   TypeDispatching/Recursive files import `collect_gesture_bindings` from it).
   All other kernel modules the moved files need are already aliased
   (`CellModule`, `GestureModule`, `IntentModule`, `IoMapApiModule`,
   `IoMapModule`, `OperationModule`, `PrinterContextModule`,
   `ProjectionApiModule`, `ReferenceModule`).
3. **Add `include(...)` lines** for the 12 files in the projection layer, in a
   dependency-respecting order. The higher-order compound files
   (`HigherOrderCompound.jl`, `GenericCompound.jl`) and `DraggingProjection.jl`
   import `RecursiveProjection`/`ReferenceDispatchingProjection`/`NestingProjection`/
   `IdentityProjection`, so the 12 moved files must be included **before** them.
   A safe order inside the projection layer:
   ```
   generic/Identity.jl, generic/Reversing.jl, generic/Constant.jl
   higherorder/Chaining.jl, higherorder/TypeDispatching.jl,
   higherorder/Recursive.jl, higherorder/Switching.jl,
   higherorder/PredicateDispatching.jl, higherorder/ReferenceDispatching.jl,
   higherorder/Nesting.jl, higherorder/EnvelopeUnwrapping.jl,
   generic/Focusing.jl            # Focusing imports gesture bindings; place after algebra
   Sorting.jl, Filtering.jl, Searching.jl, Copying.jl,   # existing
   ReaderDefaults.jl, DraggingProjection.jl,
   HigherOrderCompound.jl, GenericCompound.jl            # existing compounds last
   ```
   Cross-check each moved file's `import ..` peers and topologically sort;
   `Identity` has no peer imports, the dispatchers import gesture bindings, the
   compounds import the dispatchers.

### Phase 4 — Remove the kernel includes

In `package/kernel/main/projection/ProjectionLayer.jl`, delete the 12
`include("generic/…")` / `include("higherorder/…")` lines (lines 22–33). The
layer file then lists only the machinery includes.

### Phase 5 — Repoint downstream aliases

`ProjecturedVisual` and `ProjecturedDomain` currently alias these modules as
`const XxxProjectionModule = ProjecturedKernel.XxxProjectionModule`. Both
packages already `using ProjecturedBase`, so **repoint the aliases** from
`ProjecturedKernel.` to `ProjecturedBase.`:

- `package/visual/main/ProjecturedVisual.jl` lines 85–96 (12 aliases:
  Identity, TypeDispatching, PredicateDispatching, ReferenceDispatching,
  Chaining, Nesting, Recursive, Switching, EnvelopeUnwrapping, Focusing,
  Reversing, Constant).
- `package/domain/main/ProjecturedDomain.jl` lines 56, 61, 62, 68, 71, 75, 85
  (Nesting, PredicateDispatching, Identity, Recursive, ReferenceDispatching,
  Chaining, TypeDispatching).

Keeping the **alias names identical** means every downstream `import
..XxxProjectionModule` in visual/domain source keeps working unchanged (19
files in domain, 9 in visual, 2 in base — the base ones now resolve to
base-local modules).

**Opt-in packages need no change:** `package/odbc/main/ProjecturedOdbc.jl:388-389`
reaches these via `ProjecturedDomain.RecursiveProjectionModule` /
`ProjecturedDomain.ChainingProjectionModule`, which stay valid because domain
keeps the same alias names (Phase 5 only repoints their right-hand side).

**Umbrella needs no change:** `Projectured.jl` re-exports by looping over each
source's submodules with a `parentmodule(_m) === _src` guard, so a module that
moves from kernel to base is automatically re-exported as a base module with no
edit.

### Phase 6 — Move tests, examples, and docs (triad rule)

Per the triad rule ("every piece lives in the lowest package of its DAG whose
API it hard-references"):

1. **Tests.** The only kernel test that hard-references a moved projection is
   `package/kernel/test/editor/FocusingTest.jl` (uses `FocusingProjectionModule`,
   included from `ProjecturedKernelTest.jl:73` with
   `using ProjecturedKernel.FocusingProjectionModule` at line 49). Move it to
   `package/base/test/projection/FocusingTest.jl`, repoint its `using` to
   `ProjecturedBase.FocusingProjectionModule`, and register it in
   `ProjecturedBaseTest.jl` instead of `ProjecturedKernelTest.jl`. Verify no
   other kernel test names a moved module (grep confirmed only Focusing +
   the aggregator).
2. **Examples.** Grep `package/kernel/example` — no example hard-references a
   moved module (none found), so nothing to move.
3. **Docs.** `package/kernel/doc/generic-projections.md` and
   `package/kernel/doc/higher-order-projections.md` document the moved
   projections; move them to `package/base/doc/` and update the doc index in
   `package/kernel/doc/architecture.md` and `package/base/doc/architecture.md`
   (base's projection section at lines 74–92 lists Sorting/Filtering/…; extend
   it with the generic + higher-order sets). Update the reading-order links in
   the root `CLAUDE.md`/`README.md` and `documentation/architecture.md` module
   inventory (Stage 2 tables) to point at the new base location. Also refresh
   the kernel `ProjecturedKernel.jl` docstring line that claims the kernel
   carries "the projection algebra (higher-order combinators + generic
   projections)" — after the move it carries the interface + template engine,
   not the concrete combinators.

### Phase 7 — Update the base layering guard expectation

The base guard already declares `layers = ["document","projection","serialization"]`
(`ProjecturedBaseTest.jl:55`) and needs no new layer. But confirm the moved
files respect it: they may import only the `document` layer and kernel, never
`serialization`. All 12 import kernel machinery only (verified), so the guard
should pass unchanged. Run `test_base_layering()` to confirm, and
`test_kernel_layering()` to confirm the kernel projection layer still satisfies
its ordered-layer rule after losing the concrete files.

## Verification

Run in increasing scope, stopping at the first failure:

1. `test_kernel_layering()` and `test_base_layering()` — the static guards.
2. `test_cell()` then `test_kernel()` — kernel still loads and the projection
   template engine + reader defaults still dispatch correctly (the moved
   `RecursiveProjection` disambiguations are the main risk).
3. `test_base()` — base loads with the 12 new modules and the moved Focusing
   test passes.
4. `test_json_to_syntax()` / `test_syntax_to_text()` — a representative
   pipeline that exercises `RecursiveProjection` + `TypeDispatchingProjection` +
   `ChainingProjection` + the template engine end-to-end, proving the
   machinery↔concrete split still composes across the kernel/base boundary.
5. `test_visual()` / `test_domain()` — the repointed aliases resolve and the
   full pipelines still build.

The load-order and disambiguation-dispatch are the two things most likely to
break; the layering guards plus a single JSON→Syntax→Text pipeline test cover
both.

## Risks & notes

- **Load order is the main hazard.** Julia includes are a hand-maintained
  topological sort; a moved file included before a peer it imports fails at
  precompile. Phase 3's ordering must be cross-checked against each file's
  `import ..` peers (Identity → dispatchers → Focusing → compounds).
- **Method dispatch, not just names.** The two `RecursiveProjection`
  disambiguation methods exist *because* Julia can't rank the recursive
  `Projection` reader against the transparent-wrapper reader. Moving them must
  preserve identical signatures so the ambiguity resolves the same way — verify
  with the JSON pipeline test (item 4), which is where a regression would show
  as a wrong operation on a keystroke inside a nested node.
- **Alias-shadowing.** Removing the four kernel-pointing aliases in base is
  mandatory: a `const RecursiveProjectionModule = ProjecturedKernel.…` alias and
  a base submodule of the same name cannot coexist. Missing this yields a
  redefinition error at base load.
- **No API surface change.** Every projection keeps its name and its
  export; the umbrella re-exports it identically. Downstream code that writes
  `using Projectured` sees no difference. Only intra-project `import
  ..XxxModule` resolution moves from kernel to base, absorbed by the alias
  repointing in Phase 5.
