# Catalog deferred atoms: filesystem/file, sql/*, julia/nothing + julia/insertion

Follow-up to [`plan/done/atomic-example-catalog.md`](../done/atomic-example-catalog.md).
Phase D deferred four atoms because each needs **real domain work**, not a catalog change.
This plan closes them one at a time; each is independently shippable and keeps
`test_catalog()` green.

Branch: `catalog-deferred-atoms` (worktree `projectured-julia-catalog-deferred`), off `main`
at `a3b980b6`.

## The three items

### 1. filesystem/file — introduced-token caret round-trip
`FileSystemFileToSyntaxLeaf` renders `" " * basename(f.pathname)` — **introduced** text
(leading space + derived basename), not `bound`. Its mappers are the identity, so a graphics
caret `.value{N}` passes straight to a `FileSystemFile` (which has `.pathname`, no `.value`)
→ `SelectionMismatch`. The introduced text is not directly editable (basename is derived), so
a caret on it should **name the whole file node** (`∅`) via `ProjectionReference`, not descend
into a nonexistent field.

- [x] Add `make_filesystem_file_document_example` (a bare `FileSystemFile`, qualified
  `FileSystemModule.FileSystemFile` — the type is not exported by its module).
- [x] Add a `FileSystemToSyntax` bridge to `Catalog.jl`'s `BRIDGES` so the atom reaches
  text/graphics (it had none — only json/xml/yaml/julia/markdown/math/book did).
- [x] Reproduce: `test_catalog(; domain=:filesystem)` → 7 fail / 1 error (`SelectionMismatch`
  `::FileSystemFile.value{N}` on `:home`/`:end`/mouse carets + nav).
- [x] Fix `FileSystemFileToSyntaxLeaf`:
  - **Own selection cell** (deferred-iomap forward-map, like `FileSystemDirectoryToSyntaxNode`)
    instead of sharing `f.selection` — the shared cell couldn't carry a `proj(...)` caret that
    `SyntaxLeafToText` would render.
  - `map_reference_backward`: `∅` → identity; `::SyntaxLeaf.value{k}` caret →
    `proj(p, ::SyntaxLeaf.value{k})` (introduced, since the basename has no file field).
  - `map_reference_forward`: unwrap `proj(p, out)` → `out` (the leaf caret).
  - `read_intent(::ReplaceStringRangeOperation) = nothing` — decline edits (non-editable).
    **Must be type-specific**, not a catch-all `op`: a bare `op` is *ambiguous* with
    `ReaderDefaults`' `read_intent(::Projection, iomap, ::ReplaceStringRangeOperation)` → MethodError.
- [x] Register `AtomicDocument(:filesystem, "file", …)`. **`test_catalog(; domain=:filesystem)`
  → 1546 pass / 0 fail / 0 error / 0 broken.** ✅

### 2. sql/* — readers for the leaf stages
`SqlXxxToSyntaxLeaf` are read-only (v1): no `read_intent`, so reader/repl/navigation
`MethodError`. Needs `read_intent` on the leaf stages + a `SqlToSyntax` bridge into the
projection graph, then the sql atoms drop in.

- [x] Audit: the 7 leaf stages are `@projection_template` opaque display leaves (RuleIoMap),
  sharing one `read_intent(::Union{7 leaves}, ::RuleIoMap, op) = nothing`. The note was
  **partly stale** — the failure isn't a plain "no reader" MethodError, it's an **ambiguity**:
  the `op::Any` decline collides with the template's typed readers (gesture
  `::Union{KeyPress,KeyDown}`, `ClaimedGesture`, and `ReaderDefaults`' `::ReplaceStringRangeOperation`).
  Never triggered before because sql leaves were always embedded; a *bare* atom receives raw
  gestures directly → `MethodError` on every reader/repl/nav event.
- [x] Reproduce: `test_catalog(; domain=:sql)` → **2228 fail** (all the ambiguity MethodError,
  world age `0x97ef`); printer passes, nav reaches 0 states (seed throws — NOT a runaway).
- [x] Fix (`SqlToSyntax.jl`): **remove** the `op::Any` catch-all; add for the 7-leaf Union
  `_SqlDisplayLeaf`:
  - `read_intent(::_SqlDisplayLeaf, ::RuleIoMap, ::ReplaceSelectionOperation)` — try the
    template backward, else collapse to a bounded flat offset `proj(p, {flat})` via
    `_syntax_to_flat` (exactly XmlElementToSyntaxNode). Keeps nav **bounded** (the memory's
    runaway risk) and enumerable.
  - `map_reference_forward(::_SqlDisplayLeaf, ::RuleIoMap, ref)` — pass introduced refs through.
  - Gestures fall to the template reader; text edits are declined by `ReaderDefaults`' opaque-leaf
    rule — so no `op::Any` decline is needed (that was the ambiguity).
- [x] Add a `SqlToSyntax` bridge to `BRIDGES` (text/graphics reachability) + 4 atoms
  (all_columns / column_name / table_name / scalar_value). **`test_catalog(; domain=:sql)`
  → 6376 pass / 0 fail / 0 error / 0 broken.** ✅

### 3. julia/nothing + julia/insertion — bare-leaf reprint of a type-swapped node
Bare leaves that type/commit-swap their node type on edit; the bare projection can't reprint
the swapped type (only the full pipeline dispatches it). Needs the bare leaf to tolerate /
reproject the swapped type, or the atom to carry the dispatching projection.

- [ ] Diagnose the swap: what type does the edit produce, and why the bare leaf can't reprint.
- [ ] Decide fix vs. atom-projection choice; implement.
- [ ] Register the julia atoms; confirm catalog green.

## Verification
- Per item: `test_catalog(; domain=:<domain>)` green, plus the domain's own suite
  (`test_filesystem_to_syntax()`, `test_sql*()`, `test_julia*()`) unaffected.
- Final: full `test_catalog()` green (0 fail/error/broken), count grows by the added atoms × 3.
- All Julia runs under the memory cap:
  `systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 julia --project=. …`

## Notes / decisions
_(filled in as work proceeds)_
