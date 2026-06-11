# LibPQ Go To Hell (ODBC Migration)

Replace the PostgreSQL-specific `LibPQ.jl` dependency with ODBC-based database
connectivity. LibPQ wraps the native `libpq` C library, binding the project to
PostgreSQL and requiring the PostgreSQL client libraries installed at the OS level.
ODBC is a universal standard: drivers exist for PostgreSQL, SQL Server, MySQL,
Oracle, SQLite, and more; on Windows the driver manager is built-in; on
Linux/macOS unixODBC suffices. A single `OdbcDatabaseAdapter` replaces
`PostgresDatabaseAdapter` and makes the adapter layer genuinely multi-database.

---

## Files Affected

| File | Change |
|---|---|
| `program/Project.toml` | Remove `LibPQ`, add `ODBC` |
| `Project.toml` (root) | Remove `LibPQ` direct dev dependency |
| `program/Manifest.toml` | Regenerate via `Pkg.rm` — removes `LibPQ`, `LibPQ_jll`, orphaned transitive deps |
| `Manifest.toml` (root) | Regenerate via `Pkg.rm` — same as above |
| `program/src/external/Database.jl` | Main rewrite — see phases below |
| `program/src/external/DatabaseTabular.jl` | Drop `import LibPQ`, switch cursor API |
| `program/src/projection/primitive/DatabaseTableToTabularGrid.jl` | Drop `import LibPQ`, switch cursor API, rename adapter import |
| `program/src/projection/primitive/DbCatalogTableToTabularGrid.jl` | Drop `import LibPQ`, switch cursor API, `$1` → `?` in UPDATE |
| `program/src/Projectured.jl` | Rename `PostgresDatabaseAdapter` → `OdbcDatabaseAdapter` |
| `test/src/external/DatabaseTest.jl` | Update `_make_test_adapter` |
| `test/src/external/DatabaseTabularTest.jl` | Update adapter construction |
| `test/src/external/DbCatalogTest.jl` | Update adapter construction |
| `test/src/external/DbCatalogJsonTest.jl` | Update adapter construction |

---

## Design Decisions

### Adapter rename: `PostgresDatabaseAdapter` → `OdbcDatabaseAdapter`

The new concrete type:

```julia
mutable struct OdbcDatabaseAdapter <: DatabaseAdapter
    dsn::String                         # ODBC connection string
    rowid_column::String                # configurable; no universal ctid equivalent
    _conn::Union{Nothing, ODBC.Connection}
end

OdbcDatabaseAdapter(; dsn::AbstractString,
                      rowid_column::AbstractString="rowid") =
    OdbcDatabaseAdapter(String(dsn), String(rowid_column), nothing)
```

PostgreSQL users pass the ODBC connection string and opt in to `ctid`:

```julia
OdbcDatabaseAdapter(
    dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
        "Database=mydb;Uid=user;Pwd=pass;",
    rowid_column="ctid")
```

### Connection

```julia
db_connect!(adapter)  →  adapter._conn = ODBC.Connection(adapter.dsn)
db_close!(adapter)    →  DBInterface.close(adapter._conn); adapter._conn = nothing
db_alive(adapter)     →  try DBInterface.execute(adapter._conn, "SELECT 1"); true; catch false
db_rowid_column(adapter) → adapter.rowid_column
```

### Cursor API and column extraction

ODBC.jl's `DBInterface.execute` returns an `ODBC.Cursor` which supports
`Tables.jl`. Replace the two LibPQ-specific private helpers:

```julia
# was: String[String(n) for n in LibPQ.column_names(result)]
_col_names(cursor) = String.(propertynames(cursor))

# _materialize_rows is unchanged — row[i] positional indexing still works
```

### Parameterized placeholder syntax

LibPQ uses PostgreSQL-style `$1, $2, …`; ODBC uses standard `?` repeated
positionally. `_build_select` builds raw-string WHERE clauses (no bind params),
so it is unaffected. `db_insert!` and `db_update!` must change:

```julia
# db_insert! — was: "$1, $2, ..."
placeholders = join(fill("?", length(cols)), ", ")

# db_update! — was: "col = $1, col = $2, ..."
set_clause = join(["\"$(c)\" = ?" for c in cols], ", ")
```

`db_execute_raw` passes `params` to `DBInterface.execute(conn, sql, params)` —
the caller is responsible for using `?` in their SQL.

### DML row counts

`LibPQ.num_affected_rows(result)` → `DBInterface.rowcount(cursor)`.
`DBInterface.rowcount` is part of the DBInterface.jl 2.3+ contract; ODBC.jl
implements it via `ODBC.API.SQLRowCount`. If a driver returns `-1` (unknown)
the functions return that sentinel rather than masking it.

### Catalog queries

Replace PostgreSQL-specific system-catalogue queries with standard SQL.

**`db_catalog_databases`** — `pg_database` has no universal equivalent.
Use `information_schema`:

```sql
SELECT DISTINCT table_catalog
FROM information_schema.tables
ORDER BY table_catalog
```

