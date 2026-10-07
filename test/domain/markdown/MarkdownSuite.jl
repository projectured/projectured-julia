"""
    test_markdown_layering()

Static layered-architecture guard for `ProjecturedMarkdown`.
"""
function test_markdown_layering()
    main = get_package_source_root(ProjecturedMarkdown)
    check_layering(main, pathof(ProjecturedMarkdown);
                   name = "markdown",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedMarkdown; all = true)
                         if isdefined(ProjecturedMarkdown, n) &&
                            getfield(ProjecturedMarkdown, n) isa Module &&
                            getfield(ProjecturedMarkdown, n) !== ProjecturedMarkdown &&
                            parentmodule(getfield(ProjecturedMarkdown, n)) !== ProjecturedMarkdown))
end

"""
    test_markdown()

Run this package's whole suite: the layering guard and every markdown test.
"""
function test_markdown()
    @testset "ProjecturedMarkdown" begin
        test_markdown_layering()
        test_markdown_parser()
        test_markdown_page_wrap()
        test_markdown_embed_card()
        test_markdown_page_table()
        test_markdown_image_leaf()
        test_markdown_theme()
        test_markdown_link_target()
    end
end

export test_markdown_link_target
export test_markdown, test_markdown_layering, test_markdown_parser, test_markdown_page_wrap, test_markdown_embed_card,
       test_markdown_page_table, test_markdown_image_leaf, test_markdown_theme
