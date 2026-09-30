# Fragment of `OdbcModule`.
#
import ProjecturedDatabase.DatabaseModule: connect_db!, close_db!, is_db_alive
import ProjecturedDatabase.DatabaseModule: DatabaseInstance


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

# A value of a connection string: a value that holds a character with a meaning
# in the string — a `;`, a `{`, a `}`, an `=`, or a space at an end — goes
# between braces, and each `}` of it is written twice. A value that holds none of
# them is written as it is.
function _escape_odbc_value(value::AbstractString)::String
    text = String(value)
    special = any(c -> c in (';', '{', '}', '='), text) ||
              (!isempty(text) && (isspace(first(text)) || isspace(last(text))))
    special || return text
    "{" * replace(text, "}" => "}}") * "}"
end

"""
    get_dsn(pool, inst::DatabaseInstance) -> String

Build the ODBC connection string for `inst` using the pool's driver. Adapters
are bucketed by this DSN, so two `DatabaseInstance`s that resolve to the same
DSN share connections.

The server, the database and the credentials of `inst` are escaped, so a name, a
user or a password with a `;` or a `}` in it stays one value. The driver of the
pool carries its own braces, as `"{PostgreSQL Unicode}"` does, and goes into the
string as it is.
"""
function get_dsn(pool::OdbcConnectionPool, inst::DatabaseInstance)::String
    "Driver=$(pool.driver);Server=$(_escape_odbc_value(inst.host));Port=$(inst.port);" *
    "Database=$(_escape_odbc_value(inst.database));" *
    "Uid=$(_escape_odbc_value(inst.credentials.user));" *
    "Pwd=$(_escape_odbc_value(inst.credentials.password));"
end

# ── Checkout / checkin ──────────────────────────────────────────────────────────

function _checkout(pool::OdbcConnectionPool, dsn::String)::OdbcDatabaseAdapter
    lock(pool.lock) do
        bucket = get(pool.idle, dsn, nothing)
        if bucket !== nothing
            while !isempty(bucket)
                a = pop!(bucket)
                is_db_alive(a) && return a
                try; close_db!(a); catch; end   # stale: drop it and try the next
            end
        end
        a = OdbcDatabaseAdapter(dsn=dsn, rowid_column=pool.rowid_column)
        connect_db!(a)
        return a
    end
end

function _checkin(pool::OdbcConnectionPool, dsn::String, a::OdbcDatabaseAdapter)
    lock(pool.lock) do
        bucket = get!(pool.idle, dsn, OdbcDatabaseAdapter[])
        if length(bucket) < pool.max_size && is_db_alive(a)
            push!(bucket, a)
        else
            try; close_db!(a); catch; end
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
    dsn = get_dsn(pool, inst)
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
            try; close_db!(a); catch; end
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
                try; close_db!(a); catch; end
            end
            empty!(bucket)
        end
    end
    pool
end
