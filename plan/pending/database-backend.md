# Database Backend

A generic database access layer living alongside the SDL backend, with PostgreSQL as the first concrete implementation. Query results are pipelined directly into the caller-specified target type — `TabularGrid`, future `SpreadsheetDocument`, or `RawDatabaseResult` for explicit raw access — with no intermediate allocation.

## Library Recommendation

| Library | Role | Notes |
|---|---|---|
| **DBInterface.jl** | Abstract DB interface | Julia-ecosystem standard — defines `connect`, `execute`, `close`; all drivers implement it |
| **LibPQ.jl** | PostgreSQL driver | Wraps `libpq` C library; implements `DBInterface`; well-maintained; returns `Tables.jl`-compatible rows |
| **SQLite.jl** | SQLite driver (future) | Same `DBInterface` interface — zero extra adapter code needed to support it |

**Decision**: use `DBInterface.jl` as the generic contract. The project's own `DatabaseAdapter` abstract type wraps it, keeping the codebase independent of upstream API changes and providing a place for project-specific extensions.

---

## Design Decisions

- **`DatabaseAdapter` wraps `DBInterface`** — the abstract type holds the `DBInterface` connection internally and forwards to it. Concrete subtypes (`PostgresDatabaseAdapter`) own driver-specific initialisation.
- **Target-type dispatch** — `db_query(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into `T`. No intermediate struct. Adding a new target type is a new dispatch method; the DB layer is unchanged.
- **Three targets** — `TabularGrid` (current scope), `SpreadsheetDocument` (future), `RawDatabaseResult` (explicit raw materialization for inspection/serialization).
- **`TabularGrid` target** — column names populate a header `TabularRow`; each data row populates a subsequent `TabularRow`. `col_count` = number of columns.
- **`RawDatabaseResult` is a plain struct** — `columns::Vector{String}` + `rows::Vector{Vector{Any}}`. Only allocated when explicitly requested as the target.
- **`Database.jl` imports `TabularModule`** — consistent with `Sdl.jl` importing `GraphicsModule`. Load order in `Projectured.jl` must place `Tabular.jl` before `Database.jl`.
- **Mutations are plain functions** — `db_insert!`, `db_update!`, `db_delete!`. No `Operation` wrappers at this stage; those can be added later.
- **Single-table scope** — `db_query` targets one table; arbitrary SQL is exposed via `db_execute_raw` but is not the primary API. This matches the stated scope.
- **File: `program/src/backend/Database.jl`** — parallel to `program/src/backend/Sdl.jl`.

---

## Phase 1 — Abstract Adapter and Target Types

### File: `program/src/backend/Database.jl`

**`DatabaseAdapter`** (abstract):

```julia
abstract type DatabaseAdapter end
```

**Core interface** — implemented by all concrete subtypes:

```julia
db_connect!(adapter::DatabaseAdapter)       # open the connection
db_close!(adapter::DatabaseAdapter)         # close the connection
db_alive(adapter::DatabaseAdapter)::Bool    # connection health check
```

**`RawDatabaseResult`** (plain struct — explicit opt-in target only):

```julia
struct RawDatabaseResult
    columns::Vector{String}           # column names in order
    rows::Vector{Vector{Any}}         # one inner vector per row
end
```

**Query functions** — target type `T` is a required parameter; rows are pipelined directly into `T`:

```julia
db_query(adapter, table::String, ::Type{T};
    columns=nothing,          # Vector{String} or nothing → all columns
    where=nothing,            # String → raw WHERE clause; nothing → no filter
    limit=nothing             # Int or nothing
)::T where T

