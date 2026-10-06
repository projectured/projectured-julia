"""
    test_chart_layering()

Static layered-architecture guard for `ProjecturedChart`.
"""
function test_chart_layering()
    main = get_package_source_root(ProjecturedChart)
    check_layering(main, pathof(ProjecturedChart);
                   name = "chart",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedChart; all = true)
                         if isdefined(ProjecturedChart, n) &&
                            getfield(ProjecturedChart, n) isa Module &&
                            getfield(ProjecturedChart, n) !== ProjecturedChart &&
                            parentmodule(getfield(ProjecturedChart, n)) !== ProjecturedChart))
end

"""
    test_chart()

Run this package's whole suite: the layering guard and every chart test.
"""
function test_chart()
    @testset "ProjecturedChart" begin
        test_chart_layering()
        test_chart_projection()
        test_chart_scale()
        test_chart_theme()
        test_chart_pie()
    end
end

export test_chart, test_chart_layering, test_chart_projection, test_chart
export test_chart_scale, test_chart_theme, test_chart_pie
