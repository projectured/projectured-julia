"""
    test_help()

Run this package's whole suite: the two trees and the page about the program.
The kernel tests the description of a type (`test_docstring_summary`).
"""
const test_help = TestSuite("ProjecturedPlatform", [
    test_help_tree,
    test_help_pages,
    test_about_page_to_syntax,
])

export test_help, test_help_tree, test_help_pages,
       test_about_page_to_syntax
