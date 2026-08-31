# Catalog: every document type is an atom (no skipping; failures are `@test_broken`)

> **Status (2026-08-12): IN PROGRESS.** Workstreams 1 to 3 are done:
> `JsonObjectEntryToSyntaxNode` exists in
> [package/json/main/JsonToSyntax.jl](../../source/json/JsonToSyntax.jl);
> the catalog test lives at
> [package/projectured/test/projection/CatalogTest.jl](../../test/projectured/projection/CatalogTest.jl)
> with `test_catalog()` and a per-entry `@test_broken`/`@catalog-broken`
> mechanism. Workstream 4 (fix the `@test_broken` bugs) is still open: 14
> `@catalog-broken` comment groups remain in `CatalogTest.jl`, naming a bug
> list that has moved on from the one recorded below (for example, layouts and
> the widget composite printed through their own recursion, bare text spans
> under block-level `WordWrapping`, and `ReferenceStub`). Read the current list
> with `grep "@catalog-broken" package/projectured/test/projection/CatalogTest.jl`
> rather than the snapshot below; the pass/broken counts in the Result section
> were not re-measured for this audit.

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
- [x] 1. **JsonObjectEntry projection** — `JsonObjectEntryToSyntaxNode`; object delegates via
  `collection(:entries)`; `json/object_entry` is a real atom. (committed)
- [x] 2. **Catalog broken-registry** — `CatalogTest.jl` marks a failing entry `@test_broken` keyed
  on its signature; `@catalog-broken` comments = the bug list. (committed)
- [x] 3. **Re-add deferred + exhaustive coverage** — every node type across all domains is now an
  atom: json array/object/object_entry, yaml sequence/mapping, xml element/attribute, math (3),
  book chapter/list/book, markdown (heading/paragraph/list/emphasis/link/strong/code_block/image/
  list_item/quote/root), julia (17 nodes), sql (18 nodes). **~105 atoms → 315 entries.**
- [ ] 4. **Fix the @test_broken bugs** — the open bug list (`grep @catalog-broken`):
  - julia node repl reprint → `FieldError(Nothing, :output)` (binary_op, assignment, field_access,
    for_iterator, lambda, range, return, ternary, type_annotation, unary_op, using).
  - sql node `ChildrenIoMap` `read_intent` has no edit-gesture method (comparison, select_item,
    from_item, join_on_condition, joined_from_item, update_assignment, update_statement,
    column_definition, where_filter_condition).
  - under-typed `@reference` in a node backward map (filesystem/directory, sql/statement_list).
  - yaml/sequence graphics seed returns nothing; sql/where_filter_condition nav TypeError.

## Result
Full `test_catalog()`: **184455 pass / 0 unmarked Fail / 0 error / 466 broken** — every document type
is in the catalog; the 466 broken assertions are the tracked, visible bug list (workstream 4).
