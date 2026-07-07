function make_database_adapter_example(;
        dsn=get(ENV, "TEST_ODBC_DSN",
                "Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
                "Database=projectured_test;" *
                "Uid=$(get(ENV, "PGUSER", "projectured"));" *
                "Pwd=$(get(ENV, "PGPASSWORD", "projectured"));"))
    OdbcDatabaseAdapter(dsn=dsn, rowid_column="ctid")
end

function setup_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    db_execute_raw(adapter,
        "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    db_insert!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function teardown_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end