db_execute_raw(adapter, sql::String, ::Type{T}; params=())::T where T
```

**Supported targets** (dispatched in Phase 3):

| Target type | Result shape |
|---|---|
| `TabularGrid` | Header `TabularRow` + one `TabularRow` per data row |
| `RawDatabaseResult` | Plain struct; `columns` + `rows::Vector{Vector{Any}}` |
| `SpreadsheetDocument` | *(future)* |

**Mutation functions** — unchanged, dispatch on `DatabaseAdapter`:

```julia
db_insert!(adapter, table::String, row::AbstractDict)::Int     # returns inserted row count
db_update!(adapter, table::String, row::AbstractDict,
           where::String)::Int                                  # returns updated row count
db_delete!(adapter, table::String, where::String)::Int          # returns deleted row count
```

### Exports

```julia
export DatabaseAdapter, RawDatabaseResult,
       db_connect!, db_close!, db_alive,
       db_query, db_execute_raw,
       db_insert!, db_update!, db_delete!
```

---

## Phase 2 — PostgreSQL Concrete Adapter

### Type

```julia
mutable struct PostgresDatabaseAdapter <: DatabaseAdapter
    host::String
    port::Int
    dbname::String
    user::String
    password::String
    _conn::Union{Nothing, LibPQ.Connection}   # internal; private
end

PostgresDatabaseAdapter(; host="localhost", port=5432,
    dbname, user, password) =
    PostgresDatabaseAdapter(host, port, dbname, user, password, nothing)
```

### Implementation

- `db_connect!` — `LibPQ.Connection(dsn_string)` via `DBInterface.connect`; stores in `_conn`.
- `db_close!` — `DBInterface.close(_conn)`; resets field to `nothing`.
- `db_alive` — runs `SELECT 1`; catches exceptions; returns `Bool`.
- `db_query` — builds parameterised `SELECT … FROM … WHERE … LIMIT …`; executes via `DBInterface.execute`; passes the LibPQ result cursor and column names directly to the target-type dispatch method (Phase 3).
- `db_execute_raw` — executes arbitrary SQL via `DBInterface.execute`; passes cursor to the same target-type dispatch.
- `db_insert!` / `db_update!` / `db_delete!` — build parameterised SQL from the dict/where string; return `rowcount` from execution result.

### New dependency in `program/Project.toml`

```toml
DBInterface = "a10d1c49-ce27-4219-8d33-6db1a4562965"
LibPQ = "194296ae-ab2e-5f79-8cd4-7183a0a5a0d1"
```

---

## Phase 3 — Target-Type Dispatch Methods

All methods live in `Database.jl`. A shared private helper `_col_names(cursor)` extracts column names from the LibPQ result.

### `TabularGrid` target

```julia
function db_query(adapter::PostgresDatabaseAdapter, table::String, ::Type{TabularGrid};
        columns=nothing, where=nothing, limit=nothing)::TabularGrid
    sql, params = _build_select(table, columns, where, limit)
    cursor = DBInterface.execute(adapter._conn, sql, params)
    col_names = _col_names(cursor)
    col_count = length(col_names)
    header = Cell(TabularRow(CellVector([
        Cell(TabularCell(Cell(name))) for name in col_names
    ])))
    data_rows = [Cell(TabularRow(CellVector([
        Cell(TabularCell(Cell(val))) for val in row
    ]))) for row in cursor]
    TabularGrid(CellVector(vcat([header], data_rows)), col_count)
end
```

Column names become the first `TabularRow` (header); each data row becomes a subsequent `TabularRow`. `col_count` = number of columns.

### `RawDatabaseResult` target

```julia
function db_query(adapter::PostgresDatabaseAdapter, table::String, ::Type{RawDatabaseResult};
        columns=nothing, where=nothing, limit=nothing)::RawDatabaseResult
    sql, params = _build_select(table, columns, where, limit)
    cursor = DBInterface.execute(adapter._conn, sql, params)
    col_names = _col_names(cursor)
    rows = [collect(Any, row) for row in cursor]
    RawDatabaseResult(col_names, rows)
