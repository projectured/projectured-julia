"""
    test_help()

Run this package's whole suite: the layering guard, the description of a type,
the two lists and the page about the program.
"""
function test_help()
    @testset "ProjecturedPlatform" begin
        test_docstring_summary()
        test_help_list_to_syntax()
        test_about_page_to_syntax()
    end
end

export test_help, test_docstring_summary, test_help_list_to_syntax,
       test_about_page_to_syntax
