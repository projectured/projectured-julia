"""
    DatabaseInstanceDocumentModule

Document layer for a *database connection specification*. A `DatabaseInstance`
names a reachable database (database/host/port) together with the
`DatabaseCredentials` (user/password) needed to authenticate.

It carries no live connection and no adapter — it is a pure value document.
Projections that need to talk to the database (e.g. `DatabaseInstanceToDbCatalog`,
`SqlToCellTable`) take a connection pool as a parameter and build the actual
ODBC DSN from this instance via `ConnectionPoolModule.dsn_for`.
"""
module DatabaseInstanceDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference

export DatabaseInstanceDocument, DatabaseInstance, DatabaseCredentials,
       IDatabaseInstance, IDatabaseCredentials

abstract type DatabaseInstanceDocument <: Document end

# ── DatabaseCredentials ─────────────────────────────────────────────────────────

@document struct DatabaseCredentials <: DatabaseInstanceDocument
    user::String
    password::String
    selection::Reference
end

DatabaseCredentials(; user::AbstractString, password::AbstractString) =
    DatabaseCredentials(String(user), String(password), Cell(nothing))

# ── DatabaseInstance ────────────────────────────────────────────────────────────

@document struct DatabaseInstance <: DatabaseInstanceDocument
    database::String
    host::String
    port::Int
    credentials::DatabaseCredentials
    selection::Reference
end

DatabaseInstance(; database::AbstractString,
                   host::AbstractString="localhost",
                   port::Integer=5432,
                   credentials::DatabaseCredentials) =
    DatabaseInstance(String(database), String(host), Int(port), credentials, Cell(nothing))

end # module
