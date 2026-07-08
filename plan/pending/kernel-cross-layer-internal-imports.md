# Kernel — eliminate cross-layer internal-symbol imports

> **Status: plan only.** Inventory audited 2026-07-08 by parsing every relative
> `import ..XxxModule: syms` in `package/kernel/main` and checking each named
> symbol against the target module's fragment-aware `export` list, keeping only
> the imports whose importer and target live in *different* layer folders.

## The rule

Inside `ProjecturedKernel`, a cross-layer `import ..XxxModule: sym` may name
only symbols that `XxxModule` exports. A non-exported name is a module-internal
implementation detail; importing one across a layer boundary couples a higher
layer to a lower layer's internals, invisibly to both the export list and the
layering guard (which today checks only the module-level edge direction, not
symbol visibility).

What stays allowed:

- **Same-layer private imports** — e.g. `cell/ReactiveCell.jl` importing
  `_perf` from `PerformanceCounterModule` (both layer 1). The rule is about
  *layer* boundaries; neighbours inside one layer may share internals.
- **In-module fragment sharing** — the EventCase ↔ GestureBinding precedent
  (both fragments of `GestureModule`, no import exists; see the NOTE block in
  `device/EventCase.jl`).
- **Qualified self-references from fragments** — `ReferenceBuilder.jl` emitting
  `ReferenceModule._concat` / `ReferenceModule._splice` in macro output is a
  fragment of `ReferenceModule` qualifying its own module; not a cross-layer
  edge. (Verified: no `XxxModule._name` qualified access crosses a layer.)

## Inventory — 20 symbol-imports in 10 files, two clusters

### Cluster A — the `_cell_*` codegen seam (4 symbols, 1 file)

| Importer | Layer | Imports from | Layer | Symbols |
| --- | --- | --- | --- | --- |
| `projection/IoMap.jl:14` | projection (7) | `DocumentModule` | document (2) | `_cell_autowrap_ctor`, `_cell_property_accessors`, `_cell_kw_params`, `_cell_kwctor` |

This is the **documented downward private seam**: `@document` and `@iomap`
share the four Cell-struct expr-builders (auto-wrapping ctor, Cell-transparent
`getproperty`/`setproperty!`, kwctor). The exemption is written down in the
`DocumentModule` docstring, in `package/kernel/doc/document.md`
("Downward private seam"), and in
[plan/done/kernel-layered-architecture.md](../done/kernel-layered-architecture.md)
(P2 note). This plan retires that exemption.

### Cluster B — unexported `ReferenceModule` vocabulary (16 imports, 9 files)

`ReferenceModule` exports `ElementReference`, `PositionReference`,
`TypeReference`, `FunctionReference`, `ProjectionReference`,
`TextRectangularReference`, `ReferencePath`, `EmptyReferencePath` — but **not**
`ConcreteReferencePath`, `FieldReference`, `RangeReference`, `PointReference`,
`head`, `tail`, even though its own docstring lists the first four as the same
step/path vocabulary. This is an export-list omission, not intent: the same
unexported names are imported identically above the kernel too
(`base/main/projection/Filtering.jl`, `Copying.jl`, `Sorting.jl`,
`Searching.jl`, `DraggingProjection.jl`, `visual/main/text/TextToGraphics.jl`,
`tooltip/TooltipDecorator.jl`, …).

| Importer (layer) | Symbols | Actually used in file? |
| --- | --- | --- |
| `operation/OperationModule.jl` (operation) | `ConcreteReferencePath`, `FieldReference`, `RangeReference` | yes (in fragments) |
| `editor/Playback.jl` (editor) | `ConcreteReferencePath` | yes |
| `projection/ProjectionTemplate.jl` (projection) | `ConcreteReferencePath`, `FieldReference`, `RangeReference` | yes |
| `projection/generic/Focusing.jl` (projection) | `ConcreteReferencePath` | yes |
| `projection/generic/Reversing.jl` (projection) | `ConcreteReferencePath`, `RangeReference` | `RangeReference` is **dead** |
| `projection/higherorder/ReferenceDispatching.jl:15-17` (projection) | `ConcreteReferencePath`, `FieldReference`, `RangeReference`, `PointReference`, `head`, `tail` | **entire `ReferenceModule` import is dead** — no name from it appears in the module body |

## Plan

### 1. Export the missing reference vocabulary

Add `ConcreteReferencePath`, `FieldReference`, `RangeReference`,
`PointReference` to the `ReferenceModule` export list. Collision check across
every main package's export statements: none. This also repairs the same
latent internal-symbol imports in base/visual/domain for free.

`head` / `tail` are **not** exported: the `Projectured` umbrella mechanically
flattens every exported name of every submodule, and names this generic don't
belong in the flat API. They need no export either:

- the only kernel importer (`ReferenceDispatching.jl`) doesn't use them —
  delete the whole dead import (see step 2);
- the two visual-package importers (`TextToGraphics.jl`,
  `TooltipDecorator.jl`) can switch to `path.head` / `path.tail` when the rule
  is rolled out there — the accessors are one-line wrappers over the
  `@document`-backed struct fields, and *struct fields are public API* by the
  document contract (field names are the reference vocabulary).

### 2. Delete the dead imports

- `projection/higherorder/ReferenceDispatching.jl:15-17` — remove the entire
  `import ..ReferenceModule: …` statement (none of its 11 names is used).
- `projection/generic/Reversing.jl:12` — drop `RangeReference` from the list.

### 3. Sink the Cell-struct codegen into a cell-layer macro

