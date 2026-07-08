# `@cell_struct` — sink the transparent-Cell struct codegen to the cell layer

> **Status: done (2026-07-08).** All code, test, and doc changes below are in
> place. The implementing environment had no Julia binary (network policy
> blocked fetching one), so verification there was static only — the
> layering-guard logic replayed green (include-reachability, topo order,
> layer indices) and the cross-layer `_cell_*` import is gone; the test suite
> was then run and confirmed green outside that environment before this plan
> was closed.
>
> Chosen resolution for "cluster A" of
> [kernel-cross-layer-internal-imports.md](../pending/kernel-cross-layer-internal-imports.md)
> (supersedes that plan's step 3, which proposed exporting the helpers from
> `DocumentModule` in place).

## Motivation

Three kernel macros generate the same thing — a struct whose fields are
transparent reactive `Cell`s, auto-wrapped on construction, with optional
initial values — and today they relate to one copy of the codegen in three
different, all-wrong ways:

- **`@document`** (`document/Document.jl`) *hosts* the four expr-builders
  (`_cell_autowrap_ctor`, `_cell_property_accessors`, `_cell_kw_params`,
  `_cell_kwctor`) — but since the kind-parameterized stem rework
  ([plan/done/cell-kind-documents.md](cell-kind-documents.md)) it
  generates its own parametric stem, fast-path ctor and uniform accessors, and
  actually uses only `_cell_kw_params` / `_cell_kwctor` (Document.jl:293-296).
  The autowrap/accessor builders it still hosts have exactly one consumer: the
  layer-7 module below.
- **`@iomap`** (`projection/IoMap.jl:14`) *imports all four privately* across
  five layers (projection ← document) — the kernel's last cross-layer
  internal-symbol import, currently excused as the "documented downward
  private seam".
- **`@projection`** (`projection/Projection.jl:188`) carries a **third, fully
  duplicated inline copy** — auto-wrap ctor, if-chain accessors, keyword ctor
  — importing nothing and sharing nothing. A fix to the codegen lands twice or
  not at all.

The concept references only `Cell`. It is a cell-layer concept; its home in
the document layer is historical (it grew inside `@document` and was lent
sideways). Sink it.

## Design

### The macro

New `CellModule` fragment `cell/CellStruct.jl` defining an exported,
noun-named declarative macro (per the naming rule in
`package/kernel/doc/naming.md` — "@cell_struct" reads as *here is a
cell-struct definition*):

```julia
@cell_struct struct T [<: Super]
    a                    # bare field
    b::Vector{Int}       # typed field
    c::Float64 = 1.0     # typed field with an initial value
end
```

generating exactly what `@iomap`/`@projection` expand to today:

- **Cell wrap** — every field form (`f`, `f::T`, `f[::T] = v`) becomes a
  `::Cell` field; declared value types are kept as documentation only.
- **Auto-wrapping inner ctor** — `T(vals…)` wraps each non-Cell value in
  `Cell(v)`; Cells of any kind pass through unchanged.
- **Transparent accessors** — `obj.f` reads through the cell
  (`getfield(obj, :f)[]`), `obj.f = v` writes through; raw cells stay
  reachable via `getfield`.
- **Optional initial value support** — when ≥ 1 default is declared, a
  keyword constructor à la `Base.@kwdef` (defaulted fields are optional
  keywords, the rest required), forwarding into the positional ctor so the
  Cell wrapping is defined in exactly one place.
- **No supertype injection** — the struct keeps whatever `<: Super` the
  caller wrote (or none). Each building macro injects its own default
  supertype *before* delegating; that is the macro-specific part.

### Implementation shape — one function, thin macro

The macro body is a plain function, and the function is the composition seam:

```julia
cell_struct_exprs(structdef) -> Expr(:block, structdef′, getprop, setprop, [kwctor])
macro cell_struct(structdef); esc(cell_struct_exprs(structdef)); end
```

`cell_struct_exprs` composes the four builders, which move from
`document/Document.jl` and drop their underscore (they are exported API now):
`cell_autowrap_ctor`, `cell_property_accessors`, `cell_kw_params`,
`cell_kwctor`. `CellModule` exports the macro, the function, and the four
builders — the builders are the documented seam for macro authors who reuse
*parts* (that is `@document`, below). Delegating through the function rather
than emitting a nested `@cell_struct` macrocall keeps expansion single-pass
and sidesteps nested-hygiene reasoning; the emitted symbols (`Cell`, `new`,
`getfield`) stay bare names resolved at the caller, exactly as today.

Behavior change: **none**. The emitted code is byte-for-byte today's `@iomap`
expansion. (Any divergence discovered between `@projection`'s inline copy and
the shared builders during the move is a latent bug — fix it in the shared
copy and note it in the commit message.)

### The three macros on top

- **`@iomap`** shrinks to: default the supertype to `IoMap` when none is
  written, then `esc(cell_struct_exprs(structdef))`. Its import line swaps
  `import ..DocumentModule: _cell_*` (cross-layer, non-exported) for
  `import ..CellModule: cell_struct_exprs` (cross-layer, exported, layer 7 →
  layer 1 — always downward).
- **`@projection`** shrinks the same way (default supertype `Projection`,
  delegate), deleting its ~90-line duplicate.
