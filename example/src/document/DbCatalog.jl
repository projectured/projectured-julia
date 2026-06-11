function make_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "projectured_test"),
        user=get(ENV, "PGUSER", "postgres"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    adapter = PostgresDatabaseAdapter(dbname=dbname, user=user, password=password, host=host, port=port)
    try
        db_connect!(adapter)
        conn = DbCatalogConnection(adapter)
        return conn
    catch e
        @warn "Failed to connect to database for DbCatalog example: $e"
        @warn "Set PGDATABASE, PGUSER, PGPASSWORD, PGHOST, and PGPORT environment variables to configure the connection"
        rethrow(e)
    end
end
