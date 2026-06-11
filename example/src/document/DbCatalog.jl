function make_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "projectured_test"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    dsn = get(ENV, "TEST_ODBC_DSN",
              "Driver={PostgreSQL Unicode};Server=$(host);Port=$(port);" *
              "Database=$(dbname);Uid=$(user);Pwd=$(password);")
    adapter = OdbcDatabaseAdapter(dsn=dsn, rowid_column="ctid")
    conn = DbCatalogConnection(adapter; host=host, port=port)
    # Connect eagerly when a database is reachable, but never throw: this maker
    # runs at module-load / precompile time (the `Example` constructor calls it),
    # and precompilation must not depend on a live database or ODBC driver.
    try
        db_connect!(adapter)
    catch e
        @warn "DbCatalog example: database unavailable, catalog will be empty until connected: $e"
        @warn "Set PGDATABASE, PGUSER, PGPASSWORD, PGHOST, PGPORT (or TEST_ODBC_DSN) to configure the connection"
    end
    return conn
end
