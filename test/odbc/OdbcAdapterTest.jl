# The text of the catalog queries of `OdbcDatabaseAdapter`. No database runs
# here, so the test reads the text that each catalog function sends.

"""
    test_odbc_adapter()

The catalog queries of the ODBC adapter name what their arguments ask for:
the schemas of the database that the caller names, and every database of the
server. Needs no database.
"""
function test_odbc_adapter()
    @testset "the catalog query of the schemas names the database" begin
        query = ProjecturedOdbc.OdbcModule._make_catalog_schemas_query("dvdrental")
        @test occursin("catalog_name = 'dvdrental'", query)
        @test occursin("information_schema.schemata", query)
        @test !occursin("dvdrental", ProjecturedOdbc.OdbcModule._make_catalog_schemas_query("film"))
    end

    @testset "the catalog query of the databases lists every database of the server" begin
        query = ProjecturedOdbc.OdbcModule._make_catalog_databases_query()
        @test occursin("pg_database", query)
        @test !occursin("information_schema.tables", query)
    end
end
