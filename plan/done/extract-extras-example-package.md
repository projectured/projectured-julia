# Extract a separate example package for the heavy opt-in (C++ + ODBC) examples

> **Status: DONE** (2026-06-26, on `main`). `ProjecturedExample` no longer depends
> on `ProjecturedAdaptagrams` (native C++ shim) or `ProjecturedOdbc` (database
> driver); the examples that need them moved to a new opt-in
> `ProjecturedExtrasExample`. `ProjecturedExample` now precompiles with no native
> build and no database. Verified: base examples green (json 3566/3566,
> sql_syntax 648/648), DbCatalogToSql 27/27, and `graph_adaptagrams` renders
> 4668/4668 from the new package.

## The problem

`ProjecturedExample.jl` did `using ProjecturedOdbc` and `using ProjecturedAdaptagrams`
at module top level, and listed both in `[deps]`. So **every** consumer of
`ProjecturedExample` transitively required the native adaptagrams shim
(gitignored `.so`, absent in fresh worktrees) and the ODBC driver — which blocked
precompilation of `OmnetppPredExample` / `OmnetppPredTest` (and any worktree)
even though those tests touch no graphs or databases.

## Decision

A **single combined** `ProjecturedExtrasExample` package (chosen over two separate
ODBC/adaptagrams packages) holding *both* the ODBC and the native-graph examples.
Rationale: `dvdrental_relationship` needs **both** engines, so two packages would
have to cross-depend anyway; one package is fewer moving parts and one Manifest
entry for consumers. Deps: `Projectured`, `ProjecturedExample`, `ProjecturedOdbc`,
`ProjecturedAdaptagrams`. It reuses `ProjecturedExample`'s `Example` struct,
runners, and the engine-free shared builders (imported).

## What moved (→ `package/extras-example/`)

- **Whole files** (`git mv`): `document/Database.jl`, `document/DbCatalog.jl`,
  `projection/DbCatalog.jl`.
- **Split out** of base files:
  - `projection/Graph.jl` → the two `AdaptagramsEngine` projections
    (`make_graph_adaptagrams_projection_example`,
    `make_dvdrental_relationship_projection_example`). The engine-free
    `make_graph_projection_example` / `make_graph_document_example` stayed.
  - `projection/Sql.jl` → `make_sql_table_projection_example` (live `SqlToCellTable`
    query). The static SQL→syntax projections stayed.
- **Registry** (`Examples.jl`): the example consts `dbcatalog`,
  `dvdrental_catalog(_widget)`, `dvdrental_object(_json)`, `dvdrental_catalog_json`,
  `sql_table`, `graph_adaptagrams`, `dvdrental_relationship` — and their entries in
  the auto-tested `examples` vector. The new package has its own `examples` vector
  (the 6 sweep-safe ones) and keeps the fully-walked dvdrental views +
  `dvdrental_relationship` as consts only.

## What stayed in `ProjecturedExample`

`make_graph_document_example`, `make_graph_projection_example`,
`make_table/mixed_projection_example`, `make_syntax_widget_graphics`,
`make_database_instance_document_example` (engine-free connection spec),
`make_sql_document_example` + the static SQL projections, and `graph_example`.
These are imported by the extras package.

## Test-side fix

Only `setup_persons_table` (used by 3 opt-in `external/` live-DB tests) referenced
a moved builder. To avoid making `ProjecturedTest` depend on the native-pulling
extras package, `setup_persons_table` / `teardown_persons_table` were added as
local fixture helpers in `ProjecturedTest.jl` (they only use `ProjecturedOdbc`'s
`db_execute_raw` / `db_insert!`, already a direct dep). `ProjecturedTest` is
deliberately **not** a dependent of `ProjecturedExtrasExample`.

## Implementation steps (all done)

1. ✅ Scaffold `package/extras-example/` (Project.toml with fresh UUID
   `fab2bd8f-…`, module file including the moved sources + a registry `Examples.jl`).
2. ✅ Move whole files (`git mv`) and split `Graph.jl` / `Sql.jl`.
3. ✅ Strip `ProjecturedExample`: the two `using`s, the moved `include`s, the
   moved exports, the moved registry consts + `examples`-vector entries, and the
   two `[deps]`.
4. ✅ Register `ProjecturedExtrasExample` in the root `Project.toml`
   `[deps]`/`[sources]`; `Pkg.resolve()` updated `Manifest.toml`.
5. ✅ Add the `setup_persons_table` / `teardown_persons_table` helpers to
   `ProjecturedTest`.
6. ✅ Verify: `ProjecturedExample` precompiles with **no** ODBC/adaptagrams (83
   base examples); `ProjecturedExtrasExample` precompiles and its examples render
   (incl. the native `graph_adaptagrams`); base/projection test suites green; the
   `@projection_template` hygiene regression test still passes.

## Follow-ups (out of scope here)

- **Consumer Manifests**: downstream repos (e.g. `omnetpp-pred`) carry their own
  committed `Manifest.toml` pinning `ProjecturedExample`'s old dep graph. They pick
  up the lean `ProjecturedExample` on their next `Pkg.resolve()/instantiate()`;
  no projectured-julia change is needed, but those repos should re-resolve to drop
  the now-unnecessary native/ODBC transitive deps. This is exactly what unblocks
  worktree precompilation downstream.
- Automating the `ProjecturedAdaptagrams` native build (gitignored `.so`) is a
  separate concern; this plan only **isolates** the dependency.
- `ProjecturedExtrasExample` still requires a reachable database at load time (its
  `dvdrental_*` example consts construct eagerly, as before) — unchanged behaviour,
  just relocated out of the base package.
