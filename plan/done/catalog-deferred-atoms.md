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

- [x] Diagnose (empirical): only **`julia/nothing/syntax` repl** fails (1 fail) —
  `:insert` swaps `JuliaNothing → JuliaInsertion("")`, and the bare `JuliaNothingToSyntaxLeaf`
  has no `print_document(::JuliaNothingToSyntaxLeaf, _, ::JuliaInsertion, _)` → MethodError.
  **`julia/insertion` is fully green** (empty buffer doesn't commit-swap in the walk), and
  `julia/nothing/{text,graphics}` are green (the dispatching bridge reprojects the swap).
- [x] Fix — **catalog-level** (`Catalog.jl`), the principled choice: a self-modifying document
  (its own gestures change its type) can't be projected by a bare single-type leaf, so its
  **syntax variant uses the whole-tree dispatching projection** (what text/graphics already
  chain through). Added `_self_modifying(D)` (`D` is the domain's insertion `domain_insertion(D)`
  or its `nothing_document`), `is_syntax`, and the routing in `_atom_examples`
  (`path_sequences(doc, is_syntax)` instead of `_single_step`). Applies uniformly to all 5
  insertion/nothing atoms (julia + markdown/math/book insertion) — the others keep the bare leaf.
- [x] Register `julia/nothing` + `julia/insertion` atoms. **Full `test_catalog()` green (below).** ✅

## Verification

- Per item (all green, each run under the memory cap): `test_catalog(; domain=:filesystem)`
  → 1546 pass; `test_catalog(; domain=:sql)` → 6376 pass; `test_catalog(; domain=:julia)`
  → julia/nothing/syntax was the last holdout.
- **Final: full `test_catalog()` → 58913 pass / 0 fail / 0 error / 0 broken (1m09s).**
  **111 variant-entries = 37 atoms × 3 variants across 10 domains** (was 30 atoms → 90 entries);
  +7 atoms: `filesystem/file`, `sql/{all_columns,column_name,table_name,scalar_value}`,
  `julia/{nothing,insertion}`. No regressions in the other 30 atoms.
- All Julia runs under the memory cap:
  `systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 julia --project=. …`

## Notes / decisions

- **Two of the three deferred notes were partly stale.** SQL had *gained* a shared
  `read_intent = nothing` (not "no reader"), so its failure was an ambiguity, not a plain
  MethodError. And julia/insertion turned out **already green** — only julia/nothing failed.
  Reproducing first (before designing a fix) caught both, each time.
- **One recurring pattern across filesystem + sql:** a caret/edit on *projection-introduced*
  content (text with no input field) must be handled explicitly. Selection carets collapse to a
  bounded `proj(p, …)` introduced reference (so navigation stays bounded — the runaway the
  template's default fallback would cause); edits are declined. Declines must name the exact
  operation type — a catch-all `op` is ambiguous with `ReaderDefaults` / the template's typed
  readers and throws `MethodError` (world age `0x97ef` is the tell).
- **julia was structural, not a mapper bug:** a self-modifying document needs a *dispatching*
  projection; the fix is at the catalog (how the syntax variant is chosen), not in the domain.
  The `_self_modifying` predicate must compare with `<:` because `D` is the reactive type
  (`RJuliaNothing = JuliaNothing{…}`) while the domain traits return base types.
- Every run was under the `systemd-run … MemoryMax=12G` cap; no OOM or runaway occurred
  (the SQL and julia-nothing failures both reached *fewer* states, not more).
