"""
    test_help()

Run this package's whole suite: the two lists and the page about the program.
The kernel tests the description of a type (`test_docstring_summary`).
"""
function test_help()
    @testset "ProjecturedPlatform" begin
        test_help_list_to_syntax()
        test_about_page_to_syntax()
    end
end

export test_help, test_help_list_to_syntax,
       test_about_page_to_syntax
