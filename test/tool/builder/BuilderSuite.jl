include("BuilderTest.jl")
include("PackageReleaseTest.jl")

"""
    test_builder_layering()

Static layered-architecture guard for `ProjecturedBuilder`.
"""
function test_builder_layering()
    main = get_package_source_root(ProjecturedBuilder)
    check_layering(main, pathof(ProjecturedBuilder);
                   name = "builder",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedBuilder; all = true)
                         if isdefined(ProjecturedBuilder, n) &&
                            getfield(ProjecturedBuilder, n) isa Module &&
                            getfield(ProjecturedBuilder, n) !== ProjecturedBuilder &&
                            parentmodule(getfield(ProjecturedBuilder, n)) !== ProjecturedBuilder))
end

"""
    test_builder()

Run the whole suite of `ProjecturedBuilder`: the layering guard, the binaries and
the release copy.
"""
function test_builder()
    @testset "ProjecturedBuilder" begin
        test_builder_layering()
        test_build_executable()
        test_package_release()
    end
end

export test_builder, test_builder_layering, test_build_executable, test_package_release
