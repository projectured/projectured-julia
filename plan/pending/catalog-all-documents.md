# Catalog: every document type is an atom (no skipping; failures are `@test_broken`)

Directive (2026-07-16): **all documents must be in the catalog — don't skip any.** A failing
catalog item is *valuable information* (it names a real bug) and must be fixed, not dropped.
This reverses the earlier "cover what works, defer the rest" stance from
[`catalog-compound-atoms.md`](../done/catalog-compound-atoms.md): the 6 deferred compounds come
back, coverage becomes exhaustive, and known failures are recorded as `@test_broken` (the
project's "known bug to fix" marker) so the suite stays green while the bug list stays visible.

Branch `catalog-all-documents` (worktree `projectured-julia-alldocs`), off `main`.

## Workstreams
1. **JsonObjectEntry gets its own projection.** `JsonObjectToSyntaxNode` currently *inlines* the
   `"key": value` entry via `collection(:entries) do e … end`. Extract `JsonObjectEntryToSyntaxNode`
   (renders one `"key": value`), switch the object to plain `collection(:entries)` (School A
   delegation), and register `JsonObjectEntry => JsonObjectEntryToSyntaxNode()` in the composite.
   Then `json/object_entry` is a real, projectable atom. Validate `test_json` + the json catalog.
2. **Catalog broken-registry.** Add a per-entry `@test_broken` mechanism to `CatalogTest.jl`
   (keyed by `entry.name` + tester) so a failing atom stays in the catalog, marked broken with a
   reason, without an unmarked `Fail`. Failures = the visible TODO list.
3. **Re-add the deferred atoms + go exhaustive.** Bring back yaml/sequence, filesystem/directory,
   julia/binary_op, julia/assignment, sql/comparison, sql/select_item — and add the *rest* of every
   domain's node types (all julia AST nodes, all sql nodes, all markdown/math/xml/book/yaml nodes).
   Nothing skipped.
4. **Fix the failures.** Each `@test_broken` entry is a bug to close. Start with the known-pattern
   ones (sql node `read_intent` ambiguity = the same fix as the sql display leaves), then the rest.

## Method
- Empirical per domain: add atoms → run `test_catalog(; domain=:X)` → fix, or mark `@test_broken`
  with a reason → commit.
- All Julia runs memory-capped:
  `systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 julia --project=. …`.

## Progress
- [ ] 1. JsonObjectEntry projection
- [ ] 2. Catalog broken-registry
- [ ] 3. Re-add deferred + exhaustive node coverage
- [ ] 4. Fix the failures (sql ambiguity, julia FieldError, filesystem @reference, yaml seed, …)
