"""
    test_dbcatalog_layering()

Static layered-architecture guard for `ProjecturedDbCatalog`.
"""
function test_dbcatalog_layering()
    main = get_package_source_root(ProjecturedDbCatalog)
    check_layering(main, pathof(ProjecturedDbCatalog);
                   name = "dbcatalog",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["DbCatalogDocument.jl"]),
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDbCatalog; all = true)
                         if isdefined(ProjecturedDbCatalog, n) &&
                            getfield(ProjecturedDbCatalog, n) isa Module &&
                            getfield(ProjecturedDbCatalog, n) !== ProjecturedDbCatalog &&
                            parentmodule(getfield(ProjecturedDbCatalog, n)) !== ProjecturedDbCatalog))
end

"""
    test_dbcatalog()

Run this package's whole suite: the layering guard and every dbcatalog test.
"""
function test_dbcatalog()
    @testset "ProjecturedDbCatalog" begin
        test_dbcatalog_layering()
        test_db_catalog_column_to_sql()
        test_db_catalog_table_to_sql()
        test_db_catalog_schema_to_sql()
        test_db_catalog_database_to_sql()
        test_db_catalog_rdbms_to_sql()
        test_db_catalog_marker_eligible()
        test_db_catalog_sql()
    end
end

export test_dbcatalog, test_dbcatalog_layering, test_db_catalog_column_to_sql
export test_db_catalog_table_to_sql, test_db_catalog_schema_to_sql, test_db_catalog_database_to_sql
export test_db_catalog_rdbms_to_sql, test_db_catalog_marker_eligible, test_db_catalog_sql
