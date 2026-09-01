"""
    test_math_layering()

Static layered-architecture guard for `ProjecturedMath`.
"""
function test_math_layering()
    main = package_source_root(ProjecturedMath)
    check_layering(main, pathof(ProjecturedMath);
                   name = "math",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedMath; all = true)
                         if isdefined(ProjecturedMath, n) &&
                            getfield(ProjecturedMath, n) isa Module &&
                            getfield(ProjecturedMath, n) !== ProjecturedMath &&
                            parentmodule(getfield(ProjecturedMath, n)) !== ProjecturedMath))
end

"""
    test_math()

Run this package's whole suite: the layering guard and every math test.
"""
function test_math()
    @testset "ProjecturedMath" begin
        test_math_layering()
        test_math_to_graphics()
    end
end

export test_math, test_math_layering, test_math_to_graphics
