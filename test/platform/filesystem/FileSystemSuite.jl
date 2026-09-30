"""
    test_filesystem_layering()

Static layered-architecture guard for `ProjecturedPlatform`.
"""
function test_filesystem_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "filesystem",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_filesystem()

Run this package's whole suite: the layering guard and every filesystem test.
"""
function test_filesystem()
    @testset "ProjecturedPlatform" begin
        test_filesystem_layering()
        test_filesystem_document()
        test_filesystem_to_syntax()
        test_filesystem_to_widget()
        test_workspace_duplicate()
        test_workspace_to_filesystem()
    end
end

export test_filesystem, test_filesystem_layering, test_filesystem_document, test_filesystem_to_syntax,
       test_filesystem_to_widget, test_workspace_duplicate, test_workspace_to_filesystem
