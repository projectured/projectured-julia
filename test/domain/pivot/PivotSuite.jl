"""
    test_pivot_layering()

Static layered-architecture guard for `ProjecturedPivot`.
"""
function test_pivot_layering()
    main = get_package_source_root(ProjecturedPivot)
    check_layering(main, pathof(ProjecturedPivot);
                   name = "pivot",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPivot; all = true)
                         if isdefined(ProjecturedPivot, n) &&
                            getfield(ProjecturedPivot, n) isa Module &&
                            getfield(ProjecturedPivot, n) !== ProjecturedPivot &&
                            parentmodule(getfield(ProjecturedPivot, n)) !== ProjecturedPivot))
end

"""
    test_pivot()

Run this package's whole suite: the layering guard and every pivot test.
"""
function test_pivot()
    @testset "ProjecturedPivot" begin
        test_pivot_layering()
        test_pivot_cross_table()
        test_pivot_table_projection()
        test_pivot_zone_edits()
        test_pivot_cell_views()
        test_pivot_chart_views()
        test_pivot_totals()
        test_pivot_group_view()
    end
end

export test_pivot, test_pivot_layering, test_pivot_cross_table, test_pivot_table_projection, test_pivot_zone_edits, test_pivot_cell_views, test_pivot_chart_views, test_pivot_totals, test_pivot_group_view
