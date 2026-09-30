"""
    test_display_layering()

Static layered-architecture guard for `ProjecturedPlatform`. The modules that
the package root binds from the packages below it are the aliases that the
source files import.
"""
function test_display_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "display",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_display()

Run this package's whole suite: the layering guard and a value shown in an
editor.
"""
function test_display()
    @testset "ProjecturedPlatform" begin
        test_display_layering()
        test_editor_display()
    end
end

export test_display, test_display_layering, test_editor_display
