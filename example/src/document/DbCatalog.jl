function make_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "projectured_test"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    # The catalog document is just a connection spec. No connection is opened
    # here — the DatabaseInstanceToDbCatalog projection queries the database
    # lazily (through its connection pool) when the tree is first forced, so
    # this maker stays safe to run at module-load / precompile time.
    DatabaseInstance(
        database=dbname,
        host=host,
        port=port,
        credentials=DatabaseCredentials(user=user, password=password),
    )
end
