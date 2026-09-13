"""
    test_sequencechart_layering()

Static layered-architecture guard for `ProjecturedSequenceChart`.
"""
function test_sequencechart_layering()
    main = get_package_source_root(ProjecturedSequenceChart)
    check_layering(main, pathof(ProjecturedSequenceChart);
                   name = "sequencechart",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["SequenceChartGeometry.jl"]),
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSequenceChart; all = true)
                         if isdefined(ProjecturedSequenceChart, n) &&
                            getfield(ProjecturedSequenceChart, n) isa Module &&
                            getfield(ProjecturedSequenceChart, n) !== ProjecturedSequenceChart &&
                            parentmodule(getfield(ProjecturedSequenceChart, n)) !== ProjecturedSequenceChart))
end

"""
    test_sequencechart()

Run this package's whole suite: the layering guard and every sequencechart test.
"""
function test_sequencechart()
    @testset "ProjecturedSequenceChart" begin
        test_sequencechart_layering()
        test_sequencechart_geometry()
        test_sequencechart_projection()
        test_sequencechart_scale()
        test_sequencechart_selection()
    end
end

export test_sequencechart, test_sequencechart_layering, test_sequencechart_projection, test_sequencechart_geometry
export test_sequencechart_scale, test_sequencechart_selection