- **`@document`** keeps its kind-parameterized stem — the parametric
  `Foo{C1<:AbstractCell,…}` header, fast-path auto-wrap ctor, `R`/`I`/`M`
  kind aliases and typed kind ctors, Rule Y positional-default ctors, Rule C
  `CellVector` sugar. That machinery is deliberate, recent
  (cell-kind-documents.md), and Rule Y is known precompile-fragile (see the
  warning in
  [discovered-example-catalog.md](../pending/discovered-example-catalog.md)); it is not
  touched. `@document` builds on the cell layer by importing the two builders
  it actually uses — `cell_kw_params`, `cell_kwctor` — from `..CellModule`
  instead of hosting them.

After the move, `document/Document.jl` hosts no codegen builders at all, and
the `DocumentModule` ↔ `IoMapModule` codegen edge disappears entirely — the
"Downward private seam" exemption is retired, not re-documented.

### Considered and rejected

- **Sink the kind-parameterized stem too** (make `@document` a thin wrapper
  over a parametric mode of `@cell_struct`): conceptually attractive — the
  R/I/M kinds are cell-layer vocabulary — but IoMaps and Projections have no
  use for kind aliases or `rekind`, Rule C names `CellVector` (base-package
  vocabulary that must stay above), and `@document` is load-bearing across
  every domain plus precompile-fragile in Rule Y. Revisit only if a second
  kind-parameterized consumer ever appears.
- **Sink Rule Y** (trailing positional defaults) as part of "initial value
  support": generic in spirit, but the implementation interleaves per-arity
  `CellVector` variants; a clean extraction needs a variant-hook callback with
  one caller. Leave it in `@document` with a pointer comment.
- **Emit a nested `@cell_struct` macrocall** from `@iomap`/`@projection`:
  works, but adds a second expansion layer and hygiene surface for zero
  benefit over the function call.
- **Export the helpers from `DocumentModule` where they lie** (the previous
  plan's step 3): fixes the visibility violation but leaves a cell-layer
  concept in the document layer and does nothing for `@projection`'s
  duplicate.

### Layering and enforcement

All three edges point at layer 1 and name only exported symbols, so the
planned guard check 5 (`private_import_errors`, see
kernel-cross-layer-internal-imports.md step 5) goes green for the kernel with
**no exemptions** — the private-seam carve-out never needs to be encoded in
the guard.

The umbrella flat namespace gains `@cell_struct`, `cell_struct_exprs`, and the
four builder names — specific, collision-free (checked against every main
package's export lists), and consistent with the umbrella's uncurated
front-door stance.

## Execution checklist

- [x] `cell/CellStruct.jl` (fragment of `CellModule`): move the four builders
      from `document/Document.jl`, rename `_cell_*` → `cell_*`, add
      `cell_struct_exprs` and `@cell_struct`; include from `CellModule.jl`;
      add to `CellModule`'s export list and module-docstring surface summary.
- [x] `projection/IoMap.jl`: `@iomap` = supertype default + delegate; replace
      the `..DocumentModule: _cell_*` import with
      `..CellModule: cell_struct_exprs`.
- [x] `projection/Projection.jl`: `@projection` = supertype default +
      delegate; delete the duplicated inline codegen; add the
      `..CellModule: cell_struct_exprs` import.
- [x] `document/Document.jl`: delete the four builder definitions and the
      "Shared Cell-struct codegen" comment block; import
      `cell_kw_params`, `cell_kwctor` from `..CellModule`; update the
      fragment-header comment.
- [x] `document/DocumentModule.jl`: remove the "Downward private seam"
      paragraph from the docstring.
- [x] Docs: `kernel/doc/cell.md` (new `@cell_struct` section: surface,
      builders-as-seam, who builds on it), `kernel/doc/document.md` (retire
      the "Downward private seam" section; note `@document` imports the kw
      builders from the cell layer), `documentation/macros.md` (add
      `@cell_struct`; note `@document`/`@iomap`/`@projection` build on it),
      `documentation/architecture-rules.md` (update the seam-pattern
      precedent list: share struct codegen by sinking it below both users,
      not by private import).
- [x] Tests authored: `test/cell/CellStructTest.jl` driving `@cell_struct`
      directly (wrap, transparent read/write, raw-cell passthrough via
      `getfield`, keyword ctor with defaults / required keywords, explicit
      supertype), wired into `test_kernel()` and exported.
- [x] Tests executed: `test_cell_struct()` and `test_kernel()`; expansion
      parity for the heavy users via `test_base()`, `test_visual()`,
      `test_domain()` (the three macros expand in every domain). *(Run green
      outside the implementing environment, which had no Julia binary.)*
- [x] Update
      [kernel-cross-layer-internal-imports.md](../pending/kernel-cross-layer-internal-imports.md):
      cluster A is resolved by this plan (its step 3 and the matching
      checklist item defer here); steps 1–2 (ReferenceModule exports, dead
      imports) and 5 (guard check) are unchanged.

## Out of scope

Unchanged from kernel-cross-layer-internal-imports.md: same-layer private
imports (`_perf`), test/example-package white-box imports, and
base/visual/domain guard enablement.
