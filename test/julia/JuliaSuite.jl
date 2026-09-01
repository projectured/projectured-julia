"""
    test_julia_layering()

Static layered-architecture guard for `ProjecturedJulia`.
"""
function test_julia_layering()
    main = package_source_root(ProjecturedJulia)
    check_layering(main, pathof(ProjecturedJulia);
                   name = "julia",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedJulia; all = true)
                         if isdefined(ProjecturedJulia, n) &&
                            getfield(ProjecturedJulia, n) isa Module &&
                            getfield(ProjecturedJulia, n) !== ProjecturedJulia &&
                            parentmodule(getfield(ProjecturedJulia, n)) !== ProjecturedJulia))
end

"""
    test_julia()

Run this package's whole suite: the layering guard and every julia test.
"""
function test_julia()
    @testset "ProjecturedJulia" begin
        test_julia_layering()
        test_julia_parser()
        test_julia_definition()
        test_julia_typein()
    end
end

export test_julia, test_julia_layering, test_julia_parser, test_julia_definition
export test_julia_typein