> **Superseded by [cell-struct-macro.md](../done/cell-struct-macro.md)** (2026-07-08):
> the helpers move into a new exported `@cell_struct` macro (+ builder
> functions) in the cell layer; `@document`, `@iomap`, and `@projection` build
> on top of it. That plan also removes `@projection`'s duplicated inline copy
> of the same codegen, which option (d) below left untouched. The options
> analysis is kept for the record.

Options originally considered for cluster A:

- **(a) Fragment-merge** (the EventCase precedent): impossible —
  `DocumentModule` and `IoMapModule` live in different layers; one namespace
  would dissolve the layer boundary itself.
- **(b) Duplicate the ~45 lines of codegen in `IoMapModule`**: rejected;
  the builders are subtle (escaping, Cell-wrapping, kwctor forwarding) and the
  whole point of the seam was to keep them identical.
- **(c) Julia `public` marking** (repo runs 1.12): technically available, but
  since 1.11 `names(m)` includes `public` names, so the umbrella loop flattens
  them exactly like exports unless it grows a `Base.isexported` filter — a
  third visibility state bought us nothing here.
- **(d) — chosen — export them from `DocumentModule`, renamed without the
  underscore**: `cell_autowrap_ctor`, `cell_property_accessors`,
  `cell_kw_params`, `cell_kwctor`. They are a genuine seam, not an internal: any
  macro that builds a Cell-transparent struct (`@document`, `@iomap`, future
  ones) implements against these four by name. Exporting sits them next to the
  already-exported value protocol (`cell_kind`, `rekind`, `snapshot`, …), whose
  naming they match. The umbrella flat namespace gains four specific,
  collision-free names — consistent with its stated "convenience front-door,
  not a curated boundary" stance.

  Location stays `document/Document.jl`: the builders emit every symbol
  (`Cell`, `new`, `getfield`) as bare names resolved at the macro-expansion
  site, so they have no dependencies at all and moving them (e.g. down to the
  cell layer, arguably their concept) would be pure churn.

Mechanical changes: rename definitions + call sites in `document/Document.jl`,
retarget the import and call sites in `projection/IoMap.jl`, add the four names
to the `DocumentModule` export list.

### 4. Retire the private-seam exemption from the docs

- The `DocumentModule` docstring and `package/kernel/doc/document.md` changes
  are covered by [cell-struct-macro.md](../done/cell-struct-macro.md) (the seam
  disappears rather than being re-documented).
- `documentation/architecture-rules.md` — add the rule to the Enforcement
  section: *cross-layer imports may name only exported symbols; share private
  helpers via same-module fragments (EventCase precedent) or sink the seam
  below both users as exported API (`@cell_struct` precedent).*

### 5. Enforce it in the layering guard

Extend the shared `check_layering`
([package/kernel/test/layering/CheckLayering.jl](../../package/kernel/test/layering/CheckLayering.jl))
with a fifth check, mirroring the existing `layer_errors` shape:

- **Walker**: `collect_edges` currently keeps only the referenced module name;
  extend it to also keep the per-import symbol list (`import ..Mod: a, b` →
  `Mod => [a, b]`; plain `import ..Mod` → `Mod => []`, unconstrained) and to
  collect each module's `export` statements. Fragment imports/exports fold into
  the enclosing module exactly as deps do today. Normalize `var"@x"` to `@x`.
- **Checker**: `private_import_errors(entries, layers)` — for every importer
  under a declared layer folder, every symbol imported from a module in a
  *different* layer folder must be in that module's aggregated export set.
  Reuse the transitional `exempt_files` mechanism for packages that aren't
  clean yet.
- **Self-tests** in `test_layering_checkers()` alongside the existing ones.
- **Enable for the kernel** in `test_kernel_layering()` — green once steps 1–3
  land. Base/visual/domain enablement is a follow-up: run the check once per
  package, fix or exempt (step 1 already repairs the `ReferenceModule` cases;
  visual's `head`/`tail` imports switch to field access per step 1).

Known limitation, documented in the checker header: qualified private access
(`XxxModule._name` in code or macro output) is not caught — today's only
instances are same-module fragment self-references, and the import-header check
keeps the common path honest.

### Verification

- `test_kernel_layering()` (new check green, old four checks unchanged),
  then `test_kernel()`.
- Exports are purely additive for downstream packages; a
  `test_base()` / `test_visual()` sweep after the rename confirms nothing else
  referenced the old `_cell_*` names (repo grep says only `IoMap.jl` does).

## Execution checklist

- [ ] Export `ConcreteReferencePath`, `FieldReference`, `RangeReference`,
      `PointReference` from `ReferenceModule`.
- [ ] Delete the dead `ReferenceModule` import in `ReferenceDispatching.jl`;
      drop dead `RangeReference` from `Reversing.jl`.
- [x] Cluster A: execute [cell-struct-macro.md](../done/cell-struct-macro.md)
      (`@cell_struct` in the cell layer; `@document`/`@iomap`/`@projection`
      build on it; docs updated there).
- [ ] Docs for this plan's remainder:
      `documentation/architecture-rules.md` (the cross-layer export rule).
- [ ] `check_layering` check 5 (`private_import_errors`) + self-tests; enable
      in `test_kernel_layering()`.
- [ ] Verify: `test_kernel()`; spot-run `test_base()` / `test_visual()`.

## Out of scope

- **Same-layer private imports** (`cell/ReactiveCell.jl` ←
  `PerformanceCounterModule._perf`) — permitted by the rule.
- **Test/example packages** — white-box imports of main-package internals in
  `package/*/test` are a separate policy question.
- **Base/visual/domain enablement** of the new guard check — follow-up after
  the kernel is clean; step 1 and the `head`/`tail` field-access switch remove
  the violations already known there.
