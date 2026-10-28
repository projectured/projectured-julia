include("PrecompileRecordingTest.jl")
include("PrecompilePackageTest.jl")

"""
    test_precompile_layering()

Static layered-architecture guard for `ProjecturedPrecompile`.
"""
function test_precompile_layering()
    main = get_package_source_root(ProjecturedPrecompile)
    check_layering(main, pathof(ProjecturedPrecompile);
                   name = "precompile",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPrecompile; all = true)
                         if isdefined(ProjecturedPrecompile, n) &&
                            getfield(ProjecturedPrecompile, n) isa Module &&
                            getfield(ProjecturedPrecompile, n) !== ProjecturedPrecompile &&
                            parentmodule(getfield(ProjecturedPrecompile, n)) !== ProjecturedPrecompile))
end

"""
    test_precompile()

Run the whole suite of `ProjecturedPrecompile`: the layering guard, the parts of
the recording, and a probe package at each value of its two preferences.
"""
function test_precompile()
    @testset "ProjecturedPrecompile" begin
        test_precompile_layering()
        test_precompile_recording()
        test_compile_ahead()
    end
end

export test_precompile, test_precompile_layering, test_precompile_recording, test_compile_ahead
