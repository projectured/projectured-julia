"""
    test_dbcatalog_layering()

Static layered-architecture guard for `ProjecturedDBCatalog`.
"""
function test_dbcatalog_layering()
    main = get_package_source_root(ProjecturedDBCatalog)
    check_layering(main, pathof(ProjecturedDBCatalog);
                   name = "dbcatalog",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDBCatalog; all = true)
                         if isdefined(ProjecturedDBCatalog, n) &&
                            getfield(ProjecturedDBCatalog, n) isa Module &&
                            getfield(ProjecturedDBCatalog, n) !== ProjecturedDBCatalog &&
                            parentmodule(getfield(ProjecturedDBCatalog, n)) !== ProjecturedDBCatalog))
end

"""
    test_dbcatalog()

Run this package's whole suite: the layering guard and every dbcatalog test.
"""
const test_dbcatalog = TestSuite("ProjecturedDBCatalog", [
    test_dbcatalog_layering,
    test_db_catalog_column_to_sql,
    test_db_catalog_table_to_sql,
    test_db_catalog_schema_to_sql,
    test_db_catalog_database_to_sql,
    test_db_catalog_rdbms_to_sql,
    test_db_catalog_marker_eligible,
    test_db_catalog_sql,
    test_dbcatalog_theme,
])

export test_dbcatalog, test_dbcatalog_layering, test_db_catalog_column_to_sql
export test_db_catalog_table_to_sql, test_db_catalog_schema_to_sql, test_db_catalog_database_to_sql
export test_db_catalog_rdbms_to_sql, test_db_catalog_marker_eligible, test_db_catalog_sql, test_dbcatalog_theme
