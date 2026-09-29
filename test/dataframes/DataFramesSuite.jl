"""
    test_dataframes_layering()

Static layered-architecture guard for `ProjecturedDataFrames`.
"""
function test_dataframes_layering()
    main = get_package_source_root(ProjecturedDataFrames)
    check_layering(main, pathof(ProjecturedDataFrames); name = "dataframes")
end

"""
    test_dataframes()

Run this package's whole suite: the layering guard, and the shape of the
example factory.
"""
function test_dataframes()
    @testset "ProjecturedDataFrames" begin
        test_dataframes_layering()
        test_data_frame_example()
    end
end

export test_dataframes, test_dataframes_layering, test_data_frame_example
