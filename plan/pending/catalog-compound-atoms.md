# Catalog compound atoms: minimal non-empty non-leaf documents, all domains

Follow-up to [`plan/done/catalog-deferred-atoms.md`](../done/catalog-deferred-atoms.md).
The generated catalog was **leaf-only**; the node/compound projections (`JsonArrayToSyntaxNode`,
`JsonObjectToSyntaxNode`, …) were exercised only by the big curated `json` example. Add a
**minimal, non-empty instance of each domain's primary compound (non-leaf) document types** as
catalog atoms, so the node stages get the catalog's breadth (printer/reader/repl/nav across
syntax/text/graphics) in isolation.

Branch `catalog-compound-atoms` (worktree `projectured-julia-compound`), off `main`.

## Principle
- Each atom is the **smallest non-empty** instance of a compound type — one leaf child, no more
  (`JsonArray(JsonNumber(1))`, `JsonObject("a" => JsonString("x"))`).
- Names: `domain/<compound>` alongside the existing leaf names (e.g. `json/array`, `json/object`).
- Big AST domains (julia, sql — ~20 node types each) get a **representative** set of the core
  compounds, not every node — noted per domain; easy to extend later.

## Proposed set (adjust per reproduction)
- **json**: array, object, object_entry
- **yaml**: sequence, mapping
- **xml**: element, attribute
- **math**: assignment, binary_operation, parenthesized
- **filesystem**: directory
- **book**: chapter, list
- **markdown**: heading, list, emphasis, link  (representative block + inline)
- **julia**: call, binary_op, assignment, function  (representative)
- **sql**: comparison, select_item, select_statement  (representative)

## Method (per domain, empirical — same as the deferred-atoms work)
1. Add minimal makers (derive constructors from the curated `example/document/*.jl` + domain structs).
2. Register the atoms.
3. `test_catalog(; domain=:X)` under the memory cap; fix any node-stage caret/reader gaps.
4. Commit per domain (or per phase).

Node projections are already exercised by curated examples, so most should pass; minimal
single-child instances may still surface edge cases the big examples don't.

## Phases
- [ ] Phase 1 — data domains: json, yaml, xml
- [ ] Phase 2 — math, filesystem, book
- [ ] Phase 3 — markdown (representative)
- [ ] Phase 4 — julia, sql (representative)
- [ ] Final: full `test_catalog()` green; update `documentation/testing.md`; move plan to done.

All Julia runs under `systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 julia --project=. …`.

## Notes / decisions
_(filled in as work proceeds)_
