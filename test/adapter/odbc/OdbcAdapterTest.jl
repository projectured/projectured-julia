# The text of the queries and the statements of `OdbcDatabaseAdapter`, and the
# connection string of the pool. No database runs here, so the test reads the
# text that each function builds.

"""
    test_odbc_adapter()

The catalog queries of the ODBC adapter name what their arguments ask for:
the schemas of the database that the caller names, and every database of the
server. A name goes into a query as a string literal, with each quote of it
written twice, and a table or a column name goes into a query or a statement as
a quoted identifier, with each double quote of it written twice. A database of
the catalog connects to that database, with the server and the credentials of
the instance, and a value of the connection string with a `;` or a `}` in it
stays one value. Needs no database.
"""
function test_odbc_adapter()
    @testset "the catalog query of the schemas names the database" begin
        query = ProjecturedODBC.OdbcModule._make_catalog_schemas_query("dvdrental")
        @test occursin("catalog_name = 'dvdrental'", query)
        @test occursin("information_schema.schemata", query)
        @test !occursin("dvdrental", ProjecturedODBC.OdbcModule._make_catalog_schemas_query("film"))
    end

    @testset "the catalog query of the databases lists every database of the server" begin
        query = ProjecturedODBC.OdbcModule._make_catalog_databases_query()
        @test occursin("pg_database", query)
        @test !occursin("information_schema.tables", query)
    end

    @testset "a name with a quote is one string literal in each catalog query" begin
        odbc = ProjecturedODBC.OdbcModule
        @test occursin("catalog_name = 'it''s'", odbc._make_catalog_schemas_query("it's"))
        @test occursin("table_schema = 'o''neil'", odbc._make_catalog_tables_query("o'neil"))
        query = odbc._make_catalog_columns_query("o'neil", "it's")
        @test occursin("table_schema = 'o''neil'", query)
        @test occursin("table_name = 'it''s'", query)
        @test occursin("ns.nspname = 'o''neil'", odbc._make_catalog_foreign_keys_query("o'neil"))
        # The name of a schema with no quote is written as it is.
        @test occursin("table_schema = 'public'", odbc._make_catalog_tables_query("public"))
    end

    @testset "a database of the catalog connects to that database, on the server of the instance" begin
        pool = OdbcConnectionPool()
        instance = DatabaseInstance(database = "shop", host = "db.example", port = 5433,
                                    credentials = DatabaseCredentials(user = "u", password = "p"))
        other = ProjecturedODBC.OdbcModule._make_database_instance(instance, "film")
        @test get_dsn(pool, other) == replace(get_dsn(pool, instance), "Database=shop;" => "Database=film;")
        @test occursin("Database=film;", get_dsn(pool, other))
        # The database of the instance uses the connections of the instance.
        same = ProjecturedODBC.OdbcModule._make_database_instance(instance, "shop")
        @test get_dsn(pool, same) == get_dsn(pool, instance)
    end

    @testset "a table or a column name with a double quote is one identifier" begin
        odbc = ProjecturedODBC.OdbcModule
        query, _ = odbc._build_select("a\"b", nothing, nothing, nothing)
        @test occursin("FROM \"a\"\"b\"", query)
        @test !occursin("FROM \"a\"b\"", query)
        query, _ = odbc._build_select("persons", ["na\"me", "age"], nothing, nothing)
        @test occursin("SELECT \"na\"\"me\", \"age\" FROM \"persons\"", query)
        @test occursin("INSERT INTO \"a\"\"b\" (\"na\"\"me\", \"age\") VALUES (?, ?)",
                       odbc._make_insert_statement("a\"b", ["na\"me", "age"]))
        @test occursin("UPDATE \"a\"\"b\" SET \"na\"\"me\" = ?, \"age\" = ? WHERE id = 1",
                       odbc._make_update_statement("a\"b", ["na\"me", "age"], "id = 1"))
        @test odbc._make_delete_statement("a\"b", "id = 1") == "DELETE FROM \"a\"\"b\" WHERE id = 1"
        # A name with no double quote is written as it is.
        @test odbc._make_delete_statement("persons", "id = 1") == "DELETE FROM \"persons\" WHERE id = 1"
    end

    @testset "a value of the connection string with a semicolon or a brace stays one value" begin
        pool = OdbcConnectionPool()
        instance = DatabaseInstance(database = "sh;op", host = "db.example", port = 5433,
                                    credentials = DatabaseCredentials(user = "u;s{er",
                                                                      password = "p}w;d"))
        dsn = get_dsn(pool, instance)
        @test occursin("Database={sh;op};", dsn)
        @test occursin("Uid={u;s{er};", dsn)
        @test occursin("Pwd={p}}w;d};", dsn)
        # The driver of the pool carries its own braces, and a value with no
        # special character is written as it is.
        @test occursin("Driver={PostgreSQL Unicode};", dsn)
        @test occursin("Server=db.example;", dsn)
    end
end
