"""
    test_help_layering()

Static layered-architecture guard for `ProjecturedHelp`.
"""
function test_help_layering()
    main = get_package_source_root(ProjecturedHelp)
    check_layering(main, pathof(ProjecturedHelp);
                   name = "help",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedHelp; all = true)
                         if isdefined(ProjecturedHelp, n) &&
                            getfield(ProjecturedHelp, n) isa Module &&
                            getfield(ProjecturedHelp, n) !== ProjecturedHelp &&
                            parentmodule(getfield(ProjecturedHelp, n)) !== ProjecturedHelp))
end

"""
    test_help()

Run this package's whole suite: the layering guard, the description of a type,
the two lists and the page about the program.
"""
function test_help()
    @testset "ProjecturedHelp" begin
        test_help_layering()
        test_docstring_summary()
        test_help_list_to_syntax()
        test_about_page_to_syntax()
    end
end

export test_help, test_help_layering, test_docstring_summary, test_help_list_to_syntax,
       test_about_page_to_syntax
