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
    test_shell_completeness()

Every test function of this slice is called by [`test_shell`](@ref), and each one
exactly once.

A suite is edited by hand and by script, and a slip there is invisible: a
function that stops being called takes its assertions with it and the count only
falls, while one called twice makes the count rise for nothing. Both happened
here. This asserts the suite runs what the slice defines.
"""
function test_shell_completeness()
    @testset "the suite runs every test of this slice, once" begin
        directory = joinpath(get_package_source_root(ProjecturedShell), "..", "..", "..",
                             "test", "platform", "shell")
        defined = Set{String}()
        for name in readdir(directory)
            endswith(name, ".jl") || continue
            for line in eachline(joinpath(directory, name))
                match_ = match(r"^function (test_\w+)\(\)", line)
                match_ === nothing || push!(defined, match_[1])
            end
        end
        delete!(defined, "test_shell")
        delete!(defined, "test_shell_completeness")
        # The body of `test_shell` and nothing else: a docstring above it names
        # the same functions in the same shape, and counting those would count
        # every call twice.
        called = String[]
        inside = false
        for line in eachline(joinpath(directory, "ShellSuite.jl"))
            startswith(line, "function test_shell()") && (inside = true; continue)
            inside || continue
            startswith(line, "end") && break
            stripped = strip(line)
            endswith(stripped, "()") && startswith(stripped, "test_") &&
                push!(called, stripped[1:end-2])
        end
        @test isempty(setdiff(defined, Set(called)))
        @test length(called) == length(Set(called))
    end
end

"""
    test_shell()

Run this package's whole suite: the layering guard and the window wrap.
"""
function test_shell()
    @testset "ProjecturedShell" begin
        test_shell_layering()
        test_shell_completeness()
        test_window_wrap()
        test_widget_tooltip()
        test_julia_tooltip()
        test_tooltip_window()
        test_context_menu_probe()
        test_window_shell()
        test_file_dialog()
        test_tracking_screen()
        test_pointer_light()
    end
end

export test_shell, test_shell_layering, test_shell_completeness, test_window_wrap,
       test_widget_tooltip, test_julia_tooltip, test_tooltip_window,
       test_context_menu_probe, test_window_shell, test_file_dialog, test_tracking_screen,
       test_pointer_light
