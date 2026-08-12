# Cell layer — Interface/Defaults rename

> **Status (2026-08-12): DONE.** Every change list item is verified in place:
> `package/kernel/main/cell/CellInterface.jl` and `CellDefaults.jl` exist,
> `CellModule.jl` includes them, `documentation/architecture-requirements.md`
> has `AR-CITE-EXCEPTIONS-ONLY`, and `CLAUDE.md`'s kernel inventory lists
> `CellInterface.jl` as sealed and `CellDefaults.jl` as not yet sealed. Ready
> to move to `plan/done/`.

Restructure the cell layer's contract files to match the backend layer's
`BackendInterface.jl` + `BackendDefaults.jl` shape, discovered during the seal
review of `cell/CellModule.jl`.

## Motivation

`CellUnwrap.jl` was a file named after a single function, and the cell layer's
interface file was named `AbstractCell.jl` (after its type) rather than by role.
The other layers with an interface split name the pair by role
(`BackendInterface.jl`/`BackendDefaults.jl`).

## Findings that shaped the design

- **Universal cell protocol** = `c[]` (`Base.getindex`), `peek` (`Base.peek`),
  `is_cell_up_to_date`. Of these, only `is_cell_up_to_date` is a cell-module
  generic that can be bodiless-declared; `c[]`/`peek` are `Base` generics
  (a qualified bodiless `function Base.getindex end` is a Julia syntax error —
  AR-INTERFACE-DECLARES-ONLY), so they are documented in the `AbstractCell`
  docstring and implemented per kind. **No additional all-cells generic exists
  to add.**
- The writes (`set_cell_value!`, `set_cell_function!`, `setindex!`) are **not
  universal** — `ImmutableCell` is read-only, `set_cell_function!` is
  reactive-only — so they stay with their owning kind, not the shared contract.
- The duplicated `peek(c)=c[]` and `is_cell_up_to_date(::X)=true` in
  `MutableCell.jl`/`ImmutableCell.jl` are **deliberately not lifted** into
  defaults: per `BackendDefaults.jl`'s own philosophy ("force a `MethodError`,
  don't fabricate a result"), a silent default would hand a future reactive-ish
  kind the wrong answer. The sealed kind files are therefore untouched.
- `unwrap_cell` *is* a legitimate Defaults resident: an interface generic with a
  single default implementation — declared in the interface, body in Defaults —
  exactly the `get_pointer_position` shape.

## Changes

- [x] `git mv AbstractCell.jl → CellInterface.jl` (was sealed 🔒 → re-opens ⬜).
      Keep `AbstractCell{T}` + docstring + `function is_cell_up_to_date end`;
      add a bodiless `function unwrap_cell end` (docstring moved up here).
- [x] `git mv CellUnwrap.jl → CellDefaults.jl`. Keep the `unwrap_cell(x)=…` body
      (default impl of the declared generic); header/docstring trimmed to a
      short comment mirroring `BackendDefaults.jl`.
- [x] `CellModule.jl` — update the two `include` lines.
- [x] `ProjecturedKernelTest.jl` — `interface_files` map: `cell/AbstractCell.jl`
      → `cell/CellInterface.jl`.
- [x] `package/kernel/doc/cell.md` — layer diagram + interface-file prose.
- [x] `CLAUDE.md` — rename the two inventory entries in place
      (`CellInterface.jl` flips 🔒→⬜; `CellDefaults.jl` stays ⬜).
- [x] `documentation/architecture-requirements.md` — added a new rule
      **AR-CITE-EXCEPTIONS-ONLY** (cite an AR ID in source only to flag an
      exception, never to announce compliance), surfaced by this review; the two
      cell files therefore name their interface/impl split in plain words and
      cite no rule.

## Not done here

- The sealed `ReactiveCell.jl`/`MutableCell.jl`/`ImmutableCell.jl` are untouched.
- Re-audit + re-seal of `CellInterface.jl` happens in the ongoing seal pass.
