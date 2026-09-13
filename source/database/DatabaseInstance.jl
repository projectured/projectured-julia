"""
    DatabaseInstanceDocumentModule

Document layer for a *database connection specification*. A `DatabaseInstance`
names a reachable database (database/host/port) together with the
`DatabaseCredentials` (user/password) needed to authenticate.

It carries no live connection and no adapter — it is a pure value document.
Projections that need to talk to the database (e.g. `DatabaseInstanceToDbCatalog`,
`SqlToCellTable`) take a connection pool as a parameter and build the actual
ODBC DSN from this instance via `ConnectionPoolModule.get_dsn`.
"""
module DatabaseInstanceDocumentModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

export DatabaseInstanceDocument

abstract type DatabaseInstanceDocument <: Document end

# ── DatabaseCredentials ─────────────────────────────────────────────────────────

@document struct DatabaseCredentials <: DatabaseInstanceDocument
    user::String
    password::String
end

# No field declares a default, so the macro generates no keyword constructor and
# this one owns the `(; …)` signature — it coerces both arguments to `String`.
DatabaseCredentials(; user::AbstractString, password::AbstractString) =
    DatabaseCredentials(String(user), String(password))

# ── DatabaseInstance ────────────────────────────────────────────────────────────

# The defaults live on the fields, so `DatabaseInstance(; database, credentials, …)`
# is the macro's keyword constructor; `database` and `credentials` are the two
# fields without a default, and so the two required keywords.
@document struct DatabaseInstance <: DatabaseInstanceDocument
    database::String
    host::String = "localhost"
    port::Int = 5432
    credentials::DatabaseCredentials
end

end # module
