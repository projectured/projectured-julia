# DbCatalog

Models the PostgreSQL catalog tree as a Projectured document hierarchy, enabling hierarchy-expanding projections over live database metadata.

## Document hierarchy

```
DbCatalogConnection → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn
```

`DbCatalogDocument` is the common abstract supertype. Each struct holds a typed reference to its parent, giving every node a direct path back to the adapter. `DbCatalogConnection` additionally stores `host`, `port`, and `adapter`. `DbCatalogColumn` additionally stores `data_type`. All nodes carry a `selection` reference.

Constructors are plain wrappers — no side effects. `Base.show` is a one-liner per type.

## Catalog query API

Four functions on `DatabaseAdapter`, implemented for `PostgresDatabaseAdapter`:

| Function | Returns | SQL source |
|---|---|---|
| `db_catalog_databases(adapter)` | `Vector{String}` | `pg_database` (non-template only) |
| `db_catalog_schemas(adapter, database)` | `Vector{String}` | `pg_namespace` (user schemas only) |
| `db_catalog_tables(adapter, schema)` | `Vector{String}` | `pg_tables` |
| `db_catalog_columns(adapter, schema, table)` | `Vector{NamedTuple}` | `information_schema.columns` |

`db_catalog_columns` returns `(name, data_type)` named tuples ordered by `ordinal_position`.

## Projections

Four read-only primitive projections in `DbCatalogToChildrenModule`. Each `projection_print` wraps the catalog call in a lazy `CellVector` thunk and returns a `SimpleIoMap`. The adapter is resolved by walking up the parent chain. `projection_read` and reference mapping are no-ops.

| Projection | Input → Output |
|---|---|
| `DbCatalogConnectionToChildren` | `DbCatalogConnection` → `CellVector{DbCatalogDatabase}` |
| `DbCatalogDatabaseToChildren` | `DbCatalogDatabase` → `CellVector{DbCatalogSchema}` |
| `DbCatalogSchemaToChildren` | `DbCatalogSchema` → `CellVector{DbCatalogTable}` |
| `DbCatalogTableToChildren` | `DbCatalogTable` → `CellVector{DbCatalogColumn}` |

## Tests

Six read-only live-DB tests in `DbCatalogTest.jl`. Skip gracefully when PostgreSQL is unavailable. Run with `test_db_catalog()`.

Fixture: `database=projectured_test`, `schema=public`, `table=persons`, columns `name text` and `age integer`. Tests check for presence of known names — additional schemas, tables, or columns do not cause failures.

| Test | Assertion |
|---|---|
| T1 | `"projectured_test"` is in `db_catalog_databases` result |
| T2 | `"public"` is in `db_catalog_schemas` result |
| T3 | `"persons"` is in `db_catalog_tables("public")` result |
| T4 | columns of `public.persons` include `name::text` and `age::integer` |
| T5 | `Base.show` one-liners for all five document types |
| T6 | `DbCatalogConnectionToChildren` `projection_print` returns a `CellVector{DbCatalogDatabase}` |

## Next step: projection hierarchy tests

Four live-DB tests, one per hierarchy level that has children. Each test builds the document chain from `DbCatalogConnection` down to the level under test, calls `projection_print` with the matching projection, collects the `CellVector` output, and asserts the expected child document is present.

The document chain is built explicitly using constructors — no projection is invoked for the ancestor levels, only for the level being tested. Each test is independent.

| Test | Input document | Projection | Expected child |
|---|---|---|---|
| P1 | `DbCatalogConnection(adapter)` | `DbCatalogConnectionToChildren` | a `DbCatalogDatabase` whose `name` is `"projectured_test"` |
| P2 | `DbCatalogDatabase(conn, "projectured_test")` | `DbCatalogDatabaseToChildren` | a `DbCatalogSchema` whose `name` is `"public"` |
| P3 | `DbCatalogSchema(db, "public")` | `DbCatalogSchemaToChildren` | a `DbCatalogTable` whose `name` is `"persons"` |
| P4 | `DbCatalogTable(schema, "persons")` | `DbCatalogTableToChildren` | a `DbCatalogColumn` whose `name` is `"name"` and `data_type` is `"text"`, and one whose `name` is `"age"` and `data_type` is `"integer"` |

Each test collects `iomap.output` into a vector, verifies all elements are the correct document type, and uses `any(d -> d.name == expected, children)` (or equivalent) to assert presence.

**P5 — full hierarchy expansion.** A single end-to-end test that walks all four projection levels in sequence, using the output of each step as the input document for the next. At every level the expected child is located by name and passed down.

Steps:
1. `conn = DbCatalogConnection(adapter)` → `DbCatalogConnectionToChildren` → collect databases → `db = find("projectured_test")` → assert `db isa DbCatalogDatabase`
2. `DbCatalogDatabaseToChildren` on `db` → collect schemas → `schema = find("public")` → assert `schema isa DbCatalogSchema`
3. `DbCatalogSchemaToChildren` on `schema` → collect tables → `table = find("persons")` → assert `table isa DbCatalogTable`
4. `DbCatalogTableToChildren` on `table` → collect columns → assert a `DbCatalogColumn` with `name="name"` and `data_type="text"` is present, and one with `name="age"` and `data_type="integer"` is present

Each intermediate result is asserted before proceeding. The test fails fast if any level produces wrong types or the expected node is absent.
