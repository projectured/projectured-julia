# ── A live database as a document ─────────────────────────────────────────────
#
# The connection and its catalog, held as a document so a projection can render
# what a database contains.

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
