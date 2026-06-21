"""
    ConnectionPoolModule

A small in-process ODBC connection pool. Connections are reused across queries
instead of being opened and closed each time. The pool wraps the existing
`OdbcDatabaseAdapter` (from `DatabaseModule`), so every `db_catalog_*` /
`db_execute_raw` / `db_query` query function works unchanged against a pooled
adapter.

A pool is **passed as a parameter** to the projections that need database
access (`DatabaseInstanceToDbCatalog`, `SqlToCellTable`). The DSN is derived
from a `DatabaseInstance` plus the pool's driver via `dsn_for`, so a single
pool can serve several `DatabaseInstance`s (idle adapters are bucketed by DSN).

The pool is non-blocking: `with_connection` reuses an idle adapter for the DSN
if one is alive, otherwise it opens a fresh one. `max_size` caps how many idle
adapters are *retained* per DSN on check-in; surplus connections are closed.
A `ReentrantLock` guards the idle buckets.
"""
module ConnectionPoolModule

import ..DatabaseModule: db_connect!, db_close!, db_alive
import ..OdbcAdapterModule: OdbcDatabaseAdapter
import ..DatabaseInstanceDocumentModule: DatabaseInstance

export OdbcConnectionPool, with_connection, dsn_for, close_pool!

# ── OdbcConnectionPool ──────────────────────────────────────────────────────────

mutable struct OdbcConnectionPool
    driver::String          # ODBC driver, e.g. "{PostgreSQL Unicode}"
    rowid_column::String    # technical row-identity column, e.g. "ctid"
    max_size::Int           # max idle adapters retained per DSN
    lock::ReentrantLock
    idle::Dict{String, Vector{OdbcDatabaseAdapter}}   # DSN → idle adapters
end

OdbcConnectionPool(; driver::AbstractString="{PostgreSQL Unicode}",
                     rowid_column::AbstractString="ctid",
                     max_size::Integer=8) =
    OdbcConnectionPool(String(driver), String(rowid_column), Int(max_size),
                       ReentrantLock(), Dict{String, Vector{OdbcDatabaseAdapter}}())

# ── DSN derivation ──────────────────────────────────────────────────────────────

"""
    dsn_for(pool, inst::DatabaseInstance) -> String

Build the ODBC connection string for `inst` using the pool's driver. Adapters
are bucketed by this DSN, so two `DatabaseInstance`s that resolve to the same
DSN share connections.
"""
function dsn_for(pool::OdbcConnectionPool, inst::DatabaseInstance)::String
    "Driver=$(pool.driver);Server=$(inst.host);Port=$(inst.port);" *
    "Database=$(inst.database);Uid=$(inst.credentials.user);Pwd=$(inst.credentials.password);"
end

# ── Checkout / checkin ──────────────────────────────────────────────────────────

function _checkout(pool::OdbcConnectionPool, dsn::String)::OdbcDatabaseAdapter
    lock(pool.lock) do
        bucket = get(pool.idle, dsn, nothing)
        if bucket !== nothing
            while !isempty(bucket)
                a = pop!(bucket)
                db_alive(a) && return a
                try; db_close!(a); catch; end   # stale: drop it and try the next
            end
        end
        a = OdbcDatabaseAdapter(dsn=dsn, rowid_column=pool.rowid_column)
        db_connect!(a)
        return a
    end
end

function _checkin(pool::OdbcConnectionPool, dsn::String, a::OdbcDatabaseAdapter)
    lock(pool.lock) do
        bucket = get!(pool.idle, dsn, OdbcDatabaseAdapter[])
        if length(bucket) < pool.max_size && db_alive(a)
            push!(bucket, a)
        else
            try; db_close!(a); catch; end
        end
    end
    nothing
end

"""
    with_connection(f, pool, inst::DatabaseInstance)

Check out a live pooled `OdbcDatabaseAdapter` for `inst`, run `f(adapter)`, and
return the adapter to the pool. On error the connection is discarded (closed)
rather than returned, so a broken connection is never reused.
"""
function with_connection(f, pool::OdbcConnectionPool, inst::DatabaseInstance)
    dsn = dsn_for(pool, inst)
    a = _checkout(pool, dsn)
    ok = false
    try
        result = f(a)
        ok = true
        return result
    finally
        if ok
            _checkin(pool, dsn, a)
        else
            try; db_close!(a); catch; end
        end
    end
end

"""
    close_pool!(pool)

Close and discard every idle adapter in the pool. Connections currently checked
out (inside a `with_connection` call) are unaffected.
"""
function close_pool!(pool::OdbcConnectionPool)
    lock(pool.lock) do
        for (_, bucket) in pool.idle
            for a in bucket
                try; db_close!(a); catch; end
            end
            empty!(bucket)
        end
    end
    pool
end

end # module
