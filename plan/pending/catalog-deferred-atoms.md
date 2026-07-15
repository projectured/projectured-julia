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

- [ ] Add `make_filesystem_file_document_example` (a bare `FileSystemFile`).
- [ ] Reproduce the failure with `test_catalog(; domain=:filesystem)`.
- [ ] Fix `FileSystemFileToSyntaxLeaf` mappers to handle the introduced-token caret.
- [ ] Register `AtomicDocument(:filesystem, "file", …)`; confirm catalog green.

### 2. sql/* — readers for the leaf stages
`SqlXxxToSyntaxLeaf` are read-only (v1): no `read_intent`, so reader/repl/navigation
`MethodError`. Needs `read_intent` on the leaf stages + a `SqlToSyntax` bridge into the
projection graph, then the sql atoms drop in.

- [ ] Audit which SQL leaf stages exist and what a bound/introduced caret needs.
- [ ] Add `read_intent` (+ backward mappers where missing).
- [ ] Add `SqlToSyntax` bridge to `BRIDGES` if reachability to text/graphics is wanted.
- [ ] Register the sql atoms; confirm catalog green.

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
