"""
    DatabaseInstanceToDbCatalogModule

Projection: `DatabaseInstance` → `DbCatalogRdbms` (the full catalog tree).

Builds the nested `DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema →
DbCatalogTable → DbCatalogColumn` tree from a connection spec. Each level's
child collection is a **lazy** `CellVector` thunk that queries the database
through the `OdbcConnectionPool` only when forced — so constructing the document
never touches the database, and a change anywhere re-queries only the affected
subtree.

The connection pool is a **projection parameter** (`DatabaseInstanceToDbCatalog(pool)`):
the catalog documents themselves hold no adapter and no connection. This module
subsumes the old per-level `DbCatalogToChildren` projections, which navigated a
parent-pointer chain to reach an embedded adapter.

Read-only: there is no reference mapping or read support.
"""
module DatabaseInstanceToDbCatalogModule

import ..CollectionModule: CellVector
import ..DatabaseInstanceDocumentModule: DatabaseInstance
import ..DbCatalogDocumentModule: DbCatalogRdbms, DbCatalogDatabase,
                                  DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..DatabaseModule: db_catalog_databases, db_catalog_schemas,
                         db_catalog_tables, db_catalog_columns
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ..IoMapModule: SimpleIoMap
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection

export DatabaseInstanceToDbCatalog

# ── Lazy tree builders ──────────────────────────────────────────────────────────
# Each helper returns a CellVector whose contents are recomputed lazily by
# querying through the pool. The pool + instance are captured by closure.

function _build_columns(pool, inst, schema_name::String, table_name::String)
    CellVector(() -> begin
        cols = with_connection(pool, inst) do adapter
            db_catalog_columns(adapter, schema_name, table_name)
        end
        DbCatalogColumn[DbCatalogColumn(c.name, c.data_type) for c in cols]
    end)
end

function _build_tables(pool, inst, schema_name::String)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_tables(adapter, schema_name)
        end
        DbCatalogTable[DbCatalogTable(n, _build_columns(pool, inst, schema_name, n))
                       for n in names]
    end)
end

function _build_schemas(pool, inst, database_name::String)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_schemas(adapter, database_name)
        end
        DbCatalogSchema[DbCatalogSchema(n, _build_tables(pool, inst, n))
                        for n in names]
    end)
end

function _build_databases(pool, inst)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_databases(adapter)
        end
        DbCatalogDatabase[DbCatalogDatabase(n, _build_schemas(pool, inst, n))
                          for n in names]
    end)
end

# ── DatabaseInstanceToDbCatalog ─────────────────────────────────────────────────

struct DatabaseInstanceToDbCatalog <: Projection
    pool::OdbcConnectionPool
end

function projection_print(p::DatabaseInstanceToDbCatalog,
                          recursion, inst::DatabaseInstance, ctx)
    rdbms = DbCatalogRdbms(inst.host, inst.port, _build_databases(p.pool, inst))
    SimpleIoMap(p, inst, rdbms)
end

map_reference_forward(::DatabaseInstanceToDbCatalog, iomap, ref) = nothing
map_reference_backward(::DatabaseInstanceToDbCatalog, iomap, ref) = nothing
projection_read(::DatabaseInstanceToDbCatalog, iomap, op) = nothing

end # module
