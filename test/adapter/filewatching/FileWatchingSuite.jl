"""
    test_filewatching_layering()

Static layered-architecture guard for `ProjecturedFileWatching`.
"""
function test_filewatching_layering()
    main = get_package_source_root(ProjecturedFileWatching)
    check_layering(main, pathof(ProjecturedFileWatching);
                   name = "filewatching",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFileWatching; all = true)
                         if isdefined(ProjecturedFileWatching, n) &&
                            getfield(ProjecturedFileWatching, n) isa Module &&
                            getfield(ProjecturedFileWatching, n) !== ProjecturedFileWatching &&
                            parentmodule(getfield(ProjecturedFileWatching, n)) !== ProjecturedFileWatching))
end

"""
    test_filewatching()

Run this package's whole suite: the layering guard, and the watch of a folder
by a `FolderMonitor`.
"""
function test_filewatching()
    @testset "ProjecturedFileWatching" begin
        test_filewatching_layering()
        test_folder_monitor()
    end
end

export test_filewatching, test_filewatching_layering, test_folder_monitor