end
```

### `SpreadsheetDocument` target *(future)*

Adding support = one new dispatch method on `db_query` and `db_execute_raw`. No changes to the adapter, connection, or SQL-building logic.

---

## Phase 4 — Integration into `Projectured.jl`

```julia
include("backend/Database.jl")
```

Placement: after `include("backend/Sdl.jl")` so both backends are loaded together.

Exports to add:
```julia
using .DatabaseModule: DatabaseAdapter, RawDatabaseResult,
                       PostgresDatabaseAdapter,
                       db_connect!, db_close!, db_alive,
                       db_query, db_execute_raw,
                       db_insert!, db_update!, db_delete!
```

Load order requirement: `include("document/Tabular.jl")` must precede `include("backend/Database.jl")`.

---

## Phase 5 — Tests

### File: `test/src/backend/DatabaseTest.jl`

Tests require a live PostgreSQL instance. Use a dedicated test database (`projectured_test`). A helper fixture creates and tears down a `persons` table.

**T1 — Connect / close** — `db_connect!` succeeds; `db_alive` returns `true`; `db_close!` succeeds; `db_alive` returns `false`.

**T2 — Insert** — `db_insert!(adapter, "persons", Dict("name"=>"Alice","age"=>30))` returns 1; row exists in DB.

**T3 — Query into `TabularGrid`** — `db_query(adapter, "persons", TabularGrid)` returns a `TabularGrid`; row 1 is the header (column names as `TabularCell`s); row 2 is the data row; `g.col_count == 2`.

**T4 — Header content** — `tabular_cell(g, 1, 1)` equals the column name string (e.g. `"name"`); `tabular_cell(g, 2, 1)` equals `"Alice"`.

**T5 — Query filtered into `TabularGrid`** — `db_query(adapter, "persons", TabularGrid; where="age > 20", limit=10)` returns only matching data rows.

**T6 — Query into `RawDatabaseResult`** — `db_query(adapter, "persons", RawDatabaseResult)` returns `RawDatabaseResult`; `r.columns == ["name", "age"]`; `r.rows[1][1] == "Alice"`.

**T7 — Update** — `db_update!(adapter, "persons", Dict("age"=>31), "name = 'Alice'")` returns 1; subsequent `db_query(..., TabularGrid)` reflects the change.

**T8 — Delete** — `db_delete!(adapter, "persons", "name = 'Alice'")` returns 1; subsequent query grid has only 1 row (header).

**T9 — `db_execute_raw` into `RawDatabaseResult`** — `db_execute_raw(adapter, "SELECT count(*) FROM persons", RawDatabaseResult)` returns a `RawDatabaseResult` with one row.

### Wiring

```julia
include("backend/DatabaseTest.jl")   # in include block (guarded if no live DB)
test_database()                       # in test_backends()
```

---

## Implementation Steps

1. Add `DBInterface` and `LibPQ` to `program/Project.toml`.
2. Create `program/src/backend/Database.jl` — abstract type, `RawDatabaseResult`, core interface functions.
3. Implement `PostgresDatabaseAdapter` with connection and mutation functions (Phase 2).
4. Add `TabularGrid` and `RawDatabaseResult` dispatch methods for `db_query` and `db_execute_raw` (Phase 3).
5. Wire into `Projectured.jl` after `Tabular.jl` (Phase 4).
6. Write `test/src/backend/DatabaseTest.jl` (Phase 5).

## Future Extensions

- **SQLite adapter** — `SQLiteDatabaseAdapter` using `SQLite.jl` + `DBInterface`; zero change to the abstract API.
- **Connection pool** — wrap multiple connections behind `DatabaseAdapter`; `db_query` picks an idle one.
- **Schema introspection** — `db_schema(adapter, table)::DatabaseSchema` (column names + types + constraints) as foundation for schema-driven projection (tentative §14e).
- **Reactive polling** — periodic cell invalidation for live-updating `TabularGrid` views; PostgreSQL LISTEN/NOTIFY as a push-based alternative.
- **Operation wrappers** — `DatabaseInsertOperation` etc. for editor undo/redo integration.
