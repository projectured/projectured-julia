# Cell layer — restructure for cohesion and guessability

**Status:** ✅ **Complete.** All changes landed on `main`: C-B (`7c956018`),
C-A + C-E (`c53d7051`), C-C (`51afa4db`), C-D Part 1 (toolkit → `cell_struct_*`)
and C-D Part 2 (protocol verbs → `set_cell_value!`/`set_cell_function!`/
`is_cell_up_to_date`). C-D was re-applied over intervening main work (widget/SQL/
text-caret commits) by re-running the mechanical rename, so it also caught the new
old-name occurrences those commits added. The four sealed kind files were edited
for C-D Part 2 with the user's go-ahead (rename only; they remain sealed).
Verified at each step: full-stack loads, the cell/toolkit tests, and the
kernel/base/visual/domain layering guards.

Scope: layer 1 of the kernel, `package/kernel/main/cell/`. The user asked four
questions — (Q1) should exported names carry `cell`/`Cell`? (Q2) is there a
better file organization? (Q3) `CellAccess` feels weird; (Q4) `Clock` doesn't
belong in the cell layer — and asked for a whole-layer review with a plan to
make it better structured and easier to follow. Backward compatibility is
explicitly *not* a constraint.

---

## 1. Current structure

The "cell layer" is actually **three modules spanning three dependency
heights**, all collapsed into one folder/layer:

```
PerformanceCounterModule   (PerformanceCounter.jl)   — instrumentation; the engine DEPENDS on it (loads first)
        ▲
CellModule                 (CellModule.jl, 7 fragments) — the engine + kinds + access + struct codegen
   ├─ AbstractCell.jl   — AbstractCell{T} base + is_up_to_date decl   [interface file]
   ├─ ReactiveCell.jl   — the pull-based reactive engine
   ├─ MutableCell.jl    — plain mutable box
   ├─ ImmutableCell.jl  — read-only wrapper
   ├─ CellAccess.jl     — unwrap_cell
   ├─ StructPlan.jl     — struct-definition parse (compile-time)
   └─ CellStruct.jl     — @cell_struct codegen (compile-time)
        ▲
ClockModule                (Clock.jl)                 — the animation clock; a CLIENT of the engine (imports it)
```

The arrows are real `using`/`import` edges: `ReactiveCell` imports
`PerformanceCounterModule`; `ClockModule` imports `CellModule`. So within "layer
1" there is a mini-DAG of height 3 — an instrumentation leaf *below* the engine,
and a client *above* it.

**Seal status** (from `CLAUDE.md`): 🔒 = `PerformanceCounter`, `AbstractCell`,
`ReactiveCell`, `MutableCell`, `ImmutableCell`, `Clock`. ⬜ (editable) =
`CellLayer.jl`, `CellModule.jl`, `CellAccess.jl`, `StructPlan.jl`,
`CellStruct.jl`.

**Consumer facts** (established by grep, decide what can move where):

- `CellModule` is imported by document, reference, selection, operation,
  projection layers (kernel) and by sql/graphics/text (higher packages).
- `ClockModule` is imported by exactly two kernel layers: **projection**
  (`PrinterContext` has a `clock::Clock` field) and **editor** — plus visual
  (`WidgetToGraphics`) and the video package above kernel. ⇒ Clock must stay at
  or below the projection layer, but imports only `CellModule`, so it can sink as
  low as **layer 2** — which is where C-C placed it (renumbering projection→12,
  editor→16, etc.).
- The struct-macro **toolkit free functions** (`struct_plan`, `cell_struct_exprs`,
  `required_count`, …) are used by the macro authors and a few helpers:
  `document/DocumentMacro.jl`, `document/DocumentCopy.jl`, `document/DocumentKind.jl`,
  `projection/IoMap.jl`, `projection/Projection.jl`, and `visual/syntax/Syntax.jl`.
- **⚠ Correction (discovered at execution time):** the `@cell_struct` **macro
  itself** is used *directly* by many more modules — so a two-module split (C-A)
  requires `using ..CellStructModule` in **9 modules across two packages**, not 3.
  The full set: kernel `ClockModule` (🔒 `Clock.jl`), `DocumentModule`,
  `ReferenceModule` (covers `ReferenceStep`/`ReferencePath` fragments),
  `IoMapModule`, `ProjectionModule`, `ProjectionReferenceModule`; visual
  `PointReferenceModule`, `TextRectangularReferenceModule`, `SyntaxModule`; plus a
  `ProjecturedVisual` re-export alias `const CellStructModule = …`, 3 test files
  (`CellStructTest`, `StructPlanTest`, `DocumentMacroTest`), and the cell-layer
  files. **One consumer, `Clock.jl`, is sealed** (it declares `@cell_struct struct
  Clock`), so C-A is *not* sealed-free, and it must be verified against a **visual**
  load, not just kernel.
