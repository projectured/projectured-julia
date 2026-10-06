"""
    test_dataframes_layering()

Static layered-architecture guard for `ProjecturedDataFrames`. The modules
that the package root binds from the packages below it are the aliases that
the source files import.
"""
function test_dataframes_layering()
    main = get_package_source_root(ProjecturedDataFrames)
    check_layering(main, pathof(ProjecturedDataFrames);
                   name = "dataframes",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDataFrames; all = true)
                         if isdefined(ProjecturedDataFrames, n) &&
                            getfield(ProjecturedDataFrames, n) isa Module &&
                            getfield(ProjecturedDataFrames, n) !== ProjecturedDataFrames &&
                            parentmodule(getfield(ProjecturedDataFrames, n)) !== ProjecturedDataFrames))
end

"""
    test_dataframes()

Run this package's whole suite: the layering guard, the shape of the example
factory, the view of a data frame, its columns, its filters, its order, its
refresh, its duplicate, its theme, and a frame shown through the display.
"""
function test_dataframes()
    @testset "ProjecturedDataFrames" begin
        test_dataframes_layering()
        test_data_frame_example()
        test_data_frame_view()
        test_data_frame_table()
        test_data_frame_columns()
        test_data_frame_paths()
        test_data_frame_cells()
        test_data_frame_row_edits()
        test_data_frame_row_page()
        test_data_frame_column_edits()
        test_data_frame_find()
        test_data_frame_filter()
        test_data_frame_sort()
        test_data_frame_refresh()
        test_data_frame_duplicate()
        test_data_frame_column_width()
        test_data_frame_theme()
        test_data_frame_display()
    end
end

export test_dataframes, test_dataframes_layering, test_data_frame_example, test_data_frame_view,
       test_data_frame_row_page, test_data_frame_table,
       test_data_frame_columns, test_data_frame_paths, test_data_frame_cells, test_data_frame_row_edits,
       test_data_frame_column_edits, test_data_frame_find, test_data_frame_filter,
       test_data_frame_sort, test_data_frame_refresh, test_data_frame_duplicate,
       test_data_frame_column_width, test_data_frame_theme, test_data_frame_display
