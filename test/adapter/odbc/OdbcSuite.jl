function setup_persons_table(adapter)
    execute_db_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    execute_db_raw(adapter, "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    insert_into_db!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function teardown_persons_table(adapter)
    execute_db_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end

include("OdbcAdapterTest.jl")
include("external/DatabaseResultTest.jl")
include("external/DbCatalogQueryTest.jl")
include("external/DbCatalogSyntaxTest.jl")

"""
    test_odbc_layering()

Static layered-architecture guard for `ProjecturedODBC`.
"""
function test_odbc_layering()
    main = get_package_source_root(ProjecturedODBC)
    check_layering(main, pathof(ProjecturedODBC);
                   name = "odbc",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedODBC; all = true)
                         if isdefined(ProjecturedODBC, n) &&
                            getfield(ProjecturedODBC, n) isa Module &&
                            getfield(ProjecturedODBC, n) !== ProjecturedODBC &&
                            parentmodule(getfield(ProjecturedODBC, n)) !== ProjecturedODBC))
end

"Run the ODBC database + catalog suite (skips when no DB is reachable)."
function test_odbc()
    @testset "ProjecturedODBC" begin
        test_odbc_adapter()
        test_odbc_database_no_db()
        test_odbc_database()
        test_db_catalog()
        test_db_catalog_syntax()
    end
end

export test_odbc, test_odbc_layering, test_odbc_adapter, test_odbc_database, test_odbc_database_no_db, test_db_catalog, test_db_catalog_syntax