- `unwrap_cell` is used at ~40 sites across 15 files. Reactive protocol verbs:
  `set_function!` 172 sites, `is_up_to_date` 70, `set_value!` 47.

---

## 2. Findings

### F1 — One module bundles two unrelated audiences (⇢ Q2)

`CellModule` mixes the **runtime reactive primitive** (kinds, read/write,
tracking, `unwrap_cell`) with a **compile-time struct-macro toolkit**
(`StructPlan`, `@cell_struct` codegen). These serve different readers at
different times: the first is called on the hot path at runtime; the second runs
only during macro expansion, and only three macros consume it. Bundling them
means a reader of the reactive engine wades through AST-rewriting codegen and
vice versa. They are two *slices*, not one.

### F2 — `CellAccess.jl` is a vaguely-named one-liner (⇢ Q3)

The file holds a single function, `unwrap_cell`. Its own header explains *why* it
is separate: `AbstractCell.jl` is the layer's interface file and
[AR-INTERFACE-DECLARES-ONLY](../../documentation/architecture-requirements.md#ar-interface-declares-only)
forbids method bodies there, so a function with a body cannot live beside the
type it dispatches on. That reasoning is sound — the weirdness is the **name**
(`CellAccess` promises a broad "access" surface but delivers one accessor) and
its **isolation** (a one-function file wedged between the kinds and the codegen).

### F3 — `Clock` is a client of the engine, mis-filed as part of it (⇢ Q4)

The current docs justify Clock's placement by *dependency height* ("everything at
cell dependency height"). But by **cohesion**, Clock is a *client*: it `using
..CellModule`s and builds a `@cell_struct` on top of it, exactly as a document or
projection would. It is architecturally a layer *above* the engine that happens
to be filed *inside* it. The user's instinct is correct on cohesion grounds; the
docs' defence is a dependency-height argument, not a cohesion one.

### F4 — The struct-toolkit's exported vocabulary is split-brained (⇢ Q1)

Half the toolkit carries a consistent prefix (`cell_struct_exprs`,
`cell_struct_kw_params`, `cell_struct_kwctor`, `cell_struct_positional_ctors`),
the other half is bare and generic (`struct_plan`, `add_plan_field!`,
`retype_fields!`, `declared_value_types`, `field_cell_kinds`, `cell_kind_of`,
`required_count`, `trailing_default_count`, `struct_macro_default`). Under bare
`using ..CellModule` **every export lands in every consumer's scope**
([AR-QUALIFIED-EXTENSION](../../documentation/architecture-requirements.md#ar-qualified-extension)
+ `test_export_collisions`), so generic names like `required_count` /
`trailing_default_count` / `declared_value_types` are both collision-prone and
poorly self-describing out of context.

### F5 — `cell.md` "Public surface" is out of sync with the real exports (doc bug)

`package/kernel/doc/cell.md` lists `cell_struct_autowrap_ctor` and
`cell_struct_property_accessors` as public, but `CellModule` does **not** export
them (they are internal helpers of `cell_struct_exprs`); and it omits
`cell_struct_positional_ctors` and `struct_macro_default`, which *are* exported.
Violates
[AR-HONEST-DOCS](../../documentation/architecture-requirements.md#ar-honest-docs).
Fix regardless of the rest.

### F6 — Naming-convention drift in the layer's own filenames (observation)

Per [naming.md](../../package/kernel/doc/naming.md), the folder-owning module is
`<Concept>Module.jl` and the contract fragment it includes first is
`<Concept>.jl`/`Interface.jl`. Here the contract fragment is `AbstractCell.jl`
(named for the type, not the role) — defensible, because `Cell` is already the
`ReactiveCell{Any}` alias so a bare `Cell.jl` would mislead. Noted, not
necessarily actioned; relevant if the kinds are regrouped (C-B).

---

## 3. Proposed changes

Ranked by value/cost. Each is independently approvable. "Sealed?" flags whether
execution needs the user to unseal a file first.

### C-A — Split `CellModule` into engine + struct-macro toolkit (⇢ Q2). ✅ Done (`c53d7051`).

Make the compile-time codegen its own module (a second slice of the cell layer):

- `cell/CellModule.jl` — keeps the runtime engine: `AbstractCell`, the three
  kinds, `unwrap_cell`. Exports `Cell`, `AbstractCell`, `ReactiveCell`,
  `MutableCell`, `ImmutableCell`, `set_value!`, `set_function!`, `is_up_to_date`,
  `unwrap_cell`.
- `cell/CellStructModule.jl` — **new** module `using ..CellModule`, includes
  `StructPlan.jl` + `CellStruct.jl`, exports the `@cell_struct` seam and the
  `StructPlan` toolkit. Codegen emits `Cell`/`new`/`getfield` as bare names that
  resolve in the *caller's* scope, so this split is transparent to emitted code.
- `cell/CellLayer.jl` — include `CellStructModule.jl` after `CellModule.jl`.
- Update the 3 consumers to add `using ..CellStructModule`:
  `document/DocumentMacro.jl`, `projection/IoMap.jl`, `projection/Projection.jl`.

**Sealed?** **Yes — one file.** The engine/toolkit files themselves are editable
(`StructPlan.jl`, `CellStruct.jl`, `CellModule.jl`, `CellLayer.jl` + new
`CellStructModule.jl`), but every `@cell_struct` consumer must add `using
..CellStructModule`, and one such consumer is the sealed `Clock.jl` (a one-line
import addition, content otherwise unchanged). See the ⚠ correction in §1 for the
full 9-module / cross-package consumer set. **Guard/docs:** check whether
`CheckLayering.jl` needs the new module registered; rewrite the `cell.md`
"Layer structure" + CellModule/CellStruct sections; add `cell/CellStructModule.jl`
to the `CLAUDE.md` seal list. **Risk:** moderate (cross-package, one sealed file);
verify with a real `using ProjecturedKernel` **and** `using ProjecturedVisual`
load (guards can be green while `using` fails — [[guards-are-not-a-load-check]])
plus `test_cell()`.

*Lighter alternative* if the user prefers one module: keep `CellModule` but move
fragments into `cell/kind/` and `cell/struct/` subfolders for readability only.

### C-B — Rehome/rename `unwrap_cell`, retire `CellAccess.jl` (⇢ Q3). ✅ Done (`7c956018`).

`unwrap_cell` stays in the engine module (C-A) as the cross-kind runtime
accessor. Rename the file to state its one job precisely — proposed
`cell/CellUnwrap.jl` (or fold it into a small `cell/CellProtocol.jl` that also
holds the `is_up_to_date(::Vector{Cell})` convenience method, giving the "cross-
kind operations over `AbstractCell`" file real content instead of one line). The
existence of a dedicated file is *correct* (AR-INTERFACE-DECLARES-ONLY keeps it
out of `AbstractCell.jl`); only the name needs sharpening.

**Sealed?** No — `CellAccess.jl` is editable. If we choose to fold in the
`Vector{Cell}` method, that method currently lives in the sealed `ReactiveCell.jl`
— folding it out needs permission; leaving it put avoids that.

### C-C — Promote `Clock` out of the cell layer (⇢ Q4). ✅ Done.

Landed: `Clock.jl` + `ClockTest.jl` moved to a new `clock/` layer (kernel layer
2), `ClockLayer.jl` added, `CellLayer.jl` trimmed, `ProjecturedKernel.jl`
include order + all layer-number comments renumbered (event→3 … editor→16), the
`ProjecturedKernelTest.jl` `layers` vector + `ClockTest` include path updated, the
`CLAUDE.md` seal list given a new Layer 2 section with everything below
renumbered, and the layer numbers swept across ~11 kernel/`documentation/` guides
(the plan's "renumber is two places" estimate was wrong — layer numbers are cited
throughout the docs). Verified: kernel + visual load, `test_clock` 15/15, the
layering guard 10/10. The scope note below is retained for the record.

Give the animation clock **its own thin layer directly above cell** (new layer 2,
`clock/`, module `ClockModule` unchanged), sinking it as low as its single
dependency (`CellModule`) allows —
[AR-FRAMEWORKS-SINK](../../documentation/architecture-requirements.md#ar-frameworks-sink).
This makes the layer numbering honest: the engine is layer 1, its first client is
layer 2. `using ..ClockModule` resolves the same in `PrinterContext`/`Editor`, so
**consumers do not change**; only the include tree, the seal-list, and the guard.

- `ProjecturedKernel.jl`: insert `include("clock/ClockLayer.jl")` at position 2;
  renumber the trailing layer comments (event→3, …, editor→16). Layer *numbers*
  live only here and in the `CLAUDE.md` seal list, so the renumber is two places.
- `git mv package/kernel/main/cell/Clock.jl package/kernel/main/clock/Clock.jl`;
  new `clock/ClockLayer.jl` fragment includes it.
- `CLAUDE.md`: move the `Clock` entry into a new "Layer 2 — clock" section (its
  🔒 stays); shift subsequent layer numbers.
- Move `test/cell/ClockTest.jl` → `test/clock/ClockTest.jl`
  (AR-PARALLEL-TRIADS).
- `cell.md`: remove Clock from the cell-layer section; point to a clock doc.

**Sealed?** Yes — `Clock.jl` moves (content unchanged, but a sealed file is being
relocated, and the seal list is edited). Needs explicit permission.
**Risk:** low functionally (pure relocation), moderate in churn (layer
renumber). **Trade-off to weigh:** a one-module layer is thin (cf. the gesture
layer, ~2 files) — defensible as genuine cross-cutting "time" infrastructure, but
if the user finds a new layer heavy, the fallback is to keep Clock at cell height
in its **own top-level concern** (a sibling module, not inside `cell/`'s engine
story) and rename the layer's self-description away from "the reactive cell
engine." Recommend the dedicated layer.

### C-D — Put `cell` in every external name (⇢ Q1). ✅ Done.

The user chose to carry `cell` in *every* exported name, one way or another —
this supersedes the original "targeted, leave the protocol verbs alone"
recommendation in §4. Two parts with different cost/seal profiles.

**Part 1 — struct-macro toolkit** (moves to `CellStructModule` under C-A).
Editable files (`StructPlan.jl`, `CellStruct.jl`), ~3 consumer files. Uniform
`cell_struct_` prefix, matching the existing
`cell_struct_exprs`/`cell_struct_kwctor` builders (drops the redundant `plan`,
since the module is `CellStructModule` and the type is `CellStructPlan`):

| current | updated (cell in name) |
|---|---|
| `StructPlan` | `CellStructPlan` |
| `struct_plan` | `cell_struct_plan` |
| `add_plan_field!` | `add_cell_struct_field!` |
| `retype_fields!` | `retype_cell_struct_fields!` |
| `declared_value_types` | `cell_struct_value_types` |
| `field_cell_kinds` | `cell_struct_field_kinds` |
| `required_count` | `cell_struct_required_count` |
| `trailing_default_count` | `cell_struct_trailing_default_count` |
| `struct_macro_default` | `cell_struct_macro_default` |
| `@cell_struct`, `cell_struct_exprs`, `cell_struct_kw_params`, `cell_struct_kwctor`, `cell_struct_positional_ctors`, `cell_kind_of` | keep — already carry `cell` |

**Part 2 — reactive protocol verbs** (stay in `CellModule`). Defined in the
**sealed** kind files, so this part needs unsealing and is **high churn**:

| current | updated | defined in | call sites |
|---|---|---|---|
| `set_value!` | `set_cell_value!` | `ReactiveCell.jl` 🔒 | 47 |
| `set_function!` | `set_cell_function!` | `ReactiveCell.jl` 🔒 | 172 |
| `is_up_to_date` | `is_cell_up_to_date` | `AbstractCell.jl` 🔒 (decl) + the three kind files 🔒 | 70 |

The cell-kind **types** (`Cell`, `AbstractCell`, `ReactiveCell`, `MutableCell`,
`ImmutableCell`) and `unwrap_cell` already carry `cell` — no change.

**Exceptions that cannot take `cell`:** `peek` extends `Base.peek` — renaming it
breaks the Base-generic extension, so it stays `peek`, namespaced by `Base`;
`cell_struct_autowrap_ctor` / `cell_struct_property_accessors` are unexported
internals (and already carry `cell`).

**Sealed?** Part 1 no; **Part 2 yes** — four sealed files (`AbstractCell.jl`,
`ReactiveCell.jl`, `MutableCell.jl`, `ImmutableCell.jl`). Get per-file permission
before Part 2. Update `cell.md`; run `test_export_collisions` (umbrella) after —
no new name may clash with another module's export.

### C-E — Fix the `cell.md` public-surface list (F5). ✅ Done (folded into `c53d7051`).

Correct the "Public surface" lines to match the real `CellModule` export list;
drop the internal helpers, add the actually-exported ones. Trivial, sealed-free.

---

## 4. Direct answers to the four questions

- **Q1 — rename all exports to carry `cell`/`Cell`?** **Yes — the user chose to
  put `cell` in every external name** (see C-D). The initial recommendation was a
  *targeted* pass (toolkit only, leaving the protocol verbs, since a mechanical
  prefix reads slightly worse and `set_function!`/`is_up_to_date`/`set_value!`
  are heavily used — 172/70/47 sites, against
  [AR-NAMING-LAW](../../documentation/architecture-requirements.md#ar-naming-law)'s
  guessability-first principle); the user overrode that in favour of a uniform
  `cell` marker across the whole interface. Accepted trade-off: the protocol-verb
  renames (C-D Part 2) are high-churn and touch sealed kind files. The types and
  `unwrap_cell` already comply; `peek` is the one exception (a `Base` extension).
- **Q2 — better file organization?** **Yes (C-A):** split the runtime engine from
  the compile-time struct codegen into two modules/slices. Optionally group the
  four kinds (C-B). This is the biggest "easier to follow" win and costs no
  sealed files.
- **Q3 — `CellAccess` weird?** **Agreed (C-B):** the dedicated file is *right*
  (interface-purity forces `unwrap_cell` out of `AbstractCell.jl`); the **name**
  is the problem. Rename to state its one job, optionally give it real siblings.
- **Q4 — `Clock` doesn't belong in the cell layer?** **Agreed (C-C):** it's a
  *client* of the engine, not part of it. Promote it to its own thin layer just
  above cell. Hard constraint discovered: `PrinterContext` couples to `Clock`, so
  it must stay ≤ projection layer; imports only `CellModule`, so layer 2 is its
  lowest legal home.

---

## 5. Recommended sequencing

1. **C-B** — rename `CellAccess.jl` → `CellUnwrap.jl`. ✅ **Done** (commit
   `7c956018`). Sealed-free.
2. **C-A + C-D Part 1 together** — the module split and the toolkit rename touch
   the same editable files. **Now requires unsealing `Clock.jl`** (one import
   line) and touches 9 modules across kernel+visual (see §1 ⚠). Fold the C-E doc
   correction into C-A's `cell.md` rewrite. Verify: real `using ProjecturedKernel`
   **and** `using ProjecturedVisual` load + `test_cell()` + `test_kernel_layering()`.
3. **C-D Part 2** (protocol-verb renames) — needs the four sealed kind files
   unsealed; high churn (~289 sites). Run `test_export_collisions` after.
4. **C-C** (Clock promotion) — last, and only after the user unseals `Clock.jl`.
   Independent of the rest.

C-A now needs `Clock.jl` unsealed; steps 3 and 4 each need per-file unseal
permission too. Only C-B was fully sealed-free.

Each step is its own commit; update `cell.md`, `CLAUDE.md` seal list, and the
layering guard in the same commit as the change that moves files.

---

## 6. Risks & constraints

- **Sealed files:** **C-A** touches one (`Clock.jl`, a one-line `using
  ..CellStructModule` addition — `Clock` is a `@cell_struct` consumer); **C-D
  Part 2** touches four (`AbstractCell.jl`, `ReactiveCell.jl`, `MutableCell.jl`,
  `ImmutableCell.jl`); **C-C** touches one (`Clock.jl`, relocation). Only C-B and
  C-E are sealed-free. Get explicit per-file permission before C-A, C-D Part 2,
  and C-C.
- **Guards are not a load check** ([[guards-are-not-a-load-check]],
  [[clean-load-is-not-a-migration-check]]): after any module split, do a real
  `using ProjecturedKernel` and scan for "undeclared at import time" warnings —
  a green guard + green `test_cell()` can still hide a broken `using`.
- **Export collisions:** the toolkit rename must not introduce a name another
  module already exports; `test_export_collisions` (umbrella) is the check.
- **AR-STABLE-FOUNDATIONS** freezes the reactive *design*, not the file layout —
  this restructure re-litigates neither the pull-based engine nor any invariant.
- **Concurrent-checkout hygiene** ([[concurrent-checkout-commit-explicit-paths]]):
  commit explicit paths; the user may be editing the same checkout.
- Do the implementation in a dedicated worktree per the global workflow.

---

## 7. Decisions (locked with the user, 2026-07-16)

1. **C-A → two modules.** Split into `CellModule` (engine + kinds + unwrap) and a
   new `CellStructModule` (`@cell_struct` + `StructPlan` toolkit). Not the
   subfolder-only variant.
2. **C-C → Clock gets its own thin layer 2** (`clock/`), above cell. Accept the
   layer renumber and the sealed-`Clock.jl` relocation (permission required at
   execution time).
3. **C-D → put `cell` in every external name** (not just the toolkit),
   superseding the original targeted recommendation. Part 1 (toolkit,
   `cell_struct_*`) rides with C-A on editable files; Part 2 (protocol verbs
   `set_cell_value!` / `set_cell_function!` / `is_cell_up_to_date`) touches the
   sealed kind files and needs permission.

C-B (rename `CellAccess.jl` → `CellUnwrap.jl`) and C-E (fix `cell.md` public
surface) stand as recommended. Nothing implemented yet — this remains a planning
document until execution is requested.
