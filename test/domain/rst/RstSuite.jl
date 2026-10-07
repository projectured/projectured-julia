"""
    test_rst_layering()

Static layered-architecture guard for `ProjecturedRST`.
"""
function test_rst_layering()
    main = get_package_source_root(ProjecturedRST)
    check_layering(main, pathof(ProjecturedRST);
                   name = "rst",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedRST; all = true)
                         if isdefined(ProjecturedRST, n) &&
                            getfield(ProjecturedRST, n) isa Module &&
                            getfield(ProjecturedRST, n) !== ProjecturedRST &&
                            parentmodule(getfield(ProjecturedRST, n)) !== ProjecturedRST))
end

"""
    test_rst()

Run this package's whole suite: the layering guard and every rst test.
"""
function test_rst()
    @testset "ProjecturedRST" begin
        test_rst_layering()
        test_rst_parser()
        test_rst_round_trip()
        test_rst_embed_card()
        test_rst_theme()
        test_rst_link_target()
    end
end

export test_rst, test_rst_layering, test_rst_parser
export test_rst_round_trip, test_rst_embed_card, test_rst_theme, test_rst_link_target
