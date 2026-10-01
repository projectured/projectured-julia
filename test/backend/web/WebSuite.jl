include("WebTest.jl")

"""
    test_web_layering()

Static layered-architecture guard for `ProjecturedWeb`.
"""
function test_web_layering()
    main = get_package_source_root(ProjecturedWeb)
    check_layering(main, pathof(ProjecturedWeb);
                   name = "web",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedWeb; all = true)
                         if isdefined(ProjecturedWeb, n) &&
                            getfield(ProjecturedWeb, n) isa Module &&
                            getfield(ProjecturedWeb, n) !== ProjecturedWeb &&
                            parentmodule(getfield(ProjecturedWeb, n)) !== ProjecturedWeb))
end

"""
    test_web()

Run the whole suite of `ProjecturedWeb`: the layering guard and every test of the package.
"""
function test_web()
    @testset "ProjecturedWeb" begin
        test_web_layering()
        test_web_backend()
    end
end

export test_web, test_web_layering, test_web_backend
