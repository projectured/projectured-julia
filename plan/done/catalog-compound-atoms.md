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

## What landed — 19 compound atoms across every domain
- **json**: array, object · **yaml**: mapping · **xml**: element, attribute
- **math**: binary_operation, assignment, parenthesized · **book**: chapter, list
- **markdown**: heading, paragraph, list, emphasis, link
- **julia**: call, block, function · **sql**: select_statement

### Catalog machinery fix (the key enabler)
A compound's bare single-step **node** projection can't recurse into its children — a bare
`JsonArrayToSyntaxNode` on `JsonArray(JsonNumber(1))` calls `print_document(nothing, …, JsonNumber(1))`
→ MethodError. Generalized the syntax-variant routing (`Catalog.jl`): use the trivial single-step
only when its output is a bare `SyntaxLeaf` (`_single_step_leaf`); otherwise (compound, or
self-modifying) use the domain's whole-tree dispatching projection. Dispatching is always a valid
superset, so this only *widens* the choice.

### Genuine domain bug fixed (surfaced by a minimal compound)
- **xml/element**: `XmlElementToSyntaxNode`'s flat-fallback asserted `iomap.output::SyntaxNode`, but
  the template produces a `SyntaxConcatenation` (a sibling of `SyntaxNode` under `SyntaxSequence`).
  Fixed to `::SyntaxConcatenation`. (The `::SyntaxNode` form is *correct* for math/sql/book.)

### Deferred (6) — each surfaces a distinct **pre-existing** domain bug a minimal compound exposes;
real domain work (cf. `plan/done/catalog-deferred-atoms.md`), not a catalog change:
- **json/object_entry** — no standalone projection (a bare `JsonObjectEntry` only lives inside a
  `JsonObject`, already covered by `json/object`).
- **yaml/sequence** — graphics Ctrl+Home seed returns `nothing`.
- **filesystem/directory** — graphics click hits an under-typed `@reference` in the directory backward map.
- **julia/binary_op**, **julia/assignment** — repl walk throws `FieldError(Nothing, :output)`.
- **sql/comparison**, **sql/select_item** — bare node atom hits the `read_intent` catch-all ambiguity
  (same class as the SQL display leaves, now on the node stages).

## Phases
- [x] Phase 1 — json (array, object), yaml (mapping), xml (element, attribute)
- [x] Phase 2 — math (3), book (chapter, list); filesystem/directory deferred
- [x] Phase 3 — markdown (heading, paragraph, list, emphasis, link)
- [x] Phase 4 — julia (call, block, function), sql (select_statement); the rest deferred
- [ ] Final: full `test_catalog()` green; update `documentation/testing.md`; move plan to done.

All Julia runs under `systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 julia --project=. …`.

## Notes / decisions
- The generalized routing means a compound atom's syntax variant is the same dispatching projection
  its text/graphics variants chain through — so all three variants exercise the real node projection.
- "Keep it simple": one leaf child per compound; a representative subset for the ~20-node AST domains
  (julia, sql). The 6 deferred compounds each need a targeted domain fix; kept out to hold the catalog
  green, documented above so they're easy to pick up.
