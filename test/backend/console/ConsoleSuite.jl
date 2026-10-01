include("ConsoleBackendTest.jl")

"""
    test_console_layering()

Static layered-architecture guard for `ProjecturedConsole`.
"""
function test_console_layering()
    main = get_package_source_root(ProjecturedConsole)
    check_layering(main, pathof(ProjecturedConsole);
                   name = "console",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedConsole; all = true)
                         if isdefined(ProjecturedConsole, n) &&
                            getfield(ProjecturedConsole, n) isa Module &&
                            getfield(ProjecturedConsole, n) !== ProjecturedConsole &&
                            parentmodule(getfield(ProjecturedConsole, n)) !== ProjecturedConsole))
end

"""
    test_console()

Run the whole suite of `ProjecturedConsole`: the layering guard and every test of the package.
"""
function test_console()
    @testset "ProjecturedConsole" begin
        test_console_layering()
        test_console_backend()
    end
end

export test_console, test_console_layering, test_console_backend
