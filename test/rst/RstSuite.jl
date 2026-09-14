"""
    test_rst_layering()

Static layered-architecture guard for `ProjecturedRst`.
"""
function test_rst_layering()
    main = get_package_source_root(ProjecturedRst)
    check_layering(main, pathof(ProjecturedRst);
                   name = "rst",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedRst; all = true)
                         if isdefined(ProjecturedRst, n) &&
                            getfield(ProjecturedRst, n) isa Module &&
                            getfield(ProjecturedRst, n) !== ProjecturedRst &&
                            parentmodule(getfield(ProjecturedRst, n)) !== ProjecturedRst))
end

"""
    test_rst()

Run this package's whole suite: the layering guard and every rst test.
"""
function test_rst()
    @testset "ProjecturedRst" begin
        test_rst_layering()
        test_rst_parser()
        test_rst_round_trip()
        test_rst_embed()
    end
end

export test_rst, test_rst_layering, test_rst_parser
export test_rst_round_trip, test_rst_embed
