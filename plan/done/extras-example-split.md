# Extras-example split (opt-in example packages)

> **Status: done.** `package/extras-example` (`ProjecturedExtrasExample`) split
> into `package/odbc/example`, `package/adaptagrams/example`,
> `package/tulip/example`. The cross-engine `dvdrental_relationship` keeps its
> DB-derived document in odbc/example and its native-layout projection in
> adaptagrams/example, so adaptagrams/example depends on odbc/example. Verified
> by parse-check + static symbol/path resolution (the native ODBC / Adaptagrams
> C++ / Tulip engines can't precompile offline — same root-env-only constraint
> the old extras package had, so full `using` load needs the proper env).

Replace the single `package/extras-example` (`ProjecturedExtrasExample`) with
**per-opt-in example packages nested under their engine's directory**, so each
opt-in package owns its examples the way each runtime package owns its triad:

```
package/odbc/example        ProjecturedOdbcExample
package/adaptagrams/example  ProjecturedAdaptagramsExample
package/tulip/example        ProjecturedTulipExample
```

`package/extras-example` is deleted. This makes the example DAG end in three
opt-in example leaves instead of one aggregate, matching the triad rule
(`package/<name>/example`).

## The cross-engine snag and how it's resolved

`dvdrental_relationship` needs **both** Odbc (its document is derived from a
live DB catalog) and Adaptagrams (its projection is laid out by the native
engine). A pure 3-way split is therefore impossible; the cut that keeps every
source file whole:

- The relationship **document** builder (`make_dvdrental_relationship_graph_document_example`)
  lives in `document/DbCatalog.jl` → **odbc/example**, exported.
- The relationship **projection** builder lives in `projection/Graph.jl`
  beside `graph_adaptagrams` → **adaptagrams/example**.
- So **adaptagrams/example depends on odbc/example** for that one document.
  Both native-graph examples stay together; `projection/Graph.jl` is not split.

## File → package

| file | → package |
| --- | --- |
| document/Database.jl | odbc/example |
| document/DbCatalog.jl | odbc/example |
| projection/DbCatalog.jl | odbc/example |
| projection/Sql.jl | odbc/example |
| projection/Graph.jl | adaptagrams/example |
| projection/Layout.jl | tulip/example |

## Example → package

- **odbc/example**: dbcatalog, dvdrental_catalog, dvdrental_object, sql_table
- **adaptagrams/example**: graph_adaptagrams, dvdrental_relationship
- **tulip/example**: constraint_layout_tulip

Each package exports its own `<engine>_examples` registry slice + re-exports the
`Example` harness runners (so `using ProjecturedOdbcExample` is self-sufficient,
as `using ProjecturedExtrasExample` was). There is no combined `examples` sweep
list — it spanned all three engines and had no single home; nothing external
consumed it.

## Deps (mirroring extras, which had no `[sources]` — root-env-resolved)

- odbc/example: Projectured, ProjecturedExample, ProjecturedOdbc
- adaptagrams/example: Projectured, ProjecturedExample, ProjecturedAdaptagrams,
  **ProjecturedOdbcExample**
- tulip/example: Projectured, ProjecturedExample, ProjecturedTulip

Root `Project.toml` [deps]+[sources] and `Manifest.toml`: drop
ProjecturedExtrasExample, add the three (paths `package/<engine>/example`).

## Also update

- The comment references that point at `ProjecturedExtrasExample` as the home
  of the opt-in variants (domain/example projection/Sql.jl, projection/Graph.jl,
  Examples.jl; visual/example projection/Layout.jl; projectured/example
  ProjecturedExample.jl; projectured/test ProjecturedTest.jl) → name the new
  per-engine package.
- `documentation/architecture-rules.md` triad diagram (example DAG tail) and
  `architecture.md` opt-in inventory.

## Verification

These packages depend on native/heavy engines (ODBC driver, the Adaptagrams
C++ shim, Tulip+MathOptInterface) and, like the umbrella, resolve only through
the root env — no standalone offline load. Verify: every new file parses; the
root Project.toml/Manifest and every path resolve; a names/registry static
check. Full `using` load needs the proper environment (DB + built shim).

## Out of scope

Adding *tests* to the opt-in packages; changing the examples themselves.