This returns the catalog name(s) the connection can see and works in PostgreSQL,
SQL Server, and MySQL. Drivers that don't support multi-catalog will return a
single entry.

**`db_catalog_schemas`** — replace `pg_namespace`:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name NOT LIKE 'pg_%'
  AND schema_name <> 'information_schema'
ORDER BY schema_name
```

**`db_catalog_tables`** — replace `pg_tables`:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = ?
  AND table_type = 'BASE TABLE'
ORDER BY table_name
```

**`db_catalog_columns`** — already uses `information_schema.columns`; no change.

---

## Phase 1 — Complete TOML Cleanup

### `program/Project.toml`

Remove:
```toml
LibPQ = "194296ae-ab2e-5f79-8cd4-7183a0a5a0d1"
```

Add:
```toml
ODBC = "be6f12e9-ca4f-5eb2-a339-a4f995cc0291"
```

Remove any `LibPQ` entry from `[compat]` if present.

### Root `Project.toml`

The workspace root `Project.toml` carries `LibPQ` as a direct dev dependency
(used when loading `Projectured` interactively). Remove:

```toml
LibPQ = "194296ae-ab2e-5f79-8cd4-7183a0a5a0d1"
```

### `program/Manifest.toml` and root `Manifest.toml`

**Do not edit Manifest files manually.** They are machine-generated and contain
three LibPQ-related entries that must all be purged together:

1. `[[deps.LibPQ]]` — the package block itself (version 1.18.0, git-tree-sha1 …)
2. `[[deps.LibPQ_jll]]` — the native C library JLL wrapper
3. The `"LibPQ"` string inside `[[deps.Projectured]].deps` (line 433 in current Manifest)

The correct approach is to run `Pkg.rm("LibPQ")` followed by `Pkg.instantiate()`
in each package context after the `Project.toml` edits. This also cascades-removes
LibPQ-exclusive transitive dependencies that become orphaned:
`Decimals`, `DocStringExtensions`, `Infinity`, `Intervals`, `IterTools`,
`LayerDicts`, `Memento`, `OffsetArrays`, `SQLStrings`, `UTCDateTimes`,
`TimeZones`, `TZJData`, `Scratch`, `Mocking`, `InlineStrings`, `RecipesBase`.
(`CEnum` stays because `SimpleDirectMediaLayer` also depends on it.)

Run from the Julia REPL in each context:
```julia
# In program/ context:
using Pkg; Pkg.activate("program"); Pkg.rm("LibPQ"); Pkg.add("ODBC"); Pkg.instantiate()

# In root context:
using Pkg; Pkg.activate("."); Pkg.rm("LibPQ"); Pkg.instantiate()
```

---

## Phase 2 — `program/src/external/Database.jl`

1. Replace `import LibPQ` with `import ODBC`.
2. Update the module docstring — remove LibPQ UUID, reference ODBC UUID.
3. Update the `db_rowid_column` docstring — remove PostgreSQL `ctid` hardcoding;
   note it is now a constructor parameter.
4. Replace the `PostgresDatabaseAdapter` struct and constructor with
   `OdbcDatabaseAdapter` as specified in Design Decisions above.
5. Rewrite `db_connect!`, `db_close!`, `db_alive`, `db_rowid_column`.
6. Rewrite `_col_names` to use `propertynames(cursor)`.
7. Rewrite `db_query(RawDatabaseResult)` and `db_execute_raw(RawDatabaseResult)`
   to use `DBInterface.execute`.
8. Rewrite `db_insert!`, `db_update!`, `db_delete!` with `?` placeholders and
   `DBInterface.rowcount`.
9. Rewrite `db_catalog_databases`, `db_catalog_schemas`, `db_catalog_tables`
   with `information_schema` queries. `db_catalog_columns` is unchanged.
10. Update `export` — replace `PostgresDatabaseAdapter` with `OdbcDatabaseAdapter`.

---

## Phase 3 — `program/src/external/DatabaseTabular.jl`

1. Remove `import LibPQ`.
2. Change `import ..DatabaseModule: PostgresDatabaseAdapter, db_query` →
   `import ..DatabaseModule: OdbcDatabaseAdapter, db_query`.
3. In `db_query(adapter::PostgresDatabaseAdapter, ...)` rename dispatch type to
   `OdbcDatabaseAdapter`.
4. Replace `LibPQ.execute(adapter._conn, sql)` with
   `DBInterface.execute(adapter._conn, sql)`.
5. Replace `LibPQ.column_names(result)` with `String.(propertynames(result))`.
6. Row iteration `for row in result` and `row[i]` access are unchanged.

---

## Phase 3b — Projection Primitives

Two projection files bypass the `DatabaseAdapter` API and call `LibPQ` directly.

### `program/src/projection/primitive/DatabaseTableToTabularGrid.jl`

1. Remove `import LibPQ`.
2. Change `import ..DatabaseModule: PostgresDatabaseAdapter, db_update!, db_insert!` →
   `import ..DatabaseModule: OdbcDatabaseAdapter, db_update!, db_insert!`.
