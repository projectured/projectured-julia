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
    end
end

export test_pivot, test_pivot_layering, test_pivot_cross_table
