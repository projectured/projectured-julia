"""
    test_sql_layering()

Static layered-architecture guard for `ProjecturedSQL`.
"""
function test_sql_layering()
    main = get_package_source_root(ProjecturedSQL)
    check_layering(main, pathof(ProjecturedSQL);
                   name = "sql",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSQL; all = true)
                         if isdefined(ProjecturedSQL, n) &&
                            getfield(ProjecturedSQL, n) isa Module &&
                            getfield(ProjecturedSQL, n) !== ProjecturedSQL &&
                            parentmodule(getfield(ProjecturedSQL, n)) !== ProjecturedSQL))
end

"""
    test_sql()

Run this package's whole suite: the layering guard and every sql test.
"""
function test_sql()
    @testset "ProjecturedSQL" begin
        test_sql_layering()
        test_sql_parser()
        test_sql_to_syntax()
        test_sql_theme()
        test_sql_insert_update_selection()
        test_sql_to_syntax_selection()
        test_sql_ddl()
        test_sql_ddl_selection()
    end
end

export test_sql, test_sql_layering, test_sql_parser
export test_sql_to_syntax, test_sql_theme, test_sql_insert_update_selection, test_sql_to_syntax_selection
export test_sql_ddl, test_sql_ddl_selection