3. In `_query_with_ctid`: replace `LibPQ.execute(adapter._conn, sql)` with
   `DBInterface.execute(adapter._conn, sql)` and
   `String[String(n) for n in LibPQ.column_names(result)]` with
   `String.(propertynames(result))`.
4. Remove the "LibPQ access" mention from the module docstring.
5. `evaluate_operation` bodies call `db_update!` / `db_insert!` (already
   adapter-agnostic) — no change needed.

### `program/src/projection/primitive/DbCatalogTableToTabularGrid.jl`

1. Remove `import LibPQ`; add `import DBInterface` (needed for `DBInterface.execute`).
2. In `_query_with_ctid`: same cursor-API changes as above — replace
   `LibPQ.execute` with `DBInterface.execute` and
   `LibPQ.column_names` with `propertynames`.
3. In `evaluate_operation(DbCatalogUpdateOperation)`: change
   `SET \"$(op.column)\" = \$1` → `SET \"$(op.column)\" = ?` and
   `LibPQ.execute(op.adapter._conn, sql, Any[op.new_value])` →
   `DBInterface.execute(op.adapter._conn, sql, [op.new_value])`.
4. Note: `WHERE ctid = '$(op.ctid)'::tid` uses the PostgreSQL `::tid` cast.
   This is passed through transparently by the PostgreSQL ODBC driver and
   requires no change now; it remains intentionally PostgreSQL-specific (same
   as `rowid_column="ctid"`).

---

## Phase 4 — `program/src/Projectured.jl`

In the `using .DatabaseModule:` block, replace `PostgresDatabaseAdapter` with
`OdbcDatabaseAdapter`. Do the same in the `export` block.

---

## Phase 5 — Tests

### `test/src/external/DatabaseTest.jl`

Replace `_make_test_adapter`:

```julia
function _make_test_adapter()
    OdbcDatabaseAdapter(
        dsn=get(ENV, "TEST_ODBC_DSN",
                "Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
                "Database=projectured_test;" *
                "Uid=$(get(ENV, "PGUSER", "postgres"));" *
                "Pwd=$(get(ENV, "PGPASSWORD", "projectured"));"),
        rowid_column="ctid")
end
```

Update the skip message from "PostgreSQL unavailable" to "ODBC DSN unavailable".

### Other test files

Replace every `PostgresDatabaseAdapter(dbname=..., user=..., password=...)` with
`OdbcDatabaseAdapter(dsn=..., rowid_column="ctid")` using equivalent connection
strings. These calls appear in:

- `test/src/external/DbCatalogJsonTest.jl` (five call sites)
- `test/src/external/DbCatalogTest.jl`
- `test/src/external/DatabaseTabularTest.jl`

---

## Prerequisite: ODBC Driver Installation

The test environment must have the PostgreSQL ODBC driver installed.

**Windows**: download the `psqlodbc` MSI from postgresql.org; the driver
registers itself as `PostgreSQL Unicode` automatically.

**Linux**: `apt install odbc-postgresql unixodbc` (or distro equivalent), then
register in `/etc/odbcinst.ini`:

```ini
[PostgreSQL Unicode]
Driver = /usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so
```

**macOS**: `brew install psqlodbc unixodbc`.

For CI, set `TEST_ODBC_DSN` in the environment; live-DB tests skip automatically
when the DSN is unreachable (existing `skip_if_no_db` guard).

---

## Implementation Steps

1. Edit all `Project.toml` files and run `Pkg.rm` / `Pkg.instantiate` to
   regenerate both `Manifest.toml` files (Phase 1).
2. Rewrite `program/src/external/Database.jl` (Phase 2).
3. Update `program/src/external/DatabaseTabular.jl` (Phase 3).
4. Update the two projection primitive files (Phase 3b).
5. Update `program/src/Projectured.jl` exports (Phase 4).
6. Update all test call sites (Phase 5).
7. **Full grep clean-check** — zero results expected for each:
   ```
   grep -r "LibPQ" program/src/
   grep -r "LibPQ" program/Project.toml
   grep -r "LibPQ" Project.toml
   grep    "LibPQ" program/Manifest.toml
   grep    "LibPQ" Manifest.toml
   grep -r "LibPQ" test/src/
   ```
8. Run offline tests: `test_database_no_db()` requires no live DB.
9. Run live-DB tests with a PostgreSQL ODBC DSN.

---

## Future Extensions

- **SQLite adapter** — `OdbcDatabaseAdapter(dsn="Driver=SQLite3;Database=/path/to/file.db;", rowid_column="rowid")`. Zero new code; just a different DSN.
- **SQL Server / MySQL** — identical; supply the appropriate ODBC driver name in the DSN.
- **Named DSN shorthand** — constructor overload accepting a pre-registered ODBC DSN name rather than a full connection string.
- **Connection string builder** — helper `pg_odbc_dsn(; host, port, dbname, user, password)` for PostgreSQL users who don't want to hand-write the connection string.
