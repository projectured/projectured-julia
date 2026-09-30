"""
    test_display_layering()

Static layered-architecture guard for `ProjecturedDisplay`. The modules that
the package root binds from the packages below it are the aliases that the
source files import.
"""
function test_display_layering()
    main = get_package_source_root(ProjecturedDisplay)
    check_layering(main, pathof(ProjecturedDisplay);
                   name = "display",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDisplay; all = true)
                         if isdefined(ProjecturedDisplay, n) &&
                            getfield(ProjecturedDisplay, n) isa Module &&
                            getfield(ProjecturedDisplay, n) !== ProjecturedDisplay &&
                            parentmodule(getfield(ProjecturedDisplay, n)) !== ProjecturedDisplay))
end

"""
    test_display()

Run this package's whole suite: the layering guard and a value shown in an
editor.
"""
function test_display()
    @testset "ProjecturedDisplay" begin
        test_display_layering()
        test_editor_display()
    end
end

export test_display, test_display_layering, test_editor_display
