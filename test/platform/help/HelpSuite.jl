"""
    test_help_layering()

Static layered-architecture guard for `ProjecturedPlatform`.
"""
function test_help_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "help",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_help()

Run this package's whole suite: the layering guard, the description of a type,
the two lists and the page about the program.
"""
function test_help()
    @testset "ProjecturedPlatform" begin
        test_help_layering()
        test_docstring_summary()
        test_help_list_to_syntax()
        test_about_page_to_syntax()
    end
end

export test_help, test_help_layering, test_docstring_summary, test_help_list_to_syntax,
       test_about_page_to_syntax
