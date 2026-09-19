"""
    test_shell_layering()

Static layered-architecture guard for `ProjecturedShell`.
"""
function test_shell_layering()
    main = get_package_source_root(ProjecturedShell)
    check_layering(main, pathof(ProjecturedShell);
                   name = "shell",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedShell; all = true)
                         if isdefined(ProjecturedShell, n) &&
                            getfield(ProjecturedShell, n) isa Module &&
                            getfield(ProjecturedShell, n) !== ProjecturedShell &&
                            parentmodule(getfield(ProjecturedShell, n)) !== ProjecturedShell))
end

"""
    test_shell()

Run this package's whole suite: the layering guard and the window wrap.
"""
function test_shell()
    @testset "ProjecturedShell" begin
        test_shell_layering()
        test_window_wrap()
        test_widget_tooltip()
        test_julia_tooltip()
        test_tooltip_probe()
        test_context_menu_probe()
    end
end

export test_shell, test_shell_layering, test_window_wrap,
       test_widget_tooltip, test_julia_tooltip, test_tooltip_probe,
       test_context_menu_probe
