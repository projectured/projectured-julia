"""
    test_filesystem_layering()

Static layered-architecture guard for `ProjecturedFileSystem`.
"""
function test_filesystem_layering()
    main = get_package_source_root(ProjecturedFileSystem)
    check_layering(main, pathof(ProjecturedFileSystem);
                   name = "filesystem",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFileSystem; all = true)
                         if isdefined(ProjecturedFileSystem, n) &&
                            getfield(ProjecturedFileSystem, n) isa Module &&
                            getfield(ProjecturedFileSystem, n) !== ProjecturedFileSystem &&
                            parentmodule(getfield(ProjecturedFileSystem, n)) !== ProjecturedFileSystem))
end

"""
    test_filesystem()

Run this package's whole suite: the layering guard and every filesystem test.
"""
function test_filesystem()
    @testset "ProjecturedFileSystem" begin
        test_filesystem_layering()
        test_filesystem_to_syntax()
        test_filesystem_to_widget()
        test_workspace_duplicate()
    end
end

export test_filesystem, test_filesystem_layering, test_filesystem_to_syntax,
       test_filesystem_to_widget, test_workspace_duplicate
