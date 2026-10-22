"""
    test_help()

Run this package's whole suite: the two trees and the page about the program.
The kernel tests the description of a type (`test_docstring_summary`).
"""
function test_help()
    @testset "ProjecturedPlatform" begin
        test_help_tree()
        test_help_pages()
        test_about_page_to_syntax()
    end
end

export test_help, test_help_tree, test_help_pages,
       test_about_page_to_syntax
