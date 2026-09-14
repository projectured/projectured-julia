"""
    test_sql_layering()

Static layered-architecture guard for `ProjecturedSql`.
"""
function test_sql_layering()
    main = get_package_source_root(ProjecturedSql)
    check_layering(main, pathof(ProjecturedSql);
                   name = "sql",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSql; all = true)
                         if isdefined(ProjecturedSql, n) &&
                            getfield(ProjecturedSql, n) isa Module &&
                            getfield(ProjecturedSql, n) !== ProjecturedSql &&
                            parentmodule(getfield(ProjecturedSql, n)) !== ProjecturedSql))
end

"""
    test_sql()

Run this package's whole suite: the layering guard and every sql test.
"""
function test_sql()
    @testset "ProjecturedSql" begin
        test_sql_layering()
        test_sql_parser()
        test_sql_to_syntax()
        test_sql_insert_update_selection()
        test_sql_to_syntax_selection()
        test_sql_ddl()
        test_sql_ddl_selection()
    end
end

export test_sql, test_sql_layering, test_sql_parser
export test_sql_to_syntax, test_sql_insert_update_selection, test_sql_to_syntax_selection
export test_sql_ddl, test_sql_ddl_selection
